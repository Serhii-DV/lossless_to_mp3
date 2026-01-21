# Lossless Audio to MP3 Converter

A powerful bash script that converts audio files (FLAC, WAV, M4A, AIFF, APE) to high-quality MP3 format (320kbps) while preserving folder structure and metadata. Features include **CUE file support** for splitting solid audio files, single album and batch processing modes with intelligent file filtering.

## Prerequisites

Before using this script, you need to install **ffmpeg**:

### Ubuntu/Debian

```bash
sudo apt update && sudo apt install ffmpeg
```

### For CUE File Support (Optional)

To enable CUE file splitting for solid audio files, install additional tools:

```bash
sudo apt update && sudo apt install shntool cuetools
```

**Note**: The script will work without these tools but will skip CUE file processing with a warning.

### Other Linux distributions

- **CentOS/RHEL/Fedora**: `sudo yum install ffmpeg` or `sudo dnf install ffmpeg`
- **Arch Linux**: `sudo pacman -S ffmpeg`
- **macOS**: `brew install ffmpeg`

### Verify Installation

Check that ffmpeg is properly installed:

```bash
ffmpeg -version
```

## Supported Formats

### Input Formats

- **FLAC** - Free Lossless Audio Codec
- **WAV** - Waveform Audio File Format
- **M4A** - MPEG-4 Audio (including AAC and ALAC)
- **AIFF** - Audio Interchange File Format
- **APE** - Monkey's Audio (lossless compression)
- **CUE** - Cue sheets for splitting solid audio files

### Output Format

- **MP3** - 320kbps constant bitrate with full metadata preservation

### Additional Features

- **CUE file splitting** - Automatically splits solid audio files using cue sheets
- **PNG → JPG** conversion for album artwork
- **File filtering** via configuration file
- **Intelligent path handling** for artist/album structure

## Usage

### Basic Syntax

```bash
./lossless_to_mp3.sh -i INPUT_DIR [-o OUTPUT_DIR] [-c CONFIG_FILE] [-b]
```

### Options

- `-i, --input DIR` - **Required**: Input directory containing audio files
- `-o, --output DIR` - **Optional**: Output directory for converted MP3 files
- `-b, --batch` - **Optional**: Batch mode for processing multiple albums
- `-c, --config FILE` - **Optional**: Configuration file for ignored extensions
- `-h, --help` - Show help message

## Operation Modes

### 1. Single Album Mode (Default)

Process one specific album directory:

```bash
./lossless_to_mp3.sh -o /output/path -i /music/Artist/Album
```

**Result**: Creates `/output/path/Artist/Album/` with converted files

**Use case**: Converting individual albums with automatic artist/album path extraction

### 2. Batch Mode

Process all album subdirectories within an artist folder:

```bash
./lossless_to_mp3.sh -b -o /output/path -i /music/Artist
```

**Result**: Creates `/output/path/Artist/Album1/`, `/output/path/Artist/Album2/`, etc.

**Use case**: Converting entire discographies or multiple albums at once

## Configuration File

Create a `.ignore` file in the script directory to ignore specific file extensions:

```bash
# Configuration file for ignored extensions
# One extension per line (without dots)
# Lines starting with # are comments

log
m3u
m3u8
cue
nfo
sfv
md5
txt
accurip
mpg
url

```

**Custom config file**:

```bash
./lossless_to_mp3.sh -i /input -o /output -c /path/to/custom.ignore
```

## Examples

### Single Album Conversion

Convert one album with automatic output structure:

```bash
./lossless_to_mp3.sh -i "~/Music/Artist/Album Name"
```

**Creates**: `~/Music/Artist/Album Name (mp3)/`

Convert one album to specific location:

```bash
./lossless_to_mp3.sh -o "/storage/mp3" -i "~/Music/Artist/Album"
```

**Creates**: `/storage/mp3/Artist/Album/`

### Batch Processing

Convert all albums by an artist:

```bash
./lossless_to_mp3.sh -b -o "/storage/mp3" -i "~/Music/Artist"
```

**Creates**:

- `/storage/mp3/Artist/Album1/`
- `/storage/mp3/Artist/Album2/`
- `/storage/mp3/Artist/Album3/`

### With Custom Configuration

Ignore specific file types during processing:

```bash
./lossless_to_mp3.sh -i "~/Music/Album" -c "~/my-ignore-list.txt"
```

## Features

