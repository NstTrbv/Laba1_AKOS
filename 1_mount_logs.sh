#!/bin/bash
IMG=/var/logs_disk.img

if [ "$EUID" -ne 0 ]; then
    echo "Запустите через sudo"
    exit 1
fi

mkdir -p /LOGS

if [ ! -f $IMG ]; then
    truncate -s 512M $IMG
    mkfs.ext4 -q -F $IMG
fi

grep -q "$IMG" /etc/fstab || echo "$IMG /LOGS ext4 loop 0 0" >> /etc/fstab

mountpoint -q /LOGS || mount /LOGS

mkdir -p /LOGS/auth_service /LOGS/data_process_service /LOGS/system_event_handler_service

echo "Готово:"
df -h /LOGS
