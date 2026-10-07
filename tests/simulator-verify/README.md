# Testing the simulator-verify skill

How the `simulator-verify` skill (plugins/apple-platform-build) was tested, so a later session can
repeat the test after changing the skill, apvt, or Xcode. The method: write small iOS apps with
planted bugs, let subagents verify them by following the skill without reading the source,
compare their findings with the list of planted bugs, and fold their friction reports back into
the skill and `TODO.md`.

Last run (2026-10-08, Xcode 27.1 beta 27A9269, iOS 27.0 simulators): all 17 planted bugs were
found, plus one unplanted bug; one fix-and-reverify run fixed every bug of TodoFix.

## 1. Prerequisites

- Xcode running with **Settings > Intelligence > Model Context Protocol > Xcode Tools** on.
- `xcodegen` on PATH.
- apvt with `type` and `launch-env --xcode`. Until a release has them, build it from
  `~/Projects/swift/apvt` (main): `swift build`, then use `~/Projects/swift/apvt/.build/debug/apvt`.
  Put that binary first on PATH for the subagents, for example by symlinking it as
  `<scratchpad>/bin/apvt`.
- Work in the session's scratchpad directory: apps, reports, answer keys. Nothing of it belongs in
  this repository.

## 2. Reach the Xcode MCP tools from the shell

The faithful test is a fresh Claude Code session with the plugin loaded
(`claude --plugin-dir ./plugins/apple-platform-build`), where the subagents call the `xcode` MCP
tools directly. A nested `claude -p` was refused by the auto-mode classifier, and subagents only
get the parent session's MCP servers, so the last run used [xmcp](xmcp) instead. It keeps one
`xcrun mcpbridge` process alive and forwards calls with the same tool names and arguments:

```bash
tests/simulator-verify/xmcp serve                 # once; prints "xmcp: ready"
tests/simulator-verify/xmcp call XcodeListWorkspaces
tests/simulator-verify/xmcp call DeviceInteractionSynthesize '{"interactSessionKey":"k","interactionCommand":"t 100 200"}'
tests/simulator-verify/xmcp stop                  # at the end
```

Calls may run concurrently (several subagents at once). The socket is `/tmp/xmcp.sock`; set
`XMCP_SOCK` to run a second daemon. Exit code 1 means the tool reported an error.

If the session can call the `xcode` MCP tools natively, prefer that and tell the subagents to use
the tools instead of xmcp.

## 3. Dedicated simulators

One device interaction session per simulator, so give each parallel subagent its own simulator,
and keep the user's simulators out of it:

```bash
xcrun simctl create "Verify A" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl boot <udid>
xcrun simctl bootstatus <udid>
apvt setup --device <udid>
```

Create "Verify B" the same way for a second agent.

## 4. Sample apps

Each app is an xcodegen project in `<scratchpad>/apps/<Name>/` with `project.yml`, `Sources/`
and `SPEC.md`. The subagents get only `SPEC.md`. Keep the planted-bug lists in
`<scratchpad>/answers/<Name>.md`, outside the app directory, and keep bug comments out of the
source, since a tester that reads the source would find them.

`project.yml` template (replace `<Name>` and the bundle id):

```yaml
name: <Name>
options:
  bundleIdPrefix: dev.verify
  deploymentTarget:
    iOS: "18.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    GENERATE_INFOPLIST_FILE: YES
    INFOPLIST_KEY_UILaunchScreen_Generation: YES
    CODE_SIGNING_ALLOWED: NO
targets:
  <Name>:
    type: application
    platform: iOS
    sources: [Sources]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.verify.<name>
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
```

Then `xcodegen generate` and a build check:

```bash
xcodebuild -project <Name>.xcodeproj -scheme <Name> -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratchpad>/dd/<Name> build -quiet
```

Give important views `.accessibilityIdentifier`s, as real apps often do. The four apps used last
time follow. Write each spec as `SPEC.md` and each planted-bug list as the answer key. New apps
that cover other cases (a web view, a map, a permission prompt, deep links, a long form) are
welcome.

### TodoApp (SwiftUI list, `dev.verify.todo`)

Spec:
- One screen titled "Todos". A "New task" text field and an "Add" button. Add appends the typed
  task and clears the field. Empty or whitespace-only input must not create a task.
- The list shows every task, newest first. Long titles must stay readable (wrap, not cut off).
- Tapping a row toggles that task's done state (filled check mark, strikethrough). Swipe left and
  Delete removes that task.
- The footer shows "<n> left" and "Clear completed", which removes every done task.
- Initial tasks: "Buy milk", "Write the quarterly report for the product strategy meeting next
  week", "Call Alex".

Planted bugs (how to plant them):
1. Toggle hits the mirrored row: `ForEach(Array(store.items.reversed().enumerated()), id: \.element.id)`
   and `onTapGesture { store.toggle(at: index) }` on the stored (oldest-first) array. The middle
   row maps to itself, which hides the bug.
