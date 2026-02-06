# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Huginn is a Neovim plugin written in Lua for managing code issues and annotations directly within the editor. Issues are stored as Markdown files in a time-indexed directory structure on the filesystem, with no external dependencies (no GitHub Issues, Jira, etc.). Issues are linked to source code locations via tree-sitter queries, and virtual text annotations mark lines with open issues.

## Commands

### Run tests
```
make test
```
This runs the full test suite in headless Neovim.

### Run a single test module
```
make test-module MODULE=runner
```
The `_test` suffix is optional (`runner` and `runner_test` both work).

### Clean generated files
```
make clean
```
Deletes `.huginnlog` files.

## Architecture

### Layered module structure

```
plugin/huginn.lua                  → Neovim autoload entry point, calls setup()
lua/huginn/init.lua                → Setup, command registration, keymap defaults
lua/huginn/commands/               → Thin command wrappers (create, config, log, huginn_init, show, navigate, home, add_and_remove)
lua/huginn/components/             → UI components (prompt, confirm, log_viewer, issue_window, show_window, home_window, issue_picker)
lua/huginn/modules/                → Core business logic (see below)
lua/huginn/tests/                  → Test suite with custom harness
docs/                             → Specification documents (docs/specs/) and component docs (docs/components/)
```

### Core modules (`lua/huginn/modules/`)

- **context.lua** — Singleton state container. Holds durable state (cwd, config, issue_dir) and ephemeral command state. Shared across modules via duck typing rather than direct `require`.
- **config.lua** — Loads `.huginn` INI config, merges with defaults, supports live reload via `BufWritePost` autocmd.
- **issue.lua** — Issue lifecycle: create, read, write, serialize/deserialize. Issues are Markdown files with INI-structured metadata blocks stored at `<issue_dir>/YYYY/MM/<id>/Issue.md`.
- **issue_index.lua** — Maps file paths to issue IDs using SHA256-truncated hashes. Handles hash collisions by storing multiple sections per index file under `.index/`.
- **annotation.lua** — Renders virtual text annotations on buffers using extmarks. Shows open issue count per line.
- **location.lua** — Resolves source code locations using tree-sitter queries. Produces filepath + reference + context tuples.
- **filepath.lua** — Path normalization, joining, and `.huginn` file discovery (walks up directory tree).
- **ini_parser.lua** — INI format parser used for both config and issue/index files. Supports duplicate/nested sections.
- **logging.lua** — Logger abstraction writing to `.huginnlog`.
- **time.lua** — Issue ID generation and parsing (`yyyyMMdd_HHmmss` format).
- **doctor.lua** — Issue integrity scanner. Classifies issues as healthy, missing file, broken refs, or missing index. Provides interactive repair via `vim.ui.select`.

### Shared component utilities

- **float.lua** — Shared floating window helpers (`make_win_opts`, `create_buf`, `on_win_leave`, `on_win_closed`, `on_vim_resized`). Used by all windowed components.
- **issue_filter.lua** — Shared filter logic (`FILTER_CYCLE`, `FILTER_LABELS`, `apply`, `next`). Used by show_window, home_window, issue_picker.

### Key design patterns

- **Config is a live reference**: `context.durable.config.active` is a shared table — changes from config reload are immediately visible to all modules.
- **Write-through persistence**: Issues are written to disk immediately on creation; status changes flush lazily.
- **Hash-based indexing**: File paths are SHA256-hashed and truncated to `index.key_length` characters. Collisions are detected and handled by storing multiple file sections in the same index file.
- **Class-based components**: Windowed components use local classes (`Window`/`Picker`) with `__index` metamethods. Simpler components use module-level singletons (`win_id`/`buf_id`) for lifecycle.
- **No `vim.loop`**: The codebase uses `vim.fn` and `vim.uv` instead.

### Test framework

Custom test harness in `lua/huginn/tests/run.lua`, exposed as a module with `run_all()` and `run(target)` functions. Test files export a `run()` function that creates a `TestRunner` instance, registers tests via `runner:test(name, fn)`, and calls `runner:run()`. Global assertion helpers: `assert_equal`, `assert_nil`, `assert_not_nil`, `assert_true`, `assert_false`, `assert_match`.

### User commands

| Command | Description | Default keymap |
|---------|-------------|----------------|
| `:HuginnInit` | Initialize `.huginn` config in current directory | — |
| `:HuginnConfig` | Open the `.huginn` configuration file | — |
| `:HuginnLog` | Show log buffer in floating window | — |
| `:HuginnCreate` | Create issue at current cursor/selection location | `<leader>hc` |
| `:HuginnShow` | Show issues for the current buffer | `<leader>hs` |
| `:HuginnHome` | Show all project files with open issues | `<leader>hh` |
| `:HuginnNext` | Jump to the next issue location in the current buffer | `<leader>hn` |
| `:HuginnPrevious` | Jump to the previous issue location in the current buffer | `<leader>hp` |
| `:HuginnAdd` | Add a scope reference to an existing issue | `<leader>ha` |
| `:HuginnRemove` | Remove a scope reference from an existing issue | `<leader>hr` |
| `:HuginnDoctor` | Check issue integrity and interactively repair problems | — |

## Code Style

- MIT license header on every `.lua` file
- Use 4-space indentation
- Runtime: LuaJIT with global `vim` namespace (Neovim API)
- Test globals: `TestRunner`, `assert_equal`, `assert_nil`, `assert_not_nil`, `assert_true`, `assert_false`, `assert_match`
