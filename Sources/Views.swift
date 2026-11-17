import SwiftUI
import ServiceManagement

enum AppTypography {
    static let title = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 13)
    static let control = Font.system(size: 13, weight: .medium)
    static let section = Font.system(size: 12, weight: .semibold)
    static let caption = Font.system(size: 12)
}

enum Page: String, CaseIterable, Identifiable {
    case buttons, test, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .buttons: L("Tuş Atamaları", "Button Mapping"); case .test: L("Canlı Test", "Live Test"); case .settings: L("Ayarlar", "Settings") }
    }
    var symbol: String {
        switch self { case .buttons: "computermouse"; case .test: "waveform.path.ecg"; case .settings: "gearshape" }
    }
}

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var page: Page = .buttons

    var body: some View {
        NavigationSplitView {
            Sidebar(page: $page)
                .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 250)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                PageHeader(page: page)
                Divider()
                if !store.tapRunning || !store.axGranted || !store.inputGranted { PermissionBanner() }
                switch page {
                case .buttons: ButtonsView()
                case .test: LiveTestView()
                case .settings: SettingsView()
                }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 1040, minHeight: 660)
        .font(AppTypography.body)
        .environment(\.locale, store.config.language.locale)
        .id(store.config.language)
        .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}

struct Sidebar: View {
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Splinter")
                    .font(AppTypography.title)
            }
            .padding(.horizontal, 18).frame(height: 64).padding(.top, 8).padding(.bottom, 12)

            VStack(spacing: 2) {
                ForEach(Page.allCases) { p in
                    SidebarRow(page: p, selected: p == page) { page = p }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
            StatusCard().padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}

struct SidebarRow: View {
    let page: Page
    let selected: Bool
    let tap: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(AppTypography.control).frame(width: 18)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(page.title).font(AppTypography.body)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(hover ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hover = $0 }
    }
}

struct PageHeader: View {
    @EnvironmentObject var store: Store
    let page: Page

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(page.title).font(AppTypography.title)
            Spacer(minLength: 12).background(WindowDragArea())
            switch page {
            case .buttons:
                HeaderButton(symbol: "arrow.counterclockwise", title: L("Sıfırla", "Reset"), help: L("Tüm atamaları varsayılana döndür", "Reset all button assignments")) {
                    withAnimation { store.resetDefaults() }
                }
            case .test:
                HeaderButton(symbol: store.logPaused ? "play.fill" : "pause.fill",
                             title: store.logPaused ? L("Devam", "Resume") : L("Duraklat", "Pause"),
                             help: store.logPaused ? L("Kayda devam et", "Resume recording") : L("Kaydı duraklat", "Pause recording")) {
                    store.logPaused.toggle(); store.logging = !store.logPaused
                }
                Menu {
                    Section(L("Listede göster", "Show in log")) {
                        Toggle(L("Sol / sağ tıklamalar", "Left / right clicks"), isOn: $store.logClicks)
                        Toggle(L("Tekerlek kaydırma", "Wheel scrolling"), isOn: $store.logWheel)
                        Toggle(L("Trackpad hareketleri", "Trackpad gestures"), isOn: $store.showTrackpad)
                    }
                } label: {
                    HeaderButtonLabel(symbol: "line.3.horizontal.decrease", title: L("Filtre", "Filter"), hover: false)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(L("Listede hangi olayların görüneceğini seç", "Choose which events appear in the log"))
                HeaderButton(symbol: "doc.on.doc", title: nil, help: L("Kaydı panoya kopyala", "Copy log to clipboard")) { store.copyLog() }
                    .disabled(store.log.isEmpty)
                HeaderButton(symbol: "trash", title: nil, help: L("Kaydı temizle", "Clear log")) { store.clearLog() }
                    .disabled(store.log.isEmpty)
            case .settings:
                EmptyView()
            }
        }
        .padding(.horizontal, 24).frame(height: 64).padding(.top, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeaderButtonLabel: View {
    let symbol: String
    let title: String?
    let hover: Bool
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(AppTypography.control)
            if let title { Text(title).font(AppTypography.control) }
        }
        .padding(.horizontal, title == nil ? 0 : 10)
        .frame(minWidth: 28, minHeight: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(hover && enabled ? 0.10 : 0.05)))
        .foregroundStyle(enabled ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.4))
        .contentShape(Rectangle())
    }
}

