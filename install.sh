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
    --github-username)
      GITHUB_USERNAME="$2"
      shift 2
      ;;
    *)
      # Forward unknown args to setup.sh later
      FORWARD_ARGS+=" $1"
      shift
      ;;
  esac
done

# Validate hostname
CURRENT_HOSTNAME=$(hostname)

if [ -n "$NEW_HOSTNAME" ]; then
  echo "[SETUP] Setting hostname to $NEW_HOSTNAME"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  DEVICE_HOSTNAME="$NEW_HOSTNAME"
elif [[ "$CURRENT_HOSTNAME" == edge-* ]]; then
  echo "[SETUP] Using existing hostname: $CURRENT_HOSTNAME"
  DEVICE_HOSTNAME="$CURRENT_HOSTNAME"
else
  echo "[ERROR] No --hostname provided and existing hostname ($CURRENT_HOSTNAME) does not start with 'edge-'."
  echo "Please rerun the install script with: --hostname edge-yourdevice"
  exit 1
fi

# Ensure necessary packages
echo "[SETUP] Installing required packages..."
apt-get update
apt-get install -y git openssh-client curl jq

# Generate SSH key if missing
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "[SETUP] No SSH key found. Generating a new one..."
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  ssh-keygen -t ed25519 -C "$DEVICE_HOSTNAME" -f "$SSH_KEY_PATH" -N ""

  echo "[SETUP] Please provide GitHub credentials to upload the deploy key."
  if [ -z "$GITHUB_USERNAME" ]; then
    read -p "GitHub Username: " GITHUB_USERNAME
  fi
  read -s -p "GitHub Password or Token: " GITHUB_PASSWORD
  echo

  PUBLIC_KEY_CONTENT=$(cat "$SSH_KEY_PATH.pub")
  PAYLOAD=$(jq -n --arg title "$DEVICE_HOSTNAME" --arg key "$PUBLIC_KEY_CONTENT" '{title: $title, key: $key, read_only: true}')

  echo "[SETUP] Uploading deploy key to GitHub repo..."
  curl -u "$GITHUB_USERNAME:$GITHUB_PASSWORD" \
    -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/sortrace/edge-updater/keys \
    -d "$PAYLOAD"
fi

# Start SSH agent and add key
echo "[SETUP] Adding SSH key to agent..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY_PATH"

# Clone or pull repo
if [ -d "$REPO_DIR/.git" ]; then
  echo "[SETUP] Repo already exists. Pulling latest changes..."
  git -C "$REPO_DIR" pull
else
  echo "[SETUP] Cloning repo..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Run setup.sh with forwarded arguments
echo "[SETUP] Running setup.sh..."
bash "$REPO_DIR/setup.sh" $FORWARD_ARGS

echo "[SETUP] Installation complete!"
