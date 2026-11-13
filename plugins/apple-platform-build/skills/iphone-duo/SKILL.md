---
name: iphone-duo
description: Operate and verify the foldable iPhone Duo simulator - fold, unfold, half-open and rotate it from the shell (Device Hub's posture buttons pressed through the Accessibility API, since simctl, XCUITest and Xcode's device tools cannot), and screenshot a device that has two screens. Use whenever a task involves the iPhone Duo, a foldable, folded or unfolded state, Device Hub, checking a layout at both of the Duo's sizes or across a fold (compact to regular while the app runs), a Duo screenshot that is black or fails with "Cannot choose between 2 displays" / "Invalid argument", or a UI test that only fails on the Duo. Also use it before telling the user that the open Duo must be checked by hand - it need not be. Not for other simulators or physical devices.
argument-hint: "[what to do, e.g. 'open it and screenshot the settings screen' or 'run the split-view test folded and unfolded']"
metadata:
  short-description: Fold, rotate and screenshot the iPhone Duo simulator
---

# iPhone Duo simulator: fold it, rotate it, see the right screen

The Duo is one simulator with two built-in screens and three postures. Nothing in `simctl`, XCUITest or Xcode's
device-interaction tools knows about the posture, and several ordinary commands quietly look at the wrong screen. The two
scripts in this skill close that gap; the rest is what was measured on the way (Xcode 27.2, iOS 27.2, Device Hub
255.31.3 - re-check a number before building on it after an Xcode update).

| Posture | Lit screen (`simctl` name / id) | Size | Width class |
|---|---|---|---|
| Closed | cover: `LCD` / 1 | 1398x2034 px @3x = 466x678 pt | compact, in landscape (678 pt) too |
| Partially Open | inner: `LCD-1` / 3 | 2007x2853 px @3x = 669x951 pt | regular |
| Open | inner: `LCD-1` / 3 | same | regular |

## Task

$ARGUMENTS

If the line above still reads `$ARGUMENTS` literally, the task is the text the user wrote alongside the skill mention;
with nothing given, report the booted Duo's posture and orientation with a screenshot.

## 1. Pick the device

`xcrun simctl list devices available | grep Duo`, then work with the UDID everywhere. Two simulators may share the name
"iPhone Duo": `xcodebuild -destination 'name=iPhone Duo'` then fails with "Unable to find a device matching" (use
`id=<UDID>`), and Device Hub's window shows only one of them. The posture buttons exist only while the simulator is
booted: `xcrun simctl boot <UDID>` and `xcrun simctl bootstatus <UDID>` first.

## 2. Fold, unfold, rotate

`<this skill>` below is the directory this SKILL.md is in.

```bash
swift <this skill>/scripts/devicehub.swift --udid <UDID> status
swift <this skill>/scripts/devicehub.swift --udid <UDID> closed        # or: partial | open
swift <this skill>/scripts/devicehub.swift --udid <UDID> rotate-right
```

The script presses the buttons under the device in Device Hub's window ("Closed", "Partially Open", "Open",
"Rotate Right", "Home"; `press "<description>"` reaches any other) with `AXPress`. Device Hub stays in the background
and the user's pointer and keyboard are not touched, so it is safe to run while they work. `--udid` first selects that
device in the window's sidebar, because the buttons act on whichever device the window shows; switching devices takes
about ten seconds. Exit 2 means Device Hub is not running or has no window (`open -g -b com.apple.dt.Devices`), or the
process that runs your shell has no Accessibility permission; the message says which.

Why this route and not the obvious ones - each was tried, do not spend a round on them again:

- `simctl` has no posture command, Device Hub has no menu item for it, and Xcode's device-interaction tools stop at
  `orientation`.
- Screen-control tools that find an app by its bundle identifier (Claude's computer use in the background, System
  Events) see no window and no menu bar in Device Hub: LaunchServices reports its pid as `-1`. The script takes the pid
  from `pgrep -x DeviceHub` instead. Taking over the whole screen for one click would work and is not worth it.

What the buttons do:

- A press returns at once; the device needs two to three seconds to settle. Confirm with the screenshot script (its
  `posture:` line) instead of assuming.
