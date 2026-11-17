import AppKit
import CoreGraphics
import IOKit
import Combine

let kSenderField = CGEventField(rawValue: 87)!
let kMarker: Int64 = 0x4D52_4D50

struct DeviceInfo: Identifiable, Hashable {
    let id: UInt64
    let name: String
    let vendor: Int
    let product: Int
    let transport: String
    var isMouse = true
    var isTrackpad = false
    var isKeyboard = false
    var physicalUSBDevice: UInt64?
    var selection: DeviceSelection { DeviceSelection(vendor: vendor, product: product, name: name) }
}

private let engineCallback: CGEventTapCallBack = { _, type, event, _ in
    Engine.shared.handle(type, event)
}

final class Engine {
    static let shared = Engine()
    private var store: Store { Store.shared }
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var deviceCache: [UInt64: DeviceInfo?] = [:]
    private var lastDeviceRefresh = -Double.infinity
    private var configSubscription: AnyCancellable?
    private var recordingSubscription: AnyCancellable?
    private var activationObserver: NSObjectProtocol?

    private struct Press: Hashable {
        var keyboard: Bool
        var code: Int64
        var sender: Int64
    }
    private var presses: [Press: Bool] = [:]
    private var tiltStart: TimeInterval?
    private var tiltLast: TimeInterval = 0
    private var tiltDir: Int64 = 0
    private var tiltHolding = false
    private var tiltAccum: Int64 = 0
    private var tiltGen = 0
    private var tiltDevice: String?
    private var tiltSender: Int64 = 0
    private var tiltFront = ""
    private var tiltConfig: Config?
    private var tiltWork: DispatchWorkItem?
    private var tiltActivity: NSObjectProtocol?

