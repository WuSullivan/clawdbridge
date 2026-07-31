#!/usr/bin/env bash
set -euo pipefail

# ClawdBridge — 一键构建脚本
# 用法:
#   ./build.sh --mac       构建 macOS 二进制
#   ./build.sh --android   构建 Android APK
#   ./build.sh --all       构建全部平台
#   ./build.sh             显示帮助

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
MAC_DIR="$ROOT_DIR/mac"
ANDROID_DIR="$ROOT_DIR/android"
IOS_DIR="$ROOT_DIR/ios"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ────────────────────────────────────────────────────────────
# macOS: Swift SPM build → release binary
# ────────────────────────────────────────────────────────────
build_mac() {
    info "Building macOS binary..."

    cd "$MAC_DIR"
    swift build -c release --arch arm64 --arch x86_64

    mkdir -p "$BUILD_DIR/mac"
    local bin_path
    bin_path=$(swift build -c release --show-bin-path)
    cp "$bin_path/clawdbridge" "$BUILD_DIR/mac/"

    # Copy launchd plist
    cp "$MAC_DIR/Resources/clawdbridge.plist" "$BUILD_DIR/mac/"

    info "macOS binary built → $BUILD_DIR/mac/clawdbridge"

    # Show binary info
    file "$BUILD_DIR/mac/clawdbridge"
    ls -lh "$BUILD_DIR/mac/clawdbridge"
}

# ────────────────────────────────────────────────────────────
# Android: 自动下载 JDK17 + Android command line tools → APK
# ────────────────────────────────────────────────────────────
build_android() {
    info "Building Android APK..."

    local ANDROID_SDK_ROOT="$HOME/.clawdbridge-android-sdk"
    local CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
    local JDK17_URL=""
    local JDK17_DIR=""

    # Detect architecture
    local arch
    arch=$(uname -m)
    case "$arch" in
        arm64|aarch64)
            JDK17_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.9_9.tar.gz"
            JDK17_DIR="jdk-17.0.9+9"
            ;;
        x86_64)
            JDK17_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9/OpenJDK17U-jdk_x64_mac_hotspot_17.0.9_9.tar.gz"
            JDK17_DIR="jdk-17.0.9+9"
            ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    # ── Download JDK17 if not present ──
    local JDK_HOME="$HOME/.clawdbridge-jdk/$JDK17_DIR/Contents/Home"
    if [ ! -f "$JDK_HOME/bin/java" ]; then
        info "Downloading JDK 17..."
        mkdir -p "$HOME/.clawdbridge-jdk"
        curl -sL "$JDK17_URL" -o /tmp/jdk17.tar.gz
        tar xzf /tmp/jdk17.tar.gz -C "$HOME/.clawdbridge-jdk"
        rm /tmp/jdk17.tar.gz
        info "JDK 17 installed at $JDK_HOME"
    fi
    export JAVA_HOME="$JDK_HOME"

    # ── Download Android SDK command-line tools if not present ──
    if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
        info "Downloading Android command-line tools..."
        mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
        curl -sL "$CMDLINE_TOOLS_URL" -o /tmp/cmdline-tools.zip
        unzip -qo /tmp/cmdline-tools.zip -d /tmp/android-cmdline
        mv /tmp/android-cmdline/cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
        rm /tmp/cmdline-tools.zip
    fi

    export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"

    # Accept licenses & install SDK components
    info "Installing Android SDK components..."
    yes | "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_SDK_ROOT" \
        "platform-tools" \
        "platforms;android-34" \
        "build-tools;34.0.0" \
        "ndk;25.2.9519653" \
        > /dev/null 2>&1 || true

    # Generate local.properties
    cat > "$ANDROID_DIR/local.properties" <<EOF
sdk.dir=$ANDROID_SDK_ROOT
ndk.dir=$ANDROID_SDK_ROOT/ndk/25.2.9519653
EOF

    # Build APK
    cd "$ANDROID_DIR"

    # Bootstrap Gradle wrapper if needed
    if [ ! -f gradlew ]; then
        info "Bootstrapping Gradle wrapper..."
        gradle wrapper --gradle-version 8.5 > /dev/null 2>&1 || {
            # Manual gradle wrapper setup fallback
            mkdir -p gradle/wrapper
            cat > gradle/wrapper/gradle-wrapper.properties <<GRADLEPROPS
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
GRADLEPROPS
        }
    fi

    ./gradlew assembleRelease

    mkdir -p "$BUILD_DIR/android"
    cp app/build/outputs/apk/release/app-release-unsigned.apk "$BUILD_DIR/android/clawdbridge.apk" 2>/dev/null || \
    cp app/build/outputs/apk/release/app-release.apk "$BUILD_DIR/android/clawdbridge.apk" 2>/dev/null || \
    cp app/build/outputs/apk/debug/app-debug.apk "$BUILD_DIR/android/clawdbridge.apk" 2>/dev/null || true

    info "Android APK built → $BUILD_DIR/android/clawdbridge.apk"
}

# ────────────────────────────────────────────────────────────
# iOS: Xcode archive → unsigned IPA
# ────────────────────────────────────────────────────────────
build_ios() {
    info "Building iOS IPA..."
    warn "iOS build requires Xcode. Skipping unless run on macOS with Xcode installed."

    if ! command -v xcodebuild &> /dev/null; then
        error "Xcode not found — skipping iOS build"
        return 1
    fi

    cd "$IOS_DIR"
    xcodebuild archive \
        -project ClawdBridge.xcodeproj \
        -scheme ClawdBridge \
        -archivePath "$BUILD_DIR/ios/ClawdBridge.xcarchive" \
        -configuration Release \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO

    mkdir -p "$BUILD_DIR/ios"
    # Create IPA from archive
    if [ -d "$BUILD_DIR/ios/ClawdBridge.xcarchive" ]; then
        mkdir -p "$BUILD_DIR/ios/Payload"
        cp -R "$BUILD_DIR/ios/ClawdBridge.xcarchive/Products/Applications/ClawdBridge.app" "$BUILD_DIR/ios/Payload/"
        cd "$BUILD_DIR/ios"
        zip -qr ClawdBridge.ipa Payload
        rm -rf Payload
        info "iOS IPA built → $BUILD_DIR/ios/ClawdBridge.ipa"
    fi
}

# ────────────────────────────────────────────────────────────
# Main
# ────────────────────────────────────────────────────────────
print_usage() {
    echo "ClawdBridge — 一键构建脚本"
    echo ""
    echo "用法:  $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --mac        构建 macOS 二进制"
    echo "  --android    构建 Android APK（自动下载 JDK17 + Android SDK）"
    echo "  --ios        构建 iOS IPA（需要 Xcode）"
    echo "  --all        构建全部平台"
    echo "  --help       显示此帮助"
}

case "${1:-}" in
    --mac)
        build_mac
        ;;
    --android)
        build_android
        ;;
    --ios)
        build_ios
        ;;
    --all)
        build_mac
        build_android
        build_ios
        ;;
    --help|*)
        print_usage
        ;;
esac
