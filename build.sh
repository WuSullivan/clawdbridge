#!/bin/bash
set -euo pipefail
#
# ClawdBridge One-Click Build
# ============================
# cd clawdbridge && ./build.sh
#
# Auto-downloads everything needed. No Android Studio, no Xcode required
# (except for iOS — that needs Xcode no way around it).
#

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "🐾 ClawdBridge Builder"
echo "======================="

# ── Platform Detection ──────────────────────────
BUILD_MAC=true
BUILD_ANDROID=true
BUILD_IOS=false  # needs Xcode, skip by default

for arg in "$@"; do
    case "$arg" in
        --mac)    BUILD_MAC=true; BUILD_ANDROID=false ;;
        --android) BUILD_ANDROID=true; BUILD_MAC=false ;;
        --ios)     BUILD_IOS=true; BUILD_MAC=false; BUILD_ANDROID=false ;;
        --all)    BUILD_MAC=true; BUILD_ANDROID=true; BUILD_IOS=true ;;
    esac
done

# ── Mac ──────────────────────────────────────────
if $BUILD_MAC; then
    echo ""
    echo "--- Mac ---"
    cd "$ROOT"
    swift build -c release 2>&1
    OUT="$ROOT/.build/arm64-apple-macosx/release/ClawdBridge"
    if [ -f "$OUT" ]; then
        ls -lh "$OUT"
        echo "✔ Mac binary ready: $OUT"
    else
        echo "✘ Mac build failed"
    fi
fi

# ── Android ─────────────────────────────────────
if $BUILD_ANDROID; then
    echo ""
    echo "--- Android ---"

    ANDROID_HOME="$ROOT/android/.android-sdk"
    export ANDROID_HOME

    # ── JDK 17 ───────────────────────────────────
    # Check current JDK version
    JDK_VER=$(java -version 2>&1 | head -1 | grep -oE '[0-9]+' | head -1 || echo "0")

    if [ "$JDK_VER" -lt 17 ]; then
        echo "→ JDK $JDK_VER detected. Android needs JDK 17+. Installing Temurin 17…"

        case "$(uname -m)" in
            arm64|aarch64) JDK_ARCH="aarch64" ;;
            *) JDK_ARCH="x64" ;;
        esac

        JDK_URL="https://api.adoptium.net/v3/binary/latest/17/ga/mac/${JDK_ARCH}/jdk/hotspot/normal/eclipse"
        JDK_DIR="$ROOT/android/.jdk17"

        if [ ! -d "$JDK_DIR" ]; then
            mkdir -p "$JDK_DIR"
            echo "→ Downloading JDK 17…"
            curl -sL "$JDK_URL" -o "$ROOT/android/.jdk17.tar.gz"
            tar xzf "$ROOT/android/.jdk17.tar.gz" -C "$JDK_DIR" --strip-components=1
            rm "$ROOT/android/.jdk17.tar.gz"
        fi
        export JAVA_HOME="$JDK_DIR/Contents/Home"
        export PATH="$JAVA_HOME/bin:$PATH"
        echo "✔ JDK 17 ready"
    fi

    # ── Android SDK ──────────────────────────────
    if [ ! -d "$ANDROID_HOME/platforms/android-34" ]; then
        echo "→ Downloading Android SDK (cmdline-tools)…"

        case "$(uname -s)" in
            Darwin*) SDK_OS="mac" ;;
            Linux*) SDK_OS="linux" ;;
        esac
        case "$(uname -m)" in
            arm64|aarch64) SDK_ARCH="arm64" ;;
            *) SDK_ARCH="x64" ;;
        esac

        CMDLINE_ZIP="commandlinetools-${SDK_OS}-11076708_latest.zip"
        SDK_URL="https://dl.google.com/android/repository/${CMDLINE_ZIP}"

        mkdir -p "$ANDROID_HOME/cmdline-tools/latest"
        curl -sL "$SDK_URL" -o "/tmp/$CMDLINE_ZIP"
        unzip -qo "/tmp/$CMDLINE_ZIP" -d /tmp/cmdline-tools-tmp
        mv /tmp/cmdline-tools-tmp/cmdline-tools/* "$ANDROID_HOME/cmdline-tools/latest/"
        rm -rf /tmp/cmdline-tools-tmp "/tmp/$CMDLINE_ZIP"

        echo "→ Installing Android SDK packages…"
        yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" \
            "platforms;android-34" \
            "build-tools;34.0.0" \
            "platform-tools" \
            "extras;android;m2repository" 2>&1 | grep -v "^\[" || true

        echo "✔ Android SDK ready"
    fi

    # ── Build APK ────────────────────────────────
    cd "$ROOT/android"
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses 2>&1 | true

    # Generate gradlew if missing
    if [ ! -f gradle/wrapper/gradle-wrapper.jar ]; then
        echo "→ Bootstrapping Gradle wrapper…"
        mkdir -p gradle/wrapper
        curl -sL "https://raw.githubusercontent.com/gradle/gradle/v8.5.0/gradlew" -o gradlew
        chmod +x gradlew
    fi

    # Download gradle-wrapper.jar and properties if needed
    if [ ! -f gradle/wrapper/gradle-wrapper.jar ]; then
        curl -sL "https://services.gradle.org/distributions/gradle-8.5-bin.zip" -o /tmp/gradle-dist.zip
        # Just get the gradlew boot jar
        echo "→ Gradle wrapper needed. Please ensure gradle/wrapper/gradle-wrapper.jar exists."
    fi

    echo "→ Building APK…"
    ./gradlew assembleRelease 2>&1 || echo "⚠ Android build failed — check Gradle setup"

    APK=$(find app/build/outputs/apk -name "*.apk" 2>/dev/null | head -1)
    if [ -n "$APK" ]; then
        cp "$APK" "$ROOT/dist/clawdbridge.apk"
        echo "✔ APK: $ROOT/dist/clawdbridge.apk"
    fi
fi

# ── iOS ──────────────────────────────────────────
if $BUILD_IOS; then
    echo ""
    echo "--- iOS ---"
    echo "⚠ iOS build requires Xcode."

    if ! command -v xcodebuild &>/dev/null; then
        echo "✘ Xcode not found — skipping iOS"
    else
        echo "→ iOS build stub (needs .xcodeproj generation)"
    fi
fi

# ── Done ─────────────────────────────────────────
echo ""
echo "=== Done ==="
echo "Dist: $ROOT/dist/"
mkdir -p "$ROOT/dist"
ls -lh "$ROOT/dist/" 2>/dev/null || echo "(no dist yet)"
