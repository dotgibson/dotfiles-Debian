# CLAUDE.md — dotfiles-Debian

Project memory for Claude Code, auto-loaded every session. For the shared Core
rules (the load order, the "is it Core?" test, the manifest contract) see
`core/README.md` and `core/CONTRIBUTING.md`.

## What this repo is

`dotfiles-Debian` is the **OS-native layer for the Debian family** in an
**eleven-repo dotfiles system** built on a three-layer model (Core → OS-native →
Role). Structurally it is stamped from the Fedora template (see
`core/PORTING-MATRIX.md`); its apt idioms came from `dotfiles-Offense` (formerly
`dotfiles-Kali`), which has since handed its whole OS-native layer over to this
repo on the way to becoming a pure Role layer.

**Three targets, and they do not share an archive age:**

| target | archive | role here |
| ------ | ------- | --------- |
| **Ubuntu 24.04 LTS (noble)** | frozen April 2024 | the primary; headless SSH-only boxes |
| **Debian trixie** | stable | proves the repo's name is not a lie |
| **Kali rolling** | tracks sid | the box `dotfiles-Offense` stacks on, usually under WSL2 |

That spread is the single most important thing to hold in your head here. Most of
this repo exists to work around a **frozen** archive; Kali has none of that problem
and a dozen of those workarounds are wrong there. Hence the distro tier below.

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
from `noble` or present at a version Core cannot use — **on noble and trixie.
Kali has almost all of them in apt**, which is what `install/packages.txt`'s
`# only:kali` annotations are for (see "The distro tier" below):

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

## The distro tier: one manifest, three archives

`install/packages.txt` is read through `scripts/pkg-filter.sh` before Core's
`blib_read_pkgs` ever sees it. The grammar lives inside the existing trailing
comment, so an unannotated line — most of the file — behaves exactly as it always
did:

```text
name                     # applies to all three targets
name    # only:kali      # ONLY these /etc/os-release IDs
name    # skip:ubuntu    # everywhere EXCEPT these
name    # only:kali,debian
```

Fifteen names carry `# only:kali`: the tools noble cannot supply and this repo
therefore fetches as pinned tarballs, `go install`s or vendor-repo packages, all of
which Kali just has. **On Kali they come from apt and the out-of-band fetch skips
itself** — no conditional exists for that, and none is needed: `provision()` installs
the apt list first and every out-of-band install is already `command -v`-guarded.
That ordering is load-bearing and `make apt-first` enforces it.

Two rules worth internalising before editing that file:

- **Repeat the `# min:` floor on a tiered line.** A floor states what *Core* needs,
  not how old an archive is. `neovim` below 0.12 breaks Core's pinned
  nvim-treesitter whether it came from a frozen suite or a rolling one, so tiering
  it in without `min:0.12.0` swaps a known-good pinned 0.12.4 for whatever apt has.
- **`test/check-packages.sh` applies the same tier**, including in the floor loop.
  It has to: `neovim min:0.12.0` evaluated on noble finds 0.9.5 and reports a
  real-looking breach, reddening the lane it exists to certify.

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

- `os/debian.zsh` — apt/AppArmor/unattended-upgrades aliases, tmux auto-attach, WSL2 bits
- `scripts/pkg-filter.sh` — the distro tier for `install/packages.txt` (see above)
- `wsl/` — `wsl.conf` (distro-side, installed by bootstrap when on WSL) and
  `windows.wslconfig.example` (Windows-side; `networkingMode=mirrored` cannot be set
  from inside the distro, which is the most common WSL misconfiguration there is)
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
