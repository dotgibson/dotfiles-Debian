#!/usr/bin/env bash
# dotfiles-Debian/bootstrap.sh
# ──────────────────────────────────────────────────────────────────────────────
# Provision a Debian-family box (targets Ubuntu 24.04 LTS) and wire up dotfiles.
# Idempotent — safe to re-run. This is the OS-NATIVE layer; Core (zsh/tmux/nvim/git)
# is vendored under core/ and symlinked in via the shared core/lib/bootstrap-lib.sh.
#
# WHY THIS REPO CARRIES SO MANY OUT-OF-BAND INSTALLS
#   Every other Linux repo in the fleet targets a rolling or near-rolling distro.
#   Ubuntu 24.04 froze in April 2024, so a large slice of the modern-CLI stack is
#   either absent from `noble` or too old to satisfy Core — most sharply neovim
#   (noble has 0.9.5; core/nvim's pinned nvim-treesitter main branch hard-requires
#   0.12) and tree-sitter-cli (noble has 0.20.8; the floor is 0.26.1). That is a
#   property of the release date, not of the design. install/packages.txt carries
#   only what apt can actually satisfy; everything else arrives here as a pinned,
#   SHA-256-verified release asset. See install/tool-versions.env.
#
# Run `./bootstrap.sh --help` for the flag list (usage() below is the one definition —
# do NOT re-add a `sed -n 'N,Mp' "$0"` help, which silently drifts when this header moves;
# core/scripts/sync-core.sh documents that exact trap).
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LINKS_ONLY=0
DO_UPGRADE=1
DO_UNATTENDED=1
STRICT=0
FORCE_OS=0
# --only/--skip are validated by the shared lib (blib_select), which is sourced
# AFTER this loop — so capture the raw values now and apply them below.
ONLY_RAW="" SKIP_RAW="" ONLY_SEEN=0 SKIP_SEEN=0

# usage() is a real heredoc, NOT `sed -n '2,17p' "$0"`. The old form was coupled to this
# file's header line numbers, so editing the banner above silently drifted `--help` — the
# trap core/scripts/sync-core.sh calls out by name. This stays correct however the header moves.
usage() {
  cat <<'EOF'
bootstrap.sh — provision a Debian-family box (Ubuntu 24.04 LTS) and wire up dotfiles.
Idempotent: safe to re-run.

  ./bootstrap.sh                  full: apt packages + pinned extras + symlinks
  ./bootstrap.sh --links-only     just (re)create symlinks (no apt, no downloads)
  ./bootstrap.sh --dry-run        preview EVERYTHING; change nothing
  ./bootstrap.sh --no-upgrade     apt update, but skip the full-upgrade
  ./bootstrap.sh --no-unattended  don't configure unattended-upgrades
  ./bootstrap.sh --only zsh,nvim  link ONLY these Core module groups
  ./bootstrap.sh --skip tmux      link everything EXCEPT these groups
  ./bootstrap.sh --strict         exit non-zero if any best-effort step failed
  ./bootstrap.sh --force-os       run on a Debian-LIKE distro (Mint, Pop!_OS, Raspbian)
  ./bootstrap.sh -h, --help       show this help and exit

Module groups (for --only/--skip): zsh nvim tmux git prompt tools — they affect the
wiring steps only, never package provisioning; combine with --links-only to re-wire a
subset of configs without touching apt.

Env:
  BLIB_SU   privilege escalator; auto-resolved (empty as root, else sudo, else doas).
            Set explicitly to override, e.g. BLIB_SU=doas or BLIB_SU= to run as root.
EOF
}

