# Xcode device interaction: commands, hierarchy, quirks

Observed with Xcode 27.1 (27A9269) and iOS 27 simulators through `xcrun mcpbridge`. Xcode's own
agent gets this from a built-in `device-interaction` skill that other agents cannot load; the
syntax below was recovered by calling the tools. When a command is rejected, the error names the
expected shape (for example `Expected at least 3 components (t x y)`).

## Tools

| tool | use |
|---|---|
| `XcodeListWorkspaces` | Every workspace open in Xcode, also other agents' and the user's: match `workspacePath` exactly. |
| `XcodeOpenWorkspace` | `{path}`: absolute path to the `.xcodeproj` / `.xcworkspace`. Returns `workspaceIdentifier`, active scheme and destination. A wrong key returns "can't be put in front of the user for approval. Retry it with a plain absolute path." |
| `DeviceInteractionStartWorkspaceSession` | `{workspaceIdentifier, deviceIdentifier, sessionIdentifier}`. Boots the device if needed. Needed for `InstallAndRun`. One session per device. |
| `DeviceInteractionStartSession` | Same without a workspace: only for an app that is already installed. |
| `DeviceInteractionInstallAndRun` | `{interactionSessionKey, workspaceIdentifier, environmentVariables?, commandLineArguments?}`. Builds, installs, launches. `"$(inherited)"` keeps the scheme's arguments (as an array element) or variables (as a key with value `""`). Applies to this launch only. |
| `DeviceInteractionSynthesize` | `{interactSessionKey, interactionCommand?, activationBundleId?}`. Note the key is `interactSessionKey` here. Runs the command, then returns `applicationState`, `hierarchyPath`, `screenshotPath`, `thumbnailScreenshotPath`, `logsPath`. No command = capture only. |
| `DeviceInteractionEndSession` | `{interactionSessionKey}`. Always call it. |
| `GetConsoleOutput` | `{workspaceIdentifier, pattern?, oslogSeverity?, outputType?, tailLimit?}`: stdout, stderr and OSLog of the latest launch. `launchSessionInfo` says `State: started` while it runs, `expired` after it ended or crashed. |
| `StopProject` | Stops the app Xcode launched. |

## Interaction commands

Coordinates are points, origin top-left, the same space as apvt frames. Commands chain with
spaces and run in order: `t 100 200 w 0.5 t 100 260`.

| command | does |
|---|---|
| `t x y` | tap |
| `t x y 1.0` | press and hold for 1.0 s (long press, context menu) |
| `d x y` | double tap |
| `t x1 y1 f x2 y2 [seconds]` | swipe from (x1,y1) to (x2,y2): `t 200 650 f 200 250 0.3` scrolls down the content, `t 200 250 f 200 650 0.3` scrolls up, `t 380 300 f 60 300 0.3` swipes a row left (delete actions) |
| `drag x1 y1 x2 y2 [hold] [move]` | press, hold, move slowly, release (reorder, drag and drop) |
| `mt [x y, x y] dur [x y, x y] dur` | multi-touch keyframes, e.g. a pinch `mt [100 300, 300 300] 0.5 [175 300, 225 300] 0.5` |
| `b h` / `b p` / `b u` / `b d` | hardware button: home, power, volume up, volume down |
| `w 0.5` | wait |
| `orientation landscapeLeft` | rotate: `portrait`, `portraitUpsideDown`, `landscapeLeft`, `landscapeRight`, `faceUp`, `faceDown` |

Text: the documented `kbd <text>` command is rejected ("Invalid command: 'kbd'"). Use
`apvt type`. Without apvt, tap the keys: the hierarchy lists each `Key` with its hitPoint while
the keyboard is up (`Key, …, label: 'Q', hitPoint: {24.3, 624.0}`), and taps can be chained.

`activationBundleId` brings another app to the front before the command (after pressing home, or
when the hierarchy shows several apps). It is slow; use it only when needed.

## Reading the hierarchy file

```
Application bundle identifier: dev.verify.todo
Application, pid: 57189, label: 'TodoApp'
 Window, {{0.0, 0.0}, {402.0, 874.0}}, hitPoint: {201.0, 437.0}
           TextField, {{16.0, 184.0}, {331.3, 34.0}}, identifier: 'new-task', placeholderValue: 'New task', value: Buy eggs, Keyboard Focused, hitPoint: {181.7, 201.0}
           Button, {{355.3, 191.0}, {30.7, 20.3}}, identifier: 'add', label: 'Add', hitPoint: {370.7, 201.2}
                Image, {{33.3, 286.7}, {17.0, 17.0}}, identifier: 'check-Call Alex', label: 'Selected', Selected, hitPoint: {41.8, 295.2}
```

- `Device orientation: Unknown` on top is normal on the simulator; `Application UI orientation`
  is the app's.
- `{{x, y}, {width, height}}` is the frame; `hitPoint` is where to tap.
- `identifier:` is the accessibility identifier (SwiftUI `.accessibilityIdentifier`), `label:` the
  accessibility label or visible text, `value:` a field's text or a control's value,
  `placeholderValue:` the placeholder. `Selected`, `Keyboard Focused`, `Disabled` are states.
- Labels of SF Symbols are their accessibility names (`checkmark.circle.fill` reads `Selected`,
  `circle` reads `Circle`).
- The first lines name the foreground app. `com.apple.springboard` there means your app is not in
  front: it crashed, or a system button sent it away.
- Lazy lists and scroll views only list what is on screen; scroll, then capture again.
- While the edit menu is shown, its items are `MenuItem` lines (`Cut`, `Copy`, `Paste`, `AutoFill`).

Screenshots (`screenshotPath`) are in points, the same size as the coordinates (402x874 on an
iPhone 17 Pro), not in @3x pixels; crop with hierarchy frames directly.

## Filtering the hierarchy

[../scripts/hierarchy.py](../scripts/hierarchy.py) prints a hierarchy without the noise. Most
lines of a raw hierarchy are layout containers (`Other, {{…}}, hitPoint: …` with nothing else) and,
while a field has focus, the keyboard's `Key` rows; the script drops both (and the
keyboard's suggestion bar) but keeps the `Keyboard` line and the field's `Keyboard Focused` state. Plain grep works too, but `grep -v Keyboard` would drop the focused field.

## applicationState

`Running`, `RunningInBackground` (another app is in front; `activationBundleId` brings it back),
`NotRun` (session without an app launch), `Crashed`.

## Crash evidence

1. `applicationState: Crashed` and SpringBoard in front in the capture after the action.
2. `GetConsoleOutput` with `pattern: "Fatal error|fault|Exception|signal"`, for example
   `Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range`.
3. The newest `~/Library/Logs/DiagnosticReports/<AppName>-<date>.ips` has the thread backtrace.
   It is a one-line JSON header followed by a JSON body (so `jq` on the whole file fails); the
   crashed thread is the one with `"triggered": true`, and frames point into `usedImages` by
   `imageIndex`. Debug builds put the app's code in `<App>.debug.dylib`.
   [../scripts/crash_report.py](../scripts/crash_report.py) `<AppName>` prints this summary.
4. After a crash, `DeviceInteractionInstallAndRun` in the same session relaunches the app with a
   fresh state.

## Quirks

The observed quirks of these tools, and what to do about them, are in [pitfalls.md](pitfalls.md).
