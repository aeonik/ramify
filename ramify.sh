#!/bin/bash
set -x

function usage() {
    echo "Usage: $0 [-s size] <target_directory>"
    echo "  -s size: Optional, define the RAM disk size in kilobytes."
    echo "  <target_directory>: The directory to be ramified."
}

# Parsing optional arguments
USER_SIZE=0
while getopts ":s:" OPTIONS; do
    case $OPTIONS in
        s)
            echo "User size: $OPTARG"
            USER_SIZE=$OPTARG
            ;;
        *)
            echo "Invalid option: -$OPTARG" >&2
            usage
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

# Setting variables for target and shadow paths, and owner/group
TARGET_PATH="${1}"
SHADOW_PATH=".${1}.ramify"


if [[ "$OSTYPE" == "darwin"* ]]; then
    USER=$(stat -f '%Su' "${TARGET_PATH}")
    GROUP=$(stat -f '%Sg' "${TARGET_PATH}")
else
    USER=$(stat -c '%U' "${TARGET_PATH}")
    GROUP=$(stat -c '%G' "${TARGET_PATH}")
fi

cleanup() {
    echo '***CLEANUP CALLED***'

    # Sync changes back to the shadow folder
    rsync -av --delete --exclude .fseventsd "${TARGET_PATH}"/ "${SHADOW_PATH}"/

    # Check if the directory is still mounted before attempting to unmount
    if mount | grep "on ${TARGET_PATH}"; then
        umount "${TARGET_PATH}"
    fi

    # Remove the RAM disk
    if [[ "$OSTYPE" == "darwin"* ]]; then
        hdiutil detach "${DEVICE}"
    fi

    # Move the contents of the shadow folder back to the target folder
    shopt -s dotglob
    mv "${SHADOW_PATH}"/* "${TARGET_PATH}/"
    shopt -u dotglob

    # Remove the shadow folder
    rm -rf "${SHADOW_PATH}"
    exit
}


# Calculate folder size and RAM disk size
SIZE=$(du -s "${TARGET_PATH}" | cut -f 1)
RAM_SIZE=$((SIZE + (SIZE / 10)))


# Use user-defined size if provided
if [ $USER_SIZE -gt 0 ]; then
    RAM_SIZE=$USER_SIZE
fi

# Check for open files in the target folder
open_files=$(lsof "${TARGET_PATH}" 2>/dev/null | wc -l | tr -d ' ')
if [ $open_files -gt 0 ]; then
    echo "There are $open_files open files in the target folder. Please close them before proceeding."
    exit 1
fi

# Move target folder to shadow folder and set trap for cleanup
mkdir "${SHADOW_PATH}"
chown $USER:$GROUP "${SHADOW_PATH}"
shopt -s dotglob
mv "${TARGET_PATH}/"* "${SHADOW_PATH}/"
shopt -u dotglob
trap cleanup SIGHUP SIGINT SIGTERM

# Create and mount tmpfs at the target location
if [[ "$OSTYPE" == "darwin"* ]]; then
    RAM_SIZE_BYTES=$((RAM_SIZE * 1024))
    DEVICE=$(hdid -nomount ram://${RAM_SIZE_BYTES} | awk '{print $1}')
    newfs_hfs "${DEVICE}"
    mount -t hfs "${DEVICE}" "${TARGET_PATH}"
else
    mount -t tmpfs -o size=${RAM_SIZE}k tmpfs "${TARGET_PATH}"
fi

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
    if [[ "$OSTYPE" == "darwin"* ]]; then
        fswatch -1 "${TARGET_PATH}"
    else
        inotifywait -r -e modify,attrib,close_write,move,create,delete "${TARGET_PATH}"
    fi

    rsync -av --delete --exclude '.fseventsd' "${TARGET_PATH}"/ "${SHADOW_PATH}"/
done
