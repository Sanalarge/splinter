#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=false
UNIVERSAL=false
ADHOC=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --universal) UNIVERSAL=true ;;
    --adhoc) ADHOC=true ;;
    *) print -u2 "Usage: ./build.sh [--install] [--universal] [--adhoc]"; exit 2 ;;
  esac
done

if $ADHOC && $INSTALL; then
  print -u2 "Refusing ad-hoc installation: rebuilding changes its macOS permission identity."
  exit 2
fi
if ! $ADHOC && [[ "${SPLINTER_SIGNING_IDENTITY:-}" == "-" ]]; then
  print -u2 "Ad-hoc signing changes permission identity. Use the stable default signer; --adhoc is for disposable previews only."
  exit 2
fi
if ! $ADHOC; then
  EXPECTED_CERT="${SPLINTER_SIGNING_CERT_SHA1:-}"
  if [[ -z "$EXPECTED_CERT" && -f signing/identity.sha1 ]]; then
    EXPECTED_CERT="$(<signing/identity.sha1)"
  fi
  if [[ ${#EXPECTED_CERT} -ne 40 || "$EXPECTED_CERT" == *[^0-9a-fA-F]* ]]; then
    print -u2 "Set SPLINTER_SIGNING_CERT_SHA1 to your certificate fingerprint, or use --adhoc for a development build."
    exit 2
  fi
fi

mkdir -p build
STAGING_DIR="$(mktemp -d "$PWD/build/.splinter.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/Splinter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
CACHE_DIR="${TMPDIR:-/tmp}/splinter-swift-module-cache"
if $UNIVERSAL; then
  for arch in arm64 x86_64; do
    swiftc -parse-as-library -swift-version 5 -O -warnings-as-errors -module-cache-path "$CACHE_DIR" \
      -target "$arch-apple-macos14.0" Sources/*.swift -o "$STAGING_DIR/Splinter-$arch"
  done
  lipo -create "$STAGING_DIR/Splinter-arm64" "$STAGING_DIR/Splinter-x86_64" -output "$APP/Contents/MacOS/Splinter"
else
  swiftc -parse-as-library -swift-version 5 -O -warnings-as-errors -module-cache-path "$CACHE_DIR" \
    -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$APP/Contents/MacOS/Splinter"
fi
cp Info.plist "$APP/Contents/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
if [[ -f AppIcon.icns ]]; then cp AppIcon.icns "$APP/Contents/Resources/"; fi
if [[ -n "${SPLINTER_VERSION:-}" ]]; then
  if [[ ! "$SPLINTER_VERSION" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]]; then
    print -u2 "Invalid release version."
    exit 2
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SPLINTER_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${SPLINTER_BUILD_NUMBER:-}" ]]; then
  if [[ ! "$SPLINTER_BUILD_NUMBER" =~ '^[1-9][0-9]*$' ]]; then
    print -u2 "Invalid build number."
    exit 2
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SPLINTER_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if $ADHOC; then
  print -u2 "Preview build: ad-hoc signing does not preserve privacy permissions across changes."
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP"
else
  IDENTITY="${SPLINTER_SIGNING_IDENTITY:-$EXPECTED_CERT}"
  KC="${SPLINTER_SIGNING_KEYCHAIN:-$PWD/signing/dev.keychain-db}"
  SIGN_ARGS=(--force --sign "$IDENTITY")
  if [[ -n "${SPLINTER_SIGNING_KEYCHAIN:-}" || ( -z "${SPLINTER_SIGNING_IDENTITY:-}" && -f "$KC" ) ]]; then
    SIGN_ARGS+=(--keychain "$KC")
  fi
  if ! codesign "${SIGN_ARGS[@]}" "$APP"; then
    print -u2 "Stable signing failed. Unlock the signing keychain in Keychain Access and retry; the existing build was kept."
    exit 1
  fi
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
  REQUIREMENT="=identifier \"$BUNDLE_ID\" and certificate leaf = H\"$EXPECTED_CERT\""
  codesign --verify --deep --strict --test-requirement "$REQUIREMENT" "$APP"
  print "Verified stable signing identity: $EXPECTED_CERT"
fi
rm -rf build/Splinter.app
mv "$APP" build/Splinter.app
print "Built: $PWD/build/Splinter.app"
if $INSTALL; then
  mkdir -p "$HOME/Applications"
  ditto build/Splinter.app "$HOME/Applications/Splinter.app"
  print "Installed: $HOME/Applications/Splinter.app"
fi
