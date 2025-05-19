#!/bin/bash
set -e

API_URL="http://edge-api:8080"
HOSTNAME=$(hostname)
INSTALL_DIR="/opt/sortrace"
LOG_DIR="/var/log/sortrace"
LOG_FILE="$LOG_DIR/install.log"
TMP_DIR="/tmp/sortrace-bootstrap"
INSTALLER_SCRIPT="bin/install.sh"

# Vars to forward
TAILSCALE_KEY=""
WIFI_SSID=""
WIFI_PASSWORD=""
SIM_PIN=""

# --- Parse CLI Args ---
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --tailscale-key)
      TAILSCALE_KEY="$2"
      shift; shift
      ;;
    --wifi-ssid)
      WIFI_SSID="$2"
      shift; shift
      ;;
    --wifi-password)
      WIFI_PASSWORD="$2"
      shift; shift
      ;;
    --sim-pin)
      SIM_PIN="$2"
      shift; shift
      ;;
    *)
      echo "[BOOTSTRAP] Unknown option: $1"
      exit 1
      ;;
  esac
done

# Prepare logging
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chown root:root "$LOG_FILE"
chmod 644 "$LOG_FILE"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# --- Tailscale Setup ---
if [ -n "$TAILSCALE_KEY" ]; then
  log "Installing and configuring Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled

  if ! tailscale status &>/dev/null; then
    tailscale up --authkey "$TAILSCALE_KEY"
  fi
else
  log "No Tailscale key provided. Checking existing Tailscale setup..."
  if ! command -v tailscale &>/dev/null || ! tailscale status &>/dev/null; then
    log "ERROR: Tailscale not set up and no key provided. Exiting."
    exit 1
  fi
fi

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

for i in {1..50}; do
  [[ -f "$INSTALLER_SCRIPT" ]] && break
  sleep 0.1
done

if [[ -f "$INSTALLER_SCRIPT" ]]; then
  chmod +x "$INSTALLER_SCRIPT"

  log "Running $INSTALLER_SCRIPT with version: $PACKAGE_NAME (detached)"
  nohup "./$INSTALLER_SCRIPT" "$PACKAGE_NAME" \
    --tailscale-key "$TAILSCALE_KEY" \
    --wifi-ssid "$WIFI_SSID" \
    --wifi-password "$WIFI_PASSWORD" \
    --sim-pin "$SIM_PIN" \
    >> "$LOG_FILE" 2>&1 &
else
  log "❌ ERROR: $INSTALLER_SCRIPT not found after extract"
  exit 1
fi

log "✅ Bootstrap install launched. Check log for progress: $LOG_FILE"
