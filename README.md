# 📖 README

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
curl -fsSL https://raw.githubusercontent.com/sortrace/edge-public-installer/main/install.sh | sudo bash -s -- --github-pat "<your-github-pat>" --scaleway-token "<your-scaleway-token>" --hostname "edge-truck-001" --tailscale-key "<your-tailscale-key>" --sim-pin "1234" --wifi-ssid "YourSSID" --wifi-password "YourWiFiPassword"
```

> ⚡ **Important:**  
> You must provide a **GitHub Fine-Grained Personal Access Token (PAT)** with specific restricted access.  
> This token is **only used once during installation** to upload a **per-device Deploy Key**,  
> after which the device switches to using its unique SSH key for accessing updates.

---

### How to create a restricted GitHub Fine-Grained PAT

1. Visit: [Create a new fine-grained personal access token](https://github.com/settings/personal-access-tokens/new?type=fine-grained)

2. Fill in the following fields:

   - **Token name:** `Sortrace Edge Device Installer`
   - **Resource owner:** `sortrace`
   - **Expiration:** (Recommended) 30 days or less

3. Under **Repository Access**, select:

   - `Only select repositories`
   - ✅ Select **only** `sortrace/edge-updater`

4. Under **Repository Permissions**, set:

   | Permission   | Access           |
   | :----------- | :--------------- |
   | **Contents** | `Read and Write` |

5. Leave all other permissions unset (at their defaults).

6. Generate the token and **copy it safely** (you will not be able to see it again).

✅ You will paste this token when prompted during device installation.

---

### Supported Arguments for `install.sh`

| Argument           | Purpose                                                                           |
| :----------------- | :-------------------------------------------------------------------------------- |
| `--github-pat`     | Fine-Grained GitHub Personal Access Token to create a Deploy Key for this device. |
| `--scaleway-token` | Scaleway token to authenticate config fetches if needed.                          |
| `--hostname`       | Set a new hostname for the device. Must start with `edge-`.                       |
| `--tailscale-key`  | Tailscale auth key to automatically join the VPN network.                         |
| `--sim-pin`        | SIM PIN code to unlock and enable 4G connection.                                  |
| `--wifi-ssid`      | WiFi SSID if connecting via WiFi.                                                 |
| `--wifi-password`  | WiFi password if connecting via WiFi.                                             |
