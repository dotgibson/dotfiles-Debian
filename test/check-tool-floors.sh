#!/usr/bin/env bash
# test/check-tool-floors.sh
# ──────────────────────────────────────────────────────────────────────────────
# Does bootstrap.sh's presence guard still refuse an apt build that is BELOW the floor
# install/packages.txt declares — and still stand down for one that clears it?
#
# WHY A TEST AT ALL. Read the Makefile's `trap-guard` note: CI's bootstrap job only ever
# runs --links-only, so provision() — the whole out-of-band install path — is executed by
# no gate anywhere. That is how the version-blind guard shipped and stayed green while a
# real box ran neovim 0.9.5 against a config that needs 0.12. shellcheck cannot see it,
# `bash -n` cannot see it, and no lane exercises it. Hence this.
#
# It installs nothing, downloads nothing, and touches no real binary: the tools under
# test are one-line stub scripts in a temp dir, and PATH is pointed at that dir alone.
#
# The floors are read from the REAL install/packages.txt, on purpose — a fixture would
# pass while the manifest drifted, and drift in that file is precisely what the floors
# are a contract against.
#
# Exit codes:
#   0  every case behaved
#   1  environment failure (missing dpkg, unreadable manifest)
#   2  a case regressed — the guard is wrong
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 1

if [[ -r core/lib/ux.sh ]]; then
  # shellcheck source=core/lib/ux.sh
  source core/lib/ux.sh
