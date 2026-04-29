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

## Manual Review

Before final response:

- Search for direct UI-layer `FileManager` usage when touching file operations.
- Confirm `project.yml` and generated Xcode settings do not undo user-provided bundle ID, team ID, or signing choices.
- Mention unimplemented execution-plan phases plainly.