- Closing moves the UI to the cover screen and to portrait; opening again restored the earlier orientation (Landscape
  Left in the run that measured it). Check the orientation after a fold rather than carrying it over.
- `rotate-right` cycles Portrait -> Landscape Left -> Portrait Upside Down -> Landscape Right -> Portrait, in either
  posture; three presses are one turn to the left. It is the way to rotate the Duo from a script:
  `XCUIDevice.shared.orientation` changes its value but not the Duo's UI.
- Folding while the app is in front is a live compact <-> regular change (the app keeps running and is laid out again
  on the other screen), the same event as resizing an iPad window. Use it to check that a screen survives the transition
  (split view columns, sheets, inspectors), not only each end state.

Leave the device as you found it (read `status` and take a screenshot first, restore both posture and orientation at
the end) and say in the report which posture each check ran in. The booted Duo is usually the one the user is looking at.

## 3. Screenshots

```bash
bash <this skill>/scripts/duo-screenshot.sh <UDID> <out.png> [max-pixel-size]
```

It captures both screens, keeps the lit one and prints the posture (`closed` / `open` / `dark`), the screen, its pixel
and point size, and the UI orientation. Pass a max size (1200-1600) when the picture is only for reading. "Partially
Open" reads as `open`: the inner screen stays lit and nothing in `simctl` tells the two apart.

The traps the script is built around:

- `xcrun simctl io <UDID> screenshot <file>` fails on a Duo with "Cannot choose between 2 displays ... Invalid
  argument". It needs `--display=LCD` (cover) or `--display=LCD-1` (inner); `recordVideo` takes the same flag.
- The aliases are worse than the error: `--display=primary` picks the cover screen even while it is off, so an open Duo
  gives a black picture with exit 0; `--display=internal` is rejected as ambiguous; `--display=external` waits for a
  screen that never comes and has to be killed.
- The screen that is off still returns a PNG, black and small (50-110 KB). A black screenshot of a Duo means "wrong
  screen" long before it means "the app drew nothing".
- The PNG follows the UI orientation (2853x2007 in landscape, 2007x2853 in portrait), so the size alone tells the
  orientation; `xcrun simctl io <UDID> enumerate` prints `UI Orientation:` per screen.
- **Xcode's `DeviceInteractionSynthesize` looks at the cover screen while the Duo is open** (one capture of the home
  screen in each posture): its screenshot is the cover screen (678x466, black). The hierarchy is the inner screen's
  (window 951x669), but its `hitPoint`s are computed against the cover screen's size (the window's read 339, 233, the
  middle of 678x466) and elements outside that rectangle have none, and some frames are in portrait coordinates inside
  the landscape window. So on the open Duo take screenshots with the script, and after any tap sent through that tool
  check on a fresh screenshot that it landed. Closed, its screenshot is the right screen (466x678); the hierarchy read
  three seconds after a fold still had transitional frames (window 223x317), so capture again before using one. This
  matters for the `simulator-verify` skill, which drives the app through that tool.
- XCUITest's own screenshots (`XCUIScreen.main.screenshot()`, the automatic ones in the `.xcresult`) came out black on
  the open Duo, and the automatic recording had one frame. Take the evidence from outside the test with the script.
- Claude Code's iOS Simulator tool follows the lit screen by itself, open or closed; its coordinates are points of that
  screen (951x669 for the open Duo in landscape).

## 4. UI tests and layout on the Duo

[references/layout-and-xcuitest.md](references/layout-and-xcuitest.md) has the measured layout facts (the 84 pt
vertical bar column, the camera's occlusion region, the safe areas per posture, how a split view with an inspector
behaves at 669 / 951 pt, what UIKit restores at launch) and the XCUITest traps of the open Duo (offsets from `app`
miss, Home does not background the app). Read it before writing or debugging a UI test for the Duo, or before changing
a layout that has to work in both postures.

A layout change that claims to cover the Duo is checked in four states - closed portrait, closed landscape, open
portrait, open landscape - plus one fold and one unfold with the screen in question in front. Say which of them ran.
