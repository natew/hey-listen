import AppKit
import AVFoundation
import Foundation
import IOKit.ps
import UserNotifications

let VERSION = "0.1.0"
let APP_ID = "com.hey-listen.app"
let LAUNCHAGENT_LABEL = "com.hey-listen.daemon"

// MARK: - main entry

@main
struct HeyListen {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())

        // no args or "daemon" → start menu bar app
        if args.isEmpty || args.first == "daemon" {
            await MainActor.run { startDaemon() }
            return
        }

        // "setup" → show setup/splash window
        if args.first == "setup" {
            await MainActor.run { startSetup() }
            return
        }

        // cli mode
        let command = args.first!
        let rest = Array(args.dropFirst())

        switch command {
        case "sound": await handleSound(rest)
        case "notify": handleNotify(rest)
        case "say": handleSay(rest)
        case "clipboard": handleClipboard(rest)
        case "open": handleOpen(rest)
        case "info": handleInfo(rest)
        case "toast": await MainActor.run { runToast(rest) }
        case "highlight": await MainActor.run { runHighlight(rest) }
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

    // fairy animation
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

        let loginItem = NSMenuItem(title: "Start on login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = isLoginItemInstalled() ? .on : .off
        loginItem.tag = 100
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")

        self.statusItem.menu = menu

        // fairy sparkle animation
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

    @objc func toggleLogin() {
        if isLoginItemInstalled() {
            removeLoginItem()
            statusItem.menu?.item(withTag: 100)?.state = .off
        } else {
            installLoginItem()
            statusItem.menu?.item(withTag: 100)?.state = .on
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
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
    var diskStatus: NSTextField!
    var diskBtn: NSButton!
    var loginStatus: NSTextField!
    var loginBtn: NSButton!
    var doneBtn: NSButton!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let w: CGFloat = 480
        let h: CGFloat = 600

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "hey-listen"
        window.center()
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor

        let content = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))

        // big fairy icon top center
        let fairy = NSTextField(labelWithString: "🧚")
        fairy.font = NSFont.systemFont(ofSize: 80)
        fairy.frame = NSRect(x: (w - 100) / 2, y: h - 110, width: 100, height: 100)
        fairy.alignment = .center
        content.addSubview(fairy)

        // sparkle decorations
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

        // title — use Papyrus for that fairy/fantasy vibe (built into macOS)
        let title = NSTextField(labelWithString: "hey, listen!")
        let fairyFont = NSFont(name: "Papyrus", size: 28) ?? NSFont.systemFont(ofSize: 28, weight: .bold)
        title.font = fairyFont
        title.frame = NSRect(x: 0, y: h - 155, width: w, height: 36)
        title.alignment = .center
        content.addSubview(title)

        let subtitle = NSTextField(labelWithString: "system utilities for coding agents")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 0, y: h - 178, width: w, height: 20)
        subtitle.alignment = .center
        content.addSubview(subtitle)

        // divider
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

        // notifications
        let (notifRow, ns, nb) = makePermRow(
            y: y, width: w,
            icon: "🔔", label: "Notifications",
            desc: "send alerts when tasks complete",
            action: #selector(grantNotifications)
        )
        notifStatus = ns; notifBtn = nb
        content.addSubview(notifRow)
        y -= 68

        // accessibility
        let (accessRow, as2, ab) = makePermRow(
            y: y, width: w,
            icon: "🤖", label: "Accessibility",
            desc: "ui automation and control",
            action: #selector(grantAccessibility)
        )
        accessStatus = as2; accessBtn = ab
        content.addSubview(accessRow)
        y -= 68

        // full disk
        let (diskRow, ds, db) = makePermRow(
            y: y, width: w,
            icon: "💾", label: "Full Disk Access",
            desc: "read files across the system",
            action: #selector(grantFullDisk)
        )
        diskStatus = ds; diskBtn = db
        content.addSubview(diskRow)
        y -= 68

        // login
        let (loginRow, ls, lb) = makePermRow(
            y: y, width: w,
            icon: "🚀", label: "Start on Login",
            desc: "keep hey-listen running in background",
            action: #selector(grantLogin)
        )
        loginStatus = ls; loginBtn = lb
        content.addSubview(loginRow)

        // done button
        doneBtn = NSButton(title: "✨ Done", target: self, action: #selector(done))
        doneBtn.bezelStyle = .rounded
        doneBtn.frame = NSRect(x: (w - 140) / 2, y: 24, width: 140, height: 40)
        doneBtn.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        doneBtn.keyEquivalent = "\r"
        content.addSubview(doneBtn)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        refreshPermissions()

        // poll every 1.5s to detect when user approves in system settings
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
        // notifications
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                let granted = settings.authorizationStatus == .authorized
                self.setPermStatus(self.notifStatus, self.notifBtn, granted: granted)
            }
        }

        // accessibility
        let axGranted = AXIsProcessTrusted()
        setPermStatus(accessStatus, accessBtn, granted: axGranted)

        // full disk — heuristic: try reading a protected path
        let fdGranted = FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
        setPermStatus(diskStatus, diskBtn, granted: fdGranted)

        // login item
        let loginGranted = isLoginItemInstalled()
        setPermStatus(loginStatus, loginBtn, granted: loginGranted)
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
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                }
            }
        }
    }

    @objc func grantAccessibility() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )
        if !trusted {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    @objc func grantFullDisk() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        )
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

