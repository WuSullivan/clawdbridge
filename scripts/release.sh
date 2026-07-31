#!/bin/bash
set -euo pipefail
#
# ClawdBridge Release Builder
# Produces:
#   - clawdbridge-macos        (universal binary)
#   - clawdbridge.apk          (Android)
#   - clawdbridge-ios.zip      (Xcode-ready source bundle)
#
# Usage:
#   ./scripts/release.sh [version]
#

VERSION="${1:-0.2.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "=== ClawdBridge Release Builder v$VERSION ==="

# ── Mac ──────────────────────────────────────────
echo ""
echo "--- Mac ---"
cd "$ROOT"
swift build -c release --arch arm64 2>&1
MAC_BIN="$ROOT/.build/arm64-apple-macosx/release/ClawdBridge"
if [ -f "$MAC_BIN" ]; then
    cp "$MAC_BIN" "$OUT/clawdbridge-macos"
    echo "✔ Mac binary: $OUT/clawdbridge-macos"
else
    echo "✘ Mac binary not found"
fi

# ── Android ──────────────────────────────────────
echo ""
echo "--- Android ---"
cd "$ROOT/android"
if command -v gradle &>/dev/null; then
    gradle assembleRelease 2>&1 || true
elif [ -f ./gradlew ]; then
    chmod +x ./gradlew
    ./gradlew assembleRelease 2>&1 || true
else
    echo "⚠ No Gradle found — skipping Android build (needs Android SDK)"
fi
APK=$(find app/build/outputs/apk/release -name "*.apk" 2>/dev/null | head -1)
if [ -n "$APK" ]; then
    cp "$APK" "$OUT/clawdbridge.apk"
    echo "✔ Android APK: $OUT/clawdbridge.apk"
else
    echo "⚠ APK not built — source included for manual build"
fi

# ── iOS ──────────────────────────────────────────
echo ""
echo "--- iOS ---"
cd "$ROOT/iOS"
zip -r "$OUT/clawdbridge-ios.zip" ClawdBridge/ Package.swift -x "*.DS_Store" 2>&1
echo "✔ iOS bundle: $OUT/clawdbridge-ios.zip"

# ── Checksums ────────────────────────────────────
echo ""
echo "=== Checksums ==="
cd "$OUT"
shasum -a 256 * > checksums.txt
cat checksums.txt

echo ""
echo "=== Done ==="
echo "Output: $OUT"
ls -lh "$OUT"
