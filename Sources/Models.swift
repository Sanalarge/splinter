import AppKit
import CoreGraphics

enum Trigger: Hashable, CaseIterable, Identifiable, RawRepresentable, Codable {
    case sideForward, sideBack, tiltLeftTap, tiltRightTap, tiltLeftHold, tiltRightHold, leftClick, rightClick, middle
    case extraButton(Int)

    static let allCases: [Trigger] = [.sideForward, .sideBack, .tiltLeftTap, .tiltRightTap,
        .tiltLeftHold, .tiltRightHold, .leftClick, .rightClick, .middle] + (6...32).map { .extraButton($0) }
    var id: String { rawValue }
    var rawValue: String {
        switch self {
        case .sideForward: "sideForward"
        case .sideBack: "sideBack"
        case .tiltLeftTap: "tiltLeftTap"
        case .tiltRightTap: "tiltRightTap"
        case .tiltLeftHold: "tiltLeftHold"
        case .tiltRightHold: "tiltRightHold"
        case .leftClick: "leftClick"
        case .rightClick: "rightClick"
        case .middle: "middle"
        case .extraButton(let n): "button\(n)"
        }
    }
    init?(rawValue: String) {
        guard let value = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = value
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let t = Trigger(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown trigger")
        }
        self = t
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(rawValue)
    }
    static func mouseButton(_ index: Int64) -> Trigger? {
        switch index {
        case 0: .leftClick
        case 1: .rightClick
        case 2: .middle
        case 3: .sideBack
        case 4: .sideForward
        case 5...31: .extraButton(Int(index) + 1)
        default: nil
        }
    }
    var buttonIndex: Int64? {
        switch self {
        case .leftClick: 0
        case .rightClick: 1
        case .middle: 2
        case .sideBack: 3
        case .sideForward: 4
        case .extraButton(let n): Int64(n - 1)
        default: nil
        }
    }
    var title: String {
        switch self {
        case .sideForward: L("Yan tuş · İleri", "Side button · Forward")
        case .sideBack: L("Yan tuş · Geri", "Side button · Back")
        case .tiltLeftTap: L("Teker sola · dokunuş", "Tilt left · Tap")
        case .tiltRightTap: L("Teker sağa · dokunuş", "Tilt right · Tap")
        case .tiltLeftHold: L("Teker sola · basılı tut", "Tilt left · Hold")
        case .tiltRightHold: L("Teker sağa · basılı tut", "Tilt right · Hold")
        case .leftClick: L("Sol tık", "Left click")
        case .rightClick: L("Sağ tık", "Right click")
        case .middle: L("Tekere basma", "Middle click")
        case .extraButton(let n): L("Ek tuş \(n)", "Extra button \(n)")
        }
    }
    var signal: String {
        if let n = buttonIndex { return L("Gelen sinyal: mouse tuşu \(n + 1)", "Input: mouse button \(n + 1)") }
        return direction > 0 ? L("Gelen sinyal: yatay kaydırma (sol)", "Input: horizontal scroll (left)") :
            L("Gelen sinyal: yatay kaydırma (sağ)", "Input: horizontal scroll (right)")
    }
    var symbol: String {
        switch self {
        case .sideForward: "arrow.right.circle"
        case .sideBack: "arrow.left.circle"
        case .tiltLeftTap: "chevron.left"
        case .tiltRightTap: "chevron.right"
        case .tiltLeftHold: "chevron.left.2"
        case .tiltRightHold: "chevron.right.2"
        case .leftClick: "cursorarrow.click"
        case .rightClick: "cursorarrow.click.2"
        case .middle: "circle.circle"
        case .extraButton(let n): "\(n).circle"
        }
    }
    var hotspot: String {
        switch self {
        case .tiltLeftTap, .tiltLeftHold: "tiltLeft"
        case .tiltRightTap, .tiltRightHold: "tiltRight"
        case .leftClick: "left"
        case .rightClick: "right"
        default: rawValue
        }
    }
    var isTilt: Bool { direction != 0 }
    var direction: Int64 {
        switch self {
        case .tiltLeftTap, .tiltLeftHold: 1
        case .tiltRightTap, .tiltRightHold: -1
        default: 0
        }
    }
    var defaultAction: Action {
        switch self {
        case .sideBack, .tiltLeftTap: .back
        case .sideForward, .tiltRightTap: .forward
        case .tiltLeftHold, .tiltRightHold: .hScroll
        default: .passthrough
        }
    }
}

