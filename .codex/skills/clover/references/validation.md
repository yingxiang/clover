# Clover Validation Subskill

Use this reference before finishing a Clover task.

## Project Generation

Run XcodeGen after changing `project.yml`, adding files, removing files, or changing build settings:

```bash
xcodegen generate
```

Keep signing and bundle settings in `project.yml` aligned with the user's current Xcode project values so regeneration does not overwrite them.

## Build

Use an explicit macOS destination:

```bash
xcodebuild -project Clover.xcodeproj -scheme Clover -destination 'platform=macOS,arch=arm64' build
```

If DerivedData noise or stale products interfere, use a temporary DerivedData path:

```bash
xcodebuild -project Clover.xcodeproj -scheme Clover -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/CloverDerivedData build
```

## Tests

Run focused tests for provider, domain, operation, startup, or persistence changes:

```bash
xcodebuild -project Clover.xcodeproj -scheme Clover -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/CloverDerivedData test
```

## Startup Checks

When changing lifecycle or UI shell code:

- Launch the built app.
- Confirm a visible main window appears.
- Confirm closing and reopening the app shows a window again.
- Check logs if the app launches without a window.

Useful log command:

```bash
/usr/bin/log show --style compact --last 5m --predicate 'process == "Clover"'
```

## UI Regression Checks

When changing AppKit interactions, manually reason through or test the matching UI surface before finishing:

- Toolbar/layout picker: current toolbar content is readable, commands fire on first click, and popovers anchor to the toolbar control rather than drifting to the window center.
- List/grid parity: operations available in list mode should also work in grid mode unless explicitly scoped.
- Drag/drop: verify list-to-list, list-to-grid, grid-to-list, and grid-to-grid paths when drag/drop code changes. Include dropping onto blank grid space.
- Thumbnails: list and grid cells should first show an icon, then replace it with a non-distorted Quick Look thumbnail when available.
- Detail reuse: if list or grid has already shown a file's derived detail text such as package size or folder item count, switching to the other view mode should reuse it immediately instead of recalculating it once per surface.
- Quick Look: Space opens preview for the selected item; arrow keys move through pane items while preview is visible.
- Quick Look animation: in list mode, the zoom should start from the left file icon area; closing should zoom back and crossfade instead of hard-disappearing.
- Inline rename: Return and selected-name click should edit the visible filename in place.
- Inline rename selection: files should preselect only the basename and leave the extension unselected; folders should select the full name.
- New item rename flow: New Folder / Text / Markdown should insert a pending row/item immediately, enter inline rename without a full pane refresh, and only create the real filesystem item after the rename is confirmed.
- Pending item cancel: Esc or cancel on a pending new item should remove the placeholder and leave no file/folder created on disk.
- List subtree toggles: expanding/collapsing a directory in list mode should not visibly flash or rebuild the whole pane; it should animate as a local row insertion/removal.
- Cross-window operations: modifying files in one window should not make unrelated directories in other windows refresh or blink.

## Manual Review

Before final response:

- Search for direct UI-layer `FileManager` usage when touching file operations.
- Search for list/grid asymmetry when changing file interactions:

```bash
rg -n "tableView|collectionView|FileTableView|FileCollectionView|dragging|thumbnail|QuickLook|QLPreview" Clover/UI Clover/App
```

- Check large Swift files after meaningful edits:

```bash
find Clover Tests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head
```

- Inspect files at or above 800 lines and split any project-owned file that exceeds 1000 lines unless the user explicitly accepts a temporary exception.
- Confirm `project.yml` and generated Xcode settings do not undo user-provided bundle ID, team ID, or signing choices.
- Mention unimplemented execution-plan phases plainly.
