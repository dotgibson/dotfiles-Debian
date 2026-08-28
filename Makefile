# Makefile — a discoverable façade over this repo's entry points.
# ──────────────────────────────────────────────────────────────────────────────
# Deliberately thin: it adds almost no logic beyond what CI already runs, so `make lint`
# == the reusable lint gate in dotfiles-core, and a green `make lint` means a green PR.
#
# ONE deliberate exception, `trap-guard`. CI's bootstrap job only ever runs --links-only,
# so provision() — the entire out-of-band install path — is executed by NO gate anywhere,
# which is how a leaked RETURN trap that aborted every real run shipped green. The guard
# is STRICTER than the reusable workflow, never looser, so "green here means green there"
# still holds in the direction that matters. Getting it into CI proper is a dotfiles-core
# change; until then the pre-commit hook is what actually blocks the commit.
#
# NOT to be confused with core/Makefile — that is *dotfiles-core's* Makefile, which
# arrives with the vendored subtree. Its `audit` / `sync` / `release` targets operate on
# the Core repo and are meaningless from this vendored copy. This file is the entry point
# for THIS repo.
#
# The vendored core/ is excluded from every check here: it is gated upstream.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY: help lint shellcheck syntax zsh-syntax trap-guard markdown check dry-run links-only packages-check tool-checksums integrity hooks clean capabilities

# Repo-owned shell only — core/ is gated upstream. Mirrors the reusable gate's
# `git ls-files '*.sh' ':!:core/**'`.
SH_FILES  := $(shell git ls-files '*.sh' ':!:core/**' 2>/dev/null)
ZSH_FILES := $(shell git ls-files '*.zsh' ':!:core/**' 2>/dev/null)

help: ## Show this help
	@echo "dotfiles-Debian — make targets:"
	@grep -E '^[a-z][a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: shellcheck syntax zsh-syntax trap-guard apt-first capabilities ## The gate: shellcheck + bash -n + zsh -n + trap discipline + apt ordering
	@printf '\033[32m✓\033[0m lint clean\n'

shellcheck: ## ShellCheck the repo-owned bash (excludes the vendored core/)
	@command -v shellcheck >/dev/null 2>&1 || { \
	  if [ "$$(id -u 2>/dev/null)" = 0 ]; then p=""; elif command -v sudo >/dev/null 2>&1; then p="sudo "; else p="<as root> "; fi; \
	  echo "shellcheck not installed: $${p}apt-get install -y shellcheck"; exit 1; }
	@test -n "$(SH_FILES)" || { echo "no repo-owned .sh"; exit 0; }
	@echo "shellcheck -x $(SH_FILES)"
	@shellcheck -x $(SH_FILES)

syntax: ## bash -n the repo-owned bash, and check --help still works
	@test -n "$(SH_FILES)" || { echo "no repo-owned .sh"; exit 0; }
	@for f in $(SH_FILES); do echo "bash -n $$f"; bash -n "$$f" || exit 1; done
	@bash bootstrap.sh --help >/dev/null || { echo "bootstrap.sh --help failed"; exit 1; }

zsh-syntax: ## zsh -n the repo-owned zsh modules (shellcheck has no zsh mode)
	@# ONE recipe line, deliberately. make runs each line in its own shell, so the
	@# `exit 0` in a multi-line version only ends THAT line — the guard printed
	@# "skipping" and then the next line ran `zsh -n` anyway and failed. Joining them
	@# makes the skip a real skip. (Inherited from the template's Makefile; the same
	@# shape is still in the other OS repos' copies.)
	@if ! command -v zsh >/dev/null 2>&1; then echo "zsh not installed — skipping"; \
	elif test -z "$(ZSH_FILES)"; then echo "no repo-owned .zsh"; \
	else for f in $(ZSH_FILES); do echo "zsh -n $$f"; zsh -n "$$f" || exit 1; done; fi

