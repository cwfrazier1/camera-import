#!/bin/bash
# setup.sh — Install camera-import on a Proxmox/Debian host
set -euo pipefail

echo "=== Camera Import Setup ==="

# ── Install dependencies ──
echo "Installing dependencies..."
apt-get update -qq
apt-get install -y gphoto2 rclone zip curl jq

# ── Install immich-cli (optional) ──
if command -v npm &>/dev/null; then
    echo "Installing immich-cli..."
    npm i -g @immich/cli || echo "WARNING: immich-cli install failed. API fallback will be used."
else
    echo "NOTE: npm not found. Immich uploads will use direct API (no immich-cli)."
fi

# ── Install scripts ──
echo "Installing camera-import.sh to /usr/local/bin/..."
cp camera-import.sh /usr/local/bin/camera-import.sh
chmod +x /usr/local/bin/camera-import.sh

# ── Install config ──
if [[ ! -f /etc/camera-import.conf ]]; then
    echo "Installing default config to /etc/camera-import.conf..."
    cp camera-import.conf /etc/camera-import.conf
    echo ">>> EDIT /etc/camera-import.conf with your paths and API keys <<<"
else
    echo "Config already exists at /etc/camera-import.conf — skipping."
fi

# ── Install udev rules ──
echo "Installing udev rules..."
cp 99-nikon-cameras.rules /etc/udev/rules.d/
udevadm control --reload-rules
udevadm trigger
echo "udev rules installed. Cameras will auto-trigger on USB plug-in."

# ── Create directories ──
source /etc/camera-import.conf
mkdir -p "$IMPORT_DIR" "$ARCHIVE_DIR"
echo "Created import directories."

# ── Create log file ──
touch "$LOG_FILE"
chmod 666 "$LOG_FILE"

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit /etc/camera-import.conf with your settings"
echo "  2. Configure rclone remotes:"
echo "     rclone config  (set up: gphotos, amazon, apple)"
echo "  3. Set your Immich API key in the config"
echo "  4. Mount your Synology backup share"
echo "  5. Plug in your camera!"
