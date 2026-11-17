import SwiftUI
import AppKit

enum UITests {
    static func run() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let store = Store.shared
        let output = URL(fileURLWithPath: CommandLine.arguments.last!, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--interaction-only") { try rapidIllustrationSelections(); return }
        if CommandLine.arguments.contains("--menu-only") { try actionMenuInteractions(); return }
        store.mouseName = "Wireless Mouse"
        store.mouseTransport = "Bluetooth"
        store.seenDevices = [TestIO.mouse, TestIO.other]
        store.connectedDevices = [TestIO.mouse, TestIO.other]
        for language in [AppLanguage.en, .tr] {
            store.config.language = language
            store.config.mapping = [:]; store.config.custom = [:]
            store.config.selectedDevice = nil
            store.tapRunning = true; store.axGranted = true; store.inputGranted = true
            store.observedButtons = [.extraButton(6), .extraButton(8)]
            let langOutput = output.appendingPathComponent(language.rawValue)
            try FileManager.default.createDirectory(at: langOutput, withIntermediateDirectories: true)
            try render("buttons", ButtonsView().environmentObject(store), at: langOutput)
            store.selectTrigger(.leftClick)
            try render("buttons-left-selected", ButtonsView().environmentObject(store), at: langOutput)
            store.setAction(.copy, for: .leftClick)
            try render("buttons-left-remapped", ButtonsView().environmentObject(store), at: langOutput)
            store.setAction(.passthrough, for: .leftClick)
            store.setAction(.custom, for: .middle)
            store.config.custom["middle"] = Shortcut(keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, display: "⌘C")
            store.selected = .middle
            try render("buttons-custom", ButtonsView().environmentObject(store), at: langOutput)
            store.clearLog(); store.logPaused = false
            try render("live-empty", LiveTestView().environmentObject(store), at: langOutput)
            store.logPaused = true
            try render("live-paused", LiveTestView().environmentObject(store), at: langOutput)
            store.log = (0..<400).map { i in
                LogEntry(time: Date(), kind: .tilt, text: L("Yatay scroll sola \(i)", "Horizontal scroll left \(i)"), device: "Wireless Mouse", result: Action.back.title)
            }
            try render("live-400-entries", LiveTestView().environmentObject(store), at: langOutput)
            try render("settings", SettingsView().environmentObject(store), at: langOutput, height: 1100)
            try render("window-buttons", shell(.buttons).environmentObject(store), at: langOutput, width: 1040, height: 700)
            try render("window-settings", shell(.settings).environmentObject(store), at: langOutput, width: 1040, height: 700)
            store.tapRunning = false; store.axGranted = false
            try render("permission-banner", PermissionBanner().environmentObject(store), at: langOutput, height: 160)
            try expect(Action.copy.title == (language == .en ? "Copy" : "Kopyala"), "Wrong UI language")
        }
        try recorderLifecycle()
        try rapidIllustrationSelections()
        try actionMenuInteractions()
        print("UI PASS: 22 offscreen views across English/Turkish; recorder, rapid selection and action menu checks")
    }

