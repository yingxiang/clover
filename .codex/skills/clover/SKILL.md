---
name: clover
description: Use when working in the Clover macOS file manager project, especially for Swift/AppKit architecture, multi-pane file browsing, toolbar/popover UI, drag/drop, thumbnails, FileProvider-backed file operations, workspace persistence, app startup, signing, and validation.
---

# Clover Project Skill

Use this skill for development inside the Clover repository.

## First Steps

1. Read `mac_file_manager_ai_execution_plan.md` for product scope and phase requirements.
2. Do not edit `project.yml` for build-setting changes unless the user explicitly asks; this repo may keep hand-tuned `.xcodeproj` settings that should not be regenerated away.
3. When adding/removing files or changing build settings, update `Clover.xcodeproj/project.pbxproj` directly and call out the touched project settings in the final response.
4. Build with `xcodebuild -project Clover.xcodeproj -scheme Clover -destination 'platform=macOS,arch=arm64' build`.
5. Run focused tests after changing domain, provider, file-operation, startup, or persistence behavior.

## Subskills

- Read `references/architecture.md` before changing models, providers, file operations, workspaces, or shared app services.
- Read `references/appkit-ui.md` before changing windows, panes, sidebars, tables, grids, thumbnails, path bars, toolbars/titlebar accessories, popovers, menus, shortcuts, Quick Look, tags, split-view resizing, or drag/drop.
- Read `references/code-organization.md` before adding new controllers, services, views, test suites, or expanding any Swift file that is already near 800 lines.
- Read `references/validation.md` before finishing a task or touching signing, app startup, `project.yml`, sandboxing, or tests.
- Read `references/roadmap.md` when choosing the next implementation phase from the execution plan.

## Core Rules

- Use Swift + AppKit. Do not introduce SwiftUI unless the user explicitly asks.
- Prefer current AppKit/Foundation APIs over deprecated compatibility helpers. When looking up applications, prefer `NSWorkspace.urlForApplication(...)` APIs; when exposing share actions, prefer `NSSharingServicePicker` over deprecated manual service enumeration.
- Swift 6 actor isolation applies to AppKit/Objective-C delegate conformances in this project. When an older Cocoa delegate/protocol crosses actor boundaries, prefer a small `@preconcurrency` conformance or another narrow compatibility fix instead of weakening isolation more broadly.
- UI code must not perform direct file operations with `FileManager`; route file reads/writes through `FileProvider` and `FileOperationService`.
- Disk work must be asynchronous and must not block the main thread.
- Directory listing must return quickly. Do not perform recursive size, thumbnail, image metadata, package inspection, or other expensive per-item work while opening a folder; load that data asynchronously or lazily after the directory contents are visible.
- Preserve the provider abstraction so remote, archive, and sync providers can later use the same UI.
- Use `UserDirectories.homeURL` for the real user's home directory. In the sandbox, `FileManager.default.homeDirectoryForCurrentUser` can point at the container home and break sidebar folders such as Downloads.
- Directory permission checks must test current access each time: first resolve matching security-scoped bookmarks, then try direct directory readability. Do not rely on an "already authorized" flag.
- When using restored bookmarks for user-selected folders such as Downloads, call `startAccessingSecurityScopedResource()` around provider, Quick Look thumbnail/preview, and sharing operations, then balance it with `stopAccessingSecurityScopedResource()`.
- In `LocalFileProvider`, all filesystem operations that need security-scoped access must go through the shared scoped-operation helpers (`runScopedFileOperation(...)` and parent-grouped variants). Do not open/close `SecurityScopedAccess` ad hoc inside individual file operations; this has caused repeated permission regressions, especially for multi-select operations.
- Batch file operations should group or deduplicate security scopes before starting work. Open each needed scope once for the whole operation, then close scopes in reverse order after all files in that scope are processed. Do not repeatedly start/stop the same bookmarked parent for each selected file.
- Normalize permission errors at the provider boundary with the operation's relevant parent/destination URL so the UI can decide whether to prompt. The UI must not infer missing permission without consulting `DirectoryAccessStore` for an existing bookmark.
- Treat list/grid filtering as an in-memory view-model operation. Type-filter changes should use the loaded `allItems` and update visible rows/items without triggering a full pane reload or directory listing.
- Keep existing pane layouts free: single, two vertical, two horizontal, and four-grid. Advanced three-pane layouts such as left-one-right-two, left-two-right-one, top-one-bottom-two, and top-two-bottom-one are Pro-only and should trigger the upgrade window when selected without an active Pro entitlement.
- Keep Release monetization UI purchase-focused: show Upgrade/Purchase entry points before purchase, hide Upgrade to Clover Pro once the lifetime product is active, and keep Restore Purchases / Manage Subscription menu and dialog buttons behind Debug-only controls unless the user explicitly asks to ship them.
- Until the next Pro iteration, expose only the stash shelf and advanced pane layouts in Pro menus, upgrade-page feature lists, and visible paid feature entry points. Keep other Pro v1 feature code available for later development, but do not advertise those entries.
- For the Pro stash shelf glass background, use `NSGlassEffectView` on macOS 26+ and keep an `NSVisualEffectView` fallback for earlier macOS versions.
- Avoid synchronous app bundle icon/display-name lookup on the menu-building path. For Open With menus, show a generic icon immediately, then load and cache app icons asynchronously.
- Keep project-owned Swift files under 1000 lines. When any module file grows beyond 1000 lines, consider splitting it by responsibility before adding more behavior.
- Treat 800 lines as a warning threshold. Prefer extracting focused controllers, views, services, model types, helpers, or tests before the file becomes hard to review.
- Treat any single method over 200 lines as a warning sign. Consider extracting smaller methods, helper types, or focused collaborators before adding more logic.
- After feature work, remove unused or deprecated code paths promptly instead of leaving dead code, commented-out implementations, or stale compatibility shims behind.
- After feature work changes architecture, workflow, UI conventions, or implementation patterns, update this skill or the relevant reference file before finishing.
- Any user-visible copy added in code must go through localization (`L10n` / string catalog). Do not hard-code display text in Swift, menus, alerts, buttons, tooltips, labels, or status messages.
- Do not copy QSpace, Path Finder, Finder, or other products' branding, icons, copy, or proprietary layout details.