fi
say() { printf '%s::%s %s\n' "${UX_BLU:-}" "${UX_RST:-}" "$*"; }
ok() { printf '%s%s%s %s\n' "${UX_GRN:-}" "${UX_OK:-+}" "${UX_RST:-}" "$*"; }
bad() { printf '%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" "$*" >&2; }

# Skip rather than fail off the family, the way test/check-packages.sh skips without
# apt-get: `make lint` should stay runnable from a non-Debian dev box.
command -v dpkg >/dev/null 2>&1 || {
  say "no dpkg on this host — skipping (the guard's comparator is Debian's)."
  exit 0
}

# The caller contract scripts/tool-floor.sh documents: it reports through these two, and
# deliberately provides no fallback. Stub them so a case can assert what was reported.
SHADOWED=()
note_shadow() { SHADOWED+=("$1"); }
blib_warn() { WARNED="$*"; }
WARNED=""
BLIB_SU="sudo"

# shellcheck source=scripts/tool-floor.sh
source scripts/tool-floor.sh

STUBS="$(mktemp -d)"
trap 'rm -rf "$STUBS"' EXIT

# stub <name> <what --version prints>  — a fake tool on PATH. `printf %s\n "$*"` rather
# than echo so a version banner containing a leading dash cannot be eaten as a flag.
stub() {
  local name="$1"; shift
  printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$(printf '%q' "$*")" >"$STUBS/$name"
  chmod +x "$STUBS/$name"
}

rc=0
case_n=0
# check <expect: current|stale|absent> <binary> <description>
#
# PREPEND the stub dir; do NOT replace PATH. have_current_tool shells out to awk, timeout
# and dpkg, and a bare PATH="$STUBS" hid all three — _tool_floor then read no floor at
# all and every case passed as "current" for entirely the wrong reason.
check() {
  local want="$1" bin="$2" desc="$3" got
  case_n=$((case_n + 1))
  SHADOWED=(); WARNED=""
  if PATH="$STUBS:$PATH" have_current_tool "$bin"; then got=current; else got=stale; fi
  if ! PATH="$STUBS:$PATH" command -v "$bin" >/dev/null 2>&1; then got=absent; fi
  if [[ "$got" == "$want" ]]; then
    printf '  %-46s %s\n' "$desc" "ok ($got)"
  else
    bad "$desc — expected $want, got $got"
    rc=2
  fi
}

say "floors read from install/packages.txt (unfiltered, by design)"
while read -r name want; do
  got="$(_tool_floor "$name")"
  if [[ "$got" == "$want" ]]; then
    printf '  %-46s %s\n' "$name" "min:$got"
  else
    bad "$name — expected floor $want, read '${got:-<none>}'"
    rc=2
  fi
done <<'FLOORS'
neovim 0.12.0
tree-sitter-cli 0.26.1
golang-go 1.22
FLOORS

# A floor must come from a DECLARATION, never from prose. packages.txt says "neovim is
# NOT here. noble ships 0.9.5" in a comment; a field-1 match that ignored comment lines
# would still be fooled by a name at the start of one, so both rules are asserted.
for name in starship lazygit atuin dust delta hexyl; do
  got="$(_tool_floor "$name")"
  [[ -z "$got" ]] || { bad "$name — expected NO floor, read min:$got"; rc=2; }
done
ok "no floor invented for the tools that declare none"

say "binary → package name (only the renames need listing)"
while read -r bin want; do
  got="$(_tool_floor_pkg "$bin")"
  [[ "$got" == "$want" ]] || { bad "$bin — expected $want, got $got"; rc=2; }
done <<'NAMES'
nvim neovim
tree-sitter tree-sitter-cli
delta git-delta
dust du-dust
starship starship
NAMES
ok "package names resolve"

say "the guard"
check absent no-such-tool-anywhere "absent entirely → install it"

stub nvim "NVIM v0.9.5"
check stale nvim "noble's 0.9.5, floor 0.12.0 → install the pin"
[[ "${SHADOWED[0]:-}" == *"below min:0.12.0"* && "${SHADOWED[0]:-}" == *"purge -y neovim"* ]] ||
  { bad "a stale tool must be reported with its purge command; got '${SHADOWED[0]:-<nothing>}'"; rc=2; }

stub nvim "NVIM v0.12.4"
check current nvim "the pinned 0.12.4 → stand down"
((${#SHADOWED[@]} == 0)) || { bad "a current tool must report nothing"; rc=2; }

# THE KALI CASE, and the one a regression here would break silently: apt supplied it,
# it clears the floor, so the pinned fetch must no-op. Not the pin (0.12.4) — the FLOOR.
stub nvim "NVIM v0.12.0"
check current nvim "kali: apt build exactly AT the floor → no-op"

stub tree-sitter "tree-sitter 0.20.8"
check stale tree-sitter "noble's 0.20.8, floor 0.26.1 → install the pin"
stub tree-sitter "tree-sitter 0.26.12"
check current tree-sitter "the pinned 0.26.12 → stand down"

# No `# min:` in the manifest → presence is the whole contract, exactly as before. This
# is what keeps `# skip:kali` delta/hexyl from re-downloading on every noble run.
stub delta "delta 0.16.5"
check current delta "no declared floor → presence alone is enough"

# An unreadable --version must not be treated as a breach. Acting on a version we could
# not parse would replace a perfectly good binary on a guess.
stub nvim "no version here"
check current nvim "unparseable --version → leave it alone"
[[ "$WARNED" == *"unreadable"* ]] || { bad "an unparseable --version must warn"; rc=2; }

# bootstrap.sh runs under `set -euo pipefail`, and this guard is called from inside it.
# Every case above ran in an if-condition, where errexit is suspended — so none of them
# could catch a helper that exits non-zero on a path bash would otherwise treat as fatal.
# This repo has already lost a full afternoon to exactly that class of bug (the leaked
# RETURN trap that aborted provision() at the instant it returned), so run the guard for
# real under those flags, in a subshell, and require it to survive.
#
# Re-stub so the four probes cover all four branches: below-floor (the one that reports),
# above-floor, no-floor-declared, and absent. The last case left nvim unparseable, which
# would have exercised only one of them.
stub nvim "NVIM v0.9.5"
say "errexit discipline (bootstrap.sh runs set -euo pipefail)"
for probe in nvim tree-sitter delta no-such-tool-anywhere; do
  case_n=$((case_n + 1))
  if out="$(PATH="$STUBS:$PATH" bash -euo pipefail -c '
        note_shadow() { :; }; blib_warn() { :; }; BLIB_SU=sudo
        source scripts/tool-floor.sh
        have_current_tool "$1" || true
        printf survived' _ "$probe" 2>&1)" && [[ "$out" == survived ]]; then
    printf '  %-46s %s\n' "$probe" "ok (no errexit abort)"
  else
    bad "$probe — the guard aborted under set -e: ${out:-<no output>}"
    rc=2
  fi
done

echo
if ((rc == 0)); then
  ok "$case_n guard cases behaved; floors and package names match the manifest."
  exit 0
fi
bad "the presence guard regressed — see above"
cat >&2 <<'EOF'

The two directions this gate protects, and they pull against each other:
  • too old must INSTALL   — else a frozen archive silently wins and bootstrap
                             still prints "complete" (the neovim 0.9.5 / winborder bug)
  • new enough must NO-OP  — else Kali fetches a pinned tarball that shadows its own
                             distro build, which is what `make apt-first` also guards
EOF
exit "$rc"
