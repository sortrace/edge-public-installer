#!/bin/bash

set -e

# Settings
REPO_URL="git@github.com:sortrace/edge-updater.git"
REPO_DIR="/opt/sortrace/edge-updater"
SSH_KEY_PATH="/etc/sortrace/id_ed25519"

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

# Validate or Prompt Missing Inputs
CURRENT_HOSTNAME=$(hostname)

if [ -z "$NEW_HOSTNAME" ]; then
  if [[ "$CURRENT_HOSTNAME" == edge-* ]]; then
    echo "[INSTALL] Using existing hostname: $CURRENT_HOSTNAME"
    DEVICE_HOSTNAME="$CURRENT_HOSTNAME"
  else
    read -p "[INSTALL] Enter hostname (must start with 'edge-'): " NEW_HOSTNAME < /dev/tty
    DEVICE_HOSTNAME="$NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
  fi
else
  if [[ "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]]; then
    echo "[INSTALL] Hostname already set to $NEW_HOSTNAME. Skipping hostname change."
    DEVICE_HOSTNAME="$NEW_HOSTNAME"
  else
    echo "[INSTALL] Setting hostname to $NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    DEVICE_HOSTNAME="$NEW_HOSTNAME"
  fi
fi

if [ -z "$TAILSCALE_KEY" ]; then
  echo
  echo "[INSTALL] You must create a Tailscale auth key:"
  echo "  👉 https://login.tailscale.com/admin/settings/keys"
  echo
  read -p "[INSTALL] Enter Tailscale Auth Key: " TAILSCALE_KEY < /dev/tty
fi

# Update /etc/hosts
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127.0.1.1.*/127.0.1.1   $DEVICE_HOSTNAME/" /etc/hosts
else
  echo "127.0.1.1   $DEVICE_HOSTNAME" >> /etc/hosts
fi

# Ensure necessary packages
echo "[INSTALL] Installing required packages..."
apt-get update -qq
apt-get install -y -qq git openssh-client curl jq

# Add GitHub to known hosts
if ! grep -q "^github.com " ~/.ssh/known_hosts 2>/dev/null; then
  echo "[INSTALL] Adding GitHub SSH fingerprint to known_hosts..."
  mkdir -p ~/.ssh
  ssh-keyscan github.com >> ~/.ssh/known_hosts
else
  echo "[INSTALL] GitHub SSH fingerprint already present."
fi

# Generate SSH key if missing
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[INSTALL] No SSH key found. Generating a new one..."
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  ssh-keygen -t ed25519 -C "$DEVICE_HOSTNAME" -f "$SSH_KEY_PATH" -N ""
  
  echo
  echo "[INSTALL] =================================================="
  echo "[INSTALL] SSH public key generated:"
  echo
  cat "$SSH_KEY_PATH.pub"
  echo
  echo "[INSTALL] =================================================="
  echo "[INSTALL] Please copy the above public key and add it as a Deploy Key to:"
  echo "         https://github.com/sortrace/edge-updater/settings/keys"
  echo "[INSTALL] (Set it as Read-Only)"
  echo
  read -n 1 -s -r -p "[INSTALL] Press any key to continue after the Deploy Key has been added..." < /dev/tty
  echo
else
  echo "[INSTALL] SSH key already present. Skipping key generation."
fi

# Start SSH agent and add key
echo "[INSTALL] Adding SSH key to agent..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"

# Add SSH config entry for GitHub if missing
if ! grep -q "Host github.com" /etc/ssh/ssh_config 2>/dev/null; then
  echo "[INSTALL] Adding GitHub SSH config..."
  cat <<EOF >> /etc/ssh/ssh_config

# Sortrace Edge Device GitHub Access
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY_PATH
    IdentitiesOnly yes
EOF
else
  echo "[INSTALL] GitHub SSH config already present."
fi

# Clone or pull repo
if [ -d "$REPO_DIR/.git" ]; then
  echo "[INSTALL] Repo already exists. Pulling latest changes..."
  git -C "$REPO_DIR" pull
else
  echo "[INSTALL] Cloning repo..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Run setup.sh with forwarded arguments
echo "[INSTALL] Running setup.sh..."
bash "$REPO_DIR/setup.sh" \
  --hostname "$DEVICE_HOSTNAME" \
  --tailscale-key "$TAILSCALE_KEY" \
  ${SIM_PIN:+--sim-pin "$SIM_PIN"} \
  ${WIFI_SSID:+--wifi-ssid "$WIFI_SSID"} \
  ${WIFI_PASSWORD:+--wifi-password "$WIFI_PASSWORD"}

echo "[INSTALL] Installation complete!"
