#!/bin/bash
# ============================================================
# add_user_relay.sh - Add a new user to the Xray relay server
# Usage: ./add_user_relay.sh <relay_ip> <relay_user> <relay_pass> <user_name> [sni]
# ============================================================

set -e

if [ $# -lt 4 ] || [ $# -gt 5 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <relay_ip> <relay_user> <relay_pass> <user_name> [sni]"
    exit 1
fi

RELAY_IP="$1"
RELAY_USER="$2"
RELAY_PASS="$3"
USERNAME="$4"
REQUESTED_SNI="${5:-}"

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

# Install jq on the server if missing
echo "Ensuring jq is installed on the server..."
ssh_cmd "
if ! command -v jq &> /dev/null; then
    apt-get update -qq && apt-get install -y -qq jq
fi
"

# Fetch the default SNI directly from the server's config
echo "Fetching SNI from server configuration..."
SERVER_SNI=$(ssh_cmd "jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' /usr/local/etc/xray/config.json")

if [ -z "$SERVER_SNI" ] || [ "$SERVER_SNI" = "null" ]; then
    echo "Error: Could not retrieve SNI from server config."
    exit 1
fi

# Determine SNI to use
if [ -n "$REQUESTED_SNI" ]; then
    # Validate if requested SNI is in the server's allowed list
    ALLOWED_SNIS=$(ssh_cmd "jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[]' /usr/local/etc/xray/config.json")
    if echo "$ALLOWED_SNIS" | grep -qx "$REQUESTED_SNI"; then
        USE_SNI="$REQUESTED_SNI"
        echo "Using requested SNI: $USE_SNI"
    else
        echo "Warning: SNI '$REQUESTED_SNI' not in server's allowed list. Using default: $SERVER_SNI"
        USE_SNI="$SERVER_SNI"
    fi
else
    USE_SNI="$SERVER_SNI"
    echo "No SNI specified, using server default: $USE_SNI"
fi

# Generate new UUID
NEW_UUID=$(ssh_cmd "cat /proc/sys/kernel/random/uuid")
echo "Generated UUID: $NEW_UUID"

# Update config to add user to BOTH inbounds (TCP on 443, gRPC on 8443)
echo "Updating /usr/local/etc/xray/config.json..."
ssh_cmd "
CONFIG=/usr/local/etc/xray/config.json

# Add to first inbound (TCP, port 443)
jq --arg uuid '$NEW_UUID' \
'.inbounds[0].settings.clients += [{\"id\": \$uuid, \"flow\": \"xtls-rprx-vision\"}]' \
\$CONFIG > /tmp/config.tmp

# Add to second inbound (gRPC, port 8443) if it exists
if jq -e '.inbounds[1]' \$CONFIG > /dev/null 2>&1; then
    jq --arg uuid '$NEW_UUID' \
    '.inbounds[1].settings.clients += [{\"id\": \$uuid, \"flow\": \"\"}]' \
    /tmp/config.tmp > /tmp/config.tmp2
    mv /tmp/config.tmp2 \$CONFIG
else
    mv /tmp/config.tmp \$CONFIG
fi
"

# Quick validation
echo "Validating configuration..."
ssh_cmd "xray run -test -config /usr/local/etc/xray/config.json > /dev/null 2>&1 || { echo '❌ Config invalid'; exit 1; }"
echo "✅ Config is valid."

# Restart Xray
echo "Restarting Xray..."
ssh_cmd "systemctl restart xray && sleep 2 && systemctl is-active --quiet xray"
echo "✅ Xray restarted successfully."

# Retrieve public key and short ID from the first inbound
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

# Generate VLESS links
VLESS_LINK_TCP="vless://${NEW_UUID}@${RELAY_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${USE_SNI}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}#${USERNAME}_Relay_TCP"
VLESS_LINK_GRPC="vless://${NEW_UUID}@${RELAY_IP}:8443?encryption=none&security=reality&sni=${USE_SNI}&fp=chrome&pbk=${RELAY_PUB}&sid=${RELAY_SHORT}&type=grpc&serviceName=xray_grpc_service&mode=gun#${USERNAME}_Relay_gRPC"

echo ""
echo "============================================"
echo "✅ New user added to relay server!"
echo "============================================"
echo "Connection strings (via Relay to Exit):"
echo ""
echo "1. TCP + REALITY (Port 443):"
echo "$VLESS_LINK_TCP"
echo ""
echo "2. gRPC + REALITY (Port 8443 - Resilient):"
echo "$VLESS_LINK_GRPC"
echo ""
echo "Manual parameters:"
echo "  Address:    $RELAY_IP"
echo "  UUID:       $NEW_UUID"
echo "  SNI:        $USE_SNI"
echo "  Public Key: $RELAY_PUB"
echo "  Short ID:   $RELAY_SHORT"
echo "============================================"