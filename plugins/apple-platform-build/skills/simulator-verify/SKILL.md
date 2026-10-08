---
name: simulator-verify
description: Verify that an iOS app really works by driving it in the iOS Simulator - build and launch it through the Xcode MCP server, tap, swipe and type through its flows, check each result in the live UI hierarchy, catch crashes and console errors, and check every screen's layout with apvt. Use after implementing or fixing a feature, when asked to test, QA, smoke-test or "check that it works" on the simulator, to reproduce a reported bug, or to walk through a spec or acceptance criteria. Not for unit tests alone (use apple-platform-build), physical devices, or macOS apps.
argument-hint: "[what to verify, e.g. 'the sign-in flow against SPEC.md' or 'adding and deleting todos']"
metadata:
  short-description: Drive an iOS Simulator app to verify features, crashes, logs and layout
---

# Simulator verify: prove the app works, screen by screen

Check the app the way a tester would, with evidence a tester cannot see: the UI hierarchy after every action, the console, crash state, and measured layout. The Xcode MCP server (`xcode`, bundled with this plugin) builds, launches, taps and captures. apvt (see the `apvt` skill) loads an agent into the app that measures layout and types text. Xcode's hierarchy tells you what the app shows; apvt tells you whether it is laid out correctly.

## Task

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention; with nothing given, verify the feature you just changed, or ask which flow to check.

## Preconditions

- Xcode 26.3 or later running with **Settings > Intelligence > Model Context Protocol > Xcode Tools** on, so the `xcode` MCP tools exist. If they do not, say so and stop.
- `apvt` with `type` and `launch-env` (`apvt type --help` works). If apvt is missing, give `brew install k-ymmt/tap/apvt` and continue without layout checks and typing; do not install it unasked. For an apvt without those commands, see [references/pitfalls.md](references/pitfalls.md).
- The simulator's UDID (`xcrun simctl list devices booted`). Pass it everywhere so two booted simulators never get confused.

## 1. Write the checklist first

Turn the task, spec or bug report into a numbered checklist of observable expectations: an action, then what the screen must show afterwards. Add the edges the spec implies: empty and whitespace input, boundary lengths, the first, middle and last row of a list and the list after it changed size, the item you must scroll to, a value that changes another value, Return in a field, back navigation, repeating an action, and the failure paths it names. A bug that maps row k to row n-1-k is invisible if you only try the middle row. Reading the source for edge cases is fine; deciding PASS from the source is not.

## 2. Start a session and launch with the apvt agent