struct HeaderButton: View {
    let symbol: String
    let title: String?
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) { HeaderButtonLabel(symbol: symbol, title: title, hover: hover) }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .onHover { hover = $0 }
            .help(help)
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct PillToggle: View {
    @Binding var isOn: Bool
    var tint: Color = .accentColor
    var body: some View {
        Capsule()
            .fill(isOn ? tint : Color.primary.opacity(0.15))
            .frame(width: 30, height: 18)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
            .onTapGesture { isOn.toggle() }
    }
}

struct StatusCard: View {
    @EnvironmentObject var store: Store
    @State private var hover = false

    var body: some View {
        let running = store.tapRunning
        let on = running && store.config.enabled
        let tint: Color = !running ? .orange : (on ? .accentColor : .secondary)
        HStack(spacing: 10) {
            Image(systemName: running ? "computermouse.fill" : "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on ? Color.white : tint)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(on ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14))))
            VStack(alignment: .leading, spacing: 1) {
                Text(!running ? L("İzin gerekli", "Permission required") : (on ? L("Aktif", "Active") : L("Duraklatıldı", "Paused")))
                    .font(AppTypography.control)
                Text(store.connectionText)
                    .font(AppTypography.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if running { PillToggle(isOn: $store.config.enabled) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(hover ? 0.07 : 0.045)))
        .onHover { hover = $0 }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("İzin gerekli", "Permission required")).font(.headline)
                Text(L("Tuşları yakalamak için Erişilebilirlik ve Girdi İzleme izinlerini \"Splinter\" için açın.", "Allow Accessibility and Input Monitoring for Splinter to remap mouse buttons."))
                    .font(AppTypography.body).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("İzin iste", "Request access")) { store.requestPermissions() }
                .buttonStyle(.borderedProminent)
            Button(L("Erişilebilirlik", "Accessibility")) { openPrivacy("Privacy_Accessibility") }
            Button(L("Girdi İzleme", "Input Monitoring")) { openPrivacy("Privacy_ListenEvent") }
        }
        .padding(14)
        .background(Color.orange.opacity(0.12))
    }
}

func openPrivacy(_ anchor: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
        NSWorkspace.shared.open(url)
    }
}

struct MouseShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x + w * 0.5, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.45),
                   control1: CGPoint(x: x + w * 0.9, y: y), control2: CGPoint(x: x + w, y: y + h * 0.2))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h),
                   control1: CGPoint(x: x + w, y: y + h * 0.82), control2: CGPoint(x: x + w * 0.8, y: y + h))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.45),
                   control1: CGPoint(x: x + w * 0.2, y: y + h), control2: CGPoint(x: x, y: y + h * 0.82))
        p.addCurve(to: CGPoint(x: x + w * 0.5, y: y),
                   control1: CGPoint(x: x, y: y + h * 0.2), control2: CGPoint(x: x + w * 0.1, y: y))
        p.closeSubpath()
        return p
    }
}

struct RightMouseButtonShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        p.move(to: CGPoint(x: x + w * 0.5, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.38),
                   control1: CGPoint(x: x + w * 0.9, y: y), control2: CGPoint(x: x + w, y: y + h * 0.17))
        p.addQuadCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.425),
                      control: CGPoint(x: x + w * 0.75, y: y + h * 0.425))
        p.closeSubpath()
        return p
    }
}

struct LeftMouseButtonShape: Shape {
    func path(in r: CGRect) -> Path {
        let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: r.minX + r.maxX, ty: 0)
        return RightMouseButtonShape().path(in: r).applying(mirror)
    }
}

struct MouseIllustration: View {
    @EnvironmentObject var store: Store
    var interactive = true
    private let w: CGFloat = 170, h: CGFloat = 275, pad: CGFloat = 60, oy: CGFloat = 14

    private func lit(_ k: String) -> Bool { store.active.contains(k) }
    private func sel(_ ts: [Trigger]) -> Bool { interactive && ts.contains { $0 == store.selected } }
    private func pick(_ t: Trigger) { if interactive { store.selectTrigger(t, reveal: true) } }

