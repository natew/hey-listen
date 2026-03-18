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
        case "install": handleInstall()
        case "uninstall": handleUninstall()
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = renderFairy(size: 18, forTray: true)
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
        // UNUserNotificationCenter crashes without a bundle, so guard it
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    self.setPermStatus(self.notifStatus, self.notifBtn, granted: settings.authorizationStatus == .authorized)
                }
            }
        } else {
            setPermStatus(notifStatus, notifBtn, granted: false)
            notifStatus.stringValue = "⚠️ needs .app bundle"
            notifBtn.isEnabled = false
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
        guard Bundle.main.bundleIdentifier != nil else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            return
        }
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

// MARK: - install (guided CLI setup)

private func handleInstall() {
    let fm = FileManager.default
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let resolvedExe = (exe as NSString).standardizingPath
    let srcSounds = soundsDir()

    // check if already in a standard PATH location
    let pathDirs = ["/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
    let alreadyInPath = pathDirs.contains((resolvedExe as NSString).deletingLastPathComponent)

    print("hey-listen install")
    print("")

    if alreadyInPath {
        print("binary already in PATH: \(resolvedExe)")
    } else {
        // pick install location
        let localBin = "\(NSHomeDirectory())/.local/bin"
        let usrLocalBin = "/usr/local/bin"

        print("install hey-listen to PATH?")
        print("  1) \(localBin)")
        print("  2) \(usrLocalBin) (requires sudo)")
        print("  s) skip")
        print("")
        print("> ", terminator: ""); fflush(stdout)

        let choice = (readLine() ?? "1").trimmingCharacters(in: .whitespaces)
        let destDir: String

        switch choice {
        case "2": destDir = usrLocalBin
        case "s", "S": destDir = ""
        default: destDir = localBin
        }

        if !destDir.isEmpty {
            try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            let destBin = "\(destDir)/hey-listen"
            try? fm.removeItem(atPath: destBin)
            do {
                try fm.copyItem(atPath: resolvedExe, toPath: destBin)
                // make executable
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destBin)
                print("copied binary to \(destBin)")
            } catch {
                printError("failed to copy: \(error.localizedDescription)")
                printError("try: sudo cp '\(resolvedExe)' '\(destBin)'")
            }

            // copy sounds
            let destSounds = "\(destDir)/sounds"
            if fm.fileExists(atPath: srcSounds) {
                try? fm.removeItem(atPath: destSounds)
                try? fm.copyItem(atPath: srcSounds, toPath: destSounds)
                print("copied sounds to \(destSounds)")
            }

            // check if destDir is in PATH
            let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
            if !path.contains(destDir) {
                print("")
                print("add to your shell profile:")
                print("  export PATH=\"\(destDir):$PATH\"")
            }
        }
    }

    print("")
    print("run permissions setup? (y/n)")
    print("> ", terminator: ""); fflush(stdout)
    let setupChoice = (readLine() ?? "y").trimmingCharacters(in: .whitespaces).lowercased()
    if setupChoice == "y" || setupChoice == "yes" || setupChoice.isEmpty {
        // launch setup as a separate process since it needs MainActor + app.run()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: resolvedExe)
        p.arguments = ["setup"]
        try? p.run(); p.waitUntilExit()
    }

    print("")
    print("done! try: hey-listen sound hey")
}

private func handleUninstall() {
    let fm = FileManager.default
    let pathDirs = ["/usr/local/bin/hey-listen", "\(NSHomeDirectory())/.local/bin/hey-listen"]
    var removed = false
    for path in pathDirs {
        if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
            // remove sounds dir next to it
            let soundsPath = (path as NSString).deletingLastPathComponent + "/sounds"
            try? fm.removeItem(atPath: soundsPath)
            print("removed: \(path)")
            removed = true
        }
    }
    if !removed { print("not found in standard locations") }
    removeLoginItem()
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

// navi sounds bundled alongside the binary
private let NAVI_SOUNDS = ["hey", "hello", "listen", "look", "watchout", "in", "out", "float", "bonk"]

private func soundsDir() -> String {
    let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
    let dir = (exe as NSString).deletingLastPathComponent
    return "\(dir)/sounds"
}

