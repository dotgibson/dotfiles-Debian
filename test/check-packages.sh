#!/usr/bin/env bash
# test/check-packages.sh
# ──────────────────────────────────────────────────────────────────────────────
# Does every package name in install/packages.txt still RESOLVE — and at a version
# Core can actually use — on this apt suite?
#
# bootstrap.sh's apt_install is deliberately forgiving: a bulk install that fails
# retries package-by-package and records "did not install" for each casualty. That
# resilience is right for a live box — one dead name should not sink the whole install
# — but it means a typo, a rename, or a dropped package is easy to miss. This turns
# that into a gate. It installs NOTHING.
#
# TWO CHECKS, and the second is the one this repo exists to make.
#
#   1. RESOLUTION — can apt install this name at all?
#      Uses `apt-get install --simulate`, NOT `apt-cache`. That matters:
#        • `apt-cache policy <unknown>` exits 0 and prints nothing — useless as a gate.
#        • `apt-cache show <virtual>` exits 100 even though the package IS installable
#          — a false "missing".
#      `apt-get install -s` runs apt's real resolver, so it agrees with what
#      `apt-get install` would actually do: single-provider virtuals resolve, ambiguous
#      ones error, unsatisfiable dependencies error. It is the true analogue of
#      Fedora's `repoquery` + `--whatprovides` pair, collapsed into one correct command.
#
#   2. VERSION FLOORS — is the candidate NEW ENOUGH?
#      Resolution alone is not sufficient on a frozen archive, and that is the whole
#      story of this repo. Ubuntu 24.04 resolves `neovim` (0.9.5) and `tree-sitter-cli`
#      (0.20.8) perfectly happily; both are far below what Core needs, and a
#      resolution-only gate would have called that box healthy. Floors are declared in
#      install/packages.txt as `# min:X.Y.Z` trailing comments and compared with
#      `dpkg --compare-versions` — the ONLY correct comparator for Debian versions,
#      which carry epochs (`2:1.22`) and suffixes (`+dfsg`, `ubuntu0.1`) that sort
#      wrongly under `sort -V`.
#
# RUN IT WHERE THE ANSWER IS TRUE. Availability is a property of the apt sources on the
# box, so noble and trixie disagree by design. The authoritative run is the workflow
# (.github/workflows/packages.yml) in a pinned container; locally this is a smoke test
# against whatever you track, which is why the suite in view is printed.
#
# Exit codes:
#   0  every name resolved and cleared its floor (or a clean skip: no apt here)
#   1  usage/environment failure
#   2  one or more names failed — the drift signal
#
# Usage:
#   test/check-packages.sh                      # install/packages.txt
#   test/check-packages.sh install/packages.txt
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
# `set -e` is deliberately off here (the exit code IS the result), so guard the cd
# explicitly — continuing in the wrong directory would read the wrong manifest.
cd -- "$REPO_ROOT" || exit 1

if [[ -r core/lib/ux.sh ]]; then
  # shellcheck source=core/lib/ux.sh
  source core/lib/ux.sh
fi
say() { printf '%s::%s %s\n' "${UX_BLU:-}" "${UX_RST:-}" "$*"; }
ok() { printf '%s%s%s %s\n' "${UX_GRN:-}" "${UX_OK:-+}" "${UX_RST:-}" "$*"; }
bad() { printf '%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" "$*" >&2; }

command -v apt-get >/dev/null 2>&1 || {
  say "no apt-get on this host — skipping (run the packages workflow instead)."
  exit 0
}

manifest="${1:-install/packages.txt}"
[[ -f "$manifest" ]] || { bad "manifest not found: $manifest"; exit 1; }

# Reuse Core's parser rather than re-implementing the comment/whitespace rules: it is
# the SAME function bootstrap.sh feeds apt, so this checks exactly the names that would
# really be installed, including inline-comment stripping.
if [[ -r core/lib/bootstrap-lib.sh ]]; then
  # shellcheck source=core/lib/bootstrap-lib.sh
  source core/lib/bootstrap-lib.sh
else
  bad "core/lib/bootstrap-lib.sh not found — is the core/ subtree vendored?"
  exit 1
fi

# Name the suite so a local run's answer is interpretable. `apt-cache policy`'s FIRST
# release line is the dpkg status pseudo-release (a=now), which is not a suite — skip it
# and take the first real archive.
suite="$(apt-cache policy 2>/dev/null |
  sed -n 's/.*[[:space:],]a=\([^,]*\).*/\1/p' | grep -v '^now$' | head -1)"
say "apt suite in view: ${suite:-unknown}"

