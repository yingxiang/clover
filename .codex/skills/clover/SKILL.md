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
- Read `references/appkit-ui.md` before changing windows, panes, sidebars, tables, grids, thumbnails, path bars, toolbars, popovers, menus, shortcuts, Quick Look, or drag/drop.
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
- When using restored bookmarks for user-selected folders such as Downloads, call `startAccessingSecurityScopedResource()` around provider operations and balance it with `stopAccessingSecurityScopedResource()`.
- Keep project-owned Swift files under 1000 lines. Before adding substantial behavior, check the target file length with `wc -l`; if the edit would push it past 1000 lines, split by responsibility first.
- Treat 800 lines as a warning threshold. Prefer extracting focused controllers, views, services, model types, helpers, or tests before the file becomes hard to review.
- Do not copy QSpace, Path Finder, Finder, or other products' branding, icons, copy, or proprietary layout details.
