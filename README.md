# RAMify

RAMify is a script that allows you to cache a folder's contents in a RAM disk to improve read performance. It creates a shadow folder on the disk that mirrors the contents of the RAM disk and syncs any changes back to the shadow folder.

## Usage

``` bash
./ramify.sh [-s <size>] /path/to/folder

```

### Options

- `-s <size>`: Optional. Specify the size (in KB) of the tmpfs mount (RAM disk). If not specified, the script will calculate the size based on the folder size, adding a 10% buffer.

### Arguments

- `/path/to/folder`: The folder you want to cache in the RAM disk.

## How it works

1. Moves the target folder to a shadow folder (with a `.ramify` suffix).
2. Creates a tmpfs mount (RAM disk) at the target folder's original location.
3. Copies the contents of the shadow folder to the RAM disk.
4. Uses `inotifywait` to monitor changes in the RAM disk.
5. Syncs the changes from the RAM disk back to the shadow folder using `rsync`.

## Prerequisites

- Bash
- Python (used for calculating the RAM disk size)
- Inotify tools (`inotifywait` command)
- Rsync

## Installation

1. Save the script as `ramify.sh`.
2. Make the script executable with `chmod +x ramify.sh`.

## Example

Cache the contents of the folder `/path/to/your-folder` in a RAM disk:

``` bash
sudo ./ramify.sh /path/to/your-folder
```

Cache the contents of the folder `/path/to/your-folder` in a RAM disk with a user-defined size of 2048 KB:

``` bash
sudo ./ramify.sh -s 2048 /path/to/your-folder
```

## Notes

- The script must be run as root (or with sudo) to create the tmpfs mount and move the original folder.
- If the script is interrupted or terminated, it will automatically sync the contents of the RAM disk back to the shadow folder, unmount the tmpfs, and move the shadow folder back to its original location.


# RAM Disk RAID

This script creates a RAID 1 array with a RAM disk and a folder on your filesystem. It is designed to improve read performance while still retaining data durability in case of a crash.

## Usage

``` bash
sudo ./ram_disk_raid.sh /path/to/folder
```


### Arguments

- `/path/to/folder`: The folder you want to include in the RAID 1 array with a RAM disk.

## How it works

1. Creates a directory in the `/mnt/tmpfs` folder to store a copy of the target folder.
2. Copies the contents of the target folder to the new directory in the `/mnt/tmpfs` folder.
3. Binds the folders to loopback devices (e.g., `/dev/loop0` and `/dev/loop1`).
4. Creates a RAID 1 array using the loopback devices, marking the real disk folder as "write-mostly".
5. Mounts the RAID 1 array to the original folder location.

## Prerequisites

- Bash
- mdadm

## Installation

1. Save the script as `ram_disk_raid.sh`.
2. Make the script executable with `chmod +x ram_disk_raid.sh`.

## Example

Create a RAID 1 array with a RAM disk for the folder `/path/to/your-folder`:

```bash
sudo ./ram_disk_raid.sh /path/to/your-folder
```

## Notes

- The script must be run as root (or with sudo) to create the RAID 1 array and mount it.
- The script does not implement automatic syncing or cleanup on exit. If you need to update the original folder, you will need to manually stop the RAID 1 array and sync the data back to the folder.
