#!/bin/bash
# ClashMiao - sing-box 核心编译脚本
#
# 依赖:
#   - Go 1.21+
#   - gomobile (go install golang.org/x/mobile/cmd/gomobile@latest)
#   - Android NDK (ANDROID_NDK_HOME)
#   - Xcode (iOS 编译)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CORE_DIR="$SCRIPT_DIR/sing-box"
OUTPUT_DIR="$SCRIPT_DIR/output"

SINGBOX_VERSION="1.11.0"
SINGBOX_REPO="https://github.com/SagerNet/sing-box.git"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_deps() {
    log_info "检查编译依赖..."

    if ! command -v go &> /dev/null; then
        log_error "Go 未安装, 请先安装 Go 1.21+"
        exit 1
    fi

    GO_VERSION=$(go version | grep -oP '\d+\.\d+')
    log_info "Go version: $GO_VERSION"
}

# 克隆 sing-box 源码
clone_source() {
    if [ -d "$CORE_DIR" ]; then
        log_info "sing-box 源码已存在, 跳过克隆"
        return
    fi

    log_info "克隆 sing-box v${SINGBOX_VERSION}..."
    git clone --depth 1 --branch "v${SINGBOX_VERSION}" "$SINGBOX_REPO" "$CORE_DIR"
}

# 编译 iOS
build_ios() {
    log_info "编译 iOS (arm64)..."
    cd "$CORE_DIR"

    gomobile init
    gomobile bind -target ios -o "$OUTPUT_DIR/Libcore.xcframework" \
        -trimpath -ldflags="-s -w" \
        -tags "with_gvisor,with_quic,with_wireguard,with_clash_api" \
        ./mobile

    log_info "iOS 编译完成: $OUTPUT_DIR/Libcore.xcframework"
}

# 编译 Android
build_android() {
    log_info "编译 Android (arm64, arm, x86_64)..."
    cd "$CORE_DIR"

    gomobile init
    gomobile bind -target android -androidapi 21 -o "$OUTPUT_DIR/libcore.aar" \
        -trimpath -ldflags="-s -w" \
        -tags "with_gvisor,with_quic,with_wireguard,with_clash_api" \
        ./mobile

    log_info "Android 编译完成: $OUTPUT_DIR/libcore.aar"
}

# 编译 macOS（universal：x86_64 + arm64）
#
# 必须出 universal：Intel Mac 装了纯 arm64 的包**跑不起来**（Rosetta 只能
# x86→arm，反向不行）。这里以前的实现只编 arm64，但日志写的是
# "arm64, amd64"——日志和实现不符，谁照着这个脚本重建一次 libcore 就会
# 静默丢掉 Intel 支持（当前发布用的 libcore.dylib 实测是 universal，说明
# 它当初不是这个脚本产出的）。
build_macos() {
    log_info "编译 macOS (arm64 + amd64 → universal)..."
    cd "$CORE_DIR"

    local tags="with_gvisor,with_quic,with_wireguard,with_clash_api"
    local arm64_out="$OUTPUT_DIR/libcore-darwin-arm64.dylib"
    local amd64_out="$OUTPUT_DIR/libcore-darwin-amd64.dylib"
    local universal_out="$OUTPUT_DIR/libcore.dylib"

    CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
    go build -buildmode=c-shared -trimpath \
        -ldflags="-s -w" -tags "$tags" \
        -o "$arm64_out" ./cmd/internal/build_shared

    # 从 Apple Silicon 交叉编 darwin/amd64 需要显式给 clang 指定目标三元组，
    # 否则 cgo 会用宿主架构去链接。
    CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
    CGO_CFLAGS="-target x86_64-apple-macos10.15" \
    CGO_LDFLAGS="-target x86_64-apple-macos10.15" \
    go build -buildmode=c-shared -trimpath \
        -ldflags="-s -w" -tags "$tags" \
        -o "$amd64_out" ./cmd/internal/build_shared

    lipo -create "$arm64_out" "$amd64_out" -output "$universal_out"
    rm -f "$arm64_out" "$amd64_out"

    # 校验而不是假设——静默产出单架构正是这里原来的 bug。
    local archs
    archs="$(lipo -archs "$universal_out")"
    case "$archs" in
        *x86_64*arm64*|*arm64*x86_64*) ;;
        *)
            log_error "libcore.dylib 不是 universal（实际: $archs）"
            exit 1
            ;;
    esac

    log_info "macOS 编译完成: $universal_out ($archs)"
}

# 编译 Linux
build_linux() {
    log_info "编译 Linux (amd64)..."
    cd "$CORE_DIR"

    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    go build -buildmode=c-shared -trimpath \
        -ldflags="-s -w" \
        -tags "with_gvisor,with_quic,with_wireguard,with_clash_api" \
        -o "$OUTPUT_DIR/libcore-linux-amd64.so" \
        ./cmd/internal/build_shared

    log_info "Linux 编译完成: $OUTPUT_DIR/libcore-linux-amd64.so"
}

# 编译 Windows
build_windows() {
    log_info "编译 Windows (amd64)..."
    cd "$CORE_DIR"

    CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
    go build -buildmode=c-shared -trimpath \
        -ldflags="-s -w" \
        -tags "with_gvisor,with_quic,with_wireguard,with_clash_api" \
        -o "$OUTPUT_DIR/libcore-windows-amd64.dll" \
        ./cmd/internal/build_shared

    log_info "Windows 编译完成: $OUTPUT_DIR/libcore-windows-amd64.dll"
}

# 主流程
main() {
    mkdir -p "$OUTPUT_DIR"

    check_deps
    clone_source

    case "${1:-all}" in
        ios)     build_ios ;;
        android) build_android ;;
        macos)   build_macos ;;
        linux)   build_linux ;;
        windows) build_windows ;;
        mobile)
            build_ios
            build_android
            ;;
        desktop)
            build_macos
            build_linux
            build_windows
            ;;
        all)
            build_ios
            build_android
            build_macos
            build_linux
            build_windows
            ;;
        *)
            echo "Usage: $0 {ios|android|macos|linux|windows|mobile|desktop|all}"
            exit 1
            ;;
    esac

    log_info "编译完成！输出目录: $OUTPUT_DIR"
}

main "$@"
