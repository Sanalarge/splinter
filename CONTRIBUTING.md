# Contributing

Fork the repository, create a focused branch and open a pull request against
`main`. Include a short explanation of the change and how you tested it.
Use concise English commit subjects. Repository access is not required to contribute.

`main` requires pull requests and passing checks. Only the repository owner
merges changes. Do not include credentials, signing material, generated binaries,
personal event logs or local editor configuration.

## Development

Use macOS 14 or later, Xcode Command Line Tools with Swift 5.9 or later, and Python 3.

```sh
./build.sh --adhoc
python3 Tests/run-tests.py
./cli/build.sh
./cli/mouse-remap --help
```

`./build.sh --adhoc --universal` builds both supported architectures.
Ad-hoc builds are suitable for testing, but macOS permission grants may need
renewing when their contents change. Ad-hoc installation through `--install`
is deliberately disabled.

For stable local builds, supply your own certificate fingerprint and optionally
its keychain. Do not commit either private keys or keychains:

```sh
export SPLINTER_SIGNING_CERT_SHA1="YOUR_40_CHARACTER_CERTIFICATE_SHA1"
export SPLINTER_SIGNING_KEYCHAIN="/path/to/development.keychain-db"
./build.sh --universal
```

`SPLINTER_SIGNING_IDENTITY` optionally overrides the identity name used by
`codesign`; the fingerprint still verifies the result. Existing local
`signing/identity.sha1` and `signing/dev.keychain-db` files are supported and
ignored by Git. Stable signing failures leave the existing build in place.
Close Splinter before using `--install`, which installs to `~/Applications`.

The optional CLI uses the same engine. `--debug` inspects events without
remapping; `--request-permissions` explicitly asks for missing permissions.
CLI and app preferences are separate. Avoid running both remappers together.

## Tests

See [Tests/README.md](Tests/README.md). Pull request checks run the engine suite,
release version tests, both-architecture compilation and CLI compilation.
Physical input, permission dialogs, login items and Intel hardware still need
manual testing for changes affecting those paths.

The app icon can be regenerated with `tools/icon.swift` and Apple's `iconutil`.

## Releases

Each successful push to `main`, including a merged pull request, creates a
universal macOS release with a versioned ZIP, SHA-256 checksums and release notes.
Pull requests and other branches never publish releases. No version-bump commits
are generated.

`VERSION` sets the start of a release line. Its commit publishes that version;
each following first-parent commit increments its patch number. For example,
`1.2.0` becomes `1.2.1` on the next main commit. To start `1.3.0`, change
`VERSION` to `1.3.0` in a pull request. The workflow stamps the app's version and
build number without modifying the repository. Versions already used by another
commit are rejected; rerunning a published release leaves it unchanged.

Official releases currently use ad-hoc signing. Developer ID signing and
notarization require an Apple Developer account and a separate signing setup.

Repository owners can apply the checked-in policy with
`python3 scripts/configure-repository.py --repo Sanalarge/splinter` after the
initial push. It requires repository administration access and does not add
collaborators. Main requires a pull request and successful CI, with no bypass;
the sole maintainer merges PRs without needing a second account to approve them.
Release tags cannot be updated or deleted. External fork workflows require
maintainer approval before running.
