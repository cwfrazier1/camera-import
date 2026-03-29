# Camera Import

Auto-import photos from Nikon D7500 and Z5 when plugged into the Proxmox host. Backs up to Synology, uploads to Google Photos, Amazon Photos, Apple Photos, and Immich — all in parallel.

## How It Works

1. **USB plug-in** → udev rule detects camera and triggers `camera-import.sh`
2. **Import** → pulls all photos/videos via `gphoto2` (or mount fallback)
3. **Zip backup** → creates a zip archive and copies it to Synology NFS share
4. **Parallel uploads** → Google Photos, Amazon Photos, iCloud Drive, and Immich

Apple Photos is handled by uploading to iCloud Drive, where a macOS watcher script (`apple-photos-watcher.sh`) auto-imports new files into Photos.app.

## Files

| File | Purpose |
|------|---------|
| `camera-import.sh` | Main import/upload script (runs on Proxmox) |
| `camera-import.conf` | Configuration (paths, API keys, rclone remotes) |
| `99-nikon-cameras.rules` | udev rules for auto-detection |
| `setup.sh` | Installs everything on the Proxmox host |
| `apple-photos-watcher.sh` | macOS daemon that watches iCloud Drive and imports to Photos.app |
| `com.cwfrazier.apple-photos-watcher.plist` | launchd plist for the macOS watcher |

## Setup — Proxmox Host

```bash
# Clone and run setup as root
cd /opt
git clone https://github.com/cwfrazier1/camera-import.git
cd camera-import
sudo bash setup.sh
```

Then edit `/etc/camera-import.conf` with your actual paths and keys.

### rclone Remotes

Set up three rclone remotes:

```bash
# Google Photos
rclone config create gphotos google\ photos

# Amazon Photos (via Amazon Drive)
rclone config create amazon amazon\ cloud\ drive

# iCloud Drive (for Apple Photos pipeline)
rclone config create apple webdav \
  url=https://dav.icloud.com \
  vendor=other \
  user=YOUR_APPLE_ID \
  pass=$(rclone obscure YOUR_APP_SPECIFIC_PASSWORD)
```

### Synology NFS Mount

Add to `/etc/fstab`:

```
synology_ip:/volume1/backup  /mnt/synology/backup  nfs  defaults  0  0
```

### Immich

1. Go to your Immich instance → User Settings → API Keys
2. Create a new key and paste it into `/etc/camera-import.conf` as `IMMICH_API_KEY`

## Setup — macOS (Apple Photos)

On your Mac, install `fswatch` and the watcher:

```bash
brew install fswatch
# Load the auto-import daemon
cp com.cwfrazier.apple-photos-watcher.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.cwfrazier.apple-photos-watcher.plist
```

This watches `~/Library/Mobile Documents/com~apple~CloudDocs/camera-import/` and auto-imports any new photos into Photos.app.

## Manual Usage

```bash
# Auto-detect camera
camera-import.sh

# Specify camera
camera-import.sh d7500
camera-import.sh z5
```

## Logs

All activity is logged to `/var/log/camera-import.log` (configurable in conf).