private func resolveSoundPath(_ name: String) -> String {
    let lower = name.lowercased()
    // navi sounds
    if NAVI_SOUNDS.contains(lower) {
        let path = "\(soundsDir())/\(lower).wav"
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    // system sound aliases
    if let alias = SOUND_ALIASES[lower] { return "/System/Library/Sounds/\(alias).aiff" }
    // direct path
    if FileManager.default.fileExists(atPath: name) { return name }
    // system sound by name
    let sys = "/System/Library/Sounds/\(name).aiff"
    if FileManager.default.fileExists(atPath: sys) { return sys }
    printError("sound not found: \(name). use --list"); exit(1)
}

private func listSounds() {
    print("navi sounds:")
    for s in NAVI_SOUNDS { print("  \(s)") }
    print("")
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
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; window.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
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
            completionHandler: { exit(0) })
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

// MARK: - fairy (positionable floating fairy with speech bubble)

// find a window's bounds by app name or title
private func findWindowBounds(_ query: String) -> (x: Double, y: Double, w: Double, h: Double)? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for win in list {
        let owner = win[kCGWindowOwnerName as String] as? String ?? ""
        let title = win[kCGWindowName as String] as? String ?? ""
        let layer = win[kCGWindowLayer as String] as? Int ?? 0
        if layer != 0 { continue }
        if owner.localizedCaseInsensitiveContains(query) || title.localizedCaseInsensitiveContains(query) {
            let b = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return (b["X"] as? Double ?? 0, b["Y"] as? Double ?? 0, b["Width"] as? Double ?? 0, b["Height"] as? Double ?? 0)
        }
    }
    return nil
}