    private static func shell(_ page: Page) -> some View {
        HStack(spacing: 0) {
            Sidebar(page: .constant(page)).frame(width: 220)
            Divider()
            VStack(spacing: 0) {
                PageHeader(page: page)
                Divider()
                if page == .settings { SettingsView() } else { ButtonsView() }
            }
        }
        .font(AppTypography.body)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private static func actionMenuInteractions() throws {
        let store = Store.shared
        store.config.language = .en
        store.setAction(.back, for: .sideBack)
        let host = NSHostingView(rootView: ActionPicker(trigger: .sideBack).environmentObject(store))
        host.frame = CGRect(x: 0, y: 0, width: 200, height: 44)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000)); window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded(); pump(0.04)
        let watchdog = DispatchSource.makeTimerSource(queue: .global())
        watchdog.schedule(deadline: .now() + 5)
        watchdog.setEventHandler { fputs("FAIL action menu tracking timed out\n", stderr); exit(2) }
        watchdog.resume()
        defer { watchdog.cancel() }
        for (upCount, expected) in [(1, Action.disabled), (2, .passthrough)] {
            let location = host.convert(CGPoint(x: 100, y: 22), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                NSApp.postEvent(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!, atStart: false)
            }
            let keys: [(UInt16, String)] = [(119, "\u{f72b}")] + Array(repeating: (126, "\u{f700}"), count: upCount) + [(36, "\r")]
            for (code, characters) in keys {
                NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: code == 36 ? [] : .function, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!, atStart: false)
            }
            let deadline = Date().addingTimeInterval(0.08)
            while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp, .keyDown], until: deadline, inMode: .default, dequeue: true) {
                NSApp.sendEvent(next)
            }
            pump(0.02)
            try expect(store.action(for: .sideBack) == expected, "Native action menu did not select \(expected.rawValue)")
        }
        print("UI PASS: action menu opened twice, selected Disable/Pass through and closed without a cooldown")
    }

    private static func rapidIllustrationSelections() throws {
        let store = Store.shared
        let host = NSHostingView(rootView: MouseIllustration().environmentObject(store))
        host.frame = CGRect(x: 0, y: 0, width: 290, height: 303)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        pump(0.05)
        let selections: [(CGPoint, Trigger)] = [
            (CGPoint(x: 105, y: 64), .leftClick),
            (CGPoint(x: 195, y: 64), .rightClick),
            (CGPoint(x: 119, y: 66), .tiltLeftTap),
            (CGPoint(x: 171, y: 66), .tiltRightTap),
            (CGPoint(x: 145, y: 66), .middle),
            (CGPoint(x: 61, y: 171), .sideBack)
        ]
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<3 {
            for (point, expected) in selections {
                let location = host.convert(point, to: nil)
                let timestamp = ProcessInfo.processInfo.systemUptime
                let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                    timestamp: timestamp, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 1, clickCount: 1, pressure: 1)!
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                    timestamp: timestamp + 0.001, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 2, clickCount: 1, pressure: 0)!
                NSApp.postEvent(down, atStart: false)
                NSApp.postEvent(up, atStart: false)
                let deadline = Date().addingTimeInterval(0.025)
                while let next = NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp], until: deadline, inMode: .default, dequeue: true) {
                    NSApp.sendEvent(next)
                }
                pump(0.02)
                try expect(store.selected == expected, "Illustration selection stalled on \(expected.rawValue)")
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "UI PASS: %d consecutive local illustration clicks in %.3f seconds", selections.count * 3, elapsed))
    }

    private static func recorderLifecycle() throws {
        let a = ShortcutCapture(), b = ShortcutCapture()
        a.start { _ in }
        try expect(a.recording && Store.shared.recordingShortcut, "Recorder did not start")
        b.start { _ in }
        try expect(!a.recording && b.recording && Store.shared.recordingShortcut, "Two recorders active")
        b.stop()
        try expect(!b.recording && !Store.shared.recordingShortcut, "Recorder did not stop")
        var temporary: ShortcutCapture? = ShortcutCapture()
        let reference = WeakReference(temporary)
        temporary?.start { _ in }
        temporary = nil
        try expect(reference.value == nil && !Store.shared.recordingShortcut, "Recorder retained by monitor")
        print("UI PASS shortcut recorder: transfer, stop, weak monitor cleanup")
        var captured: UInt16?
        a.start { captured = $0.keyCode }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        NSApp.postEvent(key, atStart: true)
        if let next = NSApp.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(next)
        }
        try expect(captured == 8 && !a.recording && !Store.shared.recordingShortcut, "Local shortcut recording failed")
        captured = nil
        a.start { captured = $0.keyCode }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0,
            context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        NSApp.postEvent(escape, atStart: true)
        if let next = NSApp.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(next)
        }
        try expect(captured == nil && !a.recording, "Esc did not cancel")
        print("UI PASS shortcut recorder: local Cmd+C capture and Esc cancellation")
    }

    private static func render<V: View>(_ name: String, _ view: V, at output: URL, width: CGFloat = 820, height: CGFloat = 640) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw Failure(message: "Cannot render \(name)") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "Cannot encode \(name)") }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        window.close()
        print("UI PASS \(output.lastPathComponent)/\(name): \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)")
    }
}
