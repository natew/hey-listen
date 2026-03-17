import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import IOKit.ps
import UserNotifications

let VERSION = "0.1.0"
let LAUNCHAGENT_LABEL = "com.hey-listen.daemon"

// MARK: - main entry

@main
struct HeyListen {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty || args.first == "daemon" {
            await MainActor.run { startDaemon() }
            return
        }

        if args.first == "setup" {
            await MainActor.run { startSetup() }
            return
        }

        let command = args.first!
        let rest = Array(args.dropFirst())

        switch command {
        case "sound": await handleSound(rest)
        case "notify": handleNotify(rest)
        case "say": handleSay(rest)
        case "open": handleOpen(rest)
        case "info": handleInfo(rest)
        case "windows": handleWindows(rest)
        case "toast": await MainActor.run { runToast(rest) }
        case "highlight": await MainActor.run { runHighlight(rest) }
        case "fairy": await MainActor.run { runFairy(rest) }
        case "login": handleLogin(rest)
        case "help", "--help", "-h": printUsage()
        case "version", "--version", "-v": print("hey-listen \(VERSION)")
        default:
            printError("unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }
}

// MARK: - menu bar daemon

@MainActor
private func startDaemon() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    _appDelegate = delegate
    app.run()
}

private var _appDelegate: AppDelegate?

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var animTimer: Timer?
    var frameIndex = 0
    let frames = ["🧚", "✨", "🧚‍♀️", "💫"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🧚"
            button.toolTip = "hey-listen"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "🧚 hey-listen v\(VERSION)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        let running = NSMenuItem(title: "✨ listening...", action: nil, keyEquivalent: "")
        running.isEnabled = false
        menu.addItem(running)
        menu.addItem(.separator())
        menu.addItem(withTitle: "🔧 Setup...", action: #selector(openSetup), keyEquivalent: "s")
        menu.addItem(withTitle: "📋 Copy path", action: #selector(copyPath), keyEquivalent: "c")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        self.statusItem.menu = menu

        animTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.frameIndex = (self.frameIndex + 1) % self.frames.count
                self.statusItem.button?.title = self.frames[self.frameIndex]
            }
        }
    }

    @objc func openSetup() {
        let selfPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        Process.launchedProcess(launchPath: selfPath, arguments: ["setup"])
    }

    @objc func copyPath() {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc func quit() { NSApp.terminate(nil) }
}

// MARK: - setup / splash screen

@MainActor
private func startSetup() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = SetupDelegate()
    app.delegate = delegate
    _setupDelegate = delegate
    app.run()
}

private var _setupDelegate: SetupDelegate?

