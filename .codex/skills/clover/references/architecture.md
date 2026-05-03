# Clover Architecture Subskill

Use this reference before changing shared models, providers, file operations, workspace persistence, or app services.

## Project Shape

- Target platform: macOS 15+.
- Language and UI stack: Swift + AppKit.
- Product: multi-pane local file manager with future room for remote providers, archives, sync, batch rename, and advanced workspace workflows.
- Keep project-owned Swift files below 1000 lines. At 800 lines, plan the next split; before 1000 lines, split by responsibility instead of appending more behavior.

## Module Boundaries

- `Clover/App`: application lifecycle, dependency assembly, main window ownership.
- `Clover/Domain`: stable product concepts such as `FileItem`, `PaneLayout`, `PaneState`, `Workspace`, and sort/view modes.
- `Clover/Infrastructure`: concrete providers, operations, persistence, icon loading, and filesystem-facing services.
- `Clover/UI`: AppKit controllers and views. Keep these thin; use view models for state.

## Size And Responsibility Rules

- Do not intentionally make a Swift source file exceed 1000 lines.
- When a file approaches 800 lines, decide whether state, view construction, menu construction, data source behavior, provider implementation, or tests should move into a separate type/file.
- Prefer small named files over broad utility files. A file should have a clear product responsibility, not merely collect unrelated helpers.
- Extensions in the same file still count toward the file size limit; move meaningful extensions into focused files when they grow.

## File Access Rules

- UI code must not call `FileManager` directly for file browsing or mutation.
- Directory listing belongs behind `FileProvider`.
- Copy, move, rename, new folder, and trash actions belong in `FileOperationService`.
- Use `URLResourceValues` for file metadata.
- Preserve security-scoped bookmark compatibility even when the first local build does not fully enforce sandbox workflows.
- Use `UserDirectories.homeURL` whenever Clover needs the real user home path. Sandbox APIs can resolve to the app container home, which makes sidebar entries point at paths like `~/Library/Containers/.../Data/Downloads`.
- `DirectoryAccessStore` should resolve the nearest stored bookmark ancestor with a path-boundary check, not a plain string prefix. A bookmark for `/Users/me/Down` must not authorize `/Users/me/Downloads`.
- Permission prompts should be based on current readability/bookmark resolution. Do not store or consult a separate runtime "authorized once" marker.
- Keep security-scope lifetimes tight and operation-scoped. Start access around provider work, Quick Look thumbnail/preview access, and share/AirDrop validation or execution; stop access as soon as that operation or preview ownership ends.

## Concurrency

- File listing and file operations must run off the main thread.
- UI updates must return to the main actor.
- Large-directory behavior should have loading/error state and must remain cancellable or replaceable by a newer navigation request.

## Refresh And Notifications

- Distinguish full directory navigation from local UI mutations. Opening a different folder can reload pane contents; expanding/collapsing an already-visible list subtree should not.
- Distinguish data reloads from visible-item filtering. Search and type filters should recompute from already loaded pane state; they must not call `FileProvider.listDirectory` or clear pane-local detail caches.
- Cross-window file-operation notifications should carry enough context, such as affected directories, so panes can ignore unrelated changes instead of all refreshing globally.
- Prefer scoped refresh decisions based on the pane's current directory and any visible expanded child directories.
- Cache already loaded expanded child directories within a pane session and invalidate them deliberately, not by default on every refresh path.
- Treat pane-visible derived metadata such as directory item counts, package sizes, image dimensions, and similar detail strings as pane state, not as view-specific state. List and grid surfaces should read from the same cache so view-mode switches stay presentational rather than triggering new filesystem work.

## Workspace State

- Persist layouts through codable domain state, not view-controller state.
- Keep pane state serializable: current path/bookmark, view mode, sort option, selection, back history, and forward history.
- When reducing pane count, preserve the active pane first.
- When increasing pane count, create additional panes from the user's home directory unless restored state exists.
