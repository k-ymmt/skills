# apvt command reference

Condensed from `apvt --help`, `apvt <command> --help`, and the README of https://github.com/k-ymmt/apvt (apvt 0.1.0). When a detail matters, `apvt <command> --help` is authoritative for the installed version.

## Commands

| command | does |
|---|---|
| `apvt setup [--device D] [--rebuild]` | Builds the agent for the simulator (cached under `~/Library/Caches/apvt/`) and sets `DYLD_INSERT_LIBRARIES` in the simulator's launchd, so every app launched afterwards by `simctl` or the home screen loads it. Apps already running must be relaunched. Lasts until the simulator shuts down. |
| `apvt teardown [--device D]` | Undoes `setup`; apps launched from then on run without the agent. |
| `apvt status [--device D]` | Booted simulators, whether each is set up, apps running with the agent, and apps running without it (with the exact relaunch command). |
| `apvt inspect` | Layout issues on the current screen, one per line, with `@N` node numbers and the fix per rule. Exit 1 on an error. |
| `apvt tree` | The view tree with frames: `@N Type #identifier "text" (x,y wxh) [SwiftUI modifiers] {traits} !issues`. Same-frame chains print as `A > B`. |
| `apvt query <selector>` | Every node the selector matches: frame, ancestors, children, text metrics, issues. Exit 1 when nothing matches. |
| `apvt assert <selector> [checks]` | Checks every matching node; exit 1 when any check fails. With no checks, asserts existence. |
| `apvt screenshot <file.png>` | PNG with issues outlined and labelled `@N` (red: error, orange: warning, dashed: the other nodes an issue involves). |
| `apvt rules` | What `inspect` checks and how to fix each. |
| `apvt debug swiftui-raw <file.json>` / `apvt debug methods <Class>` | Diagnostics for apvt itself; not needed for layout work. |

## Options shared by inspect, tree, query, assert, screenshot

| option | meaning |
|---|---|
| `--device <name\|udid>` | Simulator. Default: the only booted one. |
| `--app <bundle-id\|process>` | App. Default: the only running app whose agent answers (only the foreground app does). |
| `--wait <seconds>` | Wait for the app's agent to appear, for example right after `simctl launch`. Use `--wait 10` after a launch. |
| `--snapshot <file.json>` | Read a snapshot saved with `--save` instead of asking the app. Not for `screenshot`. |
| `--json` | Print JSON instead of text. |

`inspect` and `tree` take `--save <file.json>`. `inspect` also takes `--annotate <file.png>` (screenshot with the issues outlined), `--rule <name>` (repeatable or comma-separated, to run only some rules), `--limit <n>` (0 = all, default 40), `--fail-on error|warning|never` (default `error`), and `--min-target <pt>` (default 24, the `small-target` threshold).

`tree` takes `--all` (include private views and system chrome), `--depth <n>`, and `--root <selector>` (only the subtree of the first match). `query` and `assert` take `--include-system`. `screenshot` takes `--outline issues|all` (`all` also boxes every visible element in blue with its `@N`) and `--plain` (no drawing).

## Selectors (query, assert, tree --root, assert references)

| selector | matches |
|---|---|
| `@12` | the node numbered 12 in this snapshot (numbers change between snapshots) |
| `#follow` | accessibility identifier equals `follow` |
| `text:Follow` | text, label or placeholder contains `Follow`, case-insensitive |
| `text="Recent posts"` | text is exactly `Recent posts` |
| `type:Button` | type or class name, case-insensitive (`Text`, `UILabel`, `HStack`, `.frame`, …) |
| `role:control` | role: `window`, `container`, `text`, `image`, `control`, `shape`, `spacer`, `scroll`, `hosting` |
| `follow` | bare word: an identifier, or else an exact text |

Join terms with commas; all must match: `type:Text,text:Inbox`. Quote the whole selector in the shell. Only `@N` reaches system and private views unless `--include-system` is given.

## Assertion checks

Every check runs on every node the selector matches. A `<ref>` is a selector that matches exactly one node, or `screen` / `safe-area`. A `<size>` is a number or an operator and number: `150`, `">=44"`, `"<=100"`. Equality checks allow `--tolerance <pt>` of slack (default 0.5).

| flag | passes when |
|---|---|
| `--count <n>` | exactly n nodes match |
| `--visible` | on screen, not hidden, not clipped, not zero-sized |
| `--inside <ref>` | the frame lies within the reference |
| `--not-truncated` | no `truncated`, `squeezed` or `clipped` issue on the node |
| `--no-overlap` | no `overlap` issue involving the node |
| `--no-issues` | no issue of any rule on the node |
| `--width <size>` / `--height <size>` | the frame's size satisfies the comparison |
| `--min-width <n>` / `--min-height <n>` | shorthand for `">=n"` |
| `--align-leading`, `--align-trailing`, `--align-top`, `--align-bottom`, `--align-center-x`, `--align-center-y <ref>` | that edge or center equals the reference's |
| `--same-width <ref>` / `--same-height <ref>` | the size equals the reference's |
| `--left-of`, `--right-of`, `--above`, `--below <ref>` | entirely on that side of the reference |
| `--spacing <size>` | with a direction flag: the gap between the two |