@MainActor
class SetupDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var pollTimer: Timer?
    var notifStatus: NSTextField!
    var notifBtn: NSButton!
    var accessStatus: NSTextField!
    var accessBtn: NSButton!
    var loginStatus: NSTextField!
    var loginBtn: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w: CGFloat = 480
        let h: CGFloat = 500

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "hey-listen"
        window.center()
        window.isMovableByWindowBackground = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // fairy icon
        let fairy = NSTextField(labelWithString: "🧚")
        fairy.font = NSFont.systemFont(ofSize: 80)
        fairy.frame = NSRect(x: (w - 100) / 2, y: h - 110, width: 100, height: 100)
        fairy.alignment = .center
        content.addSubview(fairy)

        let sparkleL = NSTextField(labelWithString: "✨")
        sparkleL.font = NSFont.systemFont(ofSize: 24)
        sparkleL.frame = NSRect(x: (w - 100) / 2 - 40, y: h - 70, width: 40, height: 30)
        sparkleL.alignment = .center
        content.addSubview(sparkleL)

        let sparkleR = NSTextField(labelWithString: "✨")
        sparkleR.font = NSFont.systemFont(ofSize: 24)
        sparkleR.frame = NSRect(x: (w + 100) / 2 + 4, y: h - 80, width: 40, height: 30)
        sparkleR.alignment = .center
        content.addSubview(sparkleR)

        let title = NSTextField(labelWithString: "hey, listen!")
        title.font = NSFont(name: "Papyrus", size: 28) ?? NSFont.systemFont(ofSize: 28, weight: .bold)
        title.frame = NSRect(x: 0, y: h - 155, width: w, height: 36)
        title.alignment = .center
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "system utilities for coding agents")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 0, y: h - 178, width: w, height: 20)
        subtitle.alignment = .center
        content.addSubview(subtitle)

        let divider = NSBox()
        divider.boxType = .separator
        divider.frame = NSRect(x: 40, y: h - 198, width: w - 80, height: 1)
        content.addSubview(divider)

        let permTitle = NSTextField(labelWithString: "Permissions")
        permTitle.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        permTitle.frame = NSRect(x: 40, y: h - 228, width: 200, height: 24)
        content.addSubview(permTitle)

        let permDesc = NSTextField(labelWithString: "grant each, then come back — it updates live ✨")
        permDesc.font = NSFont.systemFont(ofSize: 11)
        permDesc.textColor = .tertiaryLabelColor
        permDesc.frame = NSRect(x: 40, y: h - 248, width: 400, height: 16)
        content.addSubview(permDesc)

        var y = h - 292

        let (notifRow, ns, nb) = makePermRow(y: y, width: w, icon: "🔔", label: "Notifications",
            desc: "send alerts when tasks complete", action: #selector(grantNotifications))
        notifStatus = ns; notifBtn = nb
        content.addSubview(notifRow)
        y -= 68

        let (accessRow, as2, ab) = makePermRow(y: y, width: w, icon: "🤖", label: "Accessibility",
            desc: "read window titles and bounds", action: #selector(grantAccessibility))
        accessStatus = as2; accessBtn = ab
        content.addSubview(accessRow)
        y -= 68

        let (loginRow, ls, lb) = makePermRow(y: y, width: w, icon: "🚀", label: "Start on Login",
            desc: "keep hey-listen running in background", action: #selector(grantLogin))
        loginStatus = ls; loginBtn = lb
        content.addSubview(loginRow)

        let doneBtn = NSButton(title: "✨ Done", target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded
        doneBtn.frame = NSRect(x: (w - 140) / 2, y: 24, width: 140, height: 40)
        doneBtn.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        doneBtn.keyEquivalent = "\r"
        content.addSubview(doneBtn)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshPermissions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPermissions() }
        }
    }

    func makePermRow(y: CGFloat, width: CGFloat, icon: String, label: String, desc: String, action: Selector) -> (NSView, NSTextField, NSButton) {
        let row = NSView(frame: NSRect(x: 40, y: y, width: width - 80, height: 58))
        let iconLabel = NSTextField(labelWithString: icon)
        iconLabel.font = NSFont.systemFont(ofSize: 24)
        iconLabel.frame = NSRect(x: 0, y: 16, width: 36, height: 36)
        row.addSubview(iconLabel)

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.frame = NSRect(x: 44, y: 34, width: 200, height: 20)
        row.addSubview(nameLabel)

        let descLabel = NSTextField(labelWithString: desc)
        descLabel.font = NSFont.systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 44, y: 16, width: 250, height: 16)
        row.addSubview(descLabel)

        let status = NSTextField(labelWithString: "⏳ pending")
        status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        status.textColor = .systemOrange
        status.frame = NSRect(x: 44, y: 0, width: 120, height: 14)
        row.addSubview(status)

        let btn = NSButton(title: "Grant", target: self, action: action)
        btn.bezelStyle = .rounded
        btn.frame = NSRect(x: row.frame.width - 80, y: 18, width: 70, height: 28)
        row.addSubview(btn)

        return (row, status, btn)
    }

    func refreshPermissions() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.setPermStatus(self.notifStatus, self.notifBtn, granted: settings.authorizationStatus == .authorized)
            }
        }
        setPermStatus(accessStatus, accessBtn, granted: AXIsProcessTrusted())
        setPermStatus(loginStatus, loginBtn, granted: isLoginItemInstalled())
    }

    func setPermStatus(_ label: NSTextField, _ btn: NSButton, granted: Bool) {
        if granted {
            label.stringValue = "✅ granted"
            label.textColor = .systemGreen
            btn.title = "Done"
            btn.isEnabled = false
        } else {
            label.stringValue = "⏳ pending"
            label.textColor = .systemOrange
            btn.title = "Grant"
            btn.isEnabled = true
        }
    }

    @objc func grantNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
            }
        }
    }

    @objc func grantAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if !trusted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @objc func grantLogin() {
        installLoginItem()
        refreshPermissions()
    }

    @objc func done() {
        pollTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

// MARK: - login item (for hey-listen itself)

private func launchAgentPath() -> String {
    "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/LaunchAgents/\(LAUNCHAGENT_LABEL).plist"
}

private func resolvedExePath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let installed = "\(home)/.local/bin/hey-listen"
    if FileManager.default.fileExists(atPath: installed) { return installed }
    return Bundle.main.executablePath ?? CommandLine.arguments[0]
}

