---
name: clover
description: Use when working in the Clover macOS file manager project, especially for Swift/AppKit architecture, multi-pane file browsing, toolbar/popover UI, drag/drop, thumbnails, FileProvider-backed file operations, workspace persistence, app startup, signing, and validation.
---

# Clover Project Skill

Use this skill for development inside the Clover repository.

## First Steps

1. Read `mac_file_manager_ai_execution_plan.md` for product scope and phase requirements.
2. Keep `project.yml` as the source for generated Xcode settings.
3. Run `xcodegen generate` after adding/removing files or changing build settings. If `xcodegen` is unavailable in the local environment, update `Clover.xcodeproj/project.pbxproj` manually and call that out in the final response.
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
- Treat list/grid filtering as an in-memory view-model operation. Type-filter changes should use the loaded `allItems` and update visible rows/items without triggering a full pane reload or directory listing.
- Keep existing pane layouts free: single, two vertical, two horizontal, and four-grid. Advanced three-pane layouts such as left-one-right-two, left-two-right-one, top-one-bottom-two, and top-two-bottom-one are Pro-only and should trigger the upgrade window when selected without an active Pro entitlement.
- For the Pro stash shelf glass background, use `NSGlassEffectView` on macOS 26+ and keep an `NSVisualEffectView` fallback for earlier macOS versions.
- Avoid synchronous app bundle icon/display-name lookup on the menu-building path. For Open With menus, show a generic icon immediately, then load and cache app icons asynchronously.
- Keep project-owned Swift files under 1000 lines. When any module file grows beyond 1000 lines, consider splitting it by responsibility before adding more behavior.
- Treat 800 lines as a warning threshold. Prefer extracting focused controllers, views, services, model types, helpers, or tests before the file becomes hard to review.
- Treat any single method over 200 lines as a warning sign. Consider extracting smaller methods, helper types, or focused collaborators before adding more logic.
- After feature work, remove unused or deprecated code paths promptly instead of leaving dead code, commented-out implementations, or stale compatibility shims behind.
- After feature work changes architecture, workflow, UI conventions, or implementation patterns, update this skill or the relevant reference file before finishing.
- Any user-visible copy added in code must go through localization (`L10n` / string catalog). Do not hard-code display text in Swift, menus, alerts, buttons, tooltips, labels, or status messages.
- Do not copy QSpace, Path Finder, Finder, or other products' branding, icons, copy, or proprietary layout details.

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
- Clicking the stack opens a centered popover below the shelf; clicking again closes it. Popover items use the same thumbnail background/radius as shelf items.
- Popover content should stay centered, keep its arrow anchored to the shelf center, and update its content size when files are removed so narrow lists can shrink without visible jitter.
- Each popover file item has a small remove button. Right-click shelf menu includes clearing the stash and closing the window.
