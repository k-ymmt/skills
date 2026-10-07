---
name: apvt
description: Find and fix layout mistakes in an iOS app running in the iOS Simulator with apvt (Apple Platform View Tester), which reads the live UIKit and SwiftUI view tree with frames in points. Use after changing a SwiftUI view or UIKit layout, when a user reports text cut off, overlapping, truncated, off-screen, under the status bar, or too small to tap, or when asked to verify a screen's layout, assert view positions, or get an annotated screenshot of the simulator. Not for macOS apps, physical devices, or color contrast.
argument-hint: "[screen or question, e.g. 'check the profile screen' or 'is #follow at least 44pt wide']"
metadata:
  short-description: Find layout bugs in a running iOS Simulator app
---

# apvt: see the real layout of a simulator app

`apvt` (https://github.com/k-ymmt/apvt) injects a small agent into apps launched on the iOS Simulator and reports what the views really look like: the tree with frames in screen points, and the layout mistakes in it. Use it instead of guessing from a screenshot or from the source, because SwiftUI's final frames are only known at runtime and a screenshot cannot tell a truncated text from an intentionally short one.

## Task

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention; with nothing given, inspect the screen the simulator currently shows and fix the errors it reports.

## Preconditions

- `apvt` on PATH. If `apvt --version` fails, tell the user in one sentence and give `brew install k-ymmt/tap/apvt`; do not install it unasked. It needs macOS 15+, Xcode with the iOS Simulator platform, and Swift 6.2+.
- Only the iOS Simulator is supported. For a device or a macOS app, say so and fall back to the Xcode MCP tools of the `apple-platform-build` skill. To verify behavior (taps, flows, crashes, logs) rather than layout alone, use the `simulator-verify` skill, which drives the app and calls apvt on each screen.
- One booted simulator, or pass `--device <name|udid>` to every command.

## Workflow

1. **Set up once per simulator boot.** `apvt status` says whether each booted simulator is set up and which running apps carry the agent. If it is not set up, run `apvt setup` (the first run builds the agent for the simulator; a few seconds). The setup lasts until the simulator shuts down.
2. **Launch so the agent loads.** Xcode's launch replaces the environment variable that `apvt setup` puts into launchd, so an app started by Xcode's Run, `RunProject`, or `DeviceInteractionInstallAndRun` answers nothing unless you hand that launch the agent yourself:
   - With the Xcode MCP server: `apvt launch-env --device <udid>` prints the variables as JSON; add `"$(inherited)": ""` and pass them as `environmentVariables` of `DeviceInteractionInstallAndRun`. The app keeps Xcode's console (`GetConsoleOutput`). The `simulator-verify` skill builds on this.
   - Otherwise build (`BuildProject` or `xcodebuild`), make sure the build is installed (Xcode's Run installs it; a bare build needs `xcrun simctl install booted <path/to/App.app>`), and start it from the command line:

     ```bash
     xcrun simctl terminate booted <bundle-id>; xcrun simctl launch booted <bundle-id>
     ```

   `apvt status` shows which apps carry the agent (`loaded by launchd` or `loaded by env`) and prints the relaunch command for every app running without it. The bundle id is `PRODUCT_BUNDLE_IDENTIFIER` in the target's build settings, or in `xcrun simctl listapps booted`. `launch-env` and `type` need apvt newer than 0.1.0; with 0.1.0 use the simctl relaunch.
3. **Reach the screen.** Launch arguments (`xcrun simctl launch booted <bundle-id> -screen profile`), a deep link (`xcrun simctl openurl booted <url>`), or the simulator interaction tools you already have. To fill a text field, tap it and run `apvt type "text"` (`--replace`, `--submit` for Return). Only the foreground app answers; iOS suspends the others.
4. **Inspect.** Right after a launch, add `--wait 10`:

   ```bash
   apvt inspect --wait 10
   ```

   Each line names a rule, a node `@N`, its frame `(x,y widthxheight)` in points, and what is wrong, followed by how to fix that kind of issue. Exit code 1 means at least one error; 0 means none (`--fail-on warning` to tighten, `--fail-on never` for a report only). Before changing code, keep the evidence: `apvt inspect --save before.json --annotate before.png`, and read the PNG when the text alone does not make the problem clear.
5. **Understand one node before editing.** `apvt query @N` shows the node, its ancestors with their frames and SwiftUI modifiers, text metrics (the width the text needs versus what it has), and its issues; this is what points at the modifier or constraint to change. `apvt tree --root <selector>` shows a subtree; `apvt rules` repeats the fix for each rule. Rule messages already name suspects (for example the `.fixedSize` child that pushed a container past the screen); start from those.
6. **Fix, rebuild, relaunch, inspect again.** Node numbers change between snapshots, so re-read them from the new `inspect` output instead of reusing old `@N`. Stop and report after three rounds on the same issue rather than thrashing.
7. **Assert what you meant**, not only that `inspect` is quiet. `inspect` checks only its listed rules; an assertion fixes the intent in a command the user can rerun:

   ```bash
   apvt assert '#follow' --visible --inside safe-area --min-width 44
   apvt assert 'type:Text,text:Inbox' --not-truncated --no-overlap
   apvt assert '#plan-free' --same-width '#plan-pro' --align-top '#plan-pro' --left-of '#plan-pro' --spacing 12
   ```

   Selectors: `@12`, `#identifier`, `text:Sub`, `text="Exact"`, `type:Button`, `role:control`, terms joined by commas. References (`--inside`, `--align-*`, `--left-of`, …) must match exactly one node, or be `screen` / `safe-area`.

## Reporting

Quote the issue lines from `inspect` as apvt printed them, say which source change fixed each, and end with the final `apvt inspect` or `apvt assert` result. When you could not verify, for example because the app could not be relaunched under the agent, say that first instead of reporting the fix as done. Include the annotated screenshot path when you wrote one.

## Limits worth knowing

- Fonts are only partly visible to the agent; an issue that relies on a guessed font is reported as a warning, not an error. Read warnings with that in mind.
- Contrast and color are not checked. Content inside a scroll view is not flagged as offscreen.
- Private framework views and system chrome (navigation bar, keyboard) are folded out of the tree and out of the issues; `--all` on `tree` or `--include-system` on `query`/`assert` brings them back.
- Every command takes `--json` for parsing and `--snapshot file.json` to re-read a saved snapshot without the app. `screenshot` and `--annotate` need the running app.
- `apvt teardown` undoes the setup when the user wants the simulator back to normal.

The full command, selector, assertion and rule reference is in [references/commands.md](references/commands.md).
