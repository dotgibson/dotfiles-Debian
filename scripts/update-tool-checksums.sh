#!/usr/bin/env bash
# scripts/update-tool-checksums.sh
# ──────────────────────────────────────────────────────────────────────────────
# Recompute the pinned SHA-256 of every release ASSET bootstrap.sh downloads, and
# write it back into install/tool-versions.env. Run this AFTER bumping a *_VERSION
# there: bootstrap.sh's verified_install checks each download against its *_SHA256
# and FAILS CLOSED on a mismatch — so a version bump is only complete once its
# checksum is refreshed.
#
# The consumer-side twin of core/scripts/update-tool-checksums.sh: same shape, same
# contract, same "review the diff before committing" discipline. It downloads the exact
# asset URL bootstrap.sh uses (Linux x86_64), hashes it, and rewrites the matching
# KEY= line in place.
#
# CROSS-CHECK before committing. This file is the trust anchor for everything bootstrap
# installs out of band, and hashing whatever the CDN served you only proves the download
# was self-consistent. Where upstream publishes a checksum sidecar, --verify fetches it
# and asserts the two agree.
#
#   scripts/update-tool-checksums.sh              # refresh the pins
#   scripts/update-tool-checksums.sh --verify     # refresh + assert vs upstream sidecars
#   scripts/update-tool-checksums.sh --check      # report drift only, write nothing
#   scripts/update-tool-checksums.sh --latest     # report newer upstream versions
#
# NOTE on --latest: GitHub's API is not used (it needs a token and rate-limits hard).
# The release tag is resolved from the redirect on /releases/latest/download/<anything>,
# which needs no auth and works from a bare container.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
cd -- "$REPO_ROOT" || exit 1
PINS="install/tool-versions.env"

if [[ -r core/lib/ux.sh ]]; then
  # shellcheck source=core/lib/ux.sh
  source core/lib/ux.sh
fi
say() { printf '%s::%s %s\n' "${UX_BLU:-}" "${UX_RST:-}" "$*"; }
ok() { printf '%s%s%s %s\n' "${UX_GRN:-}" "${UX_OK:-+}" "${UX_RST:-}" "$*"; }
bad() { printf '%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" "$*" >&2; }

VERIFY=0 CHECK=0 LATEST=0
for a in "$@"; do case "$a" in
  --verify) VERIFY=1 ;;
  --check) CHECK=1 ;;
  --latest) LATEST=1 ;;
  -h | --help)
    sed -n '2,28p' "$0"
    exit 0
    ;;
  *)
    bad "unknown flag: $a"
    exit 2
    ;;
esac; done

[[ -r "$PINS" ]] || { bad "$PINS not found"; exit 1; }
# shellcheck source=install/tool-versions.env
source "$PINS"

# name|github-repo|tag-prefix|asset-template   (${V} expands to the pinned version)
# Keep this table in step with the verified_install calls in bootstrap.sh.
#
# ALWAYS brace the expansion. `lazygit_$V_linux` is parsed as the variable
# `V_linux_x86_64` (underscore is an identifier character), which under `set -u` aborts
# and, without it, would silently build a URL with the version missing.
TOOLS=(
  "NVIM|neovim/neovim|v|nvim-linux-x86_64.tar.gz"
  "TREESITTER|tree-sitter/tree-sitter|v|tree-sitter-linux-x64.gz"
  "STARSHIP|starship/starship|v|starship-x86_64-unknown-linux-gnu.tar.gz"
  "LAZYGIT|jesseduffield/lazygit|v|lazygit_\${V}_linux_x86_64.tar.gz"
  "ATUIN|atuinsh/atuin|v|atuin-x86_64-unknown-linux-gnu.tar.gz"
  "MISE|jdx/mise|v|mise-v\${V}-linux-x64.tar.gz"
  "UV|astral-sh/uv||uv-x86_64-unknown-linux-gnu.tar.gz"
  "TY|astral-sh/ty||ty-x86_64-unknown-linux-gnu.tar.gz"
  "DUST|bootandy/dust|v|dust-v\${V}-x86_64-unknown-linux-gnu.tar.gz"
  "XH|ducaale/xh|v|xh-v\${V}-x86_64-unknown-linux-musl.tar.gz"
  "PROCS|dalance/procs|v|procs-v\${V}-x86_64-linux.zip"
  "DIFFT|Wilfred/difftastic||difft-x86_64-unknown-linux-gnu.tar.gz"
  "DELTA|dandavison/delta||delta-\${V}-x86_64-unknown-linux-gnu.tar.gz"
  "HEXYL|sharkdp/hexyl|v|hexyl-v\${V}-x86_64-unknown-linux-gnu.tar.gz"
)
# carapace is intentionally absent: it is a .deb whose integrity apt verifies on
# install, so tool-versions.env pins only its version and there is no hash to refresh.

