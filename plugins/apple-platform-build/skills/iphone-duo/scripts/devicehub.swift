// Drive Device Hub's device window through the Accessibility API: fold / unfold / rotate a simulator.
//
//   swift devicehub.swift [--udid <UDID>] status
//   swift devicehub.swift [--udid <UDID>] closed | partial | open | rotate-right | home
//   swift devicehub.swift [--udid <UDID>] press "<button description>"
//
// Device Hub has no CLI or menu item for the posture of a foldable simulator; the only control is the row of
// buttons under the device ("Closed", "Partially Open", "Open", "Rotate Right", …). They answer AXPress, so this
// presses them without bringing Device Hub to the front and without taking the pointer.
//
// --udid selects that device in the window's sidebar first (the buttons act on the device the window shows);
// without it the window is used as it is.
//
// Exit codes: 0 done, 1 the button / device was not found or the press failed, 2 Device Hub cannot be reached.
import ApplicationServices
import Foundation

func say(_ text: String) { print(text); fflush(stdout) }  // an unflushed pipe loses the output on exit()
func fail(_ code: Int32, _ text: String) -> Never { say("error: " + text); exit(code) }

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func string(_ element: AXUIElement, _ name: String) -> String { attr(element, name) as? String ?? "" }
func children(_ element: AXUIElement) -> [AXUIElement] { attr(element, "AXChildren") as? [AXUIElement] ?? [] }

/// NSRunningApplication and System Events report Device Hub's pid as -1 (seen with Xcode 27.2), which is also why
/// computer-use's background tools find no window. The process table has the real one.
func deviceHubPID() -> pid_t? {
    let pgrep = Process()
    let out = Pipe()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-x", "DeviceHub"]
    pgrep.standardOutput = out
    do { try pgrep.run() } catch { return nil }
    pgrep.waitUntilExit()
    let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return text.split(separator: "\n").first.flatMap { pid_t($0) }
}

struct DeviceRow { let udid: String; let name: String; let row: AXUIElement }

struct Window {
    let element: AXUIElement
    var buttons: [(name: String, element: AXUIElement)] = []
    var outline: AXUIElement?
    var rows: [DeviceRow] = []

    init(_ element: AXUIElement) {
        self.element = element
        walk(element, 0)
    }

    private mutating func walk(_ e: AXUIElement, _ depth: Int) {
        let role = string(e, "AXRole")
        if role == "AXOutline" {  // the sidebar: one row per device, labelled "TableRow.Device.<UDID>"
            outline = e
            for row in children(e) where string(row, "AXRole") == "AXRow" {
                let texts = children(row).flatMap(children)
                guard let id = texts.map({ string($0, "AXIdentifier") }).first(where: { $0.hasPrefix("TableRow.Device.") })
                else { continue }
                let name = texts.first { string($0, "AXRole") == "AXStaticText" }.map { string($0, "AXValue") } ?? ""
                rows.append(DeviceRow(udid: String(id.dropFirst("TableRow.Device.".count)), name: name, row: row))
            }
            return
        }
        // The device's own screen is mirrored into the window as an accessibility tree; its buttons are the
        // simulator's apps, not Device Hub's controls.
        if string(e, "AXSubrole") == "AXSContentGroup" || depth > 8 { return }
        if role == "AXButton" {
            let name = string(e, "AXDescription")
            if !name.isEmpty, !string(e, "AXHelp").isEmpty { buttons.append((name, e)) }
        }
        for child in children(e) { walk(child, depth + 1) }
    }

    var selected: DeviceRow? { rows.first { attr($0.row, "AXSelected") as? Bool == true } }
}