## Pane Context Menus

- Keep cross-pane context-menu operations consistent. Copy To, Move To, Compress To, Extract To, Open in Other Pane, and future pane-targeted actions should use the same target model, naming, highlighting, and command routing.
- Target submenus should refer to panes, not windows. Use `Current Pane` for the source pane and `Pane 1`, `Pane 2`, etc. for other panes. Do not mix terms such as Window and Pane in the same target menu family.
- When there is only one pane, hide cross-pane-only actions such as Copy To and Move To. Actions that still make sense in the current pane, such as Compress and Extract To, should remain as direct current-pane commands.
- When multiple panes exist, pane-targeted actions should use a submenu. Compress To and Extract To include `Current Pane`, then a separator, then other pane targets. Copy To and Move To list only other pane targets because current-pane copy/move is not useful.
- Hovering a non-current pane target in any pane-targeted submenu must show the same pane selection overlay and highlight behavior used by Open in Other Pane. Closing the submenu must hide the overlays.
- Executing a target-pane action should route through `PaneLayoutController` to the destination `FilePaneViewController`, use that pane's `viewModel.currentURL` as the destination directory, refresh/select results in the destination pane when applicable, focus the destination pane, and hide pane overlays.
- Keep file operations behind `FilePaneViewModel` and `FileOperationService`/`FileProvider`; context-menu code should build commands and route targets, not perform direct filesystem work.

## Pane Drag And Drop

- Keep file drag/drop behavior consistent across panes and windows in list and grid modes. Resolve drops through pane state: dropping onto a browsable directory targets that directory; dropping onto blank/non-folder space targets the pane's current folder.
- During file drags, hovering a browsable directory should show it as the drop target and auto-expand it after the normal delay, whether the drag started in the same pane, another pane, another Clover window, or another app.
- When dragging over any visible target row, collapse expanded sibling directories at the same list depth so only the target's sibling group stays focused. Moving from one folder/file to another should not leave unrelated same-level folders expanded behind the drag.
- When the drag moves away from a directory target, exits the pane, or moves over blank/non-folder space, clear the temporary folder drop-target selection and cancel pending folder expansion. The destination pane itself should still activate/highlight as the current drop target.
- Drag sources should write selected file URLs plus pane-source identity metadata to the pasteboard so same-pane and cross-pane hover behavior can be distinguished reliably.
- Execute moves through `FilePaneViewModel` and `FileOperationService`, not direct UI-layer `FileManager` calls.

## Pro Stash Shelf

- Current free features must stay free. Gate only new Pro v1 features such as the stash shelf.
- Keep the stash shelf lightweight and Finder-like: a small floating, borderless AppKit window, draggable but not resizable.
- Use a glass/liquid-glass background. On macOS 26+, use `NSGlassEffectView`; on earlier macOS, fall back to `NSVisualEffectView`.
- The shelf glass should have a small radius, a subtle `NSColor.separatorColor` border, and a larger non-clipped drag-over highlight using border/fill rather than a hard clipped shadow.
- Empty state shows only a centered plus icon on glass. Hide the move button when empty; the whole empty shelf window should be draggable.
- Non-empty state shows file thumbnails as a stack. The newest file is on top; one file is not rotated, multiple files are slightly rotated and offset. Show a bottom-centered red count badge.
- Stashed file thumbnails use a white background at about 30% opacity, corner radius 5, no extra border.
- Keep moving the shelf distinct from dragging files out: the move button appears at the top-left only when files exist; dragging/clicking the stack should operate on stashed files.
- External file drops must be accepted reliably across the whole shelf surface, including the center over thumbnails or the plus icon. Deduplicate stashed files by canonical path.
- Dragging stashed files out of the shelf must use the same Finder-like external drag contract as pane drags: write file URLs plus filename/path compatibility data for external inputs and file-accepting controls, and advertise copy-only semantics to non-local targets.
- Stash shelf drag visuals must preserve the thumbnail snapshot aspect ratio. Do not stretch the stack snapshot into the full shelf hit area; center the drag frame using the snapshot's own size.
- Clicking the stack opens a centered popover below the shelf; clicking again closes it. Popover items use the same thumbnail background/radius as shelf items.
- Popover content should stay centered, keep its arrow anchored to the shelf center, and update its content size when files are removed so narrow lists can shrink without visible jitter.
- Each popover file item has a small remove button. Right-click shelf menu includes clearing the stash and closing the window.