// MARK: - login item (launchagent)

private func launchAgentPath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return "\(home)/Library/LaunchAgents/\(LAUNCHAGENT_LABEL).plist"
}

private func executablePath() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let installed = "\(home)/.local/bin/hey-listen"
    if FileManager.default.fileExists(atPath: installed) {
        return installed
    }
    return Bundle.main.executablePath ?? CommandLine.arguments[0]
}

func isLoginItemInstalled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentPath())
}

func installLoginItem() {
    let plist: [String: Any] = [
        "Label": LAUNCHAGENT_LABEL,
        "ProgramArguments": [executablePath(), "daemon"],
        "RunAtLoad": true,
        "KeepAlive": false,
    ]

    let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    let dir = (launchAgentPath() as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: launchAgentPath(), contents: data)
    print("login item installed at \(launchAgentPath())")
}

func removeLoginItem() {
    try? FileManager.default.removeItem(atPath: launchAgentPath())
    print("login item removed")
}

private func handleLogin(_ args: [String]) {
    let sub = args.first ?? "status"
    switch sub {
    case "enable", "on", "install":
        installLoginItem()
    case "disable", "off", "remove":
        removeLoginItem()
    case "status":
        print("login item: \(isLoginItemInstalled() ? "enabled" : "disabled")")
    default:
        printError("usage: hey-listen login <enable|disable|status>")
        exit(1)
    }
}

// MARK: - sound

private let SOUND_ALIASES: [String: String] = [
    "success": "Glass",
    "error": "Basso",
    "warning": "Sosumi",
    "done": "Hero",
    "start": "Blow",
    "ping": "Ping",
    "pop": "Pop",
    "purr": "Purr",
    "tink": "Tink",
    "morse": "Morse",
    "submarine": "Submarine",
    "funk": "Funk",
    "frog": "Frog",
    "bottle": "Bottle",
]

private func handleSound(_ args: [String]) async {
    let flags = parseFlags(args)
    let positional = flags.positional
    let volume = Float(flags.named["volume"] ?? flags.named["v"] ?? "1.0") ?? 1.0

    guard let name = positional.first else {
        if flags.has("list") || flags.has("l") {
            listSounds()
            return
        }
        printError("usage: hey-listen sound <name|path> [--volume 0.0-1.0]")
        exit(1)
    }

    let path = resolveSoundPath(name)
    let url = URL(fileURLWithPath: path)
    do {
        let player = try AVAudioPlayer(contentsOf: url)
        player.volume = volume
        player.play()
        while player.isPlaying {
            try await Task.sleep(for: .milliseconds(50))
        }
    } catch {
        printError("failed to play sound: \(error.localizedDescription)")
        exit(1)
    }
}

private func resolveSoundPath(_ name: String) -> String {
    if let alias = SOUND_ALIASES[name.lowercased()] {
        return "/System/Library/Sounds/\(alias).aiff"
    }
    if FileManager.default.fileExists(atPath: name) {
        return name
    }
    let systemPath = "/System/Library/Sounds/\(name).aiff"
    if FileManager.default.fileExists(atPath: systemPath) {
        return systemPath
    }
    printError("sound not found: \(name). use --list to see available sounds")
    exit(1)
}

private func listSounds() {
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds") else { return }
    let reverse = Dictionary(uniqueKeysWithValues: SOUND_ALIASES.map { ($1, $0) })
    print("system sounds:")
    for file in files.sorted() {
        let name = (file as NSString).deletingPathExtension
        if let alias = reverse[name] {
            print("  \(name) (alias: \(alias))")
        } else {
            print("  \(name)")
        }
    }
}

// MARK: - notify (via osascript for bundle-free operation)

