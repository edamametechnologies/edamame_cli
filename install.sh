#!/bin/sh
# EDAMAME CLI Installer
# Usage: curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/edamametechnologies/edamame_cli/main/install.sh | sh -s -- [OPTIONS]
#
# Options:
#   --install-dir PATH   Binary install directory (default: /usr/local/bin on Unix, $HOME on Windows)
#   --force-binary       Skip package managers, use binary download
#   --version VERSION    Install a specific version (default: latest)
#
# Examples:
#   curl --proto '=https' --tlsv1.2 -sSf \
#     https://raw.githubusercontent.com/edamametechnologies/edamame_cli/main/install.sh | sh
#
#   curl ... | sudo sh -s -- --force-binary
#   curl ... | sh -s -- --install-dir /opt/bin --version 1.1.2

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

REPO_BASE_URL="https://github.com/edamametechnologies/edamame_cli"
FALLBACK_VERSION="1.1.4"

detect_platform() {
    local uname_out
    uname_out=$(uname -s 2>/dev/null || echo "unknown")
    case "$uname_out" in
        Linux)   echo "linux" ;;
        Darwin)  echo "macos" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)       echo "unknown" ;;
    esac
}

download_file() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$1" -O "$2"
    else
        error "Neither curl nor wget found."
    fi
}

fetch_latest_version() {
    local api_url="${REPO_BASE_URL}/releases/latest"
    local json=""
    if command -v curl >/dev/null 2>&1; then
        if [ -n "$GITHUB_TOKEN" ]; then
            json=$(curl --connect-timeout 10 --max-time 30 -fsSL -H "Authorization: token $GITHUB_TOKEN" "$api_url" 2>/dev/null) || json=""
        else
            json=$(curl --connect-timeout 10 --max-time 30 -fsSL "$api_url" 2>/dev/null) || json=""
        fi
    elif command -v wget >/dev/null 2>&1; then
        if [ -n "$GITHUB_TOKEN" ]; then
            json=$(wget --timeout=30 -q -O - --header="Authorization: token $GITHUB_TOKEN" "$api_url" 2>/dev/null) || json=""
        else
            json=$(wget --timeout=30 -q -O - "$api_url" 2>/dev/null) || json=""
        fi
    fi
    echo "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' | sed 's/^v//'
}

detect_glibc_version() {
    if command -v getconf >/dev/null 2>&1; then
        getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}'
    else
        echo ""
    fi
}

version_lt() {
    [ "$1" = "$2" ] && return 1
    local smallest
    smallest=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
    [ "$smallest" = "$1" ] && [ "$1" != "$2" ]
}

determine_linux_suffix() {
    local arch="$1"
    local libc="$2"
    case "$arch" in
        x86_64)
            if [ "$libc" = "musl" ]; then echo "x86_64-unknown-linux-musl"
            else echo "x86_64-unknown-linux-gnu"; fi ;;
        i686)      echo "i686-unknown-linux-gnu" ;;
        aarch64)
            if [ "$libc" = "musl" ]; then echo "aarch64-unknown-linux-musl"
            else echo "aarch64-unknown-linux-gnu"; fi ;;
        armv7|armv7l|armhf)
            echo "armv7-unknown-linux-gnueabihf" ;;
        *)  error "Unsupported Linux architecture: $arch" ;;
    esac
}

# ── Parse arguments ──────────────────────────────────────────────

CONFIG_INSTALL_DIR=""
CONFIG_FORCE_BINARY="false"
CONFIG_VERSION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --install-dir)   CONFIG_INSTALL_DIR="$2"; shift 2 ;;
        --force-binary)  CONFIG_FORCE_BINARY="true"; shift ;;
        --version)       CONFIG_VERSION="$2"; shift 2 ;;
        *)               warn "Unknown option: $1"; shift ;;
    esac
done

# ── Platform detection ───────────────────────────────────────────

PLATFORM=$(detect_platform)
ARCH=$(uname -m 2>/dev/null || echo "unknown")
LINUX_ARCH_NORMALIZED="$ARCH"
LINUX_LIBC_FLAVOR="gnu"

