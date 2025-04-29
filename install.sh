#!/bin/bash

REPO_URL="https://github.com/sortrace/edge-updater"
REPO_DIR="/opt/sortrace/edge-updater"

# Ensure Git is installed
apt-get update
apt-get install -y git

# Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull
else
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
fi

# Run setup with all passed arguments
bash "$REPO_DIR/setup.sh" "$@"
