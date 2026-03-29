#!/bin/bash
# camera-import.sh — Auto-import photos from Nikon D7500/Z5
# Triggered by udev on USB plug-in or run manually.
#
# Usage: camera-import.sh [d7500|z5]
#   If no argument, auto-detects which camera is connected.

set -euo pipefail

# ── Load config ──
CONF="/etc/camera-import.conf"
if [[ -f "$CONF" ]]; then
    # shellcheck source=/dev/null
    source "$CONF"
else
    echo "ERROR: Config not found at $CONF" >&2
    echo "Copy camera-import.conf to /etc/camera-import.conf and configure it." >&2
    exit 1
fi

# ── Logging ──
LOG_FILE="${LOG_FILE:-/var/log/camera-import.log}"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "========== Camera import started =========="

# ── Determine camera ──
CAMERA="${1:-}"
if [[ -z "$CAMERA" ]]; then
    # Auto-detect via gphoto2
    if command -v gphoto2 &>/dev/null; then
        DETECTED=$(gphoto2 --auto-detect 2>/dev/null | tail -n +3 || true)
        if echo "$DETECTED" | grep -qi "d7500"; then
            CAMERA="d7500"
        elif echo "$DETECTED" | grep -qi "z 5\|z5"; then
            CAMERA="z5"
        fi
    fi

    # Fallback: check mount points
    if [[ -z "$CAMERA" ]]; then
        if [[ -d "$D7500_MOUNT" ]] && ls "$D7500_MOUNT"/* &>/dev/null; then
            CAMERA="d7500"
        elif [[ -d "$Z5_MOUNT" ]] && ls "$Z5_MOUNT"/* &>/dev/null; then
            CAMERA="z5"
        fi
    fi

    if [[ -z "$CAMERA" ]]; then
        log "ERROR: No camera detected. Plug in a camera or specify: $0 [d7500|z5]"
        exit 1
    fi
fi

CAMERA=$(echo "$CAMERA" | tr '[:upper:]' '[:lower:]')
log "Camera detected: $CAMERA"

# ── Create dated import directory ──
DATE_STAMP=$(date '+%Y-%m-%d')
BATCH_ID="${DATE_STAMP}_$(date '+%H%M%S')"
BATCH_DIR="${IMPORT_DIR}/${CAMERA}/${BATCH_ID}"
mkdir -p "$BATCH_DIR"
log "Import directory: $BATCH_DIR"

# ── Import photos ──
import_via_gphoto2() {
    log "Importing via gphoto2..."
    # Wait for camera to settle after USB plug-in
    sleep 3
    # Kill any gvfs process that may have grabbed the camera
    pkill -f "gvfs.*gphoto" 2>/dev/null || true
    sleep 1
    gphoto2 --get-all-files --filename "$BATCH_DIR/%f.%C" --skip-existing 2>&1
    log "gphoto2 import complete."
}

import_via_mount() {
    local mount_path
    case "$CAMERA" in
        d7500) mount_path="$D7500_MOUNT" ;;
        z5)    mount_path="$Z5_MOUNT" ;;
    esac

    log "Importing from mount: $mount_path"
    # Wait for mount to be ready
    for i in {1..30}; do
        if [[ -d "$mount_path" ]] && ls "$mount_path"/* &>/dev/null 2>&1; then
            break
        fi
        sleep 2
    done

    if [[ ! -d "$mount_path" ]]; then
        log "ERROR: Mount path $mount_path not available after 60s"
        exit 1
    fi

    # Copy all files (preserving directory structure from DCIM)
    find "$mount_path" -type f \( -iname "*.nef" -o -iname "*.jpg" -o -iname "*.jpeg" \
        -o -iname "*.mov" -o -iname "*.mp4" -o -iname "*.nrw" \) \
        -exec cp -n {} "$BATCH_DIR/" \;

    log "Mount-based import complete."
}

# Prefer gphoto2, fall back to mount
if command -v gphoto2 &>/dev/null; then
    import_via_gphoto2
else
    import_via_mount
fi

# ── Verify we got files ──
FILE_COUNT=$(find "$BATCH_DIR" -type f | wc -l)
if [[ "$FILE_COUNT" -eq 0 ]]; then
    log "WARNING: No files imported. Aborting."
    rmdir "$BATCH_DIR" 2>/dev/null || true
    exit 1
fi
log "Imported $FILE_COUNT files."

# ── Step 1: Zip backup to Synology ──
log "Creating zip backup..."
ARCHIVE_NAME="${CAMERA}_${BATCH_ID}.zip"
ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}"
mkdir -p "$ARCHIVE_DIR"
zip -r -j "$ARCHIVE_PATH" "$BATCH_DIR/"
log "Archive created: $ARCHIVE_PATH"

# Copy to Synology
if [[ -d "$SYNOLOGY_BACKUP_DIR" ]]; then
    mkdir -p "${SYNOLOGY_BACKUP_DIR}/${CAMERA}"
    cp "$ARCHIVE_PATH" "${SYNOLOGY_BACKUP_DIR}/${CAMERA}/"
    log "Backup copied to Synology: ${SYNOLOGY_BACKUP_DIR}/${CAMERA}/${ARCHIVE_NAME}"
else
    log "WARNING: Synology backup dir not mounted at $SYNOLOGY_BACKUP_DIR — skipping."
fi

# ── Step 2: Upload to Google Photos ──
upload_google_photos() {
    if ! command -v rclone &>/dev/null; then
        log "WARNING: rclone not installed — skipping Google Photos."
        return
    fi
    log "Uploading to Google Photos..."
    local album="${CAMERA}_${DATE_STAMP}"
    rclone copy "$BATCH_DIR" "${RCLONE_GOOGLE_PHOTOS}:album/${album}" \
        --verbose --ignore-existing 2>&1
    log "Google Photos upload complete (album: $album)."
}

# ── Step 3: Upload to Amazon Photos ──
upload_amazon_photos() {
    if ! command -v rclone &>/dev/null; then
        log "WARNING: rclone not installed — skipping Amazon Photos."
        return
    fi
    log "Uploading to Amazon Photos..."
    local dest_dir="Pictures/camera-import/${CAMERA}/${BATCH_ID}"
    rclone copy "$BATCH_DIR" "${RCLONE_AMAZON_PHOTOS}:${dest_dir}" \
        --verbose --ignore-existing 2>&1
    log "Amazon Photos upload complete."
}

# ── Step 4: Upload to Apple Photos (via iCloud Drive rclone) ──
upload_apple_photos() {
    if ! command -v rclone &>/dev/null; then
        log "WARNING: rclone not installed — skipping Apple Photos."
        return
    fi
    # Apple Photos has no direct API from Linux. Strategy:
    # Upload to iCloud Drive via rclone, then use a macOS shortcut/script
    # to auto-import from that folder into Photos.app.
    log "Uploading to iCloud Drive (for Apple Photos import)..."
    local dest_dir="camera-import/${CAMERA}/${BATCH_ID}"
    rclone copy "$BATCH_DIR" "${RCLONE_APPLE_PHOTOS}:${dest_dir}" \
        --verbose --ignore-existing 2>&1
    log "iCloud Drive upload complete. Files will auto-import to Photos.app via Folder Action."
}

# ── Step 5: Upload to Immich ──
upload_immich() {
    if [[ -z "${IMMICH_API_KEY:-}" ]]; then
        log "WARNING: IMMICH_API_KEY not set — skipping Immich."
        return
    fi

    log "Uploading to Immich at ${IMMICH_URL}..."

    # Use immich-cli if available, otherwise use the API directly
    if command -v immich &>/dev/null; then
        immich upload --server "$IMMICH_URL" --key "$IMMICH_API_KEY" "$BATCH_DIR" 2>&1
    else
        # Direct API upload
        local uploaded=0
        local failed=0
        for file in "$BATCH_DIR"/*; do
            [[ -f "$file" ]] || continue
            local filename
            filename=$(basename "$file")
            local mime
            mime=$(file --mime-type -b "$file")

            response=$(curl -s -w "%{http_code}" -o /dev/null \
                -X POST "${IMMICH_URL}/api/assets" \
                -H "x-api-key: ${IMMICH_API_KEY}" \
                -F "assetData=@${file};type=${mime}" \
                -F "deviceAssetId=${filename}" \
                -F "deviceId=camera-import-${CAMERA}" \
                -F "fileCreatedAt=$(stat -c %W "$file" 2>/dev/null || date -r "$file" '+%Y-%m-%dT%H:%M:%S')" \
                -F "fileModifiedAt=$(stat -c %Y "$file" 2>/dev/null || date -r "$file" '+%Y-%m-%dT%H:%M:%S')")

            if [[ "$response" =~ ^2 ]]; then
                ((uploaded++))
            else
                ((failed++))
                log "  Failed to upload: $filename (HTTP $response)"
            fi
        done
        log "Immich upload complete: $uploaded uploaded, $failed failed."
    fi
}

# ── Run uploads in parallel ──
log "Starting uploads..."
upload_google_photos &
PID_GP=$!
upload_amazon_photos &
PID_AP=$!
upload_apple_photos &
PID_APPLE=$!
upload_immich &
PID_IMMICH=$!

# Wait for all uploads
FAIL=0
for pid in $PID_GP $PID_AP $PID_APPLE $PID_IMMICH; do
    wait "$pid" || ((FAIL++))
done

if [[ "$FAIL" -gt 0 ]]; then
    log "WARNING: $FAIL upload(s) had errors. Check log for details."
else
    log "All uploads completed successfully."
fi

# ── Optional notification ──
if [[ "${NOTIFY_ON_COMPLETE:-no}" == "yes" ]] && [[ -n "${NOTIFY_EMAIL:-}" ]]; then
    echo "Camera import complete: $FILE_COUNT files from $CAMERA ($BATCH_ID)" \
        | mail -s "Camera Import Complete" "$NOTIFY_EMAIL"
fi

log "========== Camera import finished ($FILE_COUNT files from $CAMERA) =========="