func isLoginItemInstalled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPath())
}

func installLoginItem() {
    let plist: [String: Any] = [
        "Label": LAUNCHAGENT_LABEL,
        "ProgramArguments": [resolvedExePath(), "daemon"],
        "RunAtLoad": true,
        "KeepAlive": false,
    ]
    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let dir = (launchAgentPath() as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: launchAgentPath(), contents: data)
    print("login item installed")
}

func removeLoginItem() {
    try? FileManager.default.removeItem(atPath: launchAgentPath())
    print("login item removed")
}

private func handleLogin(_ args: [String]) {
    switch args.first ?? "status" {
    case "enable", "on": installLoginItem()
    case "disable", "off": removeLoginItem()
    case "status": print("login: \(isLoginItemInstalled() ? "enabled" : "disabled")")
    default: printError("usage: hey-listen login <enable|disable|status>"); exit(1)
    }
}

// MARK: - windows (read-only window info)

private func handleWindows(_ args: [String]) {
    let flags = parseFlags(args)
    let json = flags.has("json") || flags.has("j")
    let filter = flags.named["app"] ?? flags.named["a"]

    // CGWindowListCopyWindowInfo works without accessibility for basic info
    guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        printError("failed to get window list")
        exit(1)
    }

    var results: [[String: Any]] = []
    for win in windowList {
        let owner = win[kCGWindowOwnerName as String] as? String ?? ""
        let name = win[kCGWindowName as String] as? String ?? ""
        let layer = win[kCGWindowLayer as String] as? Int ?? 0
        let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]

        // skip menubar, desktop, etc
        if layer != 0 { continue }

        // filter by app name if specified
        if let filter, !owner.localizedCaseInsensitiveContains(filter) { continue }

        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let w = bounds["Width"] as? Double ?? 0
        let h = bounds["Height"] as? Double ?? 0
        let pid = win[kCGWindowOwnerPID as String] as? Int ?? 0

        if json {
            results.append([
                "app": owner, "title": name, "pid": pid,
                "x": x, "y": y, "width": w, "height": h,
            ])
        } else {
            let titleStr = name.isEmpty ? "" : " | \"\(name)\""
            print("[\(owner)] pid:\(pid) | \(Int(x)),\(Int(y)) \(Int(w))x\(Int(h))\(titleStr)")
        }
    }

    if json {
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }
}

// MARK: - sound

private let SOUND_ALIASES: [String: String] = [
    "success": "Glass", "error": "Basso", "warning": "Sosumi", "done": "Hero",
    "start": "Blow", "ping": "Ping", "pop": "Pop", "purr": "Purr", "tink": "Tink",
    "morse": "Morse", "submarine": "Submarine", "funk": "Funk", "frog": "Frog", "bottle": "Bottle",
]

