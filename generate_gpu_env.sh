#!/usr/bin/env bash
set -e

URL="https://rocm.docs.amd.com/en/latest/compatibility/compatibility-matrix.html"
OUTDIR="config/GPU"

echo "[INFO] Fetching ROCm compatibility matrix..."
HTML=$(curl -s "$URL")

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

count=0

while read -r OPT; do
    NAME=$(echo "$OPT" | grep -oP '>\K[^<]+')
    GFX=$(echo "$OPT" | grep -oP 'data-selector-extra-bindings='\''\{"gfx": "\K[^"]+')

    [ -z "$NAME" ] && continue
    [ -z "$GFX" ] && continue

    # AMD を削除してファイル名生成
    BASE=$(echo "$NAME" | sed 's/^AMD //')
    FILENAME=$(echo "$BASE" \
        | tr '[:lower:]' '[:upper:]' \
        | sed 's/[^A-Z0-9]/_/g' \
        | sed 's/_\+/_/g' \
        | sed 's/^_//;s/_$//')

    # GFX をファイル名から削除
    FILENAME=$(echo "$FILENAME" | sed -E 's/_GFX[0-9A-Z]+$//')

    #### SERIES 抽出 ####

    SERIES=""

    # Instinct MIxxx
    if echo "$NAME" | grep -q "Instinct MI"; then
        NUM=$(echo "$NAME" | grep -oP 'MI\K[0-9]+')
        SERIES="MI$(echo "$NUM" | sed 's/[0-9]$/00/')"
    fi

    # Radeon RX xxxx
    if echo "$NAME" | grep -q "Radeon RX"; then
        NUM=$(echo "$NAME" | grep -oP 'RX \K[0-9]+')
        SERIES="RX$(echo "$NUM" | sed 's/[0-9]$/000/')"
    fi

    # Radeon AI PRO Rxxxx
    if echo "$NAME" | grep -q "Radeon AI PRO R"; then
        NUM=$(echo "$NAME" | grep -oP 'R\K[0-9]+')
        SERIES="R$(echo "$NUM" | sed 's/[0-9]$/000/')"
    fi

    # Ryzen AI
    if echo "$NAME" | grep -q "Ryzen AI"; then
        NUM=$(echo "$NAME" | grep -oP '\b[0-9]{3}\b')
        SERIES="AI$(echo "$NUM" | sed 's/[0-9]$/00/')"
    fi

    FILEPATH="$OUTDIR/${FILENAME}.env"

    echo "[INFO] Generating ${FILENAME}.env"

    cat <<EOF > "$FILEPATH"
AMD_GPU="$NAME"
SERIES="$SERIES"
LLVM_TARGET="$GFX"
EOF

    count=$((count + 1))
done < <(echo "$HTML" | grep -oP '<option[^>]+>[^<]+')

echo "[INFO] Generated $count GPU definitions."