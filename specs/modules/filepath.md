# Filepath

Paths that cross module or component boundaries are always relative to `context.cwd` — the directory containing the `.huginn` config file. Modules may compose absolute paths internally for filesystem operations, but any path stored in an issue, passed between modules, or written to an index file must be relative. The `relative_to_absolute` and `absolute_to_relative` functions in this module handle conversion at those boundaries.

## Normalization

### normalize(path) -> string

Resolves `.` and `..` components, collapses duplicate slashes, and replaces backslashes with forward slashes. Returns `"."` if `path` is nil or empty.

At module load time, the availability of `vim.fs.normalize` is checked once. If present, `normalize` delegates to it. Otherwise, a private fallback (`huginn_normalize`) is used. The fallback handles:

1. Backslash replacement (`\` → `/`).
2. Duplicate slash collapse (`//` → `/`).
3. Component-wise resolution of `.` (removed) and `..` (pops the previous component). For absolute paths, `..` at the root is silently discarded. For relative paths, leading `..` components are preserved.

The result is always forward-slash separated. Absolute paths retain their leading `/`.

## Path Manipulation

### join(...) -> string

Joins one or more path components into a single normalized path. Empty or nil arguments are skipped. Trailing slashes on individual components are stripped before joining. A bare `"/"` component is preserved as the root prefix. Returns `"."` if no arguments are provided.

The result is passed through `normalize` before being returned.

### dirname(path) -> string

Returns the parent directory of `path`. The input is normalized before processing. Returns `"/"` for the root directory and `"."` for paths with no directory component (bare filenames). Returns `"."` if `path` is nil or empty.

### basename(path) -> string

Returns the final component of `path` (the filename). The input is normalized and trailing slashes are stripped before extracting. Returns `""` if `path` is nil or empty.

## Filesystem Queries

Both functions use `vim.uv.fs_stat` and return `false` for nil or empty inputs.

### exists(path) -> boolean

Returns `true` if `path` refers to an existing file or directory.

### is_directory(path) -> boolean

Returns `true` if `path` exists and is a directory. Returns `false` for files, symlinks to non-directories, and nonexistent paths.

## Config Discovery

### find_huginn_file(start_path) -> string?

Walks up the directory tree from `start_path` looking for a `.huginn` file. Returns the absolute path to the first `.huginn` file found, or `nil` if the root is reached without finding one.

If `start_path` is a file (not a directory), the search begins from its parent directory. The walk terminates when `dirname` returns the same path as the current directory — this is the root sentinel.

This function is called during plugin initialization by the [context module](context.md#singleton-lifecycle) to locate the project's configuration file.

## Relative/Absolute Conversion

Both functions take `huginn_dir` — the absolute path to the directory containing the `.huginn` config file. This is `context.cwd` at runtime (see [context specification](context.md)).

### relative_to_absolute(relative, huginn_dir) -> string?

Converts a relative path to absolute by joining it with `huginn_dir`. If `relative` is already absolute (starts with `/`), it is normalized and returned as-is. Returns `nil` if either argument is nil or empty.

### absolute_to_relative(absolute, huginn_dir) -> string?

Strips the `huginn_dir` prefix from `absolute` to produce a relative path. Returns `nil` if either argument is nil or empty. Both paths are normalized before comparison.

- If `absolute` starts with `huginn_dir/`, the prefix is stripped and the remainder is returned.
- If `absolute` equals `huginn_dir` exactly, returns `"."`.
- If `absolute` is not under `huginn_dir`, the full absolute path is returned unchanged. This is a passthrough, not an error — callers should be aware that the result may still be absolute.
