#!/bin/bash
set -e

# Download microcks-cli binary if not already present.
# Compatible with macOS (Darwin) and Linux, amd64 and arm64.
#
# The binary is cached in ~/.local/bin/ so it is downloaded once
# and shared across all projects.

MICROCKS_CLI_VERSION="${MICROCKS_CLI_VERSION:-0.5.6}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_PATH="$SCRIPT_DIR/microcks-cli"
CACHE_DIR="$HOME/.local/bin"
CACHED_BINARY="$CACHE_DIR/microcks-cli-${MICROCKS_CLI_VERSION}"

# If already present locally (symlink or file), nothing to do
if [ -x "$LOCAL_PATH" ]; then
  echo "microcks-cli already available at $LOCAL_PATH"
  exit 0
fi

# If cached globally, just symlink
if [ -x "$CACHED_BINARY" ]; then
  echo "microcks-cli ${MICROCKS_CLI_VERSION} found in cache, creating symlink..."
  ln -sf "$CACHED_BINARY" "$LOCAL_PATH"
  echo "microcks-cli ready at $LOCAL_PATH"
  exit 0
fi

# Detect OS
OS=$(uname -s)
case "$OS" in
  Darwin) OS_NAME="darwin" ;;
  Linux)  OS_NAME="linux" ;;
  *)
    echo "Unsupported OS: $OS"
    exit 1
    ;;
esac

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_NAME="amd64" ;;
  aarch64) ARCH_NAME="arm64" ;;
  arm64)   ARCH_NAME="arm64" ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

DOWNLOAD_URL="https://github.com/microcks/microcks-cli/releases/download/${MICROCKS_CLI_VERSION}/microcks-cli-${OS_NAME}-${ARCH_NAME}"

echo "Downloading microcks-cli ${MICROCKS_CLI_VERSION} for ${OS_NAME}/${ARCH_NAME}..."
echo "URL: $DOWNLOAD_URL"

mkdir -p "$CACHE_DIR"
curl -sSfL "$DOWNLOAD_URL" -o "$CACHED_BINARY"

if [ $? -ne 0 ] || [ ! -s "$CACHED_BINARY" ]; then
  echo "Download failed. Cleaning up..."
  rm -f "$CACHED_BINARY"
  exit 1
fi

chmod +x "$CACHED_BINARY"
ln -sf "$CACHED_BINARY" "$LOCAL_PATH"

echo "microcks-cli downloaded to $CACHED_BINARY and symlinked to $LOCAL_PATH"
