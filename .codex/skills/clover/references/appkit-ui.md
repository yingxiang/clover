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
```

Window lifecycle rules:

- Own the main window through `MainWindowController`.
- Keep the main window retained while the app is running.
- On launch and app reopen, call `showWindow`, `makeKeyAndOrderFront`, and activate the app.
- Avoid relying on state restoration for the initial shell unless restoration has explicit tests.
- Keep window controllers focused on composition and command routing. Move popovers, menu builders, toolbar controls, drawing helpers, and complex child views into separate files before the controller approaches 800 lines.
- When restoring a workspace, immediately resynchronize toolbar state such as layout/view-mode buttons and command availability. Do not assume restoring pane state will automatically refresh toolbar visuals.

## Toolbar And Popovers

- For toolbar controls that must keep exact visual layout or popover anchoring, prefer a small custom `NSControl` as `NSToolbarItem.view` over relying only on `NSToolbarItem.label/image`.
- Custom toolbar controls must call `sendAction(_:to:)` from mouse handling so text-only or custom display modes still trigger the command directly.
- Anchor popovers to the actual toolbar control view whenever possible. Use content-view fallback anchors only as a last resort.
- Layout picker toolbar UI should show the current layout icon plus a dropdown indicator; avoid replacing the button label with verbose layout names.
- Keep layout picker popover content icon-only with tooltips/accessibility labels for specific layout names.
- If toolbar buttons use custom views, keep `NSButton.isEnabled` and `NSToolbarItem.isEnabled` synchronized. Updating only the button can leave the toolbar label in the wrong enabled/disabled color.
- When a toolbar action depends on selection state, propagate command-availability changes from the active pane back to the window controller so custom toolbar items update immediately instead of waiting for focus changes.
- Clover fixes the system toolbar display mode to icon-only. Set `toolbar.displayMode = .iconOnly`, `allowsUserCustomization = false`, and `autosavesConfiguration = false`; do not remove restored localization strings just to hide system display-mode menu text.
- AppKit's system toolbar/titlebar right-click menu can still appear in full-screen because events may come from private chrome windows rather than the app's `NSWindow`. For this project, suppress that menu with an `NSEvent.addLocalMonitorForEvents` on right/control-click down/up events, scoped to the Clover window plus full-screen chrome/top-screen-area checks. Button subclass `menu(for:)` overrides or `NSWindow.sendEvent(_:)` interception are not sufficient by themselves for full-screen.
- Remove local event monitors when the window closes. A window controller-owned monitor is acceptable for toolbar context-menu suppression and pane-switch shortcuts.
- Titlebar accessory views should avoid fixed-height constraints that fight `NSTitlebarAccessoryClipView` in full-screen. Prefer intrinsic/flexible vertical sizing plus fixed control dimensions, and align controls to titlebar peers visually rather than constraining the accessory container height.
- Sidebar collapse/expand belongs near the titlebar full-screen button, not in shifting content layout. Keep the toggle fixed to the left titlebar area, match toolbar icon tint, set a tooltip/accessibility label, animate collapse/expand, and persist the sidebar collapsed state in `Workspace`.
- Toolbar button help should use `toolTip` and accessibility labels for the localized action name. Keep visible toolbar display icon-only and do not expose AppKit's titlebar right-click display-mode switching.

## Pane Layouts

First-version layouts:

- Single pane.
- Two vertical panes.
- Two horizontal panes.
- Four-grid panes.

Rules:

- `PaneLayoutController` creates, removes, and rearranges pane controllers.
- Preserve active pane state when switching layouts.
- When switching pane layouts, default newly created left/right and top/bottom split dividers to equal 50/50 proportions unless restoring an explicit saved ratio.
- Highlight the active pane clearly.
- Keyboard commands act on the active pane.
- Each pane can navigate independently.
- Two-pane split resizing must enforce a minimum ratio of 2:1 from either side rather than allowing one pane to collapse visually.
- Four-grid resizing must be a true cross split: the vertical and horizontal dividers intersect as one crosshair, and dragging the intersection moves all four pane sizes together. Avoid independent nested split views for four-grid interaction because their dividers can become visually staggered.
- In four-grid mode, make the crosshair drag target own the drag gesture once the cursor changes to resize. This prevents accidental file drag gestures from the pane content while resizing near the divider.
- Tab switches focus between panes: `Tab` moves to the next pane, `Shift+Tab` to the previous pane, and single-pane layouts should not intercept it. Do not steal Tab while a text editor/search field/path input/inline rename editor is active. After switching, make the target pane's table or collection view first responder.

## File Pane

- Use `NSTableView` for the first list view.
- Use `NSCollectionView` for grid/icon mode; size grid items so icon, up-to-two-line name, and detail text never overlap.
- Keep file list state in `FilePaneViewModel`.
- File rows should expose name, type, size, modification date, and directory state.
- Sort and filter through view-model/domain behavior, not ad hoc table callbacks.
- Prefer table-native affordances for list headers: use `NSTableColumn.sortDescriptorPrototype` and `tableView(_:sortDescriptorsDidChange:)` for sortable columns, and keep the header's sort indicator synchronized with `FilePaneViewModel.sortOption`.
- Put type filtering in the table header or another non-overlapping control. Do not float a filter popup over the table header, because it can cover section/header UI.
- If a table header column opens a menu rather than sorting, make that visible in the title (for example `Type ▾`) and keep the actual filter state in the view model.
- Type-filter selection should update visible list/grid items from `FilePaneViewModel` memory. Do not send it through the full pane `reload()` path because that clears derived-detail caches and restarts thumbnail/detail work.
- Prefer SF Symbols or system icons through `AppIconProvider`; do not add third-party icon sets.
- Keep context-menu setup, table delegate/data source behavior, and row interaction logic separable. If `FilePaneViewController` grows toward 800 lines, extract menu routing, table subclasses, or view construction into focused files.
- Pane-local navigation controls belong with the pane path UI, not the global toolbar. Each pane should maintain its own back/forward history so multi-pane browsing remains independent.
- Window title should follow the active pane's current folder display name. Propagate active pane path changes from `FilePaneViewController` through `PaneLayoutController`/workspace/root controllers to `MainWindowController`.
- If no file is selected, actions like Open in Terminal should fall back to the active pane's current folder instead of silently doing nothing.
- In list mode, expanding or collapsing a directory should update only the affected rows. Do not rebuild or reload the entire table view for a local tree toggle.
- List-mode directory expansion should feel animated. Prefer row insertion/removal animations over abrupt whole-table redraws.
- Re-expanding a previously loaded child directory in the same pane should reuse cached children when possible instead of reloading from disk immediately.
- During file drags, hovering a browsable directory should visibly select that directory as the drop target and auto-expand it after a short delay. Drop target calculation should use the current pointer location, not stale cell row tags or AppKit's proposed insertion row.
- Refreshes after file operations must update cached children for currently expanded directories as well as the root directory so expanded folders show newly moved/copied items immediately.
- Move notifications should include the original moved item URLs so other panes/windows can clear stale visible rows from expanded-directory caches before reloading affected directories.
- Opening an extractable archive from the file pane should run Clover's extraction flow, refresh the pane, and select the extracted result. It must not fall through to the system/Finder open path. Treat common archive extensions such as zip, tar, tgz, tar.gz, tbz, tbz2, tar.bz2, txz, and tar.xz as extractable, and route them to an extraction tool that supports the format.
- Compressing selected files from the context menu should route through `FileOperationService`/`FileProvider`, create a uniquely named zip in the current pane directory, refresh the pane, and select the created archive.
- Long paths should not force the window wider or prevent shrinking. Use AppKit path controls or similarly compressible native controls for path display/input rather than unbounded labels or text fields.
- File labels/tags should match Finder placement: in list mode, show tag color dots after the filename; in icon/grid mode, show them before the displayed filename. Keep tag indicators compact and non-textual unless the user explicitly asks for tag names.

## Icons, Thumbnails, And Grid Details

- Show a system/file icon immediately, then replace it asynchronously with a Quick Look thumbnail when available.
- Use the same thumbnail policy in list and grid views. Images, text, documents, and other Quick Look-supported files should show thumbnails; folders keep folder icons unless a provider-specific folder thumbnail is added later.
- When generating Quick Look thumbnails or previewing files under a stored user-selected bookmark, start security-scoped access for the bookmarked ancestor while Quick Look reads the file.
- List and grid views should share the same pane-local detail metadata cache. If one view has already resolved item count, package size, dimensions, or other visible detail text for an item, switching view modes must reuse that result instead of recalculating it.
- In-flight detail loads should also be shared per item within a pane so switching between list and grid while metadata is still computing does not launch duplicate work.
- Derived detail work triggered from a user-interactive table/grid update should not hop to a lower QoS task that can produce priority-inversion warnings.
- Preserve thumbnail aspect ratio. Do not force `NSImage.size` to a square after Quick Look returns the image.
- Grid names are maximum two lines, not forced two lines. The name selection background should shrink to one line when the name fits.
- Grid detail text belongs below the name and is not part of selection highlighting. Follow Finder-like detail semantics: image dimensions, folder item count, otherwise formatted file size.
- Grid selection should separately indicate the icon area and name text. Avoid full-cell selection blocks unless the user explicitly changes the design.

## Inline Rename And Preview

- Rename should edit the selected filename inline in the list/grid view instead of using a separate modal rename prompt.
- Pressing Return on a selected item begins inline rename.
- Clicking the selected grid name again should begin inline rename.
- Inline rename should preselect only the editable filename stem for files, leaving the extension unselected by default. Folders should still select the full name.
- The filename-stem selection rule should be shared between list/grid and new-item/existing-item rename paths, not reimplemented differently in each surface.
- New Folder, New Text File, and New Markdown File should insert a visible pending item into the current list/grid and immediately enter inline rename.
- Pending new items should not create the real file/folder on disk until the user explicitly commits the rename. Esc/cancel should remove the pending item without touching disk.
- Starting inline rename for a pending item must not trigger a full pane reload or retry loop that steals focus and ends editing immediately.
- Pressing Space previews the selected file with Quick Look.
- Pressing Space again while Clover owns a visible Quick Look panel should close the preview.
- When Quick Look is visible, arrow keys should move between previewable items in the current pane and keep the pane selection synchronized. macOS arrow-key events often include the `.function` modifier flag, so navigation-key modifier filtering must subtract both `.numericPad` and `.function`.
- Use `QLPreviewPanelDelegate.previewPanel(_:handle:)` plus a local key monitor when needed; Quick Look can own focus, and pane table/collection key handlers may not receive preview-window events.
- Observe or otherwise synchronize `QLPreviewPanel.currentPreviewItemIndex` so system-handled navigation and Clover-handled navigation keep the list/grid selection aligned.
- Implement `previewPanel(_:sourceFrameOnScreenFor:)` for Quick Look zoom animations. In list mode, anchor the animation to the name-column's left file icon area rather than the whole row; in grid mode, use the grid icon rect. Return `.zero` only when no visible source can be found.
- Implement `previewPanel(_:transitionImageFor:contentRect:)` so Quick Look open/close animations use the same file icon/thumbnail as the source view. Closing the preview should keep the zoom-back motion and add a visible crossfade rather than disappearing abruptly.
- Quick Look data source/delegate ownership should be cleaned up when the preview panel closes so stale pane controllers do not continue receiving panel callbacks.

## Menus And Shortcuts

- Provide a minimal main menu so the app has normal macOS activation, quit, close, hide, and window behavior.
- Add commands incrementally and route them to the active pane or selected file items.
- Keep command handlers separate from direct filesystem operations.
- Menu entries that depend on a selected file or folder should be built from the current selection context, not from hard-coded global availability.
- Prefer system-provided menu/picker surfaces for share flows. On modern macOS, use `NSSharingServicePicker` and its standard share menu item instead of deprecated `NSSharingService.sharingServices(forItems:)` enumeration.
- Do not call ShareKit `canPerform` with selected file URLs just to decide whether a menu item is enabled unless security-scoped access is active. Prefer enabling Share/AirDrop from selection shape and wrapping actual share validation/execution in security scopes.
- Open With menus should avoid synchronous `NSWorkspace`/bundle icon work while building the menu. Display a fallback app icon first, then asynchronously load and cache per-application icons; titles should come from the app URL filename so localized/non-ASCII names are not mangled by system log/path compaction.
- Context menus and table header menus should live in focused extension files where possible. Avoid letting `FilePaneViewController` absorb menu-building, sorting, preview, and navigation details once it approaches the 800-line warning threshold.
- Do not implement Finder-like expandable folder rows in the list with ad hoc nested menus or table-row hacks. If multi-level in-place folder expansion is required, plan it as an `NSOutlineView`/tree-model feature.
- If a legacy Objective-C delegate such as a sharing picker delegate triggers Swift 6 isolation warnings, keep the fix local to that conformance. Prefer `@preconcurrency` or another narrow bridge over broad actor annotations that can hide unrelated threading issues.

## Appearance And Chrome

- Do not add a persistent bottom status bar unless it carries critical, action-worthy information. Default to giving pane content the full vertical space.
- Path bars and similar top chrome should usually inherit the window background rather than painting a custom solid background. Extra background layers tend to drift out of sync during macOS appearance changes.
- If a view must still use layer-backed colors, refresh them in `viewDidChangeEffectiveAppearance()` instead of relying on a one-time `cgColor` assignment during initialization.
- Active pane highlighting should be subtle: prefer a thin accent border plus a modest corner radius over a heavy outline.

## Drag And Drop

- Drag/drop must work between panes/windows in both list and grid modes.
- Drag sources should explicitly write selected file URLs to the pasteboard; do not rely only on implicit `pasteboardWriterFor...` behavior when cross-window movement is required.
- Drop targets should accept file URLs on table views, collection views, and the grid scroll view/background so dropping on empty grid space moves into the current folder.
- Validate drops as `.move` only when file URLs can be read from the pasteboard.
- Resolve the destination through pane state: dropping onto a directory targets that directory; dropping onto blank space targets the current folder.
- Execute moves through `FilePaneViewModel` and `FileOperationService`, not direct UI-layer `FileManager` calls.
