#!/bin/bash
# Usage: ./scsw_extract.sh [target_folder] [output_folder]
# Extracts all subtitle streams from each .mkv in target_folder.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [target_folder] [output_folder]"
    echo "Extract all subtitle streams from each .mkv in target_folder."
    echo "Default output folder: target_folder/out"
    exit 0
fi

TARGET_DIR="${1:-.}"
OUTPUT_DIR="${2:-$TARGET_DIR/out}"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: target folder not found: $TARGET_DIR" >&2
    exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
    echo "Error: ffprobe is required but not found in PATH" >&2
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is required but not found in PATH" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

codec_to_ext() {
    case "$1" in
        subrip) echo "srt" ;;
        ass|ssa) echo "ass" ;;
        webvtt) echo "vtt" ;;
        mov_text) echo "srt" ;;
        hdmv_pgs_subtitle) echo "sup" ;;
        dvd_subtitle|xsub) echo "ass" ;;
        *) echo "ass" ;;
    esac
}

sanitize() {
    tr -cd '[:alnum:]_.-' <<< "$1"
}

shopt -s nullglob
mkv_files=("$TARGET_DIR"/*.mkv)

if [[ ${#mkv_files[@]} -eq 0 ]]; then
    echo "No .mkv files found in $TARGET_DIR"
    exit 0
fi

for mkv in "${mkv_files[@]}"; do
    base="$(basename "$mkv" .mkv)"

    mapfile -t streams < <(
        ffprobe -v error \
            -select_streams s \
            -show_entries stream=index,codec_name:stream_tags=language,title \
            -of csv=p=0:s='|' \
            "$mkv"
    )

    if [[ ${#streams[@]} -eq 0 ]]; then
        echo "No subtitle streams in: $(basename "$mkv")"
        continue
    fi

    echo "Extracting from: $(basename "$mkv")"

    for row in "${streams[@]}"; do
        IFS='|' read -r stream_index codec language title <<< "$row"

        stream_index="${stream_index:-}"
        codec="${codec:-unknown}"
        language="${language:-und}"
        title="${title:-}"

        ext="$(codec_to_ext "$codec")"
        safe_lang="$(sanitize "$language")"
        [[ -z "$safe_lang" ]] && safe_lang="und"

        out_file="$OUTPUT_DIR/${base}.s${stream_index}.${safe_lang}.${ext}"

        # For text subtitles in mov_text, convert to srt for portability.
        if [[ "$codec" == "mov_text" ]]; then
            ffmpeg -v error -y -i "$mkv" -map 0:"$stream_index" -c:s srt "$out_file"
        else
            ffmpeg -v error -y -i "$mkv" -map 0:"$stream_index" -c:s copy "$out_file"
        fi

        if [[ -n "$title" ]]; then
            echo "  - stream $stream_index ($codec, lang=$safe_lang, title=$title) -> $(basename "$out_file")"
        else
            echo "  - stream $stream_index ($codec, lang=$safe_lang) -> $(basename "$out_file")"
        fi
    done

done

echo "Done. Extracted subtitles in: $OUTPUT_DIR"