    var body: some View {
        let ox = pad
        ZStack {
            ZStack {
                MouseShape().fill(LinearGradient(colors: [Color(white: 0.27), Color(white: 0.09)],
                                                 startPoint: .top, endPoint: .bottom))
                Ellipse().fill(Color.white.opacity(0.06)).frame(width: w * 0.8, height: h * 0.35)
                    .position(x: w / 2, y: h * 0.12)
                leftClickArea
                rightClickArea
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h * 0.40))
                    p.move(to: CGPoint(x: 0, y: h * 0.38))
                    p.addQuadCurve(to: CGPoint(x: w, y: h * 0.38), control: CGPoint(x: w / 2, y: h * 0.47))
                }
                .stroke(Color.black.opacity(0.6), lineWidth: 1.5)

            }
            .frame(width: w, height: h)
            .clipShape(MouseShape())
            .overlay(MouseShape().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            .position(x: ox + w / 2, y: oy + h / 2)

            wheel.position(x: ox + w / 2, y: oy + h * 0.19)
            tiltArrow(left: true).position(x: ox + w / 2 - 26, y: oy + h * 0.19)
            tiltArrow(left: false).position(x: ox + w / 2 + 26, y: oy + h * 0.19)
            sideButton(.sideForward).position(x: ox + 1, y: oy + h * 0.42)
            sideButton(.sideBack).position(x: ox + 1, y: oy + h * 0.57)

            caption(L("İleri", "Forward"), lit: lit("sideForward") || sel([.sideForward])).position(x: ox - 30, y: oy + h * 0.42)
            caption(L("Geri", "Back"), lit: lit("sideBack") || sel([.sideBack])).position(x: ox - 30, y: oy + h * 0.57)
        }
        .frame(width: w + pad * 2, height: h + oy * 2)
    }

    private func caption(_ s: String, lit: Bool) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(lit ? Color.accentColor : Color.secondary)
    }

    private var leftClickArea: some View {
        let on = lit("left")
        let selected = sel([.leftClick])
        return Button { pick(.leftClick) } label: {
            LeftMouseButtonShape()
                .fill(Color.accentColor.opacity(on ? 0.30 : selected ? 0.14 : 0.001))
                .overlay(LeftMouseButtonShape().stroke(Color.accentColor.opacity(selected ? 0.7 : 0), lineWidth: 1))
                .contentShape(LeftMouseButtonShape())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .allowsHitTesting(interactive)
        .accessibilityLabel(Trigger.leftClick.title)
        .accessibilityIdentifier("mouse.left")
        .frame(width: w, height: h)
    }

    private var rightClickArea: some View {
        let on = lit("right")
        let selected = sel([.rightClick])
        return Button { pick(.rightClick) } label: {
            RightMouseButtonShape()
                .fill(Color.accentColor.opacity(on ? 0.30 : selected ? 0.14 : 0.001))
                .overlay(RightMouseButtonShape().stroke(Color.accentColor.opacity(selected ? 0.7 : 0), lineWidth: 1))
                .contentShape(RightMouseButtonShape())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .allowsHitTesting(interactive)
        .accessibilityLabel(Trigger.rightClick.title)
        .accessibilityIdentifier("mouse.right")
        .frame(width: w, height: h)
    }

    private var wheel: some View {
        let on = lit("middle") || lit("wheel")
        let s = sel([.middle])
        return RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [Color(white: 0.48), Color(white: 0.2)], startPoint: .leading, endPoint: .trailing))
            .overlay(
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1.5) }
                }
                .padding(.horizontal, 3).padding(.vertical, 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(on || s ? Color.accentColor : Color.black.opacity(0.4), lineWidth: on || s ? 2.5 : 1))
            .shadow(color: on ? Color.accentColor.opacity(0.9) : .clear, radius: 8)
            .frame(width: 18, height: 48)
            .contentShape(Rectangle())
            .onTapGesture { pick(.middle) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Trigger.middle.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pick(.middle) }
            .accessibilityIdentifier("mouse.middle")
    }

    private func tiltArrow(left: Bool) -> some View {
        let ts: [Trigger] = left ? [.tiltLeftTap, .tiltLeftHold] : [.tiltRightTap, .tiltRightHold]
        let on = lit(left ? "tiltLeft" : "tiltRight")
        let s = sel(ts)
        return Image(systemName: left ? "chevron.left" : "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.white.opacity(on || s ? 1 : 0.6))
            .frame(width: 22, height: 22)
            .background(Circle().fill(on ? Color.accentColor : (s ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.1))))
            .contentShape(Circle())
            .onTapGesture { pick(ts[0]) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ts[0].title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pick(ts[0]) }
            .accessibilityIdentifier(left ? "mouse.tilt.left" : "mouse.tilt.right")
    }

    private func sideButton(_ t: Trigger) -> some View {
        let on = lit(t.hotspot)
        let s = sel([t])
        return Capsule()
            .fill(on ? Color.accentColor : (s ? Color.accentColor.opacity(0.7) : Color(white: 0.34)))
            .overlay(Capsule().stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: 10, height: 34)
            .shadow(color: on ? Color.accentColor : .clear, radius: 8)
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture { pick(t) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t.title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pick(t) }
            .accessibilityIdentifier("mouse." + t.rawValue)
    }
}

