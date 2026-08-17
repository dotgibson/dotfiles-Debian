# Changelog

All notable changes to **dotfiles-Debian** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
repo uses [Conventional Commits](https://www.conventionalcommits.org/). Release tags are
cut by the `auto-tag` workflow when a Core sync lands.

Changes to `core/` are **not** listed here — they arrive as Core releases; see
[`core/CHANGELOG.md`](core/CHANGELOG.md) and the `core_version` in `core.lock`.

## [Unreleased]

### Added

- Initial `dotfiles-Debian` OS-native layer: the Debian-family repo the fleet had
  planned, cancelled, and left a note against in `dotfiles-core/scripts/os-repos.txt`.
  Targets **Ubuntu 24.04 LTS** on headless SSH-only machines; `debian:trixie` is a
  blocking CI lane because the repo is named for the family, not one distro.
- `install/tool-versions.env` — version + SHA-256 pins for the twelve tools a frozen
  LTS cannot supply, with `scripts/update-tool-checksums.sh` to refresh them
  (`--check` to assert, `--latest` to report newer upstream releases).
- `test/check-packages.sh` — resolves every manifest name with
  `apt-get install --simulate` (apt's real resolver, unlike `apt-cache`, which exits 0
  on unknown names and non-zero on installable virtual ones) **and** enforces the
  `# min:X.Y.Z` version floors declared in `install/packages.txt`. Wired to
  `make packages-check` and the `packages` workflow.
- `verified_tree_install` alongside `verified_install` in `bootstrap.sh`. Neovim ships
  a directory tree (`bin/`, `lib/`, `share/nvim/runtime`), not a lone binary — copying
  just `bin/nvim` yields an editor whose `$VIMRUNTIME` points at nothing.
- `verified_install` handles all three shapes upstreams actually ship — `.tar.gz`,
  plain `.gz` (tree-sitter) and `.zip` (procs) — and takes an optional inner-binary
  name for assets whose executable is named differently from the command.

### Notes on what is deliberately absent

- `neovim` and `tree-sitter-cli` are **not** in `install/packages.txt`. Ubuntu 24.04
  resolves both (0.9.5 and 0.20.8) and both are far below what Core requires (0.12 and
  0.26.1) — which is exactly why the version-floor check exists; resolution alone would
  have called that box healthy.
- `yq` in either spelling: noble's `yq` is kislyuk's Python tool, and the Go `yq-go`
  this stack means is sid-only. Installed via `go install` instead.
- `cargo`, and therefore `yazi`/`ast-grep`/`viddy`: noble's rustc is 1.75, too old to
  build them. All are `HAVE_*`-guarded in Core, so the shell degrades cleanly.
- `wl-clipboard`/`xclip`: no display on these boxes. This leaves Core's `clip` without
  a backend — see the README's *Headless clipboard* note for the OSC 52 fix, which
  belongs upstream in `dotfiles-core`.
- PPAs, in any form. They are keyed to an Ubuntu series and would break the Debian
  lane; vendor-signed apt repos (Charm, 1Password) are used instead.

### Fixed

- `make zsh-syntax` printed "zsh not installed — skipping" and then ran `zsh -n`
  anyway. Each `make` recipe line runs in its own shell, so the guard's `exit 0` only
  ended that line. The same shape is still present in the other OS repos' Makefiles.
