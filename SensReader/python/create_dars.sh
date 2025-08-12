#!/bin/bash

# create_dars.sh <scene_list_file>
# This script creates .dar archives for the given scene list file.
#
# --- to list contents of archives ---
# echo "Contents of archives for $scene_name:"
# dar -l color
# dar -l depth
# dar -l pose
# dar -l intrinsic
# --- to create the directory again (extract the files into the same location) ---
# dar -R . -O -wa -x color -v -g color
# dar -R . -O -wa -x depth -v -g depth
# dar -R . -O -wa -x pose -v -g pose
# dar -R . -O -wa -x intrinsic -v -g intrinsic

# Check if a file argument is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <scene_list_file>"
    echo "Example: $0 em1_below_35.txt"
    echo "Example: $0 <(echo 'scene1234_56')"
    exit 1
fi

# Check if the file exists OR if it's a file descriptor (process substitution)
if [ ! -f "$1" ] && [ ! -r "$1" ]; then
    echo "Error: File '$1' not found or not readable"
    exit 1
fi

# Base paths
BASE_SCAN_PATH="/project/def-wangcs/indrisch/vllm/data/ScanNet/scans"
BASE_OUTPUT_PATH="/project/def-wangcs/indrisch/vllm/data/ScanNet/scans"

echo "Processing scenes from: $1"
echo "------------------------"

# Process each scene
while IFS= read -r scene_name; do
    # Skip empty lines
    if [ -n "$scene_name" ]; then
        echo "Processing scene: $scene_name"
        
        # Define paths for this scene
        SCAN_FILE="${BASE_SCAN_PATH}/${scene_name}/${scene_name}.sens"
        OUTPUT_DIR="${BASE_OUTPUT_PATH}/${scene_name}"
        
        # Check if .sens file exists
        if [ ! -f "$SCAN_FILE" ]; then
            echo "Warning: .sens file not found: $SCAN_FILE"
            continue
        fi
        
        # Extract data using the Python reader
        python /project/def-wangcs/indrisch/vllm/data_support/ScanNet/SensReader/python/reader.py \
            --filename "$SCAN_FILE" \
            --output_path "$OUTPUT_DIR" \
            --export_color_images \
            --export_depth_images \
            --export_poses \
            --export_intrinsics
        
        # Pack into .dar archives
        pushd "$OUTPUT_DIR"
        echo "Creating .dar archives for $scene_name..."
        
        # Create .dar archives for each data type
        dar -w -c color -g color/
        dar -w -c depth -g depth/
        dar -w -c pose -g pose/
        dar -w -c intrinsic -g intrinsic/
        
        # Delete the folders that have been archived:
        echo "Deleting the folders that have been archived..."
        rm -rf color depth pose intrinsic

        # # Extract the archives again:
        # echo "Extracting the archives again..."
        # dar -R . -O -wa -x color -v -g color
        # dar -R . -O -wa -x depth -v -g depth
        # dar -R . -O -wa -x pose -v -g pose
        # dar -R . -O -wa -x intrinsic -v -g intrinsic
        
        popd
        
        echo "Completed processing: $scene_name"
        echo "------------------------"
    fi
done < "$1"

echo "All scenes processed successfully!"
echo ""
echo "To extract archives later, use:"
echo "dar -R . -O -wa -x color -v -g color"
echo "dar -R . -O -wa -x depth -v -g depth"
echo "dar -R . -O -wa -x pose -v -g pose"
echo "dar -R . -O -wa -x intrinsic -v -g intrinsic"
