# Layout facts and XCUITest traps on the iPhone Duo

Measured on the Duo simulator with iOS 27.1-27.2 while making one app (a SwiftUI app with a `NavigationSplitView`, an
`.inspector` and a full-screen reader) work on it. Numbers are measurements, not documentation: re-measure after an OS
update before relying on one.

## Contents

- Running UI tests on the Duo
- XCUITest traps on the open Duo
- The bar column, the camera, the safe areas
- A split view at the Duo's widths
- State restoration and what a fold changes

## Running UI tests on the Duo

- Destination by UDID: `-destination 'platform=iOS Simulator,id=<UDID>'`. `name=iPhone Duo` finds nothing when two
  simulators share the name.
- Put the device into the posture and orientation the test expects **before** the run, with `scripts/devicehub.swift`
  (SKILL.md section 2). A test cannot do it: `XCUIDevice.shared.orientation` does not turn the Duo's UI, and nothing in
  XCUITest folds it. Name the required state in the test (its name or a comment), and make a test that needs the open
  Duo fail loudly when it finds the folded one instead of passing on the wrong layout.
- Boot the simulator first and wait for `xcrun simctl bootstatus <UDID>`. A simulator that `xcodebuild` has just booted
  is slow, and anything with a load timeout (a web view drawing its first page) fails for that reason alone.
- Tests written for a phone assume a navigation bar with a back button; folded, the Duo keeps the status bar and those
  buttons in its vertical bar column, so such a test fails at that step. `UIDevice.current.userInterfaceIdiom` in a test
  picks the phone layout, which is wrong for the open Duo's regular width. Neither is an app bug.
- Launching by hand: `SIMCTL_CHILD_<NAME>=<value> xcrun simctl launch <UDID> <bundle id>` passes an environment
  variable; `simctl launch --stdout=<file>` wrote no file, `--console-pty` in the background shows `print` output. Logs:
  `xcrun simctl spawn <UDID> log stream --level debug --predicate 'subsystem == "<subsystem>"'` (nothing arrives unless
  the simulator is already booted).

## XCUITest traps on the open Duo

- **Offsets from `app` miss.** `app.coordinate(withNormalizedOffset: .zero).withOffset(...)` uses `app.frame`, which on
  the open Duo in landscape is not the window's frame (its height read 951 pt), so a tap aimed at the middle of the page
  landed in a side column. Anchor on the window or on an element:
  `app.windows.firstMatch.coordinate(withNormalizedOffset:)`.
- **Reading where a tap went.** `xcrun xcresulttool export attachments` gives "Synthesized Event ..." attachments
  (binary plists): `plutil -p` shows `originalOffset` (what the test asked for) and `coordinate.x / .y` (the device
  coordinate that was sent). In landscape the mapping was x_dev = y_screen, y_dev = 951 - x_screen. Read this before
  adding a wait for "the tap was ignored".
- **Home does not background the app.** `XCUIDevice.shared.press(.home)` leaves `app.state` at foreground on the open
  Duo, even twice. `XCUIApplication(bundleIdentifier: "com.apple.springboard").activate()` backgrounds it.
- **The first tap can go to the sidebar.** At regular width a split view's sidebar may come up over the detail and take
  the first tap; tests written for the phone layout do not expect it.
- **Evidence.** The test's own screenshots are black and the recording has one frame on the open Duo; take screenshots
  with `scripts/duo-screenshot.sh` from outside. The status bar's presence can be asserted through
  `XCUIApplication(bundleIdentifier: "com.apple.springboard").statusBars`.

## The bar column, the camera, the safe areas

Folded, the Duo puts the status bar and the tab bar into a vertical column, 84 pt wide, on the trailing edge in portrait
and the leading edge in landscape, with the camera at its top.

| State | Window size | `window.safeAreaInsets` |
|---|---|---|
| folded, portrait | 466x678 pt | top 0, bottom 34, right 84 |
| folded, landscape | 678x466 pt | left 84, bottom 34 |
| open, landscape | 951x669 pt | the bar column's side 84 (867 pt remain) |
| open, portrait | 669x951 pt | not measured yet |

- "The window has a side inset on one side only" recognises the column (a landscape iPhone has one on both sides).
- `UIView.reservedRegions(kind: .occlusion)` (iOS 27.1+) returns two regions when folded: the camera
  (399.67, 29.33, 37x37; x 29.33 in landscape) and the column's bar area, whose height changes when the status bar is
  shown or hidden (174 / 82) and is therefore a poor anchor for layout.
- Hiding the status bar removes the column's inset on the open Duo (84 -> 0, and the occlusion regions with it), which
  lays the split view out again; the folded Duo and an iPhone 17 do not change. To keep the layout still, put the lost
  inset back with the root view controller's `additionalSafeAreaInsets`.
- `.statusBarHidden` (and other preferences) set inside `.inspector` never reach the window's root at regular width;
  set them outside the inspector. Check the root's `prefersStatusBarHidden` before concluding the OS ignores it.
- While bars animate back on the open Duo in landscape, the measured width wobbles for about 0.1 s (867 -> 783 ->
  867 pt). A rule that reacts to a width change misfires there; react to the columns being shown or hidden instead.
- Before saying "there is no API for this part of the device", grep the SDK's headers and `.swiftinterface` files: the
  occlusion API was missed once by looking only at `safeAreaInsets`.

## A split view at the Duo's widths

- Folded: compact in both orientations (678 pt is still compact), so the phone layout.
- Open: regular. `NavigationSplitView` + `.inspector` becomes one `UISplitViewController`. 669 pt (portrait) does not
  fit a sidebar, a detail and an inspector together; 867 pt (landscape, without the bar column) does.
- The detail's `.navigationSplitViewColumnWidth(min:ideal:)`: `min` becomes `minimumSecondaryColumnWidth`, and `ideal`
  goes into the split's preferred size (sidebar width + ideal). Where the window is narrower than that, a launch
  without saved state starts with the sidebar hidden.
- UIKit decides whether the sidebar overlays the detail or sits beside it **at the moment the sidebar is shown**, from
  the room there is then; a settled overlay is not re-tiled later (closing the inspector three seconds afterwards left
  it overlaid). Change the columns in the same update instead of waiting on a timer, and check three starts before
  reporting "side by side": a launch without saved state, a launch with saved state, and a rotation.

## State restoration and what a fold changes

- UIKit saves the split view's column arrangement when the app goes to the background (not when a column changes) into
  `<app container>/Library/Saved Application State/<bundle id>.savedState/` and restores it on the next launch, writing
  `true` into an `.inspector(isPresented:)` binding whatever its `@State` default says. To reproduce an "the inspector is
  open after launch" report: open it, go Home, terminate, launch. Delete that folder for a launch without saved state.
- A fold with the inspector open is the regular -> compact case in which UIKit turns the open inspector column into a
  sheet (the binding gets `false`, the size class turns compact, the binding gets `true`). This was first worked out by
  dragging an iPad window's corner; `devicehub.swift closed` with the inspector open should be the same event on the Duo
  itself and has not been run yet.