case "$PLATFORM" in
    linux)
        case "$ARCH" in
            armv7l|armhf) LINUX_ARCH_NORMALIZED="armv7" ;;
        esac
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ "$ID" = "alpine" ]; then
                LINUX_LIBC_FLAVOR="musl"
            else
                GLIBC_VERSION=$(detect_glibc_version)
                case "$ARCH" in
                    x86_64)
                        if [ -n "$GLIBC_VERSION" ] && version_lt "$GLIBC_VERSION" "2.29"; then
                            LINUX_LIBC_FLAVOR="musl"
                        fi ;;
                    aarch64)
                        if [ -n "$GLIBC_VERSION" ] && version_lt "$GLIBC_VERSION" "2.35"; then
                            LINUX_LIBC_FLAVOR="musl"
                        fi ;;
                esac
            fi
        fi ;;
    macos)   ID="macos" ;;
    windows) ID="windows" ;;
    *)       error "Unsupported platform." ;;
esac

# ── Resolve install directory and sudo ───────────────────────────

INSTALL_DIR="$CONFIG_INSTALL_DIR"
if [ -z "$INSTALL_DIR" ]; then
    case "$PLATFORM" in
        linux|macos) INSTALL_DIR="/usr/local/bin" ;;
        windows)     INSTALL_DIR="$HOME" ;;
    esac
fi

SUDO=""
if [ "$PLATFORM" != "windows" ] && [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi
fi

# ── Resolve version ─────────────────────────────────────────────

VERSION="$CONFIG_VERSION"
if [ -z "$VERSION" ]; then
    VERSION=$(fetch_latest_version)
    if [ -z "$VERSION" ]; then
        warn "Failed to determine latest version, using fallback $FALLBACK_VERSION"
        VERSION="$FALLBACK_VERSION"
    fi
fi

# ── Build artifact name and URL ──────────────────────────────────

ARTIFACT_EXT=""
case "$PLATFORM" in
    linux)   SUFFIX=$(determine_linux_suffix "$LINUX_ARCH_NORMALIZED" "$LINUX_LIBC_FLAVOR") ;;
    macos)   SUFFIX="universal-apple-darwin" ;;
    windows) SUFFIX="x86_64-pc-windows-msvc"; ARTIFACT_EXT=".exe" ;;
esac

ARTIFACT_NAME="edamame_cli-${VERSION}-${SUFFIX}${ARTIFACT_EXT}"
ARTIFACT_URL="${REPO_BASE_URL}/releases/download/v${VERSION}/${ARTIFACT_NAME}"
TARGET_NAME="edamame_cli${ARTIFACT_EXT}"
TARGET_PATH="$INSTALL_DIR/$TARGET_NAME"

# ── APT / APK package path (Linux, non-forced) ──────────────────

pkg_installed="false"

if [ "$PLATFORM" = "linux" ] && [ "$CONFIG_FORCE_BINARY" != "true" ]; then
    case "${ID:-}" in
        alpine)
            if command -v apk >/dev/null 2>&1; then
                REPO_URL="https://edamame.s3.eu-west-1.amazonaws.com/repo/alpine/v3.15/main"
                if ! grep -q "$REPO_URL" /etc/apk/repositories 2>/dev/null; then
                    info "Adding EDAMAME APK repository..."
                    KEY_URL="https://edamame.s3.eu-west-1.amazonaws.com/repo/alpine/v3.15/main/${ARCH}/edamame.rsa.pub"
                    download_file "$KEY_URL" /tmp/edamame.rsa.pub || true
                    if [ -f /tmp/edamame.rsa.pub ]; then
                        $SUDO cp /tmp/edamame.rsa.pub /etc/apk/keys/edamame.rsa.pub
                    fi
                    echo "$REPO_URL" | $SUDO tee -a /etc/apk/repositories >/dev/null
                fi
                $SUDO apk update < /dev/null
                $SUDO apk add --no-cache --upgrade edamame-cli < /dev/null && pkg_installed="true"
            fi
            ;;
        ubuntu|debian|raspbian|pop|linuxmint|elementary|zorin)
            if command -v apt-get >/dev/null 2>&1; then
                if ! grep -q "edamame.s3.eu-west-1.amazonaws.com/repo" /etc/apt/sources.list.d/edamame.list 2>/dev/null; then
                    info "Adding EDAMAME APT repository..."
                    if ! command -v gpg >/dev/null 2>&1; then
                        $SUDO apt-get install -y gnupg < /dev/null 2>/dev/null || {
                            $SUDO apt-get update -qq < /dev/null
                            $SUDO apt-get install -y gnupg < /dev/null
                        }
                    fi
                    download_file "https://edamame.s3.eu-west-1.amazonaws.com/repo/public.key" /tmp/edamame_key.asc
                    cat /tmp/edamame_key.asc | $SUDO gpg --dearmor -o /usr/share/keyrings/edamame.gpg
                    rm -f /tmp/edamame_key.asc
                    DEB_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
                    echo "deb [arch=${DEB_ARCH} signed-by=/usr/share/keyrings/edamame.gpg] https://edamame.s3.eu-west-1.amazonaws.com/repo stable main" | \
                        $SUDO tee /etc/apt/sources.list.d/edamame.list >/dev/null
                fi
                $SUDO apt-get update -qq < /dev/null
                $SUDO apt-get install -y edamame-cli < /dev/null && pkg_installed="true"
            fi
            ;;
    esac
