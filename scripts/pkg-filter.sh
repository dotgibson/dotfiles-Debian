#!/usr/bin/env bash
# scripts/pkg-filter.sh — the distro tier for install/packages.txt.
# ──────────────────────────────────────────────────────────────────────────────
# SOURCE this; it defines one function and runs nothing.
#
# WHY THIS EXISTS. This repo targets three distros with incompatible archive ages:
# Ubuntu 24.04 froze in April 2024, Debian trixie is stable, and Kali is a rolling
# sid derivative. A package that noble cannot honestly supply — and that bootstrap.sh
# therefore fetches as a pinned, SHA-256-verified release asset — is frequently just
# in apt on Kali. Before Kali became a target, "what noble has" was a constant and the
# list could be flat. It is now a variable, and this is where it varies.
#
# WHY NOT A SECOND FILE. A sibling install/packages.kali.txt would drift: the shared
# 90% would be duplicated, and nothing would notice when one copy gained a package.
# One list with per-line annotations keeps every name in exactly one place.
#
# WHY NOT A SECOND PARSER. Core's blib_read_pkgs is what actually turns a line into a
# name for apt, and test/check-packages.sh deliberately reuses it so the check resolves
# EXACTLY what a real run would install. That property is worth keeping, so this filter
# sits IN FRONT of it and only decides which lines it gets to see. blib_read_pkgs takes
# a path, so callers compose the two with process substitution:
#
#     mapfile -t pkgs < <(blib_read_pkgs <(pkg_filter_lines "$list" "$OS_ID"))
#
# THE GRAMMAR, which lives inside the existing trailing comment so blib_read_pkgs is
# unaffected and an un-annotated file behaves exactly as it always did:
#
#     name                      # applies everywhere (the default)
#     name    # only:kali       # ONLY on these IDs
#     name    # skip:ubuntu     # everywhere EXCEPT these IDs
#     name    # only:kali,debian    (comma-separated, no spaces)
#
# IDs are matched against /etc/os-release ID — ubuntu, debian, kali. Both markers may
# appear on one line; `only:` is evaluated first and an ID excluded by it is dropped
# regardless of `skip:`. Annotations coexist with the `# min:X.Y.Z` floors and with
# ordinary prose in the same comment, in any order.
# ──────────────────────────────────────────────────────────────────────────────

# pkg_filter_lines <file> <os-id> — print the lines of <file> that apply to <os-id>,
# otherwise verbatim. Comments and blanks pass through untouched; stripping them is
# blib_read_pkgs's job, not this one. Anything that is not a readable REGULAR file
# prints nothing and returns 1, so a caller's `mapfile` sees an empty list rather than a
# silent partial one.
#
# -f AND -r, not -r alone: `-r` is TRUE for a directory, so an -r-only guard let a
# directory through to the read, which then failed with `read error: Is a directory`
# and — because the while loop exits normally on it — returned 0. That is the worst
# possible answer here: a caller would read it as "the list is legitimately empty".
pkg_filter_lines() {
  local file="$1" id="$2" line list
  [[ -f "$file" && -r "$file" ]] || return 1
  # `|| [[ -n "$line" ]]` so a final line with no trailing newline is not dropped.
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ \#[[:space:]]*only:([A-Za-z0-9_,-]+) ]]; then
      list=",${BASH_REMATCH[1]},"
      [[ "$list" == *",$id,"* ]] || continue
    fi
    if [[ "$line" =~ \#[[:space:]]*skip:([A-Za-z0-9_,-]+) ]]; then
      list=",${BASH_REMATCH[1]},"
      [[ "$list" == *",$id,"* ]] && continue
    fi
    printf '%s\n' "$line"
  done <"$file"
}
