Automate Pi Backups
Djn-

Usage:
system_backup.sh [device] [backup_path] [retention_days] [compression]

   - device:           Optional. Default is /dev/mmcblk0
   - backup_path:      Optional. Default is /mnt/pi
   - retention_days:   Optional. Default is 365
   - compression:      Optional. true or false. Default is true

 Examples:
  - system_backup.sh                          # Run with all defaults
  - system_backup.sh /dev/sda                 # Override device only
  - system_backup.sh /dev/sda /mnt/backups    # Override device and backup path
  - system_backup.sh /dev/sda /mnt/backups 180 false  # Full control

Install
- wget -qO /usr/local/bin/system_backup.sh https://raw.githubusercontent.com/djnaff/Pibackup/refs/heads/main/system_backup.sh && chmod +x /usr/local/bin/system_backup.sh
