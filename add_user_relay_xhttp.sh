#!/bin/bash

# ============================================================
# add_user_relay_xhttp.sh - Add a new user to XHTTP inbound (port 8443)
# Usage: ./add_user_relay_xhttp.sh <relay_ip> <relay_user> <relay_pass> <user_name> <sni>
# ============================================================

set -e

if [ $# -ne 5 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <relay_ip> <relay_user> <relay_pass> <user_name> <sni>"
    exit 1
fi

RELAY_IP="$1"
RELAY_USER="$2"
RELAY_PASS="$3"
USERNAME="$4"
REQUESTED_SNI="$5"

if ! command -v sshpass &> /dev/null; then
    echo "Error: 'sshpass' not installed. Run: sudo apt install sshpass"
    exit 1
fi

ssh_cmd() {
    sshpass -p "$RELAY_PASS" ssh -o StrictHostKeyChecking=no "$RELAY_USER@$RELAY_IP" "$1"
}

echo "============================================"
echo "Adding a new XHTTP user to relay server ($RELAY_IP)"
echo "============================================"

# Install jq if missing
echo "Ensuring jq is installed..."
ssh_cmd "
    if ! command -v jq &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq jq
    fi
"

# Fetch allowed SNI list from the second inbound (port 8443)
echo "Fetching allowed SNI list from server..."
SNI_ARRAY_JSON=$(ssh_cmd "
    jq -c '.inbounds[1].streamSettings.realitySettings.serverNames' /usr/local/etc/xray/config.json
")
if [ -z "$SNI_ARRAY_JSON" ] || [ "$SNI_ARRAY_JSON" = "null" ]; then
    echo "Error: Could not retrieve serverNames from second inbound. Make sure it exists."
    exit 1
fi

# Parse SNI list and first element
ALLOWED_SNIS=$(echo "$SNI_ARRAY_JSON" | jq -r '.[]')
FIRST_SNI=$(echo "$SNI_ARRAY_JSON" | jq -r '.[0]')

if [ -z "$FIRST_SNI" ] || [ "$FIRST_SNI" = "null" ]; then
    echo "Error: SNI list is empty."
    exit 1
fi

# Determine SNI to use
if [ -n "$REQUESTED_SNI" ]; then
    if echo "$ALLOWED_SNIS" | grep -qx "$REQUESTED_SNI"; then
        USE_SNI="$REQUESTED_SNI"
        echo "Using requested SNI: $USE_SNI"
    else
        echo "Warning: SNI '$REQUESTED_SNI' not in allowed list. Using default: $FIRST_SNI"
        USE_SNI="$FIRST_SNI"
    fi
else
    USE_SNI="$FIRST_SNI"
    echo "No SNI specified, using default: $USE_SNI"
fi

# Generate new UUID
NEW_UUID=$(ssh_cmd "cat /proc/sys/kernel/random/uuid")
echo "Generated UUID: $NEW_UUID"

# Update config (add to inbound index 1)
echo "Updating /usr/local/etc/xray/config.json (adding to second inbound)..."
ssh_cmd "
    CONFIG=/usr/local/etc/xray/config.json
    jq --arg uuid '$NEW_UUID' \
       '.inbounds[1].settings.clients += [{\"id\": \$uuid, \"flow\": \"\"}]' \
       \$CONFIG > /tmp/config.tmp
    mv /tmp/config.tmp \$CONFIG
"

# Validate configuration
ssh_cmd "xray run -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1 || { echo 'Config invalid'; exit 1; }"

# Restart Xray
echo "Restarting Xray..."
ssh_cmd "systemctl restart xray && sleep 2 && systemctl is-active --quiet xray"
echo "Xray restarted successfully."

# Retrieve public key and short ID (shared with first inbound)
RELAY_PUB=$(ssh_cmd "
    PRIV=\$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' /usr/local/etc/xray/config.json)
    echo \"\$PRIV\" | xargs -I {} xray x25519 -i {} | awk '/PublicKey/ {print \$3}'
")
RELAY_SHORT=$(ssh_cmd "
    jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' /usr/local/etc/xray/config.json
")

if [ -z "$RELAY_PUB" ] || [ -z "$RELAY_SHORT" ]; then
    echo "Error: Could not retrieve public key or short ID."
    exit 1
fi

# Generate VLESS link (for reference, though unlikely to work in most clients)
VLESS_LINK="vless://${NEW_UUID}@${RELAY_IP}:8443?encryption=none&security=reality&sni=${USE_SNI}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}#${USERNAME}"

# Generate JSON client configuration file
JSON_FILE="${USERNAME}_xhttp_config.json"
cat > "$JSON_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${RELAY_IP}",
            "port": 80,
            "users": [
              {
                "id": "${NEW_UUID}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "serverName": "${USE_SNI}",
          "fingerprint": "chrome",
          "publicKey": "${RELAY_PUB}",
          "shortId": "${RELAY_SHORT}"
        },
        "xhttpSettings": {
          "mode": "stream-up",
          "host": "${USE_SNI}",
          "path": "/download/updates",
          "headers": {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
          },
          "xPaddingBytes": "100-500",
          "xmux": {
            "maxConcurrency": 128,
            "hMaxRequestTimes": 1000,
            "hMaxReusableSecs": 3600
          }
        }
      }
    }
  ]
}
EOF

echo ""
echo "============================================"
echo "✅ New XHTTP user added successfully!"
echo "============================================"
echo "Username: $USERNAME"
echo "UUID: $NEW_UUID"
echo ""
echo "JSON configuration file saved as: $JSON_FILE"
echo ""
echo "To use:"
echo "  xray run -c $JSON_FILE"
echo ""
echo "Then set your SOCKS5 proxy to 127.0.0.1:10808"
echo ""
echo "VLESS link (may not work in many clients):"
echo "$VLESS_LINK"
echo "============================================"