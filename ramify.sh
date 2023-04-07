#!/bin/bash

# $1 is the location of the ramdisk
# $2 is the location to be ramified 

USER_SIZE=0

# Get optional arguments
while getopts ":s:" OPTIONS; do
        case $OPTIONS in

                s)
			echo $OPTARG
                        USER_SIZE=$OPTARG
                        ;;

	        *)
            		echo "Invalid option: -$OPTARG" >&2
            		usage
            		exit 2
            		;;
        esac
done

# Shift Optional variables to allow for the rest of the arguments to pass
shift $((OPTIND - 1))

TARGET_PATH="${1}"
SHADOW_PATH="${1}.ramify"
USER=$(stat -c '%U' "${TARGET_PATH}")
GROUP=$(stat -c '%G' "${TARGET_PATH}")

echo "User defined size: $USER_SIZE"
function cleanup() {
	echo "***CLEANUP CALLED***"
	rsync -avz "${TARGET_PATH}"/ "${SHADOW_PATH}"/
	umount "${TARGET_PATH}"
	rmdir "${TARGET_PATH}"
	mv "${SHADOW_PATH}" "${TARGET_PATH}"
	exit
}

# Check for open files on the system.
# TODO add logic to prompt user to terminate processes, or pause execution
echo "Number of open files: $(lsof "${TARGET_PATH}" 2> /dev/null | wc -l)"

# Check folder size
SIZE=$(du -s "${TARGET_PATH}" | cut -f 1)
echo "Size of target: ${SIZE}KB"

# Partition tmpfs with 10% increase size.
# Removed AWK because AWK has a hard time with floating points
# RAM_SIZE=$(awk "BEGIN {print ($SIZE+(0.1 * $SIZE))}")
RAM_SIZE=$(python -c 'import sys; size=int(sys.argv[1]); print(int(size+(0.1*size)));' "$SIZE")
# Set size manually if user supplied option
if [ $USER_SIZE -gt 0 ]; then
	echo "User supplied size as: ${USER_SIZE}KB"
	RAM_SIZE=$USER_SIZE
fi

echo "Partioning ${RAM_SIZE}KB"

# Move target folder to shadow location
echo "Moving "${TARGET_PATH}" to "${SHADOW_PATH}""
mv "${TARGET_PATH}" "${SHADOW_PATH}"

# Catch any signals and cleanup
trap cleanup SIGHUP SIGINT SIGTERM

# Mount tmpfs in the original target location
echo "Mounting tmpfs on "${TARGET_PATH}""
echo "mount -t tmpfs -o size=${RAM_SIZE}k tmpfs "${TARGET_PATH}""
mkdir "${TARGET_PATH}"
mount -t tmpfs -o size=${RAM_SIZE}k tmpfs "${TARGET_PATH}"
chown $USER:$GROUP "${TARGET_PATH}"

sleep 5s

echo "Copying contents from target to ramdisk..."
rsync -a --progress "${SHADOW_PATH}"/ "${TARGET_PATH}"/

echo "Engage inotify syncing"
while true; do
  inotifywait -r -e modify,attrib,close_write,move,create,delete "${TARGET_PATH}"
  rsync -av "${TARGET_PATH}"/ "${SHADOW_PATH}"/
done
