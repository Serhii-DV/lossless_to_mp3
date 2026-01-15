#!/bin/bash

# Audio to MP3 Converter Script
# Converts FLAC, WAV, M4A, and APE files to MP3 320kbps while preserving folder structure

set -euo pipefail

INPUT_DIR=""
OUTPUT_DIR=""
CONFIG_FILE=""
BATCH_MODE=false
IGNORED_EXTENSIONS=()

# Check if ffmpeg is installed
command -v ffmpeg >/dev/null 2>&1 || {
    echo "Error: ffmpeg is required but not installed."
    echo "Install with: sudo apt update && sudo apt install ffmpeg"
    exit 1
}

# Check if shntool and cuetools are installed (for CUE file support)
if ! command -v shnsplit >/dev/null 2>&1 || ! command -v cuebreakpoints >/dev/null 2>&1; then
    echo "Warning: shntool and cuetools are not installed - CUE file splitting will be skipped."
    echo "To enable CUE file support, install with: sudo apt update && sudo apt install shntool cuetools"
    echo
fi

show_usage() {
    echo "Usage: $0 -i INPUT_DIR [-o OUTPUT_DIR] [-c CONFIG_FILE] [-b]"
    echo "  -i, --input DIR     Input directory containing audio files (FLAC, WAV, M4A, APE)"
    echo "                      Also supports CUE files for splitting solid audio files"
    echo "  -o, --output DIR    Output directory for converted MP3 files (optional)"
    echo "                      If not specified, creates 'INPUT_DIR (mp3)'"
    echo "  -b, --batch         Batch mode: process all subdirectories as separate albums"
    echo "                      Single mode (default): process input directory as one album"
    echo "  -c, --config FILE   Configuration file with ignored extensions (optional)"
    echo "                      Default: .ignore in script directory"
    echo "                      Format: one extension per line (without dots)"
    echo "  -h, --help          Show this help message"
}

