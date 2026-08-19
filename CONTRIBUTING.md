# Contributing to dotfiles-Debian

This is the **OS-native layer for the Debian family** in a three-layer dotfiles system, and the
template the other Linux repos are stamped from. The contribution rules are therefore
mostly *boundary* rules: the hard part is not writing the change, it is knowing which
repo it belongs in.

GitHub resolves `CONTRIBUTING.md` from the repo root, `.github/`, or `docs/` — the
vendored `core/CONTRIBUTING.md` governs `dotfiles-core` and is inert here.

## The rule that bites: never hand-edit `core/`

`core/` is a **vendored `git subtree` copy** of
[`dotfiles-core`](https://github.com/dotgibson/dotfiles-core). It is overwritten on the
next sync, so an edit there is silent drift: it works until a sync clobbers it, and it
never reaches the source of truth.

To change shared config: edit it **in `dotfiles-core`**, run `make audit` there, then
`make sync` to fan it out to every OS repo.

Three things enforce this, deliberately overlapping:

1. A local `pre-commit` hook installed by `bootstrap.sh` (`blib_install_core_guard`).
2. The `core-integrity` workflow, which compares your `HEAD:core` **git tree object**
   against the SHA recorded in `core.lock` — so any byte-level change is caught at PR time.
3. `CODEOWNERS`, which routes `core/` diffs to the maintainer.

## Which layer does my change belong to?

| If the change… | It belongs in |
| --- | --- |
| is identical on every machine (zsh, tmux, nvim, git, starship) | `dotfiles-core` |
| changes with the **OS** (package manager, clipboard, paths, AppArmor) | **here** |
| changes with the **operator** (offensive/defensive tooling) | `dotfiles-Offense` / `dotfiles-Defense` |

Structural changes to the OS-native layout start in **dotfiles-Fedora**, the template,
and propagate per [`core/PORTING-MATRIX.md`](core/PORTING-MATRIX.md). If your fix to
`bootstrap.sh` would be identical on Arch and openSUSE, that is a strong signal it
belongs in `core/lib/bootstrap-lib.sh` upstream instead.

One judgement call is specific to this repo: **does a tool belong in
`install/packages.txt` or in `bootstrap.sh`?** It belongs in the manifest only if apt
resolves it *at a version Core can use*, **on the distro you annotate it for**. A name
with no `# only:` / `# skip:` marker is claimed for all three targets, so it must resolve
on noble, trixie AND kali-rolling. Ubuntu 24.04 is frozen, so "apt has it" is not
the same question as "apt has a usable one" — `neovim` and `tree-sitter-cli` both
resolve and both break the stack. Declare a floor (`# min:X.Y.Z`) when it matters, and
move anything below it into `bootstrap.sh` as a pinned `verified_install`.

## Local development

```bash
make help          # list every target
make lint          # shellcheck + bash -n + zsh -n, exactly as CI runs them
make check         # lint + a hermetic --links-only run in a throwaway HOME
make dry-run       # preview the full bootstrap plan; changes nothing
make hooks         # install the pre-commit hooks (needs `pre-commit`)
```

`make lint` is the gate. Green it before you push — CI runs the same checks via the
reusable workflow in `dotfiles-core`, plus `actionlint` on the workflows.

The vendored `core/` is **excluded** from this repo's linting: it is gated upstream by
`dotfiles-core`'s own `make audit`.

## Pull requests

`main` is protected: PRs are required, and the `lint`, `bootstrap`, and `core-integrity`
checks must pass.

- Branch names: `fix/…`, `feat/…`, `docs/…`, `chore/…`, or `sync/…` after the work.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `type(scope): summary` — e.g. `fix(bootstrap): resolve the escalator once`.
- A user-visible change gets a `CHANGELOG.md` entry under `[Unreleased]` in the same commit.
- Keep the reasoning. This codebase deliberately carries long comments explaining *why* a
  guard exists (which archive actually has the package, which keyring apt consults). If you
  change such a line, update the comment with it — those comments are the record of bugs
  that already cost someone an afternoon.

## Testing a bootstrap change

`bootstrap.sh` is the one file that can strand a fresh machine, so it gets the most care:

```bash
make lint                      # shellcheck -x, bash -n, --help
make dry-run                   # full plan, mutates nothing
make check                     # hermetic --links-only against a throwaway HOME
```

If you have a container runtime, the closest thing to a fresh box — and the case that
regressed most often — is a **root** run with no `sudo` present:

```bash
podman run --rm -v "$PWD:/repo" -w /repo ubuntu:24.04 bash -c './bootstrap.sh --links-only'
```

Re-run any full bootstrap **twice** and confirm the second run re-downloads nothing: the
presence guards in front of every `verified_install` are easy to break in a way that
silently costs bandwidth and minutes per run.

Two package-level gates back that up:

```bash
make packages-check            # every name resolves, and clears its declared floor
make tool-checksums            # every pinned asset still hashes to its pin
```

## Reporting bugs

Open an [issue](https://github.com/dotgibson/dotfiles-Debian/issues). Security problems
go through [`SECURITY.md`](SECURITY.md) instead — please don't file those publicly.
