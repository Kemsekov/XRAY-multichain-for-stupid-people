#!/bin/bash

# ============================================================
# add_user.sh - Add a new user to the Xray tunnel (relay server)
# Usage: ./add_user.sh <relay_ip> <relay_user> <relay_pass>
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

# Check for sni_exit.json file
if [ ! -f "sni_exit.json" ]; then
    echo "Error: sni_exit.json not found. Please create it with allowed SNI values."
    exit 1
fi

# Read and parse allowed SNIs from sni.json
ALLOWED_SNIS=$(jq -r '.[]' sni_exit.json)
FIRST_SNI=$(jq -r '.[0]' sni_exit.json)

if [ -z "$FIRST_SNI" ] || [ "$FIRST_SNI" = "null" ]; then
    echo "Error: sni_exit.json is empty or invalid."
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


if ! command -v sshpass &> /dev/null; then
    echo "Error: 'sshpass' not installed. Run: sudo apt install sshpass"
    exit 1
fi

ssh_cmd() {
    sshpass -p "$RELAY_PASS" ssh -o StrictHostKeyChecking=no "$RELAY_USER@$RELAY_IP" "$1"
}

echo "============================================"
echo "Adding a new user to relay server ($RELAY_IP)"
echo "============================================"

# Install jq if missing
echo "Ensuring jq is installed..."
ssh_cmd "
    if ! command -v jq &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq jq
    fi
"

# Generate new UUID
NEW_UUID=$(ssh_cmd "cat /proc/sys/kernel/random/uuid")
echo "Generated UUID: $NEW_UUID"

# Update config (no backup)
echo "Updating /usr/local/etc/xray/config.json..."
ssh_cmd "
    CONFIG=/usr/local/etc/xray/config.json
    jq --arg uuid '$NEW_UUID' \
       '.inbounds[0].settings.clients += [{\"id\": \$uuid, \"flow\": \"xtls-rprx-vision\"}]' \
       \$CONFIG > /tmp/config.tmp
    mv /tmp/config.tmp \$CONFIG
"

# Quick validation (optional, but keeps safety)
ssh_cmd "xray run -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1 || { echo 'Config invalid'; exit 1; }"

# Restart Xray
echo "Restarting Xray..."
ssh_cmd "systemctl restart xray && sleep 2 && systemctl is-active --quiet xray"
echo "Xray restarted successfully."

# Retrieve public key and short ID
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

# Generate VLESS link
VLESS_LINK="vless://${NEW_UUID}@${RELAY_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${USE_SNI}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}#${USERNAME}"

echo ""
echo "============================================"
echo "✅ New user added successfully!"
echo "============================================"
echo "Connection string:"
echo "$VLESS_LINK"
echo ""
echo "Manual parameters:"
echo "  Address:    $RELAY_IP"
echo "  Port:       443"
echo "  Protocol:   VLESS"
echo "  UUID:       $NEW_UUID"
echo "  Flow:       xtls-rprx-vision"
echo "  Security:   reality"
echo "  SNI:        www.google.com"
echo "  Fingerprint: chrome"
echo "  Public Key: $RELAY_PUB"
echo "  Short ID:   $RELAY_SHORT"
echo "============================================"