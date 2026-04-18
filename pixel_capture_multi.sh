#!/bin/bash
# =====================================================
# Pixel Auto Capture + Transfer Script (Mac/Linux)
# Supports MULTIPLE devices simultaneously
# Deletes photos from phone after successful pull
# =====================================================

# --- CONFIGURATION ---
SAVE_FOLDER="$HOME/PixelCaptures"
INTERVAL=7
# ---------------------

mkdir -p "$SAVE_FOLDER"

echo "====================================================="
echo " Pixel Multi-Device Auto Capture Script"
echo " Saving photos to: $SAVE_FOLDER"
echo " Interval: $INTERVAL seconds"
echo " Press CTRL+C to stop all devices"
echo "====================================================="
echo ""

# Get list of connected devices
DEVICES=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}')

if [ -z "$DEVICES" ]; then
    echo "ERROR: No devices found. Make sure your Pixels are connected"
    echo "and USB Debugging is enabled on each one."
    exit 1
fi

echo "Found devices:"
echo "$DEVICES"
echo ""

# Function to capture from a single device in a loop
capture_device() {
    DEVICE_ID=$1
    DEVICE_FOLDER="$SAVE_FOLDER/$DEVICE_ID"
    mkdir -p "$DEVICE_FOLDER"

    echo "[$DEVICE_ID] Starting capture..."

    while true; do
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

        # Take photo on this specific device
        adb -s "$DEVICE_ID" shell input keyevent 27

        # Wait for photo to save on device
        sleep 2

        # Get latest photo filename — strip ALL whitespace/control characters
        LATEST=$(adb -s "$DEVICE_ID" shell ls -t /sdcard/DCIM/Camera/ | head -1 | tr -d '\r\n\t ')

        if [ -z "$LATEST" ]; then
            echo "[$DEVICE_ID] WARNING: Could not get latest filename, skipping..."
            sleep $((INTERVAL - 2))
            continue
        fi

        # Pull to computer into device-specific subfolder
        adb -s "$DEVICE_ID" pull "/sdcard/DCIM/Camera/$LATEST" \
            "$DEVICE_FOLDER/photo_$TIMESTAMP.jpg" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo "[$DEVICE_ID] [$(date +%H:%M:%S)] Saved: photo_$TIMESTAMP.jpg"
            # Delete from phone only after successful pull
            adb -s "$DEVICE_ID" shell rm "/sdcard/DCIM/Camera/$LATEST"
        else
            echo "[$DEVICE_ID] WARNING: Pull failed for $LATEST — keeping on device"
        fi

        sleep $((INTERVAL - 2))
    done
}

# Launch a background process for each device
PIDS=()
for DEVICE_ID in $DEVICES; do
    capture_device "$DEVICE_ID" &
    PIDS+=($!)
    echo "Started capture for device: $DEVICE_ID (PID: $!)"
done

echo ""
echo "All devices running! Photos saved to subfolders by device ID."
echo "Press CTRL+C to stop all."

# Kill all background jobs on CTRL+C
trap 'echo ""; echo "Stopping all devices..."; kill "${PIDS[@]}"; exit 0' SIGINT SIGTERM
wait
