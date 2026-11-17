import AppKit
import CoreGraphics
import Darwin
import IOKit

final class TestPreferences: ConfigPreferences {
    var values: [String: Any] = [:]
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}
final class WeakReference<T: AnyObject> {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}
final class TestPermissions {
    var accessibility = false
    var inputMonitoring = false
    var accessibilityRequests = 0
    var inputRequests = 0
    var grantOnRequest = false
    var access: PermissionAccess {
        PermissionAccess(accessibilityGranted: { self.accessibility },
            inputMonitoringGranted: { self.inputMonitoring },
            requestAccessibility: {
                self.accessibilityRequests += 1
                if self.grantOnRequest { self.accessibility = true }
            }, requestInputMonitoring: {
                self.inputRequests += 1
                if self.grantOnRequest { self.inputMonitoring = true }
            })
    }
}

enum TestIO {
    private static var frontFixture = "test.browser"
    static var nativeFront = false
    static var front: String {
        get { nativeFront ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" : frontFixture }
        set { frontFixture = newValue }
    }
    static var overrideDevice = true
    static var device: DeviceInfo? = mouse
    static let mouse = DeviceInfo(id: 100, name: "Wireless Mouse", vendor: 0x046D, product: 1, transport: "Bluetooth")
    static let other = DeviceInfo(id: 101, name: "Other Mouse", vendor: 0x1234, product: 1, transport: "USB")
    static let keyboard = DeviceInfo(id: 102, name: "Keyboard", vendor: 0x05AC, product: 2, transport: "USB", isMouse: false, isKeyboard: true)
    static let receiverMouse = DeviceInfo(id: 501, name: "Universal Receiver", vendor: 0x1234, product: 18,
        transport: "USB", physicalUSBDevice: 9001)
    static let receiverKeys = DeviceInfo(id: 502, name: "Receiver keyboard interface", vendor: 0x1234, product: 18,
        transport: "USB", isMouse: false, isKeyboard: true, physicalUSBDevice: 9001)
    static var events: [CGEvent] = []
    static var missions: [String] = []
    static var lookups = 0
    static func record(_ event: CGEvent) { events.append(event.copy()!) }
}

struct Failure: Error { let message: String }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message: message) }
}
func pump(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}
func event(_ type: CGEventType, code: Int64 = 123, flags: CGEventFlags = .maskControl,
           button: Int64 = 2, horizontal: Int64 = 1, vertical: Int64 = 0, continuous: Bool = false) -> CGEvent {
    let e: CGEvent
    switch type {
    case .keyDown, .keyUp:
        e = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(clamping: code), keyDown: type == .keyDown)!
        e.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
    case .scrollWheel:
        e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
                    wheel1: Int32(clamping: vertical), wheel2: Int32(clamping: horizontal), wheel3: 0)!
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
    case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
        let mouseButton: CGMouseButton = [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(type) ? .left :
            ([CGEventType.rightMouseDown, .rightMouseUp, .rightMouseDragged].contains(type) ? .right : .center)
        e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: mouseButton)!
        e.setIntegerValueField(.mouseEventButtonNumber, value: mouseButton == .right ? 1 : mouseButton == .left ? 0 : button)
    default:
        e = CGEvent(source: nil)!
        e.type = type
    }
    e.flags = flags
    return e
}
func keyDowns() -> [Int64] {
    TestIO.events.filter { $0.type == .keyDown }.map { $0.getIntegerValueField(.keyboardEventKeycode) }
}

@main struct EngineTests {
    static var passed = 0
    static var failed = 0
    static var results: [[String: Any]] = []
    static var store: Store { Store.shared }

    static func reset() {
        pump(0.06)
        Store.shared = Store(preferences: TestPreferences(), migrateLegacy: false)
        store.config = Config()
        store.config.tiltGap = 0.08
        store.config.tiltHold = 0.12
        store.config.controlArrowSideButtons = true
        store.config.language = .en
        store.logging = false
        store.liveTestVisible = false
        store.connectedDevices = []
        store.seenDevices = []
        store.clearLog()
        store.active = []
        store.selected = .sideBack
        TestIO.front = "test.browser"
        TestIO.overrideDevice = true
        TestIO.device = TestIO.mouse
        TestIO.events = []
        TestIO.missions = []
        TestIO.lookups = 0
    }

    static func test(_ name: String, _ body: (Engine) throws -> Void) {
        reset()
        do {
            try body(Engine())
            passed += 1
            results.append(["name": name, "pass": true])
            print("PASS \(name)")
        } catch {
            failed += 1
            let message = (error as? Failure)?.message ?? String(describing: error)
            results.append(["name": name, "pass": false, "detail": message])
            print("FAIL \(name): \(message)")
        }
    }

    static func main() throws {
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--crash-speed") {
            store.config.scrollSpeed = 1e300
            store.config.tiltHold = 0
            let engine = Engine()
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            Thread.sleep(forTimeInterval: 0.06)
            let held = event(.scrollWheel)
            let result = engine.handle(.scrollWheel, held)
            try expect(result != nil && held.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 6 && TestIO.events.count == 1,
                "Huge-speed regression did not reach the clamped hold/scale path")
            print("PASS former crash: speed clamped to 6, accumulated scroll flushed, hold scaled without a trap")
            return
        }
        if CommandLine.arguments.contains("--perf") { performance(); return }
        if CommandLine.arguments.contains("--live-probe") { liveProbe(); return }
        if CommandLine.arguments.contains("--tap-probe") { try tapProbe(); return }
        if CommandLine.arguments.contains("--receiver-probe") { try receiverProbe(); return }
        #if TEST_UI
        if CommandLine.arguments.contains("--ui") { try UITests.run(); return }
        #endif

        test("Config JSON round trip, custom shortcuts and exclusions") { _ in
            var c = Config()
            c.custom["middle"] = Shortcut(keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, display: "⌘C")
            c.excludedApps = ["test.game"]
            c.mapping["middle"] = "custom"
            let data = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            try expect(decoded == c, "Configuration changed")
        }
        test("Legacy partial JSON supplies defaults") { _ in
            let c = try JSONDecoder().decode(Config.self, from: Data("{\"enabled\":false}".utf8))
            try expect(!c.enabled && c.tiltHold == 0.35 && c.smartNav, "Missing defaults")
        }
        test("Malformed JSON is rejected") { _ in
            do {
                _ = try JSONDecoder().decode(Config.self, from: Data("{\"tiltHold\":\"bad\"}".utf8))
                throw Failure(message: "Invalid JSON accepted")
            } catch is DecodingError {}
        }
        test("All trigger defaults, mapping options and reset") { _ in
            for t in Trigger.allCases {
                try expect(store.action(for: t) == t.defaultAction, "Wrong default \(t)")
                try expect(Action.options(for: t).contains(.hScroll) == t.isTilt, "Invalid action option")
                store.setAction(.disabled, for: t)
            }
            store.config.custom["middle"] = Shortcut(keyCode: 1, flags: 0, display: "S")
            store.resetDefaults()
            try expect(store.config.custom.isEmpty && store.config.mapping.isEmpty, "Reset incomplete")
        }
        test("Unknown mapping falls back to default") { _ in
            store.config.mapping["sideBack"] = "future-action"
            try expect(store.action(for: .sideBack) == .back, "Bad fallback")
        }