trap-guard: ## Refuse a RETURN trap that does not disarm itself (shellcheck cannot see this)
	@# A bash RETURN trap is a GLOBAL slot, not a function-scoped one: arm it inside a
	@# function and it stays armed in the CALLER's frame, firing a second time when the
	@# caller returns — by which point the local it cleans up is out of scope and `set -u`
	@# kills the script. That is invisible to shellcheck, to `bash -n`, and to every CI
	@# job here (all of which run --links-only and never enter provision). Hence a grep.
	@#
	@# RETURN is matched as a SIGNAL TOKEN — followed by whitespace or end-of-line — not
	@# only as the last word. Anchoring it to end-of-line let `trap '...' RETURN  # note`
	@# and `trap '...' RETURN EXIT` through, and both leak exactly the same way.
	@test -n "$(SH_FILES)" || exit 0
	@if grep -nE "^[[:space:]]*trap[[:space:]].*[[:space:]]RETURN([[:space:]]|$$)" $(SH_FILES) | grep -v 'trap - RETURN'; then \
	  echo "^ a RETURN trap must disarm itself:  trap 'trap - RETURN; …' RETURN"; \
	  echo "  Otherwise it leaks into the caller's frame and fires again on ITS return."; \
	  exit 1; \
	fi
	@printf '\033[32m✓\033[0m RETURN traps disarm themselves\n'

apt-first: ## Refuse an out-of-band install that could run BEFORE the apt base list
	@# THE INVARIANT: provision() installs install/packages.txt first, and every
	@# out-of-band install (verified_install / verified_tree_install / go install /
	@# vendor apt repo) after it. Each of those is guarded by `command -v <binary>`,
	@# so on a distro where apt already supplied the tool the guard fires and the
	@# download is skipped. That guard is the ENTIRE mechanism behind the `# only:kali`
	@# tier in install/packages.txt — Kali's archive tracks sid and has neovim,
	@# starship, lazygit and friends, so apt lands them and the pinned fetch no-ops.
	@#
	@# Reorder those two blocks and nothing errors: the guards simply all miss, every
	@# tool is fetched out-of-band as well as from apt, and Kali quietly ends up with
	@# a pinned tarball shadowing its distro build. No lint sees that, and no CI job
	@# here does either — they run --links-only and never enter provision(). Hence a
	@# line-number check, in the same spirit as trap-guard above.
	@base=$$(grep -n 'apt_install "$${base\[@\]}"' bootstrap.sh | head -1 | cut -d: -f1); \
	if [ -z "$$base" ]; then \
	  echo "apt-first: could not find the base apt_install line in bootstrap.sh"; exit 1; \
	fi; \
	bad=$$(grep -nE '^[[:space:]]*(verified_install|verified_tree_install|_dotfiles_go_install|_add_vendor_repo) ' bootstrap.sh \
	      | awk -F: -v b="$$base" '$$1 < b { print }'); \
	if [ -n "$$bad" ]; then \
	  echo "$$bad"; \
	  echo "^ these run BEFORE apt_install of the base list (line $$base)."; \
	  echo "  Their 'command -v' guards would then always miss, so the '# only:kali'"; \
	  echo "  tier in install/packages.txt would double-install instead of skipping."; \
	  exit 1; \
	fi; \
	printf '\033[32m✓\033[0m out-of-band installs all follow the apt base list (line %s)\n' "$$base"

markdown: ## markdownlint the repo-owned docs (shares .markdownlint.jsonc with Core)
	@command -v markdownlint-cli2 >/dev/null 2>&1 \
		|| { echo "markdownlint-cli2 not installed: npm i -g markdownlint-cli2 — skipping"; exit 0; }
	@markdownlint-cli2 '*.md' '!core/**'

dry-run: ## Preview the FULL bootstrap plan (packages + symlinks); changes nothing
	@./bootstrap.sh --dry-run

links-only: ## Re-wire the symlinks on THIS machine (no apt, no downloads)
	@./bootstrap.sh --links-only

packages-check: ## Do all install/packages.txt names resolve, and clear their version floors?
	@./test/check-packages.sh install/packages.txt