@MainActor
private func runFairy(_ args: [String]) {
    let flags = parseFlags(args)
    let duration = Double(flags.named["duration"] ?? flags.named["d"] ?? "10.0") ?? 10.0
    let message = flags.positional.isEmpty ? nil : flags.positional.joined(separator: " ")
    let windowQuery = flags.named["window"] ?? flags.named["w"]
    let atPos = flags.named["at"]
    let corner = flags.named["corner"] ?? "top-right"
    let soundName = flags.named["sound"] ?? flags.named["s"]

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let screenH = screen.frame.height

    // resolve position
    var posX: CGFloat = screen.visibleFrame.midX
    var posY: CGFloat = screen.visibleFrame.midY

    if let windowQuery, let wb = findWindowBounds(windowQuery) {
        // position relative to window corner (coordinates are top-left origin from CG)
        switch corner {
        case "top-left", "tl":
            posX = CGFloat(wb.x) - 30
            posY = screenH - CGFloat(wb.y) + 10
        case "top-right", "tr":
            posX = CGFloat(wb.x + wb.w) - 40
            posY = screenH - CGFloat(wb.y) + 10
        case "bottom-left", "bl":
            posX = CGFloat(wb.x) - 30
            posY = screenH - CGFloat(wb.y + wb.h) - 60
        case "bottom-right", "br":
            posX = CGFloat(wb.x + wb.w) - 40
            posY = screenH - CGFloat(wb.y + wb.h) - 60
        case "center":
            posX = CGFloat(wb.x + wb.w / 2) - 30
            posY = screenH - CGFloat(wb.y + wb.h / 2)
        default:
            posX = CGFloat(wb.x + wb.w) - 40
            posY = screenH - CGFloat(wb.y) + 10
        }
    } else if let atPos {
        let parts = atPos.split(separator: ",")
        if parts.count == 2, let ax = Double(parts[0]), let ay = Double(parts[1]) {
            posX = CGFloat(ax)
            posY = screenH - CGFloat(ay) // convert top-left to bottom-left
        }
    }

    // don't touch activation policy — avoids stealing focus from other apps
    let app = NSApplication.shared

    // measure bubble
    let bubbleText = message ?? ""
    let hasBubble = !bubbleText.isEmpty
    let bubbleWidth: CGFloat = hasBubble ? min(CGFloat(bubbleText.count * 7 + 16), 240) : 0
    let fairySize: CGFloat = 50
    let closeSize: CGFloat = 18
    let totalW = fairySize + (hasBubble ? bubbleWidth + 8 : 0) + closeSize / 2
    let totalH = fairySize + closeSize / 2

    let window = NSWindow(
        contentRect: NSRect(x: posX, y: posY, width: totalW, height: totalH),
        styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .clear; window.isOpaque = false; window.level = .floating
    window.hasShadow = false
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]

    let contentView = NSView(frame: window.contentView!.bounds)
    window.contentView = contentView

    let fairyImage = NSImageView(frame: NSRect(x: 4, y: 4, width: fairySize - 8, height: fairySize - 8))
    fairyImage.image = renderFairy(size: fairySize - 8)
    fairyImage.imageScaling = .scaleProportionallyUpOrDown
    fairyImage.wantsLayer = true
    fairyImage.layer?.magnificationFilter = .nearest
    contentView.addSubview(fairyImage)

    if hasBubble {
        let bubbleH: CGFloat = 26
        let bubbleY: CGFloat = 14
        let bubbleView = NSView(frame: NSRect(x: fairySize + 4, y: bubbleY, width: bubbleWidth, height: bubbleH))
        bubbleView.wantsLayer = true
        bubbleView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        bubbleView.layer?.cornerRadius = 7
        bubbleView.shadow = NSShadow()
        bubbleView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
        bubbleView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        bubbleView.layer?.shadowRadius = 3
        bubbleView.layer?.shadowOpacity = 1
        contentView.addSubview(bubbleView)

        let bubble = NSTextField(labelWithString: bubbleText)
        bubble.font = NSFont(name: "Menlo", size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .medium)
        bubble.textColor = .labelColor
        bubble.isBezeled = false; bubble.drawsBackground = false
        bubble.alignment = .center
        bubble.frame = NSRect(x: 4, y: 4, width: bubbleWidth - 8, height: 16)
        bubbleView.addSubview(bubble)
    }

    // close circle top-right, overlapping the edge
    let closeContainer = NSView(frame: NSRect(x: totalW - closeSize, y: totalH - closeSize, width: closeSize, height: closeSize))
    closeContainer.wantsLayer = true
    closeContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
    closeContainer.layer?.cornerRadius = closeSize / 2
    closeContainer.shadow = NSShadow()
    closeContainer.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
    closeContainer.layer?.shadowOffset = CGSize(width: 0, height: -1)
    closeContainer.layer?.shadowRadius = 2
    closeContainer.layer?.shadowOpacity = 1
    contentView.addSubview(closeContainer)

    let closeBtn = NSButton(title: "✕", target: FairyCloseHandler.shared, action: #selector(FairyCloseHandler.close))
    closeBtn.isBordered = false
    closeBtn.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
    closeBtn.frame = NSRect(x: 0, y: 0, width: closeSize, height: closeSize)
    closeContainer.addSubview(closeBtn)

    window.alphaValue = 0; window.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.3; window.animator().alphaValue = 1 }

    // play sound if requested
    if let soundName {
        let path = resolveSoundPath(soundName)
        if let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            player.play()
            _fairySoundPlayer = player // prevent dealloc
        }
    }

    // bob just the fairy emoji, not the whole window
    var bobUp = true
    let bobTimer = Timer(timeInterval: 1.2, repeats: true) { _ in
        let dy: CGFloat = bobUp ? 6 : -6
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            var f = fairyImage.frame; f.origin.y += dy
            fairyImage.animator().frame = f
        }
        bobUp.toggle()
    }
    RunLoop.main.add(bobTimer, forMode: .common)

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
        bobTimer.invalidate()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; window.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }
    app.run()
}

// MARK: - fairy pixel art renderer

