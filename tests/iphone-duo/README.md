# Testing the iphone-duo skill

How the `iphone-duo` skill (plugins/apple-platform-build) was checked, so a later session can repeat it after an Xcode
update or a change to the scripts. Both scripts act on a real simulator and on Device Hub's window, so the test is a
run-through on a booted Duo, not a unit test.

Last run (2026-11-13, Xcode 27.2, iOS 27.2 simulator, Device Hub 255.31.3, macOS 27): every step below behaved as
written. The prompts in section 3 have not been run as a with-skill / without-skill comparison yet.

## 1. Prerequisites

- An iPhone Duo simulator, booted: `xcrun simctl list devices available | grep Duo`, `xcrun simctl boot <UDID>`,
  `xcrun simctl bootstatus <UDID>`.
- Device Hub running with a window: `open -g -b com.apple.dt.Devices`.
- Accessibility permission for the app that runs the shell (the scripts say so with exit 2 when it is missing).
- Note the device's posture and orientation first and restore them at the end; the user may be looking at it.

## 2. Run-through

`S=plugins/apple-platform-build/skills/iphone-duo/scripts`, `D=<UDID>`, `O=<scratch folder>`.

| Step | Command | Expect |
|---|---|---|
| status | `swift $S/devicehub.swift --udid $D status` | the window title, `device: iPhone Duo <UDID>`, buttons including `Closed, Partially Open, Open, Rotate Right` |
| starting point | `bash $S/duo-screenshot.sh $D $O/start.png 1200` | `posture:` and `orientation:` of the device as found |
| close | `swift $S/devicehub.swift --udid $D closed`, wait 3 s, screenshot | `posture: closed`, `screen: LCD  1398x2034 px  (466x678 pt)` in portrait |
| rotate, folded | `... rotate-right`, wait 3 s, screenshot | orientation moves one step in Portrait -> Landscape Left -> Portrait Upside Down -> Landscape Right; the PNG's width and height swap |
| half open | `... partial`, wait 3 s, screenshot | `posture: open`, `screen: LCD-1` (the inner screen stays lit) |
| open | `... open`, wait 3 s, screenshot | `posture: open`, `screen: LCD-1  2853x2007 px  (951x669 pt)` in landscape, or the swapped size in portrait |
| full turn | four times `... rotate-right` | back at the orientation it started from |
| fold with an app in front | `xcrun simctl launch $D <bundle id>`, then `closed` / `open` with a screenshot after each | the app is still in front and laid out for the other screen |
| other device | `--udid <a shut-down Duo> open` | the sidebar switches, then `error: no button 'Open' ...`, exit 1 |
| back | `--udid $D status` | `selected iPhone Duo <UDID> in the sidebar` and the posture buttons again |
| not a Duo | `bash $S/duo-screenshot.sh <an iPhone 17's UDID> $O/x.png` | `error: no screen 'LCD-1' ...`, exit 1 |
| bad input | `swift $S/devicehub.swift bogus`; `--udid 00000000-0000-0000-0000-000000000000 open` | exit 1 with a message naming the commands / the missing device |

Read at least the closed and the open screenshot: the posture line is derived from which screen is lit, so a picture of
the home screen on the wrong screen would show the script's logic is off.

What to re-check after an Xcode update, because the scripts depend on it:

- The buttons' accessibility descriptions (`Closed`, `Partially Open`, `Open`, `Rotate Right`) and the sidebar rows'
  identifiers (`TableRow.Device.<UDID>`): `devicehub.swift status` lists what it finds.
- The screen names `LCD` / `LCD-1` (`xcrun simctl io <UDID> enumerate`).
- Whether LaunchServices still reports Device Hub's pid as `-1` (if it does not, nothing breaks: `pgrep` keeps working).
- `DeviceInteractionSynthesize` on the open Duo: SKILL.md records that its screenshot is the cover screen and its
  hitPoints are off. Start a session, capture once without a command, look at the screenshot's size, end the session.

## 3. Prompts for a with-skill / without-skill comparison

1. "Take a screenshot of my app's first screen on the iPhone Duo, once open and once folded, and put the device back
   the way it was." - Expect: reads the posture first, uses `devicehub.swift` instead of asking the user to click in
   Device Hub, captures with `duo-screenshot.sh` and checks the `posture:` line, restores posture and orientation.
2. "`xcrun simctl io <UDID> screenshot` fails with 'Invalid argument' on the Duo simulator, and with
   `--display=primary` the picture is black. Is my app drawing nothing?" - Expect: explains the two screens and that
   `primary` is the cover screen, off while the device is open; captures the lit screen; does not debug the app's drawing.
3. "Run `<a UI test>` on the open Duo in landscape, then folded in portrait." - Expect: boots and waits, sets posture
   and orientation with the script before each run because XCUITest cannot, uses `id=<UDID>` as the destination,
   reports per posture, restores the device.