private func handleSound(_ args: [String]) async {
    let flags = parseFlags(args)
    let volume = Float(flags.named["volume"] ?? flags.named["v"] ?? "1.0") ?? 1.0

    guard let name = flags.positional.first else {
        if flags.has("list") || flags.has("l") { listSounds(); return }
        printError("usage: hey-listen sound <name|path> [--volume 0.0-1.0]")
        exit(1)
    }

    let url = URL(fileURLWithPath: resolveSoundPath(name))
    do {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = volume
        player.play()
        while player.isPlaying { try await Task.sleep(for: .milliseconds(50)) }
    } catch {
        printError("failed to play: \(error.localizedDescription)")
        exit(1)
    }
}

private func resolveSoundPath(_ name: String) -> String {
    if let alias = SOUND_ALIASES[name.lowercased()] { return "/System/Library/Sounds/\(alias).aiff" }
    if FileManager.default.fileExists(atPath: name) { return name }
    let sys = "/System/Library/Sounds/\(name).aiff"
    if FileManager.default.fileExists(atPath: sys) { return sys }
    printError("sound not found: \(name). use --list"); exit(1)
}

private func listSounds() {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds") else { return }
    let rev = Dictionary(uniqueKeysWithValues: SOUND_ALIASES.map { ($1, $0) })
    print("system sounds:")
    for f in files.sorted() {
        let n = (f as NSString).deletingPathExtension
        print(rev[n].map { "  \(n) (alias: \($0))" } ?? "  \(n)")
    }
}

// MARK: - notify

private func handleNotify(_ args: [String]) {
    let flags = parseFlags(args)
    guard let title = flags.positional.first else {
        printError("usage: hey-listen notify <title> [body] [--sound <name>] [--subtitle <text>]")
        exit(1)
    }
    let body = flags.positional.count > 1 ? flags.positional.dropFirst().joined(separator: " ") : nil
    let subtitle = flags.named["subtitle"]
    let sound = flags.named["sound"] ?? flags.named["s"] ?? "default"

    var script = "display notification \"\(escapeAS(body ?? ""))\""
    script += " with title \"\(escapeAS(title))\""
    if let subtitle { script += " subtitle \"\(escapeAS(subtitle))\"" }
    if sound != "none" { script += " sound name \"\(sound)\"" }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let err = Pipe(); p.standardError = err
    do {
        try p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 { print("notification sent") }
        else { printError("failed: \(String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")"); exit(1) }
    } catch { printError("failed: \(error.localizedDescription)"); exit(1) }
}

private func escapeAS(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - toast

@MainActor
private func runToast(_ args: [String]) {
    let flags = parseFlags(args)
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "3.0") ?? 3.0
    guard !flags.positional.isEmpty else { printError("usage: hey-listen toast <message> [--duration 3.0]"); exit(1) }
    let message = flags.positional.joined(separator: " ")

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let sf = screen.visibleFrame
    let ww: CGFloat = 400, wh: CGFloat = 60, pad: CGFloat = 20

    let window = NSWindow(
        contentRect: NSRect(x: sf.origin.x + (sf.width - ww) / 2, y: sf.origin.y + sf.height - wh - pad, width: ww, height: wh),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .clear; window.isOpaque = false; window.level = .floating
    window.hasShadow = true; window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let vfx = NSVisualEffectView(frame: window.contentView!.bounds)
    vfx.autoresizingMask = [.width, .height]; vfx.material = .hudWindow; vfx.state = .active
    vfx.wantsLayer = true; vfx.layer?.cornerRadius = 12; vfx.layer?.masksToBounds = true
    window.contentView?.addSubview(vfx)

    let label = NSTextField(labelWithString: "🧚 \(message)")
    label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
    label.textColor = .labelColor; label.alignment = .center
    label.frame = vfx.bounds; label.autoresizingMask = [.width, .height]
    vfx.addSubview(label)

    window.alphaValue = 0; window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.3; window.animator().alphaValue = 1 }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; window.animator().alphaValue = 0 },
            completionHandler: { NSApp.terminate(nil) })
    }
    app.run()
}

// MARK: - highlight (bounding box overlay)

