# Changelog

All notable changes to **dotfiles-Debian** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this
repo uses [Conventional Commits](https://www.conventionalcommits.org/). Release tags are
cut by the `auto-tag` workflow when a Core sync lands.

Changes to `core/` are **not** listed here — they arrive as Core releases; see
[dotfiles-core's CHANGELOG](https://github.com/dotgibson/dotfiles-core/blob/main/CHANGELOG.md) and the `core_version` in
`core.lock`.

## [Unreleased]

### Added

- **The canonical fleet `make` verbs: `test` and `core-verify`
  (dotgibson/dotfiles-core#691).** Nine repos had nine dialects — "verify core" had five
  spellings across the fleet, "dry run" two, and only `help` was common to every
  Makefile, so a contributor moving between repos re-learned the verbs each time and no
  gate noticed. `dotfiles-core`'s `scripts/make-vocabulary.txt` now declares the seven
  names once (`help`, `lint`, `check`, `dry-run`, `packages-check`, `core-verify`,
  `test`) and its `make fleet-vocabulary` register reports, per repo, which resolve.
  This repo already had five.
  - `make test` runs this repo's own suite — `test/check-packages.sh` (does every name
    still resolve?) and `test/check-tool-floors.sh` (does the presence guard still refuse
    a too-old apt build?). Both already had their own entry points, `packages-check` and
    `tool-floors`, and keep them; `test` is the fleet-wide name for "run what this repo
    tests". Off apt the first exits 0 with a stated skip, the second is hermetic and runs
    anywhere.
  - `core-verify` is the canonical name for what this repo spelled `integrity`. The
    recipe is unchanged; `integrity` remains as a two-line alias, so anything already
    calling it — muscle memory, a local script, a runbook line — keeps working. The
    requirement is that the canonical name *exists*, not that the old one dies.

- **`os/debian.capabilities` and `os/debian.kali.capabilities`** — this repo's Core v5
  capability declarations (dotgibson/dotfiles-core#663, #667). Core's `up`, maint runner
  and `core-doctor` now dispatch through them. The apt verbs are identical on all three
  targets, so almost everything is shared; **exactly one key differs**, and it is why
  there are two files: Kali does not declare `MAINT_UNATTENDED_UPGRADE`, because
  engagement boxes are updated by hand between ops and a background full-upgrade
  mid-engagement destroys the reproducibility findings rest on. `bootstrap.sh` relinks the
  Kali file over the default, keyed on the **same `$OS_ID`** that `scripts/pkg-filter.sh`
  tiers `install/packages.txt` on — so the declaration and the package list agree by
  construction rather than by coincidence, and a future tier is one new file with no code
  change.
- `TOOLS_OPTIN` declares `jj` and `ast-grep` opt-in on this family — they are `—` on noble
  and trixie and cargo-only on Kali. Core's single list could not say "opt-in there,
  expected here", so `core-doctor` reported them as missing-and-expected on every box
  (dotgibson/dotfiles-core#666). `dust` is deliberately **not** in that list: it is
  present here, just installed out of band under its plain name.
- **`make capabilities`** — validates `os/*.capabilities` against Core's schema via the
  vendored `core/scripts/check-capabilities.sh`, and runs as part of `make lint`.
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
- `wl-clipboard`/`xclip`: no display on these headless ubuntu/debian boxes. Tiered in
  for Kali (`# only:kali`), which runs under WSL2 with WSLg. Copying still works
  regardless: Core's `clip` falls back to OSC 52 when it finds no local backend.
  Pasting does not, deliberately — see the README's *Headless clipboard* note.
- PPAs, in any form. They are keyed to an Ubuntu series and would break the Debian
  lane; vendor-signed apt repos (Charm, 1Password) are used instead.

### Fixed

- `make zsh-syntax` printed "zsh not installed — skipping" and then ran `zsh -n`
  anyway. Each `make` recipe line runs in its own shell, so the guard's `exit 0` only
  ended that line. The same shape is still present in the other OS repos' Makefiles.
- **`make markdown` had the same defect, and it was still live here.** Without a global
  `markdownlint-cli2` it printed "not installed — skipping" and then ran the linter
  anyway, failing with `Error 127`. Collapsed into one recipe line, so the skip is a real
  skip. Of the fleet, `dotfiles-Fedora` carries this target byte-for-byte (also live);
  `dotfiles-Offense` and `dotfiles-Defense` have the same shape guarding `npx` instead
  (latent — it only bites where `npx` is absent); `dotfiles-MacBook` already fixed its
  copy; Alpine, Arch, Gentoo and openSUSE have no markdown target at all.
- **`make markdown` also scanned the wrong files.** It globbed `'*.md'`, which is
  top-level only, while the reusable gate's markdown leg — **blocking** since
  dotgibson/dotfiles-core#592 — lints `git ls-files '*.md' ':!:core/**'`, recursively. The three
  `.github/` markdown files were therefore enforced by a required check and invisible
  locally, so this target could read green against a red PR. It now uses the same
  pathspec via a new `MD_FILES`. All nine files lint clean, so nothing was hiding.
- `.markdownlint.jsonc`'s header claimed the rules were "mirrored from Core rather than
  CI-enforced" and that "lint.yml skips `**.md` entirely". Both were true when written and
  neither survived dotgibson/dotfiles-core#592.
