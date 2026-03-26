#!/bin/bash
# Usage: ./scsw_shift.sh [-e srt_ext] compare1.compare.txt [compare2.compare.txt ...]
# Reads the single reference line under each section in compare files,
# computes the time offset (sub_start - srt_start), and produces shifted
# subtitle files via ffmpeg in ./out under the current folder.

set -euo pipefail

SRT_EXT="srt"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--ext|--srt-ext)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: missing value for -e|--ext|--srt-ext" >&2
                exit 1
            fi
            SRT_EXT="$1"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-e srt_ext] compare1.compare.txt [compare2.compare.txt ...]"
            echo "Example: $0 -e srt out/*.compare.txt"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Error: unknown option $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 [-e srt_ext] compare1.compare.txt [compare2.compare.txt ...]" >&2
    exit 1
fi

SRT_EXT="${SRT_EXT#.}"
CURRENT_DIR="$PWD"
OUT_DIR="$CURRENT_DIR/out"
mkdir -p "$OUT_DIR"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "Error: ffmpeg is required but not found in PATH" >&2
    exit 1
fi

# Extract timestamp from section: returns first HH:MM:SS,mmm found after the
# separator line (------) of the named section.
extract_ts() {
    local file="$1"
    local ext="$2"
    awk -v ext="$ext" '
        /^\[/ {
            hdr = $0; gsub(/^\[|\]$/, "", hdr)
            in_section = (hdr ~ ext"$") ? 1 : 0
            past_sep = 0
            next
        }
        in_section && /^-+$/ { past_sep = 1; next }
        in_section && past_sep && /^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}/ {
            print $1
            exit
        }
    ' "$file"
}

ts_to_ms() {
    awk -v ts="$1" 'BEGIN {
        split(ts, a, /[,:]/)
        print a[1]*3600000 + a[2]*60000 + a[3]*1000 + a[4]
    }'
}

for COMPARE in "$@"; do
    if [[ ! -f "$COMPARE" ]]; then
        echo "Error: compare file not found: $COMPARE" >&2
        continue
    fi

    BASE="$(basename "$COMPARE")"
    BASE="${BASE%.compare.txt}"

    # Find source subtitle in the current folder, not near the compare file.
    SRT_FILE=$(find "$CURRENT_DIR" -maxdepth 1 -name "${BASE}*.${SRT_EXT}" | head -1)
    if [[ -z "$SRT_FILE" ]]; then
        echo "Error: no .${SRT_EXT} file found for base '$BASE' in $CURRENT_DIR" >&2
        continue
    fi

    srt_ts=$(extract_ts "$COMPARE" "srt")
    sub_ts=$(extract_ts "$COMPARE" "sub")

    if [[ -z "$srt_ts" ]]; then
        echo "Error: no .srt timestamp found in $COMPARE" >&2
        continue
    fi
    if [[ -z "$sub_ts" ]]; then
        echo "Error: no .sub timestamp found in $COMPARE" >&2
        continue
    fi

    srt_ms=$(ts_to_ms "$srt_ts")
    sub_ms=$(ts_to_ms "$sub_ts")
    offset=$((sub_ms - srt_ms))

    offset_sign="+"
    [[ $offset -lt 0 ]] && offset_sign=""
    itsoffset=$(awk -v ms="$offset" 'BEGIN { printf "%.3f", ms / 1000 }')

    OUTPUT="$OUT_DIR/$(basename "$SRT_FILE")"
    ffmpeg -v error -y -itsoffset "$itsoffset" -i "$SRT_FILE" -c:s srt "$OUTPUT"

    COMPARE_OUT="$OUT_DIR/$(basename "$COMPARE")"
    if [[ "$(realpath "$COMPARE")" != "$(realpath -m "$COMPARE_OUT")" ]]; then
        cp -f "$COMPARE" "$COMPARE_OUT"
    fi

    echo "Compare file  : $COMPARE"
    echo "SRT reference : $srt_ts"
    echo "SUB reference : $sub_ts"
    echo "Offset        : ${offset_sign}${offset}ms"
    echo "ffmpeg offset : ${itsoffset}s"
    echo "Written to    : $OUTPUT"
    echo "Copied compare: $COMPARE_OUT"
done
