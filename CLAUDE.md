# CLAUDE.md — dotfiles-Debian

Project memory for Claude Code, auto-loaded every session. For the shared Core
rules (the load order, the "is it Core?" test, the manifest contract) see
dotfiles-core's [`README.md`](https://github.com/dotgibson/dotfiles-core/blob/main/README.md) and
[`CONTRIBUTING.md`](https://github.com/dotgibson/dotfiles-core/blob/main/CONTRIBUTING.md) — upstream, not in `core/`, which
vendors only what a machine actually runs.

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
itself** — no distro conditional exists for that, and none is needed: `provision()`
installs the apt list first and every out-of-band install is guarded by
`have_current_tool`. That ordering is load-bearing and `make apt-first` enforces it.

**The guard is version-aware, and has to be.** A bare `command -v` cannot tell a
sid-fresh `neovim` 0.12.4 from noble's 0.9.5, and on this family that is the whole
difference. A stray apt `neovim` — hand-installed, or predating the tier — answered
the old guard, so the pinned 0.12.4 was never fetched, `~/.local/opt` was never
created, and bootstrap printed *complete* over a box whose editor died at startup on
`winborder`. `scripts/tool-floor.sh` now compares the installed version against the
declared `# min:` floor: **too old installs the pin anyway and says so; new enough is
still a pure no-op.** Keep both directions — `test/check-tool-floors.sh` gates them.

Three rules worth internalising before editing that file:

- **Repeat the `# min:` floor on a tiered line.** A floor states what *Core* needs,
  not how old an archive is. `neovim` below 0.12 breaks Core's pinned
  nvim-treesitter whether it came from a frozen suite or a rolling one, so tiering
  it in without `min:0.12.0` swaps a known-good pinned 0.12.4 for whatever apt has.
  It has a second consumer now: drop the floor and bootstrap's guard goes blind again.
- **`test/check-packages.sh` applies the same tier**, including in the floor loop.
  It has to: `neovim min:0.12.0` evaluated on noble finds 0.9.5 and reports a
  real-looking breach, reddening the lane it exists to certify.
- **`bootstrap.sh` does the exact opposite — it reads floors UNFILTERED.** Both are
  right. The tier decides *who installs the name from apt*; the floor states what
  Core needs on every target. `neovim min:0.12.0` sits on an `# only:kali` line and
  must still be legible on ubuntu, because that is where it decides to fetch the
  tarball. Filter it there and the guard is blind again.

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

## Headless: what that costs — and what it no longer costs

**On noble and trixie** these are laptops on a shelf, reached only over SSH, so
`wl-clipboard`/`xclip` are deliberately absent — there is no display for them to
talk to. That is an ubuntu/debian fact, not a family one: `install/packages.txt`
tiers both in with `# only:kali`, because Kali runs under WSL2 with WSLg, where
`clip` execs `clip.exe` long before any of this applies.

**Copy works.** Core's `clip` detects WSL → macOS → Wayland → X11 and, finding
none, falls back to **OSC 52** (Core v4.13.0) — the escape sequence puts the
payload on the clipboard of the machine you are sitting at, with nothing installed
on the remote end. `pbcopy`, tmux `copy-pipe` and nvim's `"+y` all work over plain
SSH because of it. `copy-pipe` needed its own server-side `tmux load-buffer -w -`
arm (dotgibson/dotfiles-core#525): tmux runs that child under the daemonized
server, which has no controlling terminal to write the sequence to.

Two limits are real and are stated at `core/zsh/50-op.zsh:64-76`: a terminal may
**silently refuse** the write (so "sent" is the strongest true claim), and under
tmux with `set-clipboard on` the payload **also** lands in a tmux paste buffer,
readable by anything that can reach the socket — which is why `optoken`'s
"never touches your history" rationale has a hole in it (dotgibson/dotfiles-core#690).

**Paste does not, by design.** `clip-paste` has no OSC 52 counterpart because
reading means querying the terminal for a reply most refuse to send and some never
answer — a paste that hangs is worse than one that fails. It says so and exits 1;
`pbpaste` and `"+p` go with it. Use the terminal's own paste. See the README's
*Headless clipboard* note for the full account.

**Do not "fix" nvim.** `core/nvim/lua/gerrrt/config/clipboard.lua`'s OSC 52 branch
is an `elseif` reached only when `clip` is *absent*, and bootstrap puts `clip` on
PATH — so it never runs here. That is correct, not a bug: the first branch is the
one carrying the fallback. The file says so at its own `elseif`; the reverse
assumption costs an afternoon.

## Local commands

`make` — `lint` reproduces the CI gate, `check` adds a hermetic `--links-only` run,
`dry-run` previews a full install, `packages-check` resolves every package name and
checks the declared floors, `tool-floors` proves the presence guard still honours
them in both directions, `tool-checksums` re-verifies the pinned assets, and
`integrity` checks vendored Core against `core.lock`.

## Where things are

- `os/debian.zsh` — apt/AppArmor/unattended-upgrades aliases, tmux auto-attach, WSL2 bits
- `scripts/pkg-filter.sh` — the distro tier for `install/packages.txt` (see above)
- `scripts/tool-floor.sh` — `have_current_tool`, the version-aware presence guard
- `wsl/` — `wsl.conf` (distro-side, installed by bootstrap when on WSL) and
  `windows.wslconfig.example` (Windows-side; `networkingMode=mirrored` cannot be set
  from inside the distro, which is the most common WSL misconfiguration there is)
- `os/debian.conf`, `os/debian.gitconfig` — tmux + git OS overlays
- `install/packages.txt` — only what apt can honestly satisfy (with `# min:` floors)
- `install/tool-versions.env` — the pinned, SHA-256'd out-of-band assets
- `scripts/update-tool-checksums.sh` — refresh those pins (`--check`, `--latest`)
- `test/check-packages.sh` — resolution + version-floor gate (what apt offers)
- `test/check-tool-floors.sh` — the presence guard's gate (what is already installed);
  `provision()` is run by no CI lane, which is how the blind guard shipped green
- `bootstrap.sh` — apt provision + out-of-band installs + Core/OS symlink wiring
- `core/` — vendored Core (read-only here; edit upstream in dotfiles-core)

## Attribution: keep the tooling out of the record

This repo's git and GitHub history carries **no assistant attribution** — one
narrow exception, spelled out below; otherwise this overrides any default that adds
one.

- **Commits** — no `Co-Authored-By:` or session/trace trailers, and no assistant
  name in the message body. The author is the human directing the session.
- **Branches** — name them `feat/…`, `fix/…`, `docs/…` or `sync/…` after the work,
  never after the tool.
- **PR and issue bodies, and every comment** — no "Generated with…" footer, no
  session URL, no tool link, save the one automated-reply marker carved out below.
  Everywhere else: if one gets appended on create, edit it back out and re-read to
  confirm it stayed out.

**The exception: automated review-thread replies.** When a reply goes onto a PR
review thread *from the automation itself* — the Autofix / CI-monitor flow answering
a reviewer with no human reading the thread — it ends with exactly this line and
nothing else:

```text
_🤖 Addressed by [Claude Code](https://claude.com/claude-code)_
```

That is **disclosure, not credit**, which is why it bends a rule the rest of the
record does not. A reviewer is owed the fact that the thing answering them was a
machine, and they cannot infer it from a reply that reads like a colleague's — the
marker buys back the transparency the no-attribution rule would otherwise cost
someone who is not in this repo. Everything the rule protects is authorship of the
*record*; a thread reply is correspondence, and correspondence is where saying who
is talking matters most.

Scope it exactly: the carve-out is that one line, on that one kind of comment. It
does not reach commit trailers, branch names, PR or issue bodies, review summaries,
or a comment written while the human is in the loop — and a human-in-the-loop reply
needs no marker, because there is a person accountable for it. If you cannot tell
which you are doing, you are in the loop: leave it off.

This is about the repo's record, not the toolchain: the routines workflow, this
file, and Core's editor/tmux integrations are deliberate and stay put.