Output is one `PASS` / `FAIL` line per check with the measured values, then a summary line.

## Rules and fixes

| rule | finds | fix (summary of `apvt rules`) |
|---|---|---|
| `offscreen` | content cut off by, or beyond, the screen edge (not inside a scroll view) | Find the container that grew wider than the screen or the fixed size/offset that moved it. SwiftUI: remove `.fixedSize()` / fixed `.frame(width:)` on long content, let Text wrap, or use `ViewThatFits` / a ScrollView. UIKit: pin leading and trailing instead of a fixed width. |
| `wider-than-screen` | a container wider than the screen, naming the fixed-size children that pushed it | SwiftUI: drop `.fixedSize()`, replace `.frame(width: N)` with `.frame(maxWidth: .infinity)`, add `.lineLimit` / `.minimumScaleFactor`, or wrap in `ScrollView(.horizontal)`. UIKit: replace width constants with leading/trailing constraints or lower their priority. |
| `clipped` | content hidden by an ancestor that clips (`clipsToBounds`, `.clipped()`) | Grow the clipping container or drop its fixed height, or remove the clipping. UIKit: constrain the container's height to its content. |
| `truncated` | text that needs more room than its frame, measured with its font | SwiftUI: remove fixed `.frame(width:/height:)` or `.lineLimit(1)`, or let it wrap with `.fixedSize(horizontal: false, vertical: true)`. UIKit: `numberOfLines = 0` and pin leading/trailing. If one line is intended, shorten the text or add `minimumScaleFactor`. |
| `squeezed` | text narrower than its longest word, or a control collapsed to zero | A sibling took the space. SwiftUI: `.layoutPriority(1)` or `.fixedSize()` on the squeezed view, and let the long sibling truncate or wrap. UIKit: raise `contentCompressionResistancePriority`. |
| `overlap` | texts or controls drawn on top of each other | SwiftUI: an `.offset()` or `ZStack` moved one onto another; use `.overlay(alignment:)`, padding or alignment instead. UIKit: constrain one below/beside the other instead of to the same anchors. |
| `unsafe-area` | text or a control under the status bar, Dynamic Island or home indicator | SwiftUI: apply `.ignoresSafeArea()` only to the background, not the content. UIKit: constrain to `view.safeAreaLayoutGuide`. |
| `small-target` | a control smaller than 24x24pt (WCAG 2.5.8) | Make the tappable area at least 44x44pt (HIG): SwiftUI `.frame(minWidth: 44, minHeight: 44)` plus `.contentShape(Rectangle())`; UIKit larger bounds or `point(inside:with:)`. |
| `ambiguous-layout` | a UIKit view whose Auto Layout frame is ambiguous | Add the missing constraints so x, y, width and height are each determined. |
| `broken-constraint` | `Unable to simultaneously satisfy constraints`, with the conflicting set | Remove one of the listed constraints or lower one's priority below 1000. |

Not checked: contrast and color. Conflicts inside UIKit's own views (alerts, the keyboard) are left out.

## Exit codes

| code | meaning |
|---|---|
| 0 | ok |
| 1 | a check failed: `assert` failed, `inspect` found an error (or a warning with `--fail-on warning`), `query` matched nothing |
| 2 | usage error (bad selector, size, rule name) |
| 3 | environment or app: no booted simulator, not set up, no app with the agent |

Errors print `error:` / `why:` / `fix:` lines with the command that fixes the situation; run that command rather than retrying.

## Why Xcode's Run does not work

`apvt setup` sets `DYLD_INSERT_LIBRARIES` in the simulator's launchd. Xcode's Run passes its own `DYLD_INSERT_LIBRARIES` (the Main Thread Checker), which replaces launchd's value, and Xcode re-imports any debugger breakpoint without its commands, so loading the agent through the debugger was dropped. Build or Run from Xcode, stop, then relaunch with `xcrun simctl launch <udid> <bundle-id>`; the installed build then starts with the agent. SwiftUI frames are only available when the agent is in before the first view graph is built, which is why relaunching, not attaching, is required.

## Sample app

`Examples/APVTSample` in the apvt repository has screens with planted defects (`profile`, `pricing`, `badge`, `header`, `form`, `uikit`) and clean ones (`settings`, `feed`); open one with `xcrun simctl launch booted dev.apvt.sample -screen pricing`. It is a quick way to confirm the setup works before inspecting the user's app.
