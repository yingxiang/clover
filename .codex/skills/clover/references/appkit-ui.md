# Clover AppKit UI Subskill

Use this reference before changing windows, split views, panes, path bars, sidebars, file tables, grid views, toolbars, popovers, thumbnails, menus, shortcuts, Quick Look, or drag/drop.

## Main Window

The application should open a visible main window on launch.

Expected hierarchy:

```text
MainWindowController
├── NSToolbar
├── RootSplitViewController
│   ├── SidebarViewController
│   └── WorkspaceViewController
│       ├── PaneLayoutController
│       │   ├── FilePaneViewController
│       │   └── FilePaneViewController ...
│       └── StatusBarView
```

Window lifecycle rules:

- Own the main window through `MainWindowController`.
- Keep the main window retained while the app is running.
- On launch and app reopen, call `showWindow`, `makeKeyAndOrderFront`, and activate the app.
- Avoid relying on state restoration for the initial shell unless restoration has explicit tests.
- Keep window controllers focused on composition and command routing. Move popovers, menu builders, toolbar controls, drawing helpers, and complex child views into separate files before the controller approaches 800 lines.

## Toolbar And Popovers

- For toolbar controls that must keep exact visual layout or popover anchoring, prefer a small custom `NSControl` as `NSToolbarItem.view` over relying only on `NSToolbarItem.label/image`.
- Custom toolbar controls must call `sendAction(_:to:)` from mouse handling so text-only or custom display modes still trigger the command directly.
- Anchor popovers to the actual toolbar control view whenever possible. Use content-view fallback anchors only as a last resort.
- Layout picker toolbar UI should show the current layout icon plus a dropdown indicator; avoid replacing the button label with verbose layout names.
- Keep layout picker popover content icon-only with tooltips/accessibility labels for specific layout names.

## Pane Layouts

First-version layouts:

- Single pane.
- Two vertical panes.
- Two horizontal panes.
- Four-grid panes.

Rules:

- `PaneLayoutController` creates, removes, and rearranges pane controllers.
- Preserve active pane state when switching layouts.
- Highlight the active pane clearly.
- Keyboard commands act on the active pane.
- Each pane can navigate independently.

## File Pane

- Use `NSTableView` for the first list view.
- Use `NSCollectionView` for grid/icon mode; size grid items so icon, up-to-two-line name, and detail text never overlap.
- Keep file list state in `FilePaneViewModel`.
- File rows should expose name, type, size, modification date, and directory state.
- Sort and filter through view-model/domain behavior, not ad hoc table callbacks.
- Prefer table-native affordances for list headers: use `NSTableColumn.sortDescriptorPrototype` and `tableView(_:sortDescriptorsDidChange:)` for sortable columns, and keep the header's sort indicator synchronized with `FilePaneViewModel.sortOption`.
- Put type filtering in the table header or another non-overlapping control. Do not float a filter popup over the table header, because it can cover section/header UI.
- If a table header column opens a menu rather than sorting, make that visible in the title (for example `Type ▾`) and keep the actual filter state in the view model.
- Prefer SF Symbols or system icons through `AppIconProvider`; do not add third-party icon sets.
- Keep context-menu setup, table delegate/data source behavior, and row interaction logic separable. If `FilePaneViewController` grows toward 800 lines, extract menu routing, table subclasses, or view construction into focused files.
- Pane-local navigation controls belong with the pane path UI, not the global toolbar. Each pane should maintain its own back/forward history so multi-pane browsing remains independent.
- Window title should follow the active pane's current folder display name. Propagate active pane path changes from `FilePaneViewController` through `PaneLayoutController`/workspace/root controllers to `MainWindowController`.

## Icons, Thumbnails, And Grid Details

- Show a system/file icon immediately, then replace it asynchronously with a Quick Look thumbnail when available.
- Use the same thumbnail policy in list and grid views. Images, text, documents, and other Quick Look-supported files should show thumbnails; folders keep folder icons unless a provider-specific folder thumbnail is added later.
- Preserve thumbnail aspect ratio. Do not force `NSImage.size` to a square after Quick Look returns the image.
- Grid names are maximum two lines, not forced two lines. The name selection background should shrink to one line when the name fits.
- Grid detail text belongs below the name and is not part of selection highlighting. Follow Finder-like detail semantics: image dimensions, folder item count, otherwise formatted file size.
- Grid selection should separately indicate the icon area and name text. Avoid full-cell selection blocks unless the user explicitly changes the design.

## Inline Rename And Preview

- Rename should edit the selected filename inline in the list/grid view instead of using a separate modal rename prompt.
- Pressing Return on a selected item begins inline rename.
- Clicking the selected grid name again should begin inline rename.
- Pressing Space previews the selected file with Quick Look.
- Pressing Space again while Clover owns a visible Quick Look panel should close the preview.
- When Quick Look is visible, arrow keys should move between previewable items in the current pane and keep the pane selection synchronized. macOS arrow-key events often include the `.function` modifier flag, so navigation-key modifier filtering must subtract both `.numericPad` and `.function`.
- Use `QLPreviewPanelDelegate.previewPanel(_:handle:)` plus a local key monitor when needed; Quick Look can own focus, and pane table/collection key handlers may not receive preview-window events.
- Observe or otherwise synchronize `QLPreviewPanel.currentPreviewItemIndex` so system-handled navigation and Clover-handled navigation keep the list/grid selection aligned.
- Implement `previewPanel(_:sourceFrameOnScreenFor:)` for Quick Look zoom animations. Return the list row/name-cell rect in list mode and the grid icon rect in grid mode; return `.zero` only when no visible source can be found.
- Quick Look data source/delegate ownership should be cleaned up when the preview panel closes so stale pane controllers do not continue receiving panel callbacks.

## Menus And Shortcuts

- Provide a minimal main menu so the app has normal macOS activation, quit, close, hide, and window behavior.
- Add commands incrementally and route them to the active pane or selected file items.
- Keep command handlers separate from direct filesystem operations.
- Menu entries that depend on a selected file or folder should be built from the current selection context, not from hard-coded global availability.
- Context menus and table header menus should live in focused extension files where possible. Avoid letting `FilePaneViewController` absorb menu-building, sorting, preview, and navigation details once it approaches the 800-line warning threshold.
- Do not implement Finder-like expandable folder rows in the list with ad hoc nested menus or table-row hacks. If multi-level in-place folder expansion is required, plan it as an `NSOutlineView`/tree-model feature.

## Drag And Drop

- Drag/drop must work between panes/windows in both list and grid modes.
- Drag sources should explicitly write selected file URLs to the pasteboard; do not rely only on implicit `pasteboardWriterFor...` behavior when cross-window movement is required.
- Drop targets should accept file URLs on table views, collection views, and the grid scroll view/background so dropping on empty grid space moves into the current folder.
- Validate drops as `.move` only when file URLs can be read from the pasteboard.
- Resolve the destination through pane state: dropping onto a directory targets that directory; dropping onto blank space targets the current folder.
- Execute moves through `FilePaneViewModel` and `FileOperationService`, not direct UI-layer `FileManager` calls.
