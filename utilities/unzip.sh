#!/bin/bash

# Define the extension to look for
INPUT_DIR=$1
FILE_EXTENSION=$2
OUTPUT_DIR=$3

echo "Output directory found to be : $OUTPUT_DIR"
# Loop through all files in the current directory
for file in "$INPUT_DIR"/*; do
    # Check if it's a regular file
    if [ -f "$file" ]; then
        # Check if the file has the specific extension
        if [[ "$file" == *"$FILE_EXTENSION" ]]; then
            echo "Processing file $file"
            unzip -o "$file" -d "$OUTPUT_DIR"
            # You can add other operations here (e.g., process the file)
        fi
    fi
done
