#!/bin/bash
set -e

API_URL=""
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
NEW_HOSTNAME=""

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
    --hostname)
      NEW_HOSTNAME="$2"
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

# --- Hostname Configuration ---
if [ -n "$NEW_HOSTNAME" ]; then
  NEW_HOSTNAME="edge-device-${NEW_HOSTNAME#edge-device-}"
  CURRENT_HOSTNAME=$(hostname)

  if [[ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]]; then
    log "Setting hostname to $NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    sed -i "s/^127.0.1.1.*/127.0.1.1   $NEW_HOSTNAME/" /etc/hosts || echo "127.0.1.1   $NEW_HOSTNAME" >> /etc/hosts
  else
    log "Hostname already set to $NEW_HOSTNAME"
  fi
else
  NEW_HOSTNAME=$(hostname)
  log "Using current hostname: $NEW_HOSTNAME"
fi

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

# Wait for Tailscale to be up
log INFO "Waiting for Tailscale to become available..."
until tailscale status --json &>/dev/null; do
  sleep 2
done
log INFO "Tailscale is up."


# --- Ensure jq is installed ---
if ! command -v jq &>/dev/null; then
  log "jq not found. Installing..."
  apt-get update -y
  apt-get install -y jq
else
  log "jq already installed. Skipping installation."
fi

# Get Tailscale tags and determine the correct API URL
TAILSCALE_TAGS=$(tailscale status --json | jq -r '.Self.Tags[]?')
case "$TAILSCALE_TAGS" in
  *tag:prod*) API_URL="http://edge-api-prod.tail1ab977.ts.net:8080" ;;
  *tag:test*) API_URL="http://edge-api-test.tail1ab977.ts.net:8080" ;;
  *tag:dev*) API_URL="http://edge-api-dev.tail1ab977.ts.net:8080" ;;
  *tag:staging*) API_URL="http://edge-api-staging.tail1ab977.ts.net:8080" ;;
  *) API_URL="http://edge-api.tail1ab977.ts.net:8080" ;;
esac

log INFO "Using API URL: $API_URL"

# Get latest package info
log "Checking latest version from $API_URL/config/$NEW_HOSTNAME..."
PACKAGE_NAME=$(curl -fsSL "$API_URL/config/$NEW_HOSTNAME" | jq -r '.config.runtime')

if [[ -z "$PACKAGE_NAME" || "$PACKAGE_NAME" == "null" ]]; then
  log "No runtime package found from API. Exiting."
  exit 0
fi

# Get signed URL
log "Fetching signed URL for: $PACKAGE_NAME from $API_URL/image-url..."
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
    --hostname "$NEW_HOSTNAME" \
    >> "$LOG_FILE" 2>&1 &
else
  log "❌ ERROR: $INSTALLER_SCRIPT not found after extract"
  exit 1
fi

log "✅ Bootstrap install launched. Check log for progress: $LOG_FILE"
