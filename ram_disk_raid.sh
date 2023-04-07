#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root"
  exit 1
fi

# Check if a folder path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 /path/to/folder"
  exit 1
fi

# Store the folder path
FOLDER_PATH="$1"

# Create a directory in tmpfs to store a copy of the folder
mkdir "/mnt/tmpfs$(basename "${FOLDER_PATH}")"

# Copy the contents of the folder to the new directory in tmpfs
cp -r "${FOLDER_PATH}"/* "/mnt/tmpfs$(basename "${FOLDER_PATH}")"

# Bind the folders to loopback devices
sudo mount --bind "/mnt/tmpfs$(basename "${FOLDER_PATH}")" /dev/loop0
sudo mount --bind "${FOLDER_PATH}" /dev/loop1

# Create the RAID 1 array
sudo mdadm --create --verbose /dev/md0 --level=1 --raid-disks=2 /dev/loop0 /dev/loop1 -W /dev/loop1

# Mount the RAID 1 array to the folder
sudo mount /dev/md0 "${FOLDER_PATH}"

echo "RAID 1 array with RAM disk created and mounted at ${FOLDER_PATH}"

