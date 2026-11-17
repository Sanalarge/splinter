#!/usr/bin/env python3
from pathlib import Path
import atexit
import hashlib
import json
import subprocess
import shutil
import tempfile
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(tempfile.mkdtemp(prefix="splinter-test-"))
atexit.register(shutil.rmtree, OUT, ignore_errors=True)

def replace_once(source, old, new):
    assert source.count(old) == 1, f"Test seam no longer matches: {old[:100]}"
    return source.replace(old, new, 1)

models = (ROOT / "Sources/Models.swift").read_text()
models = replace_once(models, "static let shared = Store()", "static var shared = Store(preferences: TestPreferences(), migrateLegacy: false)")
(OUT / "Models.swift").write_text(models)
engine = (ROOT / "Sources/Engine.swift").read_text()
engine = replace_once(engine, "let now = ProcessInfo.processInfo.systemUptime", "let now = TestIO.inputTime ?? ProcessInfo.processInfo.systemUptime")
engine = replace_once(engine, "    func device(for event: CGEvent) -> DeviceInfo? {", "    func device(for event: CGEvent) -> DeviceInfo? {\n        if TestIO.overrideDevice { return TestIO.device }")
engine = replace_once(engine, 'NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""', "TestIO.front")
engine = replace_once(engine, ') { [weak self] _ in self?.cancelTilt() }', ') { [weak self] _ in if TestIO.nativeFront { self?.cancelTilt() } }')
assert engine.count("e.post(tap: .cghidEventTap)") == 2
engine = engine.replace("e.post(tap: .cghidEventTap)", "TestIO.record(e)")
engine = replace_once(engine, "NSWorkspace.shared.openApplication(at: url, configuration: conf)", "_ = url; TestIO.missions.append(arg ?? \"overview\")")
engine = replace_once(engine, "    private func lookup(_ id: UInt64) -> DeviceInfo? {", "    private func lookup(_ id: UInt64) -> DeviceInfo? {\n        TestIO.lookups += 1")
engine += "\nextension Engine { var testCacheCount: Int { deviceCache.count }; var testTapPort: mach_port_t { tap.map(CFMachPortGetPort) ?? 0 }; var testTapEnabled: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false } }\n"
(OUT / "Engine.swift").write_text(engine)
print(f"Test directory: {OUT}", flush=True)
print("Production SHA256: " + json.dumps({p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT / "Sources").glob("*.swift"))}), flush=True)
ui_mode = "--ui" in sys.argv
test_sources = [str(ROOT / "Tests/EngineTests.swift")]
if ui_mode:
    test_sources += [str(ROOT / "Sources/Views.swift"), str(ROOT / "Tests/UITests.swift")]
command = ["swiftc", "-swift-version", "5", "-O", "-g", "-module-cache-path", str(OUT / "module-cache"), str(ROOT / "Sources/Localization.swift"), str(OUT / "Models.swift"), str(OUT / "Engine.swift"), *test_sources, "-o", str(OUT / "test")]
if ui_mode:
    command[1:1] = ["-D", "TEST_UI"]
subprocess.run(command, check=True)
result = subprocess.run([str(OUT / "test"), *sys.argv[1:]])
sys.exit(result.returncode)
