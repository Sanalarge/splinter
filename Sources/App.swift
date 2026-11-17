import SwiftUI

@main
struct SplinterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let store = Store.shared

    var body: some Scene {
        Window("Splinter", id: "main") {
            MainView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 700)

        MenuBarExtra {
            MenuBarContent().environmentObject(store)
        } label: {
            MenuBarIcon().environmentObject(store)
        }
    }
}

struct MenuBarIcon: View {
    @EnvironmentObject var store: Store
    var body: some View { Image(systemName: store.config.enabled ? "computermouse.fill" : "computermouse") }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.tapRunning ? L("Splinter çalışıyor", "Splinter is running") : L("İzin bekleniyor", "Waiting for permissions"))
        Toggle(L("Eşlemeler etkin", "Remapping enabled"), isOn: $store.config.enabled)
        Divider()
        Button(L("Ayarları Aç…", "Open Settings…")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button(L("Çık", "Quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.shared.requestPermissionsAtLaunch()
        Engine.shared.start()
        let timer = Timer(timeInterval: 2, repeats: true) { _ in Engine.shared.start() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        Engine.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
