# Clover Architecture Subskill

Use this reference before changing shared models, providers, file operations, workspace persistence, or app services.

## Project Shape

- Target platform: macOS 15+.
- Language and UI stack: Swift + AppKit.
- Product: multi-pane local file manager with future room for remote providers, archives, sync, batch rename, and advanced workspace workflows.
- Keep Swift files below 1000 lines; split by responsibility before a file becomes difficult to scan.

## Module Boundaries

- `Clover/App`: application lifecycle, dependency assembly, main window ownership.
- `Clover/Domain`: stable product concepts such as `FileItem`, `PaneLayout`, `PaneState`, `Workspace`, and sort/view modes.
- `Clover/Infrastructure`: concrete providers, operations, persistence, icon loading, and filesystem-facing services.
- `Clover/UI`: AppKit controllers and views. Keep these thin; use view models for state.

## File Access Rules

- UI code must not call `FileManager` directly for file browsing or mutation.
- Directory listing belongs behind `FileProvider`.
- Copy, move, rename, new folder, and trash actions belong in `FileOperationService`.
- Use `URLResourceValues` for file metadata.
- Preserve security-scoped bookmark compatibility even when the first local build does not fully enforce sandbox workflows.

## Concurrency

- File listing and file operations must run off the main thread.
- UI updates must return to the main actor.
- Large-directory behavior should have loading/error state and must remain cancellable or replaceable by a newer navigation request.

## Workspace State

- Persist layouts through codable domain state, not view-controller state.
- Keep pane state serializable: current path/bookmark, view mode, sort option, selection, back history, and forward history.
- When reducing pane count, preserve the active pane first.
- When increasing pane count, create additional panes from the user's home directory unless restored state exists.