// renders the pixel art fairy as an NSImage at the given size
// forTray: uses template rendering (white, marks as template for auto dark/light)
func renderFairy(size: CGFloat, forTray: Bool = false) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
        let ctx = NSGraphicsContext.current
        ctx?.shouldAntialias = false
        ctx?.imageInterpolation = .none
        let scale = size / 976.0

        ctx?.cgContext.translateBy(x: 61 * scale, y: 183 * scale)

        let wings: NSColor = forTray ? .black : NSColor(red: 0.76, green: 0.76, blue: 0.76, alpha: 1)
        let body: NSColor = forTray ? .black : NSColor(red: 0.35, green: 0.49, blue: 1.0, alpha: 1)

        // top-left wing
        let w1 = NSBezierPath()
        w1.move(to: p(0, 178, scale)); w1.line(to: p(0, 0, scale)); w1.line(to: p(122, 0, scale))
        w1.line(to: p(122, 61, scale)); w1.line(to: p(244, 61, scale)); w1.line(to: p(244, 122, scale))
        w1.line(to: p(305, 122, scale)); w1.line(to: p(305, 239, scale)); w1.line(to: p(122, 239, scale))
        w1.line(to: p(122, 178, scale)); w1.close()
        wings.setFill(); w1.fill()

        // bottom-left wing
        let w2 = NSBezierPath()
        w2.move(to: p(183, 610, scale)); w2.line(to: p(183, 432, scale)); w2.line(to: p(244, 432, scale))
        w2.line(to: p(244, 366, scale)); w2.line(to: p(305, 366, scale)); w2.line(to: p(305, 427, scale))
        w2.line(to: p(366, 427, scale)); w2.line(to: p(366, 549, scale)); w2.line(to: p(305, 549, scale))
        w2.line(to: p(305, 610, scale)); w2.close()
        wings.setFill(); w2.fill()

        // bottom-right wing
        let w3 = NSBezierPath()
        w3.move(to: p(488, 544, scale)); w3.line(to: p(488, 422, scale)); w3.line(to: p(549, 422, scale))
        w3.line(to: p(549, 366, scale)); w3.line(to: p(610, 366, scale)); w3.line(to: p(610, 427, scale))
        w3.line(to: p(671, 427, scale)); w3.line(to: p(671, 605, scale)); w3.line(to: p(549, 605, scale))
        w3.line(to: p(549, 544, scale)); w3.close()
        wings.setFill(); w3.fill()

        // top-right wing
        let w4 = NSBezierPath()
        w4.move(to: p(671, 239, scale)); w4.line(to: p(671, 300, scale)); w4.line(to: p(610, 300, scale))
        w4.line(to: p(610, 239, scale)); w4.line(to: p(549, 239, scale)); w4.line(to: p(549, 122, scale))
        w4.line(to: p(610, 122, scale)); w4.line(to: p(610, 61, scale)); w4.line(to: p(732, 61, scale))
        w4.line(to: p(732, 0, scale)); w4.line(to: p(854, 0, scale)); w4.line(to: p(854, 178, scale))
        w4.line(to: p(793, 178, scale)); w4.line(to: p(793, 239, scale)); w4.close()
        wings.setFill(); w4.fill()

        // body (blue diamond)
        let b1 = NSBezierPath()
        b1.move(to: p(488, 488, scale)); b1.line(to: p(366, 488, scale)); b1.line(to: p(366, 427, scale))
        b1.line(to: p(305, 427, scale)); b1.line(to: p(305, 366, scale)); b1.line(to: p(244, 366, scale))
        b1.line(to: p(244, 244, scale)); b1.line(to: p(305, 244, scale)); b1.line(to: p(305, 183, scale))
        b1.line(to: p(366, 183, scale)); b1.line(to: p(366, 122, scale)); b1.line(to: p(488, 122, scale))
        b1.line(to: p(488, 188, scale)); b1.line(to: p(549, 188, scale)); b1.line(to: p(549, 249, scale))
        b1.line(to: p(610, 249, scale)); b1.line(to: p(610, 371, scale)); b1.line(to: p(549, 371, scale))
        b1.line(to: p(549, 427, scale)); b1.line(to: p(488, 427, scale)); b1.close()
        body.setFill(); b1.fill()

        return true
    }
    if forTray { img.isTemplate = true }
    return img
}

private func p(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) -> NSPoint {
    NSPoint(x: x * s, y: y * s)
}

private var _fairySoundPlayer: AVAudioPlayer?

class FairyCloseHandler: NSObject {
    static let shared = FairyCloseHandler()
    @objc func close() { exit(0) }
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

      fairy [message]              floating fairy with optional speech bubble
        --window <name>            position on a window (app or title match)
        --corner <pos>             tl, tr, bl, br, center (default: tr)
        --at <x,y>                 exact screen position (top-left origin)
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
      install                      guided setup (copy to PATH + permissions)
      uninstall                    remove from PATH

      info [topic]                 system info
        battery, dark-mode, display, front-app, all

    sound aliases:
      success, error, warning, done, start, ping, pop, purr,
      tink, morse, submarine, funk, frog, bottle

    examples:
      hey-listen sound done
      hey-listen fairy "check this!" --window Terminal
      hey-listen fairy "hey!" --at 500,300
      hey-listen notify "Build done" "all tests passed"
      hey-listen highlight 100 200 400 300 --color green --label "button"
      hey-listen windows --app Terminal --json
      hey-listen toast "deploying..."
    """)
}
