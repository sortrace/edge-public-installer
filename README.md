# Sortrace Edge Updater

The `edge-updater` repository provides all scripts needed for setting up and managing Sortrace truck devices remotely. It ensures devices can be installed, configured, and updated easily through a unified setup process.

---

## Repository Overview

| Script       | Purpose                                                                           |
| :----------- | :-------------------------------------------------------------------------------- |
| `install.sh` | Quickly installs and updates all necessary files and scripts from the repository. |

---

## Installation Instructions

To install and configure a Sortrace device in one line, run:

```bash
curl -fsSL https://raw.githubusercontent.com/sortrace/edge-public-installer/main/install.sh | sudo bash -s -- --github-token "<your-github-token>" --scaleway-token "<your-scaleway-token>" --hostname "truck-001" --tailscale-key "<your-tailscale-key>" --sim-pin "1234" --wifi-ssid "YourSSID" --wifi-password "YourWiFiPassword"
```

### Supported Arguments for `install.sh`

All arguments are forwarded to `install.sh`:

| Argument           | Purpose                                                   |
| :----------------- | :-------------------------------------------------------- |
| `--github-token`   | GitHub token to authenticate Podman pulls from `ghcr.io`. |
| `--scaleway-token` | Scaleway token to authenticate config fetches if needed.  |
| `--hostname`       | Set a new hostname for the device.                        |
| `--tailscale-key`  | Tailscale auth key to automatically join the VPN network. |
| `--sim-pin`        | SIM PIN code to unlock and enable 4G connection.          |
| `--wifi-ssid`      | WiFi SSID if connecting via WiFi.                         |
| `--wifi-password`  | WiFi password if connecting via WiFi.                     |