private func handleNotify(_ args: [String]) {
    let flags = parseFlags(args)
    let positional = flags.positional

    guard let title = positional.first else {
        printError("usage: hey-listen notify <title> [body] [--sound <name>] [--subtitle <text>]")
        exit(1)
    }

    let body = positional.count > 1 ? positional.dropFirst().joined(separator: " ") : nil
    let subtitle = flags.named["subtitle"]
    let sound = flags.named["sound"] ?? flags.named["s"] ?? "default"

    var script = "display notification"
    script += " \"\(escapeAS(body ?? ""))\""
    script += " with title \"\(escapeAS(title))\""
    if let subtitle { script += " subtitle \"\(escapeAS(subtitle))\"" }
    if sound != "none" { script += " sound name \"\(sound)\"" }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let err = Pipe()
    p.standardError = err
    do {
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus == 0 {
            print("notification sent")
        } else {
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            printError("notification failed: \(msg)")
            exit(1)
        }
    } catch {
        printError("notification failed: \(error.localizedDescription)")
        exit(1)
    }
}

private func escapeAS(_ s: String) -> String {
    s.replacingOccurrences(of: "\\", with: "\\\\")
     .replacingOccurrences(of: "\"", with: "\\\"")
}

// MARK: - toast

@MainActor
private func runToast(_ args: [String]) {
    let flags = parseFlags(args)
    let positional = flags.positional
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "3.0") ?? 3.0

    guard !positional.isEmpty else {
        printError("usage: hey-listen toast <message> [--duration 3.0]")
        exit(1)
    }

    let message = positional.joined(separator: " ")

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let sf = screen.visibleFrame
    let ww: CGFloat = 400, wh: CGFloat = 60, pad: CGFloat = 20

    let window = NSWindow(
        contentRect: NSRect(
            x: sf.origin.x + (sf.width - ww) / 2,
            y: sf.origin.y + sf.height - wh - pad,
            width: ww, height: wh
        ),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.backgroundColor = .clear
    window.isOpaque = false
    window.level = .floating
    window.hasShadow = true
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let vfx = NSVisualEffectView(frame: window.contentView!.bounds)
    vfx.autoresizingMask = [.width, .height]
    vfx.material = .hudWindow
    vfx.state = .active
    vfx.wantsLayer = true
    vfx.layer?.cornerRadius = 12
    vfx.layer?.masksToBounds = true
    window.contentView?.addSubview(vfx)

    let label = NSTextField(labelWithString: "🧚 \(message)")
    label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
    label.textColor = .labelColor
    label.alignment = .center
    label.frame = vfx.bounds
    label.autoresizingMask = [.width, .height]
    vfx.addSubview(label)

    window.alphaValue = 0
    window.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.3
        window.animator().alphaValue = 1
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.5
            window.animator().alphaValue = 0
        }, completionHandler: { exit(0) })
    }

    app.run()
}

// MARK: - highlight (bounding box overlay)

@MainActor
private func runHighlight(_ args: [String]) {
    let flags = parseFlags(args)
    let positional = flags.positional
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "3.0") ?? 3.0
    let colorName = flags.named["color"] ?? flags.named["c"] ?? "red"
    let thickness = CGFloat(Double(flags.named["thickness"] ?? flags.named["t"] ?? "3.0") ?? 3.0)
    let label = flags.named["label"]

    // parse x,y,w,h from positional args
    guard positional.count == 4,
          let x = Double(positional[0]),
          let y = Double(positional[1]),
          let w = Double(positional[2]),
          let h = Double(positional[3])
    else {
        printError("usage: hey-listen highlight <x> <y> <width> <height> [--duration 3] [--color red] [--thickness 3] [--label text]")
        printError("  coordinates are screen pixels from top-left")
        printError("  colors: red, green, blue, yellow, orange, purple, cyan")
        exit(1)
    }

    let colors: [String: NSColor] = [
        "red": .systemRed, "green": .systemGreen, "blue": .systemBlue,
        "yellow": .systemYellow, "orange": .systemOrange, "purple": .systemPurple,
        "cyan": .systemTeal,
    ]
    let color = colors[colorName.lowercased()] ?? .systemRed

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let screenH = screen.frame.height

    // convert from top-left coordinates to macOS bottom-left
    let flippedY = screenH - y - h

    let window = NSWindow(
        contentRect: NSRect(x: x - thickness, y: flippedY - thickness,
                           width: w + thickness * 2, height: h + thickness * 2),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.backgroundColor = .clear
    window.isOpaque = false
    window.level = .screenSaver
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let boxView = HighlightView(
        frame: NSRect(x: 0, y: 0, width: w + thickness * 2, height: h + thickness * 2),
        color: color,
        thickness: thickness,
        labelText: label
    )
    window.contentView = boxView

    window.alphaValue = 0
    window.orderFrontRegardless()

    // fade in with a pulse effect
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        window.animator().alphaValue = 1
    }

    // pulse animation
    var pulseUp = false
    let pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                window.animator().alphaValue = pulseUp ? 1.0 : 0.6
            }
            pulseUp.toggle()
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        pulseTimer.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { exit(0) })
    }

    app.run()
}