struct DevicePanel: View {
    @EnvironmentObject var store: Store
    var interactive = true

    var body: some View {
        VStack(spacing: 18) {
            Text(store.config.selectedDevice?.name ?? L("Tüm mouse’lar", "All mice"))
                .font(.system(size: 14, weight: .semibold))
            Text(store.connectionText).font(AppTypography.caption).foregroundStyle(.secondary)
            MouseIllustration(interactive: interactive)
            Text(interactive ? L("Çizimdeki bir tuşa tıkla ya da mouse'ta bas", "Click a button in the illustration or on your mouse") : L("Bastığın tuş çizimde yanar", "Press a mouse button to highlight it"))
                .font(AppTypography.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center).padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RadialGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                           center: .center, startRadius: 10, endRadius: 260)
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ButtonsView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            DevicePanel().frame(width: 310)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        section(L("Yan tuşlar", "Side buttons"), [.sideForward, .sideBack])
                        section(L("Teker eğme", "Wheel tilt"), [.tiltLeftTap, .tiltRightTap, .tiltLeftHold, .tiltRightHold])
                        section(L("Ana tuşlar", "Primary buttons"), [.leftClick, .rightClick, .middle])
                        if store.action(for: .leftClick) != .passthrough {
                            Text(L("Normal sol tık için ⌥ Option tuşunu basılı tutabilirsin. Ayar penceresindeki tıklamalar her zaman normal çalışır.", "Hold ⌥ Option for a normal left click. Clicks in Settings always work normally."))
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Ek tuşlar", "Extra buttons")).font(AppTypography.section).foregroundStyle(.secondary)
                            if !extraTriggers.isEmpty { rows(extraTriggers) }
                            Menu {
                                ForEach(Trigger.allCases.filter { if case .extraButton = $0 { return !extraTriggers.contains($0) }; return false }) { t in
                                    Button(t.title) { store.observedButtons.insert(t); store.selectTrigger(t, reveal: true) }
                                }
                            } label: { Label(L("Tuş ekle", "Add button"), systemImage: "plus.circle") }
                            .font(AppTypography.body).menuStyle(.borderlessButton).fixedSize()
                            Text(L("Mouse'undaki ek bir tuşa bastığında burada görünür. İstersen numarasını elle de seçebilirsin.", "Press an extra mouse button to show it here, or choose its number manually."))
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(22)
                }
                .onChange(of: store.selectionReveal) { _, _ in
                    guard let trigger = store.selected else { return }
                    DispatchQueue.main.async {
                        withTransaction(Transaction(animation: nil)) { proxy.scrollTo(trigger, anchor: .center) }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .font(AppTypography.body)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { store.liveTestVisible = false }
    }
    private var extraTriggers: [Trigger] {
        Trigger.allCases.filter { t in
            guard case .extraButton = t else { return false }
            return store.observedButtons.contains(t) || store.config.mapping[t.rawValue] != nil
        }
    }
    private func section(_ title: String, _ triggers: [Trigger]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(AppTypography.section).foregroundStyle(.secondary)
            rows(triggers)
        }
    }
    private func rows(_ triggers: [Trigger]) -> some View {
        VStack(spacing: 0) {
            ForEach(triggers) { t in
                if t != triggers.first { Divider().padding(.horizontal, 14) }
                TriggerRow(trigger: t).id(t)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 1))
    }
}

struct TriggerRow: View {
    let trigger: Trigger
    @EnvironmentObject var store: Store

