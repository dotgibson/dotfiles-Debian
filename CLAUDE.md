# CLAUDE.md — dotfiles-Debian

Project memory for Claude Code, auto-loaded every session. For the shared Core
rules (the load order, the "is it Core?" test, the manifest contract) see
`core/README.md` and `core/CONTRIBUTING.md`.

## What this repo is

`dotfiles-Debian` is the **OS-native layer for the Debian family** in an
**eleven-repo dotfiles system** built on a three-layer model (Core → OS-native →
Role). Structurally it is stamped from the Fedora template (see
`core/PORTING-MATRIX.md`); its apt idioms come from `dotfiles-Kali`, the fleet's
other Debian-family repo.

**The target is Ubuntu 24.04 LTS, on headless SSH-only boxes.** The repo is named
for the family and CI proves both `ubuntu:24.04` and `debian:trixie`, but the
package list and quirks are tuned to noble.

## The rule that bites

`core/` is a **vendored `git subtree` copy of [dotfiles-core](https://github.com/dotgibson/dotfiles-core)** — it
is *not* editable here. Anything you change under `core/` is overwritten on the
next sync. To change shared Core config, edit it **in dotfiles-core**, run
`make audit` there, then let the release fan-out bring it here.

What belongs **here** is only the OS-native layer: the apt package list, the
out-of-band installs, paths, and the bootstrap.

## The other rule that bites: Ubuntu LTS is frozen, so apt is not enough

This is the one thing that makes this repo different from every sibling. Ubuntu
24.04 froze in **April 2024**; every other Linux repo in the fleet targets a
rolling or near-rolling distro. So a large slice of the stack is either absent
from `noble` or present at a version Core cannot use:

- **`neovim`** — noble ships **0.9.5**. Core's nvim pins nvim-treesitter to its
  `main` branch, which hard-requires **0.12** (`core/nvim/lua/gerrrt/config/providers.lua`).
  Three minors short, and `noble-backports` has nothing.
- **`tree-sitter-cli`** — noble has **0.20.8**; the floor is **0.26.1**
  (`core/PORTING-MATRIX.md` footnote 5). No Debian/Ubuntu suite short of sid
  clears it, so this stays out-of-band for years.
- **`yq`** — noble's `yq` is kislyuk's **Python** yq. The Go one this stack means
  (`yq-go`) is in neither noble nor trixie. Installing the wrong one is worse
  than installing none, so **neither name goes in `packages.txt`**.
- **`cargo`** — noble's rustc is **1.75**, too old to build `yazi`, `ast-grep` or
  `viddy`. Those three are simply **not installed here**; all are `HAVE_*`-guarded
  in Core, so the shell degrades cleanly. `mise use -g rust` if you want them.

Everything apt cannot honestly supply lives in `bootstrap.sh` as a pinned,
SHA-256-verified release asset — see `install/tool-versions.env`. **A name belongs
in `install/packages.txt` only if apt really resolves it at a version Core can
use.** Version floors are declared there as `# min:X.Y.Z` trailing comments and
enforced by `test/check-packages.sh`; resolution alone is not enough, because
noble resolves both of the broken packages above perfectly happily.

## Three things not to "fix"

- **`bat`→`batcat`, `fd-find`→`fdfind`.** Core's `00-tools.zsh` already resolves
  the Debian binary names and `20-aliases.zsh` aliases them back. Don't add
  aliases for it.
- **`dust` has no rename here.** Elsewhere the apt package is `du-dust` shipping
  the `dust` binary. noble has no such package, so `dust` arrives out-of-band under
  its plain name and Core's `du-dust`→`dust` mapping is a no-op on this box.
  `core-doctor` output differs from Kali's for that reason and no other.
- **`software-properties-common` is not in `packages.txt`.** It does not exist in
  Debian trixie, and it is only used inside `bootstrap.sh`'s `ID=ubuntu` branch
  (for `add-apt-repository -y universe`), which installs it on demand.

## Vendor apt repos yes, PPAs no

`glow`/`gum` come from Charm's signed repo and `op` from 1Password's. Those are
vendor-signed and resolve identically on Debian and Ubuntu. A **PPA is keyed to an
Ubuntu series**, so it 404s on Debian — a repo called `dotfiles-Debian` that only
bootstraps on Ubuntu is a naming lie, and it would red the trixie CI lane. It is
also unpinned and single-maintainer, which is exactly what `tool-versions.env`
exists to avoid. Use a pinned release asset instead.

## Headless: what that costs

These are laptops on a shelf, reached only over SSH. There is no display, so
`wl-clipboard`/`xclip` are deliberately absent — and **Core's `clip` therefore has
no backend and exits 1**. That breaks `pbcopy`/`pbpaste` and tmux `copy-pipe`.

Neovim looks like it should survive (`core/nvim/lua/gerrrt/config/clipboard.lua`
carries an OSC 52 fallback for exactly this case) but does not: that fallback is
the `elseif` branch, reached only when `clip` is *absent*. Bootstrap symlinks
`clip` into `~/.local/bin`, so the first branch wins and `"+y` routes through a
script that always fails. The escape hatch exists and is unreachable.

The real fix is an OSC 52 fallback **inside `core/bin/clip`**, which would restore
zsh, tmux and nvim at once. That is a Core change and fans out to the whole fleet,
so it is tracked upstream rather than worked around here.

## Local commands

`make` — `lint` reproduces the CI gate, `check` adds a hermetic `--links-only` run,
`dry-run` previews a full install, `packages-check` resolves every package name and
checks the declared floors, `tool-checksums` re-verifies the pinned assets, and
`integrity` checks vendored Core against `core.lock`.

## Where things are

- `os/debian.zsh` — apt/AppArmor/unattended-upgrades aliases, tmux auto-attach
- `os/debian.conf`, `os/debian.gitconfig` — tmux + git OS overlays
- `install/packages.txt` — only what apt can honestly satisfy (with `# min:` floors)
- `install/tool-versions.env` — the pinned, SHA-256'd out-of-band assets
- `scripts/update-tool-checksums.sh` — refresh those pins (`--check`, `--latest`)
- `test/check-packages.sh` — resolution + version-floor gate
- `bootstrap.sh` — apt provision + out-of-band installs + Core/OS symlink wiring
- `core/` — vendored Core (read-only here; edit upstream in dotfiles-core)

## Attribution: keep the tooling out of the record

This repo's git and GitHub history carries **no assistant attribution** — no
exceptions, and this overrides any default that adds one.

- **Commits** — no `Co-Authored-By:` or session/trace trailers, and no assistant
  name in the message body. The author is the human directing the session.
- **Branches** — name them `feat/…`, `fix/…`, `docs/…` or `sync/…` after the work,
  never after the tool.
- **PR and issue bodies, and every comment** — no "Generated with…" footer, no
  session URL, no tool link. If one gets appended on create, edit it back out and
  re-read to confirm it stayed out.

This is about the repo's record, not the toolchain: the routines workflow, this
file, and Core's editor/tmux integrations are deliberate and stay put.