- **Multi-Format Support**: Converts FLAC, WAV, M4A, AIFF and APE to MP3
- **CUE File Support**: Automatically detects and splits solid audio files using cue sheets
- **Dual Processing Modes**: Single album or batch processing
- **High Quality**: 320kbps MP3 output with full metadata preservation
- **Intelligent Track Naming**: Extracts track titles from CUE files when available
- **Smart Audio Processing**:
  - CUE files processed first to split solid files into tracks
  - Individual audio files processed after CUE splitting
  - Avoids double-processing files already split from CUE files
- **Intelligent Paths**: Automatic artist/album directory structure detection
- **Smart File Handling**:
  - PNG → JPG conversion for album artwork
  - Configurable file filtering (ignore logs, cue sheets, etc.)
  - Preservation of other files (lyrics, artwork, etc.)
- **Robust Processing**:
  - Progress tracking and detailed summaries
  - Skip existing files to resume interrupted conversions
  - Comprehensive error handling and reporting
- **Flexible Configuration**: External config file for ignored extensions

## File Processing Logic

### CUE File Processing (Priority)

1. **CUE Detection**: Scans for `.cue` files in input directory
2. **Audio Matching**: Locates associated solid audio files (FLAC/WAV/AIFF/APE/M4A)
3. **Track Splitting**: Uses `cuebreakpoints` and `shnsplit` to split into individual tracks
4. **Track Naming**: Extracts track titles from CUE file or uses "Track XX" format
5. **MP3 Conversion**: Converts each split track directly to MP3 (320kbps)

### Audio Conversion

- **Individual FLAC/WAV/M4A/AIFF/APE** → **MP3** (320kbps, metadata preserved)
- **Note**: Files already processed via CUE splitting are automatically excluded

### Image Processing

- **PNG** → **JPG** (high quality, preserves album artwork)

### File Filtering

- Files with extensions in `.ignore` are **ignored**
- All other files are **copied** to maintain album completeness

### Path Structure

```txt
Single Mode Input:  /music/Artist/Album/
Single Mode Output: /output/Artist/Album/

Batch Mode Input:   /music/Artist/
Batch Mode Output:  /output/Artist/Album1/, /output/Artist/Album2/, ...
```

## Output Structure Examples

### Single Album Mode with CUE File

```txt
Input:
~/Music/Artist/Album Name/
├── Album.flac           # solid audio file
├── Album.cue            # cue sheet with track info
├── cover.png
├── artwork.jpg
├── album.log            # ignored (if in .ignore)
└── tracklist.txt

Output:
~/Music/Artist/Album Name (mp3)/
├── 01 - Opening Song.mp3     # split from solid file
├── 02 - Main Theme.mp3       # using CUE track titles
├── 03 - Interlude.mp3
├── 04 - Final Track.mp3
├── cover.jpg                 # PNG converted to JPG
├── artwork.jpg               # copied as-is
└── tracklist.txt             # copied as-is
```

### Single Album Mode with Individual Files

```txt
Input:
~/Music/Artist/Album Name/
├── 01 - Track One.flac
├── 02 - Track Two.wav
├── 03 - Track Three.m4a
├── 04 - Track Four.aiff
├── 05 - Track Five.ape
├── bonus/
│   └── hidden.flac
├── cover.png
├── artwork.jpg
├── album.log         # ignored (if in .ignore)
└── tracklist.cue     # ignored (if in .ignore)

Output:
~/Music/Artist/Album Name (mp3)/  [or custom path/Artist/Album Name/]
├── 01 - Track One.mp3
├── 02 - Track Two.mp3
├── 03 - Track Three.mp3
├── 04 - Track Four.mp3
├── 05 - Track Five.mp3
├── bonus/
│   └── hidden.mp3
├── cover.jpg         # PNG converted to JPG
└── artwork.jpg       # copied as-is
```

### Batch Mode

```txt
Input:
~/Music/Artist/
├── Album 1/
│   ├── track1.flac
│   └── cover.png
└── Album 2/
    ├── track1.wav
    └── artwork.jpg

Output:
~/output/Artist/
├── Album 1/
│   ├── track1.mp3
│   └── cover.jpg     # PNG → JPG
└── Album 2/
    ├── track1.mp3
    └── artwork.jpg   # copied as-is
```

## Processing Summary Reports

The script provides detailed progress information:

### CUE File Processing Summary