        let shortcuts: [(Action, UInt16, CGEventFlags)] = [
            (.back, 33, .maskCommand), (.forward, 30, .maskCommand),
            (.tabPrev, 33, [.maskCommand, .maskShift]), (.tabNext, 30, [.maskCommand, .maskShift]),
            (.closeTab, 13, .maskCommand), (.reopenTab, 17, [.maskCommand, .maskShift]),
            (.spaceLeft, 123, [.maskControl, .maskSecondaryFn, .maskNumericPad]),
            (.spaceRight, 124, [.maskControl, .maskSecondaryFn, .maskNumericPad]),
            (.copy, 8, .maskCommand), (.paste, 9, .maskCommand), (.undo, 6, .maskCommand)
        ]
        for (action, code, flags) in shortcuts {
            test("Action \(action.rawValue): key pair, flags and loop marker") { engine in
                engine.perform(action, .middle)
                try expect(TestIO.events.count == 2, "Expected down/up pair")
                try expect(TestIO.events.map(\.type) == [.keyDown, .keyUp], "Wrong event types")
                try expect(TestIO.events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == code && $0.flags == flags && $0.getIntegerValueField(.eventSourceUserData) == kMarker }, "Wrong key, modifiers or marker")
            }
        }
        for (action, arg) in [(Action.missionControl, "overview"), (.appWindows, "2"), (.showDesktop, "1")] {
            test("Action \(action.rawValue): Mission Control request") { engine in
                engine.perform(action, .middle)
                try expect(TestIO.missions == [arg], "Wrong Mission Control argument")
            }
        }
        for action in [Action.passthrough, .disabled, .custom] {
            test("Action \(action.rawValue): no shortcut configured emits nothing") { engine in
                engine.perform(action, .middle)
                try expect(TestIO.events.isEmpty && TestIO.missions.isEmpty, "Unexpected output")
            }
        }
        test("Custom shortcut emits recorded key and flags") { engine in
            store.config.custom["middle"] = Shortcut(keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, display: "⌘C")
            engine.perform(.custom, .middle)
            try expect(keyDowns() == [8] && TestIO.events.allSatisfy { $0.flags == .maskCommand }, "Wrong custom shortcut")
        }
        test("hScroll action respects direction and configured lines") { engine in
            engine.perform(.hScroll, .tiltLeftTap)
            engine.perform(.hScroll, .tiltRightTap)
            try expect(TestIO.events.map { $0.getIntegerValueField(.scrollWheelEventDeltaAxis2) } == [6, -6], "Wrong scroll output")
        }
        for bundle in Engine.codeEditors {
            test("Smart navigation in \(bundle)") { engine in
                TestIO.front = bundle
                engine.perform(.back, .sideBack)
                engine.perform(.forward, .sideForward)
                try expect(keyDowns() == [27, 27], "Wrong editor navigation keys")
                try expect(TestIO.events[0].flags == .maskControl && TestIO.events[2].flags == [.maskControl, .maskShift], "Wrong editor modifiers")
            }
        }
        test("Smart navigation can be disabled") { engine in
            TestIO.front = "com.microsoft.VSCode"
            store.config.smartNav = false
            engine.perform(.back, .sideBack)
            try expect(keyDowns() == [33], "Smart navigation did not disable")
        }
        test("Generated events bypass remapping") { engine in
            let e = event(.keyDown)
            e.setIntegerValueField(.eventSourceUserData, value: kMarker)
            try expect(e.getIntegerValueField(.eventSourceUserData) == kMarker, "Fixture marker cannot be represented")
            try expect(engine.handle(.keyDown, e) != nil && TestIO.events.isEmpty, "Generated event loop")
        }
        test("Tap-disabled callbacks return without output") { engine in
            try expect(engine.handle(.tapDisabledByTimeout, event(.null)) != nil, "Timeout callback failed")
            try expect(engine.handle(.tapDisabledByUserInput, event(.null)) != nil, "User-input callback failed")
        }
        for (code, expected) in [(Int64(123), Int64(33)), (124, 30)] {
            test("Side key \(code): down/up consumed; repeat does not repeat action") { engine in
                try expect(engine.handle(.keyDown, event(.keyDown, code: code)) == nil, "Down not consumed")
                let repeatEvent = event(.keyDown, code: code)
                repeatEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
                try expect(engine.handle(.keyDown, repeatEvent) == nil, "Repeat leaked")
                try expect(engine.handle(.keyUp, event(.keyUp, code: code)) == nil, "Up leaked")
                try expect(keyDowns() == [expected], "Action repeated")
            }
        }
        test("Keyboard Ctrl+arrow from identified keyboard passes through") { engine in
            TestIO.device = TestIO.keyboard
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Other keyboard intercepted")
        }
        test("Compatibility side shortcuts work across mouse brands") { engine in
            TestIO.device = TestIO.other
            try expect(engine.handle(.keyDown, event(.keyDown)) == nil && keyDowns() == [33], "Global remapping failed")
        }
        test("Unidentified keyboard shortcuts are protected") { engine in
            TestIO.device = nil
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Unknown device Ctrl+Left was consumed and remapped")
        }
        test("Other modifiers and unrelated keys pass through") { engine in
            for flags: CGEventFlags in [[], .maskCommand, [.maskControl, .maskShift], [.maskControl, .maskAlternate], [.maskControl, .maskCommand]] {
                try expect(engine.handle(.keyDown, event(.keyDown, flags: flags)) != nil, "Unrelated shortcut consumed")
            }
            try expect(engine.handle(.keyDown, event(.keyDown, code: 8)) != nil && TestIO.events.isEmpty, "Unrelated key consumed")
        }
        test("Disabled/excluded/passthrough side keys pass through") { engine in
            store.config.enabled = false
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil, "Disabled still remaps")
            store.config.enabled = true
            store.config.excludedApps = [TestIO.front]
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil, "Excluded app still remaps")
            store.config.excludedApps = []
            store.setAction(.passthrough, for: .sideBack)
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Passthrough still remaps")
        }
        test("Consumed key down remains consumed if Ctrl released before key up") { engine in
            _ = engine.handle(.keyDown, event(.keyDown))
            try expect(engine.handle(.keyUp, event(.keyUp, flags: [])) == nil, "Unpaired original keyUp leaked after releasing Ctrl")
        }
        test("Right-click remap consumes down/drag/up even after disabling") { engine in
            store.setAction(.copy, for: .rightClick)
            try expect(engine.handle(.rightMouseDown, event(.rightMouseDown)) == nil, "Down not consumed")
            store.config.enabled = false
            try expect(engine.handle(.rightMouseDragged, event(.rightMouseDragged)) == nil, "Drag leaked")
            try expect(engine.handle(.rightMouseUp, event(.rightMouseUp)) == nil, "Up leaked")
            try expect(engine.handle(.rightMouseUp, event(.rightMouseUp)) != nil && keyDowns() == [8], "Right-click state did not reset")
        }
        test("Right-click respects identified other-device filter") { engine in
            store.setAction(.disabled, for: .rightClick)
            TestIO.device = TestIO.other
            store.config.selectedDevice = TestIO.mouse.selection
            try expect(engine.handle(.rightMouseDown, event(.rightMouseDown)) != nil, "Other device right-click consumed")
        }
        for (button, trigger) in [(Int64(2), Trigger.middle), (3, .sideBack), (4, .sideForward), (5, .extraButton(6)), (31, .extraButton(32))] {
            test("Mouse button \(button): remaps once and consumes down/up") { engine in
                store.setAction(.copy, for: trigger)
                try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: button)) == nil, "Down not consumed")
                try expect(engine.handle(.otherMouseUp, event(.otherMouseUp, button: button)) == nil && keyDowns() == [8], "Up handling failed")
            }
        }
        test("Unmapped and unknown mouse buttons pass through") { engine in
            for button: Int64 in [2, 5, 20, 32] {
                try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: button)) != nil, "Unmapped button consumed")
            }
        }
        test("Other-device middle button respects mouse filter") { engine in
            store.setAction(.disabled, for: .middle)
            TestIO.device = TestIO.other
            store.config.selectedDevice = TestIO.mouse.selection
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown)) != nil, "Other device middle button consumed")
        }
        test("Middle-button release stays paired when disabled during press") { engine in
            store.setAction(.disabled, for: .middle)
            _ = engine.handle(.otherMouseDown, event(.otherMouseDown))
            store.config.enabled = false
            try expect(engine.handle(.otherMouseUp, event(.otherMouseUp)) == nil, "Unpaired middle up leaked")
        }
        test("Middle-button passthrough press keeps release after enabling remap") { engine in
            _ = engine.handle(.otherMouseDown, event(.otherMouseDown))
            store.setAction(.disabled, for: .middle)
            try expect(engine.handle(.otherMouseUp, event(.otherMouseUp)) != nil, "Original middle up consumed; receiving app can retain pressed state")
        }
        test("Continuous trackpad, vertical and diagonal scroll pass through") { engine in
            try expect(engine.handle(.scrollWheel, event(.scrollWheel, continuous: true)) != nil, "Trackpad intercepted")
            try expect(engine.handle(.scrollWheel, event(.scrollWheel, horizontal: 0, vertical: 1)) != nil, "Vertical scroll intercepted")
            try expect(engine.handle(.scrollWheel, event(.scrollWheel, vertical: 1)) != nil && TestIO.events.isEmpty, "Diagonal scroll intercepted")
        }
        for (h, code) in [(Int64(1), Int64(33)), (-1, 30)] {
            test("Tilt tap \(h): delayed navigation once") { engine in
                try expect(engine.handle(.scrollWheel, event(.scrollWheel, horizontal: h)) == nil, "Tap leaked")
                try expect(TestIO.events.isEmpty, "Tap fired too early")
                pump(0.12)
                try expect(keyDowns() == [code], "Wrong delayed navigation")
            }
        }
        test("Tilt passthrough mappings preserve original event") { engine in
            store.setAction(.passthrough, for: .tiltLeftTap)
            store.setAction(.passthrough, for: .tiltLeftHold)
            try expect(engine.handle(.scrollWheel, event(.scrollWheel)) != nil, "Passthrough tilt consumed")
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Passthrough generated duplicate")
        }
        test("Tilt hold releases accumulated scroll and scales subsequent events") { engine in
            for _ in 0..<5 {
                _ = engine.handle(.scrollWheel, event(.scrollWheel, horizontal: 2))
                pump(0.035)
            }
            let e = event(.scrollWheel, horizontal: 2)
            e.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 10)
            e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 2)
            try expect(engine.handle(.scrollWheel, e) != nil, "Held scroll suppressed")
            try expect(e.getIntegerValueField(.scrollWheelEventDeltaAxis2) == 4 && e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == 20 && e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == 4, "Scroll fields: lines=\(e.getIntegerValueField(.scrollWheelEventDeltaAxis2)) points=\(e.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)) fixed=\(e.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2))")
            pump(0.12)
            try expect(keyDowns().isEmpty && TestIO.events.count == 1, "Hold also generated tap or duplicate flush")
        }
        test("Tilt hold action fires only once per burst") { engine in
            store.setAction(.copy, for: .tiltLeftHold)
            for _ in 0..<8 {
                try expect(engine.handle(.scrollWheel, event(.scrollWheel)) == nil, "Mapped hold leaked")
                pump(0.035)
            }
            pump(0.12)
            try expect(keyDowns() == [8], "Hold did not fire exactly once")
        }
        test("Tilt tap hScroll uses configured line count") { engine in
            store.setAction(.hScroll, for: .tiltLeftTap)
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            pump(0.12)
            try expect(TestIO.events.count == 1 && TestIO.events[0].getIntegerValueField(.scrollWheelEventDeltaAxis2) == 6, "Wrong tap scroll")
        }
        test("Disabling mappings cancels a pending tilt tap") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            store.config.enabled = false
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Delayed back shortcut emitted while mappings disabled")
        }
        test("Switching to an excluded app cancels pending tilt tap") { engine in
            store.config.excludedApps = ["test.game"]
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            TestIO.front = "test.game"
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Delayed shortcut emitted into excluded app")
        }
        test("Rapid opposite tilt taps both produce navigation") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel, horizontal: 1))
            pump(0.005)
            _ = engine.handle(.scrollWheel, event(.scrollWheel, horizontal: -1))
            pump(0.12)
            try expect(keyDowns() == [33, 30], "Expected back and forward, got \(keyDowns())")
        }
        test("Other-device horizontal scroll respects mouse filter") { engine in
            TestIO.device = TestIO.other
            store.config.selectedDevice = TestIO.mouse.selection
            try expect(engine.handle(.scrollWheel, event(.scrollWheel)) != nil, "Other mouse horizontal scroll consumed")
        }
        test("A new tilt after a blocked main loop starts a new burst") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            Thread.sleep(forTimeInterval: 0.20)
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            pump(0.12)
            try expect(keyDowns() == [33, 33], "Separated taps merged into a hold because timer had not run")
        }
        test("Device lookup negatively caches an unresolvable sender") { engine in
            TestIO.overrideDevice = false
            let e = event(.leftMouseDown)
            e.setIntegerValueField(kSenderField, value: Int64.max - 100)
            try expect(e.getIntegerValueField(kSenderField) == Int64.max - 100, "Fixture sender ID cannot be represented")
            for _ in 0..<10 { _ = engine.device(for: e) }
            try expect(TestIO.lookups == 1, "Missing device retried \(TestIO.lookups) times; cache entries=\(engine.testCacheCount)")
        }
        test("Live log coalesces repeat and caps at 400 entries") { _ in
            store.logging = true
            for _ in 0..<10 { store.addLog(.scroll, "repeat", device: "mouse", result: nil) }
            pump(0.02)
            try expect(store.log.count == 1 && store.log[0].count == 10, "Repeat aggregation failed")
            for i in 0..<1000 { store.addLog(.scroll, "event \(i)", device: "mouse", result: nil) }
            pump(0.12)
            try expect(store.log.count == 400 && store.log[0].text == "event 999", "Log retention failed")
        }
        test("Live log distinguishes events from different devices") { _ in
            store.logging = true
            store.addLog(.click, "Sol tık", device: "Mouse A", result: nil)
            store.addLog(.click, "Sol tık", device: "Mouse B", result: nil)
            pump(0.02)
            try expect(store.log.count == 2, "Different device events merged into first device entry")
        }
        test("Paused logging rejects new events") { _ in
            store.logging = false
            store.addLog(.key, "paused", device: nil, result: nil)
            pump(0.02)
            try expect(store.log.isEmpty, "Paused log still appends")
        }
        test("Clearing log does not resurrect queued entries") { _ in
            store.logging = true
            store.addLog(.key, "queued", device: nil, result: nil)
            store.clearLog()
            pump(0.02)
            try expect(store.log.isEmpty, "Queued entry appeared after Clear")
        }
        test("Repeated flashes clear after last event") { _ in
            store.flash("wheel")
            pump(0.02)
            store.flash("wheel")
            pump(0.32)
            try expect(store.active.contains("wheel"), "Flash ended before last event deadline")
            pump(0.06)
            try expect(!store.active.contains("wheel"), "Flash stuck")
        }
        test("Decoded settings reject values that crash scroll scaling") { _ in
            let c = try JSONDecoder().decode(Config.self, from: Data("{\"scrollSpeed\":1e300,\"tiltGap\":-1,\"tiltHold\":-1}".utf8))
            try expect(c.scrollSpeed.isFinite && (1...6).contains(c.scrollSpeed) && c.tiltGap > 0 && c.tiltHold > 0, "Out-of-range numeric settings accepted")
        }
        test("New configuration is brand independent and preserves keyboard shortcuts") { engine in
            store.config = Config()
            try expect(store.config.selectedDevice == nil && !store.config.controlArrowSideButtons, "Unsafe new defaults")
            for dev in [TestIO.mouse, TestIO.other] {
                TestIO.device = dev
                try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) == nil, "Native back not mapped")
                _ = engine.handle(.otherMouseUp, event(.otherMouseUp, button: 3))
                try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 4)) == nil, "Native forward not mapped")
                _ = engine.handle(.otherMouseUp, event(.otherMouseUp, button: 4))
            }
            try expect(keyDowns() == [33, 30, 33, 30], "Brand-dependent native mappings")
            let count = TestIO.events.count
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.count == count, "Compatibility unexpectedly enabled")
        }
        test("Unknown physical mouse works in all-mice mode") { engine in
            TestIO.device = nil
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) == nil && keyDowns() == [33], "Unknown physical mouse ignored")
        }
        test("Selected mouse mode rejects unidentified physical sources") { engine in
            store.config.selectedDevice = TestIO.mouse.selection
            TestIO.device = nil
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) != nil, "Unknown source bypassed selection")
            try expect(engine.handle(.scrollWheel, event(.scrollWheel)) != nil && TestIO.events.isEmpty, "Unknown scroll bypassed selection")
        }
        test("Device filter uses product and name, not vendor alone") { engine in
            store.config.selectedDevice = TestIO.mouse.selection
            TestIO.device = DeviceInfo(id: 110, name: "Another Model", vendor: TestIO.mouse.vendor, product: 99, transport: "USB")
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) != nil, "Other model shares vendor")
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Other model keyboard alias consumed")
        }
        test("Selected mouse survives transport and registry ID changes") { engine in
            store.config.selectedDevice = TestIO.mouse.selection
            TestIO.device = DeviceInfo(id: 111, name: TestIO.mouse.name, vendor: TestIO.mouse.vendor, product: TestIO.mouse.product, transport: "USB")
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) == nil && keyDowns() == [33], "Transport-bound selection")
        }
        test("Known trackpad buttons and discrete horizontal events are preserved") { engine in
            TestIO.device = DeviceInfo(id: 112, name: "Trackpad", vendor: 1, product: 2, transport: "Bluetooth", isMouse: true, isTrackpad: true)
            store.setAction(.disabled, for: .rightClick)
            try expect(engine.handle(.rightMouseDown, event(.rightMouseDown)) != nil, "Trackpad click remapped")
            try expect(engine.handle(.scrollWheel, event(.scrollWheel)) != nil, "Discrete trackpad event remapped")
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Trackpad shortcut remapped")
        }
        test("Press decisions are independent for two mouse senders") { engine in
            store.setAction(.disabled, for: .middle)
            let a = event(.otherMouseDown)
            a.setIntegerValueField(kSenderField, value: 201)
            try expect(engine.handle(.otherMouseDown, a) == nil, "First mouse press leaked")
            store.setAction(.passthrough, for: .middle)
            let b = event(.otherMouseDown)
            b.setIntegerValueField(kSenderField, value: 202)
            try expect(engine.handle(.otherMouseDown, b) != nil, "Second mouse press swallowed")
            let upB = event(.otherMouseUp); upB.setIntegerValueField(kSenderField, value: 202)
            let upA = event(.otherMouseUp); upA.setIntegerValueField(kSenderField, value: 201)
            try expect(engine.handle(.otherMouseUp, upB) != nil && engine.handle(.otherMouseUp, upA) == nil, "Mouse release decisions crossed")
        }
        test("Other-mouse drags honor the press decision") { engine in
            store.setAction(.disabled, for: .middle)
            _ = engine.handle(.otherMouseDown, event(.otherMouseDown))
            store.config.enabled = false
            try expect(engine.handle(.otherMouseDragged, event(.otherMouseDragged)) == nil, "Remapped drag leaked")
        }
        test("Disabling and immediately enabling does not revive pending tilt") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            store.config.enabled = false; store.config.enabled = true
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Old tilt revived")
        }
        test("Changing a mapping cancels its pending tilt") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            store.setAction(.closeTab, for: .tiltLeftTap)
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Pending tilt used a new action")
        }
        test("Switching to any other application cancels pending tilt") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            TestIO.front = "test.other-app"
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Pending tilt entered a different app")
        }
        test("Shortcut recording bypasses remaps and cancels pending tilt") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            store.recordingShortcut = true
            defer { store.recordingShortcut = false }
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil, "Recorder shortcut intercepted")
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) != nil, "Recorder mouse intercepted")
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Old tilt fired during recording")
        }
        test("Engine deallocation cancels delayed work") { _ in
            var engine: Engine? = Engine()
            let reference = WeakReference(engine)
            _ = engine?.handle(.scrollWheel, event(.scrollWheel))
            engine = nil
            try expect(reference.value == nil, "Engine retained by a timer or observer")
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Deallocated engine sent an action")
        }
        test("Direct numeric mutations clamp huge, infinite and NaN settings") { _ in
            store.config.scrollSpeed = 1e300
            try expect(store.config.scrollSpeed == 6, "Huge speed not clamped")
            store.config.scrollSpeed = .nan; store.config.tiltGap = -.infinity
            store.config.tiltHold = -1; store.config.tapScrollLines = Int.max
            try expect(store.config.scrollSpeed.isFinite && store.config.tiltGap > 0 && store.config.tiltHold > 0 && store.config.tapScrollLines == 30, "Invalid direct settings")
        }
        test("Legacy native assignments and custom shortcuts migrate") { _ in
            let data = Data(#"{"mouseVendorID":12994,"onlyFromMouse":false,"mapping":{"button4":"custom","button5":"paste"},"custom":{"button4":{"keyCode":8,"flags":1048576,"display":"⌘C"}}}"#.utf8)
            let c = try JSONDecoder().decode(Config.self, from: data)
            try expect(c.schemaVersion == 2 && c.selectedDevice == nil && c.controlArrowSideButtons, "Legacy device lock or compatibility lost")
            try expect(c.mapping["sideBack"] == "custom" && c.mapping["sideForward"] == "paste" && c.custom["sideBack"]?.keyCode == 8, "Legacy mappings lost")
            try expect(c.mapping["button4"] == nil && c.custom["button4"] == nil, "Legacy keys remain active")
        }
        test("Modern configuration round trip preserves device and language") { _ in
            var c = Config()
            c.language = .tr; c.selectedDevice = TestIO.other.selection
            c.excludedApps = ["z.app", "a.app"]
            let data = try JSONEncoder().encode(c)
            let decoded = try JSONDecoder().decode(Config.self, from: data)
            try expect(decoded == c, "Modern configuration changed")
        }
        test("Unknown saved language falls back to system") { _ in
            let c = try JSONDecoder().decode(Config.self, from: Data(#"{"schemaVersion":2,"language":"xx"}"#.utf8))
            try expect(c.language == .system && !c.controlArrowSideButtons, "Unknown language or schema fallback")
        }
        test("Store persists language, mappings and device across recreation") { _ in
            let preferences = TestPreferences()
            do {
                let instance = Store(preferences: preferences, migrateLegacy: false)
                instance.config.language = .tr
                instance.config.selectedDevice = TestIO.other.selection
                instance.setAction(.copy, for: .extraButton(9))
            }
            let restored = Store(preferences: preferences, migrateLegacy: false)
            try expect(restored.config.language == .tr && restored.config.selectedDevice == TestIO.other.selection && restored.action(for: .extraButton(9)) == .copy, "Persisted settings lost")
            preferences.values["config.v1"] = Data("invalid".utf8)
            let recovered = Store(preferences: preferences, migrateLegacy: false)
            try expect(recovered.config == Config(), "Corrupt preferences did not recover")
        }
        test("Quick shortcut recording cancellation cannot revive pending tilt") { engine in
            _ = engine.handle(.scrollWheel, event(.scrollWheel))
            store.recordingShortcut = true; store.recordingShortcut = false
            pump(0.12)
            try expect(TestIO.events.isEmpty, "Tilt revived after recording")
        }
        test("Turkish and English switch titles without changing identifiers") { _ in
            let ids = Trigger.allCases.map(\.rawValue)
            store.config.language = .tr
            try expect(Action.copy.title == "Kopyala" && Trigger.sideBack.title == "Yan tuş · Geri", "Turkish titles missing")
            store.config.language = .en
            try expect(Action.copy.title == "Copy" && Trigger.sideBack.title == "Side button · Back", "English titles missing")
            try expect(Trigger.allCases.map(\.rawValue) == ids && Action.back.group == "navigation", "Language changed stable keys")
            for language in AppLanguage.allCases {
                store.config.language = language
                try expect(Action.allCases.allSatisfy { !$0.title.isEmpty } && Trigger.allCases.allSatisfy { !$0.title.isEmpty }, "Empty translation")
            }
        }
        test("All mouse buttons through 32 have unique stable Codable triggers") { _ in
            try expect(Set(Trigger.allCases.map(\.rawValue)).count == Trigger.allCases.count, "Duplicate identifiers")
            for index: Int64 in 0...31 {
                let t = Trigger.mouseButton(index)!
                let data = try JSONEncoder().encode(t)
                let decoded = try JSONDecoder().decode(Trigger.self, from: data)
                try expect(decoded == t && t.buttonIndex == index, "Button trigger mismatch")
            }
        }
        test("Pause drops log entries queued before pausing") { _ in
            store.logging = true
            store.addLog(.click, "queued", device: nil, result: nil)
            store.logging = false
            pump(0.02)
            try expect(store.log.isEmpty, "Queued log appeared during pause")
        }
        test("Settings window preserves right-click input even with a remapped action") { engine in
            TestIO.front = Engine.applicationBundleID
            store.selectTrigger(.tiltLeftTap)
            store.setAction(.closeTab, for: .rightClick)
            let reveal = store.selectionReveal
            for _ in 0..<20 {
                try expect(engine.handle(.rightMouseDown, event(.rightMouseDown)) != nil, "Settings right down swallowed")
                try expect(engine.handle(.rightMouseUp, event(.rightMouseUp)) != nil, "Settings right up swallowed")
            }
            pump(0.02)
            try expect(store.selected == .tiltLeftTap && store.selectionReveal == reveal, "Right-click stole UI selection or scrolled the form")
            try expect(TestIO.events.isEmpty && store.active.contains("right"), "Settings remapped its own click or lost feedback")
        }
        test("Settings preserves side buttons, compatibility keys and tilt") { engine in
            TestIO.front = Engine.applicationBundleID
            store.logging = true
            store.selectTrigger(.tiltRightTap)
            try expect(engine.handle(.otherMouseDown, event(.otherMouseDown, button: 3)) != nil, "Settings back button swallowed")
            _ = engine.handle(.otherMouseUp, event(.otherMouseUp, button: 3))
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil, "Settings shortcut remapped")
            _ = engine.handle(.keyUp, event(.keyUp))
            try expect(engine.handle(.scrollWheel, event(.scrollWheel)) != nil, "Settings tilt swallowed")
            pump(0.12)
            try expect(TestIO.events.isEmpty && store.selected == .tiltRightTap, "Settings changed itself")
            try expect(!store.log.isEmpty && store.active.contains("tiltLeft"), "Live feedback disappeared in own UI")
        }
        test("Physical feedback never requests assignment scrolling") { engine in
            let initial = store.selectionReveal
            _ = engine.handle(.otherMouseDown, event(.otherMouseDown, button: 4))
            pump(0.02)
            try expect(store.selected == .sideForward && store.selectionReveal == initial, "Physical button requested scrolling")
            store.selectTrigger(.tiltLeftTap, reveal: true)
            try expect(store.selectionReveal == initial + 1, "Illustration selection did not request reveal")
            store.selectTrigger(.tiltLeftTap, reveal: true)
            try expect(store.selectionReveal == initial + 2, "Repeated illustration click ignored")
        }
        test("Rapid manual selections do not wait for flash expiration") { _ in
            let sequence: [Trigger] = [.tiltLeftTap, .rightClick, .tiltRightTap, .middle, .sideBack, .sideForward]
            for _ in 0..<20 {
                for t in sequence {
                    store.flash(t.hotspot)
                    store.selectTrigger(t)
                    try expect(store.selected == t, "Selection deferred behind a flash timer")
                }
            }
        }
        test("Release swallowed before entering Settings stays paired") { engine in
            store.setAction(.disabled, for: .rightClick)
            try expect(engine.handle(.rightMouseDown, event(.rightMouseDown)) == nil, "Outside click not swallowed")
            TestIO.front = Engine.applicationBundleID
            try expect(engine.handle(.rightMouseUp, event(.rightMouseUp)) == nil, "Original release pairing lost")
        }
        test("First launch requests missing permissions only once across recreation") { _ in
            let preferences = TestPreferences(), permissions = TestPermissions()
            let first = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            first.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 1 && permissions.inputRequests == 1, "First request missing")
            let rebuilt = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            rebuilt.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 1 && permissions.inputRequests == 1, "Recreated app requested denied permissions again")
            try expect(!rebuilt.axGranted && !rebuilt.inputGranted, "Missing permissions hidden")
        }
        test("Explicit permission retry works after a refusal") { _ in
            let preferences = TestPreferences(), permissions = TestPermissions()
            let instance = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch()
            permissions.grantOnRequest = true
            instance.requestPermissions()
            try expect(permissions.accessibilityRequests == 2 && permissions.inputRequests == 2, "Explicit retry suppressed")
            try expect(instance.axGranted && instance.inputGranted, "New grants not reflected")
        }
        test("Granted permissions are never requested again") { _ in
            let preferences = TestPreferences(), permissions = TestPermissions()
            permissions.accessibility = true; permissions.inputMonitoring = true
            let instance = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch(); instance.requestPermissions()
            let restarted = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            restarted.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 0 && permissions.inputRequests == 0, "Already granted permission prompted")
        }
        test("Only the missing input permission is requested") { _ in
            let permissions = TestPermissions(); permissions.accessibility = true
            let instance = Store(preferences: TestPreferences(), migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 0 && permissions.inputRequests == 1, "Extra accessibility request")
        }
        test("Only the missing accessibility permission is requested") { _ in
            let permissions = TestPermissions(); permissions.inputMonitoring = true
            let instance = Store(preferences: TestPreferences(), migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 1 && permissions.inputRequests == 0, "Extra input-monitoring request")
        }
        test("Permission polling and revocation update status without opening prompts") { _ in
            let preferences = TestPreferences(), permissions = TestPermissions()
            permissions.accessibility = true; permissions.inputMonitoring = true
            let instance = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch()
            permissions.accessibility = false
            for _ in 0..<20 { instance.refreshPermissions() }
            let restarted = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            restarted.requestPermissionsAtLaunch()
            try expect(!restarted.axGranted && restarted.inputGranted, "Revocation not visible")
            try expect(permissions.accessibilityRequests == 0 && permissions.inputRequests == 0, "Polling or restarting opened prompts")
        }
        test("Resetting mappings does not reset permission-request history") { _ in
            let preferences = TestPreferences(), permissions = TestPermissions()
            let instance = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            instance.requestPermissionsAtLaunch()
            instance.resetDefaults(); instance.config.language = .tr
            let restarted = Store(preferences: preferences, migrateLegacy: false, permissions: permissions.access)
            restarted.requestPermissionsAtLaunch()
            try expect(permissions.accessibilityRequests == 1 && permissions.inputRequests == 1, "Mapping/language reset restarted permission prompts")
        }
        test("Default left click preserves down, drag and release") { engine in
            try expect(store.action(for: .leftClick) == .passthrough, "Left click must default to pass through")
            for type in [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
                try expect(engine.handle(type, event(type)) != nil, "Default primary input swallowed")
            }
            try expect(TestIO.events.isEmpty, "Default left click emitted an action")
        }
        test("Left-click remap fires once and pairs down, drag and release") { engine in
            store.setAction(.copy, for: .leftClick)
            for type in [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
                try expect(engine.handle(type, event(type)) == nil, "Remapped primary input leaked")
            }
            try expect(keyDowns() == [8] && TestIO.events.count == 2, "Left click did not emit one shortcut")
        }
        test("Left release keeps initial decision across configuration changes") { engine in
            store.setAction(.disabled, for: .leftClick)
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) == nil, "Disabled left click leaked")
            store.config.enabled = false
            try expect(engine.handle(.leftMouseUp, event(.leftMouseUp)) == nil, "Swallowed primary release leaked")
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) != nil, "Paused primary press swallowed")
            store.config.enabled = true
            try expect(engine.handle(.leftMouseUp, event(.leftMouseUp)) != nil, "Passed primary release swallowed")
        }
        test("Option-click bypasses a primary-button assignment through release") { engine in
            store.setAction(.disabled, for: .leftClick)
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown, flags: .maskAlternate)) != nil, "Option recovery click swallowed")
            try expect(engine.handle(.leftMouseDragged, event(.leftMouseDragged, flags: [])) != nil, "Recovery drag swallowed")
            try expect(engine.handle(.leftMouseUp, event(.leftMouseUp, flags: [])) != nil, "Recovery release swallowed")
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown, flags: [])) == nil, "Normal click did not resume mapping")
            _ = engine.handle(.leftMouseUp, event(.leftMouseUp))
        }
        test("Left-click assignments respect selected device and preserve trackpad") { engine in
            store.setAction(.disabled, for: .leftClick)
            store.config.selectedDevice = TestIO.mouse.selection
            TestIO.device = TestIO.other
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) != nil, "Other device primary click swallowed")
            _ = engine.handle(.leftMouseUp, event(.leftMouseUp))
            store.config.selectedDevice = nil
            TestIO.device = DeviceInfo(id: 113, name: "Trackpad", vendor: 1, product: 2, transport: "Bluetooth", isMouse: true, isTrackpad: true)
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) != nil, "Trackpad primary click swallowed")
            _ = engine.handle(.leftMouseUp, event(.leftMouseUp))
        }
        test("Settings remains clickable with a disabled left-click mapping") { engine in
            store.setAction(.disabled, for: .leftClick)
            store.selectTrigger(.rightClick)
            TestIO.front = Engine.applicationBundleID
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) != nil, "Settings primary click swallowed")
            try expect(engine.handle(.leftMouseUp, event(.leftMouseUp)) != nil, "Settings primary release swallowed")
            pump(0.02)
            try expect(store.selected == .rightClick && TestIO.events.isEmpty && !store.active.contains("left"), "Configuration clicks caused unrelated primary feedback")
        }
        test("Click targeting the app passes through before it becomes frontmost") { engine in
            store.setAction(.disabled, for: .leftClick)
            let e = event(.leftMouseDown)
            let pid = Int64(ProcessInfo.processInfo.processIdentifier)
            e.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
            try expect(e.getIntegerValueField(.eventTargetUnixProcessID) == pid, "Fixture target PID not represented")
            try expect(engine.handle(.leftMouseDown, e) != nil && TestIO.events.isEmpty, "Click to activate Settings swallowed")
            try expect(engine.handle(.leftMouseUp, event(.leftMouseUp)) != nil, "Activation release swallowed")
        }
        test("Left-click mapping persists and resets to its native default") { _ in
            let preferences = TestPreferences()
            let first = Store(preferences: preferences, migrateLegacy: false)
            first.setAction(.custom, for: .leftClick)
            first.config.custom["leftClick"] = Shortcut(keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, display: "⌘C")
            let restored = Store(preferences: preferences, migrateLegacy: false)
            try expect(restored.action(for: .leftClick) == .custom && restored.config.custom["leftClick"]?.keyCode == 8, "Left-click assignment lost")
            restored.resetDefaults()
            try expect(restored.action(for: .leftClick) == .passthrough, "Left-click default not restored")
        }
        test("Live Test highlights left click without executing its assignment") { engine in
            TestIO.front = Engine.applicationBundleID
            store.liveTestVisible = true
            store.setAction(.copy, for: .leftClick)
            try expect(engine.handle(.leftMouseDown, event(.leftMouseDown)) != nil, "Live Test primary click swallowed")
            _ = engine.handle(.leftMouseUp, event(.leftMouseUp))
            pump(0.02)
            try expect(store.active.contains("left") && TestIO.events.isEmpty, "Live primary feedback missing or assignment executed")
        }
        test("Composite receiver side keys resolve through its sibling mouse interface") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            store.config.selectedDevice = TestIO.receiverMouse.selection
            TestIO.device = TestIO.receiverKeys
            for code: Int64 in [123, 124] {
                try expect(engine.handle(.keyDown, event(.keyDown, code: code)) == nil, "Receiver side key not recognized")
                try expect(engine.handle(.keyUp, event(.keyUp, code: code)) == nil, "Receiver side release leaked")
            }
            try expect(keyDowns() == [33, 30], "Receiver did not emit Back/Forward")
        }
        test("Identical receivers on separate USB devices are not merged") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            var other = TestIO.receiverKeys; other.physicalUSBDevice = 9002
            TestIO.device = other
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Separate keyboard/receiver misclassified")
        }
        test("A keyboard-only receiver is never treated as a mouse") { engine in
            TestIO.device = TestIO.receiverKeys
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Keyboard without pointer accepted")
        }
        test("Missing physical USB ancestry does not match a receiver by name or vendor") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            var keys = TestIO.receiverKeys; keys.physicalUSBDevice = nil
            TestIO.device = keys
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Metadata-only receiver match")
        }
        test("Receiver aliases still require compatibility mode") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            store.config.controlArrowSideButtons = false
            TestIO.device = TestIO.receiverKeys
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Compatibility setting ignored")
        }
        test("Receiver pointer must match the selected mouse") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            store.config.selectedDevice = TestIO.mouse.selection
            TestIO.device = TestIO.receiverKeys
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Selected mouse filter bypassed")
        }
        test("A trackpad sibling does not qualify a receiver keyboard") { engine in
            var pointer = TestIO.receiverMouse; pointer.isTrackpad = true
            store.connectedDevices = [pointer]
            TestIO.device = TestIO.receiverKeys
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Trackpad treated as receiver mouse")
        }
        test("Unrelated internal keyboard stays native with receiver compatibility enabled") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            TestIO.device = TestIO.keyboard
            try expect(engine.handle(.keyDown, event(.keyDown)) != nil && TestIO.events.isEmpty, "Internal keyboard intercepted")
        }
        test("Receiver Ctrl+Shift or Ctrl+Option arrows retain their keyboard behavior") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            TestIO.device = TestIO.receiverKeys
            for flags: CGEventFlags in [[.maskControl, .maskShift], [.maskControl, .maskAlternate], [.maskControl, .maskCommand]] {
                try expect(engine.handle(.keyDown, event(.keyDown, flags: flags)) != nil, "Modified keyboard shortcut intercepted")
                _ = engine.handle(.keyUp, event(.keyUp, flags: flags))
            }
            try expect(TestIO.events.isEmpty, "Modified receiver key emitted action")
        }
        test("Live Test identifies receiver side keys and previews their assignment") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            store.config.selectedDevice = TestIO.receiverMouse.selection
            TestIO.device = TestIO.receiverKeys
            TestIO.front = Engine.applicationBundleID
            store.liveTestVisible = true; store.logging = true
            try expect(engine.handle(.keyDown, event(.keyDown)) == nil, "Live Test leaked receiver Ctrl+arrow to macOS Spaces")
            try expect(engine.handle(.keyUp, event(.keyUp)) == nil, "Live Test leaked receiver key release")
            pump(0.02)
            try expect(store.active.contains("sideBack") && TestIO.events.isEmpty, "Receiver feedback missing or preview executed")
            try expect(store.log.first?.kind == .button && store.log.first?.text.contains("Side button") == true && store.log.first?.result == "Preview · Back", "Receiver still labeled as keyboard")
        }
        test("Receiver repeat and release preserve the initial remap decision") { engine in
            store.connectedDevices = [TestIO.receiverMouse]
            TestIO.device = TestIO.receiverKeys
            _ = engine.handle(.keyDown, event(.keyDown))
            let repeated = event(.keyDown); repeated.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            try expect(engine.handle(.keyDown, repeated) == nil, "Receiver repeat leaked")
            store.config.controlArrowSideButtons = false
            try expect(engine.handle(.keyUp, event(.keyUp, flags: [])) == nil && keyDowns() == [33], "Receiver release or repeat pairing failed")
        }
        test("All 616 trigger/action combinations dispatch through the event engine") { _ in
            var combinations = 0
            for trigger in Trigger.allCases {
                for action in Action.options(for: trigger) {
                    let engine = Engine()
                    store.config = Config()
                    store.config.tiltGap = 0.08
                    store.config.tiltHold = 0.12
                    for t in Trigger.allCases { store.setAction(.disabled, for: t) }
                    store.setAction(action, for: trigger)
                    store.config.custom[trigger.rawValue] = Shortcut(keyCode: 8, flags: CGEventFlags.maskCommand.rawValue, display: "⌘C")
                    TestIO.events = []
                    TestIO.missions = []
                    if trigger.isTilt {
                        if trigger == .tiltLeftHold || trigger == .tiltRightHold {
                            for _ in 0..<6 {
                                _ = engine.handle(.scrollWheel, event(.scrollWheel, horizontal: trigger.direction))
                                pump(0.035)
                            }
                        } else {
                            _ = engine.handle(.scrollWheel, event(.scrollWheel, horizontal: trigger.direction))
                        }
                        pump(0.12)
                    } else if trigger == .leftClick {
                        _ = engine.handle(.leftMouseDown, event(.leftMouseDown))
                        _ = engine.handle(.leftMouseUp, event(.leftMouseUp))
                    } else if trigger == .rightClick {
                        _ = engine.handle(.rightMouseDown, event(.rightMouseDown))
                        _ = engine.handle(.rightMouseUp, event(.rightMouseUp))
                    } else {
                        let button = trigger.buttonIndex!
                        _ = engine.handle(.otherMouseDown, event(.otherMouseDown, button: button))
                        _ = engine.handle(.otherMouseUp, event(.otherMouseUp, button: button))
                    }
                    let name = "\(trigger.rawValue)/\(action.rawValue)"
                    if [.missionControl, .appWindows, .showDesktop].contains(action) {
                        try expect(TestIO.missions.count == 1 && TestIO.events.isEmpty, "Wrong dispatch \(name)")
                    } else if action == .hScroll || (action == .passthrough && trigger.isTilt) {
                        try expect(TestIO.events.count == 1 && TestIO.events[0].type == .scrollWheel, "Wrong scroll dispatch \(name)")
                    } else if action == .disabled || action == .passthrough {
                        try expect(TestIO.events.isEmpty && TestIO.missions.isEmpty, "Unexpected dispatch \(name)")
                    } else {
                        try expect(TestIO.events.count == 2 && keyDowns().count == 1 && TestIO.missions.isEmpty, "Wrong key dispatch \(name)")
                    }
                    combinations += 1
                }
            }
            print("MATRIX checked \(combinations) combinations")
            try expect(combinations == 616, "Action matrix count changed")
        }
        pump(0.4)
        print("RESULT \(passed) passed; \(failed) failed; \(passed + failed) total")
        if let index = CommandLine.arguments.firstIndex(of: "--json"), CommandLine.arguments.count > index + 1 {
            let data = try JSONSerialization.data(withJSONObject: ["passed": passed, "failed": failed, "tests": results], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        exit(failed == 0 ? 0 : 1)
    }

    static func liveProbe() {
        store.refreshPermissions()
        print("Accessibility=\(store.axGranted) InputMonitoring=\(store.inputGranted)")
        let engine = Engine()
        engine.refreshMouseInfo()
        print("Mouse=\(store.mouseName ?? "none") Transport=\(store.mouseTransport ?? "none")")
    }

    static func receiverProbe() throws {
        reset()
        TestIO.overrideDevice = false
        let engine = Engine()
        engine.refreshMouseInfo()
        let pointers = store.connectedDevices
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOHIDDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw Failure(message: "Cannot inspect HID devices")
        }
        defer { IOObjectRelease(iterator) }
        var tested = 0, protected = 0
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            var id: UInt64 = 0
            let success = IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS
            IOObjectRelease(service)
            guard success else { continue }
            let key = event(.keyDown)
            key.setIntegerValueField(kSenderField, value: Int64(bitPattern: id))
            guard let info = engine.device(for: key), info.isKeyboard, !info.isMouse else { continue }
            let pointer = info.physicalUSBDevice.flatMap { group in pointers.first { $0.physicalUSBDevice == group } }
            if let pointer {
                store.config.selectedDevice = pointer.selection
                TestIO.events = []
                for code: Int64 in [123, 124] {
                    let down = event(.keyDown, code: code), up = event(.keyUp, code: code)
                    for e in [down, up] { e.setIntegerValueField(kSenderField, value: Int64(bitPattern: id)) }
                    try expect(engine.handle(.keyDown, down) == nil, "Connected receiver alias not recognized")
                    try expect(engine.handle(.keyUp, up) == nil, "Connected receiver release leaked")
                }
                try expect(keyDowns() == [33, 30], "Connected receiver produced wrong actions")
                print("RECEIVER PASS: \(info.name) vendor=\(info.vendor) product=\(info.product) keyboard=\(id) pointer=\(pointer.id) USB-parent=\(info.physicalUSBDevice!) Back/Forward outputs captured")
                tested += 1
            } else {
                TestIO.events = []
                try expect(engine.handle(.keyDown, key) != nil && TestIO.events.isEmpty, "Unrelated real keyboard intercepted")
                let up = event(.keyUp); up.setIntegerValueField(kSenderField, value: Int64(bitPattern: id))
                _ = engine.handle(.keyUp, up)
                protected += 1
            }
        }
        try expect(tested > 0, "No connected composite receiver was verified")
        print("RECEIVER RESULT: \(tested) connected receiver(s) verified; \(protected) unrelated keyboard interface(s) preserved; no events posted to the system")
    }

    static func tapProbe() throws {
        store.config.enabled = false
        TestIO.nativeFront = true
        TestIO.overrideDevice = false
        store.refreshPermissions()
        guard store.axGranted && store.inputGranted else {
            print("TAP SKIP: missing existing permissions; no permission dialog requested")
            return
        }
        let engine = Engine.shared
        engine.start()
        try expect(engine.testTapEnabled && store.tapRunning, "Event tap creation failed")
        let originalPort = engine.testTapPort
        for _ in 0..<20 { engine.start() }
        try expect(engine.testTapPort == originalPort, "Repeated start creates a new event tap")
        _ = engine.handle(.tapDisabledByTimeout, event(.null))
        try expect(engine.testTapEnabled, "Timeout recovery did not enable tap")
        pump(0.2)
        try expect(TestIO.events.isEmpty && TestIO.missions.isEmpty, "Disabled probe generated an action")
        print("TAP PASS: creation, 20 idempotent starts, timeout callback; disabled mappings; no posted events")
    }

    static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    static func performance() {
        reset()
        TestIO.nativeFront = CommandLine.arguments.contains("--native-front")
        print("PERF: optimized isolated event engine; device fixture; no SwiftUI rendering")
        print("Native foreground query: \(TestIO.nativeFront)")
        let engine = Engine()
        store.config.enabled = false
        let bypass = event(.keyDown, code: 8)
        var start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100_000 { _ = engine.handle(.keyDown, bypass) }
        print(String(format: "unrelated key: %.3f us/event", (CFAbsoluteTimeGetCurrent() - start) * 10))
        let wheel = event(.scrollWheel, horizontal: 0, vertical: 1)
        pump(0.5)
        print("RSS baseline: \(residentBytes())")
        for cycle in 1...8 {
            start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<10_000 {
                autoreleasepool { _ = engine.handle(.scrollWheel, wheel) }
            }
            let queued = residentBytes()
            pump(0.5)
            print(String(format: "wheel cycle %d: enqueue %.2f ms, queued RSS %llu, drained RSS %llu", cycle, (CFAbsoluteTimeGetCurrent() - start - 0.5) * 1000, queued, residentBytes()))
        }
        store.logging = true
        for cycle in 1...4 {
            for i in 0..<10_000 { store.addLog(.scroll, "event \(i)", device: "mouse", result: nil) }
            pump(0.5)
            print("log cycle \(cycle): count=\(store.log.count) RSS=\(residentBytes())")
        }
        if CommandLine.arguments.contains("--leaks") {
            print("LEAKS_READY pid=\(getpid())")
            pump(45)
        }
    }
}
