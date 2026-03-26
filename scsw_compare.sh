#!/bin/bash
# Usage: ./scsw_compare.sh [folder] [rows] [ext1] [ext2]
# Finds paired files with configurable extensions sharing the same base name, transforms each
# with srt_to_oneline.sh / sub_to_oneline.sh, and produces a stacked
# comparison of the first N rows (default: 30).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FOLDER="${1:-.}"
ROWS="${2:-30}"
EXT1="${3:-srt}"
EXT2="${4:-sub}"
OUT_DIR="$PWD/out"

EXT1="${EXT1#.}"
EXT2="${EXT2#.}"

SRT_SCRIPT="$SCRIPT_DIR/lib/srt_to_oneline.sh"
SUB_SCRIPT="$SCRIPT_DIR/lib/sub_to_oneline.sh"

for s in "$SCRIPT_DIR/lib/srt_to_oneline.sh" "$SCRIPT_DIR/lib/sub_to_oneline.sh"; do
    if [[ ! -x "$s" ]]; then
        echo "Error: $s not found or not executable." >&2
        exit 1
    fi
done

mkdir -p "$OUT_DIR"

# Build associative arrays: base_name -> filepath
declare -A srt_map sub_map

while IFS= read -r -d '' f; do
    fname="$(basename "$f")"
    base="${fname%%.*}"
    srt_map["$base"]="$f"
done < <(find "$FOLDER" -maxdepth 1 -name "*.${EXT1}" -print0)

while IFS= read -r -d '' f; do
    fname="$(basename "$f")"
    base="${fname%%.*}"
    sub_map["$base"]="$f"
done < <(find "$FOLDER" -maxdepth 1 -name "*.${EXT2}" -print0)

matched=0

for base in "${!srt_map[@]}"; do
    if [[ -n "${sub_map[$base]+set}" ]]; then
        matched=1
        srt_file="${srt_map[$base]}"
        sub_file="${sub_map[$base]}"

        srt_ext="$(basename "$srt_file")"
        srt_ext="${srt_ext#*.}"          # e.g. it.srt
        sub_ext="$(basename "$sub_file")"
        sub_ext="${sub_ext#*.}"          # e.g. track2.eng.sub

        outfile="$OUT_DIR/${base}.compare.txt"

        # Transform and capture first N rows
        tmp_srt=$(mktemp)
        tmp_sub=$(mktemp)
        "$SRT_SCRIPT" "$srt_file" | head -n "$ROWS" > "$tmp_srt"
        "$SUB_SCRIPT" "$sub_file" | head -n "$ROWS" > "$tmp_sub"

        # Compute separator width as longest line across both files
        sep_width=$(awk '{ if (length > max) max = length } END { print max }' "$tmp_srt" "$tmp_sub")
        [[ -z "$sep_width" || "$sep_width" -lt 20 ]] && sep_width=60
        separator=$(printf '%*s' "$sep_width" '' | tr ' ' '-')

        {
            printf '[%s]\n' "$srt_ext"
            printf '%s\n' "$separator"
            cat "$tmp_srt"
            printf '\n[%s]\n' "$sub_ext"
            printf '%s\n' "$separator"
            cat "$tmp_sub"
        } > "$outfile"

        rm -f "$tmp_srt" "$tmp_sub"

        echo "Created: $outfile"
        echo "  srt : $(basename "$srt_file")"
        echo "  sub : $(basename "$sub_file")"
    fi
done

if [[ $matched -eq 0 ]]; then
    echo "No matching .${EXT1}/.${EXT2} pairs found in $FOLDER"
fi
