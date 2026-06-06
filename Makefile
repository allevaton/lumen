# lumen — dev & install shortcuts
#
# Binaries install to $(CARGO_HOME)/bin (defaults to ~/.cargo/bin), which must be
# on your PATH. For fish that's a one-time: `fish_add_path ~/.cargo/bin`.

# Pass extra cargo flags via FLAGS, e.g. `make install FLAGS=--no-default-features`
FLAGS ?=

.DEFAULT_GOAL := build

.PHONY: build release install reinstall uninstall run test lint fmt fmt-check check clean help

build: ## Debug build
	cargo build $(FLAGS)

release: ## Release build (LTO, slow)
	cargo build --release $(FLAGS)

install: ## Build (release) and install `lumen` to ~/.cargo/bin
	cargo install --path . $(FLAGS)

reinstall: ## Force-reinstall over an existing version
	cargo install --path . --force $(FLAGS)

uninstall: ## Remove the installed `lumen` binary
	cargo uninstall lumen

run: ## Run the TUI against the current repo (make run ARGS="diff")
	cargo run -- $(ARGS)

test: ## Run the test suite
	cargo test $(FLAGS)

lint: ## Clippy across all targets
	cargo clippy --all-targets $(FLAGS)

fmt: ## Format the codebase
	cargo fmt

fmt-check: ## Verify formatting without writing
	cargo fmt --check

check: fmt-check lint test ## Pre-commit gate: fmt + clippy + tests

clean: ## Remove build artifacts
	cargo clean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
