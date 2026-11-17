#!/usr/bin/env python3
"""Read-only check that two different app builds share the same stable identity."""
from pathlib import Path
import json
import re
import subprocess
import sys

def inspect(path):
    path = str(Path(path).resolve())
    result = subprocess.run(["codesign", "-d", "-r-", path], capture_output=True, text=True, check=True)
    output = result.stdout + result.stderr
    match = re.search(r"^designated => (.+)$", output, re.MULTILINE)
    if not match or "certificate" not in match.group(1):
        raise RuntimeError(f"{path} has no certificate-based designated requirement")
    details = subprocess.run(["codesign", "-d", "--verbose=4", path], capture_output=True, text=True, check=True)
    cdhash = re.search(r"^CDHash=(.+)$", details.stdout + details.stderr, re.MULTILINE)
    if not cdhash:
        raise RuntimeError(f"{path} has no code hash")
    return {"path": path, "requirement": match.group(1), "cdhash": cdhash.group(1)}

if len(sys.argv) != 3:
    sys.exit("Usage: python3 Tests/check-signing.py older.app newer.app")
a, b = map(inspect, sys.argv[1:])
assert a["cdhash"] != b["cdhash"], "Use builds with different signed contents"
assert a["requirement"] == b["requirement"], "Builds changed their permission identity"
for app in [a, b]:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--test-requirement",
                    "=" + a["requirement"], app["path"]], check=True)
print(json.dumps({"different_code": True, "same_stable_identity": True,
                  "both_satisfy_original_requirement": True, "builds": [a, b]}, indent=2))
