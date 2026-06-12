#!/bin/bash

# ============================================================
# generate_config.sh - Set up Xray exit & relay servers (systemd)
# Usage: ./generate_config.sh <exit_ip> <exit_user> <exit_pass> <relay_ip> <relay_user> <relay_pass>
# ============================================================

set -e

if [ $# -ne 6 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <exit_ip> <exit_user> <exit_pass> <relay_ip> <relay_user> <relay_pass>"
    exit 1
fi

EXIT_IP="$1"
EXIT_USER="$2"
EXIT_PASS="$3"
RELAY_IP="$4"
RELAY_USER="$5"
RELAY_PASS="$6"

# Read RELAY_DOMAIN from .env safely
RELAY_DEST=$(grep '^RELAY_DOMAIN=' .env | cut -d'=' -f2 | tr -d '[:space:]')
if [ -z "$RELAY_DEST" ]; then
    echo "Error: RELAY_DOMAIN not found or empty in .env file."
    exit 1
fi

# Read and validate sni_exit.json
SNI_ARRAY_EXIT=$(cat sni_exit.json | tr -d '\n\r')
if ! echo "$SNI_ARRAY_EXIT" | jq -e . >/dev/null 2>&1; then
    echo "Error: sni_exit.json does not contain valid JSON."
    exit 1
fi
EXIT_DEST=$(echo "$SNI_ARRAY_EXIT" | jq -r '.[0]')
if [ -z "$EXIT_DEST" ] || [ "$EXIT_DEST" = "null" ]; then
    echo "Error: sni_exit.json array is empty."
    exit 1
fi

# Check sshpass
if ! command -v sshpass &> /dev/null; then
    echo "Error: 'sshpass' not installed. Run: sudo apt install sshpass"
    exit 1
fi

ssh_cmd() {
    sshpass -p "$3" ssh -o StrictHostKeyChecking=no "$2@$1" "$4"
}
scp_file() {
    sshpass -p "$5" scp -o StrictHostKeyChecking=no "$1" "$2@$3:$4"
}

echo "============================================"
echo "Gathering information from exit server ($EXIT_IP)..."
echo "============================================"

EXIT_UUID=$(ssh_cmd "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "cat /proc/sys/kernel/random/uuid")
EXIT_PRIV=$(ssh_cmd "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "xray x25519 | awk '/PrivateKey/ {print \$2}'")
EXIT_PUB=$(ssh_cmd "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "echo '$EXIT_PRIV' | xargs -I {} xray x25519 -i {} | awk '/PublicKey/ {print \$3}'")
EXIT_SHORT=$(ssh_cmd "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "openssl rand -hex 8")

echo "  Exit UUID: $EXIT_UUID"
echo "  Exit PrivateKey: $EXIT_PRIV"
echo "  Exit PublicKey (derived): $EXIT_PUB"
echo "  Exit ShortID: $EXIT_SHORT"

echo ""
echo "============================================"
echo "Gathering information from relay server ($RELAY_IP)..."
echo "============================================"

RELAY_PRIV=$(ssh_cmd "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "xray x25519 | awk '/PrivateKey/ {print \$2}'")
RELAY_SHORT=$(ssh_cmd "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "openssl rand -hex 8")
FIRST_USER_UUID=$(ssh_cmd "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "cat /proc/sys/kernel/random/uuid")
RELAY_PUB=$(ssh_cmd "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "echo '$RELAY_PRIV' | xargs -I {} xray x25519 -i {} | awk '/PublicKey/ {print \$3}'")

echo "  Relay PrivateKey: $RELAY_PRIV"
echo "  Relay PublicKey (derived): $RELAY_PUB"
echo "  Relay ShortID: $RELAY_SHORT"
echo "  First user UUID: $FIRST_USER_UUID"

# Create exit config (PL)
echo ""
echo "Creating exit configuration..."
cat > /tmp/exit_config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$EXIT_UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "${EXIT_DEST}:443",
          "serverNames": $SNI_ARRAY_EXIT,
          "privateKey": "$EXIT_PRIV",
          "shortIds": ["$EXIT_SHORT"]
        }
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$EXIT_UUID", "flow": ""}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "dest": "${EXIT_DEST}:443",
          "serverNames": $SNI_ARRAY_EXIT,
          "privateKey": "$EXIT_PRIV",
          "shortIds": ["$EXIT_SHORT"]
        },
        "grpcSettings": {
          "serviceName": "xray_grpc_service"
        }
      }
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF

# Create relay config (RU) with first user added
echo "Creating relay configuration..."
cat > /tmp/relay_config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "tag": "user-inbound",
      "settings": {
        "clients": [{"id": "$FIRST_USER_UUID", "flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "$RELAY_DEST:8444",
          "serverNames": ["$RELAY_DEST"],
          "privateKey": "$RELAY_PRIV",
          "shortIds": ["$RELAY_SHORT"]
        }
      }
    },
    {
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vless",
      "tag": "user-inbound-grpc",
      "settings": {
        "clients": [{"id": "$FIRST_USER_UUID", "flow": ""}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "dest": "$RELAY_DEST:8444",
          "serverNames": ["$RELAY_DEST"],
          "privateKey": "$RELAY_PRIV",
          "shortIds": ["$RELAY_SHORT"]
        },
        "grpcSettings": {
          "serviceName": "xray_grpc_service"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "tag": "to-pl",
      "settings": {
        "vnext": [{
          "address": "$EXIT_IP",
          "port": 8443,
          "users": [{"id": "$EXIT_UUID", "encryption": "none"}]
        }]
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "serverName": "${EXIT_DEST}",
          "fingerprint": "chrome",
          "shortId": "$EXIT_SHORT",
          "publicKey": "$EXIT_PUB"
        },
        "grpcSettings": {
          "serviceName": "xray_grpc_service"
        }
      }
    },
    {"protocol": "freedom", "tag": "direct"}
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "inboundTag": ["user-inbound", "user-inbound-grpc"],
        "outboundTag": "to-pl"
      }
    ]
  }
}
EOF

echo ""
echo "============================================"
echo "Copying configs to servers..."
echo "============================================"

ssh_cmd "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "mkdir -p /usr/local/etc/xray"
ssh_cmd "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "mkdir -p /usr/local/etc/xray"

scp_file "/tmp/exit_config.json" "$EXIT_USER" "$EXIT_IP" "/usr/local/etc/xray/config.json" "$EXIT_PASS"
echo "Exit config uploaded to /usr/local/etc/xray/config.json"
scp_file "/tmp/relay_config.json" "$RELAY_USER" "$RELAY_IP" "/usr/local/etc/xray/config.json" "$RELAY_PASS"
echo "Relay config uploaded to /usr/local/etc/xray/config.json"

rm -f /tmp/exit_config.json /tmp/relay_config.json

echo ""
echo "============================================"
echo "Opening firewall ports (443, 8443)..."
echo "============================================"
open_firewall() {
  ssh_cmd "$1" "$2" "$3" "ufw allow 443/tcp && ufw allow 8443/tcp || { iptables -A INPUT -p tcp --dport 443 -j ACCEPT; iptables -A INPUT -p tcp --dport 8443 -j ACCEPT; }"
}
open_firewall "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS"
open_firewall "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS"

echo ""
echo "============================================"
echo "Restarting Xray via systemd..."
echo "============================================"

restart_xray() {
    local ip="$1" user="$2" pass="$3" name="$4"
    echo "Restarting Xray on $name ($ip)..."
    ssh_cmd "$ip" "$user" "$pass" "
        systemctl restart xray
        sleep 2
        systemctl is-active --quiet xray && echo '✅ Xray active' || { echo '❌ Xray failed'; journalctl -u xray -n 10 --no-pager; exit 1; }
    " || { echo "Error restarting Xray on $name"; exit 1; }
    echo "$name configured."
}

restart_xray "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "Relay server"
restart_xray "$EXIT_IP" "$EXIT_USER" "$EXIT_PASS" "Exit server"

# Generate VLESS link for the first user
VLESS_LINK1="vless://${FIRST_USER_UUID}@${RELAY_DEST}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${RELAY_DEST}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}#FirstUser_TCP"
VLESS_LINK2="vless://${FIRST_USER_UUID}@${RELAY_DEST}:8443?encryption=none&security=reality&sni=${RELAY_DEST}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}&type=grpc&serviceName=xray_grpc_service&mode=gun#FirstUser_gRPC"

echo ""
echo "============================================"
echo "✅ Setup complete!"
echo "============================================"
echo "First user connection strings (copy these):"
echo "1. TCP + REALITY (Fallback):"
echo "$VLESS_LINK1"
echo ""
echo "2. gRPC + REALITY (Primary/Resilient):"
echo "$VLESS_LINK2"
echo ""
echo "Tunnel active: users connecting to $RELAY_IP will exit via $EXIT_IP."
echo "To add more users, run: ./add_user.sh $RELAY_IP $RELAY_USER <pass>"
echo "============================================"