#!/bin/bash
# Usage: ./scsw_shift.sh [-f from_ext] [-t to_ext] compare1.compare.txt [compare2.compare.txt ...]
# Computes an offset from compare file sections and applies it to source subtitle files.
# Supported source formats: SRT and ASS/SSA-style SUB (Dialogue lines).

set -euo pipefail

FROM_EXT="srt"
TO_EXT="sub"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--ext|--srt-ext)
            # Backward compatibility: old flag now maps to --from.
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: missing value for -e|--ext|--srt-ext" >&2
                exit 1
            fi
            FROM_EXT="$1"
            shift
            ;;
        -f|--from)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: missing value for -f|--from" >&2
                exit 1
            fi
            FROM_EXT="$1"
            shift
            ;;
        -t|--to)
            shift
            if [[ $# -eq 0 ]]; then
                echo "Error: missing value for -t|--to" >&2
                exit 1
            fi
            TO_EXT="$1"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-f from_ext] [-t to_ext] compare1.compare.txt [compare2.compare.txt ...]"
            echo "Examples:"
            echo "  $0 -f it.srt -t track2.eng.sub out/*.compare.txt"
            echo "  $0 -f track2.eng.sub -t track2.eng.sub out/*.compare.txt"
            echo "  $0 -f it.srt -t it.srt out/*.compare.txt"
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
    echo "Usage: $0 [-f from_ext] [-t to_ext] compare1.compare.txt [compare2.compare.txt ...]" >&2
    exit 1
fi

FROM_EXT="${FROM_EXT#.}"
TO_EXT="${TO_EXT#.}"

CURRENT_DIR="$PWD"
OUT_DIR="$CURRENT_DIR/out"
mkdir -p "$OUT_DIR"

# Extract timestamp from section: returns first HH:MM:SS,mmm found after the
# separator line (------) of the named section.
extract_ts() {
    local file="$1"
    local ext="$2"
    awk -v ext="$ext" '
        function ends_with(str, suffix) {
            if (length(str) < length(suffix)) return 0
            return substr(str, length(str) - length(suffix) + 1) == suffix
        }
        /^\[/ {
            hdr = $0
            gsub(/^\[|\]$/, "", hdr)
            in_section = ends_with(hdr, ext) ? 1 : 0
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

shift_srt_file() {
    local input="$1"
    local output="$2"
    local offset_ms="$3"

    awk -v off="$offset_ms" '
        function to_ms(ts, a) {
            split(ts, a, /[,:]/)
            return a[1]*3600000 + a[2]*60000 + a[3]*1000 + a[4]
        }
        function fmt_ms(ms, h, m, s, r) {
            if (ms < 0) ms = 0
            h = int(ms / 3600000); ms -= h * 3600000
            m = int(ms / 60000);   ms -= m * 60000
            s = int(ms / 1000);    r = ms - s * 1000
            return sprintf("%02d:%02d:%02d,%03d", h, m, s, r)
        }
        {
            gsub(/\r/, "")
            if (match($0, /^[0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3} --> [0-9]{2}:[0-9]{2}:[0-9]{2},[0-9]{3}$/)) {
                split($0, p, " --> ")
                s = fmt_ms(to_ms(p[1]) + off)
                e = fmt_ms(to_ms(p[2]) + off)
                print s " --> " e
            } else {
                print $0
            }
        }
    ' "$input" > "$output"
}

shift_sub_file() {
    local input="$1"
    local output="$2"
    local offset_ms="$3"

    awk -v off="$offset_ms" '
        function to_ms(ts, a, n, h, m, s, cs) {
            n = split(ts, a, /[.:]/)
            h  = a[1] + 0
            m  = a[2] + 0
            s  = a[3] + 0
            cs = (n >= 4) ? a[4] + 0 : 0
            return h*3600000 + m*60000 + s*1000 + cs*10
        }
        function fmt_sub(ms, h, m, s, cs) {
            if (ms < 0) ms = 0
            h = int(ms / 3600000); ms -= h * 3600000
            m = int(ms / 60000);   ms -= m * 60000
            s = int(ms / 1000);    ms -= s * 1000
            cs = int(ms / 10)
            return sprintf("%d:%02d:%02d.%02d", h, m, s, cs)
        }
        {
            gsub(/\r/, "")
            if ($0 ~ /^Dialogue:/) {
                n = split($0, a, ",")
                if (n >= 3) {
                    a[2] = fmt_sub(to_ms(a[2]) + off)
                    a[3] = fmt_sub(to_ms(a[3]) + off)
                    line = a[1]
                    for (i = 2; i <= n; i++) line = line "," a[i]
                    print line
                } else {
                    print $0
                }
            } else {
                print $0
            }
        }
    ' "$input" > "$output"
}

for COMPARE in "$@"; do
    if [[ ! -f "$COMPARE" ]]; then
        echo "Error: compare file not found: $COMPARE" >&2
        continue
    fi

    BASE="$(basename "$COMPARE")"
    BASE="${BASE%.compare.txt}"

    # Find source subtitle in the current folder, not near the compare file.
    SOURCE_FILE=$(find "$CURRENT_DIR" -maxdepth 1 -name "${BASE}*.${FROM_EXT}" | head -1)
    if [[ -z "$SOURCE_FILE" ]]; then
        echo "Error: no .${FROM_EXT} file found for base '$BASE' in $CURRENT_DIR" >&2
        continue
    fi

    from_ts=$(extract_ts "$COMPARE" "$FROM_EXT")
    to_ts=$(extract_ts "$COMPARE" "$TO_EXT")

    if [[ -z "$from_ts" ]]; then
        echo "Error: no .${FROM_EXT} timestamp found in $COMPARE" >&2
        continue
    fi
    if [[ -z "$to_ts" ]]; then
        echo "Error: no .${TO_EXT} timestamp found in $COMPARE" >&2
        continue
    fi

    from_ms=$(ts_to_ms "$from_ts")
    to_ms=$(ts_to_ms "$to_ts")
    offset=$((to_ms - from_ms))

    OUTPUT="$OUT_DIR/$(basename "$SOURCE_FILE")"
    case "$FROM_EXT" in
        *srt)
            shift_srt_file "$SOURCE_FILE" "$OUTPUT" "$offset"
            ;;
        *sub)
            shift_sub_file "$SOURCE_FILE" "$OUTPUT" "$offset"
            ;;
        *)
            echo "Error: unsupported source extension '.${FROM_EXT}'. Use an srt or sub-based extension." >&2
            continue
            ;;
    esac

    COMPARE_OUT="$OUT_DIR/$(basename "$COMPARE")"
    if [[ "$(realpath "$COMPARE")" != "$(realpath -m "$COMPARE_OUT")" ]]; then
        cp -f "$COMPARE" "$COMPARE_OUT"
    fi

    offset_sign="+"
    [[ $offset -lt 0 ]] && offset_sign=""
    echo "Compare file  : $COMPARE"
    echo "From          : .${FROM_EXT} ($from_ts)"
    echo "To            : .${TO_EXT} ($to_ts)"
    echo "Offset        : ${offset_sign}${offset}ms"
    echo "Written to    : $OUTPUT"
    echo "Copied compare: $COMPARE_OUT"
done