enum Action: String, CaseIterable, Identifiable, Codable {
    case passthrough, disabled, back, forward, hScroll, tabPrev, tabNext, closeTab, reopenTab,
         missionControl, appWindows, showDesktop, spaceLeft, spaceRight, copy, paste, undo, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .passthrough: L("Varsayılan", "Pass through")
        case .disabled: L("Devre dışı", "Disable button")
        case .back: L("Geri", "Back")
        case .forward: L("İleri", "Forward")
        case .hScroll: L("Yatay kaydırma", "Horizontal scroll")
        case .tabPrev: L("Önceki sekme", "Previous tab")
        case .tabNext: L("Sonraki sekme", "Next tab")
        case .closeTab: L("Sekmeyi kapat", "Close tab")
        case .reopenTab: L("Kapanan sekmeyi aç", "Reopen closed tab")
        case .missionControl: "Mission Control"
        case .appWindows: L("Uygulama pencereleri", "App windows")
        case .showDesktop: L("Masaüstünü göster", "Show desktop")
        case .spaceLeft: L("Soldaki masaüstü", "Desktop to the left")
        case .spaceRight: L("Sağdaki masaüstü", "Desktop to the right")
        case .copy: L("Kopyala", "Copy")
        case .paste: L("Yapıştır", "Paste")
        case .undo: L("Geri al", "Undo")
        case .custom: L("Özel kısayol…", "Custom shortcut…")
        }
    }
    var symbol: String {
        switch self {
        case .passthrough: "equal.circle"
        case .disabled: "nosign"
        case .back: "arrow.backward"
        case .forward: "arrow.forward"
        case .hScroll: "arrow.left.and.right"
        case .tabPrev: "arrow.left.square"
        case .tabNext: "arrow.right.square"
        case .closeTab: "xmark.square"
        case .reopenTab: "arrow.uturn.backward.square"
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .showDesktop: "menubar.dock.rectangle"
        case .spaceLeft: "rectangle.lefthalf.filled"
        case .spaceRight: "rectangle.righthalf.filled"
        case .copy: "doc.on.doc"
        case .paste: "doc.on.clipboard"
        case .undo: "arrow.uturn.backward"
        case .custom: "keyboard"
        }
    }
    var group: String {
        switch self {
        case .back, .forward, .hScroll, .tabPrev, .tabNext, .closeTab, .reopenTab: "navigation"
        case .missionControl, .appWindows, .showDesktop, .spaceLeft, .spaceRight: "system"
        case .copy, .paste, .undo: "editing"
        default: "other"
        }
    }
    static let groups = ["navigation", "system", "editing", "other"]
    static func groupTitle(_ group: String) -> String {
        switch group {
        case "navigation": L("Gezinme", "Navigation")
        case "system": L("Sistem", "System")
        case "editing": L("Düzen", "Editing")
        default: L("Diğer", "Other")
        }
    }
    static func options(for t: Trigger) -> [Action] {
        t.isTilt ? allCases : allCases.filter { $0 != .hScroll }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var flags: UInt64
    var display: String
}

struct DeviceSelection: Codable, Hashable {
    var vendor: Int
    var product: Int
    var name: String
    func matches(_ d: DeviceInfo) -> Bool {
        d.vendor == vendor && d.product == product && d.name == name
    }
}

struct Config: Codable, Equatable {
    var schemaVersion = 2
    var enabled = true
    var mapping: [String: String] = [:]
    var custom: [String: Shortcut] = [:]
    var tiltHold = 0.35 { didSet { tiltHold = Self.clamp(tiltHold, 0.05...2, 0.35) } }
    var tiltGap = 0.18 { didSet { tiltGap = Self.clamp(tiltGap, 0.02...1, 0.18) } }
    var scrollSpeed = 2.0 { didSet { scrollSpeed = Self.clamp(scrollSpeed, 1...6, 2) } }
    var tapScrollLines = 6 { didSet { tapScrollLines = min(30, max(1, tapScrollLines)) } }
    var selectedDevice: DeviceSelection?
    var controlArrowSideButtons = false
    var smartNav = true
    var excludedApps: [String] = []
    var language: AppLanguage = .system

