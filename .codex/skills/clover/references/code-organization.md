# Clover Code Organization Subskill

Use this reference before adding new controllers, services, views, test suites, or expanding a Swift file that is already near 800 lines.

## File Size Guardrails

- Treat 800 lines as a warning threshold and 1000 lines as a hard threshold for project-owned Swift files.
- Before adding substantial code, check the target file with `wc -l path/to/File.swift`.
- Do not intentionally push a project-owned Swift file over 1000 lines. Split by responsibility first.
- If a file is already over 1000 lines, avoid adding new behavior there unless the immediate task is to split or stabilize it.
- Generated files, vendored files, and Xcode-managed project files are outside this Swift source-size rule, but avoid editing generated output directly unless required.

## Split Patterns

- App composition: keep app delegate, scene/window setup, and dependency assembly in separate files when they grow.
- Window and toolbar UI: move toolbar item factories, popover controllers, icon drawing, and menu builders out of large window controllers.
- Pane UI: keep table view subclasses, context-menu routing, path bar views, status views, and drag/drop delegates in focused files.
- Domain logic: keep codable state, enums, sorting, filtering, and navigation history in separate files when each grows real behavior.
- Infrastructure: split protocols, concrete providers, operation services, persistence stores, conflict policies, and error mapping into named files.
- Tests: split test suites by feature once a test file approaches 800 lines; move reusable fixtures into focused test-support files.

## Naming Rules

- Prefer names that describe product responsibility, such as `LayoutPickerViewController`, `FilePaneContextMenuController`, or `WorkspacePersistenceStore`.
- Avoid catch-all files such as `Helpers.swift`, `Utils.swift`, or `Extensions.swift` unless they remain tiny and tightly scoped.
- Extensions in the same file still count toward the 1000-line limit. Move meaningful extensions into their own focused files.

## Review Checklist

Before finishing a meaningful code change, run:

```bash
find Clover Tests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head
```

Then:

- Inspect any file at or above 800 lines.
- Split any project-owned Swift file over 1000 lines, or clearly state why it is a temporary exception.
- Keep the split aligned with existing folders and `project.yml`; run `xcodegen generate` if files are added or removed.
