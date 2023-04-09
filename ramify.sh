#!/bin/bash

# Parsing optional arguments
while getopts ":s:" OPTIONS; do
    case $OPTIONS in
        s)
            echo "User size: $OPTARG"
            USER_SIZE=$OPTARG
            ;;
        *)
            echo "Invalid option: -$OPTARG" >&2
            exit 2
            ;;
    esac
done

# Shift the optional arguments
shift $((OPTIND - 1))

# Check if required argument is provided
if [ $# -eq 0 ]; then
    echo "Error: No target directory provided." >&2
    usage
    exit 1
fi

TARGET_PATH="${1}"

# Setting variables for target and shadow paths, and owner/group
TARGET_PATH="${1}"
SHADOW_PATH="${1}.ramify"
USER=$(stat -c '%U' "${TARGET_PATH}")
GROUP=$(stat -c '%G' "${TARGET_PATH}")

function usage() {
    echo "Usage: $0 [-s size] <target_directory>"
    echo "  -s size: Optional, define the RAM disk size in kilobytes."
    echo "  <target_directory>: The directory to be ramified."
}

# Cleanup function to handle script termination
function cleanup() {
    echo "***CLEANUP CALLED***"
    rsync -av --delete "${TARGET_PATH}"/ "${SHADOW_PATH}"/
    umount "${TARGET_PATH}" && mv "${SHADOW_PATH}/*" "${TARGET_PATH}/"
    exit
}

# Calculate folder size and RAM disk size
SIZE=$(du -s "${TARGET_PATH}" | cut -f 1)
RAM_SIZE=$(python -c 'import sys; size=int(sys.argv[1]); print(int(size+(0.1*size)));' "$SIZE")

# Use user-defined size if provided
if [ $USER_SIZE -gt 0 ]; then
    RAM_SIZE=$USER_SIZE
fi
#
# Check for open files in the target folder
open_files=$(lsof "${TARGET_PATH}" 2>/dev/null | wc -l)
if [ $open_files -gt 0 ]; then
    echo "There are $open_files open files in the target folder. Please close them before proceeding."
    exit 1
fi

# Move target folder to shadow folder and set trap for cleanup
mkdir "${SHADOW_PATH}"
chown $USER:$GROUP "${SHADOW_PATH}"
mv "${TARGET_PATH}/"* "${SHADOW_PATH}/"
trap cleanup SIGHUP SIGINT SIGTERM

# Create and mount tmpfs at the target location
mkdir "${TARGET_PATH}"
mount -t tmpfs -o size=${RAM_SIZE}k tmpfs "${TARGET_PATH}"
chown $USER:$GROUP "${TARGET_PATH}"

# Check for mounting errors
if [ $? -ne 0 ]; then
    echo "Failed to mount tmpfs on ${TARGET_PATH}"
    exit 1
fi

# Rsync the contents of the shadow folder to the RAM disk
rsync -a --progress "${SHADOW_PATH}"/ "${TARGET_PATH}"/

# Sync changes between the RAM disk and the shadow folder
while true; do
    inotifywait -r -e modify,attrib,close_write,move,create,delete "${TARGET_PATH}"
    rsync -av --delete "${TARGET_PATH}"/ "${SHADOW_PATH}"/
    sleep 300s
    rsync -av --delete "${TARGET_PATH}"/ "${SHADOW_PATH}"/
done
