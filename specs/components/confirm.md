# confirm Component

No dependencies.

## Purpose

A generic yes/no confirmation dialog backed by `vim.ui.select`. Used by `HuginnInit` (overwrite check) and `issue.delete` (deletion guard).

## Public API

### confirm.show(opts, callback)

Presents a `"Yes"` / `"No"` selection prompt. Calls `callback(true)` on "Yes", `callback(false)` on "No" or dismissal.

`opts` is a `ConfirmOpts` table or a plain string (treated as `{ message = opts, level = "safe" }`):

```lua
---@class huginn.ConfirmOpts
{
  message = string,            -- the question to display
  level   = huginn.ConfirmLevel?, -- "safe" (default), "caution", or "danger"
}
```

No-ops if `callback` is missing or not a function. Calls `callback(false)` if `opts` is invalid or `message` is empty.

## Prompt Format

The prompt is prefixed with the level label:

```
[Safe] Proceed with action?
[Caution] Discard unsaved changes?
[Danger] A .huginn configuration already exists. Replace it?
```

## Levels

| Level | Label | Usage |
|-------|-------|-------|
| `safe` | `[Safe]` | Default; low-risk confirmations |
| `caution` | `[Caution]` | Potentially lossy actions (e.g., discarding edits) |
| `danger` | `[Danger]` | Destructive actions (e.g., issue deletion) |
