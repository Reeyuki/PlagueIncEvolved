#!/bin/bash
set -e

BUILD_DIR="${1:-Build}"
PART_SIZE_MB=20
PART_SIZE_BYTES=$((PART_SIZE_MB * 1024 * 1024))

split_file() {
    local src="$1"
    local dest_prefix="$2"
    local basename
    basename=$(basename "$src")
    local total_bytes
    total_bytes=$(stat -c%s "$src")
    local total_mb
    total_mb=$(echo "scale=1; $total_bytes / 1048576" | bc)

    echo "Splitting $basename ($total_mb MB) into ${PART_SIZE_MB}MB parts..." >&2

    split -b "$PART_SIZE_BYTES" -d -a 4 "$src" "${dest_prefix}/${basename}.part"

    local part_num=1
    for f in "${dest_prefix}/${basename}.part"*; do
        local new_name="${dest_prefix}/${basename}.part${part_num}"
        mv "$f" "$new_name"
        part_num=$((part_num + 1))
    done

    local total_parts=$((part_num - 1))
    echo "  -> Created $total_parts parts" >&2
    echo "$total_parts"
}

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory '$BUILD_DIR' not found"
    exit 1
fi

MANIFEST_FILE="${BUILD_DIR}/chunk_manifest.json"
echo "{" > "$MANIFEST_FILE"
echo '  "files": [' >> "$MANIFEST_FILE"

first_entry=true

for filepath in "$BUILD_DIR"/*.data "$BUILD_DIR"/*.wasm; do
    [ -f "$filepath" ] || continue

    filename=$(basename "$filepath")
    total_bytes=$(stat -c%s "$filepath")
    total_parts_count=$(split_file "$filepath" "$BUILD_DIR")

    parts_json=""
    for i in $(seq 1 "$total_parts_count"); do
        part_file="${BUILD_DIR}/${filename}.part${i}"
        part_bytes=$(stat -c%s "$part_file")
        if [ -n "$parts_json" ]; then
            parts_json="${parts_json},"
        fi
        parts_json="${parts_json}
        {\"index\": $i, \"file\": \"${filename}.part${i}\", \"size\": $part_bytes}"
    done

    if [ "$first_entry" = false ]; then
        echo "    ," >> "$MANIFEST_FILE"
    fi
    first_entry=false

    cat >> "$MANIFEST_FILE" << EOF
    {
      "name": "$filename",
      "totalSize": $total_bytes,
      "parts": [$parts_json
      ]
    }
EOF

done

echo "  ]" >> "$MANIFEST_FILE"
echo "}" >> "$MANIFEST_FILE"

echo ""
echo "Manifest written to $MANIFEST_FILE"
echo "Done. Original .data and .wasm files can now be removed from the server if desired."
echo "To remove originals: rm Build/*.data Build/*.wasm"
