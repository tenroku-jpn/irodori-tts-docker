#!/bin/bash
set -e
 
URL=https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html
OUTDIR="config/GPU"
 
mkdir -p "$OUTDIR"
 
# パック定義
declare -A PACKS=(
    ["gfx110X-all"]="gfx1100,gfx1101"
    ["gfx103X-all"]="gfx1030,gfx1031"
    ["gfx1150"]="gfx1150"
    ["gfx1151"]="gfx1151"
    ["gfx1152"]="gfx1152"
    ["gfx90a"]="gfx90a"
    ["gfx908"]="gfx908"
    ["gfx120X-all"]="gfx1200,gfx1201"
    ["gfx90X-dcgpu"]="gfx90a,gfx908"
    ["gfx94X-dcgpu"]="gfx942,gfx940"
    ["gfx950-dcgpu"]="gfx950"
)
 
# キー名を大文字＋アンダーバー化
normalize_key() {
    echo "$1" \
        | tr '[:lower:]' '[:upper:]' \
        | sed 's/ /_/g' \
        | sed 's/[^A-Z0-9_]/_/g'
}
 
# gfx → PACK_NAME 判定
detect_pack() {
    local gfx="$1"
    for pack in "${!PACKS[@]}"; do
        IFS=',' read -ra arr <<< "${PACKS[$pack]}"
        for g in "${arr[@]}"; do
            [[ "$g" == "$gfx" ]] && echo "$pack" && return
        done
    done
    echo "$gfx"
}

 
echo "[INFO] Fetching AMD GPU table..."
html=$(curl -s "$URL" || echo "")
 
[[ -z "$html" ]] && {
    echo "[ERROR] Failed to fetch AMD page."
    exit 1
}
 
line=$(echo "$html" | tr '\n' ' ')
tables=$(echo "$line" | grep -oP '<table.*?</table>')
 
IFS=$'\n'
for table in $tables; do
    # ヘッダを抽出
    headers=($(echo "$table" \
        | grep -oP '<th[^>]*>.*?</th>' \
        | sed 's/<[^>]*>//g'))

    # 「GPU」というヘッダを持たないテーブルはスキップ
    echo "${headers[@]}" | grep -q "GPU" || continue
    
    rows=$(echo "$table" | grep -oP '<tr[^>]*>.*?</tr>')
 
    for row in $rows; do
        cols=($(echo "$row" \
            | grep -oP '<td[^>]*>.*?</td>' \
            | sed 's/<[^>]*>//g'))
 
        [[ ${#cols[@]} -eq 0 ]] && continue
        [[ ${#cols[@]} -ne ${#headers[@]} ]] && continue
 
        support="${cols[-1]}"
        echo "$support" | grep -q "✅" || continue
 
        gpu="${cols[0]}"
        llvm="${cols[2]}"
        pack=$(detect_pack "$llvm")
 
        fname=$(echo "$gpu" | tr ' /' '_' | tr '[:lower:]' '[:upper:]')
 
        echo "[INFO] Generating $fname.env"
 
        {
            for i in "${!headers[@]}"; do
                key=$(normalize_key "${headers[$i]}")
                val="${cols[$i]}"
                echo "${key}=\"${val}\""
            done
 
            # PACK_NAME を追加
            echo "PACK_NAME=\"${pack}\""
        } > "$OUTDIR/$fname.env"
    done
done
 
echo "[INFO] GPU env generation complete."
