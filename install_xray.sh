#!/bin/bash

# ============================================================
# install_xray.sh - Install Xray as a systemd service
# Usage: ./install_xray.sh <server_ip> <username> <password>
# ============================================================

set -e

if [ $# -ne 3 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <server_ip> <username> <password>"
    exit 1
fi

SERVER_IP="$1"
USERNAME="$2"
PASSWORD="$3"

if ! command -v sshpass &> /dev/null; then
    echo "Error: 'sshpass' is not installed."
    echo "Install it: sudo apt install sshpass   (or yum install sshpass)"
    exit 1
fi

echo "Connecting to $SERVER_IP as $USERNAME..."
echo ""

# Run the official Xray installation script
sshpass -p "$PASSWORD" ssh -t -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" "
    if command -v xray >/dev/null 2>&1; then
        echo '✅ Xray is already installed.'
        systemctl is-active --quiet xray && echo '✅ Xray service is running.' || echo '⚠️ Xray service is not active.'
    else
        echo 'Xray not found. Installing official Xray release...'
        bash -c \"\$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)\" @ install
        echo '✅ Installation complete.'
    fi

    # Ensure systemd service is enabled and started
    systemctl enable xray
    systemctl restart xray
    sleep 2
    if systemctl is-active --quiet xray; then
        echo '✅ Xray service is running and enabled.'
    else
        echo '❌ Xray service failed to start. Check logs: journalctl -u xray'
        exit 1
    fi
"

SSH_EXIT=$?

echo ""
if [ $SSH_EXIT -eq 0 ]; then
    echo "✅ Xray successfully installed/verified on $SERVER_IP with systemd service."
else
    echo "❌ Operation failed on $SERVER_IP (exit code: $SSH_EXIT)."
fi

exit $SSH_EXIT