tool-checksums: ## Re-verify the pinned out-of-band assets against install/tool-versions.env
	@./scripts/update-tool-checksums.sh --check

check: lint ## lint + a hermetic --links-only run against a throwaway HOME
	@tmp=$$(mktemp -d); \
	mkdir -p "$$tmp/.config/tmux/plugins/tpm"; \
	echo ":: bootstrap --links-only into $$tmp"; \
	HOME="$$tmp" ./bootstrap.sh --links-only >/dev/null || { echo "bootstrap failed"; rm -rf "$$tmp"; exit 1; }; \
	rc=0; \
	for l in .config/zsh/loader.zsh .config/zsh/80-os.zsh .config/starship.toml \
	         .config/lazygit/config.yml .config/nvim .vimrc .gitconfig; do \
	  test -L "$$tmp/$$l" || { echo "MISSING symlink: $$l"; rc=1; }; \
	done; \
	test -e "$$tmp/.config/zsh/loader.zsh" || { echo "loader.zsh is dangling"; rc=1; }; \
	test -f "$$tmp/.config/sesh/sesh.toml" || { echo "sesh.toml not seeded"; rc=1; }; \
	test -L "$$tmp/.config/sesh/sesh.toml" && { echo "sesh.toml must be a copy, not a link"; rc=1; }; \
	grep -q "dotfiles-managed v4" "$$tmp/.zshrc" || { echo "~/.zshrc not managed"; rc=1; }; \
	grep -q "source .*loader.zsh" "$$tmp/.zshrc" || { echo "~/.zshrc does not source the loader"; rc=1; }; \
	rm -rf "$$tmp"; \
	test $$rc -eq 0 && printf '\033[32m✓\033[0m symlink graph OK\n' || exit 1

integrity: ## Verify the vendored core/ is pristine vs core.lock (needs a sibling dotfiles-core)
	@ref=../dotfiles-core; \
	test -d "$$ref" || { echo "needs a sibling clone of dotfiles-core at $$ref"; echo "(the core_sha in core.lock only resolves in Core's object store — see core.lock)"; exit 1; }; \
	git -C "$$ref" cat-file -e "$$(sed -n 's/^core_sha=//p' core.lock)" 2>/dev/null || { \
	  echo ":: locked core_sha is not in $$ref yet — fetching (a stale reference clone reports"; \
	  echo "   UNVERIFIABLE, which reads like tampering but only means 'fetch Core')"; \
	  git -C "$$ref" fetch --quiet origin || true; }; \
	"$$ref/scripts/core-integrity.sh" --self "$(CURDIR)"

hooks: ## Install the pre-commit hooks into this clone
	@command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit not installed: pip install pre-commit"; exit 1; }
	@pre-commit install
	@echo "run them all with: pre-commit run --all-files"

clean: ## Remove local scratch artifacts (never touches tracked files)
	@find . -name '*.pre-dotfiles.*' -maxdepth 2 -print -delete 2>/dev/null || true

# ── the OS capability declaration (Core v5, #663/#667) ────────────────────────
# ONE definition of the schema gates all seven declaring repos: the validator is
# core/scripts/check-capabilities.sh, vendored with Core, so a schema change arrives
# with the next sync instead of needing seven hand-written greps to be updated in
# step. Core's own `make audit` runs the same script over its shipped example and
# sweeps the fleet for these files; this is the local half of that gate.
#
# The glob is guarded because an unmatched glob stays LITERAL in sh — without the
# test this would "validate" a file named `os/*.capabilities` and pass on nothing,
# which is the failure mode a gate must never have.
capabilities: ## Validate os/*.capabilities against Core's schema
	@rc=0; found=0; \
	for f in os/*.capabilities; do \
	  [ -e "$$f" ] || continue; found=1; \
	  core/scripts/check-capabilities.sh "$$f" --packages install/packages.txt || rc=1; \
	done; \
	if [ "$$found" -eq 0 ]; then echo "!! no os/*.capabilities — this repo must declare one (see core/examples/os.capabilities.example)"; rc=1; fi; \
	exit $$rc