    static let codeEditors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "com.vscodium",
    ]
    static var applicationBundleID: String { Bundle.main.bundleIdentifier ?? "com.local.splinter" }

    init() {
        configSubscription = store.$config.sink { [weak self] cfg in
            guard let self, self.tiltStart != nil, cfg != self.tiltConfig else { return }
            self.cancelTilt()
        }
        recordingSubscription = store.$recordingShortcut.sink { [weak self] recording in
            if recording { self?.cancelTilt() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancelTilt() }
    }

    func start() {
        store.refreshPermissions()
        if ProcessInfo.processInfo.systemUptime - lastDeviceRefresh >= 10 { refreshMouseInfo() }
        guard store.axGranted && store.inputGranted else {
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            store.tapRunning = false
            cancelTilt()
            return
        }
        if let tap, CFMachPortIsValid(tap) {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            let running = CGEvent.tapIsEnabled(tap: tap)
            if store.tapRunning != running { store.tapRunning = running }
            return
        }
        removeTap()
        let types: [CGEventType] = [.keyDown, .keyUp, .scrollWheel, .otherMouseDown, .otherMouseUp,
            .otherMouseDragged, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: engineCallback, userInfo: nil),
            let source = CFMachPortCreateRunLoopSource(nil, t, 0) else {
            store.tapRunning = false
            return
        }
        tap = t; tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        store.tapRunning = CGEvent.tapIsEnabled(tap: t)
    }

    private func removeTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tapSource = nil; tap = nil
    }
    func stop() { cancelTilt(); removeTap(); store.tapRunning = false }

    func refreshMouseInfo() {
        lastDeviceRefresh = ProcessInfo.processInfo.systemUptime
        deviceCache.removeAll(keepingCapacity: true)
        var devices: [DeviceInfo] = []
        if let match = IOServiceMatching("IOHIDDevice") {
            var iter: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS {
                defer { IOObjectRelease(iter) }
                while true {
                    let service = IOIteratorNext(iter)
                    if service == 0 { break }
                    var id: UInt64 = 0
                    if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS {
                        let d = readDevice(service, id: id)
                        if d.isMouse && !d.isTrackpad { devices.append(d) }
                    }
                    IOObjectRelease(service)
                }
            }
        }
        devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if store.connectedDevices != devices { store.connectedDevices = devices }
        let selected = store.config.selectedDevice
        let best = selected.flatMap { s in devices.first { s.matches($0) } } ?? (selected == nil ? devices.first : nil)
        let name = best?.name, transport = best?.transport
        if store.mouseName != name { store.mouseName = name }
        if store.mouseTransport != transport { store.mouseTransport = transport }
        if store.seenDevices.count > 64 { store.seenDevices = Array(store.seenDevices.suffix(64)) }
    }

    func device(for event: CGEvent) -> DeviceInfo? {
        let id = UInt64(bitPattern: event.getIntegerValueField(kSenderField))
        guard id != 0 else { return nil }
        if let cached = deviceCache[id] { return cached }
        let info = lookup(id)
        if deviceCache.count >= 256 { deviceCache.removeAll(keepingCapacity: true) }
        deviceCache[id] = .some(info)
        if let info {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.store.seenDevices.contains(where: { $0.id == info.id }) else { return }
                if self.store.seenDevices.count >= 64 { self.store.seenDevices.removeFirst() }
                self.store.seenDevices.append(info)
            }
        }
        return info
    }
    private func lookup(_ id: UInt64) -> DeviceInfo? {
        guard let matching = IORegistryEntryIDMatching(id) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return readDevice(service, id: id)
    }
    private func readDevice(_ service: io_registry_entry_t, id: UInt64) -> DeviceInfo {
        func prop(_ key: String) -> Any? {
            IORegistryEntrySearchCFProperty(service, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents))
        }
        let name = prop("Product") as? String ?? L("Bilinmeyen cihaz", "Unknown device")
        let pairs = prop("DeviceUsagePairs") as? [[String: Int]] ?? []
        let mouseUsage = ((prop("PrimaryUsagePage") as? Int) == 1 && (prop("PrimaryUsage") as? Int) == 2)
            || pairs.contains { $0["DeviceUsagePage"] == 1 && $0["DeviceUsage"] == 2 }
        let keyboardUsage = ((prop("PrimaryUsagePage") as? Int) == 1 && (prop("PrimaryUsage") as? Int) == 6)
            || pairs.contains { $0["DeviceUsagePage"] == 1 && $0["DeviceUsage"] == 6 }
        let lower = name.lowercased()
        return DeviceInfo(id: id, name: name, vendor: prop("VendorID") as? Int ?? 0,
            product: prop("ProductID") as? Int ?? 0, transport: prop("Transport") as? String ?? "",
            isMouse: mouseUsage || lower.contains("mouse"),
            isTrackpad: lower.contains("trackpad") || lower.contains("touchpad"),
            isKeyboard: keyboardUsage, physicalUSBDevice: physicalUSBDevice(for: service))
    }
    private func physicalUSBDevice(for service: io_registry_entry_t) -> UInt64? {
        var entry = service
        guard IOObjectRetain(entry) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(entry) }
        for _ in 0..<32 {
            if IOObjectConformsTo(entry, "IOUSBHostDevice") != 0 {
                var id: UInt64 = 0
                return IORegistryEntryGetRegistryEntryID(entry, &id) == KERN_SUCCESS && id != 0 ? id : nil
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(entry)
            entry = parent
        }
        return nil
    }
    private func isSideButtonSource(_ dev: DeviceInfo?, _ cfg: Config) -> Bool {
        guard cfg.controlArrowSideButtons else { return false }
        if isMouse(dev, cfg) { return true }
        guard let dev, dev.isKeyboard, !dev.isTrackpad, let physical = dev.physicalUSBDevice else { return false }
        return store.connectedDevices.contains { pointer in
            pointer.physicalUSBDevice == physical && pointer.isMouse && !pointer.isTrackpad
                && (cfg.selectedDevice?.matches(pointer) ?? true)
        }
    }
    private func isMouse(_ dev: DeviceInfo?, _ cfg: Config, physicalEvent: Bool = false) -> Bool {
        guard let dev else { return physicalEvent && cfg.selectedDevice == nil }
        guard !dev.isTrackpad, physicalEvent || dev.isMouse else { return false }
        return cfg.selectedDevice?.matches(dev) ?? true
    }
    private func frontBundle() -> String { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancelTilt()
            if let tap, store.axGranted && store.inputGranted { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == kMarker { return pass }
        let keyboard = type == .keyDown || type == .keyUp
        let code = event.getIntegerValueField(keyboard ? .keyboardEventKeycode : .mouseEventButtonNumber)
        let press = Press(keyboard: keyboard, code: code, sender: event.getIntegerValueField(kSenderField))
        if [.keyUp, .otherMouseUp, .leftMouseUp, .rightMouseUp].contains(type), let swallowed = presses.removeValue(forKey: press) {
            return swallowed ? nil : pass
        }
        if [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(type) { return presses[press] == true ? nil : pass }
        if type == .keyDown, let swallowed = presses[press] { return swallowed ? nil : pass }
        if store.recordingShortcut { return pass }
        let cfg = store.config
        let front = frontBundle()
        let targetIsSelf = event.getIntegerValueField(.eventTargetUnixProcessID) == Int64(ProcessInfo.processInfo.processIdentifier)
        let windowNumber = event.getIntegerValueField(.mouseEventWindowUnderMousePointer)
        let ownWindow = windowNumber > 0 && (NSApp?.windows.contains {
            $0.isVisible && Int64($0.windowNumber) == windowNumber
        } ?? false)
        let ownInterface = front == Self.applicationBundleID || targetIsSelf || ownWindow
        let excluded = !cfg.enabled || ownInterface || cfg.excludedApps.contains(front)
        let skipNote = !cfg.enabled ? L("Kapalı", "Disabled") : ownInterface ?
            L("Ayarlar · değiştirilmedi", "Settings · unchanged") : L("Hariç uygulama", "Excluded app")

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let trig = Trigger.mouseButton(code) else {
                if store.logging { store.addLog(.button, L("Mouse tuşu \(code + 1)", "Mouse button \(code + 1)"), device: device(for: event)?.name, result: nil) }
                return pass
            }
            let dev = device(for: event)
            let eligible = isMouse(dev, cfg, physicalEvent: true)
            let a = store.action(for: trig)
            let primaryBypass = trig == .leftClick && event.flags.contains(.maskAlternate)
            let remap = !excluded && eligible && !primaryBypass && a != .passthrough
            presses[press] = remap
            if eligible && (trig != .leftClick || !ownInterface || store.liveTestVisible) {
                store.fired(trig, select: !ownInterface && trig != .leftClick)
            }
            if (trig != .leftClick && trig != .rightClick) || store.logClicks || remap {
                store.addLog(.button, trig.title, device: dev?.name, result: excluded ? skipNote : remap ? a.title : nil)
            }
            if remap { perform(a, trig); return nil }
        case .keyDown:
            guard code == 123 || code == 124 else { return pass }
            let f = event.flags
            let ctrlArrow = f.contains(.maskControl) && !f.contains(.maskCommand) && !f.contains(.maskAlternate) && !f.contains(.maskShift)
            let dev = cfg.controlArrowSideButtons && ctrlArrow ? device(for: event) : nil
            let fromMouse = ctrlArrow && isSideButtonSource(dev, cfg)
            let trig: Trigger = code == 123 ? .sideBack : .sideForward
            let a = store.action(for: trig)
            let preview = fromMouse && ownInterface && store.liveTestVisible && cfg.enabled
            let remap = fromMouse && (!excluded || preview) && a != .passthrough
            presses[press] = remap
            if fromMouse { store.fired(trig, select: !ownInterface) }
            if ctrlArrow {
                let signal = code == 123 ? "Ctrl + ←" : "Ctrl + →"
                store.addLog(fromMouse ? .button : .key, fromMouse ? "\(trig.title) (\(signal))" : signal,
                    device: dev?.name, result: !fromMouse ? L("Klavye · dokunulmadı", "Keyboard · unchanged") :
                        preview ? L("Test · ", "Preview · ") + a.title : excluded ? skipNote : a.title)
            }
            if remap {
                if !preview && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { perform(a, trig) }
                return nil
            }
        case .scrollWheel:
            if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
                if store.showTrackpad { store.addLog(.trackpad, L("Trackpad kaydırma", "Trackpad scroll"), device: nil, result: nil) }
                return pass
            }
            let v = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let h = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            if h != 0 && v == 0 { return handleTilt(h, event, cfg, excluded, skipNote) }
            if v != 0 {
                store.flash("wheel")
                if store.logging && store.logWheel {
                    store.addLog(.scroll, v > 0 ? L("Tekerlek yukarı", "Scroll up") : L("Tekerlek aşağı", "Scroll down"), device: device(for: event)?.name, result: nil)
                }
            }
        default: break
        }
        return pass
    }

    private func handleTilt(_ h: Int64, _ event: CGEvent, _ cfg: Config, _ excluded: Bool, _ skipNote: String) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        let dev = device(for: event)
        guard isMouse(dev, cfg, physicalEvent: true) else { cancelTilt(); return pass }
        let left = h > 0
        store.flash(left ? "tiltLeft" : "tiltRight")
        store.addLog(.tilt, left ? L("Yatay scroll sola", "Horizontal scroll left") : L("Yatay scroll sağa", "Horizontal scroll right"), device: dev?.name, result: excluded ? skipNote : nil)
        if excluded { cancelTilt(); return pass }
        let tapT: Trigger = left ? .tiltLeftTap : .tiltRightTap
        let holdT: Trigger = left ? .tiltLeftHold : .tiltRightHold
        let tapA = store.action(for: tapT), holdA = store.action(for: holdT)
        let now = ProcessInfo.processInfo.systemUptime
        let sender = event.getIntegerValueField(kSenderField)
        if tiltStart != nil && (now - tiltLast >= cfg.tiltGap || left != (tiltDir > 0) || sender != tiltSender) {
            finishTilt()
        }
        if tapA == .passthrough && holdA == .passthrough { return pass }
        if tiltStart == nil {
            tiltStart = now; tiltDir = left ? 1 : -1; tiltAccum = 0; tiltHolding = false
            tiltDevice = dev?.name; tiltSender = sender; tiltFront = frontBundle(); tiltConfig = cfg
            tiltGen += 1
            tiltActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Handling mouse wheel input")
        }
        tiltLast = now
        scheduleTiltCheck(gen: tiltGen)
        if !tiltHolding, let start = tiltStart, now - start >= cfg.tiltHold {
            tiltHolding = true
            store.fired(holdT)
            store.addLog(.tilt, holdT.title, device: dev?.name, result: holdA.title)
            switch holdA {
            case .hScroll: postHScroll(scaled(tiltAccum, cfg.scrollSpeed))
            case .passthrough: postHScroll(tiltAccum)
            case .disabled: break
            default: perform(holdA, holdT)
            }
        }
        if tiltHolding {
            switch holdA {
            case .hScroll: scale(event, cfg.scrollSpeed); return pass
            case .passthrough: return pass
            default: return nil
            }
        }
        let sum = tiltAccum.addingReportingOverflow(h)
        tiltAccum = sum.overflow ? (h > 0 ? Int64(Int32.max) : Int64(Int32.min)) : Int64(Int32(clamping: sum.partialValue))
        return nil
    }
    private func scheduleTiltCheck(gen: Int) {
        guard tiltWork == nil else { return }
        let delay = max(0.001, store.config.tiltGap - (ProcessInfo.processInfo.systemUptime - tiltLast))
        let work = DispatchWorkItem { [weak self] in
            guard let self, gen == self.tiltGen, self.tiltStart != nil else { return }
            self.tiltWork = nil
            if ProcessInfo.processInfo.systemUptime - self.tiltLast < self.store.config.tiltGap {
                self.scheduleTiltCheck(gen: gen)
            } else { self.finishTilt() }
        }
        tiltWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func cancelTilt() {
        tiltWork?.cancel(); tiltWork = nil; tiltGen += 1
        tiltStart = nil; tiltConfig = nil; tiltHolding = false; tiltAccum = 0
        if let tiltActivity { ProcessInfo.processInfo.endActivity(tiltActivity); self.tiltActivity = nil }
    }
    private func finishTilt() {
        defer { cancelTilt() }
        guard tiltStart != nil, !tiltHolding, let cfg = tiltConfig,
              cfg == store.config, cfg.enabled, frontBundle() == tiltFront,
              !cfg.excludedApps.contains(tiltFront), !store.recordingShortcut else { return }
        let t: Trigger = tiltDir > 0 ? .tiltLeftTap : .tiltRightTap
        let a = store.action(for: t)
        store.fired(t)
        store.addLog(.tilt, t.title, device: tiltDevice, result: a.title)
        switch a {
        case .passthrough: postHScroll(tiltAccum)
        case .hScroll: postHScroll(Int64(cfg.tapScrollLines) * t.direction)
        default: perform(a, t)
        }
    }
    private func scaled(_ n: Int64, _ k: Double) -> Int64 {
        let result = (Double(n) * Config.clamp(k, 1...6, 2)).rounded()
        return Int64(min(Double(Int32.max), max(Double(Int32.min), result)))
    }
    private func scale(_ event: CGEvent, _ k: Double) {
        guard k != 1 else { return }
        let lines = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let points = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let fixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: scaled(lines, k))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: scaled(points, k))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixed * Config.clamp(k, 1...6, 2))
    }

    func perform(_ a: Action, _ t: Trigger) {
        let smart = store.config.smartNav && Engine.codeEditors.contains(frontBundle())
        let cmd: CGEventFlags = .maskCommand
        let arrow: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        switch a {
        case .passthrough, .disabled: break
        case .back: smart ? key(27, .maskControl) : key(33, cmd)
        case .forward: smart ? key(27, [.maskControl, .maskShift]) : key(30, cmd)
        case .hScroll: postHScroll(Int64(store.config.tapScrollLines) * t.direction)
        case .tabPrev: key(33, [.maskCommand, .maskShift])
        case .tabNext: key(30, [.maskCommand, .maskShift])
        case .closeTab: key(13, cmd)
        case .reopenTab: key(17, [.maskCommand, .maskShift])
        case .missionControl: missionControl(nil)
        case .appWindows: missionControl("2")
        case .showDesktop: missionControl("1")
        case .spaceLeft: key(123, arrow)
        case .spaceRight: key(124, arrow)
        case .copy: key(8, cmd)
        case .paste: key(9, cmd)
        case .undo: key(6, cmd)
        case .custom:
            if let s = store.config.custom[t.rawValue] { key(CGKeyCode(s.keyCode), CGEventFlags(rawValue: s.flags)) }
        }
    }
    private func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: kMarker)
            e.post(tap: .cghidEventTap)
        }
    }
    private func postHScroll(_ lines: Int64) {
        guard lines != 0, let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2,
            wheel1: 0, wheel2: Int32(clamping: lines), wheel3: 0) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: kMarker)
        e.post(tap: .cghidEventTap)
    }
    private func missionControl(_ arg: String?) {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let conf = NSWorkspace.OpenConfiguration()
        if let arg { conf.arguments = [arg] }
        NSWorkspace.shared.openApplication(at: url, configuration: conf)
    }
    deinit {
        cancelTilt()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        removeTap()
    }
}
