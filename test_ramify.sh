#!/bin/bash

# Configuration
TEST_DIR="./test2"
RAMIFY_SCRIPT="./ramify.sh"
FILE_COUNT=2
RAMIFY_PID=0
FILE_SIZE_MB=1024

TOTAL_SPACE_KB=$((FILE_COUNT * FILE_SIZE_MB * 1024 * 2)) # Multiply by 2 to account for extra space

# Create test directory if it doesn't exist
if [ ! -d "$TEST_DIR" ]; then
    mkdir "$TEST_DIR"
fi

# Function to create and write files using dd
create_files() {
    local dir=$1
    for i in $(seq 1 $FILE_COUNT); do
        dd if=/dev/urandom of="$dir/file$i.bin" bs=1M count=$FILE_SIZE_MB conv=fdatasync
    done
}

# Function to calculate hashes of files
hash_files() {
    local dir=$1
    local hashes=()
    for i in $(seq 1 $FILE_COUNT); do
        hash=$(md5sum "$dir/file$i.bin" | awk '{print $1}')
        hashes+=("$hash")
    done
    echo "${hashes[@]}"
}

# Function to compare two arrays of hashes
compare_hashes() {
    local -n hashes1=$1
    local -n hashes2=$2
    for i in $(seq 0 $(($FILE_COUNT - 1))); do
        if [ "${hashes1[$i]}" != "${hashes2[$i]}" ]; then
            return 1
        fi
    done
    return 0
}

# Function to clean up the test files
cleanup_files() {
    local dir=$1
    for i in $(seq 1 $FILE_COUNT); do
        rm "$dir/file$i.bin"
    done
}

# Step 1: Hammer "test" directory disk speed with dd
echo "Step 1: Writing files to $TEST_DIR"
create_files "$TEST_DIR"
hashes_before_ramify=($(hash_files "$TEST_DIR"))

# Step 2: Run ramify on "test" directory
$RAMIFY_SCRIPT -s $TOTAL_SPACE_KB "$TEST_DIR" &>/dev/null &
RAMIFY_PID=$!
sleep 10

# Step 3: Hammer "test" directory again with dd
echo "Step 3: Writing files to $TEST_DIR after RAMify"
create_files "$TEST_DIR"

# Step 4: Wait for files to appear in "test.ramify"
echo "Step 4: Waiting for files to sync to ${TEST_DIR}.ramify"

# Run the rm and create_files commands in the background
rm "${TEST_DIR}/file1.bin" &
create_files "${TEST_DIR}" &

sync_file_count=0
timeout=30
elapsed_time=0
while [[ $sync_file_count -lt 2 && $elapsed_time -lt $timeout ]]; do
    sleep 0.5
    elapsed_time=$((elapsed_time + 1))

    hashes_after_ramify=($(hash_files "${TEST_DIR}.ramify"))
    sync_file_count=$((${#hashes_after_ramify[@]} - ${#hashes_before_ramify[@]}))
done

if [[ $elapsed_time -eq $timeout ]]; then
    echo "File sync to ${TEST_DIR}.ramify timed out after 30 seconds"
else
    echo "Files synced to ${TEST_DIR}.ramify after $elapsed_time seconds"
fi

# Wait for the background processes to complete
wait

# Step 5: Delete one of the files in "test"
echo "Step 5: File1.bin already deleted in Step 4"
rm "${TEST_DIR}/file1.bin"

# Wait for the file to be deleted in "${TEST_DIR}.ramify"
echo "Waiting for the file to be deleted in ${TEST_DIR}.ramify"
timeout=30
elapsed_time=0
while [[ -e "${TEST_DIR}.ramify/file1.bin" && $elapsed_time -lt $timeout ]]; do
    sleep 0.5
    elapsed_time=$((elapsed_time + 1))
done

if [[ $elapsed_time -eq $timeout ]]; then
    echo "File deletion in ${TEST_DIR}.ramify timed out after 30 seconds"
else
    echo "File deleted in ${TEST_DIR}.ramify after $elapsed_time seconds"
fi

# Check if the deleted file is removed from "test.ramify"
if [ ! -e "${TEST_DIR}.ramify/file1.bin" ]; then
    echo "File deletion successfully synced to ${TEST_DIR}.ramify"
else
    echo "File deletion not synced to ${TEST_DIR}.ramify"
fi

# Compare the hashes and print the results
if compare_hashes hashes_before_ramify hashes_after_ramify; then
    echo "Hashes match for files created before and after RAMify"
else
    echo "Hashes do not match for files created before and after RAMify"
fi

# Step 7: Cleanup the rest of the files
echo "Step 7: Cleaning up"
cleanup_files "$TEST_DIR"
cleanup_files "${TEST_DIR}.ramify"
rmdir "${TEST_DIR}.ramify"