# The distro tier, applied BEFORE Core's parser — otherwise this would resolve names the
# target it runs on would never be asked to install (a kali-only package checked on noble
# is a guaranteed, meaningless red). OS_ID comes from the box the check runs on, which in
# CI is the matrix container.
# shellcheck source=scripts/pkg-filter.sh
source "$(dirname "$0")/../scripts/pkg-filter.sh"
CHECK_OS_ID="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | head -1 | tr -d "\"'\''")"
say "distro tier: ${CHECK_OS_ID:-unknown}"
mapfile -t pkgs < <(blib_read_pkgs <(pkg_filter_lines "$manifest" "$CHECK_OS_ID"))
((${#pkgs[@]})) || { bad "$manifest parsed to zero package names"; exit 1; }
say "$manifest — ${#pkgs[@]} names"

# apt needs an index to resolve against; a bare container has none.
if [[ -z "$(ls -A /var/lib/apt/lists 2>/dev/null)" ]]; then
  say "apt lists are empty — running apt-get update first"
  apt-get update -qq >/dev/null 2>&1 || bad "apt-get update failed; results may be wrong"
fi

sim() { apt-get install --simulate --no-install-recommends "$@" 2>&1; }

# ── 1. resolution ─────────────────────────────────────────────────────────────
# Bulk first, then per-name — the same bulk-then-retry shape as bootstrap.sh's
# apt_install, and for the same reason. The bulk pass proves something no per-name
# probe can: that the whole set is CO-INSTALLABLE (no two names conflict).
missing=()
if sim "${pkgs[@]}" >/dev/null 2>&1; then
  ok "all ${#pkgs[@]} names resolve, and the set is co-installable."
else
  bad "the bulk resolve failed — narrowing down per package"
  for p in "${pkgs[@]}"; do
    # Capture output and status in separate statements: `out=$(...)` does set $? to the
    # command's status, but that is easy to break with any later edit that inserts a
    # statement between the two. Test the call directly instead.
    if out="$(sim "$p")"; then continue; fi
    case "$out" in
    *"Unable to locate package"*) missing+=("$p — absent from ${suite:-this suite}") ;;
    *"is a virtual package provided by"*) missing+=("$p — ambiguous virtual; name a concrete provider") ;;
    *"has no installation candidate"*) missing+=("$p — indexed but not installable here") ;;
    *) missing+=("$p — $(printf '%s' "$out" | grep -iE '^E:' | head -1)") ;;
    esac
  done
fi

# ── 2. version floors ─────────────────────────────────────────────────────────
# Floors live in the manifest's trailing comments (`name  # min:X.Y.Z`) so the file
# stays human-first and there is no second list to drift. Read them straight from the
# source rather than through blib_read_pkgs, which strips comments by design — but
# through pkg_filter_lines, which does not.
#
# The tier matters MORE here than in the resolve pass above, because the failure is
# louder: a kali-only floor evaluated on noble does not merely fail to resolve, it
# resolves to the WRONG PACKAGE and reports a real-looking breach. `neovim min:0.12.0`
# on noble finds 0.9.5 and calls it BELOW the floor — which is true, and is precisely
# why noble installs the pinned tarball instead. Unfiltered, that reds the lane it is
# supposed to certify.
below=()
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" == *"min:"* ]] || continue
  name="${line%%#*}"; name="${name//[[:space:]]/}"
  [[ -n "$name" ]] || continue
  floor="$(printf '%s' "$line" | sed -n 's/.*min:\([0-9][0-9A-Za-z.:+~-]*\).*/\1/p')"
  [[ -n "$floor" ]] || continue
  cand="$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/{print $2}')"
  if [[ -z "$cand" || "$cand" == "(none)" ]]; then
    below+=("$name — no candidate, cannot check floor min:$floor")
    continue
  fi
  if dpkg --compare-versions "$cand" ge "$floor"; then
    printf '  %-24s %s (floor %s) ok\n' "$name" "$cand" "$floor"
  else
    below+=("$name — candidate $cand is BELOW the required min:$floor")
  fi
done < <(pkg_filter_lines "$manifest" "$CHECK_OS_ID")

echo
rc=0
if ((${#missing[@]})); then
  bad "${#missing[@]} package name(s) did NOT resolve against ${suite:-this suite}:"
  printf '    %s\n' "${missing[@]}" >&2
  rc=2
fi
if ((${#below[@]})); then
  bad "${#below[@]} package(s) are below their declared version floor:"
  printf '    %s\n' "${below[@]}" >&2
  rc=2
fi

if ((rc == 0)); then
  ok "all ${#pkgs[@]} names resolve and every declared floor is met on ${suite:-this suite}."
  exit 0
fi

cat >&2 <<'EOF'

A non-resolving name is one of:
  • a rename       — find the new name and update install/packages.txt
  • a drop         — remove it, or move it to bootstrap.sh as a verified_install
  • a typo         — fix it
  • suite drift    — real on one release, absent on another

A name below its floor means apt CAN install it but Core cannot use it. Move it out of
install/packages.txt and into bootstrap.sh as a pinned verified_install, the way neovim
and tree-sitter-cli already are — do not just delete the floor.
EOF
exit "$rc"
