# Clover AppKit UI Subskill

Use this reference before changing windows, split views, panes, path bars, sidebars, file tables, menus, shortcuts, or drag/drop.

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
- Keep file list state in `FilePaneViewModel`.
- File rows should expose name, type, size, modification date, and directory state.
- Sort and filter through view-model/domain behavior, not ad hoc table callbacks.
- Prefer SF Symbols or system icons through `AppIconProvider`; do not add third-party icon sets.
- Keep context-menu setup, table delegate/data source behavior, and row interaction logic separable. If `FilePaneViewController` grows toward 800 lines, extract menu routing, table subclasses, or view construction into focused files.

## Menus And Shortcuts

- Provide a minimal main menu so the app has normal macOS activation, quit, close, hide, and window behavior.
- Add commands incrementally and route them to the active pane or selected file items.
- Keep command handlers separate from direct filesystem operations.
- Menu entries that depend on a selected file or folder should be built from the current selection context, not from hard-coded global availability.
