#!/bin/bash
# ============================================================
# setup-caddy.sh - Set up Caddy with a fallback website for REALITY
# Usage: ./setup-caddy.sh <ip> <user> <password>
# ============================================================

set -e

if [ $# -ne 3 ]; then
    echo "Error: Invalid number of arguments."
    echo "Usage: $0 <ip> <user> <password>"
    exit 1
fi

IP="$1"
USER="$2"
PASS="$3"

# Check for .env and index.html
if [ ! -f ".env" ]; then
    echo "Error: .env file not found in current directory."
    exit 1
fi

if [ ! -f "index.html" ]; then
    echo "Error: index.html file not found in current directory."
    exit 1
fi

# Read RELAY_DOMAIN from .env safely
RELAY_DOMAIN=$(grep '^RELAY_DOMAIN=' .env | cut -d'=' -f2 | tr -d '[:space:]')
if [ -z "$RELAY_DOMAIN" ]; then
    echo "Error: RELAY_DOMAIN not found or empty in .env file."
    exit 1
fi

echo "🌐 Domain to configure: $RELAY_DOMAIN"

# Check sshpass
if ! command -v sshpass &> /dev/null; then
    echo "Error: 'sshpass' not installed. Run: sudo apt install sshpass"
    exit 1
fi

ssh_cmd() {
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$USER@$IP" "$1"
}

scp_file() {
    sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$1" "$USER@$IP:$2"
}

echo "============================================"
echo "Connecting to server ($IP)..."
echo "============================================"

# 1. Install Caddy (Debian/Ubuntu)
echo "📦 Installing Caddy..."
ssh_cmd "
if ! command -v caddy &> /dev/null; then
    sudo apt update -qq
    sudo apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    sudo apt update -qq
    sudo apt install -y -qq caddy
fi
"

# 2. Prepare web directory and upload index.html
echo "📂 Setting up web directory and uploading index.html..."
ssh_cmd "sudo mkdir -p /var/www/caddy_site"
scp_file "index.html" "/tmp/index.html"
ssh_cmd "sudo mv /tmp/index.html /var/www/caddy_site/index.html"
ssh_cmd "sudo chown -R caddy:caddy /var/www/caddy_site"
ssh_cmd "sudo chmod -R 755 /var/www/caddy_site"

# 3. Configure Caddyfile
echo "⚙️ Configuring Caddy to listen on port 8443..."
ssh_cmd "
cat > /tmp/Caddyfile <<EOF
${RELAY_DOMAIN}:8443 {
    root * /var/www/caddy_site
    file_server
}
EOF
sudo mv /tmp/Caddyfile /etc/caddy/Caddyfile
sudo chown root:caddy /etc/caddy/Caddyfile
sudo chmod 640 /etc/caddy/Caddyfile
"

# 4. Ensure port 80 is open for Let's Encrypt HTTP-01 challenge
echo "🔥 Ensuring port 80 is open for Let's Encrypt challenge..."
ssh_cmd "
if command -v ufw &> /dev/null; then
    sudo ufw allow 80/tcp || true
fi
"

# 5. Restart Caddy to apply config and fetch certificate
echo "🔄 Restarting Caddy (this may take a minute to fetch the Let's Encrypt certificate)..."
ssh_cmd "sudo systemctl restart caddy"
sleep 5

# Check if Caddy is running and cert is fetched
echo "🔍 Checking Caddy status..."
ssh_cmd "sudo systemctl is-active --quiet caddy && echo '✅ Caddy is active' || { echo '❌ Caddy failed'; sudo journalctl -u caddy -n 15 --no-pager; exit 1; }"

echo ""
echo "============================================"
echo "✅ Caddy setup complete!"
echo "============================================"
echo "Your fallback website is now live at:"
echo "👉 https://${RELAY_DOMAIN}:8443"
echo ""
echo "⚠️ CRITICAL NEXT STEPS FOR XRAY:"
echo "1. Update your Xray Relay config (realitySettings):"
echo "   - Change \"dest\" to: \"127.0.0.1:8443\""
echo "   - Add \"${RELAY_DOMAIN}\" to the \"serverNames\" array"
echo "2. Ensure Xray is NOT listening on port 80 (Caddy needs it for cert renewal)."
echo "3. Ensure Xray owns port 443, and Caddy owns port 8443."
echo "============================================"