1. `XcodeListWorkspaces` and pick your project's entry; compare real paths (`/tmp` is `/private/tmp`), since other agents' and the user's workspaces are listed too. If it is not open, `XcodeOpenWorkspace` with `{"path": "<absolute .xcodeproj or .xcworkspace>"}`. Pass the `workspaceIdentifier` to **every** call. The first Xcode calls after Xcode or a simulator started (`XcodeListWorkspaces`, `XcodeOpenWorkspace`, the first `DeviceInteractionInstallAndRun`) can take one to two minutes; allow at least 240 s before treating one as hung, and do not reissue it meanwhile.
2. `apvt setup --device <udid>` once per simulator boot.
3. `DeviceInteractionStartWorkspaceSession` with `workspaceIdentifier`, `deviceIdentifier: <udid>` and a **new** `sessionIdentifier` such as `verify-login-1432`; names cannot be reused. Its reply asks you to spawn a subagent with a `device-interaction` skill. That skill exists only inside Xcode's own agent; this skill and [references/device-interaction.md](references/device-interaction.md) replace it. Handing the driving to a subagent is still useful when you can: give it the session key, the checklist and this skill.
4. `apvt launch-env --xcode --device <udid>` prints JSON, `"$(inherited)": ""` included. Pass it unchanged as `environmentVariables` of `DeviceInteractionInstallAndRun`, together with `interactionSessionKey` and `workspaceIdentifier`. Without it, Xcode's launch drops the apvt agent. The JSON spans several lines; when you call the tool through a shell wrapper instead of natively, compact it first: `apvt launch-env --xcode --device <udid> | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))'`. Test hooks go in `commandLineArguments`, after `"$(inherited)"`.
5. Check that `apvt status --device <udid>` lists the app as `loaded by env`. Capture once (`DeviceInteractionSynthesize` without `interactionCommand`) and make sure the hierarchy shows the app's first screen; a tap sent earlier is lost. If the checklist has a transient state (a loading spinner), capture right after the launch returns, before anything else.

## 3. Drive each item: capture, act, capture, judge

`DeviceInteractionSynthesize` runs its command, then returns `applicationState` and the paths of a hierarchy file and a screenshot. Loop:

1. **Find the target.** Read the hierarchy with `python3 <this skill>/scripts/hierarchy.py FILE ['regex' …]`, where FILE is the hierarchy path, the Synthesize JSON (or a file holding it), or `-` for stdin. It drops empty containers and the keyboard's insides; with regexes it prints only matching lines. Tap an element's `hitPoint: {x, y}` (points). In a list row, tap the label inside, not the `Cell`; for a `Stepper`, tap its `-Increment` / `-Decrement` children. Do not tap a hitPoint that lies under the navigation or tab bar: scroll first. An element pushed partly off the screen (in a sheet, say) cannot be scrolled into view: tap its visible part and report the layout FAIL. Estimate from the screenshot only after a hitPoint tap did nothing.
2. **Act.** `t x y` tap, `t x y 1.0` long press, `d x y` double tap, `t x1 y1 f x2 y2 0.3` swipe or scroll (`t 200 650 f 200 250 0.3` scrolls down), `w 0.5` wait. Commands chain with spaces; end the chain at every step whose result decides an item.
3. **Type with apvt.** Tap the field, then `apvt type --device <udid> "text"`; `--replace` clears it first, `--submit` presses Return. Xcode's own text command does not work. Take hitPoints from a capture made after the keyboard appeared, because controls below it move.
4. **Judge from the new hierarchy.** Compare it with the capture before the action: the element you acted on must have changed (label, `value:`, `Selected`, rows), and nothing else should have. A counter that moved does not prove the right row changed. Open the screenshot when the result is visual.
5. **Check the app is alive.** `applicationState` must stay `Running`. `Crashed`, or SpringBoard in front, means the last action killed the app. Get the reason from `GetConsoleOutput` with `{"pattern": "Fatal error|fault|Exception|signal"}`, and the crashed line from `python3 <this skill>/scripts/crash_report.py <AppName>`. Then call the same `DeviceInteractionInstallAndRun` again; the app restarts fresh in the same session.
6. **Check the layout on each new screen.** Run `apvt inspect --device <udid> --wait 5`; it exits 1 on an error. Errors are bugs, Auto Layout conflicts included (they appear only here). An `overlap`, `truncated` or `unsafe-area` warning on an element of your checklist is a FAIL; a lone `small-target` warning is an observation. Assert what matters for each message and primary button: `apvt assert --device <udid> '#pay' --visible --inside safe-area --no-overlap`. apvt's `#id` is the identifier the hierarchy shows.
7. **Read the console after side effects** (save, pay, submit, delete, network). Use `GetConsoleOutput` with `{"pattern": "declin|fail|denied|invalid", "oslogSeverity": ["error","fault"], "tailLimit": 20}` (expect `… was invalidated` noise from `invalid`): an app can show success while logging the failure. Always combine `oslogSeverity` with a keyword `pattern`: severity alone fills `tailLimit` with simulator noise. Count only the app's own lines; [references/pitfalls.md](references/pitfalls.md) lists the noise.

To reach screens and states: scroll for rows not yet in the hierarchy; prefer launch arguments and deep links (`xcrun simctl openurl <udid> <url>`) to long tap sequences; try extreme values to reach failure paths. When the normal path is broken, reach the screen another way, check it anyway, and say how you got there.

## 4. Fix, then verify again

When an item fails and the task includes fixing it, change the source and call `DeviceInteractionInstallAndRun` again with the same arguments; it rebuilds. If the build fails, read `GetBuildLog` with `severity: "error"`. Confirm that the new build runs: the `Application, pid:` line shows a new pid, and one result the fix changes. Rerun the failed item and every item that touches the same code; each launch starts fresh, so order them so one sets up the next. Stop after three rounds on the same failure and report.

## 5. End and report

Always call `DeviceInteractionEndSession`, also after errors: an open session blocks the device ("already in use by a different session"). An idle session expires ("Session not found"); start a new one with a new name.

Report a table of the checklist: item, PASS / FAIL / NOT CHECKED, and the evidence (the hierarchy line, the apvt line, the console line, or the crash reason). For each FAIL give steps to reproduce from launch, expected versus actual, and the screenshot path. Put behavior the spec does not decide under Observations. State what you could not verify first. Never mark an item PASS because the code looks right.

When something misbehaves (a hung install, no agent answering, lost taps or keystrokes, a wedged simulator), read [references/pitfalls.md](references/pitfalls.md). Command syntax and the hierarchy format are in [references/device-interaction.md](references/device-interaction.md).
