#!/bin/bash
# Usage: ./scsw_compare.sh [folder] [rows] [ext1] [ext2]
# Finds paired files with configurable extensions sharing the same base name, transforms each
# with srt_to_oneline.sh / ass_to_oneline.sh, and produces a stacked
# comparison of the first N rows (default: 30).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FOLDER="${1:-.}"
ROWS="${2:-30}"
EXT1="${3:-srt}"
EXT2="${4:-ass}"
OUT_DIR="$PWD/out"

EXT1="${EXT1#.}"
EXT2="${EXT2#.}"

SRT_SCRIPT="$SCRIPT_DIR/lib/srt_to_oneline.sh"
SUB_SCRIPT="$SCRIPT_DIR/lib/ass_to_oneline.sh"

for s in "$SCRIPT_DIR/lib/srt_to_oneline.sh" "$SCRIPT_DIR/lib/ass_to_oneline.sh"; do
    if [[ ! -x "$s" ]]; then
        echo "Error: $s not found or not executable." >&2
        exit 1
    fi
done

pick_converter() {
    local ext="$1"
    case "$ext" in
        *srt) echo "$SRT_SCRIPT" ;;
        *ass) echo "$SUB_SCRIPT" ;;
        *)
            echo "Error: unsupported extension '.${ext}'. Use an srt- or ass-based extension." >&2
            return 1
            ;;
    esac
}

CONV1="$(pick_converter "$EXT1")" || exit 1
CONV2="$(pick_converter "$EXT2")" || exit 1

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
        file1="${srt_map[$base]}"
        file2="${sub_map[$base]}"

        ext1_name="$(basename "$file1")"
        ext1_name="${ext1_name#*.}"          # e.g. it.srt
        ext2_name="$(basename "$file2")"
        ext2_name="${ext2_name#*.}"          # e.g. track2.eng.ass

        outfile="$OUT_DIR/${base}.compare.txt"

        # Transform and capture first N rows
        tmp_1=$(mktemp)
        tmp_2=$(mktemp)
        "$CONV1" "$file1" | head -n "$ROWS" > "$tmp_1"
        "$CONV2" "$file2" | head -n "$ROWS" > "$tmp_2"

        # Compute separator width as longest line across both files
        sep_width=$(awk '{ if (length > max) max = length } END { print max }' "$tmp_1" "$tmp_2")
        [[ -z "$sep_width" || "$sep_width" -lt 20 ]] && sep_width=60
        separator=$(printf '%*s' "$sep_width" '' | tr ' ' '-')

        {
            printf '[%s]\n' "$ext1_name"
            printf '%s\n' "$separator"
            if [[ -s "$tmp_1" ]]; then
                cat "$tmp_1"
            else
                printf '[No lines parsed]\n'
            fi
            printf '\n[%s]\n' "$ext2_name"
            printf '%s\n' "$separator"
            if [[ -s "$tmp_2" ]]; then
                cat "$tmp_2"
            else
                printf '[No lines parsed]\n'
            fi
        } > "$outfile"

        rm -f "$tmp_1" "$tmp_2"

        echo "Created: $outfile"
        echo "  ${EXT1}: $(basename "$file1")"
        echo "  ${EXT2}: $(basename "$file2")"
    fi
done

if [[ $matched -eq 0 ]]; then
    echo "No matching .${EXT1}/.${EXT2} pairs found in $FOLDER"
fi
