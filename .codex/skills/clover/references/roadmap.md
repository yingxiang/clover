# Clover Roadmap Subskill

Use this reference when choosing the next implementation phase from `mac_file_manager_ai_execution_plan.md`.

## Current Implementation Order

1. AppKit app shell and visible main window.
2. Domain models: file item, pane state, workspace, sort option, view mode.
3. Provider layer: `FileProvider`, `LocalFileProvider`, async directory listing, metadata loading.
4. Single-pane table browsing.
5. Path bar and directory navigation.
6. Multi-pane layouts and active-pane handling.
7. File operations: copy, move, rename, new folder, trash.
8. Workspace persistence and restoration.
9. Sidebar favorites and common locations.
10. Search within the current directory.
11. Quick Look preview.
12. Drag/drop between panes.
13. Context menus, toolbar commands, and shortcuts.
14. Icon view foundation.

## First-Version Scope

Must eventually include:

- Main window.
- Multi-pane layout switching.
- Local file browsing.
- List view.
- Basic icon view.
- Address/path bar.
- Copy, move, rename, new folder, and trash.
- Pane-to-pane drag/drop.
- Workspace save and restore.
- Current-directory search.
- Quick Look preview.
- Basic context menu.
- Basic keyboard shortcuts.

Out of first-version scope:

- Remote connections.
- Cloud-drive-specific integrations.
- Archive interior browsing.
- Folder sync.
- Advanced batch rename.
- Plugin system.
- Multi-device sync.
- Payment system.

## Acceptance Style

Each phase should finish with:

- A running app or focused test proving the behavior.
- Clear file list of touched implementation areas.
- Known omissions from the plan, stated explicitly.
