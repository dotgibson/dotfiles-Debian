# Debian/Ubuntu Aliases Cheat Sheet

OS-specific aliases from `os/debian.zsh`. See [`core/aliases.md`](core/aliases.md) for the universal alias
set that every machine in the fleet shares.

## Package Management (apt)

All of these use `apt-get`, not `apt`: apt's output is explicitly not a stable interface
for scripts, so keeping one verb means these behave the same pasted into a script.

| Alias | Command |
| --- | --- |
| `apti` | `sudo apt-get install -y` |
| `apts` | `apt-cache search` |
| `aptu` | `sudo apt-get update && sudo apt-get full-upgrade -y` |
| `aptr` | `sudo apt-get remove` |
| `aptp` | `sudo apt-get purge` (remove + drop config files) |
| `aptc` | `sudo apt-get autoremove && sudo apt-get autoclean` |
| `aptw` | `dpkg -S` (which package owns a file/command) |
| `aptl` | `dpkg -L` (list files a package installed) |
| `aptshow` | `apt-cache show` |
| `aptpolicy` | `apt-cache policy` (what versions/pockets are on offer) |
| `aptup` | `apt list --upgradable` |

## Unattended upgrades

Ubuntu updates itself in the background for the security pocket, which is also the
usual reason apt is unexpectedly lock-held.

| Alias | Command |
| --- | --- |
| `uu-status` | `systemctl status unattended-upgrades` |
| `uu-log` | Tail `/var/log/unattended-upgrades/unattended-upgrades.log` |
| `aptlock` | Show what is holding the dpkg lock (or say it's free) |

## AppArmor

The Debian-family LSM, and the analog of Fedora's SELinux helpers.

| Alias | Command |
| --- | --- |
| `aa-status` | `sudo aa-status` (or a clear note if AppArmor isn't active) |
| `aa-denials` | Recent AppArmor denials from the kernel log |

## Misc

| Alias | Command |
| --- | --- |
| `dotsync` | `cd` to this checkout (resolved from the symlink, wherever it lives) |
| `localip` | `ip -brief -4 addr show scope global` |
| `opsignin` | `eval "$(op signin)"` (only if `op` is installed) |
| `pbcopy` / `pbpaste` | Core's `clip` / `clip-paste` — **inert headless**, see README |

## Not aliased here

`bat` and `fd` are **not** re-aliased in this layer. Debian ships them as `batcat` and
`fdfind`; Core's `00-tools.zsh` resolves the real binary and `20-aliases.zsh` aliases
them back to their canonical names. Adding aliases here would shadow that.