@MainActor
private func runHighlight(_ args: [String]) {
    let flags = parseFlags(args)
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "3.0") ?? 3.0
    let colorName = flags.named["color"] ?? flags.named["c"] ?? "red"
    let thickness = CGFloat(Double(flags.named["thickness"] ?? flags.named["t"] ?? "3.0") ?? 3.0)
    let labelText = flags.named["label"]

    guard flags.positional.count == 4,
          let x = Double(flags.positional[0]), let y = Double(flags.positional[1]),
          let w = Double(flags.positional[2]), let h = Double(flags.positional[3])
    else {
        printError("usage: hey-listen highlight <x> <y> <w> <h> [--duration 3] [--color red] [--label text]")
        exit(1)
    }

    let colors: [String: NSColor] = [
        "red": .systemRed, "green": .systemGreen, "blue": .systemBlue,
        "yellow": .systemYellow, "orange": .systemOrange, "purple": .systemPurple, "cyan": .systemTeal,
    ]
    let color = colors[colorName.lowercased()] ?? .systemRed

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screenH = (NSScreen.main ?? NSScreen.screens[0]).frame.height
    let flippedY = screenH - y - h

    let window = NSWindow(
        contentRect: NSRect(x: x - thickness, y: flippedY - thickness, width: w + thickness * 2, height: h + thickness * 2),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .clear; window.isOpaque = false; window.level = .screenSaver
    window.hasShadow = false; window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let boxView = HighlightView(
        frame: NSRect(x: 0, y: 0, width: w + thickness * 2, height: h + thickness * 2),
        color: color, thickness: thickness, labelText: labelText)
    window.contentView = boxView
    window.alphaValue = 0; window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.2; window.animator().alphaValue = 1 }

    var pulseUp = false
    let pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.5; window.animator().alphaValue = pulseUp ? 1.0 : 0.6 }
            pulseUp.toggle()
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        pulseTimer.invalidate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; window.animator().alphaValue = 0 },
            completionHandler: { NSApp.terminate(nil) })
    }
    app.run()
}

class HighlightView: NSView {
    let color: NSColor; let thickness: CGFloat; let labelText: String?
    init(frame: NSRect, color: NSColor, thickness: CGFloat, labelText: String?) {
        self.color = color; self.thickness = thickness; self.labelText = labelText
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inset = thickness / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = thickness
        color.withAlphaComponent(0.9).setStroke()
        color.withAlphaComponent(0.05).setFill()
        path.fill(); path.stroke()

        let ml: CGFloat = min(12, rect.width / 4, rect.height / 4)
        color.setStroke()
        for c in makeCorners(rect, ml) { c.lineWidth = thickness + 1; c.stroke() }

        if let labelText, !labelText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white,
                .backgroundColor: color.withAlphaComponent(0.85),
            ]
            let str = NSAttributedString(string: " \(labelText) ", attributes: attrs)
            str.draw(at: NSPoint(x: rect.minX, y: rect.maxY + 2))
        }
    }

    func makeCorners(_ r: NSRect, _ l: CGFloat) -> [NSBezierPath] {
        let pts: [(NSPoint, NSPoint, NSPoint)] = [
            (NSPoint(x: r.minX, y: r.maxY - l), NSPoint(x: r.minX, y: r.maxY), NSPoint(x: r.minX + l, y: r.maxY)),
            (NSPoint(x: r.maxX - l, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY), NSPoint(x: r.maxX, y: r.maxY - l)),
            (NSPoint(x: r.minX, y: r.minY + l), NSPoint(x: r.minX, y: r.minY), NSPoint(x: r.minX + l, y: r.minY)),
            (NSPoint(x: r.maxX - l, y: r.minY), NSPoint(x: r.maxX, y: r.minY), NSPoint(x: r.maxX, y: r.minY + l)),
        ]
        return pts.map { p in let b = NSBezierPath(); b.move(to: p.0); b.line(to: p.1); b.line(to: p.2); return b }
    }
}

// MARK: - fairy (floating animated fairy)