    static func clamp(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        n.isFinite ? min(range.upperBound, max(range.lowerBound, n)) : fallback
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion, enabled, mapping, custom, tiltHold, tiltGap, scrollSpeed, tapScrollLines,
             selectedDevice, controlArrowSideButtons, smartNav, excludedApps, language
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        mapping = try c.decodeIfPresent([String: String].self, forKey: .mapping) ?? d.mapping
        custom = try c.decodeIfPresent([String: Shortcut].self, forKey: .custom) ?? d.custom
        tiltHold = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .tiltHold) ?? d.tiltHold, 0.05...2, d.tiltHold)
        tiltGap = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .tiltGap) ?? d.tiltGap, 0.02...1, d.tiltGap)
        scrollSpeed = Self.clamp(try c.decodeIfPresent(Double.self, forKey: .scrollSpeed) ?? d.scrollSpeed, 1...6, d.scrollSpeed)
        tapScrollLines = min(30, max(1, try c.decodeIfPresent(Int.self, forKey: .tapScrollLines) ?? d.tapScrollLines))
        selectedDevice = try c.decodeIfPresent(DeviceSelection.self, forKey: .selectedDevice)
        controlArrowSideButtons = try c.decodeIfPresent(Bool.self, forKey: .controlArrowSideButtons) ?? (version < 2)
        smartNav = try c.decodeIfPresent(Bool.self, forKey: .smartNav) ?? d.smartNav
        var seen = Set<String>()
        excludedApps = (try c.decodeIfPresent([String].self, forKey: .excludedApps) ?? []).filter { seen.insert($0).inserted }
        language = (try c.decodeIfPresent(String.self, forKey: .language)).flatMap(AppLanguage.init(rawValue:)) ?? .system
        if version < 2 {
            for (old, new) in [("button4", "sideBack"), ("button5", "sideForward")] {
                if mapping[new] == nil { mapping[new] = mapping[old] }
                if custom[new] == nil { custom[new] = custom[old] }
                mapping.removeValue(forKey: old); custom.removeValue(forKey: old)
            }
        }
    }
}

enum LogKind {
    case key, button, click, scroll, tilt, trackpad
    var symbol: String {
        switch self {
        case .key: "keyboard"
        case .button: "computermouse"
        case .click: "cursorarrow.click"
        case .scroll: "arrow.up.and.down"
        case .tilt: "arrow.left.and.right"
        case .trackpad: "hand.point.up.left"
        }
    }
}
struct LogEntry: Identifiable {
    let id = UUID()
    var time: Date
    let kind: LogKind
    let text: String
    let device: String?
    let result: String?
    var count = 1
}

protocol ConfigPreferences {
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: ConfigPreferences {}

struct PermissionAccess {
    var accessibilityGranted: () -> Bool
    var inputMonitoringGranted: () -> Bool
    var requestAccessibility: () -> Void
    var requestInputMonitoring: () -> Void

    static let system = PermissionAccess(
        accessibilityGranted: { AXIsProcessTrusted() },
        inputMonitoringGranted: { CGPreflightListenEventAccess() },
        requestAccessibility: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        requestInputMonitoring: { _ = CGRequestListenEventAccess() }
    )
}

final class Store: ObservableObject {
    static let shared = Store()
    private static let key = "config.v1"
    private static let permissionRequestKey = "permissions.initial-request.v1"
    private let preferences: ConfigPreferences
    private let permissions: PermissionAccess
    @Published var config: Config { didSet {
        L10n.language = config.language
        if config != oldValue { save() }
    } }
    @Published var log: [LogEntry] = []
    @Published var active: Set<String> = []
    @Published var selected: Trigger? = .sideBack
    @Published var selectionReveal = 0
    @Published var tapRunning = false
    @Published var axGranted = false
    @Published var inputGranted = false
    @Published var seenDevices: [DeviceInfo] = []
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var showTrackpad = false
    @Published var logClicks = true
    @Published var logWheel = true
    @Published var mouseName: String?
    @Published var mouseTransport: String?
    @Published var logPaused = false
    @Published var recordingShortcut = false
    @Published var observedButtons: Set<Trigger> = []
    var logging = false
    var liveTestVisible = false
    private var logGeneration = 0
    private var pendingFlashes: Set<String> = []
    private var flashDeadlines: [String: TimeInterval] = [:]
    private var flashWork: DispatchWorkItem?
    private var flashScheduled = false

