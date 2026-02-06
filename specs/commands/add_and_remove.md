# HuginnAdd / HuginnRemove

Dependencies: `context`, `issue`, `issue_index`, `location`, `annotation`, `issue_picker`.

## Purpose

HuginnAdd adds the current cursor scope reference to an existing issue within the same source file. HuginnRemove removes a scope reference from an existing issue. Together they allow users to manage which named scopes (functions, methods, classes) are tracked by an issue without recreating it.

Adding a reference to a file-scoped issue converts it to function-scoped. Removing the last reference from a function-scoped issue converts it back to file-scoped.

## Command Registration

| Command | Range | Default keymap |
|---------|-------|----------------|
| `:HuginnAdd` | false | `<leader>ha` |
| `:HuginnRemove` | false | `<leader>hr` |

## Command Flow — HuginnAdd

1. Capture `CommandContext` via `context.from_command(opts)`.
2. Extract `location` via `location.from_context(cmd_ctx)`. If tree-sitter is unavailable or extraction fails, log a warning and abort — unlike HuginnCreate, there is no file-scoped fallback because adding a file-scoped reference to an existing issue is not meaningful.
3. If `location.reference` is empty (cursor is not in a named scope), alert the user ("Cursor is not in a named scope") and abort.
4. Derive relative filepath from `cmd_ctx.window.filepath` and `cmd_ctx.cwd`.
5. Look up `issue_index.get(rel_filepath)` to obtain the IndexEntry. If no IndexEntry exists, alert the user ("No issues for this file") and abort.
6. Read each issue via `issue.read(id)` for all issue IDs in the IndexEntry. If a read fails, log a warning and skip that issue.
7. **Filter to eligible issues**: Exclude issues whose references already contain `location.reference[1]`. File-scoped issues (no references) are always eligible.
8. If no eligible issues remain, alert the user ("All issues already have this reference") and abort.
9. Open the `issue_picker` component via `issue_picker.open(opts, callback)` passing:
   - `issues`: the filtered list of eligible `HuginnIssue` objects
   - `header_context`: action label and scope context (see [Picker Header Context](#picker-header-context))
   - `context`: the `CommandContext` from step 1
10. If the user dismisses the picker (callback receives `nil`), abort.
11. On selection: call `issue.add_reference(issue_id, location.reference[1])`. If the call fails, alert the user with the error and abort.
12. `cmd_ctx.logger:alert("INFO", "Added reference to: " .. issue_id)`.
13. Call `annotation.refresh()` to update virtual text on the source buffer.

## Command Flow — HuginnRemove

1. Capture `CommandContext` via `context.from_command(opts)`.
2. Extract `location` via `location.from_context(cmd_ctx)`. If tree-sitter is unavailable or extraction fails, log a warning and abort.
3. If `location.reference` is empty (cursor is not in a named scope), alert the user ("Cursor is not in a named scope") and abort.
4. Derive relative filepath from `cmd_ctx.window.filepath` and `cmd_ctx.cwd`.
5. Look up `issue_index.get(rel_filepath)` to obtain the IndexEntry. If no IndexEntry exists, alert the user ("No issues for this file") and abort.
6. Read each issue via `issue.read(id)` for all issue IDs in the IndexEntry. If a read fails, log a warning and skip that issue.
7. **Filter to eligible issues**: Include only issues whose references contain `location.reference[1]`. File-scoped issues are never eligible (they have no references to remove).
8. If no eligible issues remain, alert the user ("No issues have this reference") and abort.
9. Open the `issue_picker` component via `issue_picker.open(opts, callback)` passing:
   - `issues`: the filtered list of eligible `HuginnIssue` objects
   - `header_context`: action label and scope context (see [Picker Header Context](#picker-header-context))
   - `context`: the `CommandContext` from step 1
10. If the user dismisses the picker (callback receives `nil`), abort.
11. On selection: call `issue.remove_reference(issue_id, location.reference[1])`. If the call fails, alert the user with the error and abort. If no references remain after removal, the issue becomes file-scoped (this is handled internally by `remove_reference`).
12. `cmd_ctx.logger:alert("INFO", "Removed reference from: " .. issue_id)`.
13. Call `annotation.refresh()` to update virtual text on the source buffer.

## Picker Header Context

The header context string passed to the issue picker communicates the action and scope:

**HuginnAdd**:
```
Add: src/math.lua > calculate
```

**HuginnRemove**:
```
Remove: src/math.lua > calculate
```

The filepath is the relative path to the source file.

## Issue Filtering Details

Reference matching uses exact `type|symbol` string comparison. A cursor reference `function_declaration|calculate` matches an issue reference `function_declaration|calculate` but not `method_definition|calculate`. This ensures type-precise filtering — the same symbol name in different scope types is treated as distinct.

## Scope Conversion Notes

- **File-scoped to function-scoped (HuginnAdd)**: When a file-scoped issue (no references) gains its first reference via HuginnAdd, it becomes function-scoped. The `add_reference` function handles this transparently by appending to the empty references array.
- **Function-scoped to file-scoped (HuginnRemove)**: When the last reference is removed from an issue via HuginnRemove, the issue reverts to file-scoped. The `remove_reference` function handles this — when the references array becomes empty, the issue is file-scoped by definition.