@MainActor
private func runFairy(_ args: [String]) {
    let flags = parseFlags(args)
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "5.0") ?? 5.0
    let message = flags.positional.isEmpty ? nil : flags.positional.joined(separator: " ")

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let sf = screen.visibleFrame
    let fairySize: CGFloat = 60

    // create a small borderless window for the fairy
    let window = NSWindow(
        contentRect: NSRect(x: sf.midX, y: sf.midY, width: fairySize + 200, height: fairySize + 20),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .clear; window.isOpaque = false; window.level = .floating
    window.hasShadow = false; window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let contentView = NSView(frame: window.contentView!.bounds)
    window.contentView = contentView

    let fairyLabel = NSTextField(labelWithString: "🧚")
    fairyLabel.font = NSFont.systemFont(ofSize: 40)
    fairyLabel.frame = NSRect(x: 0, y: 0, width: fairySize, height: fairySize)
    fairyLabel.alignment = .center
    contentView.addSubview(fairyLabel)

    if let message {
        // speech bubble next to fairy
        let bubble = NSTextField(labelWithString: message)
        bubble.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        bubble.textColor = .labelColor
        bubble.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95)
        bubble.isBezeled = false; bubble.drawsBackground = true
        bubble.wantsLayer = true; bubble.layer?.cornerRadius = 8
        bubble.frame = NSRect(x: fairySize + 4, y: 15, width: 190, height: 30)
        bubble.alignment = .center
        contentView.addSubview(bubble)
    }

    window.alphaValue = 0; window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.3; window.animator().alphaValue = 1 }

    // generate random waypoints on screen
    let emojis = ["🧚", "🧚‍♀️", "✨", "🧚", "💫", "🧚‍♀️"]
    var emojiIdx = 0

    // float to random positions
    let moveTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { _ in
        DispatchQueue.main.async {
            let newX = sf.origin.x + CGFloat.random(in: 100...(sf.width - 300))
            let newY = sf.origin.y + CGFloat.random(in: 100...(sf.height - 100))

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 1.0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(
                    NSRect(x: newX, y: newY, width: window.frame.width, height: window.frame.height),
                    display: true)
            }

            emojiIdx = (emojiIdx + 1) % emojis.count
            fairyLabel.stringValue = emojis[emojiIdx]
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        moveTimer.invalidate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.5; window.animator().alphaValue = 0 },
            completionHandler: { NSApp.terminate(nil) })
    }
    app.run()
}

// MARK: - say

private func handleSay(_ args: [String]) {
    let flags = parseFlags(args)
    let voice = flags.named["voice"] ?? flags.named["v"]
    let rate = flags.named["rate"] ?? flags.named["r"]

    guard !flags.positional.isEmpty else {
        if flags.has("list") || flags.has("l") {
            for v in NSSpeechSynthesizer.availableVoices {
                let a = NSSpeechSynthesizer.attributes(forVoice: v)
                print("  \(a[.name] as? String ?? "?") (\(a[.localeIdentifier] as? String ?? ""))")
            }
            return
        }
        printError("usage: hey-listen say <text> [--voice <name>] [--rate <wpm>]"); exit(1)
    }

    let synth = NSSpeechSynthesizer()
    if let voice, let match = NSSpeechSynthesizer.availableVoices.first(where: {
        (NSSpeechSynthesizer.attributes(forVoice: $0)[.name] as? String ?? "").localizedCaseInsensitiveContains(voice)
    }) { synth.setVoice(match) }
    if let rate, let r = Float(rate) { synth.rate = r }

    synth.startSpeaking(flags.positional.joined(separator: " "))
    while synth.isSpeaking { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) }
}

// MARK: - open

private func handleOpen(_ args: [String]) {
    guard let target = args.first else { printError("usage: hey-listen open <url|path>"); exit(1) }
    if let url = URL(string: target), url.scheme != nil { NSWorkspace.shared.open(url) }
    else { NSWorkspace.shared.open(URL(fileURLWithPath: target)) }
    print("opened \(target)")
}

// MARK: - info

private func handleInfo(_ args: [String]) {
    switch args.first ?? "all" {
    case "battery": printBattery()
    case "dark", "darkmode", "dark-mode": printDarkMode()
    case "display", "screen": printDisplay()
    case "frontapp", "front-app": printFrontApp()
    case "all": printBattery(); printDarkMode(); printDisplay(); printFrontApp()
    default: printError("options: battery, dark-mode, display, front-app, all"); exit(1)
    }
}

