# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`lumen` is a fast terminal diff viewer and code-review TUI written in Rust, plus a set of AI-assisted git commands (commit messages, diff explanations, git-command generation). It ships as a single static binary and works with both Git and Jujutsu (jj).

This checkout is a **personal fork** (`origin` = `allevaton/lumen`, `upstream` = `jnsahaj/lumen`). Day-to-day work happens on the `local` branch; `main` tracks upstream. See "Fork maintenance" below.

## Commands

Prefer the `Makefile` targets — they wrap the cargo commands below and add install/check helpers. Run `make help` to list them.

```bash
make build                        # debug build (default goal)
make release                      # release build (LTO enabled, slow)
make run ARGS="diff"              # run the TUI against the current repo's uncommitted changes
make test                         # run the test suite
make lint                         # clippy across all targets
make fmt                          # format
make check                        # pre-commit gate: fmt-check + clippy + tests
make install                      # build (release) and install `lumen` to ~/.cargo/bin
```

Pass extra cargo flags via `FLAGS`, e.g. `make test FLAGS=--no-default-features`. Raw cargo still works for cases the Makefile doesn't cover:

```bash
cargo test <name>                 # run tests matching a substring (e.g. cargo test parse_pr)
cargo test --no-default-features  # build/test without the jj backend (jj is a default feature)
```

The `jj` feature is **on by default** and pulls in `jj-lib`, `chrono`, `pollster`, `futures`. Use `--no-default-features` (or `FLAGS=--no-default-features`) to confirm a change still compiles without it.

## Architecture

Entry point is `src/main.rs`: it parses the CLI (`clap`), builds a `LumenConfig`, constructs a `LumenProvider` (AI), auto-detects the VCS backend, then dispatches one of the subcommands. The codebase has two largely independent halves:

**1. The diff TUI** (`src/command/diff/`) — the bulk of the code (~14k lines). A `ratatui`/`crossterm` application.
- `mod.rs` — entry (`run_diff_ui`), `DiffOptions`, GitHub PR resolution/parsing, viewed-file tracking.
- `app.rs` — the main event loop, terminal setup, input handling. Note `open_tui_writer()`: when stdout is captured (e.g. an agent runs `output=$(lumen diff)`), the TUI is driven via `/dev/tty` so stdout stays reserved for the annotation payload.
- `state.rs` / `types.rs` — `AppState` and the core enums (selection modes, panel focus, cursor position, etc.).
- `render/` — drawing: `diff_view.rs` (side-by-side panes), `sidebar.rs`, `footer.rs`, `modal.rs`.
- `highlight/` — tree-sitter syntax highlighting. `queries.rs` holds per-language highlight queries; languages are registered in `config.rs`. Adding a language means adding the `tree-sitter-*` crate to `Cargo.toml` and wiring it here.
- `theme.rs`, `coordinates.rs`, `diff_algo.rs` (uses `similar`), `search.rs`/`global_search.rs`, `sticky_lines.rs`, `watcher.rs` (file-watch for `--watch`), `annotation.rs` (the review-annotation feature).
- `context.rs` (context-line expansion via tree-sitter), `git.rs` (the GitHub/`git`/`gh` shell-out helpers referenced below), `text_edit.rs` (shared single-line input editing — `opt+backspace`/`^W` word-delete used by every text field).

**2. AI commands** (`src/command/`) — `explain`, `draft` (commit message), `operate` (generate git commands), `list`, `configure`. Each is a small module with an `execute(&provider, ...)` method dispatched through `CommandType` in `command/mod.rs`. Prompts live in `src/ai_prompt.rs`.

**Cross-cutting layers:**
- `src/vcs/` — VCS abstraction. `VcsBackend` trait (`backend.rs`) with `GitBackend` (`git.rs`, libgit2 via `git2`) and `JjBackend` (`jj.rs`) implementations. `get_backend()` (`mod.rs`, detection logic in `detection.rs`) auto-detects, **preferring jj when both are present** (colocated repos). All command code should go through the `VcsBackend` trait, not call git directly — except for a few GitHub-specific helpers in `command/diff/` that shell out to `git`/`gh`.
- `src/provider/` — AI provider abstraction over the `genai` crate. Supports openai, groq, claude, ollama, deepseek, gemini, xai, plus custom-endpoint providers (opencode-zen, openrouter, vercel) configured via `CustomProviderConfig`.
- `src/config/` — `cli.rs` (clap definitions, `ProviderType` parsing), `configuration.rs` (`LumenConfig`, merges env + config file + CLI flags), `providers.rs` (provider metadata). Config can come from a `lumen.config.json` file; precedence is documented in the README.
- `src/git_entity/` — `GitEntity` (a `Commit` or a `Diff`) is the unit AI commands operate on. `src/commit_reference.rs` (top-level, not in this dir) parses the various reference forms (`HEAD~1`, `main..feature`, `a...b`, `from..` working-tree).

## Conventions

- Tests are colocated in `#[cfg(test)] mod tests` blocks within their module (not a separate `tests/` dir). `src/vcs/test_utils.rs` provides helpers for spinning up temp git repos.
- Errors funnel into `LumenError` (`src/error.rs`); sub-systems define their own `thiserror` enums (`ProviderError`, `VcsError`) that convert into it.
- When adding a syntax-highlighted language, the `tree-sitter-*` grammar crate must be ABI-compatible with the `tree-sitter` 0.24 core (grammar crate versions vary — 0.23/0.24/0.3 — so pin by what compiles against the core, not by matching version numbers). ABI mismatches are the usual cause of highlight build failures.

## Fork maintenance

`scripts/sync-fork.sh` (run from your work branch, e.g. `local`) fetches `upstream`, fast-forwards `main` to `upstream/main`, pushes `main` to `origin`, then rebases your current branch onto `main`. It bails if `main` has diverged or the working tree is dirty. After it runs, update the remote branch with `git push --force-with-lease origin <branch>`.