# asset_url <repo> <tagprefix> <template> <version>
asset_url() {
  local repo="$1" pfx="$2" tmpl="$3" V="$4" asset
  asset="$(eval "printf '%s' \"$tmpl\"")"
  printf 'https://github.com/%s/releases/download/%s%s/%s' "$repo" "$pfx" "$V" "$asset"
}

# latest_tag <repo> — resolve the newest release tag WITHOUT the API, by reading the
# redirect GitHub issues for /releases/latest/download/<anything>. The probe asset need
# not exist: the redirect to the tagged path happens before the 404.
latest_tag() {
  local eff
  eff="$(curl -sL -o /dev/null -w '%{url_effective}' \
    "https://github.com/$1/releases/latest/download/__probe__" 2>/dev/null)"
  printf '%s' "$eff" | sed -n 's#.*/download/\([^/]*\)/.*#\1#p'
}

rc=0 changed=0
for entry in "${TOOLS[@]}"; do
  IFS='|' read -r key repo pfx tmpl <<<"$entry"
  ver="${key}_VERSION"; sha="${key}_SHA256"
  V="${!ver:-}"
  [[ -n "$V" ]] || { bad "$ver is empty in $PINS — skipping"; rc=1; continue; }

  if ((LATEST)); then
    tag="$(latest_tag "$repo")"
    up="${tag#v}"
    if [[ -n "$up" && "$up" != "$V" ]]; then
      printf '  %-12s pinned %-12s upstream %s\n' "$key" "$V" "$up"
    fi
    continue
  fi

  url="$(asset_url "$repo" "$pfx" "$tmpl" "$V")"
  tmp="$(mktemp -d)" || { rc=1; continue; }
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/asset" "$url"; then
    bad "$key: download failed — $url"
    rm -rf "$tmp"; rc=1; continue
  fi
  got="$(sha256sum "$tmp/asset" | cut -d' ' -f1)"
  rm -rf "$tmp"

  if ((VERIFY)); then
    # Only lazygit publishes a sidecar we can consume generically today; the loop is
    # written so adding more is a one-line change rather than a new code path.
    side=""
    [[ "$key" == LAZYGIT ]] && side="https://github.com/$repo/releases/download/${pfx}${V}/checksums.txt"
    if [[ -n "$side" ]]; then
      want="$(curl -fsSL "$side" 2>/dev/null | awk -v f="lazygit_${V}_linux_x86_64.tar.gz" '$2==f{print $1}')"
      if [[ -n "$want" && "$want" != "$got" ]]; then
        bad "$key: UPSTREAM SIDECAR DISAGREES (sidecar $want, download $got)"
        rc=1; continue
      fi
      [[ -n "$want" ]] && ok "$key: matches upstream sidecar"
    fi
  fi

  cur="${!sha:-}"
  if [[ "$cur" == "$got" ]]; then
    printf '  %-12s unchanged  %s\n' "$key" "$got"
    continue
  fi
  changed=1
  if ((CHECK)); then
    bad "$key: DRIFT — pinned $cur, actual $got"
    rc=1
  else
    # Rewrite in place. The KEY=VALUE format (no spaces, no quotes) is what makes a
    # single anchored sed correct here.
    sed -i "s|^${sha}=.*|${sha}=${got}|" "$PINS"
    ok "$key: $cur -> $got"
  fi
done

((LATEST)) && exit 0
if ((CHECK)); then
  ((rc == 0)) && ok "all pins match their assets."
  exit "$rc"
fi
((changed)) && say "review the diff before committing: git diff -- $PINS"
exit "$rc"