    var body: some View {
        let selected = store.selected == trigger
        let lit = store.active.contains(trigger.hotspot)
        HStack(spacing: 12) {
            Button { store.selectTrigger(trigger) } label: {
                HStack(spacing: 10) {
                    Image(systemName: trigger.symbol)
                        .font(AppTypography.control)
                        .foregroundStyle(lit ? Color.white : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(lit ? Color.accentColor : Color.accentColor.opacity(0.10)))
                    Text(trigger.title).font(AppTypography.body).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusEffectDisabled()
            .foregroundStyle(.primary)
            .help(trigger.signal)
            .accessibilityIdentifier("trigger." + trigger.rawValue)
            if store.action(for: trigger) == .custom { ShortcutRecorder(trigger: trigger) }
            ActionPicker(trigger: trigger)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 50)
        .background(selected ? Color.accentColor.opacity(0.055) : .clear)
    }
}

struct ActionPicker: View {
    let trigger: Trigger
    @EnvironmentObject var store: Store

    var body: some View {
        let current = store.action(for: trigger)
        Menu {
            ForEach(Action.groups, id: \.self) { group in
                Section(Action.groupTitle(group)) {
                    ForEach(Action.options(for: trigger).filter { $0.group == group }) { action in
                        Button {
                            store.setAction(action, for: trigger)
                            store.selectTrigger(trigger)
                        } label: {
                            if action == current { Label(action.title, systemImage: "checkmark") }
                            else { Label(action.title, systemImage: action.symbol) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(current.title).font(AppTypography.body).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(width: 166, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.button).menuIndicator(.hidden)
        .buttonStyle(.plain).focusEffectDisabled()
        .help(current.title)
        .accessibilityLabel(trigger.title)
        .accessibilityValue(current.title)
        .accessibilityIdentifier("action." + trigger.rawValue)
        .fixedSize()
    }
}

final class ShortcutCapture: ObservableObject {
    private static weak var active: ShortcutCapture?
    @Published var recording = false
    private var monitor: Any?

    func start(_ onRecord: @escaping (NSEvent) -> Void) {
        Self.active?.stop()
        Self.active = self
        recording = true
        Store.shared.recordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode != 53 { onRecord(e) }
            self.stop()
            return nil
        }
        if monitor == nil { stop() }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false }
        if Self.active === self { Self.active = nil; Store.shared.recordingShortcut = false }
    }
    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if recording { Store.shared.recordingShortcut = false }
    }
}

struct ShortcutRecorder: View {
    let trigger: Trigger
    @EnvironmentObject var store: Store
    @StateObject private var capture = ShortcutCapture()

    var body: some View {
        Button {
            if capture.recording { capture.stop() }
            else {
                capture.start { [store, trigger] e in
                    let mods = e.modifierFlags.intersection([.command, .option, .control, .shift, .function, .numericPad])
                    store.config.custom[trigger.rawValue] = Shortcut(keyCode: e.keyCode, flags: UInt64(mods.rawValue), display: Self.describe(e, mods))
                }
            }
        } label: {
            Text(capture.recording ? L("Tuşlara bas…", "Press keys…") : (store.config.custom[trigger.rawValue]?.display ?? L("Kısayol kaydet", "Record shortcut")))
                .font(AppTypography.control)
                .lineLimit(1)
                .foregroundStyle(capture.recording ? Color.orange : Color.primary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(capture.recording ? Color.orange : Color.primary.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1, dash: capture.recording ? [3, 3] : [])))
        }
        .buttonStyle(.plain)
        .help(L("Kaydetmek için tıkla; iptal etmek için Esc tuşuna bas.", "Click to record; press Esc to cancel."))
        .onDisappear { capture.stop() }
    }
    private static func describe(_ e: NSEvent, _ m: NSEvent.ModifierFlags) -> String {
        var s = ""
        if m.contains(.function) { s += "fn " }
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        let names: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 36: "↩", 48: "⇥", 49: L("Boşluk", "Space"),
            51: "⌫", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        s += names[e.keyCode] ?? (e.charactersIgnoringModifiers?.uppercased() ?? "?")
        return s
    }
}

struct LiveTestView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            DevicePanel(interactive: false).frame(width: 330)
            Divider()
            Group {
                if store.log.isEmpty {
                    ContentUnavailableView {
                        Label(store.logPaused ? L("Kayıt duraklatıldı", "Recording paused") : L("Mouse tuşlarına bas", "Press a mouse button"),
                              systemImage: store.logPaused ? "pause.circle" : "computermouse")
                    } description: {
                        Text(L("Gelen her sinyal, hangi cihazdan geldiği ve neye çevrildiği burada listelenir.", "See incoming events, their source device and the action assigned to them."))
                    }
                } else {
                    List(store.log) { e in LogRow(entry: e, fmt: Store.logTimeFormat) }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { store.liveTestVisible = true; store.logging = !store.logPaused }
        .onDisappear { store.liveTestVisible = false; store.logging = false }
    }
}

struct LogRow: View {
    let entry: LogEntry
    let fmt: DateFormatter
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(entry.result != nil ? Color.accentColor : Color.secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(entry.result != nil ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.text).font(AppTypography.body)
                    if entry.count > 1 {
                        Text("×\(entry.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                Text("\(fmt.string(from: entry.time))\(entry.device.map { "  ·  \($0)" } ?? "")")
                    .font(AppTypography.caption.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if let r = entry.result {
                Text(r).font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.13)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 3)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var loginError: String?
    @State private var loginStatus = SMAppService.mainApp.status

    private var loginBinding: Binding<Bool> {
        Binding(get: { loginStatus == .enabled || loginStatus == .requiresApproval }, set: { on in
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch { loginError = error.localizedDescription }
            loginStatus = SMAppService.mainApp.status
        })
    }
    private var devices: [DeviceInfo] {
        var seen = Set<DeviceSelection>()
        return (store.connectedDevices + store.seenDevices).filter {
            $0.isMouse && !$0.isTrackpad && seen.insert($0.selection).inserted
        }
    }
    var body: some View {
        Form {
            Section(L("Genel", "General")) {
                Picker(L("Dil", "Language"), selection: $store.config.language) {
                    ForEach(AppLanguage.allCases) { language in Text(language.title).tag(language) }
                }
                Toggle(L("Eşlemeleri etkinleştir", "Enable remapping"), isOn: $store.config.enabled)
                Toggle(L("Mac açılınca başlat", "Launch at login"), isOn: loginBinding)
                if let loginError { Text(loginError).font(AppTypography.caption).foregroundStyle(.red) }
                if loginStatus == .requiresApproval {
                    Button(L("Başlangıç iznini Sistem Ayarları'nda onayla", "Approve launch at login in System Settings")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                Toggle(isOn: $store.config.smartNav) {
                    Text(L("Kod editörlerinde akıllı geri/ileri", "Smart navigation in code editors"))
                    Text(L("VS Code, Cursor ve Windsurf'te editörün gezinme kısayollarını kullanır.", "Use editor navigation shortcuts in VS Code, Cursor and Windsurf."))
                }
            }
            Section(L("Mouse seçimi", "Mouse selection")) {
                Picker(L("Eşlemelerin uygulanacağı cihaz", "Apply remapping to"), selection: $store.config.selectedDevice) {
                    Text(L("Tüm mouse’lar", "All mice")).tag(Optional<DeviceSelection>.none)
                    ForEach(devices) { d in Text(d.name).tag(Optional(d.selection)) }
                    if let selected = store.config.selectedDevice, !devices.contains(where: { selected.matches($0) }) {
                        Text(selected.name + L(" · Bağlı değil", " · Not connected")).tag(Optional(selected))
                    }
                }
                .onChange(of: store.config.selectedDevice) { _, _ in Engine.shared.refreshMouseInfo() }
                HStack {
                    Label(store.connectionText, systemImage: "cable.connector")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Yenile", "Refresh")) { Engine.shared.refreshMouseInfo() }
                }
                Text(L("Markadan bağımsız çalışır. Standart yan tuşlar geri/ileri olarak tanınır. Ek tuşları Canlı Test ekranında kontrol edebilirsin.", "Works across brands. Standard side buttons are recognized as Back/Forward. Check extra buttons in Live Test."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                Toggle(isOn: $store.config.controlArrowSideButtons) {
                    Text(L("Ctrl + ok gönderen yan tuşlarla uyumluluk", "Compatibility with side buttons that send Ctrl + arrow"))
                    Text(L("Mouse veya aynı USB alıcısındaki klavye arayüzünü tanır. Diğer cihazlardaki klavye kısayolları korunur.", "Recognize the mouse or its sibling keyboard interface on the same USB receiver. Keyboards on other devices are unchanged."))
                }
                if store.config.controlArrowSideButtons {
                    Text(L("Aynı alıcıyı gerçek bir klavye de kullanıyorsa onun Ctrl + ok kısayolları da çevrilebilir.", "If a real keyboard shares this receiver, its Ctrl + arrow shortcuts may also be remapped."))
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
            }
            Section(L("Teker eğme", "Wheel tilt")) {
                slider(L("Basılı tutma eşiği", "Hold threshold"), $store.config.tiltHold, 0.15...0.8, L("%.2f sn", "%.2f s"),
                    L("Bundan uzun eğme = basılı tutma", "A longer tilt is treated as a hold"))
                slider(L("Eğme bitiş aralığı", "Tilt release interval"), $store.config.tiltGap, 0.08...0.4, L("%.2f sn", "%.2f s"),
                    L("Bu süre sinyal gelmezse eğme bitti sayılır", "A tilt ends after this interval without input"))
                slider(L("Yatay kaydırma hızı", "Horizontal scroll speed"), $store.config.scrollSpeed, 1...6, "%.1f×", nil)
                Stepper(L("Dokunuşta kaydırma: \(store.config.tapScrollLines) satır", "Scroll per tap: \(store.config.tapScrollLines) lines"),
                    value: $store.config.tapScrollLines, in: 1...30)
                Text(L("Yalnızca yatay teker sinyali gönderen mouse'larda kullanılabilir. Trackpad hareketleri değiştirilmez.", "Available on mice that send horizontal wheel input. Trackpad gestures are preserved."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
            Section(L("Hariç tutulan uygulamalar", "Excluded apps")) {
                ForEach(store.config.excludedApps, id: \.self) { id in
                    HStack {
                        AppIcon(bundleID: id)
                        Text(appName(id))
                        Spacer()
                        Button { store.config.excludedApps.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help(L("Listeden çıkar", "Remove from list"))
                    }
                }
                Menu {
                    ForEach(runningApps(), id: \.self) { id in
                        Button(appName(id)) {
                            if !store.config.excludedApps.contains(id) { store.config.excludedApps.append(id) }
                        }
                    }
                } label: { Label(L("Uygulama ekle", "Add app"), systemImage: "plus") }
                .fixedSize()
                Text(L("Bu uygulamalar öndeyken mouse tuşları değiştirilmez (ör. oyunlar).", "Keep original mouse behavior while these apps are in front, such as games."))
                    .font(AppTypography.caption).foregroundStyle(.secondary)
            }
            Section(L("İzinler", "Permissions")) {
                permRow(L("Erişilebilirlik", "Accessibility"), store.axGranted, "Privacy_Accessibility")
                permRow(L("Girdi İzleme", "Input Monitoring"), store.inputGranted, "Privacy_ListenEvent")
                if !store.axGranted || !store.inputGranted {
                    Button(L("İzin iste", "Request access")) { store.requestPermissions() }
                }
            }
        }
        .formStyle(.grouped)
        .font(AppTypography.body)
        .onAppear { store.liveTestVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }
    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>,
                        _ fmt: String, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: fmt, locale: store.config.language.locale, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            if let hint { Text(hint).font(AppTypography.caption).foregroundStyle(.secondary) }
        }
    }
    private func permRow(_ title: String, _ ok: Bool, _ anchor: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok { Button(L("Ayarları aç", "Open settings")) { openPrivacy(anchor) } }
        }
    }
    private func runningApps() -> [String] {
        let ids = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
            .filter { !store.config.excludedApps.contains($0) && $0 != Bundle.main.bundleIdentifier }
        return Array(Set(ids)).sorted { appName($0).localizedCaseInsensitiveCompare(appName($1)) == .orderedAscending }
    }
}

func appName(_ bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
    return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
}

struct AppIcon: View {
    let bundleID: String
    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
        } else {
            Image(systemName: "app").frame(width: 20, height: 20)
        }
    }
}