2. Swipe-delete removes the mirrored row: `.onDelete { store.delete(at: $0) }` on the same reversed list.
3. Whitespace-only input is accepted: `guard !title.isEmpty`.
4. Clear completed crashes when a done task is not the newest one: `for i in items.indices where items[i].done { items.remove(at: i) }`.
5. The long title is cut: `.lineLimit(1)` plus `.frame(width: 220, alignment: .leading)` (apvt `truncated`).
6. Minor: Add and Clear completed are about 20pt high (apvt `small-target`).

### LoginApp (SwiftUI form, `dev.verify.login`)

Spec:
- Email field, Password field (secure), "Remember me" toggle, "Sign in" button.
- A valid email (one "@", a dot in the domain) and a password of at least 8 characters show
  "Welcome" with the email; "Sign out" returns.
- An invalid email shows "Enter a valid email address." in red below the button; a short password
  shows "Password must be at least 8 characters.". The error must be readable and must not cover
  the button.
- Return in the password field signs in like the button. Plus addressing
  (`ann+news@example.com`) must work. Any valid pair signs in (no backend).

Planted bugs:
1. A 7-character password is accepted: `s.count >= 7`.
2. The error covers the button: the error `Text` sits in a `ZStack(alignment: .topLeading)` with
   the button and `.offset(y: 6)` (apvt `overlap` warning, `apvt assert '#error' --no-overlap` fails).
3. Every valid email without "+" crashes: `email.components(separatedBy: "+")[1]` in the submit
   action. Plus-addressed emails work.

### CountriesUIKit (UIKit table and detail, `dev.verify.countries`)

Spec:
- "Countries" list: Japan, France, Brazil, Kenya, Canada, United Kingdom of Great Britain and
  Northern Ireland.
- Tapping a country opens "Details" for that country: full name (readable, may wrap),
  "Capital: …", "Population: …", and a star button toggling ☆/★. Back returns to the list.

Planted bugs:
1. Rows 1–4 open the country after next: `let index = indexPath.row == 0 ? 0 : indexPath.row + 1`.
2. The last row crashes (index out of range), from the same line.
3. The long name is cut: a one-line `UILabel` with `widthAnchor == 300` (apvt `truncated`, an
   error). Reachable only through the Canada row because of bug 1.
4. Conflicting constraints on the star button: `width == 20` and `width == 32` (apvt
   `broken-constraint`; it does not appear in `GetConsoleOutput`).

### ShopApp (SwiftUI tabs, scroll, sheet, console, `dev.verify.shop`)

Spec:
- Tabs Shop and Cart; the Cart badge shows the number of units.
- Shop: after a "Loading…" spinner (1.5 s `Task.sleep`), "Item 1" … "Item 20" priced ¥100 × n,
  each with "Add to cart".
- Cart: one row per product with a stepper (1–9) and "× qty ¥line-total"; "Total ¥…" updates
  immediately.
- "Checkout" opens a sheet with "<n> items, total ¥…" and "Pay". Paying charges the card, empties
  the cart and shows "Order placed". A declined payment must not claim the order was placed.
- Launch argument `-seedCart` starts with Item 1 and Item 2 in the cart.

Planted bugs:
1. The stepper changes the quantity but not the line total or Total: store `lineTotal` in the cart
   line and recompute it only in `add()`.
2. "Add to cart" on Item 20 adds Item 19: `let target = product.id == 20 ? shop.products[18] : product`.
   Needs scrolling to reach.
3. Pay is pushed under the home indicator: `.offset(y: 30)` on the button and
   `.ignoresSafeArea(edges: .bottom)` on the sheet (apvt `offscreen`/`clipped` errors).
4. A declined payment still says "Order placed": with more than 3 units, `pay()` logs
   `log.error("payment declined: …")` with category `shop`, then empties the cart and returns
   success. Only `GetConsoleOutput` reveals it.

The last run's ShopApp tester also found an unplanted bug: "Add to cart" can push a quantity past
the stepper's maximum of 9.

### Fix-and-reverify variant

Copy one app (TodoApp was used) to `<scratchpad>/apps/TodoFix` with a new name and bundle id, and
let an agent verify it, fix the source, and verify again until the checklist passes.

## 5. Subagent prompts

Run two at a time, each on its own simulator, in the background. Black-box template:

