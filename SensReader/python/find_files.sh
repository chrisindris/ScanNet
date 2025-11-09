#!/bin/bash

# Script to find scenes from the_650_scenes.txt that don't exist in the scans directory
SCENES_FILE="/project/def-wangcs/indrisch/vllm/data/sqa-3d/ScanQA_format/the_650_scenes.txt"
SCANS_DIR="/scratch/indrisch/scans"

# Check if the scenes file exists
if [ ! -f "$SCENES_FILE" ]; then
    echo "Error: Scenes file not found: $SCENES_FILE"
    exit 1
fi

# Check if the scans directory exists
if [ ! -d "$SCANS_DIR" ]; then
    echo "Error: Scans directory not found: $SCANS_DIR"
    exit 1
fi

# Read each scene name from the file and check if it exists as a subfolder
while IFS= read -r scene; do
    # Skip empty lines
    if [ -z "$scene" ]; then
        continue
    fi
    
    # Check if the scene directory exists
    if [ ! -d "$SCANS_DIR/$scene/color" ]; then
        echo $scene
    fi
done < "$SCENES_FILE"
