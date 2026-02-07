# Huginn

Local-first issue tracking for Neovim. Track issues right where your code lives — no external services, no context switching.

Huginn stores issues as Markdown files on your filesystem, links them to source code locations using tree-sitter, and shows inline annotations so you always know where open issues live.

## Features

- **Filesystem-native issues** — Plain Markdown files in a time-indexed directory structure. Grep them, version them, back them up however you like.
- **Tree-sitter scope linking** — Issues attach to functions, methods, and classes, not just line numbers. Refactor freely; Huginn follows the code.
- **Inline annotations** — Virtual text shows open issue counts right on the relevant lines.
- **No dependencies** — No GitHub API tokens, no Jira credentials, no network requests. Everything stays local.

## Requirements

- Neovim 0.9+ with tree-sitter support
- Tree-sitter parsers installed for languages you work with

## Installation

### lazy.nvim

```lua
{
    "JDS-Software/huginn_issues",
    opts = {},
}
```

### packer.nvim

```lua
use {
    "JDS-Software/huginn_issues",
    config = function()
        require("huginn").setup()
    end,
}
```

### vim-plug

```vim
Plug 'JDS-Software/huginn_issues'
```

## Getting Started

1. Open a project in Neovim and run `:HuginnInit` to create a [`.huginn`](.huginn) config file in your project root.

```bash
cd ~/my_project
nvim
```

2. Place your cursor on a function or method and press `<leader>hc` or invoke :HuginnCreate to create your first issue.

3. Press `<leader>hs` (:HuginnShow) to see all issues for the current scope of your cursor, or `<leader>hh` to see every file with open issues.

That's it. Issues are stored under the directory configured in `.huginn` (default: `issues/`), and annotations appear automatically.

## Commands and Keymaps

| Command | Keymap | Description |
|---|---|---|
| `:HuginnCreate` | `<leader>hc` | Create an issue at the cursor position (normal or visual mode) |
| `:HuginnShow` | `<leader>hs` | Show issues for the current buffer |
| `:HuginnHome` | `<leader>hh` | Show all project files with open issues |
| `:HuginnNext` | `<leader>hn` | Jump to the next issue in the current buffer |
| `:HuginnPrevious` | `<leader>hp` | Jump to the previous issue in the current buffer |
| `:HuginnAdd` | `<leader>ha` | Add a scope reference to an existing issue |
| `:HuginnRemove` | `<leader>hr` | Remove a scope reference from an existing issue |
| `:HuginnInit` | — | Create a `.huginn` config in the current directory |
| `:HuginnConfig` | — | Open the `.huginn` config file for editing |
| `:HuginnDoctor` | — | Check issue integrity and interactively repair problems |
| `:HuginnLog` | — | Show the log buffer in a floating window |

Commands are registered in [`lua/huginn/init.lua`](lua/huginn/init.lua) and dispatched to individual handlers under [`lua/huginn/commands/`](lua/huginn/commands/).

## Configuration

### Keymaps

Override or disable any keymap through [`setup()`](lua/huginn/init.lua):

```lua
require("huginn").setup({
    keymaps = {
        create = "<leader>ic",     -- custom binding
        show = "<leader>is",
        next = false,              -- disable this keymap
    },
})
```

### Project config (`.huginn`)

`:HuginnInit` generates a config file with sensible defaults. All options are optional — see the [config cheatsheet](./specs/cheatsheet_config.md) for a full breakdown.

```ini
[annotation]
# enabled = true
# background = "#ffffff"
# foreground = "#000000"

[plugin]
# issue_dir = issues

[index]
# key_length = 16

[issue]
# open_after_create = false

[show]
# description_length = 80

[logging]
# enabled = false
# filepath = .huginnlog
```

Configuration is managed by the plugin and reloads automatically when you save the `.huginn` file.

## How Issues Work

Each issue is a Markdown file stored at `<issue_dir>/YYYY/MM/<id>/Issue.md`, where `<id>` is a UTC timestamp (`yyyyMMdd_HHmmss`). Issues contain metadata blocks for status, location, and description — but they're still plain Markdown you can read and edit by hand.

Issues link to code through tree-sitter scope references like `function_declaration|my_function` rather than fragile line numbers. When you open a buffer, Huginn resolves these references against the current parse tree and places annotations on the right lines. The [location module](lua/huginn/modules/location.lua) handles scope resolution, and the [annotation module](lua/huginn/modules/annotation.lua) renders the virtual text.

Huginn maintains an index to find issues quickly, so you may want to add `<issue_dir>/.index` to your version control's ignore list.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for bug reports and feature requests.

## License

[MIT](LICENSE) — JDS Consulting, PLLC
