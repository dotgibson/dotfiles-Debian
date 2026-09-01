#!/usr/bin/env bash
# scripts/tool-floor.sh — the version floor behind bootstrap.sh's presence guard.
# ──────────────────────────────────────────────────────────────────────────────
# SOURCE this; it defines four functions and runs nothing.
#
# WHY THIS EXISTS. Every out-of-band install in bootstrap.sh is guarded by "is this
# binary already on PATH?", and that guard is the ENTIRE mechanism behind
# install/packages.txt's `# only:kali` tier: Kali's archive tracks sid and simply HAS
# neovim/starship/lazygit, so apt lands them minutes earlier in the same provision() and
# the pinned fetch no-ops. No distro conditional is needed there and none should be added.
#
# But presence was never the contract — VERSION is. A bare `command -v` cannot tell a
# sid-fresh neovim 0.12.4 from noble's 0.9.5, and on this family that difference is the
# entire reason the repo exists. The failure was silent and total: an apt `neovim` 0.9.5
# — hand-installed, or left over from before the tier existed — answered the guard, the
# pinned 0.12.4 was never downloaded, ~/.local/opt was never created, and bootstrap
# printed "complete" over a box whose editor died at startup on `winborder`. That
# happened, on the maintainer's own machine, and nothing in the run said so.
#
# So the guard asks the second question too, against the floors install/packages.txt
# already declares as `# min:X.Y.Z`. Three properties worth keeping straight:
#
#   • A floor is consulted ONLY where one is declared. Every tool without a `# min:`
#     behaves exactly as it did — present means skip. That is deliberate, not an
#     oversight: `git-delta` and `hexyl` are `# skip:kali` and depend on it, and
#     comparing against tool-versions.env's PIN instead would re-download on noble
#     forever, because apt's build always trails the pin by a little.
#
#   • The floor is read UNFILTERED — pkg_filter_lines is NOT applied. That is the exact
#     inverse of test/check-packages.sh, and both are right. A floor states what CORE
#     needs, not what an archive has, so it holds on all three targets; the tier only
#     decides who installs the name from apt. `neovim min:0.12.0` sits on an
#     `# only:kali` line and must still be legible HERE, on ubuntu, where it is the
#     reason the tarball gets fetched at all. This is the second consumer of the rule
#     that a tiered line must repeat its floor — filtering here would restore the bug.
#
#   • dpkg --compare-versions, never `sort -V` — the same call and the same reason as
#     test/check-packages.sh: Debian versions carry epochs (`2:1.22`) and suffixes
#     (`+dfsg`, `ubuntu0.1`) that sort wrongly under anything else.
#
# CALLER CONTRACT. have_current_tool reports through `note_shadow` and `blib_warn`.
# bootstrap.sh defines both; test/check-tool-floors.sh stubs them. There is no fallback
# on purpose — a caller that cannot report a shadowed tool is the exact silence this
# file exists to end, and it should fail loudly rather than guard quietly.
# ──────────────────────────────────────────────────────────────────────────────

# The manifest is the single source of floor VALUES. Overridable so the test can point at
# a fixture; defaulted from this script's own location so a caller need not set it.
: "${TOOL_MANIFEST:=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/install/packages.txt}"

# _tool_floor_pkg <binary> — the install/packages.txt NAME that would carry <binary>'s
# floor. Only the renames need listing; everything else is its own package name, so a
# floor added to the manifest later is honoured here with no second edit.
_tool_floor_pkg() {
  case "$1" in
  nvim) printf '%s\n' neovim ;;
  tree-sitter) printf '%s\n' tree-sitter-cli ;;
  delta) printf '%s\n' git-delta ;;
  dust) printf '%s\n' du-dust ;;
  *) printf '%s\n' "$1" ;;
  esac
}

# _tool_floor <package> — the `# min:X.Y.Z` floor declared for <package>, or nothing.
# Anchored on FIELD 1, and comment lines are skipped outright: packages.txt discusses
# `neovim` in prose several times ("neovim is NOT here", the tier rationale) before the
# real entry, and a looser match would read a floor out of an explanation.
_tool_floor() {
  [[ -r "$TOOL_MANIFEST" ]] || return 0
  awk -v p="$1" '
    /^[[:space:]]*#/ { next }
    $1 == p { for (i = 2; i <= NF; i++) if ($i ~ /^min:/) { sub(/^min:/, "", $i); print $i; exit } }
  ' "$TOOL_MANIFEST"
}

# _tool_version <binary> — what <binary> reports, reduced to bare digits-and-dots.
# A deliberately dumb heuristic (first dotted number on the first line of --version).
# It is consulted ONLY for tools that declare a floor, so it has to be right for those
# and for nothing else: `nvim --version` opens "NVIM v0.12.4", `tree-sitter --version`
# says "tree-sitter 0.26.12". A future tool whose output defeats this earns a case arm,
# not a cleverer regex. Empty output means "could not tell", which have_current_tool
# treats as leave-it-alone — a guard must never act on confidence it does not have.
#
# `timeout` because this runs an arbitrary binary off PATH, and `</dev/null` because one
# that decides to prompt would otherwise hang a bootstrap nobody is watching.
#
# NO PIPELINE, deliberately. The obvious spelling — `"$(… | head -1)" || out=""` — is
# broken in a way that only shows on big output: head exits after the first line, the
# tool is still writing, it takes SIGPIPE, and `set -o pipefail` (bootstrap.sh runs
# `set -euo pipefail`) turns that into a non-zero substitution. The `||` fallback then
# throws away a first line that had already been read perfectly. Measured: a banner
# under the 64K pipe buffer never trips it, one over it trips 20 times out of 20 — and
# the result is an empty version, read as "unreadable", read as "stand down", which
# silently skips a pinned install. That is the exact class of silence this file exists
# to end, so the whole shape is gone: capture everything, slice in the shell, and match
# with bash's own regex engine. `|| true` on the capture keeps a tool that prints its
# version and then exits non-zero.
_tool_version() {
  local out="" re='[0-9]+(\.[0-9]+)+'
  out="$(timeout 5 "$1" --version 2>/dev/null </dev/null)" || true
  out="${out%%$'\n'*}"
  [[ "$out" =~ $re ]] && printf '%s\n' "${BASH_REMATCH[0]}"
  # Explicit: the [[ ]] above is the last command, and a non-match returns 1 — which
  # `have="$(_tool_version …)"` would take as fatal under set -e.
  return 0
}

# have_current_tool <binary> — 0 when <binary> is already on PATH AND new enough that the
# out-of-band install should stand down. THE one guard: verified_install,
# verified_tree_install, the go installs and --dry-run all route through it, so there is
# no second copy to drift out of step with this one.
have_current_tool() {
  local bin="$1" pkg floor have where
  command -v "$bin" >/dev/null 2>&1 || return 1

  pkg="$(_tool_floor_pkg "$bin")"
  floor="$(_tool_floor "$pkg")"
  [[ -n "$floor" ]] || return 0

  have="$(_tool_version "$bin")"
  if [[ -z "$have" ]]; then
    blib_warn "$bin: on PATH but --version was unreadable; assuming it clears min:$floor"
    return 0
  fi
  # New enough. This is the Kali path, and it must stay a pure no-op.
  dpkg --compare-versions "$have" ge "$floor" 2>/dev/null && return 0

  where="$(command -v "$bin")"
  note_shadow "$bin: $where is $have, below min:$floor — ${BLIB_SU:+$BLIB_SU }apt-get purge -y $pkg"
  return 1
}
