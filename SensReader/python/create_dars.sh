#!/bin/bash
# example to get colour dars:
# (NOTE): works best if you create the temp_dars_env and activate it, then run this script.
# ./create_dars.sh /project/def-wangcs/indrisch/vllm/data/sqa-3d/ScanQA_format/the_650_scenes.txt --get_sens --sens_to_folders --folders_to_dars --delete_folders --delete_sens --num_workers 4 --export_color_images
# Once it's on one cluster, I can transfer using Globus.

# Record the start time
start_time=$(date +%s)

# create_dars.sh <scene_list_file> [options]
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

# Function to display usage
usage() {
    echo "Usage: $0 <scene_list_file> [options] [filetype-options]"
    echo "Example: $0 em1_below_35.txt --sens_to_folders --folders_to_dars"
    echo ""
    echo "This would only extract data using the python reader: $0 <scene_list_file> --sens_to_folders"
    echo "This would extract data using the python reader and then create dar archives: $0 <scene_list_file> --sens_to_folders --folders_to_dars"
    echo "This would extract data using the python reader and then create dar archives and then delete the folders that have been archived: $0 <scene_list_file> --sens_to_folders --folders_to_dars --delete_folders"
    echo "This would extract the archives again: $0 <scene_list_file> --dars_to_folders"
    echo ""
    echo "Options:"
    echo "  --sens_to_folders     Extract .sens file to folders (color/, depth/, etc.)"
    echo "  --folders_to_dars     Archive folders to .dar files (color.dar, depth.dar, etc.)"
    echo "  --delete_folders      Delete folders after archiving"
    echo "  --dars_to_folders     Extract .dar archives to folders"
    echo "  --delete_dars        Delete .dar archives"
    echo "  --get_sens           Get .sens file"
    echo "  --delete_sens        Delete .sens file"
    echo "  --num_workers N      Number of parallel workers (default: 1)"
    echo ""
    echo "Filetype-options:" -- the file types to apply the Options to
    echo "  --export_color_images              Extract color images"
    echo "  --export_depth_images              Extract depth images"
    echo "  --export_poses                     Extract poses"
    echo "  --export_intrinsics                Extract intrinsic parameters"
    exit 1
}

# Check for at least one argument
if [ $# -eq 0 ]; then
    usage
fi

if [[ "$PWD" == *vllm_experiments* ]]; then
    PROJECT_DIR="${PWD%%vllm_experiments*}/vllm_experiments"
elif [[ "$PWD" == *vllm* ]]; then
    PROJECT_DIR="${PWD%%vllm*}/vllm"
else
    echo "Error: Could not find 'vllm' or 'vllm_experiments' in the current path."
    exit 1
fi

# The first argument is the scene list file
scene_list_file="$1"
shift

# Store all arguments for passing to parallel workers
all_args=("$@")

# Initialize flags
sens_to_folders=false
folders_to_dars=false
delete_folders=false
dars_to_folders=false
delete_dars=false
get_sens=false
delete_sens=false
filetype_options=""
num_workers=1

# Parse options from remaining arguments
i=0
while [ $i -lt ${#all_args[@]} ]; do
    arg="${all_args[$i]}"
    case $arg in
        --sens_to_folders) sens_to_folders=true ;;
        --folders_to_dars) folders_to_dars=true ;;
        --delete_folders) delete_folders=true ;;
        --dars_to_folders) dars_to_folders=true ;;
        --delete_dars) delete_dars=true ;;
        --get_sens) get_sens=true ;;
        --delete_sens) delete_sens=true ;;
        --num_workers)
            i=$((i+1))
            num_workers="${all_args[$i]}"
            ;;
        --export_color_images) filetype_options+=" --export_color_images" ;;
        --export_depth_images) filetype_options+=" --export_depth_images" ;;
        --export_poses) filetype_options+=" --export_poses" ;;
        --export_intrinsics) filetype_options+=" --export_intrinsics" ;;
        *)
            # Stop parsing at the first unknown option if it's not a file type
            if [[ "$arg" != --* ]]; then
                echo "Error: Unknown option '$arg'"
                usage
            fi
            ;;
    esac
    i=$((i+1))
