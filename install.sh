#!/bin/bash

set -e

EDGE_API_URL="http://edge-api:8080"

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
    hostnamectl set-hostname "$NEW_HOSTNAME"
    sed -i "s/^127.0.1.1.*/127.0.1.1   $NEW_HOSTNAME/" /etc/hosts || echo "127.0.1.1   $NEW_HOSTNAME" >> /etc/hosts
  else
    echo "[INSTALL] Hostname already set to $NEW_HOSTNAME"
  fi
else
  NEW_HOSTNAME=$(hostname)
fi

# --- Install Dependencies ---
echo "[INSTALL] Installing required packages..."
apt-get update -qq
apt-get install -y -qq podman curl jq

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
  apt-get install -y -qq mmcli network-manager
  mmcli -i 0 --disable-pin --pin="$SIM_PIN"
  mmcli -m 0 --simple-connect="apn=online.telia.se"
  mmcli -m 0 --enable
fi

# --- Configure WiFi ---
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

# --- Download metadata and bootstrap image ---
echo "[INSTALL] Fetching edge metadata for hostname: $NEW_HOSTNAME"
META_JSON=$(curl -sf "$EDGE_API_URL/edge-meta/$NEW_HOSTNAME")

BOOTSTRAP_IMAGE_NAME=$(echo "$META_JSON" | jq -r '.bootstrap.image')
if [[ -]()]()