// ---- arguments -------------------------------------------------------------------------------------------------
var arguments = Array(CommandLine.arguments.dropFirst())
var udid: String?
if let flag = arguments.firstIndex(of: "--udid"), flag + 1 < arguments.count {
    udid = arguments[flag + 1].uppercased()
    arguments.removeSubrange(flag...(flag + 1))
}
let shortcuts = ["closed": "Closed", "partial": "Partially Open", "open": "Open", "rotate-right": "Rotate Right", "home": "Home"]
let command = arguments.first ?? "status"
let wanted: String?
switch command {
case "status": wanted = nil
case "press":
    guard arguments.count > 1 else { fail(1, "press needs the button's description, e.g. press \"Rotate Right\"") }
    wanted = arguments[1]
default:
    guard let name = shortcuts[command] else {
        fail(1, "unknown command '\(command)'; use status, \(shortcuts.keys.sorted().joined(separator: ", ")) or press \"<button>\"")
    }
    wanted = name
}

// ---- Device Hub ------------------------------------------------------------------------------------------------
guard AXIsProcessTrusted() else {
    fail(2, "no Accessibility permission for this process (System Settings > Privacy & Security > Accessibility: the app that runs this shell)")
}
guard let pid = deviceHubPID() else {
    fail(2, "Device Hub is not running; open it with: open -g -b com.apple.dt.Devices")
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 3)  // a busy Device Hub fails a call instead of holding each one for 6 s
func loadWindows() -> [Window] { (attr(app, "AXWindows") as? [AXUIElement] ?? []).map(Window.init) }
var windows = loadWindows()
guard !windows.isEmpty else {
    fail(2, "Device Hub has no window; open one with: open -g -b com.apple.dt.Devices")
}

func describe(_ window: Window) {
    say("window: \(string(window.element, "AXTitle"))")
    if let device = window.selected { say("  device: \(device.name) \(device.udid)") } else { say("  device: (no row selected)") }
    say("  buttons: " + window.buttons.map { $0.name + ((attr($0.element, "AXEnabled") as? Bool ?? true) ? "" : " (disabled)") }
        .joined(separator: ", "))
}

// Show the wanted device first: the buttons act on whichever device the window shows.
var target = windows[0]
if let udid {
    if let shown = windows.first(where: { $0.selected?.udid == udid }) {
        target = shown
    } else if let holder = windows.first(where: { w in w.rows.contains { $0.udid == udid } }),
              let row = holder.rows.first(where: { $0.udid == udid }) {
        let result = AXUIElementSetAttributeValue(row.row, "AXSelected" as CFString, kCFBooleanTrue)
        guard result == .success else { fail(1, "could not select \(udid) in the sidebar (AXError \(result.rawValue))") }
        // The detail side is rebuilt for the new device: wait (a few seconds at most) until the window reports the
        // new selection and, when a button is wanted, shows it.
        var settled: Window?
        let deadline = Date().addingTimeInterval(6)
        repeat {
            usleep(300_000)
            settled = loadWindows().first { $0.selected?.udid == udid } ?? settled
            if let settled, wanted == nil || settled.buttons.contains(where: { $0.name == wanted }) { break }
        } while Date() < deadline
        guard let settled else { fail(1, "the sidebar did not switch to \(udid)") }
        target = settled
        say("selected \(row.name) \(udid) in the sidebar")
    } else {
        fail(1, "no device \(udid) in Device Hub's sidebar")
    }
} else if let wanted, let withButton = windows.first(where: { w in w.buttons.contains { $0.name == wanted } }) {
    target = withButton
}

guard let wanted else {
    if udid == nil { windows.forEach(describe) } else { describe(target) }
    exit(0)
}

describe(target)
guard let button = target.buttons.first(where: { $0.name == wanted }) else {
    fail(1, "no button '\(wanted)' for this device (the posture buttons exist only while a foldable simulator is booted: xcrun simctl boot <UDID>)")
}
guard attr(button.element, "AXEnabled") as? Bool ?? true else { fail(1, "button '\(wanted)' is disabled") }
let pressed = AXUIElementPerformAction(button.element, "AXPress" as CFString)
guard pressed == .success else { fail(1, "AXPress on '\(wanted)' failed (AXError \(pressed.rawValue))") }
say("pressed '\(wanted)'")
