#!/bin/bash

set -e

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
    --bootstrap-image)
      BOOTSTRAP_IMAGE="$2"
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
    *)
      echo "[INSTALL] Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p /etc/sortrace

# Validate bootstrap image
if [ -z "$BOOTSTRAP_IMAGE" ]; then
  echo "[INSTALL] ERROR: --bootstrap-image is required (e.g., registry.scaleway.com/sortrace/bootstrap:latest)"
  exit 1
fi

# Optional hostname configuration
if [ -n "$NEW_HOSTNAME" ]; then
  NEW_HOSTNAME="edge-device-${NEW_HOSTNAME#edge-device-}"  # Force prefix
  CURRENT_HOSTNAME=$(hostname)

  if [[ "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]]; then
    echo "[INSTALL] Hostname already set to $NEW_HOSTNAME. Skipping change."
  else
    echo "[INSTALL] Setting hostname to $NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
  fi

  # Update /etc/hosts
  if grep -q "^127.0.1.1" /etc/hosts; then
    sed -i "s/^127.0.1.1.*/127.0.1.1   $NEW_HOSTNAME/" /etc/hosts
  else
    echo "127.0.1.1   $NEW_HOSTNAME" >> /etc/hosts
  fi
fi

# Ensure required packages
echo "[INSTALL] Installing required packages..."
apt-get update -qq
apt-get install -y -qq podman curl jq

# Tailscale installation and conditional setup
if [ -n "$TAILSCALE_KEY" ]; then
  echo "[INSTALL] Installing and configuring Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled

  if ! tailscale status &>/dev/null; then
    echo "[INSTALL] Connecting to Tailscale with provided key..."
    tailscale up --authkey "$TAILSCALE_KEY"
  else
    echo "[INSTALL] Tailscale already connected."
  fi
else
  echo "[INSTALL] No Tailscale key provided. Checking existing connection..."
  if ! command -v tailscale &>/dev/null || ! tailscale status &>/dev/null; then
    echo "[INSTALL] ERROR: Tailscale not set up and no key provided. Exiting."
    exit 1
  else
    echo "[INSTALL] Tailscale is already running."
  fi
fi

# Configure 4G modem if SIM PIN provided
if [ -n "$SIM_PIN" ]; then
  echo "[INSTALL] Configuring 4G modem..."
  apt-get install -y -qq mmcli network-manager
  mmcli -i 0 --disable-pin --pin="$SIM_PIN"
  mmcli -m 0 --simple-connect="apn=online.telia.se"
  mmcli -m 0 --enable
fi

# Configure WiFi if credentials are provided
if [ -n "$WIFI_SSID" ] && [ -n "$WIFI_PASSWORD" ]; then
  echo "[INSTALL] Configuring WiFi..."
  WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
  cat <<EOF >> "$WPA_CONF"

network={
    ssid="$WIFI_SSID"
    psk="$WIFI_PASSWORD"
}
EOF

  chmod 600 "$WPA_CONF"
  systemctl enable --now wpa_supplicant
  systemctl restart wpa_supplicant
fi

# Pull and run bootstrap container from Scaleway
echo "[INSTALL] Pulling bootstrap container: $BOOTSTRAP_IMAGE"
podman pull "$BOOTSTRAP_IMAGE"

echo "[INSTALL] Running bootstrap container..."
podman run -d --name sortrace-bootstrap \
  --restart=always \
  -v /run/podman/podman.sock:/run/podman/podman.sock \
  -v /etc/sortrace:/etc/sortrace \
  "$BOOTSTRAP_IMAGE"

echo "[INSTALL] Installation complete!"