    static let logTimeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()
    init(preferences: ConfigPreferences = UserDefaults.standard, migrateLegacy: Bool = true,
         permissions: PermissionAccess = .system) {
        self.preferences = preferences
        self.permissions = permissions
        let legacy = migrateLegacy ? UserDefaults(suiteName: "com.local.mouseremap")?.data(forKey: Store.key) : nil
        if let data = preferences.data(forKey: Store.key) ?? legacy,
           let c = try? JSONDecoder().decode(Config.self, from: data) { config = c }
        else { config = Config() }
        L10n.language = config.language
    }
    private func save() {
        if let data = try? JSONEncoder().encode(config) { preferences.set(data, forKey: Store.key) }
    }
    func action(for t: Trigger) -> Action {
        config.mapping[t.rawValue].flatMap(Action.init(rawValue:)) ?? t.defaultAction
    }
    func setAction(_ a: Action, for t: Trigger) { config.mapping[t.rawValue] = a.rawValue }
    func resetDefaults() { config.mapping = [:]; config.custom = [:] }

    func flash(_ key: String) {
        pendingFlashes.insert(key)
        guard !flashScheduled else { return }
        flashScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushFlashes() }
    }
    private func flushFlashes() {
        flashScheduled = false
        let now = ProcessInfo.processInfo.systemUptime
        for key in pendingFlashes { flashDeadlines[key] = now + 0.35 }
        let next = active.union(pendingFlashes)
        pendingFlashes.removeAll(keepingCapacity: true)
        if active != next { active = next }
        scheduleFlashExpiry()
    }
    private func scheduleFlashExpiry() {
        guard flashWork == nil, let deadline = flashDeadlines.values.min() else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.flashWork = nil
            let now = ProcessInfo.processInfo.systemUptime
            self.flashDeadlines = self.flashDeadlines.filter { $0.value > now }
            let next = Set(self.flashDeadlines.keys)
            if self.active != next { self.active = next }
            self.scheduleFlashExpiry()
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, deadline - ProcessInfo.processInfo.systemUptime), execute: work)
    }
    func selectTrigger(_ t: Trigger, reveal: Bool = false) {
        if selected != t { selected = t }
        if reveal { selectionReveal &+= 1 }
    }
    func fired(_ t: Trigger, select: Bool = true) {
        flash(t.hotspot)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if case .extraButton = t, !self.observedButtons.contains(t) { self.observedButtons.insert(t) }
            if select { self.selectTrigger(t) }
        }
    }
    var connectionText: String {
        if config.selectedDevice == nil, connectedDevices.count > 1 {
            return L("\(connectedDevices.count) mouse bağlı", "\(connectedDevices.count) mice connected")
        }
        guard let t = mouseTransport?.lowercased() else { return L("Mouse bağla veya bir tuşa bas", "Connect a mouse or press a button") }
        if t.contains("bluetooth") { return L("Bluetooth ile bağlı", "Connected via Bluetooth") }
        if t.contains("usb") { return L("USB ile bağlı", "Connected via USB") }
        return L("Bağlı", "Connected")
    }
    func clearLog() { logGeneration += 1; log.removeAll() }
    func addLog(_ kind: LogKind, _ text: String, device: String?, result: String?) {
        guard logging else { return }
        let generation = logGeneration
        let timestamp = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.logGeneration, self.logging else { return }
            self.appendLog(kind, text, device: device, result: result, at: timestamp)
        }
    }
    private func appendLog(_ kind: LogKind, _ text: String, device: String?, result: String?, at now: Date) {
        if var first = log.first, first.text == text, first.result == result,
           first.device == device, first.kind == kind, now.timeIntervalSince(first.time) < 1 {
            first.count += 1; first.time = now; log[0] = first; return
        }
        log.insert(LogEntry(time: now, kind: kind, text: text, device: device, result: result), at: 0)
        if log.count > 400 { log.removeLast(log.count - 400) }
    }
    func copyLog() {
        let text = log.reversed().map { e in
            "\(Store.logTimeFormat.string(from: e.time))  \(e.text)\(e.count > 1 ? " ×\(e.count)" : "")  [\(e.device ?? "-")]  \(e.result.map { "→ \($0)" } ?? "")"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
    }
    func refreshPermissions() {
        let ax = permissions.accessibilityGranted(), im = permissions.inputMonitoringGranted()
        if ax != axGranted { axGranted = ax }
        if im != inputGranted { inputGranted = im }
    }
    func requestPermissionsAtLaunch() {
        guard preferences.data(forKey: Self.permissionRequestKey) == nil else {
            refreshPermissions()
            return
        }
        requestPermissions()
    }
    func requestPermissions() {
        preferences.set(Data([1]), forKey: Self.permissionRequestKey)
        refreshPermissions()
        if !axGranted { permissions.requestAccessibility() }
        if !inputGranted { permissions.requestInputMonitoring() }
        refreshPermissions()
    }
    deinit { flashWork?.cancel() }
}
