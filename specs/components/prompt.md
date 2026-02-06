# prompt Component

No dependencies.

## Purpose

A floating buffer input component for capturing multi-line text. Used by `HuginnCreate` to collect issue descriptions.

## Public API

### prompt.show(opts, callback)

Opens a centered floating window with an editable markdown buffer. Calls `callback(string)` on submit or `callback(nil)` on dismissal.

`opts` is a `PromptOpts` table or a plain string (treated as `{ message = opts }`):

```lua
---@class huginn.PromptOpts
{
  message = string,   -- window title text
  default = string?,  -- pre-filled buffer content
}
```

No-ops if `callback` is missing or not a function. Calls `callback(nil)` if `opts` is invalid or `message` is empty.

## Window Configuration

- **Style**: Floating window, centered in the editor
- **Size**: 60% width, 30% height
- **Border**: Rounded, with title (message text, centered)
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, `filetype=markdown`

The buffer opens in insert mode.

## Keybindings

Buffer-local, registered on the scratch buffer.

| Key | Modes | Action |
|-----|-------|--------|
| `<C-s>` | n, i | Submit input |
| `<Esc>` | n | Dismiss (callback receives `nil`) |

### Submit (`<C-s>`)

1. Exit insert mode.
2. Read all buffer lines and join with `"\n"`.
3. Trim trailing whitespace.
4. Close the window and call `callback(content)`.

### Dismiss (`<Esc>`)

1. Exit insert mode.
2. Close the window and call `callback(nil)`.

## Double-Fire Guard

A `resolved` flag prevents the callback from firing more than once. Both submit and dismiss check this flag before proceeding.

## Autocmds

- **WinClosed** (`HuginnPrompt` augroup): If the window is closed externally (e.g., `:q`) and the callback has not yet fired, calls `callback(nil)`. Cleans up the augroup.
