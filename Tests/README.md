# Tests

Run on macOS with Xcode Command Line Tools and Python 3:

```sh
python3 Tests/run-tests.py --json /tmp/splinter-tests.json
python3 -m unittest discover -s Tests -p 'test_*.py'
```

The engine suite covers mappings, input pairing, scrolling, receiver identity,
configuration migration, permissions and timer cleanup. It checks 616 valid
trigger/action combinations. A temporary source copy redirects outgoing events,
Mission Control requests, foreground-app lookup and device fixtures. Preferences
stay in memory; no input is sent to other applications. Replacement boundaries
are asserted by the runner, and production-source hashes are printed.
Hold sequences and flash expiry use controlled monotonic samples so shared CI
scheduling cannot change the simulated deadlines. Timer callbacks still use the native run loop.

Optional checks:

| Command after `python3 Tests/run-tests.py` | Purpose |
| --- | --- |
| `--ui /tmp/splinter-ui` | Render both languages and test local AppKit interactions |
| `--perf --native-front` | Measure engine throughput and process memory |
| `--receiver-probe` | Check a connected composite USB receiver without posting events |
| `--live-probe` | Read current device and permission information |
| `--tap-probe` | Check event-tap lifecycle using existing permissions and disabled mappings |
| `--crash-speed` | Check extreme scroll-speed handling |

UI and native checks need a normal logged-in macOS session. Hardware probes need
the corresponding devices or existing permissions; CI runs only isolated tests.
Performance numbers describe the test process, not end-to-end input latency.

To verify that two different certificate-signed builds retain their permission identity:

```sh
python3 Tests/check-signing.py older.app newer.app
```

This check reads signatures; it does not change macOS permissions.
