#!/bin/bash

set -euo pipefail
trap 'echo "[ERROR] Command failed at line $LINENO: $BASH_COMMAND"' ERR

EDGE_API_URL="http://edge-api:8080"
NEW_HOSTNAME=""
TAILSCALE_KEY=""
SIM_PIN=""
WIFI_SSID=""
WIFI_PASSWORD=""
ARCH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --hostname)
      NEW_HOSTNAME="$2"
      shift; shift
      ;;
    --tailscale-key)
      TAILSCALE_KEY="$2"
      shift; shift
      ;;
    --sim-pin)
      SIM_PIN="$2"
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
    --arch)
      ARCH="$2"
      shift; shift
      ;;
    *)
      echo "[INSTALL] Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p /etc/sortrace

# --- Hostname Configuration ---
if [ -n "$NEW_HOSTNAME" ]; then
  NEW_HOSTNAME="edge-device-${NEW_HOSTNAME#edge-device-}"
  CURRENT_HOSTNAME=$(hostname)

  if [[ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]]; then
    echo "[INSTALL] Setting hostname to $NEW_HOSTNAME"
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    sudo sed -i "s/^127.0.1.1.*/127.0.1.1   $NEW_HOSTNAME/" /etc/hosts || echo "127.0.1.1   $NEW_HOSTNAME" >> /etc/hosts
  else
    echo "[INSTALL] Hostname already set to $NEW_HOSTNAME"
  fi
else
  NEW_HOSTNAME=$(hostname)
fi

# --- Install Dependencies ---
echo "[INSTALL] Installing required packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq podman curl jq

# --- Tailscale Setup ---
if [ -n "$TAILSCALE_KEY" ]; then
  echo "[INSTALL] Installing and configuring Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled

  if ! tailscale status &>/dev/null; then
    tailscale up --authkey "$TAILSCALE_KEY"
  fi
else
  echo "[INSTALL] No Tailscale key provided. Checking existing Tailscale setup..."
  if ! command -v tailscale &>/dev/null || ! tailscale status &>/dev/null; then
    echo "[INSTALL] ERROR: Tailscale not set up and no key provided. Exiting."
    exit 1
  fi
fi

# --- Configure 4G Modem (if SIM PIN provided) ---
if [ -n "$SIM_PIN" ]; then
  echo "[INSTALL] Configuring 4G modem..."
  sudo apt-get install -y -qq mmcli network-manager
  mmcli -i 0 --disable-pin --pin="$SIM_PIN"
  mmcli -m 0 --simple-connect="apn=online.telia.se"
  mmcli -m 0 --enable
fi

# --- Configure WiFi ---
if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
  echo "[INSTALL] Configuring WiFi..."
  WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
  sudo tee -a "$WPA_CONF" > /dev/null <<EOF

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASSWORD"
}
EOF
  sudo chmod 600 "$WPA_CONF"
  sudo systemctl enable --now wpa_supplicant
  sudo systemctl restart wpa_supplicant
fi

# --- Download metadata and bootstrap image ---
echo "[INSTALL] Fetching edge metadata for hostname: $NEW_HOSTNAME"
META_JSON=$(curl -sf "$EDGE_API_URL/edge-meta/$NEW_HOSTNAME")

BOOTSTRAP_IMAGE_NAME=$(echo "$META_JSON" | jq -r '.bootstrap.image')
if [ -z "$BOOTSTRAP_IMAGE_NAME" ] || [ "$BOOTSTRAP_IMAGE_NAME" = "null" ]; then
  echo "[INSTALL] ERROR: Failed to extract bootstrap image name from metadata"
  exit 1
fi

echo "[INSTALL] Resolving signed URL for image: $BOOTSTRAP_IMAGE_NAME"
BOOTSTRAP_IMAGE_URL=$(curl -sf "$EDGE_API_URL/image-url?name=$BOOTSTRAP_IMAGE_NAME" | jq -r .url)
if [ -z "$BOOTSTRAP_IMAGE_URL" ] || [ "$BOOTSTRAP_IMAGE_URL" = "null" ]; then
  echo "[INSTALL] ERROR: Failed to resolve image URL"
  exit 1
fi

echo "[INSTALL] Downloading bootstrap image tarball from $BOOTSTRAP_IMAGE_URL"
IMAGE_TAR_PATH="$HOME/bootstrap-image.tar"
curl -L "$BOOTSTRAP_IMAGE_URL" -o "$IMAGE_TAR_PATH"

echo "[INSTALL] Loading bootstrap image into Podman..."
sudo podman load -i "$IMAGE_TAR_PATH"

IMAGE_REF=$(sudo podman images --format "{{.Repository}}:{{.Tag}}" | grep -m1 'edge-bootstrap:')

echo "[INSTALL] Starting bootstrap container: $IMAGE_REF"

# Conditionally add architecture if provided
ARCH_OPTION=""
if [ -n "$ARCH" ]; then
  ARCH_OPTION="--arch=$ARCH"
fi

echo "[INSTALL] Creating or updating systemd service for bootstrap container..."

# Stop and remove existing container if it exists
if sudo podman container exists edge-device-bootstrap; then
  echo "[INSTALL] Removing existing container..."
  sudo podman rm -f edge-device-bootstrap
fi

# (Re)create the container
sudo podman create --name edge-device-bootstrap \
  --restart=always \
  -v /run/podman/podman.sock:/run/podman/podman.sock \
  -v /etc/sortrace:/etc/sortrace \
  $ARCH_OPTION \
  $IMAGE_REF

# Generate new systemd unit file
sudo podman generate systemd --name edge-device-bootstrap --files --restart-policy=always

SERVICE_FILE="container-edge-device-bootstrap.service"
SYSTEMD_TARGET="/etc/systemd/system/$SERVICE_FILE"

# Overwrite the old service unit
sudo mv -f "$SERVICE_FILE" "$SYSTEMD_TARGET"

# Ensure RestartSec=10 exists or is updated
if grep -q '^RestartSec=' "$SYSTEMD_TARGET"; then
  sudo sed -i 's/^RestartSec=.*/RestartSec=10/' "$SYSTEMD_TARGET"
else
  sudo sed -i '/^\[Service\]/a RestartSec=10' "$SYSTEMD_TARGET"
fi

# Reload and restart systemd service
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_FILE"
sudo systemctl restart "$SERVICE_FILE"

echo "[INSTALL] ✅ Bootstrap service is running with a 10s restart delay."