private func printBattery() {
    let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    for s in IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef] {
        guard let d = IOPSGetPowerSourceDescription(snap, s)?.takeUnretainedValue() as? [String: Any] else { continue }
        print("battery: \(d[kIOPSCurrentCapacityKey] as? Int ?? -1)% | charging: \(d[kIOPSIsChargingKey] as? Bool ?? false) | source: \(d[kIOPSPowerSourceStateKey] as? String ?? "?")")
    }
}

private func printDarkMode() {
    let a = NSApplication.shared.effectiveAppearance.name
    print("dark-mode: \(a == .darkAqua || a == .vibrantDark || a == .accessibilityHighContrastDarkAqua || a == .accessibilityHighContrastVibrantDark)")
}

private func printDisplay() {
    for (i, s) in NSScreen.screens.enumerated() {
        print("display[\(i)]: \(Int(s.frame.width))x\(Int(s.frame.height)) @ \(s.backingScaleFactor)x")
    }
}

private func printFrontApp() {
    if let a = NSWorkspace.shared.frontmostApplication {
        print("front-app: \(a.localizedName ?? "?") (pid: \(a.processIdentifier))")
    }
}

// MARK: - helpers

private struct ParsedFlags: Sendable {
    var positional: [String] = []
    var named: [String: String] = [:]
    func has(_ key: String) -> Bool { named.keys.contains(key) }
}

private func parseFlags(_ args: [String]) -> ParsedFlags {
    var r = ParsedFlags(); var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let k = String(a.dropFirst(2))
            if let eq = k.firstIndex(of: "=") {
                r.named[String(k[k.startIndex..<eq])] = String(k[k.index(after: eq)...])
            } else if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                r.named[k] = args[i + 1]; i += 1
            } else { r.named[k] = "true" }
        } else if a.hasPrefix("-") && a.count == 2 {
            let k = String(a.dropFirst(1))
            if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                r.named[k] = args[i + 1]; i += 1
            } else { r.named[k] = "true" }
        } else { r.positional.append(a) }
        i += 1
    }
    return r
}

private func printError(_ msg: String) {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
}

private func printUsage() {
    print("""
    🧚 hey-listen v\(VERSION) — system utilities for coding agents

    usage: hey-listen <command> [options]

    daemon mode:
      hey-listen                   start menu bar daemon (fairy tray icon)
      hey-listen setup             permissions setup screen

    commands:
      sound <name|path>            play a sound
        --volume <0.0-1.0>         volume (default: 1.0)
        --list                     list available sounds

      notify <title> [body]        send a macOS notification
        --sound <name>             notification sound
        --subtitle <text>          subtitle

      toast <message>              floating overlay banner
        --duration <seconds>       display time (default: 3.0)

      fairy [message]              floating fairy that flies around the screen
        --duration <seconds>       how long (default: 5.0)

      highlight <x> <y> <w> <h>   pulsing bounding box overlay
        --color <name>             red, green, blue, yellow, orange, purple, cyan
        --thickness <px>           border thickness (default: 3)
        --label <text>             label above the box
        --duration <seconds>       display time (default: 3.0)

      windows                      list visible windows with bounds
        --app <name>               filter by app name
        --json                     output as json

      say <text>                   text-to-speech
        --voice <name>             voice (partial match)
        --rate <wpm>               speech rate
        --list                     list voices

      open <url|path>              open in browser/Finder
      login enable|disable|status  start hey-listen on login

      info [topic]                 system info
        battery, dark-mode, display, front-app, all

    sound aliases:
      success, error, warning, done, start, ping, pop, purr,
      tink, morse, submarine, funk, frog, bottle

    examples:
      hey-listen sound done
      hey-listen fairy "hey! look at this!"
      hey-listen notify "Build done" "all tests passed"
      hey-listen highlight 100 200 400 300 --color green --label "button"
      hey-listen windows --app Terminal --json
      hey-listen toast "deploying..."
    """)
}
