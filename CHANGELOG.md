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

- **`make test` and `make core-verify`** — the two canonical fleet verbs this repo was
  missing (dotgibson/dotfiles-core#691, reported by dotgibson/dotfiles-core#846's
  register). Core now declares one `make` vocabulary for every repo that vendors it —
  `help`, `lint`, `check`, `dry-run`, `packages-check`, `core-verify`, `test` — after
  nine repos turned out to speak nine dialects, with "verify core" alone spelled five
  ways. `test` runs the repo's own suite, which today is exactly
  `test/check-packages.sh`, so `packages-check` is its only prerequisite rather than a
  copied command line; it is declared `.PHONY` because it names the `test/` directory it
  runs and an undeclared `test:` would report "up to date" and run nothing. The
  requirement is that the canonical name **exists**, not that the old one dies, so
  `integrity` stays as a `.PHONY` alias of `core-verify` and muscle memory survives.
  Verify from a Core checkout beside this one with `make fleet-vocabulary`.

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

- **`bootstrap.sh`'s `PATH` is not the shell's `PATH` — adopt `blib_user_bindirs_on_path`**
  (dotgibson/dotfiles-core#748). Replaces the hand-rolled `export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"` prelude. `~/.local/bin`, `~/.cargo/bin` and `$GOBIN` reach
  `PATH` only through the zsh layer, i.e. only inside a Core shell — which does not exist
  while `bootstrap.sh` runs. So every `command -v <tool>` guard here was answered by the
  PATH of whatever shell launched the bootstrap: on a fresh box, bash, with none of them.
  That is wasted work when the guard picks whether to reinstall, and a **wrong answer** when
  it picks a branch — `dotfiles-openSUSE` probed `command -v mise` for a mise `mise.run` had
  written to `~/.local/bin` moments earlier, both arms of its Go fallback missed, and the run
  exited 2 on every bootstrap. No stubbed CI leg can see that: a stub installs nothing, so
  "is the tool present afterwards" can never fail under one. Core has shipped
  `blib_user_bindirs_on_path` for exactly this since dotgibson/dotfiles-core#425 — it resolves
  `CARGO_HOME` and `GOBIN`/`GOPATH` rather than hard-coding them, and adds only directories
  that **exist**, so it is called again after an installer creates one. The directory this script installs into is `mkdir -p`'d before the helper runs, and the second refresh sits immediately after the `verified_install` block: the helper adds only directories that already **exist**, so a straight swap for the old unconditional `export` would have dropped `~/.local/bin` for the whole first run and made the `command -v uv` (ty route) and `command -v atuin` (daemon unit) probes miss binaries this script had just written. The literal list was a fork of Core's helper and was missing `GOBIN` — harmless only because this script sets it to `~/.local/bin` itself. A second call now runs after the `verified_install` block, which on a first run is what creates `~/.local/bin`.
- **`make check` was not hermetic, and wrote Core into your real config dir
  (dotgibson/dotfiles-core#852).** The target promises "a hermetic `--links-only` run
  against a throwaway HOME" and redirected only `HOME` — but `bootstrap.sh` resolves its
  target as `CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"`, and `core/lib/bootstrap-lib.sh`
  defaults `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME` and
  `ZDOTDIR` the same way. A `:-`/`:=` default applies **only when the variable is unset**,
  so for anyone who exports `XDG_CONFIG_HOME` the run wired Core into their live config
  tree and then failed its own assertions, which look under the temp dir bootstrap never
  touched — a gate that mutates the box it was only supposed to inspect, then blames the
  tree. Reproduced against the byte-identical recipe in `dotfiles-Fedora`
  (dotgibson/dotfiles-Fedora#153); only the package manager differs between the two repos
  here, and the `--links-only` path is the same Core code. Fixed with `env -u` for the
  five variables the bootstrap path consults — the fix `dotfiles-openSUSE` had already
  reached locally.
- **`make check`'s `mktemp -d` was unguarded**, so a failure left `$tmp` empty and the
  next line ran `mkdir -p "$tmp/.config/tmux/plugins/tpm"` — `/.config/…` on the real
  filesystem. It now refuses, and a `trap` replaces the two hand-placed `rm -rf`s so an
  interrupted run cleans up too.
- **`make check` accepted a commented-out loader line.** `grep -q "source .*loader.zsh"`
  matched `# source ~/.config/zsh/loader.zsh`, and its unescaped `.` also matched
  `loaderXzsh`. Now `grep -qE '^[^#]*source .*loader\.zsh'`, and both `~/.zshrc` greps
  are `2>/dev/null` so a missing file reports once instead of twice.

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
