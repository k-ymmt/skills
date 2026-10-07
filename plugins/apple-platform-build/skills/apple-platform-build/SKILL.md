---
name: apple-platform-build
description: Build, test, run, and diagnose Xcode projects for iOS, macOS, watchOS, tvOS, and visionOS. Use whenever a task involves compiling Swift or Objective-C code in an .xcodeproj or .xcworkspace, running XCTest or Swift Testing suites, rendering SwiftUI previews, reading build errors, or driving a simulator. Prefers the Xcode MCP server bundled with this plugin and falls back to xcodebuild.
argument-hint: "[scheme or task, e.g. 'run unit tests' or 'build MyApp']"
metadata:
  short-description: Build and test Apple projects via Xcode MCP
---

# Apple Platform Build

Drive the user's Xcode workspace through Xcode itself instead of re-deriving the build from the command line.

## Task

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention; with nothing given, build the active scheme and report the result.

## Why the Xcode MCP server first

This plugin registers an MCP server named `xcode` that runs `xcrun mcpbridge`, Apple's bridge into the running Xcode (Xcode 26.3 or later). Building through it reuses Xcode's own build system, derived data, signing, and run destinations, so results match what the user sees in the IDE and incremental builds stay fast. `xcodebuild` from a shell starts a separate build service, can pick different settings, and loses the preview, debugger, and device-interaction tools entirely. Use the shell only when the bridge is unavailable.

## Preconditions

The bridge only works when Xcode is running with the workspace open and **Xcode > Settings > Intelligence > Model Context Protocol > Xcode Tools** enabled. If the `xcode` tools are missing from your tool list or the first call fails:

1. Say so in one sentence and name the setting above so the user can enable it.
2. Fall back to the shell commands in the last section. Do not silently switch.

## Workflow

1. **Find the workspace.** `XcodeListWorkspaces` shows what Xcode has open. If the project is not open, `XcodeOpenWorkspace` with the absolute path to the `.xcworkspace` (preferred) or `.xcodeproj`. Pass the returned workspace identifier to later calls when more than one workspace is open.
2. **Pick scheme and destination.** `XcodeListSchemes` and `XcodeListRunDestinations`; switch with `XcodeSwitchScheme` / `XcodeSwitchRunDestination` only when the active ones do not match the task. Tell the user if you change them, since the choice persists in their IDE.
3. **Build.** `BuildProject`, then `GetBuildLog` filtered to errors (add warnings only when the user asked about them). Fix errors in source, then rebuild; stop and report after three failed rounds on the same error rather than thrashing.
4. **Test.** `GetTestList` to confirm the targets exist, then `RunAllTests` or `RunSomeTests` with specific identifiers. Read failures from the result; `GetConsoleOutput` has the log lines when an assertion message is not enough.
5. **Run or preview when the task needs it.** `RunProject` launches the active scheme; `RenderPreview` returns a snapshot of a SwiftUI preview and is the fastest way to check a view change. `DeviceInteractionStartWorkspaceSession` then `DeviceInteractionInstallAndRun` and `DeviceInteractionSynthesize` drive the simulator for UI checks; end with `DeviceInteractionEndSession`.
   For layout correctness (text cut off, overlaps, off-screen content, tap targets), use the `apvt` skill of this plugin: it reads the real frames from the running simulator app. Note that apvt needs the app relaunched with `xcrun simctl launch`, not `RunProject`.
6. **Diagnose without a full build.** `XcodeRefreshCodeIssuesInFile` gives compiler diagnostics for one file; `GetTargetBuildSettings` answers "which setting is this target using"; `DocumentationSearch` beats guessing at an Apple API signature.

## Editing files

Prefer your own file tools for source edits; they work on filesystem paths. Use `XcodeWrite` / `XcodeMV` / `XcodeRM` only when a change must also update the project navigator, for example adding a new file to a target that lacks a synchronized folder, because those tools take Xcode project paths rather than filesystem paths.

## Shell fallback

When the bridge is unavailable, use `xcodebuild` and keep its output readable:

```bash
xcodebuild -list -json -workspace App.xcworkspace
xcodebuild build -workspace App.xcworkspace -scheme App -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E 'error:|warning:|BUILD'
xcodebuild test -workspace App.xcworkspace -scheme App -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E 'error:|failed|passed|Executed'
```

Use `-project` instead of `-workspace` for a bare `.xcodeproj`, and `swift build` / `swift test` for a Swift package without an Xcode project. Report the exact failing command and its error lines, not a summary.
