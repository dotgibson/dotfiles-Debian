# Security Policy — dotfiles-Debian

This repo provisions a workstation. `bootstrap.sh` runs as your user, escalates to root
for package installs, and fetches software from the internet. That makes its **trust
decisions** part of its security surface, so they are written down here rather than left
implicit in the script.

GitHub resolves `SECURITY.md` from the repo root, `.github/`, or `docs/` — the vendored
`core/SECURITY.md` governs `dotfiles-core` and is inert here.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem. Use GitHub's
[private vulnerability reporting](https://github.com/dotgibson/dotfiles-Debian/security/advisories/new),
or email <garrettallen2@gmail.com>. Expect an acknowledgement within a few days.

## Secrets: none are stored here

This repository contains **no secrets, keys, or tokens**, and none should ever be added.

- Runtime secrets come from **1Password** via the `op` CLI (see `core/zsh/50-op.zsh`).
- **SSH keys are never tracked.** `.gitignore` excludes everything under `ssh/`, plus the
  usual key/credential filename patterns. Nothing there is tracked at all now — the ssh
  client config moved into Core as `core/ssh/config` (dotgibson/dotfiles-core#450).
- Your **git identity** (name/email) is *seeded once* to `~/.config/git/local.gitconfig`
  and edited there — it is never tracked back into this repo.
- **Push protection and secret scanning are enabled** on this repository. `gitleaks` also
  runs at author time via `.pre-commit-config.yaml`.

## Trust decisions made by `bootstrap.sh`

Provisioning a modern CLI stack on a frozen Ubuntu LTS means going outside the distro
repos far more than on a rolling distro. Each of these is a deliberate choice with a
real cost; none is hidden.

| What | Source | Why not `apt` | Mitigation |
| --- | --- | --- | --- |
| **neovim, tree-sitter, starship, lazygit, atuin, mise, uv, ty, dust, xh, procs, difft** | Upstream GitHub release assets | Absent from `noble`, or present far below the version Core requires (nvim 0.9.5 vs 0.12; tree-sitter 0.20.8 vs 0.26.1) | **Version and SHA-256 pinned** in `install/tool-versions.env`; the asset is downloaded to a temp file, `sha256sum -c`'d, and only then unpacked. **Never `curl \| sh`.** Fail-closed: a missing pin, a failed download, or a hash mismatch skips that tool loudly and records it in the closing report |
| **glow, gum** | Charm's signed apt repo (`repo.charm.sh`) | Not in `noble` or `trixie` | Vendor-signed repo with a rotating key — a stronger control than a hash we maintain by hand. The key is dearmored into `/etc/apt/keyrings` **before** the sources line is written, so a failed key fetch costs the tool, never a wedged `apt-get update` |
| **1Password CLI** | `downloads.1password.com` apt repo | Not packaged by Debian/Ubuntu | Same shape and same ordering guarantee as Charm above |
| **carapace** | Upstream `.deb` release asset | `go install` is *impossible* — the module has `replace` directives plus uncommitted generated sources (see the comment in `bootstrap.sh`) | Installed via `apt-get install <path>`, so dpkg verifies the package. Version-pinned, but **not checksum-pinned** — see *Known gaps* |
| **yq, doggo, sesh** | `go install` | `yq-go` is sid-only (noble's `yq` is the unrelated Python tool); the others are unpackaged | The Go module proxy verifies against the checksum database |
| **tpm** (tmux plugins) | `github.com/tmux-plugins/tpm` | Not packaged | Shallow clone, one time, into `~/.config/tmux/plugins` |

**No PPAs.** A PPA is keyed to an Ubuntu series, so it breaks Debian and would red the
`debian:trixie` CI lane; it is also unpinned and single-maintainer, and its maintainer
scripts run as root. A pinned tarball into `~/.local/bin` cannot touch `/usr`. The line
this repo draws is *vendor-signed apt repos yes, PPAs no*.

### Unattended upgrades

`bootstrap.sh` enables `unattended-upgrades` restricted to the **security pocket**, and
`--no-unattended` opts out. Full upgrades stay manual (Core's `up`): an unwatched box
that silently changes package behaviour is its own kind of incident.

### Privilege escalation

`bootstrap.sh` resolves an escalator **once** (`BLIB_SU`: empty when already root, else
`sudo`, else `doas`) and refuses to start a provisioning run if it has none. When using
`sudo` it primes the timestamp up front and refreshes it in the background, so no
privileged call later in the run can stall on an invisible password prompt. Set
`BLIB_SU` explicitly to override. `--links-only` needs no privileges at all.

### Known gaps

Recorded honestly rather than papered over:

1. **The pinned assets do not update themselves.** Every `verified_install` is
   presence-guarded, so once a binary exists on the box no later bootstrap replaces it.
   Bumping is a deliberate act: edit `install/tool-versions.env`, run
   `scripts/update-tool-checksums.sh`, review the diff. `--latest` reports which pins
   have newer upstream releases, and `make tool-checksums` asserts the pins still match
   what upstream serves.
2. **carapace is version-pinned but not checksum-pinned.** It arrives as a `.deb`, so
   dpkg verifies the package, but there is no hash of our own in the loop and nothing
   upgrades it afterwards. Check `carapace --version` occasionally.
3. **`~/.local/bin` is on PATH ahead of `/usr/bin`.** That is what makes the
   out-of-band installs win over an older apt copy of the same tool — which is the point
   on a frozen archive — but it also means anything that can write there can shadow a
   system binary for your shell.
4. **Reusable workflows are pinned to the moving `@v4` tag**, not a commit SHA. This is
   the documented fleet policy (`core/RELEASE-STRATEGY.md`): a caller's contract then
   changes only via a Core *release*. All workflows are first-party (`dotgibson/*`), and
   third-party actions inside them (`actions/checkout`, `actions/cache`) *are* SHA-pinned.

## Supported versions

The tip of `main` is the only supported version. The targeted release is **Ubuntu 24.04
LTS**; **Debian trixie** is proven in CI because the repo is named for the family.
Ubuntu 26.04 is watched as an advisory lane — when a tool this repo installs
out-of-band appears there, that is the signal to promote it back into
`install/packages.txt`. See that file for per-package availability notes.
