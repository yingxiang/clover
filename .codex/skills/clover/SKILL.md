---
name: clover
description: Use when working in the Clover macOS file manager project, especially for Swift/AppKit architecture, multi-pane file browsing, FileProvider-backed file operations, workspace persistence, app startup, signing, and validation.
---

# Clover Project Skill

Use this skill for development inside the Clover repository.

## First Steps

1. Read `mac_file_manager_ai_execution_plan.md` for product scope and phase requirements.
2. Keep `project.yml` as the source for generated Xcode settings.
3. Run `xcodegen generate` after adding/removing files or changing build settings.
4. Build with `xcodebuild -project Clover.xcodeproj -scheme Clover -destination 'platform=macOS,arch=arm64' build`.
5. Run focused tests after changing domain, provider, file-operation, startup, or persistence behavior.

## Subskills

- Read `references/architecture.md` before changing models, providers, file operations, workspaces, or shared app services.
- Read `references/appkit-ui.md` before changing windows, panes, sidebars, tables, path bars, toolbars, menus, shortcuts, or drag/drop.
- Read `references/validation.md` before finishing a task or touching signing, app startup, `project.yml`, sandboxing, or tests.
- Read `references/roadmap.md` when choosing the next implementation phase from the execution plan.

## Core Rules

- Use Swift + AppKit. Do not introduce SwiftUI unless the user explicitly asks.
- UI code must not perform direct file operations with `FileManager`; route file reads/writes through `FileProvider` and `FileOperationService`.
- Disk work must be asynchronous and must not block the main thread.
- Preserve the provider abstraction so remote, archive, and sync providers can later use the same UI.
- Do not copy QSpace, Path Finder, Finder, or other products' branding, icons, copy, or proprietary layout details.
