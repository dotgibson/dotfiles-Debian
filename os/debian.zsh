# dotfiles-Debian/os/debian.zsh
# ──────────────────────────────────────────────────────────────────────────────
# The Debian/Ubuntu OS-native shell layer. Symlinked to ~/.config/zsh/80-os.zsh and
# loaded AFTER Core (tools/aliases/functions). Debian-family-specific only.
#
# Targets Ubuntu 24.04 LTS (the CI-proven target); plain Debian and the other
# Debian-family derivatives work on the same paths but are not gated in CI.
#
# NOTE: clipboard logic does not live here — it is Core's cross-OS `clip`/`clip-paste`
# scripts, which zsh, tmux, and nvim all share. This layer just keeps the
# pbcopy/pbpaste muscle-memory names pointed at them.
# ──────────────────────────────────────────────────────────────────────────────
[[ $- == *i* ]] || return 0

# ── PATH: user-local bins first (Core's `clip` scripts + cargo tools land here)
[[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin${PATH:+:$PATH}"
[[ -d "$HOME/.cargo/bin" && ":$PATH:" != *":$HOME/.cargo/bin:"* ]] && export PATH="$HOME/.cargo/bin${PATH:+:$PATH}"
# ~/.atuin/bin: where atuin's own installer puts the binary. bootstrap.sh installs the
# pinned release asset into ~/.local/bin instead, so this is the belt-and-braces entry for
# a box where atuin arrived some other way — THIS file is fragment 80 and Core's tool
# detection already ran at 00, so the link in ~/.local/bin is what actually gets detected.
[[ -d "$HOME/.atuin/bin" && ":$PATH:" != *":$HOME/.atuin/bin:"* ]] && export PATH="$HOME/.atuin/bin${PATH:+:$PATH}"

# ── Clipboard: delegate to Core's cross-OS scripts (single implementation) ────
# On a headless box with no Wayland/X11 session these have no backend to reach —
# see README's "Headless" note. The aliases stay so the muscle memory is consistent.
command -v clip       >/dev/null && alias pbcopy='clip'
command -v clip-paste >/dev/null && alias pbpaste='clip-paste'

# ── tool completions / shell hooks (parity with the other os layers) ─────────
# direnv/gh/uv/ty emit DETERMINISTIC scripts (the generated hook/completion TEXT is static
# for a given binary; only the runtime hooks vary per-dir/-shell), so route them through
# Core's _cache_eval (00-tools.zsh) — one cheap `source` of a cached file instead of forking
# each generator on EVERY interactive shell. _cache_eval self-guards on the binary being
# present and regenerates only when it's newer than the cache. Falls back to the eager
# eval if this OS layer is sourced without Core's 00-tools.zsh — the fallback
# keeps direnv's stderr visible, while the cached path suppresses the generator's
# stderr (as _cache_eval does); direnv's per-dir runtime warnings are unaffected.
if (( $+functions[_cache_eval] )); then
  _cache_eval direnv direnv hook zsh
  _cache_eval gh gh completion -s zsh
  _cache_eval uv uv generate-shell-completion zsh
  _cache_eval ty ty generate-shell-completion zsh
else
  command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
  command -v gh >/dev/null 2>&1 && eval "$(gh completion -s zsh 2>/dev/null)"
  command -v uv >/dev/null 2>&1 && eval "$(uv generate-shell-completion zsh 2>/dev/null)"
  command -v ty >/dev/null 2>&1 && eval "$(ty generate-shell-completion zsh 2>/dev/null)"
fi

# ── conveniences ──────────────────────────────────────────────────────────────
# dotsync — jump to THIS checkout, wherever it lives. ${0:A} resolves the bootstrap
# symlink (~/.config/zsh/80-os.zsh) back to os/debian.zsh, so :h:h is the repo root;
# the literal path is only the last-resort fallback.
DOTFILES_DEBIAN="${${0:A}:h:h}"
[[ -d "$DOTFILES_DEBIAN" ]] || DOTFILES_DEBIAN="$HOME/dotfiles-Debian"
export DOTFILES_DEBIAN
alias dotsync='cd "$DOTFILES_DEBIAN"'
command -v op >/dev/null 2>&1 && alias opsignin='eval "$(op signin)"'
alias localip='ip -brief -4 addr show scope global'     # iface + LAN IP(s)

# ── Debian ships fd as `fdfind` and bat as `batcat` — Core's 00-tools.zsh already
#    resolves both, and 20-aliases.zsh aliases them back to their canonical names.
#    Do NOT "fix" this here; you would be shadowing Core's resolution.

# ── apt quality-of-life ───────────────────────────────────────────────────────
# apt-get, not apt: apt's output is explicitly "not a stable interface for scripts"
# and it warns as much when piped. For interactive one-liners the difference is
# cosmetic; keeping one verb everywhere means these aliases behave the same when
# you paste them into a script.
alias apti='sudo apt-get install -y'
alias apts='apt-cache search'
alias aptu='sudo apt-get update && sudo apt-get full-upgrade -y'
alias aptr='sudo apt-get remove'
alias aptp='sudo apt-get purge'                # remove + drop config files
alias aptc='sudo apt-get autoremove && sudo apt-get autoclean'
alias aptw='dpkg -S'                           # which package owns a file/command
alias aptl='dpkg -L'                           # list files a package installed
alias aptshow='apt-cache show'
alias aptpolicy='apt-cache policy'             # what versions/pockets are on offer
# `apt list --upgradable` is the one place the apt verb earns its keep interactively.
alias aptup='apt list --upgradable 2>/dev/null'

# ── unattended-upgrades ───────────────────────────────────────────────────────
# Ubuntu enables this by default for the security pocket, so the box updates itself
# behind your back. Core's `up` does the full upgrade; these just let you see what
# the automatic half has been doing, and why apt is sometimes lock-held.
alias uu-status='systemctl status unattended-upgrades --no-pager'
alias uu-log='sudo tail -40 /var/log/unattended-upgrades/unattended-upgrades.log'
alias aptlock='sudo lsof /var/lib/dpkg/lock-frontend 2>/dev/null || echo "dpkg lock is free"'

# ── AppArmor helpers (Debian-family's LSM — the analog of Fedora's SELinux) ───
alias aa-status='sudo aa-status 2>/dev/null || echo "AppArmor not active / apparmor-utils not installed"'
alias aa-denials='sudo journalctl -k --since "10 min ago" 2>/dev/null | grep -i apparmor | tail -40'

# ── atuin daemon: the opt-in Core ships OFF (dotfiles-core#335) ───────────────
# Core's atuin/config.toml is vendored identically to every repo, so the per-machine flip
# is atuin's own env override, set HERE — never by editing that file. The daemon owns the
# SQLite writes so shells stop contending for the DB lock.
#
#   systemd present → the unit bootstrap installed owns the lifecycle; just enable.
#   no systemd      → hand the lifecycle to atuin itself (autostart), the same path Alpine
#                     and macOS take. NOT compatible with systemd_socket, which we do not use.
#
# Either way Core's guard (00-tools.zsh) probes the socket once before the first prompt and
# forces the daemon off for that shell if nothing is listening — so a broken launcher costs
# the lock relief, never a working shell. `core-doctor` reports the degraded state.
if [[ -n ${HAVE_ATUIN:-} ]]; then
  export ATUIN_DAEMON__ENABLED=true
  [[ -d /run/systemd/system ]] || export ATUIN_DAEMON__AUTOSTART=true
fi

# ── WSL2 niceties ────────────────────────────────────────────────────────────
# Kali under WSL2 is this repo's second-biggest deployment after the SSH-only
# shelf boxes, since dotfiles-Offense stacks its Role layer on one. None of this is
# Kali-specific though — it applies to any Debian-family distro under WSL.
#
# Detection is deliberately fork-free: WSL_DISTRO_NAME is set by WSL itself, and
# the /proc/version fallback is read with zsh's $(<file) rather than grep, because
# this runs on every interactive shell and Core's bench job holds startup to a
# 120ms budget. (bootstrap.sh uses Core's blib_is_wsl for the same test in bash,
# where the grep is fine — it runs once.)
_IS_WSL=0
if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
  _IS_WSL=1
elif [[ -r /proc/version ]]; then
  _pv="$(</proc/version)"; _pv=${_pv:l}
  [[ "$_pv" == *microsoft* || "$_pv" == *wsl* ]] && _IS_WSL=1
  unset _pv
fi

if (( _IS_WSL )); then
  alias open='explorer.exe'
  command -v wslview >/dev/null && alias xdg-open='wslview'

  # cdwin — jump to the Windows user profile.
  #
  # A FUNCTION, not an alias, and this is the point. dotfiles-Offense shipped
  #     [[ -n "${WINHOME:-}" ]] && alias cdwin='cd "$WINHOME"'
  # but nothing in that repo, or in Core, ever set WINHOME — so the alias only
  # existed for someone who had already exported it by hand, i.e. effectively never.
  # Deriving it eagerly at startup is not the fix either: it costs a powershell.exe
  # fork (~200ms+) on every single interactive shell, which is most of the startup
  # budget for a path most shells never take.
  #
  # So resolve it lazily, on first use, and memoise. Falls back to /mnt/c/Users/$USER,
  # which is right on the common setup and wrong quietly rather than loudly.
  cdwin() {
    if [[ -z "${WINHOME:-}" ]]; then
      local up
      up="$(powershell.exe -NoProfile -NonInteractive -Command '$env:USERPROFILE' 2>/dev/null | tr -d '\r')"
      if [[ -n "$up" ]] && command -v wslpath >/dev/null 2>&1; then
        WINHOME="$(wslpath "$up" 2>/dev/null)"
      fi
      [[ -d "${WINHOME:-}" ]] || WINHOME="/mnt/c/Users/$USER"
      export WINHOME
    fi
    if [[ -d "$WINHOME" ]]; then
      cd "$WINHOME"
    else
      print -u2 "cdwin: could not resolve the Windows profile (tried \$WINHOME, powershell.exe, /mnt/c/Users/$USER)"
      return 1
    fi
  }
fi

unset _IS_WSL

# ── auto-start/attach tmux for interactive terminals ─────────────────────────
# Land straight in a persistent `main` session for LOCAL interactive logins (a WSL
# terminal, a physical console) so it survives across shells. But NOT when you arrive
# over ssh ($SSH_CONNECTION set): coming in over ssh you're normally already inside a
# multiplexer on the client, so auto-attaching here just nests a mux you'd close
# anyway. The trade is that a dropped ssh link no longer drops you back into a live
# remote session — accepted, for not nesting. Run `tmux` by hand if you do want a
# server-side session over ssh. Fleet-wide policy, mirrored in dotfiles-Windows'
# powershell/os/30-windows.ps1 psmux auto-launch.
# Also skip inside an existing tmux, VS Code's integrated terminal, non-TTYs, and when
# DEBIAN_NO_TMUX is set (scp/rsync and `ssh host <cmd>` are already covered by -t 1).
if command -v tmux >/dev/null 2>&1 \
   && [[ -z "$TMUX" && -z "${DEBIAN_NO_TMUX:-}" && -z "${SSH_CONNECTION:-}" \
         && -t 1 && "$TERM_PROGRAM" != "vscode" ]]; then
  tmux attach -t main 2>/dev/null || tmux new-session -s main
fi