class HighlightView: NSView {
    let color: NSColor
    let thickness: CGFloat
    let labelText: String?

    init(frame: NSRect, color: NSColor, thickness: CGFloat, labelText: String?) {
        self.color = color
        self.thickness = thickness
        self.labelText = labelText
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let inset = thickness / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)

        // draw border
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        path.lineWidth = thickness
        color.withAlphaComponent(0.9).setStroke()
        color.withAlphaComponent(0.05).setFill()
        path.fill()
        path.stroke()

        // corner markers for extra visibility
        let markerLen: CGFloat = min(12, rect.width / 4, rect.height / 4)
        color.setStroke()
        for corner in corners(of: rect, length: markerLen) {
            corner.lineWidth = thickness + 1
            corner.stroke()
        }

        // optional label
        if let labelText, !labelText.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white,
                .backgroundColor: color.withAlphaComponent(0.85),
            ]
            let str = NSAttributedString(string: " \(labelText) ", attributes: attrs)
            let size = str.size()
            let labelRect = NSRect(x: rect.minX, y: rect.maxY + 2, width: size.width, height: size.height)
            str.draw(in: labelRect)
        }
    }

    func corners(of rect: NSRect, length: CGFloat) -> [NSBezierPath] {
        var paths: [NSBezierPath] = []
        // top-left
        let tl = NSBezierPath()
        tl.move(to: NSPoint(x: rect.minX, y: rect.maxY - length))
        tl.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        tl.line(to: NSPoint(x: rect.minX + length, y: rect.maxY))
        paths.append(tl)
        // top-right
        let tr = NSBezierPath()
        tr.move(to: NSPoint(x: rect.maxX - length, y: rect.maxY))
        tr.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        tr.line(to: NSPoint(x: rect.maxX, y: rect.maxY - length))
        paths.append(tr)
        // bottom-left
        let bl = NSBezierPath()
        bl.move(to: NSPoint(x: rect.minX, y: rect.minY + length))
        bl.line(to: NSPoint(x: rect.minX, y: rect.minY))
        bl.line(to: NSPoint(x: rect.minX + length, y: rect.minY))
        paths.append(bl)
        // bottom-right
        let br = NSBezierPath()
        br.move(to: NSPoint(x: rect.maxX - length, y: rect.minY))
        br.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        br.line(to: NSPoint(x: rect.maxX, y: rect.minY + length))
        paths.append(br)
        return paths
    }
}

// MARK: - say

