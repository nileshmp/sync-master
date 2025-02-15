#!/bin/bash

# Define the extension to look for
INPUT_DIR=$1
FILE_EXTENSION=$2
OUTPUT_DIR=$3
IMAGE_QUALITY=$4

echo "Usage: $> ./resize-image.sh ../fromGoogle/extracted .jpg ../fromGoogle/light 85"
echo "Provided: $> ./resize-image.sh $1 $2 $3 $4"

# # Check if no arguments are provided
# if [ $# -eq 0 ]; then
#     print_usage
#     exit 1
# fi

resize() {
    # Loop through all files in the current directory
    for file in "$INPUT_DIR"/*; do
        # Check if it's a regular file
        if [ -f "$file" ]; then
            # Check if the file has the specific extension
            if [[ "$file" == *"$FILE_EXTENSION" ]]; then
                echo "Processing file $file"
                FILE_NAME=$(basename "$file")
                magick $file -quality $IMAGE_QUALITY "$OUTPUT_DIR/$FILE_NAME"
                # You can add other operations here (e.g., process the file)
            fi
        fi
    done
}

# Function to continue based on user input
ask_to_continue() {
    echo "Do you want to continue? (y/n)"
    read -p "[y/n]: " response
    case "$response" in
        y|Y|yes|Yes)
            echo "Continuing..."
            resize
            ;;
        n|N|no|No)
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo "Invalid response. Please enter 'y' or 'n'."
            ask_to_continue # Recursively ask if input is invalid
            ;;
    esac
}



# # Parse command-line arguments
# while [[ $# -gt 0 ]]; do
#     case $1 in
#         -h|--help)
#             print_usage
#             exit 0
#             ;;
#         -v|--version)
#             echo "Version 1.0.0"
#             exit 0
#             ;;
#         -f|--file)
#             FILE=$2
#             if [ -z "$FILE" ]; then
#                 echo "Error: Missing argument for --file"
#                 exit 1
#             fi
#             echo "Processing file: $FILE"
#             shift 2
#             ;;
#         *)
#             echo "Invalid option: $1"
#             print_usage
#             exit 1
#             ;;
#     esac
# done

# Ask user if they want to continue
ask_to_continue
