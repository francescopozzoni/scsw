#!/bin/bash
# Usage: ./srt_to_oneline.sh input.srt [output.txt]
# Converts each SRT block to: timestamp --> timestamp text (single line)

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 input.srt [output.txt]" >&2
    exit 1
fi

INPUT="$1"
OUTPUT="${2:-}"

run() {
awk '
{
    gsub(/\r/, "")
}
/^[0-9]+$/ { next }
/-->/ {
    if (ts != "") print ts " " text
    ts = $0
    text = ""
    next
}
/^[[:space:]]*$/ { next }
{
    text = (text == "") ? $0 : text " " $0
}
END {
    if (ts != "") print ts " " text
}
' "$INPUT"
}

if [[ -n "$OUTPUT" ]]; then
    run > "$OUTPUT"
else
    run
fi

if [[ -n "$OUTPUT" ]]; then
    echo "Written to $OUTPUT"
fi
