#!/bin/bash
set -e

API_URL="http://edge-api:8080"
HOSTNAME=$(hostname)
INSTALL_DIR="/opt/sortrace"
LOG_DIR="/var/log/sortrace"
LOG_FILE="$LOG_DIR/install.log"
TMP_DIR="/tmp/sortrace-bootstrap"
INSTALLER_SCRIPT="bin/install.sh"

# Prepare logging
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check for supervisord
if ! command -v supervisord >/dev/null 2>&1; then
  log "supervisord not found — installing..."
  sudo apt-get update
  sudo apt-get install -y supervisor
else
  log "supervisord found at $(command -v supervisord)"
fi

# Get latest package info
log "Checking latest version from $API_URL/edge-meta/$HOSTNAME..."
PACKAGE_NAME=$(curl -fsSL "$API_URL/edge-meta/$HOSTNAME" | jq -r '.runtime.package')

if [[ -z "$PACKAGE_NAME" || "$PACKAGE_NAME" == "null" ]]; then
  log "No runtime package found from API. Exiting."
  exit 0
fi

# Get signed URL
log "Fetching signed URL for: $PACKAGE_NAME"
SIGNED_URL=$(curl -fsSL "$API_URL/image-url?name=$PACKAGE_NAME" | jq -r '.url')
if [[ -z "$SIGNED_URL" || "$SIGNED_URL" == "null" ]]; then
  log "Failed to retrieve signed download URL."
  exit 1
fi

# Prepare temp workspace
log "Downloading and extracting runtime package..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR"

curl -fsSL -o runtime-package.tar.tgz "$SIGNED_URL"
tar -xzf runtime-package.tar.tgz

for i in {1..50}; do  # 50 × 0.1s = 5 seconds max
  [[ -f bin/install.sh ]] && break
  sleep 0.1
done

if [[ -f bin/install.sh ]]; then
  ./bin/install.sh
else
  echo "❌ ERROR: bin/install.sh not found after extract"
  exit 1
fi

log "Running $INSTALLER_SCRIPT with version: $PACKAGE_NAME (detached)"
nohup "./$INSTALLER_SCRIPT" "$PACKAGE_NAME" >> "$LOG_FILE" 2>&1 &

log "✅ Bootstrap install launched. Check log for progress: $LOG_FILE"