done

echo "Filetype options: $filetype_options"
echo "Number of workers: $num_workers"

# Check if at least one action is specified
if ! $sens_to_folders && ! $folders_to_dars && ! $delete_folders && ! $dars_to_folders && ! $delete_dars && ! $get_sens && ! $delete_sens; then
    echo "Error: No action specified. Please provide at least one option like --sens_to_folders."
    usage
fi

# Check if the file exists OR if it's a file descriptor (process substitution)
if [ ! -f "$scene_list_file" ] && [ ! -r "$scene_list_file" ]; then
    echo "File '$scene_list_file' not found or not readable, it must be just a scene name."
    scene_name="$scene_list_file"
    scene_list_file=$(mktemp)
    echo "$scene_name" >> "$scene_list_file"
fi

# Base paths
BASE_SCAN_PATH="$PROJECT_DIR/data/ScanNet/scans"
BASE_OUTPUT_PATH="$PROJECT_DIR/data/ScanNet/scans"


echo "Processing scenes from: $scene_list_file"
echo "------------------------"


if $sens_to_folders; then
    echo "This script will call ./reader.py; it will call (or create, if needed) a temporary venv."
    if [ ! -d "temp_dars_env" ]; then
        module load python/3.12 opencv/4.11
        virtualenv --no-download temp_dars_env && source temp_dars_env/bin/activate
        pip install --no-index --upgrade pip
        pip install --no-index numpy imageio pypng
    else
        module load python/3.12 opencv/4.11
        source temp_dars_env/bin/activate
    fi
fi


process_scene() {
    scene_name="$1"
    # The rest of the arguments are the original arguments passed to the script.
    shift
    local original_args=("$@")

    # Skip empty lines
    if [ -z "$scene_name" ]; then
        return
    fi

    # Activate virtual environment if needed for this worker
    if [ "$sens_to_folders" = true ]; then
        source temp_dars_env/bin/activate
    fi

    echo "Processing scene: $scene_name"
    
    # Define paths for this scene
    local SCAN_FILE="${BASE_SCAN_PATH}/${scene_name}/${scene_name}.sens"
    local FOLDER_COLOR="${BASE_OUTPUT_PATH}/${scene_name}/color"
    local FOLDER_DEPTH="${BASE_OUTPUT_PATH}/${scene_name}/depth"
    local FOLDER_POSE="${BASE_OUTPUT_PATH}/${scene_name}/pose"
    local FOLDER_INTRINSICS="${BASE_OUTPUT_PATH}/${scene_name}/intrinsics"
    local OUTPUT_DIR="${BASE_OUTPUT_PATH}/${scene_name}"

    if [ "$get_sens" = true ]; then
        if [ -f "$SCAN_FILE" ]; then
            echo "Warning: .sens file already exists: $SCAN_FILE"
        else
        echo "Getting .sens file..."
            #$PROJECT_DIR/data/scripts/get_sqa3d.sh "$scene_name"
            /project/def-wangcs/indrisch/vllm_experiments/data/scripts/get_sqa3d.sh "$scene_name"
        fi
    fi
    
    if [ "$sens_to_folders" = true ]; then
        # Check if .sens file exists
        if [ ! -f "$SCAN_FILE" ]; then
            echo "Warning: .sens file not found: $SCAN_FILE"
            return # continue in a loop
        fi
        
        # Extract data using the Python reader
        echo "Converting .sens to folders..."
        source temp_dars_env/bin/activate
        python $PROJECT_DIR/data_support/ScanNet/SensReader/python/reader.py \
            --filename "$SCAN_FILE" \
            --output_path "$OUTPUT_DIR" \
            ${filetype_options}
    fi
    
    # Change to output directory for dar and rm operations
    # It's possible the directory doesn't exist if only --dars_to_folders is used
    # on a clean scene, but dar should handle it.
    if [ -d "$OUTPUT_DIR" ]; then
        pushd "$OUTPUT_DIR" > /dev/null
    else
        echo "Warning: Output directory $OUTPUT_DIR does not exist. Skipping operations for this scene."
        return # continue in a loop
    fi
    
    if [ "$folders_to_dars" = true ]; then
        # Pack into .dar archives
        echo "Creating .dar archives for $scene_name..."
        
        # Create .dar archives for each data type
        for arg in "${original_args[@]}"; do
            case $arg in
                --export_color_images) dar -w -c color -g color/ ;;
                --export_depth_images) dar -w -c depth -g depth/ ;;
                --export_poses) dar -w -c pose -g pose/ ;;
                --export_intrinsics) dar -w -c intrinsic -g intrinsic/ ;;
            esac
        done
    fi

    if [ "$dars_to_folders" = true ]; then
        # Extract the archives again:
        echo "Extracting the archives..."
        for arg in "${original_args[@]}"; do
            case $arg in
                --export_color_images) dar -R . -O -wa -x color -v -g color ;;
                --export_depth_images) dar -R . -O -wa -x depth -v -g depth ;;
                --export_poses) dar -R . -O -wa -x pose -v -g pose ;;
                --export_intrinsics) dar -R . -O -wa -x intrinsic -v -g intrinsic ;;
            esac
        done
    fi
    
    if [ "$delete_folders" = true ]; then
        # Delete the folders that have been archived:
        echo "Deleting the folders that have been archived..."
        for arg in "${original_args[@]}"; do
            case $arg in
                --export_color_images) rm -rf color ;;
                --export_depth_images) rm -rf depth ;;
                --export_poses) rm -rf pose ;;
                --export_intrinsics) rm -rf intrinsic ;;
            esac
        done
    fi

    if [ "$delete_dars" = true ]; then
        # Delete the dar archives:
        echo "Deleting the dar archives..."
        for arg in "${original_args[@]}"; do
            case $arg in
                --export_color_images) rm -rf color.1.dar ;;
                --export_depth_images) rm -rf depth.1.dar ;;
                --export_poses) rm -rf pose.1.dar ;;
                --export_intrinsics) rm -rf intrinsic.1.dar ;;
            esac
        done
    fi

    if [ "$delete_sens" = true ]; then
        echo "Deleting the .sens file..."
        rm -rf "$SCAN_FILE"
    fi
    
    popd > /dev/null
    
    echo "Completed processing: $scene_name"
    echo "------------------------"
}

