
# Xray Multi‑Hop Tunnel (VLESS+REALITY)

Two servers: **Exit** (final internet hop) and **Relay** (receives users).  
Traffic: `User → Relay → Exit → Internet`.

Scripts use official Xray‑core + systemd. Config path: `/usr/local/etc/xray/config.json`.

---

## 📁 Files & What They Do

| File | Purpose |
|------|---------|
| `install_xray.sh` | Installs Xray on a remote server (systemd). |
| `sni.json` | Local file – list of allowed SNI domains for the relay (JSON array). First entry = camouflage `dest`. |
| `generate_config.sh` | Reads `sni.json`, generates keys, configures both servers, creates first user. |
| `add_user.sh` | Adds a new user (UUID) to relay. Accepts optional SNI (must be in `sni.json`). |

---

## 🔧 Prerequisites (local machine)

```bash
sudo apt update && sudo apt install sshpass jq -y
```

- Two remote servers with **root** SSH access.
- Port **443** open on both servers (do manually or uncomment firewall lines in `generate_config.sh`).

---

## 🚀 Order of Execution

1. **Install Xray on both servers**  
   ```bash
   ./install_xray.sh <exit_ip> root "exit_pass"
   ./install_xray.sh <relay_ip> root "relay_pass"
   ```

2. **Create `sni.json`** (example)  
   ```bash
   echo '["www.google.com","ya.ru","dzen.ru","www.microsoft.com"]' > sni.json
   ```

3. **Generate tunnel + first user**  
   ```bash
   ./generate_config.sh <exit_ip> root "exit_pass" <relay_ip> root "relay_pass"
   ```
   → Outputs a working VLESS link (use it to test).

4. **Add more users (optional)**  
   ```bash
   # Default SNI (first from sni.json)
   ./add_user.sh <relay_ip> root "relay_pass" "Alice"
   
   # Specific SNI
   ./add_user.sh <relay_ip> root "relay_pass" "Bob" ya.ru
   ```

---

## 📌 Script Arguments

- `install_xray.sh` `<ip> <username> <password>`
- `generate_config.sh` `<exit_ip> <exit_user> <exit_pass> <relay_ip> <relay_user> <relay_pass>`
- `add_user.sh` `<relay_ip> <relay_user> <relay_pass> <username> [sni]`

All scripts use `sshpass` (password‑based SSH). For production, switch to SSH keys.

---

## 🔍 Notes

- `encryption=none` is correct – REALITY provides encryption.
- Keys are derived automatically (no mismatches).
- Relay accepts any `sni` listed in `sni.json`.
- No backup created in `add_user.sh` – keep your `sni.json` and re‑run scripts if needed.

---

## Connection
Use AmneziaVPN, copy generated connection string to 'InsertKey' field and press connect.
