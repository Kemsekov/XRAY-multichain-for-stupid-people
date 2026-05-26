Here's the updated `README.md` with generic **Relay** and **Exit** terminology (no country‑specific names).

---

# Multi‑Hop Xray Tunnel: VLESS + REALITY

This repository contains three scripts to deploy a **multi‑hop VLESS + REALITY** tunnel between two servers:

- **Exit server** – the final node that connects to the internet.
- **Relay server** – receives connections from end users and forwards them to the exit server.

Traffic flows:  
`End User → Relay → Exit → Internet`

All scripts use the **official Xray‑core** installer and manage Xray as a **systemd service**. Configuration files are stored in `/usr/local/etc/xray/config.json` (the standard path for official Xray installations).

---

## 📦 Prerequisites

- **Local machine** – Linux (Debian/Ubuntu recommended) with `sshpass` installed:
  ```bash
  sudo apt update && sudo apt install sshpass -y
  ```
- **Two remote servers** – both with **root** access (or a user with sudo privileges).  
  The scripts assume you can SSH as `root` (or a user who can run `systemctl` and write to `/usr/local/etc/xray`).
- **Open port 443** on both servers (the scripts do **not** automatically open it – you can uncomment the firewall lines inside `generate_config.sh` or do it manually).

---

## 🚀 Step 1 – Install Xray on both servers

Use `install_xray.sh` to install the official Xray release and enable the systemd service.

```bash
chmod +x install_xray.sh

# Install on exit server
./install_xray.sh <exit_ip> root "exit_password"

# Install on relay server
./install_xray.sh <relay_ip> root "relay_password"
```

The script will:
- Check if Xray is already installed.
- If not, download and install the latest release.
- Enable and start the `xray.service` (systemd).
- Verify that the service is running.

---

## 🔗 Step 2 – Generate the tunnel configuration

Run `generate_config.sh` **once** from your local machine. It will:
- Connect to both servers and generate fresh cryptographic keys (UUID, private/public keys, short IDs).
- Create configuration files for the exit and relay servers.
- Upload the configurations to `/usr/local/etc/xray/config.json`.
- Restart Xray on both servers using `systemctl`.
- Output a **working VLESS link** for the first end user.

```bash
chmod +x generate_config.sh

./generate_config.sh \
    <exit_ip> root "exit_password" \
    <relay_ip> root "relay_password"
```

**Example output:**
```
============================================
✅ Setup complete!
============================================
First user connection string (copy this):
vless://9f76bbd0-2b65-486f-8da0-79224c180b0c@<relay_ip>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.google.com&fp=chrome&pbk=uoTMexHksuFrfv5i4SLlvQLMOufkdSJnffZIVGS0ZS0&sid=ceda09afc6830e43#FirstUser
```

> 🧪 **Test the tunnel**  
> Use the generated VLESS link with any REALITY‑compatible client (e.g., `linv2`, Hiddify, Nekoray, v2rayNG).  
> Once connected, your public IP should be that of the **exit server**.

---

## 👥 Step 3 – Add more users

Use `add_user.sh` to add additional end users to the **relay server**. Each user gets a unique UUID and a VLESS link.

```bash
chmod +x add_user.sh

./add_user.sh <relay_ip> root "relay_password" "Alice"
```

The last parameter is a **username** (only used as a label in the generated link comment).

**Example output:**
```
============================================
✅ New user added successfully!
============================================
Connection string:
vless://6a74ad1e-4fd1-4b3f-8be4-ab9fcbf3f564@<relay_ip>:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.google.com&fp=chrome&pbk=uoTMexHksuFrfv5i4SLlvQLMOufkdSJnffZIVGS0ZS0&sid=ceda09afc6830e43#Alice
```

You can run this script as many times as needed. Each new user will be appended to the `clients` array in the relay’s inbound configuration.

---

## 🧹 Maintenance & Troubleshooting

### Check Xray service status
```bash
# On either server
systemctl status xray
```

### View logs
```bash
journalctl -u xray -f
```

### Restart Xray manually
```bash
systemctl restart xray
```

### Test the tunnel from the command line (using `linv2`)
```bash
# Install linv2 (once)
curl -fsSL -o linv2.sh https://raw.githubusercontent.com/yxnjm/linv2/main/linv2.sh && chmod +x linv2.sh

# Connect using a VLESS link
sudo ./linv2.sh -vless "vless://..."

# In another terminal, test your public IP
curl --socks5-hostname 127.0.0.1:2080 https://api.ipify.org
```
The returned IP should be the **exit server’s IP**.

### Remove a user
Manually edit `/usr/local/etc/xray/config.json` on the relay server and delete the corresponding `{"id": "...", "flow": "..."}` block from the `inbounds[0].settings.clients` array. Then restart Xray.

---

## 🔧 Scripts Overview

| Script | Purpose | Arguments |
|--------|---------|-----------|
| `install_xray.sh` | Installs Xray‑core as a systemd service | `<ip> <user> <pass>` |
| `generate_config.sh` | Creates the multi‑hop tunnel (exit + relay) | `<exit_ip> <exit_user> <exit_pass> <relay_ip> <relay_user> <relay_pass>` |
| `add_user.sh` | Adds a new end user on the relay server | `<relay_ip> <relay_user> <relay_pass> <username>` |

All scripts use `sshpass` for password‑based SSH. For production, consider switching to **SSH keys**.

---

## 📁 Important Paths

- **Xray binary:** `/usr/local/bin/xray`
- **Configuration:** `/usr/local/etc/xray/config.json`
- **Systemd service:** `/etc/systemd/system/xray.service` (created by official installer)

---

## 🛡️ Security Notes

- The relay server’s **private key** is stored in its config file. Keep it safe.
- The exit server’s **private key** is also stored; protect it.
- REALITY camouflage uses `www.google.com` for the relay and `www.microsoft.com` for the exit. You can change these `dest` values inside `generate_config.sh` if needed.
- Firewall: ensure TCP port `443` is open on both servers (the scripts leave this to you – uncomment the firewall lines in `generate_config.sh` if you want automatic configuration with `ufw` or `iptables`).

---

## 🎉 Final Words

You now have a fully functional multi‑hop VLESS+REALITY tunnel.  
The setup is **reproducible** and **scripted** – you can redeploy at any time with a few commands.

If you encounter the dreaded `received real certificate` error, it means a key mismatch (public key does not correspond to the server’s private key). The included scripts **avoid this** by deriving public keys directly from the private keys they generate.

Enjoy your private, censorship‑resistant tunnel! 🚀