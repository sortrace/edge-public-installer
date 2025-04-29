#!/bin/bash

set -e

# Settings
REPO_URL="git@github.com:sortrace/edge-updater.git"
REPO_DIR="/opt/sortrace/edge-updater"
SSH_KEY_PATH="/etc/sortrace/id_ed25519"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)
      NEW_HOSTNAME="$2"
      shift 2
      ;;
    *)
      FORWARD_ARGS+=" $1"
      shift
      ;;
  esac
done

# Validate hostname
CURRENT_HOSTNAME=$(hostname)

if [ -n "$NEW_HOSTNAME" ]; then
  echo "[INSTALL] Setting hostname to $NEW_HOSTNAME"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  DEVICE_HOSTNAME="$NEW_HOSTNAME"
elif [[ "$CURRENT_HOSTNAME" == edge-* ]]; then
  echo "[INSTALL] Using existing hostname: $CURRENT_HOSTNAME"
  DEVICE_HOSTNAME="$CURRENT_HOSTNAME"
else
  echo "[ERROR] No --hostname provided and existing hostname ($CURRENT_HOSTNAME) does not start with 'edge-'."
  echo "Please rerun the install script with: --hostname edge-yourdevice"
  exit 1
fi

# Update /etc/hosts
if grep -q "^127.0.1.1" /etc/hosts; then
  sed -i "s/^127.0.1.1.*/127.0.1.1   $NEW_HOSTNAME/" /etc/hosts
else
  echo "127.0.1.1   $NEW_HOSTNAME" >> /etc/hosts
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

  # Prompt for GitHub credentials
  echo "[INSTALL] Deploy key requires GitHub credentials with admin access to the repo."
  read -p "GitHub Username: " GITHUB_USERNAME < /dev/tty
  read -s -p "GitHub Password or Token: " GITHUB_PASSWORD < /dev/tty
  echo

  PUBLIC_KEY_CONTENT=$(cat "$SSH_KEY_PATH.pub")
  PAYLOAD=$(jq -n --arg title "$DEVICE_HOSTNAME" --arg key "$PUBLIC_KEY_CONTENT" '{title: $title, key: $key, read_only: true}')

  echo "[INSTALL] Uploading deploy key to GitHub repo..."
  if ! curl -u "$GITHUB_USERNAME:$GITHUB_PASSWORD" \
    -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/sortrace/edge-updater/keys \
    -d "$PAYLOAD"; then
    echo "[ERROR] Failed to upload deploy key to GitHub."
    echo "[CLEANUP] Removing generated SSH key..."
    rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
    exit 1
  fi
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
bash "$REPO_DIR/setup.sh" $FORWARD_ARGS

echo "[INSTALL] Installation complete!"
