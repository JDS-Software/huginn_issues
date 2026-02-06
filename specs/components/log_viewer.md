# log_viewer Component

No dependencies.

## Purpose

A read-only floating window that displays the in-memory log buffer. Opened by the `HuginnLog` command.

## Public API

### log_viewer.open(logger)

Opens a centered floating window and populates it with `logger:get_buffer()`. If the window is already open, focuses it instead of creating a duplicate.

### log_viewer.is_open()

Returns `true` if the viewer window is currently open and valid.

## Window Configuration

- **Style**: Floating window, centered in the editor
- **Size**: 80% width, 80% height
- **Border**: Rounded, with title `" Huginn Log "` (centered)
- **Buffer options**: `buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, `filetype=huginnlog`, `modifiable=false`

## Buffer Content

Lines are read from `logger:get_buffer()`. If the buffer is empty, a single `[No log entries]` placeholder is shown. The cursor is placed on the last line.

## Keybindings

Buffer-local, registered on the scratch buffer.

| Key | Mode | Action |
|-----|------|--------|
| `q` | n | Close the window |
| `<C-r>` | n | Refresh — re-read log buffer and repopulate |

## Autocmds

Under the `HuginnLogViewer` augroup:

- **VimResized**: Recalculate window dimensions and reposition.
- **WinClosed**: Clean up module state when the window is closed externally (e.g., `:q`).

## Testing

The module exposes `_close()` which closes the window and resets internal state.
