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

cleanup() {
  echo "Syncing data back to the original folder and stopping the RAID 1 array..."
  sudo umount "${FOLDER_PATH}"
  sudo mdadm --stop /dev/md0
  sudo umount /dev/loop0
  sudo umount /dev/loop1
  sudo rsync -av --delete "/mnt/tmpfs$(basename "${FOLDER_PATH}")"/ "${FOLDER_PATH}"/
  sudo rm -r "/mnt/tmpfs$(basename "${FOLDER_PATH}")"
  echo "Cleanup completed."
}

# Register the cleanup function to be executed on exit or crash
trap cleanup EXIT SIGHUP SIGINT SIGTERM

# Wait for user input to terminate the script
read -p "Press [Enter] to stop the script and cleanup..."
