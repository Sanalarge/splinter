import AppKit
import Combine

if CommandLine.arguments.contains("--help") {
    print("Usage: mouse-remap [--debug] [--request-permissions]")
    print("--debug: inspect mouse events without remapping; --request-permissions: show macOS permission prompts")
    exit(0)
}

let debug = CommandLine.arguments.contains("--debug")
_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let store = Store.shared
store.config.enabled = !debug
store.logging = debug
store.showTrackpad = debug
let logSubscription = store.$log.sink { entries in
    guard debug, let e = entries.first else { return }
    print("\(Store.logTimeFormat.string(from: e.time))  \(e.text) [\(e.device ?? "?")] \(e.result ?? "") ×\(e.count)")
    fflush(stdout)
}
store.refreshPermissions()
if !store.axGranted || !store.inputGranted {
    print(L("Erişilebilirlik ve Girdi İzleme izinleri gerekli.", "Accessibility and Input Monitoring permissions are required."))
    if CommandLine.arguments.contains("--request-permissions") { store.requestPermissions() }
    exit(1)
}
Engine.shared.start()
guard store.tapRunning else {
    print(L("Olay izleme başlatılamadı.", "Could not start event monitoring.")); exit(1)
}
let timer = Timer(timeInterval: 2, repeats: true) { _ in Engine.shared.start() }
RunLoop.main.add(timer, forMode: .common)
print(debug ? L("Canlı test · Çıkış: Ctrl+C", "Live test · Exit: Ctrl+C") : L("Mouse eşlemeleri etkin · Çıkış: Ctrl+C", "Mouse remapping enabled · Exit: Ctrl+C"))
fflush(stdout)
RunLoop.main.run()
