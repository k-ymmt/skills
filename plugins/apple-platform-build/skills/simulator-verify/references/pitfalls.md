# Pitfalls and fixes

Observed while testing this skill on Xcode 27.1 beta with iOS 27 simulators.

## Setup and sessions

- **`XcodeOpenWorkspace` with a wrong key** answers "can't be put in front of the user for
  approval. Retry it with a plain absolute path." The key is `path`.
- **Slow first calls**: after Xcode or a simulator starts, `XcodeListWorkspaces`,
  `XcodeOpenWorkspace` and the first `DeviceInteractionInstallAndRun` have taken 90–120 s each
  (four simulators were booting at the time); later calls take seconds. Give them a time limit of
  at least 240 s (`perl -e 'alarm shift; exec @ARGV' 240 <command>` from a shell; macOS has no
  `timeout`) and wait, instead of retrying or starting a second session.
- **`workspaceIdentifier is required`**: pass it to every Xcode tool, even with one workspace open.
- **Shared workspaces**: when two agents use the same project, `GetConsoleOutput` returns that
  workspace's latest launch. Check the PID in its `launchSessionInfo` against your
  `Application, pid:` line.
- **One session per device; names are single-use; idle sessions expire.** "already in use by a
  different session with key …" means a session was not ended. "Session not found" means it
  expired or was ended: start a new one with a new name.
- **Hung install**: if `DeviceInteractionInstallAndRun` or a capture hangs for minutes, or
  `xcrun simctl install <udid> <App.app>` never returns, the simulator is wedged. Reboot it
  (`xcrun simctl shutdown <udid>; xcrun simctl boot <udid>`), run `apvt setup` again, and start a
  new session.
- **Older apvt without `launch-env`**: launch with `DeviceInteractionInstallAndRun`, then relaunch
  with `xcrun simctl terminate <udid> <bundle-id>; xcrun simctl launch <udid> <bundle-id>`. That
  launch has the agent but no `GetConsoleOutput`; read logs with
  `xcrun simctl spawn <udid> log show --last 5m --predicate 'process == "<App>"'`.
- **No agent answers** (`apvt` exit 3): the app was launched without `launch-env`'s variables, is in
  the background, or is still starting (`--wait 10`). `apvt status` says which.

## Interaction

- **First action after launch is lost**: capture until the first screen is in the hierarchy.
- **"Slide to type" introduction**: a fresh simulator shows it over the keyboard on the first
  focus; tap its `Continue`.
- **Keyboard moves controls**: a footer can move by hundreds of points while the keyboard is up.
  Re-read hitPoints; dismiss the keyboard with `apvt type "" --submit` or a tap on empty space.
- **Typing with key taps** (no apvt): wait about 1 s after focusing the field before the first key
  (`t x y w 1 t …`); earlier taps lose characters.
- **`apvt type` failed with "stopped answering"**: the text or Return crashed the app; capture.
  "nothing has keyboard focus": tap the field first, or the screen changed.
- **Ruling out the tools**: if every attempt crashes and you suspect apvt, relaunch once without
  `environmentVariables` and repeat the step with key taps. If it still crashes, the app is at fault.
- **A tap does nothing**: recapture (an animation may have moved the element) and retry once with
  the new hitPoint. Then report it, since an unresponsive control is a bug.
- **Taps near the bottom**: a plain tap in the bottom 34pt (home indicator) works; a swipe that
  starts there goes home.
- **No children**: an element marked `isRemoteLeafPlaceholder`, or content drawn without
  accessibility (a canvas, a map), has none. Estimate from the screenshot and say so.
- **Secure fields** show `•••` as their value in the hierarchy and look empty in screenshots.
- **Screenshots** are in points (402x874 on an iPhone 17 Pro), the same scale as the coordinates.
- **SpringBoard's labels** follow the simulator's language; do not grep the home screen for English.

## Console noise

`GetConsoleOutput`'s `pattern` matches the message text only, not the `[category]` prefix shown
before it. Timestamps of stdout and OSLog lines are not mutually ordered. Error-level lines that
come from the simulator or the capture machinery, not from the app:

- `[AXUIA] This child can't be serialized correctly`
- `[XPCErrors] non-launching port is incompatible with service identifier "com.apple.PointerUI…"`
- `[API] cannot add handler to 0 from 0 - dropping`
- `Failed to send CA Event for app launch measurements`
- `[AXValidations] AX Safe category class '…' was not found!`
- `Class … is implemented in both …` (stdout)
- `[hapi] CHHapticPattern … hapticpatternlibrary.plist` and `Failed to read pattern library
  data` (keyboard haptics, many per launch; the latter matches `fail`)
- `Connection from client with pid … was invalidated` (matches `invalid`)
- Lines caused by captures: `Replying to query`, `found matching snapshots`, `(error: (null))`

The app's own lines carry its subsystem's category (for example `[shop]`), or come on stdout
(`outputType: "stdio"`): `print` output and Swift runtime errors such as
`Fatal error: Index out of range`.

## Crash reports

`~/Library/Logs/DiagnosticReports/<App>-<date>.ips` is a one-line JSON header followed by a JSON
body, so `jq` on the whole file fails. The crashed thread has `"triggered": true`; its frames
point into `usedImages` by `imageIndex`; a debug build's code is in `<App>.debug.dylib`.
`scripts/crash_report.py <App>` prints the summary.