read_ignored_extensions() {
    local config_file="$1"
    IGNORED_EXTENSIONS=()

    if [[ -f "$config_file" ]]; then
        echo "Reading ignored extensions from: $config_file"
        while IFS= read -r line; do
            # Skip empty lines and comments (lines starting with #)
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                # Remove leading/trailing whitespace and convert to lowercase
                line=$(echo "$line" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                if [[ -n "$line" ]]; then
                    IGNORED_EXTENSIONS+=("$line")
                fi
            fi
        done < "$config_file"

        if [[ ${#IGNORED_EXTENSIONS[@]} -gt 0 ]]; then
            echo "Ignored extensions: ${IGNORED_EXTENSIONS[*]}"
        else
            echo "No valid extensions found in config file"
        fi
        echo
    else
        echo "Config file not found: $config_file (this is optional)"
        echo
    fi
}

is_extension_ignored() {
    local file_extension="$1"
    file_extension=$(echo "$file_extension" | tr '[:upper:]' '[:lower:]')

    for ignored_ext in "${IGNORED_EXTENSIONS[@]}"; do
        if [[ "$file_extension" == "$ignored_ext" ]]; then
            return 0  # Extension should be ignored
        fi
    done
    return 1  # Extension should not be ignored
}

find_cue_files() {
    local search_dir="$1"
    local temp_file=$(mktemp)

    # Find all CUE files and their associated audio files
    find "$search_dir" -type f -iname "*.cue" > "$temp_file"

    local cue_count=$(wc -l < "$temp_file")
    if [[ $cue_count -gt 0 ]]; then
        echo "Found $cue_count CUE file(s) for audio splitting"
        echo

        while IFS= read -r cue_file; do
            if [[ -n "$cue_file" ]]; then
                process_cue_file "$cue_file"
            fi
        done < "$temp_file"
    fi

    rm -f "$temp_file"
    return $cue_count
}

process_cue_file() {
    local cue_file="$1"

    echo "Processing CUE file: $(basename "$cue_file")"

    # Find the audio file associated with this CUE file
    local cue_dir=$(dirname "$cue_file")
    local audio_file=""

    # Look for audio files referenced in the CUE file
    local referenced_file=$(grep -i "^FILE" "$cue_file" | head -1 | sed 's/^FILE[[:space:]]*"\([^"]*\)".*/\1/' | sed "s/^FILE[[:space:]]*\([^[:space:]]*\).*/\1/")

    if [[ -n "$referenced_file" ]]; then
        # Check if the referenced file exists (try both relative and absolute paths)
        if [[ -f "$cue_dir/$referenced_file" ]]; then
            audio_file="$cue_dir/$referenced_file"
        elif [[ -f "$referenced_file" ]]; then
            audio_file="$referenced_file"
        fi
    fi

    # If not found from CUE file, look for common audio files in the same directory
    if [[ -z "$audio_file" ]]; then
        for ext in flac wav ape m4a; do
            local candidate=$(find "$cue_dir" -maxdepth 1 -type f -iname "*.$ext" | head -1)
            if [[ -n "$candidate" ]]; then
                audio_file="$candidate"
                break
            fi
        done
    fi

    if [[ -z "$audio_file" || ! -f "$audio_file" ]]; then
        echo "Warning: No associated audio file found for CUE file: $cue_file"
        echo
        return 1
    fi

    echo "Associated audio file: $(basename "$audio_file")"

    # Check if required tools are available
    if ! command -v shnsplit >/dev/null 2>&1 || ! command -v cuebreakpoints >/dev/null 2>&1; then
        echo "Warning: shntool/cuetools not available - skipping CUE file splitting"
        echo
        return 1
    fi

    # Create a temporary directory for split files
    local temp_split_dir=$(mktemp -d)
    local original_dir=$(pwd)

    cd "$temp_split_dir" || {
        echo "Error: Cannot create temporary directory for splitting"
        return 1
    }

    echo "Splitting audio file using CUE sheet..."

    # Split the audio file using the CUE file
    if cuebreakpoints "$cue_file" | shnsplit -o flac "$audio_file"; then
        echo "✓ Successfully split audio file"

        # Convert split files to MP3
        local split_count=0
        local convert_success=0
        local convert_failed=0

        for split_file in *.flac; do
            if [[ -f "$split_file" ]]; then
                split_count=$((split_count + 1))

                # Get track info from CUE file if possible
                local track_num=$(printf "%02d" $split_count)
                local track_title="Track $track_num"

                # Try to extract track title from CUE file
                local cue_track_title=$(awk -v track="$split_count" '
                    /^[[:space:]]*TRACK[[:space:]]+/ {
                        if ($2 == sprintf("%02d", track) || $2 == track) {
                            found_track = 1
                        } else {
                            found_track = 0
                        }
                    }
                    found_track && /^[[:space:]]*TITLE[[:space:]]+/ {
                        gsub(/^[[:space:]]*TITLE[[:space:]]+"/, "")
                        gsub(/"[[:space:]]*$/, "")
                        print
                        exit
                    }
                ' "$cue_file")

                if [[ -n "$cue_track_title" ]]; then
                    # Clean the title for filename use
                    track_title=$(echo "$cue_track_title" | tr '/' '_' | tr '\\' '_' | tr ':' '_' | tr '*' '_' | tr '?' '_' | tr '"' '_' | tr '<' '_' | tr '>' '_' | tr '|' '_')
                fi

                # Create output filename
                local output_name="${track_num} - ${track_title}.mp3"

                # Calculate output path maintaining directory structure
                local relative_cue_path
                local resolved_cue=$(realpath "$cue_file")
                local resolved_input_dir=$(realpath "$INPUT_DIR")

                if [[ "$resolved_cue" == "$resolved_input_dir"* ]]; then
                    relative_cue_path=$(python3 -c "
import os
import sys
cue_file = sys.argv[1]
input_dir = sys.argv[2]
try:
    rel_path = os.path.relpath(cue_file, input_dir)
    if rel_path == '.' or rel_path.startswith('..'):
        print('.')
    else:
        print(os.path.dirname(rel_path) if os.path.dirname(rel_path) != '.' else '.')
except:
    print('.')
" "$resolved_cue" "$resolved_input_dir")
                else
                    relative_cue_path="."
                fi

                local final_output_dir
                if [[ "$relative_cue_path" == "." ]]; then
                    final_output_dir="$OUTPUT_DIR"
                else
                    final_output_dir="$OUTPUT_DIR/$relative_cue_path"
                fi

                local final_output_file="$final_output_dir/$output_name"

                # Create output directory
                if [[ ! -d "$final_output_dir" ]]; then
                    mkdir -p "$final_output_dir" || {
                        echo "Error: Cannot create directory '$final_output_dir'"
                        convert_failed=$((convert_failed + 1))
                        continue
                    }
                fi

                if [[ -f "$final_output_file" ]]; then
                    echo "Warning: '$final_output_file' already exists, skipping..."
                    convert_success=$((convert_success + 1))
                else
                    echo "Converting track $split_count: $track_title"

                    if ffmpeg -y -nostdin -i "$split_file" \
                           -codec:a libmp3lame \
                           -b:a 320k \
                           -map_metadata 0 \
                           -id3v2_version 3 \
                           -write_id3v1 1 \
                           "$final_output_file" \
                           -v quiet -stats; then
                        echo "✓ Successfully converted: $output_name"
                        convert_success=$((convert_success + 1))
                    else
                        echo "✗ Failed to convert: $split_file"
                        convert_failed=$((convert_failed + 1))
                    fi
                fi
            fi
        done

        echo
        echo "=== CUE Split Conversion Summary ==="
        echo "Total tracks split: $split_count"
        echo "Successfully converted: $convert_success"
        echo "Failed conversions: $convert_failed"
        echo

    else
        echo "✗ Failed to split audio file using CUE sheet"
        cd "$original_dir"
        rm -rf "$temp_split_dir"
        return 1
    fi

    # Clean up
    cd "$original_dir"
    rm -rf "$temp_split_dir"

    return 0
}

get_output_path() {
    local input_file="$1"

    # Use realpath to resolve any symbolic links and normalize paths
    local resolved_input=$(realpath "$input_file")
    local resolved_input_dir=$(realpath "$INPUT_DIR")

    # Calculate relative path using Python for reliable path handling
    local relative_path
    if [[ "$resolved_input" == "$resolved_input_dir"* ]]; then
        # File is under the input directory - calculate relative path using Python
        relative_path=$(python3 -c "
import os
import sys
input_file = sys.argv[1]
input_dir = sys.argv[2]
try:
    rel_path = os.path.relpath(input_file, input_dir)
    if rel_path == '.' or rel_path.startswith('..'):
        print(os.path.basename(input_file))
    else:
        print(rel_path)
except:
    print(os.path.basename(input_file))
" "$resolved_input" "$resolved_input_dir")

        # Fallback: if calculation failed, use basename
        if [[ -z "$relative_path" ]]; then
            relative_path=$(basename "$input_file")
        fi
    else
        # File is not under input directory - use basename as fallback
        relative_path=$(basename "$input_file")
    fi

    # Extract filename and change extension to .mp3
    local base_name=$(basename "$relative_path")
    base_name="${base_name%.*}.mp3"

    # Handle subdirectories within the album folder
    local subdir=$(dirname "$relative_path")
    if [[ "$subdir" == "." ]]; then
        # File is directly in the album folder
        echo "$OUTPUT_DIR/$base_name"
    else
        # File is in a subdirectory within the album
        echo "$OUTPUT_DIR/$subdir/$base_name"
    fi
}

convert_audio() {
    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        echo "Error: File '$input_file' not found"
        return 1
    fi

    local extension="${input_file##*.}"
    extension="${extension,,}"  # Convert to lowercase

    # Check if it's a supported audio format
    if [[ "$extension" != "flac" && "$extension" != "wav" && "$extension" != "m4a" && "$extension" != "ape" ]]; then
        echo "Warning: '$input_file' is not a supported audio file (FLAC/WAV/M4A/APE), skipping..."
        return 0
    fi

    local output_file
    output_file=$(get_output_path "$input_file")

    local output_dir=$(dirname "$output_file")

    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            echo "Error: Cannot create directory '$output_dir'"
            return 1
        }
    fi

    if [[ -f "$output_file" ]]; then
        echo "Warning: '$output_file' already exists, skipping..."
        return 0
    fi

    echo "Converting:  $input_file -> $output_file"

    if ffmpeg -y -nostdin -i "$input_file" \
           -codec:a libmp3lame \
           -b:a 320k \
           -map_metadata 0 \
           -id3v2_version 3 \
           -write_id3v1 1 \
           "$output_file" \
           -v quiet -stats; then
        echo "✓ Successfully converted:  $output_file"
        return 0
    else
        echo "✗ Failed to convert: $input_file"
        return 1
    fi
}

convert_png() {
    local input_file="$1"

    if [[ ! -f "$input_file" ]]; then
        echo "Error: File '$input_file' not found"
        return 1
    fi

    local extension="${input_file##*.}"
    if [[ "${extension,,}" != "png" ]]; then
        echo "Warning: '$input_file' is not a PNG file, skipping..."
        return 0
    fi

    # Use the same improved path resolution logic as audio files
    local resolved_input=$(realpath "$input_file")
    local resolved_input_dir=$(realpath "$INPUT_DIR")

    # Calculate relative path using Python for reliable path handling
    local relative_path
    if [[ "$resolved_input" == "$resolved_input_dir"* ]]; then
        # File is under the input directory - calculate relative path using Python
        relative_path=$(python3 -c "
import os
import sys
input_file = sys.argv[1]
input_dir = sys.argv[2]
try:
    rel_path = os.path.relpath(input_file, input_dir)
    if rel_path == '.' or rel_path.startswith('..'):
        print(os.path.basename(input_file))
    else:
        print(rel_path)
except:
    print(os.path.basename(input_file))
" "$resolved_input" "$resolved_input_dir")

        # Fallback: if calculation failed, use basename
        if [[ -z "$relative_path" ]]; then
            relative_path=$(basename "$input_file")
        fi
    else
        # File is not under input directory - use basename as fallback
        relative_path=$(basename "$input_file")
    fi

    local base_name=$(basename "$relative_path")
    base_name="${base_name%.*}.jpg"

    local subdir=$(dirname "$relative_path")
    local output_file
    if [[ "$subdir" == "." ]]; then
        output_file="$OUTPUT_DIR/$base_name"
    else
        output_file="$OUTPUT_DIR/$subdir/$base_name"
    fi

    local output_dir=$(dirname "$output_file")

    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            echo "Error: Cannot create directory '$output_dir'"
            return 1
        }
    fi

    if [[ -f "$output_file" ]]; then
        echo "Warning: '$output_file' already exists, skipping..."
        return 0
    fi

    echo "Converting PNG: $input_file -> $output_file"

    if ffmpeg -y -nostdin -i "$input_file" \
           -q:v 2 \
           "$output_file" \
           -v quiet -stats; then
        echo "✓ Successfully converted PNG: $output_file"
        return 0
    else
        echo "✗ Failed to convert PNG: $input_file"
        return 1
    fi
}

copy_other_files() {
    local copied=0
    local copy_failed=0
    local png_converted=0
    local png_failed=0
    local ignored=0

    echo "Processing other files (images, text files, etc.)..."
    echo

    # Find all files that are NOT audio files
    local temp_file=$(mktemp)
    find "$INPUT_DIR" -type f ! \( -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.ape" \) > "$temp_file"

    local total_other_files=$(wc -l < "$temp_file")

    if [[ $total_other_files -eq 0 ]]; then
        echo "No other files found to process."
        echo
        rm -f "$temp_file"
        return 0
    fi

    echo "Found $total_other_files other files to process"

    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            local extension="${file##*.}"

            # Check if this extension should be ignored
            if is_extension_ignored "$extension"; then
                echo "Ignoring: $(basename "$file") (extension: $extension)"
                ignored=$((ignored + 1))
                continue
            fi

            # Check if it's a PNG file that needs conversion
            if [[ "${extension,,}" == "png" ]]; then
                echo "Converting PNG: $(basename "$file")"
                if convert_png "$file"; then
                    png_converted=$((png_converted + 1))
                else
                    png_failed=$((png_failed + 1))
                fi
            else
                # Regular file copy for non-PNG files
                # Use the same improved path resolution logic as audio files
                local resolved_file=$(realpath "$file")
                local resolved_input_dir=$(realpath "$INPUT_DIR")

                # Calculate relative path using Python for reliable path handling
                local relative_path
                if [[ "$resolved_file" == "$resolved_input_dir"* ]]; then
                    # File is under the input directory - calculate relative path using Python
                    relative_path=$(python3 -c "
import os
import sys
input_file = sys.argv[1]
input_dir = sys.argv[2]
try:
    rel_path = os.path.relpath(input_file, input_dir)
    if rel_path == '.' or rel_path.startswith('..'):
        print(os.path.basename(input_file))
    else:
        print(rel_path)
except:
    print(os.path.basename(input_file))
" "$resolved_file" "$resolved_input_dir")

                    # Fallback: if calculation failed, use basename
                    if [[ -z "$relative_path" ]]; then
                        relative_path=$(basename "$file")
                    fi
                else
                    # File is not under input directory - use basename as fallback
                    relative_path=$(basename "$file")
                fi

                local output_file="$OUTPUT_DIR/$relative_path"
                local output_dir=$(dirname "$output_file")

                # Create directory if it doesn't exist
                if [[ ! -d "$output_dir" ]]; then
                    mkdir -p "$output_dir" || {
                        echo "Error: Cannot create directory '$output_dir'"
                        copy_failed=$((copy_failed + 1))
                        continue
                    }
                fi

                # Copy the file if it doesn't already exist
                if [[ -f "$output_file" ]]; then
                    echo "Warning: '$output_file' already exists, skipping..."
                    copied=$((copied + 1))
                else
                    echo "Copying: $(basename "$file")"
                    if cp "$file" "$output_file"; then
                        copied=$((copied + 1))
                    else
                        echo "✗ Failed to copy: $file"
                        copy_failed=$((copy_failed + 1))
                    fi
                fi
            fi
        fi
    done < "$temp_file"

    rm -f "$temp_file"

    echo
    echo "=== File Processing Summary ==="
    echo "PNG files converted to JPG: $png_converted"
    echo "Failed PNG conversions: $png_failed"
    echo "Other files copied: $copied"
    echo "Files ignored: $ignored"
    echo "Failed copies: $copy_failed"
    echo
}

process_single_album() {
    local album_dir="$1"
    local output_dir="$2"

    echo "Processing album: $(basename "$album_dir")"
    echo "Input directory: $album_dir"
    echo "Output directory: $output_dir"

    # Temporarily set global variables for this album
    local original_input_dir="$INPUT_DIR"
    local original_output_dir="$OUTPUT_DIR"

    INPUT_DIR="$album_dir"
    OUTPUT_DIR="$output_dir"

    # Create output directory
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR" || {
            echo "Error: Cannot create output directory '$OUTPUT_DIR'"
            return 1
        }
    fi

    # Process the album
    process_directory

    # Restore global variables
    INPUT_DIR="$original_input_dir"
    OUTPUT_DIR="$original_output_dir"
}

process_batch() {
    echo "Scanning for album directories in: $INPUT_DIR"

    local album_count=0
    local processed_albums=0
    local failed_albums=0

    # Find all subdirectories (albums) in the artist directory
    while IFS= read -r -d '' album_dir; do
        if [[ -d "$album_dir" ]]; then
            album_count=$((album_count + 1))
            local album_name=$(basename "$album_dir")
            local album_output_dir="$BASE_OUTPUT_DIR/$album_name"

            echo
            echo "=== Processing Album $album_count: $album_name ==="

            if process_single_album "$album_dir" "$album_output_dir"; then
                processed_albums=$((processed_albums + 1))
                echo "✓ Successfully processed album: $album_name"
            else
                failed_albums=$((failed_albums + 1))
                echo "✗ Failed to process album: $album_name"
            fi
        fi
    done < <(find "$INPUT_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

    echo
    echo "=== Batch Processing Summary ==="
    echo "Total albums found: $album_count"
    echo "Successfully processed: $processed_albums"
    echo "Failed: $failed_albums"
}

process_directory() {
    local count=0
    local success=0
    local failed=0

    echo "Input directory: $INPUT_DIR"
    echo "Output directory: $OUTPUT_DIR"

    # First, process any CUE files for splitting solid audio files
    echo "Checking for CUE files..."
    if find_cue_files "$INPUT_DIR"; then
        echo "CUE file processing completed"
        echo
    fi

    echo "Searching for individual audio files (FLAC, WAV, M4A, APE)..."
    echo

    # Find individual audio files, but exclude those that might be solid files with CUE sheets
    local temp_file=$(mktemp)
    local cue_audio_files=$(mktemp)

    # First, identify audio files that have associated CUE files (these are solid files)
    find "$INPUT_DIR" -type f -iname "*.cue" | while read -r cue_file; do
        local cue_dir=$(dirname "$cue_file")
        # Look for the audio file referenced in CUE or common audio files in the same directory
        local referenced_file=$(grep -i "^FILE" "$cue_file" | head -1 | sed 's/^FILE[[:space:]]*"\([^"]*\)".*/\1/' | sed "s/^FILE[[:space:]]*\([^[:space:]]*\).*/\1/" 2>/dev/null || true)

        if [[ -n "$referenced_file" ]]; then
            if [[ -f "$cue_dir/$referenced_file" ]]; then
                echo "$cue_dir/$referenced_file"
            elif [[ -f "$referenced_file" ]]; then
                echo "$referenced_file"
            fi
        else
            # Look for any audio file in the same directory as the CUE file
            find "$cue_dir" -maxdepth 1 -type f \( -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.ape" \) | head -1
        fi
    done | sort -u > "$cue_audio_files"

    # Find all audio files, then exclude those associated with CUE files
    find "$INPUT_DIR" -type f \( -iname "*.flac" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.ape" \) | while read -r audio_file; do
        if ! grep -Fxq "$audio_file" "$cue_audio_files"; then
            echo "$audio_file"
        fi
    done > "$temp_file"

    rm -f "$cue_audio_files"

    local total_files=$(wc -l < "$temp_file")
    echo "Found $total_files audio files to convert"
    echo

    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            count=$((count + 1))
            echo "Processing file #$count/$total_files: $(basename "$file")"
            if convert_audio "$file"; then
                success=$((success + 1))
            else
                failed=$((failed + 1))
            fi
            echo
        fi
    done < "$temp_file"

    rm -f "$temp_file"

    echo "=== Conversion Summary ==="
    echo "Total audio files found: $count"
    echo "Successfully converted: $success"
    echo "Failed conversions: $failed"
    echo

    # Copy other files after FLAC conversion
    copy_other_files
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                INPUT_DIR="$2"
                INPUT_DIR="${INPUT_DIR/#\~/$HOME}"
                INPUT_DIR="${INPUT_DIR%/}"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                OUTPUT_DIR="${OUTPUT_DIR/#\~/$HOME}"
                OUTPUT_DIR="${OUTPUT_DIR%/}"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                CONFIG_FILE="${CONFIG_FILE/#\~/$HOME}"
                shift 2
                ;;
            -b|--batch)
                BATCH_MODE=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo "Error:  Unknown option $1"
                show_usage
                exit 1
                ;;
            *)
                echo "Error:  Unexpected argument '$1'"
                show_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$INPUT_DIR" ]]; then
        echo "Error: Input directory is required (-i option)"
        show_usage
        exit 1
    fi

    # Set default config file if not specified
    if [[ -z "$CONFIG_FILE" ]]; then
        # Look for .ignore file in the same directory as the script
        local script_dir=$(dirname "$(realpath "$0")")
        CONFIG_FILE="$script_dir/.ignore"
    fi

    # Store original OUTPUT_DIR to check if it was provided
    local original_output_provided=false
    if [[ -n "$OUTPUT_DIR" ]]; then
        original_output_provided=true
    fi

    # Read ignored extensions from config file
    read_ignored_extensions "$CONFIG_FILE"

    # Set default output directory if not specified
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="${INPUT_DIR} (mp3)"
    fi

    # Set up output directory structure based on mode
    if [[ "$BATCH_MODE" == "true" ]]; then
        # Batch mode: OUTPUT_DIR/artist_name/album_name for each album
        echo "Batch mode: Processing all subdirectories as separate albums"
        ARTIST_NAME=$(basename "$INPUT_DIR")
        BASE_OUTPUT_DIR="$OUTPUT_DIR/$ARTIST_NAME"
    else
        # Single album mode: Extract artist and album from path
        echo "Single album mode: Processing input directory as one album"
        local album_name=$(basename "$INPUT_DIR")
        local artist_path=$(dirname "$INPUT_DIR")
        local artist_name=$(basename "$artist_path")

        # If output dir was specified, create artist/album structure
        if [[ "$original_output_provided" == "true" ]]; then
            OUTPUT_DIR="$OUTPUT_DIR/$artist_name/$album_name"
        fi
    fi

    if [[ ! -d "$INPUT_DIR" ]]; then
        echo "Error: Input directory '$INPUT_DIR' does not exist"
        exit 1
    fi

    if [[ "$BATCH_MODE" == "true" ]]; then
        process_batch
    else
        if [[ ! -d "$OUTPUT_DIR" ]]; then
            mkdir -p "$OUTPUT_DIR" || {
                echo "Error: Cannot create output directory '$OUTPUT_DIR'"
                exit 1
            }
        fi
        process_directory
    fi
}

main "$@"