```
You are a QA agent testing an iOS app in the iOS Simulator. Follow the skill at
<repo>/plugins/apple-platform-build/skills/simulator-verify/SKILL.md (read it fully first; read its
references when it points you there; its scripts/ are usable). Treat it as your operating manual.

Task for the skill: verify <App> against its specification and report every deviation.

Environment specifics (they only tell you how to reach the tools):
- The Xcode MCP tools are reachable from the shell: `<repo>/tests/simulator-verify/xmcp call <ToolName> '<json arguments>'`,
  exactly an MCP tool call to the `xcode` server (same names and arguments), printing the tool's
  text result; exit code 1 = tool error. Never run `xmcp serve` or `xmcp stop`.
- apvt: `<scratchpad>/bin/apvt` (development build with `type` and `launch-env`).
- Use ONLY simulator "<Verify A>", UDID <udid> (booted, apvt setup done). Do not touch other
  simulators. Another agent works on another simulator; do not end sessions you did not start.
- Project: <scratchpad>/apps/<App>/<App>.xcodeproj (scheme <App>). Spec: <scratchpad>/apps/<App>/SPEC.md.
- Black-box: do NOT read <scratchpad>/apps/<App>/Sources, <scratchpad>/answers or <scratchpad>/reports.
  Do not edit files outside <scratchpad>/reports/. Do not fix the app.
- Budget: roughly 60-80 tool calls.

Write your report to <scratchpad>/reports/<App>.md and return it as your final answer: checklist
table (PASS/FAIL/NOT CHECKED with evidence), FAIL reproduction steps, observations, a candid
"Friction log" (skill, references, scripts, tools; exact errors; concrete suggestions), and rough
counts of tool calls, Synthesize and apvt calls.
```

For the fix-and-reverify variant, allow reading and editing `<scratchpad>/apps/TodoFix/Sources`,
ask for the checklist before and after, each fix, and a friction log about the rebuild loop.

## 6. Scoring and follow-up

- Compare each report's FAILs with the answer key: found, missed, or misattributed. A FAIL that is
  not in the key is either an unplanted real bug (check the source) or a false positive (a skill
  problem).
- Read every friction log. Fix the skill, its references and scripts (keep SKILL.md under about
  10 KB; one tester could not read a 14.5 KB SKILL.md in one go), fix apvt when the tool is at fault,
  and add what cannot be fixed here to `TODO.md`.
- After substantial skill changes, run at least one more agent on the final version to confirm.
- Run `scripts/validate.sh`, then commit.

## 7. Cleanup

```bash
tests/simulator-verify/xmcp call XcodeListWorkspaces          # then XcodeCloseWorkspace each test workspace
tests/simulator-verify/xmcp stop
xcrun simctl shutdown <udid>; xcrun simctl delete <udid>      # only the Verify simulators you created
apvt teardown --device <udid>                                 # on any of the user's simulators you set up
```

Remove the test apps' DerivedData only after checking that its `info.plist` `WorkspacePath`
points into the scratchpad.

## 8. Comparison with a no-skill baseline

To measure what the skill adds, run each app twice in parallel: once with the black-box prompt
above (skill + apvt), once with a baseline prompt that drops the skill and apvt. The baseline gets
the same xmcp line, budget and report format, plus: "use the Xcode MCP tools, Xcode's own
command-line tools (xcrun simctl, xcodebuild, log) and standard shell utilities; do NOT use apvt
or any other third-party UI inspection tool, and do NOT read anything under this repository except
the xmcp script". Copy each app into `apps/A/<App>` and `apps/B/<App>` so the two runs open
different Xcode workspaces, and use four simulators (Verify A1, A2, B1, B2); run `apvt setup` on
the A ones only. Booting four new simulators at once made `apvt setup` time out once; rerun it.

Last run (2026-10-08, same environment as above, 8 agents):

| App | Skill + apvt | Baseline (Xcode MCP only) |
|---|---|---|
| TodoApp (6) | 6 (bug 6 as a small-target observation) | 5 (missed bug 6) |
| LoginApp (3) | 3 | 2 (missed the 7-character password) |
| CountriesUIKit (4) | 4 | 3 (missed the broken constraint) |
| ShopApp (4) | 4 | 3 (saw Item 20 add Item 19 but dismissed it as its own mistake); also found the unplanted quantity-past-9 bug |
| Total (17) | 17 | 13 |
| Wall time | 14, 20, 5, 8 min | 33, 32, 6, 9 min |
| Agent tool calls | 36, 39, 28, 33 | 59, 66, 37, 54 |

What the baseline lacked: the Synthesize command syntax (the TodoApp and LoginApp agents sent
about 2,100 and 850 brute-force probes; one probe storm broke the session with "Target device has
invalid screen scale"), text entry (they tapped keyboard keys, so TodoApp could test only
U+3000 instead of ASCII spaces), layout checks (no tool finds a constraint conflict that never
reaches the console), and the first/middle/last-row and boundary-value habits.

## Known traps while testing

- The first `DeviceInteractionInstallAndRun` once hung for more than 10 minutes because the
  simulator's install daemon was stuck; rebooting the simulator fixed it. Run long tool calls with a
  time limit (`perl -e 'alarm shift; exec @ARGV' 240 <command>`; macOS has no `timeout`).
- Device interaction session names are single-use; one session per device; idle sessions expire.
- Subagents tend to write the same helper (call Synthesize, then filter with `hierarchy.py`); that
  is expected with xmcp and does not apply to native MCP calls.