while [[ $# -gt 0 ]]; do case "$1" in
  --links-only) LINKS_ONLY=1 ;;
  --no-upgrade) DO_UPGRADE=0 ;;
  --no-unattended) DO_UNATTENDED=0 ;;
  --dry-run | -n) BLIB_DRY=1 ;;
  --strict) STRICT=1 ;;
  --force-os) FORCE_OS=1 ;;
  --only) [[ $# -ge 2 ]] || { echo "--only requires module names, e.g. --only zsh,nvim" >&2; exit 1; }; ONLY_RAW="$2"; ONLY_SEEN=1; shift ;;
  --only=*) ONLY_RAW="${1#*=}"; ONLY_SEEN=1 ;;
  --skip) [[ $# -ge 2 ]] || { echo "--skip requires module names, e.g. --skip tmux" >&2; exit 1; }; SKIP_RAW="$2"; SKIP_SEEN=1; shift ;;
  --skip=*) SKIP_RAW="${1#*=}"; SKIP_SEEN=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown arg: $1" >&2
    usage >&2
    exit 1
    ;;
  esac; shift; done
# BLIB_DRY is read by the shared lib's mutating helpers via ${BLIB_DRY:-0} at CALL time,
# so setting it here (before the lib is sourced) is enough. Default it so `set -u` is safe.
: "${BLIB_DRY:=0}"

# ── core/ subtree present? (inline: can't source a lib out of core/ before this) ─
# Validate the SPECIFIC paths we depend on (zsh modules + the two libs sourced
# next) so a missing/partial subtree fails HERE with a precise message, not later
# with a cryptic `source: No such file`.
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  if [[ ! -e "$DOTFILES/$_req" ]]; then
    echo "core/ subtree missing or incomplete (need $_req). One-time, run:" >&2
    echo "  git subtree add  --prefix=core <dotfiles-core remote> main --squash   # first time" >&2
    echo "  git subtree pull --prefix=core <dotfiles-core remote> main --squash   # to update" >&2
    exit 1
  fi
done
unset _req

# Shared bash UX palette + provisioning scaffold (vendored under core/lib).
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"
# The distro tier for install/packages.txt (ubuntu / debian / kali). Sits in FRONT of
# Core's blib_read_pkgs rather than replacing it — see scripts/pkg-filter.sh's header.
# shellcheck source=scripts/pkg-filter.sh
source "$DOTFILES/scripts/pkg-filter.sh"

# Apply any --only/--skip module selection now the validator (blib_select) exists;
# it aborts on a malformed selector or an unknown group.
if ((ONLY_SEEN)); then blib_select --only "$ONLY_RAW"; fi
if ((SKIP_SEEN)); then blib_select --skip "$SKIP_RAW"; fi

# ── deferred failures ─────────────────────────────────────────────────────────
# Many steps below are deliberately best-effort (`|| true` / a warning): a rate-limited
# GitHub API or a vendor repo that is down must not strand the rest of a fresh box. But a
# script that then prints "complete" and exits 0 regardless means a machine missing half
# its tools reports success. Record each miss and report them together at the end (and
# exit non-zero under --strict).
FAILED_STEPS=()
note_fail() {
  FAILED_STEPS+=("$1")
  blib_warn "$1"
}

# ── sanity: confirm we're on a Debian-family box ──────────────────────────────
# Parse the ID= / ID_LIKE= KEYS rather than grepping the whole file for "debian": a bare
# `grep -qi debian /etc/os-release` matches any incidental substring (a HOME_URL, a
# PRETTY_NAME) and would sail a wholly unrelated distro past the guard.
#
# ubuntu, debian and kali are ALL first-class here — the repo is named for the family, and
# CI proves ubuntu:24.04 (the LTS target), debian:trixie (so an Ubuntu-only assumption or a
# PPA reds a PR), and kalilinux/kali-rolling. Kali joined when dotfiles-Offense shed its
# OS-native half to become a pure Role layer: the offensive repo now stacks ON this one
# rather than carrying a duplicate apt layer of its own.
#
# Kali is the reason install/packages.txt is distro-tiered. It is a rolling sid derivative
# while noble froze in April 2024, so a package this repo must fetch out-of-band on Ubuntu
# is frequently just in apt on Kali — see the `# only:` / `# skip:` annotations there and
# the apt-first checks around verified_install below.
#
# OTHER derivatives (Mint, Pop!_OS, Raspbian) still report ID_LIKE=debian and still need
# --force-os: they are legitimate but DELIBERATELY untested, because their package sets and
# release cadence differ from the three we actually prove in CI.
_osr_field() { # <KEY> — the unquoted value of KEY in /etc/os-release ("" when absent)
  [[ -r /etc/os-release ]] || return 0
  sed -n "s/^$1=//p" /etc/os-release | head -1 | tr -d '"'"'"
}
OS_ID="$(_osr_field ID)"
OS_ID_LIKE="$(_osr_field ID_LIKE)"
if [[ "$OS_ID" != ubuntu && "$OS_ID" != debian && "$OS_ID" != kali ]]; then
  if [[ " $OS_ID_LIKE " == *" debian "* ]]; then
    if ((FORCE_OS)); then
      blib_warn "ID=$OS_ID is only debian-LIKE — continuing under --force-os; package names may differ"
    else
      echo "This bootstrap targets Ubuntu (ID=ubuntu), Debian (ID=debian) or Kali (ID=kali); this box reports ID=$OS_ID (ID_LIKE=$OS_ID_LIKE)." >&2
      echo "Package availability differs there. Re-run with --force-os to proceed anyway." >&2
      exit 1
    fi
  else
    echo "This bootstrap targets Debian-family distros. /etc/os-release reports ID=${OS_ID:-<none>}." >&2
    exit 1
  fi
fi

# ── privilege escalation ──────────────────────────────────────────────────────
# Resolve the escalator ONCE, the way the shared lib expects (it reads $BLIB_SU, defaulting
# to `sudo` only when the var is UNSET — so an explicit empty value means "run directly").
#
# Deliberately NOT a hardcoded `sudo` (which is what dotfiles-Offense did before it shed
# its OS-native half to this repo): there is no sudo
# to call inside an `ubuntu:24.04` container, which is exactly where the reusable CI
# bootstrap test runs. Resolving here keeps our escalations in step with the lib's own
# (blib_set_login_shell).
if [[ -z "${BLIB_SU+x}" ]]; then
  # STRING compare, and tolerate `id` itself being unavailable. `[[ "$(id -u)" -eq 0 ]]` is
  # an ARITHMETIC comparison, and bash evaluates an empty string there as 0 — so on a box
  # where `id` is missing or off PATH that concluded "we are root" and then ran every
  # privileged command unescalated. Fail closed to "not root": the worst case is a
  # needless sudo.
  _uid="$(id -u 2>/dev/null || true)"
  if [[ "$_uid" == "0" ]]; then
    BLIB_SU=""
  elif command -v sudo >/dev/null 2>&1; then
    BLIB_SU="sudo"
  elif command -v doas >/dev/null 2>&1; then
    BLIB_SU="doas"
  else
    BLIB_SU=""
    ((LINKS_ONLY)) || {
      echo "Not root and neither sudo nor doas is installed — cannot install packages." >&2
      echo "Re-run as root, install sudo, or use --links-only (which needs no privileges)." >&2
      exit 1
    }
  fi
fi
export BLIB_SU
# priv <cmd...> — run CMD under the resolved escalator, or directly when we are already
# root. Never invokes an empty-string command (which would be a "" not found error).
priv() {
  if [[ -n "$BLIB_SU" ]]; then "$BLIB_SU" "$@"; else "$@"; fi
}

# ── apt invocation policy ─────────────────────────────────────────────────────
# Two env vars and one option that together make apt safe to run UNATTENDED over SSH.
# All three are load-bearing on Ubuntu Server specifically; skip any of them and an
# unwatched bootstrap can hang or die.
#
#   DEBIAN_FRONTEND=noninteractive
#     Suppresses debconf's own prompts (the classic one).
#
#   NEEDRESTART_MODE=a
#     Ubuntu Server 24.04 PREINSTALLS `needrestart`, which interposes on apt and asks —
#     on a full-screen curses dialog — which services to restart. DEBIAN_FRONTEND does
#     NOT suppress it: it is a separate apt hook with its own frontend. On a headless
#     box reached only by ssh that is an invisible prompt on a run nobody is watching,
#     i.e. an indefinite hang. `a` = restart automatically without asking. This is the
#     single biggest difference between provisioning Ubuntu Server and provisioning
#     Kali/Debian, and it is why this repo cannot just reuse Kali's apt block.
#
#   -o DPkg::Lock::Timeout=600
#     unattended-upgrades (enabled by default on Ubuntu) holds the dpkg lock, so a
#     bootstrap that starts inside its window otherwise dies INSTANTLY on
#     /var/lib/dpkg/lock-frontend. Wait for it instead of failing.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
APT_OPTS=(-o DPkg::Lock::Timeout=600)

apt_get() { priv apt-get "${APT_OPTS[@]}" "$@"; }

# apt_install — resilient: bulk first, then per-package.
# apt aborts the WHOLE transaction on a single unresolvable name, so one dropped or
# renamed package would otherwise cost the entire install. That matters more here than
# anywhere else in the fleet: a frozen archive is exactly where names go missing.
apt_install() {
  local -a pkgs=("$@")
  ((${#pkgs[@]})) || return 0
  if apt_get install -y --no-install-recommends "${pkgs[@]}"; then return 0; fi
  blib_say "bulk install hit a snag — retrying package-by-package"
  local p
  for p in "${pkgs[@]}"; do
    # Keep --no-install-recommends on the retry too: without it the fallback path
    # quietly pulls a much larger dependency set than the bulk path would have,
    # so WHICH path ran changed what ended up on the box.
    apt_get install -y --no-install-recommends "$p" ||
      note_fail "apt: $p did not install (unavailable on this release?)"
  done
}

# ── preflight: the commands this script assumes ───────────────────────────────
# Fail HERE with the whole list, instead of dying halfway through provisioning with a
# cryptic error from whichever one happened to be reached first.
preflight_cmds() {
  local -a need=() missing=()
  # --links-only has NO hard requirements: wiring is pure shell plus coreutils. Notably it
  # must not demand git — the reusable CI test provisions only `bash zsh` and pre-seeds the
  # tpm dir precisely so the wiring path stays offline and deterministic.
  ((LINKS_ONLY)) || need=(apt-get dpkg curl sed awk tar)
  local c
  for c in "${need[@]}"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if ((${#missing[@]})); then
    echo "Missing required command(s): ${missing[*]}" >&2
    echo "On Debian/Ubuntu: ${BLIB_SU:+$BLIB_SU }apt-get install -y ${missing[*]}" >&2
    exit 1
  fi
  # git is a SOFT requirement, and only for the one-time tpm clone in blib_link_core —
  # which already degrades gracefully on failure. On a full run apt installs git from
  # install/packages.txt anyway, well before the wiring step. So warn, never abort.
  if ! command -v git >/dev/null 2>&1 && [[ ! -d "$CONFIG/tmux/plugins/tpm" ]]; then
    blib_warn "git is not installed — the one-time tpm clone will be skipped; install git, then re-run with --links-only (or clone tpm by hand and press prefix + I)"
  fi
}
preflight_cmds

# ── keep the sudo timestamp warm for the whole run ────────────────────────────
# Several steps below sit AFTER downloads that take minutes — comfortably longer than
# sudo's 5-minute timestamp. sudo writes its PROMPT to stderr and reads the password from
# the TTY, so a later call can stop the run dead at an INVISIBLE prompt: no output, no
# progress, indistinguishable from a hang.
#
# Prime the timestamp ONCE up front, with the prompt visible, then refresh it in the
# background so no later call can ever block. Only meaningful for sudo: doas has no
# refreshable timestamp API, and as root there is nothing to prime.
SUDO_KEEPALIVE_PID=""
sudo_keepalive_start() {
  [[ "$BLIB_SU" == sudo ]] || return 0
  blib_say "priming sudo (asks once; the timestamp is kept warm for the whole run)"
  sudo -v || {
    echo "sudo authentication failed — cannot provision packages." >&2
    exit 1
  }
  # kill -0 "$$" stops the refresher when this script exits even if the trap is missed
  # (e.g. SIGKILL), so it can never outlive the bootstrap as an orphan.
  while true; do
    sudo -n true 2>/dev/null || true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit 0
  done &
  SUDO_KEEPALIVE_PID=$!
  # shellcheck disable=SC2064  # expand the PID NOW: the var is reset below on stop
  trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null || true" EXIT
}
sudo_keepalive_stop() {
  [[ -n "$SUDO_KEEPALIVE_PID" ]] || return 0
  kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  SUDO_KEEPALIVE_PID=""
  trap - EXIT
}

# ── pinned + verified installs ────────────────────────────────────────────────
# The tools apt cannot supply arrive as VERIFIED release assets, never `curl … | sh`.
# install/tool-versions.env pins each one's version AND the SHA-256 of its asset; the
# helpers below fetch that exact asset, verify it, and unpack it. Nothing is piped into
# a shell. See that file's header for the rationale.
#
# OUT_OF_BAND_TOOLS is also what --dry-run reports, so keep it in step with the calls
# in provision().
OUT_OF_BAND_TOOLS=(
  nvim tree-sitter starship lazygit atuin mise uv ty
  dust xh procs yq difft glow gum doggo sesh carapace op
  delta hexyl
)
TOOL_PINS="$DOTFILES/install/tool-versions.env"
if [[ -r "$TOOL_PINS" ]]; then
  # shellcheck source=install/tool-versions.env
  source "$TOOL_PINS"
else
  blib_warn "$TOOL_PINS missing — the pinned tool installs will be skipped"
fi
# Default every pin to empty so a missing/partial pin file degrades to "skip this
# tool" rather than tripping `set -u` and aborting the whole bootstrap.
: "${NVIM_VERSION:=}" "${NVIM_SHA256:=}"
: "${TREESITTER_VERSION:=}" "${TREESITTER_SHA256:=}"
: "${STARSHIP_VERSION:=}" "${STARSHIP_SHA256:=}"
: "${LAZYGIT_VERSION:=}" "${LAZYGIT_SHA256:=}"
: "${ATUIN_VERSION:=}" "${ATUIN_SHA256:=}"
: "${MISE_VERSION:=}" "${MISE_SHA256:=}"
: "${UV_VERSION:=}" "${UV_SHA256:=}"
: "${TY_VERSION:=}" "${TY_SHA256:=}"
: "${DUST_VERSION:=}" "${DUST_SHA256:=}"
: "${XH_VERSION:=}" "${XH_SHA256:=}"
: "${PROCS_VERSION:=}" "${PROCS_SHA256:=}"
: "${DIFFT_VERSION:=}" "${DIFFT_SHA256:=}"
: "${DELTA_VERSION:=}" "${DELTA_SHA256:=}"
: "${HEXYL_VERSION:=}" "${HEXYL_SHA256:=}"
# carapace is the one out-of-band tool with no SHA pin: it arrives as a signed .deb and
# apt verifies it, so the pin here is only the version to fetch.
: "${CARAPACE_VERSION:=}"

# _vi_fetch <binary> <url> <sha256> <outvar> — shared front half of the installers:
# skip if already present, refuse a bad/missing pin, download, verify. Echoes the temp
# dir path into <outvar>. Returns non-zero when the caller should stop (already
# installed, or a fail-closed condition) — callers treat that as "nothing to do".
#
# FAIL-CLOSED by design: a missing pin, a failed download, or a hash mismatch SKIPS the
# tool loudly rather than installing something unverified.
#
# NOTE the leading-underscore locals. This function writes its result back through a
# CALLER-SUPPLIED variable NAME (`printf -v "$outvar"`), so any local it declares that
# shares that name would shadow the caller's variable and swallow the result — bash has
# no other scoping to save you. The callers pass `tmp`, so a local named `tmp` here
# silently broke every single out-of-band install: the caller's path stayed empty, every
# unpack was attempted on "/asset", and all of it surfaced only as "could not unpack".
# Keep these prefixed, and keep them out of step with the caller's names.
_vi_fetch() {
  local _vi_bin="$1" _vi_url="$2" _vi_want="$3" _vi_outvar="$4"
  command -v "$_vi_bin" >/dev/null 2>&1 && return 1

  local _vi_arch; _vi_arch="$(uname -m)"
  if [[ "$_vi_arch" != x86_64 ]]; then
    note_fail "$_vi_bin: no pinned asset for $_vi_arch — install it by hand"
    return 1
  fi
  if [[ -z "$_vi_want" || ! "$_vi_want" =~ ^[0-9a-f]{64}$ ]]; then
    note_fail "$_vi_bin: no valid SHA-256 pin in install/tool-versions.env — SKIPPED"
    return 1
  fi

  blib_say "$_vi_bin (pinned release asset, sha256-verified)"
  local _vi_dir; _vi_dir="$(mktemp -d)" || return 1
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "$_vi_dir/asset" "$_vi_url"; then
    note_fail "$_vi_bin: download failed ($_vi_url) — SKIPPED"
    rm -rf "$_vi_dir"; return 1
  fi
  if ! printf '%s  %s\n' "$_vi_want" "$_vi_dir/asset" | sha256sum -c - >/dev/null 2>&1; then
    echo "   $_vi_bin: SHA-256 MISMATCH — refusing to install." >&2
    echo "     expected $_vi_want" >&2
    echo "     actual   $(sha256sum "$_vi_dir/asset" | cut -d' ' -f1)" >&2
    echo "     If you just bumped the version, run scripts/update-tool-checksums.sh." >&2
    note_fail "$_vi_bin: SHA-256 mismatch — SKIPPED"
    rm -rf "$_vi_dir"; return 1
  fi
  printf -v "$_vi_outvar" '%s' "$_vi_dir"
  return 0
}

# verified_install <binary> <asset-url> <sha256> [inner-name]
# For assets that contain ONE binary. Handles the three shapes upstreams actually ship:
# .tar.gz, plain .gz, and .zip — the dotfiles-Offense version this was derived from
# assumed tar.gz only, so a plain
# .gz (tree-sitter) or a .zip (procs) failed to unpack and the tool was SILENTLY skipped.
#
# [inner-name] is the name of the executable INSIDE the asset when it differs from the
# command you want on PATH (mikefarah's yq ships `yq_linux_amd64`). Without it, the
# find-by-name below matches nothing and the tool is again silently skipped.
verified_install() {
  local bin="$1" url="$2" want="$3" inner="${4:-$1}" tmp=""
  _vi_fetch "$bin" "$url" "$want" tmp || return 0
  # Clean up on every exit path below. Disarm FIRST: a RETURN trap is a GLOBAL slot, not
  # a function-scoped one, so an armed trap survives into the CALLER's frame and fires
  # AGAIN on ITS return — where $tmp is long out of scope and `set -u` makes it fatal.
  # That aborted every fresh-box run at the instant provision() returned, after all of its
  # work had succeeded, so wire_links never ran and the box got every package but not one
  # symlink. Worse, bash blames a RETURN trap on the last nested function DEFINITION in
  # that frame (_add_vendor_repo) rather than on this line, which sends the hunt to
  # entirely the wrong place. Keep the disarm, and keep it first.
  #
  # `|| true` guards a different edge. A RETURN trap does NOT clobber the function's
  # return status — bash preserves it, so `return 7` still surfaces as 7 even when the
  # trap body ends in a failure — but a FAILING command INSIDE the trap does trip errexit.
  # `rm -rf` on our own mktemp dir is about as safe as it gets, yet the cost of the
  # unlucky case is aborting a bootstrap that had otherwise fully succeeded. Same rule
  # Core applies in blib_set_login_shell: a trailing cleanup step may not throw away a
  # complete run.
  trap 'trap - RETURN; rm -rf "$tmp" || true' RETURN

  local found=""
  if tar -xzf "$tmp/asset" -C "$tmp" 2>/dev/null; then
    : # tarball — find the binary by name below
  elif [[ "$url" == *.zip ]] && command -v unzip >/dev/null 2>&1 &&
    unzip -qo "$tmp/asset" -d "$tmp" 2>/dev/null; then
    : # zip — same
  elif gunzip -c "$tmp/asset" >"$tmp/$inner" 2>/dev/null && [[ -s "$tmp/$inner" ]]; then
    # Plain gzip of a bare executable (tree-sitter ships this shape). gunzip leaves it
    # non-executable; `install -m 0755` below fixes that, so do NOT filter on -perm here.
    found="$tmp/$inner"
  else
    note_fail "$bin: could not unpack the asset — SKIPPED"
    return 0
  fi

  if [[ -z "$found" ]]; then
    # Archives nest the binary at varying depths (atuin under a versioned dir, uv/ty
    # under a target-triple dir, lazygit and starship at the root), so find by NAME
    # rather than assuming a layout.
    #
    # Deliberately NOT filtered on -perm -u+x. Zip archives do not always carry the
    # exec bit (procs' does not), so the permission filter would match nothing and the
    # tool would be reported as "not inside the asset" — a silent skip with a
    # misleading reason. `install -m 0755` below sets the mode regardless, so the bit
    # on the extracted file is not information we need.
    found="$(find "$tmp" -type f -name "$inner" -print -quit 2>/dev/null)"
  fi
  if [[ -z "$found" ]]; then
    note_fail "$bin: no '$inner' executable inside the asset — SKIPPED"
    return 0
  fi

  mkdir -p "$HOME/.local/bin"
  install -m 0755 "$found" "$HOME/.local/bin/$bin"
  blib_ok "$bin → ~/.local/bin/$bin"
}

# verified_tree_install <binary> <asset-url> <sha256> <opt-dir> <rel-bin-path>
# For assets that are a DIRECTORY TREE, not a lone binary — Neovim is the case that
# forces this to exist. `nvim-linux-x86_64.tar.gz` ships bin/, lib/ and
# share/nvim/runtime, and the runtime is not optional: copy bin/nvim alone (which is
# what a single-binary installer does) and you get an nvim that starts and then fails
# on every builtin, because $VIMRUNTIME points into nothing. So: unpack the tree under
# ~/.local/opt/<opt-dir> and symlink the binary into ~/.local/bin.
#
# Deliberately NOT the AppImage, even though upstream ships one: Ubuntu 24.04 sets
# kernel.apparmor_restrict_unprivileged_userns=1, which blocks the unprivileged user
# namespace an AppImage needs to FUSE-mount itself. The tarball has no such dependency.
verified_tree_install() {
  local bin="$1" url="$2" want="$3" optdir="$4" relbin="$5" tmp=""
  _vi_fetch "$bin" "$url" "$want" tmp || return 0
  # Self-disarming and errexit-proof, for the reasons spelled out in verified_install.
  trap 'trap - RETURN; rm -rf "$tmp" || true' RETURN

  if ! tar -xzf "$tmp/asset" -C "$tmp" 2>/dev/null; then
    note_fail "$bin: could not unpack the asset — SKIPPED"
    return 0
  fi
  # The tarball has a single top-level dir whose name carries the version/arch; take it
  # by shape rather than by name so an upstream rename doesn't silently break this.
  local top
  top="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -print -quit 2>/dev/null)"
  if [[ -z "$top" || ! -x "$top/$relbin" ]]; then
    note_fail "$bin: expected $relbin inside the asset — SKIPPED"
    return 0
  fi

  local dest="$HOME/.local/opt/$optdir"
  mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
  rm -rf "$dest"
  mv "$top" "$dest"
  ln -sfn "$dest/$relbin" "$HOME/.local/bin/$bin"
  blib_ok "$bin → ~/.local/opt/$optdir (linked into ~/.local/bin)"
}

_dotfiles_go_install() { # <import-path@version> <binary-name>
  # go install drops binaries in ~/go/bin, which the shell layer does NOT put on
  # PATH (it prefixes ~/.local/bin and ~/.cargo/bin) — so pin GOBIN to ~/.local/bin
  # or the tool would still read as "missing" after bootstrap.
  [[ "$#" -ge 2 ]] || return 0
  if command -v "$2" >/dev/null 2>&1; then return 0; fi
  command -v go >/dev/null 2>&1 || {
    note_fail "$2: go is not installed — SKIPPED"
    return 0
  }
  blib_say "$2 (go install)"
  # Ubuntu 24.04's golang-go is 1.22, and GOTOOLCHAIN defaults to `auto` from 1.21, so
  # a module demanding a newer Go downloads its own toolchain rather than failing.
  mkdir -p "$HOME/.local/bin"
  GOBIN="$HOME/.local/bin" go install "$1" >/dev/null 2>&1 ||
    note_fail "$2: go install failed — SKIPPED"
}

provision() {
  # ── PATH: make the presence guards below tell the TRUTH ─────────────────────
  # Every `command -v <tool>` guard decides whether to spend time downloading. Installs
  # land in ~/.local/bin (and ~/.cargo/bin), which are NOT on PATH during a fresh
  # bootstrap — os/debian.zsh adds them, and that has not been sourced yet. Without this
  # prelude every re-run would redo work it had already done.
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

  local base_list="$DOTFILES/install/packages.txt"
  # The base list is not optional — bootstrapping without it installs NOTHING and still
  # exits 0, which reads as success. blib_read_pkgs does no existence check of its own.
  [[ -f "$base_list" ]] || {
    echo "missing $base_list — the base package list is required" >&2
    exit 1
  }
  local -a base=()
  # pkg_filter_lines drops the lines annotated for OTHER distros; blib_read_pkgs then
  # turns what survives into names, exactly as it always did. Process substitution because
  # blib_read_pkgs takes a path.
  mapfile -t base < <(blib_read_pkgs <(pkg_filter_lines "$base_list" "$OS_ID"))

  sudo_keepalive_start

  # ── universe (Ubuntu only) ──────────────────────────────────────────────────
  # Most of the modern-CLI stack lives in `universe`, not `main`. It is enabled by
  # default on Desktop and Server images, so this is belt-and-braces for minimal/cloud
  # images — but it is done unconditionally on Ubuntu so CI proves THIS SCRIPT'S
  # assumption rather than the container image's defaults. `add-apt-repository` lives in
  # software-properties-common, which is why that one package is installed ahead of the
  # manifest. Guarded on ID=ubuntu because it is the ONLY target with that component:
# Debian has no `universe`, and Kali ships `kali-rolling main contrib non-free
# non-free-firmware` — on either, the call errors.
  if [[ "$OS_ID" == ubuntu ]]; then
    blib_say "apt update (pre-universe)"
    apt_get update -qq || note_fail "apt-get update failed"
    if ! command -v add-apt-repository >/dev/null 2>&1; then
      apt_install software-properties-common
    fi
    if command -v add-apt-repository >/dev/null 2>&1; then
      blib_say "ensuring the 'universe' component is enabled"
      priv add-apt-repository -y universe >/dev/null 2>&1 ||
        note_fail "could not enable universe (already enabled, or add-apt-repository failed)"
    fi
  fi

  if ((DO_UPGRADE)); then
    blib_say "apt update + full-upgrade"
    apt_get update || note_fail "apt-get update failed"
    apt_get full-upgrade -y || note_fail "apt-get full-upgrade failed"
  else
    blib_say "apt update (skipping full-upgrade: --no-upgrade)"
    apt_get update || note_fail "apt-get update failed"
  fi

  # ORDER IS LOAD-BEARING: this must stay AHEAD of every out-of-band install below.
  # Each of those is guarded by `command -v <binary>`, so on a distro where apt already
  # supplied the tool the guard fires and the download no-ops. That is the whole
  # mechanism behind install/packages.txt's `# only:kali` tier — Kali's archive tracks
  # sid and simply has neovim/starship/lazygit/…, so apt lands them here and the pinned
  # fetches skip themselves. No conditional is needed, and adding one would duplicate a
  # guard that already exists and can drift from it.
  #
  # Reorder these two blocks and nothing errors — the guards just all miss, and Kali ends
  # up with a pinned tarball shadowing its distro build. `make apt-first` pins the order.
  blib_say "apt base CLI stack (install/packages.txt)"
  apt_install "${base[@]}"
  blib_ok "base packages requested: ${#base[@]}"

  # ── the frozen-archive half: pinned, verified release assets ────────────────
  # Everything below is absent from noble, or present but too old to satisfy Core.
  # Each is HAVE_*-guarded in the shell, so a failure here degrades, never aborts.

  # neovim — noble ships 0.9.5; core/nvim's pinned nvim-treesitter (main) hard-requires
  # 0.12. This is the one non-negotiable out-of-band install: without it the editor half
  # of the stack does not work at all. Tree install, not single-binary (see the helper).
  verified_tree_install nvim \
    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
    "$NVIM_SHA256" "nvim-linux-x86_64" "bin/nvim"

  # tree-sitter CLI — floor is 0.26.1 (core/PORTING-MATRIX.md); noble has 0.20.8, and
  # NO Debian/Ubuntu suite short of sid clears it. Ships as a plain .gz of the bare
  # binary, which is why verified_install grew a gunzip branch.
  verified_install tree-sitter \
    "https://github.com/tree-sitter/tree-sitter/releases/download/v${TREESITTER_VERSION}/tree-sitter-linux-x64.gz" \
    "$TREESITTER_SHA256"

  # Absent from noble entirely.
  verified_install starship \
    "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-gnu.tar.gz" \
    "$STARSHIP_SHA256"
  verified_install lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_x86_64.tar.gz" \
    "$LAZYGIT_SHA256"
  verified_install atuin \
    "https://github.com/atuinsh/atuin/releases/download/v${ATUIN_VERSION}/atuin-x86_64-unknown-linux-gnu.tar.gz" \
    "$ATUIN_SHA256"
  verified_install mise \
    "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" \
    "$MISE_SHA256"
  verified_install uv \
    "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" \
    "$UV_SHA256"
  # dust: the apt package would be `du-dust` (binary `dust`), but it is not in noble.
  # Installed out-of-band the binary is plainly `dust`, so Core's du-dust→dust name
  # resolution is simply a no-op on this box. Do not "fix" that.
  verified_install dust \
    "https://github.com/bootandy/dust/releases/download/v${DUST_VERSION}/dust-v${DUST_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    "$DUST_SHA256"
  verified_install xh \
    "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    "$XH_SHA256"
  # procs ships a .zip — the second shape verified_install had to learn.
  verified_install procs \
    "https://github.com/dalance/procs/releases/download/v${PROCS_VERSION}/procs-v${PROCS_VERSION}-x86_64-linux.zip" \
    "$PROCS_SHA256"
  # difftastic's binary is `difft`, not the package name. Opt-in (Core gates on
  # HAVE_DIFFT), so a skip here is harmless.
  verified_install difft \
    "https://github.com/Wilfred/difftastic/releases/download/${DIFFT_VERSION}/difft-x86_64-unknown-linux-gnu.tar.gz" \
    "$DIFFT_SHA256"

  # delta and hexyl — the two names apt has on noble and trixie but NOT on kali-rolling
  # (proven by the kali packages lane, which is the only place that difference shows).
  # They are `# skip:kali` in the manifest and land here instead.
  #
  # No distro conditional, on purpose. _vi_fetch returns early when `command -v <bin>`
  # already answers, so on noble and trixie — where apt installed git-delta and hexyl
  # minutes earlier in this same provision() — these two calls cost one PATH lookup and
  # download nothing. On Kali the lookup misses and the pinned asset is fetched. Same
  # guard that makes the `# only:kali` tier work, running in the opposite direction.
  verified_install delta \
    "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    "$DELTA_SHA256"
  verified_install hexyl \
    "https://github.com/sharkdp/hexyl/releases/download/v${HEXYL_VERSION}/hexyl-v${HEXYL_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    "$HEXYL_SHA256"

  # ty — Astral's type checker. Prefer `uv tool install` (uv verifies its own downloads
  # and keeps ty upgradable in place); fall back to the pinned asset when uv is absent.
  if ! command -v ty >/dev/null 2>&1; then
    if command -v uv >/dev/null 2>&1; then
      blib_say "ty (via uv tool install)"
      uv tool install ty >/dev/null 2>&1 || note_fail "ty: uv tool install failed"
    else
      verified_install ty \
        "https://github.com/astral-sh/ty/releases/download/${TY_VERSION}/ty-x86_64-unknown-linux-gnu.tar.gz" \
        "$TY_SHA256"
    fi
  fi

  # ── atuin daemon: install the systemd user unit ─────────────────────────────
  # os/debian.zsh exports ATUIN_DAEMON__ENABLED=true, and sets AUTOSTART only when there
  # is NO systemd. Ubuntu HAS systemd, so without this block the daemon would be enabled
  # with nothing to launch it — the one state core/PORTING-MATRIX.md's atuin note says is
  # worth avoiding. Core's guard degrades safely (it probes the socket and forces the
  # daemon off for that shell), so the cost is the lock relief rather than a broken shell,
  # but "enabled and unlaunchable" is still the wrong thing to ship.
  if command -v atuin >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    local unit_src="$DOTFILES/core/examples/atuin-daemon.service"
    local unit_dst="$HOME/.config/systemd/user/atuin-daemon.service"
    # Capability probe, not a version parse: an atuin too old to know `daemon` would let
    # the unit start and fail on repeat, and the unit is Restart=on-failure/RestartSec=3 —
    # i.e. a restart loop for as long as the box is up. Ask the binary, not a number.
    if ! atuin daemon --help >/dev/null 2>&1; then
      blib_warn "installed atuin has no 'daemon' subcommand (too old) — skipping the unit"
    elif [[ -f "$unit_src" ]]; then
      blib_say "atuin daemon (systemd user unit)"
      if (mkdir -p "${unit_dst%/*}" 2>/dev/null && install -m 0644 "$unit_src" "$unit_dst" 2>/dev/null); then
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        if systemctl --user enable --now atuin-daemon >/dev/null 2>&1; then
          blib_ok "atuin-daemon enabled — 'loginctl enable-linger \"\$USER\"' keeps it up outside a login session"
        else
          # Never fatal, and on these boxes worth knowing: they are reached only over ssh,
          # so without linger the daemon dies with the last session.
          blib_warn "atuin-daemon not enabled (no user systemd session?) — shells fall back to direct SQLite writes"
        fi
      else
        note_fail "atuin-daemon: could not write the user unit — SKIPPED"
      fi
    fi
  fi

  # ── go-installed tools ──────────────────────────────────────────────────────
  # yq: noble's `yq` is kislyuk's PYTHON yq, and `yq-go` (mikefarah's, the jq-for-YAML
  # this stack means) does not exist in noble OR trixie — it is sid-only. So neither
  # name can go in packages.txt; installing the wrong one is worse than installing none.
  _dotfiles_go_install github.com/mikefarah/yq/v4@latest yq
  _dotfiles_go_install github.com/mr-karan/doggo/cmd/doggo@latest doggo
  _dotfiles_go_install github.com/joshmedeski/sesh/v2@latest sesh

  # ── vendor apt repos ────────────────────────────────────────────────────────
  # The fleet's established idiom for tools whose upstream runs a signed repo. Preferred
  # over a PPA: these resolve identically on Debian and Ubuntu (a PPA is keyed to an
  # Ubuntu series and 404s on Debian), and they are vendor-signed rather than
  # single-maintainer. Keys go in /etc/apt/keyrings, noble's convention.
  _add_vendor_repo() { # <name> <key-url> <sources-line>
    local name="$1" keyurl="$2" line="$3"
    local keyring="/etc/apt/keyrings/${name}.gpg"
    local listfile="/etc/apt/sources.list.d/${name}.list"
    [[ -f "$listfile" ]] && return 0
    command -v gpg >/dev/null 2>&1 || { note_fail "$name repo: gpg is missing — SKIPPED"; return 0; }
    priv install -d -m 0755 /etc/apt/keyrings
    # Write the KEY first and only then the sources line. A .list pointing at a keyring
    # that failed to download wedges EVERY later `apt-get update` on the box — a much
    # worse outcome than simply not having the tool.
    if ! curl -fsSL "$keyurl" | priv gpg --dearmor --yes -o "$keyring" 2>/dev/null; then
      note_fail "$name repo: could not fetch/dearmor the signing key — SKIPPED"
      priv rm -f "$keyring"
      return 0
    fi
    priv chmod 0644 "$keyring"
    printf '%s\n' "$line" | priv tee "$listfile" >/dev/null
    blib_ok "$name apt repo configured"
  }

  # Charm (glow, gum) — neither is in noble. Their repo is a signed flat repo serving
  # every Debian-family release from one dist, hence the `* *` suite/component.
  if ! command -v glow >/dev/null 2>&1 || ! command -v gum >/dev/null 2>&1; then
    _add_vendor_repo charm "https://repo.charm.sh/apt/gpg.key" \
      "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *"
    apt_get update -qq || true
    apt_install glow gum
  fi

  # op (1Password CLI) — vendor repo, same shape.
  if ! command -v op >/dev/null 2>&1; then
    local op_arch; op_arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    _add_vendor_repo 1password "https://downloads.1password.com/linux/keys/1password.asc" \
      "deb [arch=${op_arch} signed-by=/etc/apt/keyrings/1password.gpg] https://downloads.1password.com/linux/debian/${op_arch} stable main"
    apt_get update -qq || true
    apt_install 1password-cli
  fi

  # ── carapace — upstream .deb ────────────────────────────────────────────────
  # Deliberately NOT go-installed: `go install` cannot work for ANY version of it
  # (replace directives in go.mod plus uncommitted generated sources). Absent from every
  # Debian/Ubuntu suite, so the release .deb is the only automatic path. apt-get wants a
  # PATH, not a URL, hence the temp download.
  if ! command -v carapace >/dev/null 2>&1 && [[ -n "$CARAPACE_VERSION" ]]; then
    local cara_arch cara_tmp
    cara_arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
    cara_tmp="$(mktemp -d)"
    blib_say "carapace (upstream .deb)"
    if curl -fsSL --retry 3 -o "$cara_tmp/carapace.deb" \
      "https://github.com/carapace-sh/carapace-bin/releases/download/v${CARAPACE_VERSION}/carapace-bin_${CARAPACE_VERSION}_linux_${cara_arch}.deb"; then
      apt_get install -y "$cara_tmp/carapace.deb" || note_fail "carapace: .deb install failed"
    else
      note_fail "carapace: .deb download failed — SKIPPED"
    fi
    rm -rf "$cara_tmp"
  fi

  # ── unattended-upgrades ─────────────────────────────────────────────────────
  # These boxes sit on a shelf and are only reached over ssh, so nobody is going to
  # notice a security advisory. Restrict it to the SECURITY pocket: a full auto-upgrade
  # on an unattended machine is how you find out a package changed behaviour at 3am.
  # Core's `up` still owns the deliberate, full upgrade.
  if ((DO_UNATTENDED)); then
    blib_say "unattended-upgrades (security pocket only)"
    apt_install unattended-upgrades
    if [[ -d /etc/apt/apt.conf.d ]]; then
      printf '%s\n' \
        'APT::Periodic::Update-Package-Lists "1";' \
        'APT::Periodic::Unattended-Upgrade "1";' |
        priv tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null ||
        note_fail "could not write 20auto-upgrades"
    fi
  else
    blib_say "skipping unattended-upgrades (--no-unattended)"
  fi

  # ── WSL2: the distro-side /etc/wsl.conf ─────────────────────────────────────
  # Only written when we are actually inside WSL — blib_is_wsl is Core's test, used
  # here rather than re-rolling one (os/debian.zsh has a fork-free zsh twin for the
  # per-shell case; this runs once, so the grep is free).
  #
  # systemd=true is the load-bearing line: without it there is no user session bus,
  # and the atuin daemon unit this bootstrap installs above has nothing to run under.
  #
  # NOT idempotent in the useful sense — it overwrites /etc/wsl.conf every run. That
  # is deliberate: the file is small, fully owned by this repo, and a half-edited one
  # is worse than a replaced one. Anything hand-added there belongs in the repo copy.
  if blib_is_wsl; then
    blib_say "installing /etc/wsl.conf (systemd + default user + interop)"
    local wsl_user
    wsl_user="$(id -un)"
    if [[ -r "$DOTFILES/wsl/wsl.conf" ]]; then
      if sed "s/__WSL_USER__/$wsl_user/" "$DOTFILES/wsl/wsl.conf" |
        priv tee /etc/wsl.conf >/dev/null; then
        blib_ok "wsl.conf written — from Windows: 'wsl.exe --shutdown', then reopen the distro"
      else
        note_fail "could not write /etc/wsl.conf"
      fi
    else
      note_fail "wsl/wsl.conf missing from the checkout — /etc/wsl.conf not written"
    fi
    # The counterpart lives on the Windows side and CANNOT be set from in here, so
    # it can only ever be a pointer. Worth saying out loud: a listener inside WSL2
    # is unreachable from the LAN until networkingMode=mirrored, and the symptom
    # (connection refused from another host, works from the Windows host) sends
    # people to debug the wrong layer entirely.
    blib_say "NOTE: inbound listeners need mirrored networking — see wsl/windows.wslconfig.example"
  fi
}

wire_links() {
  # The shared symlink surface + the Debian OS overlays + the managed .zshrc
  # loader + the default-login-shell switch all live in core/lib/bootstrap-lib.sh.
  blib_link_core "$DOTFILES" "$CONFIG"
  blib_link_os_layer "$DOTFILES" "$CONFIG" debian
  # shellcheck disable=SC2119  # no args is intentional — writes the default module set
  blib_write_zshrc_loader
  blib_set_login_shell
  # Install the local pre-commit guard that refuses hand-edits to the vendored core/
  # subtree. .git/hooks is NOT version-controlled, so a fresh clone has none. The
  # PR-time core-integrity workflow is the durable backstop, but this catches the edit
  # before it is ever committed.
  #
  # Dry-run guarded at the CALL SITE on purpose: blib_install_core_guard writes
  # .git/hooks/pre-commit unconditionally (it predates BLIB_DRY and does not consult it),
  # so calling it under --dry-run would mutate the repo during a run that promises not to.
  if ((BLIB_DRY)); then
    blib_say "would install the core/ pre-commit guard in $DOTFILES"
  else
    blib_install_core_guard "$DOTFILES" || true
  fi
  blib_ok "symlinks wired$(blib_selected_note)"
}

# ── run ───────────────────────────────────────────────────────────────────────
if ((BLIB_DRY)); then
  blib_say "DRY RUN — nothing below is executed or written"
fi

if ((LINKS_ONLY)); then
  :
elif ((BLIB_DRY)); then
  # A dry run must preview provisioning too, not silently skip half the script. Print the
  # plan (what apt would be asked for, which extras are missing) without touching anything.
  [[ "$OS_ID" == ubuntu ]] && blib_say "would ensure the 'universe' component is enabled"
  blib_say "would apt update$( ((DO_UPGRADE)) && printf ' + full-upgrade')"
  if [[ -f "$DOTFILES/install/packages.txt" ]]; then
    _dry_pkgs=()
    mapfile -t _dry_pkgs < <(blib_read_pkgs <(pkg_filter_lines "$DOTFILES/install/packages.txt" "$OS_ID"))
    blib_say "would apt install ${#_dry_pkgs[@]} packages: ${_dry_pkgs[*]}"
    unset _dry_pkgs
  else
    blib_warn "install/packages.txt is missing — a real run would abort here"
  fi
  for _t in "${OUT_OF_BAND_TOOLS[@]}"; do
    command -v "$_t" >/dev/null 2>&1 || blib_say "would install (out of band): $_t"
  done
  unset _t
  ((DO_UNATTENDED)) && blib_say "would configure unattended-upgrades (security pocket)"
  # The distro tier and the WSL step are both conditional, so a preview that omitted
  # them would under-report on exactly the boxes where they matter.
  blib_say "distro tier in effect: ID=${OS_ID:-unknown}"
  if blib_is_wsl; then
    blib_say "would write /etc/wsl.conf (systemd + default user=$(id -un) + interop)"
    blib_say "would note: inbound listeners need mirrored networking (wsl/windows.wslconfig.example)"
  fi
else
  provision
  sudo_keepalive_stop
fi

wire_links
blib_wire_summary

# ── closing report ────────────────────────────────────────────────────────────
# Say plainly what did NOT work. A script that prints "complete" and exits 0 no matter
# how many best-effort steps failed makes a half-provisioned box look identical to a
# good one — and on a frozen archive, best-effort steps DO fail.
if ((${#FAILED_STEPS[@]})); then
  printf '\n%s%s%s %s\n' "${UX_YEL:-}" "${UX_WARN:-!}" "${UX_RST:-}" \
    "${#FAILED_STEPS[@]} step(s) did not complete:"
  printf '    - %s\n' "${FAILED_STEPS[@]}"
  echo
  if ((STRICT)); then
    blib_warn "exiting non-zero (--strict)"
    exit 1
  fi
  blib_ok "Debian bootstrap finished WITH the warnings above — open a new shell or: exec zsh"
else
  blib_ok "Debian bootstrap complete — open a new shell or: exec zsh"
fi
