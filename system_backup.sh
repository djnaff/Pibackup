#!/bin/bash
#
# Automate Pi Backups
# Djn-
#
# Usage:
#   /system_backup.sh [device] [backup_path] [retention_days] [compression]
#
#   - device:           Optional. Default is /dev/mmcblk0
#   - backup_path:      Optional. Default is /mnt/pi
#   - retention_days:   Optional. Default is 365
#   - compression:      Optional. true or false. Default is true
#
# Examples:
#   system_backup.sh                          # Run with all defaults
#   system_backup.sh /dev/sda                 # Override device only
#   system_backup.sh /dev/sda /mnt/backups    # Override device and backup path
#   system_backup.sh /dev/sda /mnt/backups 180 false  # Full control

# Defaults can be changed
DEFAULT_DEVICE="/dev/mmcblk0"
DEFAULT_BACKUP_PATH="/mnt/pi" #must be on a mounted drive and not local
DEFAULT_RETENTION_DAYS=365
DEFAULT_COMPRESSION=true #takes a long time but recovers more space
PISHRINK_URL="https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh"
PISHRINK_SCRIPT="/tmp/pishrink.sh"
PISHRINK_CACHE="/usr/local/bin/pishrink.sh"

# Parse arguments
SD_DEVICE="${1:-$DEFAULT_DEVICE}"
BACKUP_PATH="${2:-$DEFAULT_BACKUP_PATH}"
RETENTION_DAYS="${3:-$DEFAULT_RETENTION_DAYS}"
COMPRESSION_ENABLED="${4:-$DEFAULT_COMPRESSION}"

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo -e "\n**********************************"
  echo "*** This script must be run as root! ***"
  echo "**********************************\n"
  exit 1
fi

# Check if device exists
if [[ ! -b "$SD_DEVICE" ]]; then
  echo "❌ Device $SD_DEVICE does not exist or is not a block device."
  exit 1
fi

# Ensure backup path exists
mkdir -p "$BACKUP_PATH" || {
  echo "❌ Failed to create backup directory: $BACKUP_PATH"
  exit 1
}

# Check if backup path is on local root filesystem
mnt=$(findmnt -n -o TARGET --target "$BACKUP_PATH")

if [[ "$mnt" == "/" ]]; then
  echo "❌ Error: Backup path ($BACKUP_PATH) is on the local root filesystem (local disk). Aborting."
  exit 1
else
  echo "✅ Backup path is on a mounted filesystem (mount point: $mnt)"
fi

# Check and install required PiShrink dependencies
echo "🔍 Checking PiShrink prerequisites..."
REQUIRED_PKGS=(wget parted gzip pigz xz-utils udev e2fsprogs)
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    MISSING_PKGS+=("$pkg")
  fi
done

if [ ${#MISSING_PKGS[@]} -ne 0 ]; then
  echo "📦 Installing missing packages: ${MISSING_PKGS[*]}"
  apt update && apt install -y "${MISSING_PKGS[@]}" || {
    echo "❌ Failed to install required packages."
    exit 1
  }
else
  echo "✅ All prerequisites are already installed."
fi

# Attempt to download latest PiShrink
echo "🌐 Downloading latest PiShrink..."
if curl -fsSL "$PISHRINK_URL" -o "$PISHRINK_SCRIPT"; then
  chmod +x "$PISHRINK_SCRIPT"
  cp "$PISHRINK_SCRIPT" "$PISHRINK_CACHE" 2>/dev/null
  echo "✅ PiShrink downloaded and cached at $PISHRINK_CACHE"
else
  echo "⚠️ Failed to download latest PiShrink."
  if [[ -x "$PISHRINK_CACHE" ]]; then
    echo "⚡ Using cached PiShrink from $PISHRINK_CACHE"
    cp "$PISHRINK_CACHE" "$PISHRINK_SCRIPT"
  else
    echo "❌ No cached PiShrink available. Aborting."
    exit 1
  fi
fi


# Create fsck trigger
touch /boot/forcefsck || {
  echo "❌ Failed to create fsck trigger."
  exit 1
}

# Generate backup file name with date and time
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_PATH/${HOSTNAME}.${TIMESTAMP}.img"

# Perform backup
echo "🔄 Backing up from $SD_DEVICE to: $BACKUP_FILE"
if ! dd if="$SD_DEVICE" | pv | dd of="$BACKUP_FILE" bs=1M; then
  echo "❌ Backup failed during dd."
  rm -f "$BACKUP_FILE"
  exit 1
fi

# Remove fsck trigger
rm -f /boot/forcefsck || echo "⚠️ Warning: Failed to remove fsck trigger."

# Shrink the image
echo "📦 Running PiShrink..."
if [[ "$COMPRESSION_ENABLED" == true ]]; then
  "$PISHRINK_SCRIPT" -az "$BACKUP_FILE"
else
  "$PISHRINK_SCRIPT" -a "$BACKUP_FILE"
fi

if [[ $? -ne 0 ]]; then
  echo "❌ PiShrink failed."
  exit 1
fi

# Delete old backups
echo "  Deleting backups older than $RETENTION_DAYS days..."
find "$BACKUP_PATH" -name "${HOSTNAME}.*.img" -type f -mtime +"$RETENTION_DAYS" -delete

echo "✅ Backup completed successfully: $BACKUP_FILE"

