#!/bin/bash
# apple-photos-watcher.sh — Runs on macOS to auto-import files
# from iCloud Drive into Photos.app.
#
# Install: launchctl load apple-photos-watcher.plist
# This watches ~/Library/Mobile Documents/com~apple~CloudDocs/camera-import/
# and imports new files into Photos.app using AppleScript.

WATCH_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/camera-import"

if [[ ! -d "$WATCH_DIR" ]]; then
    echo "iCloud Drive camera-import folder not found. Creating..."
    mkdir -p "$WATCH_DIR"
fi

echo "Watching $WATCH_DIR for new photos..."

fswatch -0 --event Created "$WATCH_DIR" | while IFS= read -r -d '' file; do
    # Only process image/video files
    case "${file,,}" in
        *.jpg|*.jpeg|*.nef|*.nrw|*.mov|*.mp4|*.heic|*.png)
            echo "Importing to Photos.app: $file"
            osascript -e "
                tell application \"Photos\"
                    import POSIX file \"$file\"
                end tell
            " 2>/dev/null && echo "  Imported: $(basename "$file")"
            ;;
    esac
done