fi

# macOS: try Homebrew first unless forced
if [ "$PLATFORM" = "macos" ] && [ "$CONFIG_FORCE_BINARY" != "true" ]; then
    if command -v brew >/dev/null 2>&1; then
        if ! brew tap | grep -q "edamametechnologies/tap"; then
            brew tap edamametechnologies/tap >/dev/null 2>&1 || true
        fi
        if brew list edamame-cli >/dev/null 2>&1; then
            brew upgrade edamame-cli >/dev/null 2>&1 || true
        else
            brew install edamame-cli >/dev/null 2>&1 || true
        fi
        if command -v edamame_cli >/dev/null 2>&1; then
            pkg_installed="true"
        fi
    fi
fi

# Windows: try Chocolatey first unless forced
if [ "$PLATFORM" = "windows" ] && [ "$CONFIG_FORCE_BINARY" != "true" ]; then
    if command -v choco >/dev/null 2>&1; then
        if choco list --local-only --exact edamame-cli 2>/dev/null | grep -q "^edamame-cli "; then
            choco upgrade edamame-cli -y 2>/dev/null < /dev/null || true
        else
            choco install edamame-cli -y 2>/dev/null < /dev/null || true
        fi
        if command -v edamame_cli.exe >/dev/null 2>&1 || command -v edamame_cli >/dev/null 2>&1; then
            pkg_installed="true"
        fi
    fi
fi

# ── Binary download fallback ────────────────────────────────────

if [ "$pkg_installed" != "true" ]; then
    info "Downloading edamame_cli ${VERSION} (${SUFFIX})..."
    TMP_BIN=$(mktemp)
    if ! download_file "$ARTIFACT_URL" "$TMP_BIN"; then
        FALLBACK_NAME="edamame_cli-${FALLBACK_VERSION}-${SUFFIX}${ARTIFACT_EXT}"
        FALLBACK_URL="${REPO_BASE_URL}/releases/download/v${FALLBACK_VERSION}/${FALLBACK_NAME}"
        warn "Primary download failed, trying fallback v${FALLBACK_VERSION}..."
        if ! download_file "$FALLBACK_URL" "$TMP_BIN"; then
            rm -f "$TMP_BIN"
            error "Failed to download edamame_cli binary."
        fi
    fi

    if [ "$PLATFORM" != "windows" ]; then
        chmod +x "$TMP_BIN"
    fi

    if [ -n "$SUDO" ]; then
        $SUDO mkdir -p "$INSTALL_DIR"
        $SUDO install -m 755 "$TMP_BIN" "$TARGET_PATH"
    else
        mkdir -p "$INSTALL_DIR"
        if command -v install >/dev/null 2>&1; then
            install -m 755 "$TMP_BIN" "$TARGET_PATH"
        else
            cp "$TMP_BIN" "$TARGET_PATH"
            chmod 755 "$TARGET_PATH" 2>/dev/null || true
        fi
    fi
    rm -f "$TMP_BIN"
    info "Installed at $TARGET_PATH"
fi

# ── Verify ───────────────────────────────────────────────────────

BIN_PATH=$(command -v edamame_cli 2>/dev/null || command -v edamame-cli 2>/dev/null || true)
if [ -z "$BIN_PATH" ] && [ -f "$TARGET_PATH" ]; then
    BIN_PATH="$TARGET_PATH"
fi

if [ -z "$BIN_PATH" ]; then
    error "edamame_cli not found after installation."
fi

info "edamame_cli installed: $BIN_PATH"
"$BIN_PATH" --version 2>/dev/null || true