# Export function and variables to be available in subshells
export -f process_scene
export sens_to_folders folders_to_dars delete_folders dars_to_folders delete_dars get_sens delete_sens
export filetype_options
export BASE_SCAN_PATH BASE_OUTPUT_PATH

# Process each scene
# We use a while loop to read the file and pipe to xargs to avoid issues with too many arguments
# for files with many lines.
if [ "$num_workers" -gt 1 ]; then
    echo "Running in parallel with $num_workers workers."
    # The command for bash -c needs careful quoting.
    # We pass the scene name as the first argument, and the original arguments after that.
    # The `_` is a placeholder for $0 in the bash -c shell.
    escaped_args=$(printf " %q" "${all_args[@]}")
    grep -v -e '^$' "$scene_list_file" | xargs -n 1 -P "$num_workers" -I {} bash -c "process_scene '{}' $escaped_args"
else
    echo "Running sequentially."
    while IFS= read -r scene_name; do
        # Skip empty lines
        if [ -n "$scene_name" ]; then
            process_scene "$scene_name" "${all_args[@]}"
        fi
    done < "$scene_list_file"
fi

if $sens_to_folders; then
    deactivate
    #rm -r temp_dars_env
fi

echo "All scenes processed successfully!"
echo ""
echo "To extract archives later, use:"
echo "dar -R . -O -wa -x color -v -g color"
echo "dar -R . -O -wa -x depth -v -g depth"
echo "dar -R . -O -wa -x pose -v -g pose"
echo "dar -R . -O -wa -x intrinsic -v -g intrinsic"

# Record the end time
end_time=$(date +%s)

# Calculate the duration
duration=$((end_time - start_time))

# Convert duration to a more human-readable format (minutes and seconds)
minutes=$((duration / 60))
seconds=$((duration % 60))

echo "Total running time: ${minutes} minutes and ${seconds} seconds."
