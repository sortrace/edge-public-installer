#!/bin/bash

set -e

INSTALL_DIR="/opt/sortrace"
INSTALLER_PATH="$INSTALL_DIR/bin/install.sh"
VERSION_FILE="$INSTALL_DIR/update/version.txt"
API_URL="http://edge-api:8080"
HOSTNAME=$(hostname)

# Ensure install location exists
mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/update"

# If not running from installed location, copy ourselves there
SELF_PATH="$(realpath "$0")"
if [[ "$SELF_PATH" != "$INSTALLER_PATH" ]]; then
  echo "Copying installer to $INSTALLER_PATH"
  cp "$SELF_PATH" "$INSTALLER_PATH"
  chmod +x "$INSTALLER_PATH"
fi

# Query latest version info
echo "Checking latest version from $API_URL/edge-meta/$HOSTNAME..."
RESPONSE=$(curl -fsSL "$API_URL/edge-meta/$HOSTNAME")
PACKAGE_NAME=$(echo "$RESPONSE" | jq -r '.runtime.package')

if [[ -z "$PACKAGE_NAME" || "$PACKAGE_NAME" == "null" ]]; then
  echo "No runtime package found from API."
  exit 1
fi

# Get current installed version
if [[ -f "$VERSION_FILE" ]]; then
  CURRENT_VERSION=$(cat "$VERSION_FILE")
else
  CURRENT_VERSION=""
fi

if [[ "$PACKAGE_NAME" == "$CURRENT_VERSION" ]]; then
  echo "Already up to date: $CURRENT_VERSION"
  exit 0
fi

echo "Installing new version: $PACKAGE_NAME"

# Get signed URL for the package
SIGNED_URL=$(curl -fsSL "$API_URL/image-url/name=$PACKAGE_NAME" | jq -r '.url')
if [[ -z "$SIGNED_URL" ]]; then
  echo "Failed to get signed download URL."
  exit 1
fi

# Download and extract
TMP_DIR="/tmp/sortrace-install"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

echo "Downloading package..."
curl -fsSL -o "$PACKAGE_NAME" "$SIGNED_URL"

echo "Extracting package..."
tar -xzf "$PACKAGE_NAME"

# Stop existing service
echo "Stopping sortrace-runtime service (if running)..."
systemctl stop sortrace-runtime || true

# Install files
echo "Installing to $INSTALL_DIR..."
rsync -a --delete ./ "$INSTALL_DIR/"

# Restore install.sh
cp "$SELF_PATH" "$INSTALLER_PATH"
chmod +x "$INSTALLER_PATH"

# Update version
echo "$PACKAGE_NAME" > "$VERSION_FILE"

# Start service
echo "Starting sortrace-runtime..."
systemctl start sortrace-runtime

echo "✅ Install complete: $PACKAGE_NAME"
