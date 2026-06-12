#!/bin/bash
# ============================================================
# add_many_users_relay.sh - Batch add multiple users to the Xray relay server
# Usage: ./add_many_users_relay.sh <relay_ip> <relay_user> <relay_pass> <user_name> <count>
# ============================================================

if [ $# -ne 5 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <relay_ip> <relay_user> <relay_pass> <user_name> <count>"
    exit 1
fi

RELAY_IP="$1"
RELAY_USER="$2"
RELAY_PASS="$3"
BASE_NAME="$4"
COUNT="$5"

# Validate that count is a positive integer
if ! [[ "$COUNT" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: <count> must be a positive integer greater than 0."
    exit 1
fi

# Check if the child script exists in the current directory
if [ ! -f "add_user_relay.sh" ]; then
    echo "Error: add_user_relay.sh not found in the current directory."
    echo "Please ensure you are running this script from the same folder as add_user_relay.sh."
    exit 1
fi

# Ensure the child script is executable
chmod +x add_user_relay.sh

echo "============================================"
echo "🚀 Starting batch creation of $COUNT users..."
echo "Base name: $BASE_NAME"
echo "Target server: $RELAY_IP"
echo "============================================"

SUCCESS_COUNT=0
FAIL_COUNT=0

for (( i=1; i<=COUNT; i++ )); do
    CURRENT_USER="${BASE_NAME}_${i}"
    
    echo ""
    echo "------------------------------------------------------------"
    echo "➡️ Creating user $i/$COUNT: $CURRENT_USER"
    echo "------------------------------------------------------------"
    
    # Call the single user script
    # We pass exactly 4 arguments, so it will automatically use the server's default SNI
    ./add_user_relay.sh "$RELAY_IP" "$RELAY_USER" "$RELAY_PASS" "$CURRENT_USER"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully created $CURRENT_USER"
        ((SUCCESS_COUNT++))
    else
        echo "❌ Failed to create $CURRENT_USER. Continuing to next..."
        ((FAIL_COUNT++))
    fi
done

echo ""
echo "============================================"
echo "🏁 Batch creation complete!"
echo "============================================"
echo "🟢 Successfully created: $SUCCESS_COUNT users"
if [ $FAIL_COUNT -gt 0 ]; then
    echo "🔴 Failed to create:   $FAIL_COUNT users"
fi
echo ""
echo "💡 All generated gRPC connection links have been saved as .vpn files"
echo "   in the 'xray_grpc/' directory."
echo "============================================"