```txt
Found 1 CUE file(s) for audio splitting
Processing CUE file: Album.cue
Associated audio file: Album.flac
Splitting audio file using CUE sheet...
✓ Successfully split audio file
Converting track 1: Opening Song
✓ Successfully converted: 01 - Opening Song.mp3
Converting track 2: Main Theme
✓ Successfully converted: 02 - Main Theme.mp3
[...]

=== CUE Split Conversion Summary ===
Total tracks split: 12
Successfully converted: 12
Failed conversions: 0
```

### Single Album Summary

```txt
=== Conversion Summary ===
Total audio files found: 12
Successfully converted: 12
Failed conversions: 0

=== File Processing Summary ===
PNG files converted to JPG: 2
Failed PNG conversions: 0
Other files copied: 8
Files ignored: 4
Failed copies: 0
```

### Batch Mode Summary

```txt
=== Batch Processing Summary ===
Total albums found: 5
Successfully processed: 5
Failed: 0

[Individual album summaries for each processed album]
```

## Technical Details

- **Audio Codec**: libmp3lame (LAME MP3 encoder)
- **Bitrate**: 320kbps (constant bitrate)
- **ID3 Version**: v2.3 with v1 fallback
- **Metadata Mapping**: Preserves all metadata from source files
- **Supported Input**: FLAC, WAV, M4A, AIFF, APE audio files
- **Image Processing**: PNG to JPG conversion using ffmpeg
- **Path Resolution**: Robust handling with realpath for symbolic links
- **Configuration**: External file support with comment and whitespace handling

## Advanced Usage

### Large Collections Processing

For very large music collections, consider using batch mode with screen/tmux:

```bash
# Start a screen session
screen -S music_conversion

# Run batch conversion
./lossless_to_mp3.sh -b -i "/storage/lossless" -o "/storage/mp3"

# Detach with Ctrl+A, D
# Reattach later with: screen -r music_conversion
```

### Custom Ignore Lists

Create different configuration files for different purposes:

```bash
# Minimal ignore list (logs only)
./lossless_to_mp3.sh -i ~/Music/Album -c .ignore.minimal

# Complete ignore list (logs, cue, artwork, etc.)
./lossless_to_mp3.sh -i ~/Music/Album -c .ignore.complete
```

### Resuming Interrupted Conversions

The script automatically skips existing files, making it safe to re-run:

```bash
# First run (interrupted)
./lossless_to_mp3.sh -b -i "/music/artist" -o "/mp3"

# Resume conversion (skips completed files)
./lossless_to_mp3.sh -b -i "/music/artist" -o "/mp3"
```

## Error Handling & Troubleshooting

### Common Issues

#### Permission Denied

```bash
chmod +x lossless_to_mp3.sh
```

#### ffmpeg Not Found

Ensure ffmpeg is in your PATH:

```bash
which ffmpeg
# If not found, install or add to PATH
export PATH="/usr/local/bin:$PATH"
```

#### CUE File Tools Not Found

If you want CUE file support, install the required tools:

```bash
sudo apt update && sudo apt install shntool cuetools

# Verify installation
which shnsplit cuebreakpoints
```

#### Config File Issues

- Ensure `.ignore` file exists in script directory or specify with `-c`
- Check file permissions: `chmod 644 .ignore`
- Verify format: one extension per line, no dots

#### Path Issues

- Use absolute paths for reliability
- Escape spaces in directory names or use quotes
- Verify input directories exist and are readable

### Error Types Handled

- Missing or corrupted input files
- Insufficient disk space
- Permission issues
- Invalid audio format detection
- Network interruptions (for network storage)
- Configuration file parsing errors

## Performance Tips

1. **Use SSD storage** for faster I/O operations
2. **Batch mode** is more efficient for multiple albums
3. **Screen/tmux** for large collections to prevent interruption
4. **Check disk space** before starting large conversions
5. **Close other applications** to free up system resources

## Configuration Examples

### Minimal .ignore (basic cleanup)

```txt
# Ignore only log files
log
```

### Standard .ignore (recommended)

```txt
# Standard ignore list for music conversion
log
m3u
m3u8
cue
nfo
sfv
md5
txt
accurip
mpg
url

```

### Complete .ignore (maximum cleanup)

```txt
# Complete ignore list - keeps only audio and essential files
log
m3u
cue
nfo
sfv
md5
txt
accurip
dr
torrent
url
ini
db
```

## License

This script is provided as-is for personal use. Feel free to modify and distribute.
