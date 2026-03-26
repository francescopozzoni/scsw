#!/bin/bash
# Usage: ./sub_to_oneline.sh input.sub [output.txt]
# Extracts Dialogue lines from ASS/SSA .sub files and outputs:
#   HH:MM:SS,mmm --> HH:MM:SS,mmm text

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 input.sub [output.txt]" >&2
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-}"

fmt_ts() {
    # Convert H:MM:SS.cs  ->  HH:MM:SS,mmm
    awk '{
        # split on : and .
        n = split($0, a, /[:.]/);
        h  = a[1] + 0
        m  = a[2] + 0
        s  = a[3] + 0
        cs = (n >= 4) ? a[4] + 0 : 0
        ms = cs * 10
        printf "%02d:%02d:%02d,%03d\n", h, m, s, ms
    }'
}

run() {
    grep -E '^Dialogue:' "$INPUT" | awk -F',' '
    function fmt(ts,    a, n, h, m, s, cs, ms) {
        n  = split(ts, a, /[.:]/)
        h  = a[1] + 0
        m  = a[2] + 0
        s  = a[3] + 0
        cs = (n >= 4) ? a[4] + 0 : 0
        ms = cs * 10
        return sprintf("%02d:%02d:%02d,%03d", h, m, s, ms)
    }
    {
        start = fmt($2)
        end   = fmt($3)
        # Text is everything after the 9th comma
        text = ""
        for (i = 10; i <= NF; i++) {
            text = (i == 10) ? $i : text "," $i
        }
        # Strip ASS inline tags: {...}
        gsub(/\{[^}]*\}/, "", text)
        # Strip \N and \n line breaks
        gsub(/\\[nN]/, " ", text)
        # Collapse multiple spaces
        gsub(/  +/, " ", text)
        # Trim leading/trailing spaces
        gsub(/^ +| +$/, "", text)
        print start " --> " end " " text
    }'
}

if [[ -n "$OUTPUT" ]]; then
    run > "$OUTPUT"
    echo "Written to $OUTPUT"
else
    run
fi
