---
name: Feature request
about: Suggest something for the Debian/Ubuntu layer
title: ''
labels: enhancement
assignees: ''
---

## What & why

<!-- The problem you're trying to solve, not only the solution you have in mind. -->

## Which layer?

- [ ] Genuinely **Debian-family-specific** (apt, vendor apt repos, AppArmor,
      WSL interop) — belongs here.
- [ ] Would be **identical on every distro** — belongs in
      [dotfiles-core](https://github.com/dotgibson/dotfiles-core/issues).
- [ ] Changes with the **operator** (offensive/defensive tooling) — belongs in
      `dotfiles-Kali` / `dotfiles-Defense`.

## If this adds a tool

- Package name on Ubuntu 24.04 (or why it isn't packaged): <!-- `apt-cache policy <pkg>` -->
- If packaged but too old, the candidate version vs what Core needs: <!-- `apt-cache policy` -->
- If not packaged, the install route: pinned release asset / vendor apt repo / go install
- Does Core already probe for it (`core-doctor`)?

> Anything installed outside `apt` is a trust decision that gets recorded in
> [SECURITY.md](../SECURITY.md) — please say which route you'd expect.

## Alternatives considered
