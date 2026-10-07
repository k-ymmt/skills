# TODO

Open issues and missing features found while building and testing the `simulator-verify` skill
(apple-platform-build plugin), which combines the Xcode MCP server (`xcrun mcpbridge`) with apvt.
Environment of the findings: Xcode 27.1 beta (27A9269), iOS 27.0 simulators, apvt 0.1.0 plus the unreleased
changes now merged into its main (`type`, `launch-env`), Claude Code 2.1.288.

## Xcode MCP (`xcrun mcpbridge`)

- [ ] `DeviceInteractionSynthesize` has no usable text-entry command. Xcode's own embedded
  `device-interaction` skill documents a type command (`kbd <text>`), but the parser rejects
  `kbd` with "Invalid command". Workaround in the skill: tap the field, then `apvt type`.
  Fallback without apvt: chain key taps from the hierarchy (`t x1 y1 t x2 y2 ...`).
- [ ] Xcode's `device-interaction` skill (command syntax, hierarchy format) exists only inside
  `IDEDeviceInteraction.framework`; agents outside Xcode get "load the device-interaction skill"
  with no way to load it. The skill documents the syntax recovered by probing:
  `t x y [hold]`, `t x1 y1 f x2 y2 [dur]` (swipe), `d x y`, `drag x1 y1 x2 y2 [hold] [move]`,
  `mt [x y, ...] dur ...`, `b h|p|u|d`, `w <sec>`, `orientation <value>`; commands chain with spaces.
- [ ] A `sessionIdentifier` cannot be reused after `DeviceInteractionEndSession` ("currently in use
  or was recently used"); every run needs a fresh name.
- [ ] One interaction session per device: starting another fails with "The target device is
  already in use by a different session with key …" until the old one is ended, and a session
  left idle for a while expires ("Session not found"), so long investigations must restart it.
- [ ] `DeviceInteractionInstallAndRun` once hung for more than 10 minutes: the build succeeded but
  the install never finished, and `xcrun simctl listapps`/`install` on that simulator hung too.
  Rebooting the simulator fixed it. The skill tells agents to check with a time-limited
  `simctl install` and reboot the simulator, but the MCP call itself has no timeout.
- [ ] `DeviceInteractionInstallAndRun` and `BuildProject` need `workspaceIdentifier` even with one
  workspace open in some states ("workspaceIdentifier is required").

- [ ] `XcodeOpenWorkspace` with a wrong argument key answers "can't be put in front of the user
  for approval. Retry it with a plain absolute path.", which reads like a path problem; the key is
  `path`.
- [ ] `GetConsoleOutput` with `oslogSeverity: ["error","fault"]` returns hundreds of simulator
  noise lines (`[AXUIA] This child can't be serialized correctly`, XPC, CA events) and stdout
  timestamps are not ordered with OSLog ones; there is no filter by subsystem, and `pattern`
  matches only the message text, not the `[category]` prefix the result shows.

## Simulator

- [ ] A freshly booted or erased simulator shows the keyboard's "slide to type" introduction over
  the keyboard the first time a field is focused; it must be dismissed (Continue) before typing.
- [ ] `xcrun simctl pbcopy <udid>` did not reach the app's pasteboard (`simctl pbpaste` stayed
  empty), so paste is not a text-entry fallback.
- [ ] The first tap right after `DeviceInteractionInstallAndRun` returns can be lost while the app
  builds its first screen; capture (empty command) and check the hierarchy before the first tap.

## apvt

- [ ] Release `apvt type`, `apvt launch-env [--xcode]` and the overlap/identifier fixes (merged
  into main of ~/Projects/swift/apvt, not pushed) and update the Homebrew tap; the skills need
  apvt newer than 0.1.0.
- [x] `apvt status` reported "loaded by launchd" for an agent loaded through launch environment
  variables; the loader now keeps `APVT_LOADED_BY=env`.

- [x] SwiftUI views moved with `.offset` lost their accessibility identifier in apvt (frames no
  longer overlapped), so `apvt assert '#error'` matched nothing; fixed with a same-size,
  same-text fallback.
- [x] `apvt type --submit` that crashed the app reported "the agent did not type" and suggested a
  rebuild; it now says the app stopped answering.
- [x] `overlap` was always a warning. Decided with the user: text that crosses a control's edge is
  now an error; text wholly inside a control stays a warning (a badge may be intended), so an
  error message drawn entirely inside its button (the login test) is still only a warning. The
  skill tells agents to treat overlaps of checklist elements as failures.

## simulator-verify skill

- [ ] Testers repeatedly wrote their own "act, capture, filter" shell helper around
  `DeviceInteractionSynthesize`. Over MCP the agent calls the tool directly, so a shipped helper
  would only help shell-driven setups; reconsider if real MCP sessions show the same friction.
- [ ] A helper for input variants (relaunch → focus → `apvt type` → submit → judge, repeated per
  value) would make boundary testing cheaper.
- [ ] `apvt type --submit` prints no field value when Return ended editing; printing the value
  before Return would make logs clearer.

## Testing this repository's skills

- [ ] A nested `claude -p --plugin-dir ./plugins/apple-platform-build` run (the faithful end-to-end
  test with the plugin's MCP server) was refused by Claude Code's auto-mode classifier. Tests ran
  with subagents calling the Xcode MCP tools through a shell wrapper around `xcrun mcpbridge`
  instead; the tool names and arguments are the same, the transport is not.