private func handleSay(_ args: [String]) {
    let flags = parseFlags(args)
    let positional = flags.positional
    let voice = flags.named["voice"] ?? flags.named["v"]
    let rate = flags.named["rate"] ?? flags.named["r"]

    guard !positional.isEmpty else {
        if flags.has("list") || flags.has("l") {
            for v in NSSpeechSynthesizer.availableVoices {
                let a = NSSpeechSynthesizer.attributes(forVoice: v)
                let name = a[.name] as? String ?? "?"
                let lang = a[.localeIdentifier] as? String ?? ""
                print("  \(name) (\(lang))")
            }
            return
        }
        printError("usage: hey-listen say <text> [--voice <name>] [--rate <wpm>]")
        exit(1)
    }

    let synth = NSSpeechSynthesizer()
    if let voice {
        if let match = NSSpeechSynthesizer.availableVoices.first(where: {
            (NSSpeechSynthesizer.attributes(forVoice: $0)[.name] as? String ?? "")
                .localizedCaseInsensitiveContains(voice)
        }) { synth.setVoice(match) }
    }
    if let rate, let r = Float(rate) { synth.rate = r }

    synth.startSpeaking(positional.joined(separator: " "))
    while synth.isSpeaking {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}

// MARK: - clipboard

private func handleClipboard(_ args: [String]) {
    guard let sub = args.first else {
        printError("usage: hey-listen clipboard <get|set> [text]")
        exit(1)
    }
    let pb = NSPasteboard.general
    switch sub {
    case "get", "read":
        guard let text = pb.string(forType: .string) else {
            printError("clipboard empty or not text")
            exit(1)
        }
        print(text)
    case "set", "write", "copy":
        let text = Array(args.dropFirst()).joined(separator: " ")
        guard !text.isEmpty else {
            printError("no text provided")
            exit(1)
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        print("copied")
    default:
        printError("unknown: \(sub)")
        exit(1)
    }
}

// MARK: - open

private func handleOpen(_ args: [String]) {
    guard let target = args.first else {
        printError("usage: hey-listen open <url|path>")
        exit(1)
    }
    if let url = URL(string: target), url.scheme != nil {
        NSWorkspace.shared.open(url)
    } else {
        NSWorkspace.shared.open(URL(fileURLWithPath: target))
    }
    print("opened \(target)")
}

// MARK: - info

private func handleInfo(_ args: [String]) {
    let sub = args.first ?? "all"
    switch sub {
    case "battery": printBattery()
    case "dark", "darkmode", "dark-mode": printDarkMode()
    case "display", "screen": printDisplay()
    case "frontapp", "front-app": printFrontApp()
    case "all":
        printBattery(); printDarkMode(); printDisplay(); printFrontApp()
    default:
        printError("options: battery, dark-mode, display, front-app, all")
        exit(1)
    }
}

private func printBattery() {
    let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let srcs = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef]
    for s in srcs {
        guard let d = IOPSGetPowerSourceDescription(snap, s)?.takeUnretainedValue() as? [String: Any] else { continue }
        let cap = d[kIOPSCurrentCapacityKey] as? Int ?? -1
        let chg = d[kIOPSIsChargingKey] as? Bool ?? false
        let src = d[kIOPSPowerSourceStateKey] as? String ?? "?"
        print("battery: \(cap)% | charging: \(chg) | source: \(src)")
    }
}

private func printDarkMode() {
    let a = NSApplication.shared.effectiveAppearance.name
    let dark = a == .darkAqua || a == .vibrantDark
        || a == .accessibilityHighContrastDarkAqua
        || a == .accessibilityHighContrastVibrantDark
    print("dark-mode: \(dark)")
}

private func printDisplay() {
    for (i, s) in NSScreen.screens.enumerated() {
        print("display[\(i)]: \(Int(s.frame.width))x\(Int(s.frame.height)) @ \(s.backingScaleFactor)x")
    }
}

private func printFrontApp() {
    if let app = NSWorkspace.shared.frontmostApplication {
        print("front-app: \(app.localizedName ?? "?") (pid: \(app.processIdentifier))")
    }
}

// MARK: - helpers

private struct ParsedFlags: Sendable {
    var positional: [String] = []
    var named: [String: String] = [:]

    func has(_ key: String) -> Bool {
        named.keys.contains(key)
    }
}

private func parseFlags(_ args: [String]) -> ParsedFlags {
    var r = ParsedFlags()
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let k = String(a.dropFirst(2))
            if let eq = k.firstIndex(of: "=") {
                r.named[String(k[k.startIndex..<eq])] = String(k[k.index(after: eq)...])
            } else if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                r.named[k] = args[i + 1]; i += 1
            } else {
                r.named[k] = "true"
            }
        } else if a.hasPrefix("-") && a.count == 2 {
            let k = String(a.dropFirst(1))
            if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                r.named[k] = args[i + 1]; i += 1
            } else {
                r.named[k] = "true"
            }
        } else {
            r.positional.append(a)
        }
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
      hey-listen setup             open permissions setup screen

    commands:
      sound <name|path>            play a sound
        --volume <0.0-1.0>         volume (default: 1.0)
        --list                     list available sounds

      notify <title> [body]        send a macOS notification
        --sound <name>             notification sound
        --subtitle <text>          subtitle

      toast <message>              floating overlay banner
        --duration <seconds>       display time (default: 3.0)

      highlight <x> <y> <w> <h>   draw a pulsing bounding box on screen
        --color <name>             red, green, blue, yellow, orange, purple, cyan
        --thickness <px>           border thickness (default: 3)
        --label <text>             label above the box
        --duration <seconds>       display time (default: 3.0)

      say <text>                   text-to-speech
        --voice <name>             voice (partial match)
        --rate <wpm>               speech rate
        --list                     list voices

      clipboard get|set [text]     read/write clipboard
      open <url|path>              open in browser/Finder
      login enable|disable|status  manage start-on-login

      info [topic]                 system info
        battery, dark-mode, display, front-app, all

    sound aliases:
      success, error, warning, done, start, ping, pop, purr,
      tink, morse, submarine, funk, frog, bottle

    examples:
      hey-listen sound done
      hey-listen notify "Build done" "all tests passed"
      hey-listen toast "deploying..." --duration 5
      hey-listen say "task finished"
      hey-listen info battery
    """)
}
