#!/bin/bash
set -e
 
sudo -v
 
echo '============================================'
echo '5-1. System package install'
echo '============================================'
 
sudo apt update
sudo apt install -y git wget curl build-essential \
                    python3-setuptools python3-wheel python3-pip python3-dev pkg-config \
                    fzf libatomic1 libquadmath0 gcc g++ cmake
 
CONFIG_DIR=config
 
########################################
# 1. Adrenaline 選択（fzf）
########################################
 
cd ~/docker/irodori-tts-docker
 
adrenalin=$(find "$CONFIG_DIR/Adrenalin" -maxdepth 1 -type f -name "*.env" \
    | xargs -n1 basename | sed 's/.env$//' \
    | sort -V \
    | fzf --prompt="Adrenalin バージョン > ")
 
if [[ -z "$adrenalin" ]]; then
    echo "キャンセルされました"
    exit 1
fi
 
echo "選択: $adrenalin"
source "$CONFIG_DIR/Adrenalin/$adrenalin.env"
 
########################################
# 2. GPU 選択（fzf）
########################################
 
gpu=$(find "$CONFIG_DIR/GPU" -maxdepth 1 -type f -name "*.env" \
    | xargs -n1 basename | sed 's/.env$//' \
    | sort -V \
    | fzf --prompt="GPU ハードウェア > ")
 
if [[ -z "$gpu" ]]; then
    echo "キャンセルされました"
    exit 1
fi
 
echo "選択: $gpu"
source "$CONFIG_DIR/GPU/$gpu.env"
 
########################################
# 3. config.env を生成
########################################
 
ROCM_VERSION_SHORT=${ROCM_VERSION%.*}
 
cat <<EOF > config.env
ROCM_VERSION="$ROCM_VERSION"
ROCM_VERSION_SHORT="$ROCM_VERSION_SHORT"
TORCH_VERSION="$TORCH_VERSION"
VISION_VERSION="$VISION_VERSION"
AUDIO_VERSION="$AUDIO_VERSION"
TRITON_VERSION="$TRITON_VERSION"
WHEEL_URL="$WHEEL_URL"
GPU_FILE="$GPU_FILE"
GPU_URL="$GPU_URL"
 
AMD_GPU="$AMD_GPU"
SERIES="$SERIES"
LLVM_TARGET="$LLVM_TARGET"
 
EOF
 
echo "config.env を生成しました:"
cat config.env
 
echo '============================================'
echo '5-2. ROCm for WSL install                   '
echo '============================================'
# ROCm installation (based on AMD's official documentation)
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/native_linux/install-radeon.html
#            https://rocm.docs.amd.com/en/docs-7.14.0/install/rocm.html
 
if command -v rocminfo >/dev/null 2>&1; then
    echo "ROCm already installed. Skipping."
else
 
        if dpkg --compare-versions "$ROCM_VERSION_SHORT" ge "7.9"; then
            echo "Install Preview series (7.9+)"
 
                # Add the current user to the render and video groups
                sudo usermod -a -G render,video $LOGNAME
               
                # Download and install GPG key
                sudo mkdir --parents --mode=0755 /etc/apt/keyrings
 
                # ROCm release signing key
                wget https://repo.amd.com/rocm/packages-multi-arch/gpg/rocm.gpg -O - | \
                    gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg > /dev/null
 
                sudo tee /etc/apt/sources.list.d/rocm.list << EOF
                deb [arch=amd64 signed-by=/etc/apt/keyrings/amdrocm.gpg] https://repo.amd.com/rocm/packages-multi-arch/ubuntu2404 stable main
EOF
 
                sudo apt update
               
                sudo apt install -y amdrocm${ROCM_VERSION_SHORT}-${LLVM_TARGET}
        else
            echo "Install Production series (7.0 - 7.8)"
 
            cd ~
            sudo apt update
       
            if [ ! -f "$GPU_FILE" ]; then
                wget "$GPU_URL"
            fi
       
            sudo apt install -y "./${GPU_FILE}"
            sudo amdgpu-install -y --usecase=rocm --no-dkms
        fi
fi
 
echo
echo '============================================'
echo '5-3. Build librocdxg                        '
echo '============================================'
# Build librocdxg, the DXG bridge library required by ROCm on WSL2
# Reference: https://github.com/ROCm/librocdxg
 
 
cd ~
 
if [ ! -d librocdxg ]; then
    git clone https://github.com/ROCm/librocdxg.git
else
    cd librocdxg
    git pull
    cd ..
fi
 
cd librocdxg
 
# Set the Windows SDK path (adjust version number if different)
export win_sdk='/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/'
 
# Build the library
mkdir -p build
cd build
cmake .. -DWIN_SDK="${win_sdk}/shared"
make -j"$(nproc)"
sudo make install
 
# Before proceeding, cd /path/to/librocdxg/
cd ..
cd amdsmi
cmake -B build -DWIN_SDK="${win_sdk}/shared" .
cmake --build build -j"$(nproc)"
sudo cmake --install build
source /etc/profile.d/rocdxg-amd-smi-lib.sh
 
echo
echo '============================================'
echo '5-4. GPU detection                          '
echo '============================================'

cd ~/docker/irodori-tts-docker

export HSA_ENABLE_DXG_DETECTION=1
 
grep -q "HSA_ENABLE_DXG_DETECTION=1" ~/.bashrc || \
    echo 'export HSA_ENABLE_DXG_DETECTION=1' >> ~/.bashrc
 
if ! rocminfo | grep -iq gfx; then
    echo '[WARNING] GPU may not be detected correctly.'
fi

echo
echo '============================================'
echo '5-5. make docker-compose.yml                '
echo '============================================'

cd ~/docker/irodori-tts-docker

if dpkg --compare-versions "$ROCM_VERSION_SHORT" ge "7.9"; then
    echo "Preview series (7.9+) 用 docker-compose.yml を生成"

    cat > docker-compose.yml << EOF
services:
  irodori:
    build:
      context: .
      dockerfile: Dockerfile

    container_name: irodori-tts
    restart: unless-stopped

    ports:
      - "7860:7860"
      - "7861:7861"
      - "8088:8088"

    group_add:
      - video

    volumes:
      # override パッチ
      - ./overrides/infer.py:/opt/Irodori-TTS/infer.py
      - ./overrides/gradio_app.py:/opt/Irodori-TTS/gradio_app.py
      - ./overrides/gradio_app_voicedesign.py:/opt/Irodori-TTS/gradio_app_voicedesign.py
      - ./overrides/irodori_tts/inference_runtime.py:/opt/Irodori-TTS/irodori_tts/inference_runtime.py
      - ./overrides/irodori_tts/rocm_compat.py:/opt/Irodori-TTS/irodori_tts/rocm_compat.py

      # benchmark
      - ./benchmark.py:/opt/Irodori-TTS/benchmark.py

      # ROCm ライブラリ (7.9+ / core-7.14 系)
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/lib/llvm/amdgcn/:/opt/rocm/amdgcn/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/bin/:/opt/rocm/bin/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/:/opt/rocm/core/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/:/opt/rocm/core-7/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/include/:/opt/rocm/include/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/lib/:/opt/rocm/lib/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/libexec/:/opt/rocm/libexec/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/lib/llvm/:/opt/rocm/llvm/
      - /opt/rocm/core-${ROCM_VERSION_SHORT}/share/:/opt/rocm/share/
      - /usr/lib/wsl/lib/:/usr/lib/wsl/lib/

      # キャッシュ
      - ./miopen-cache:/tmp/miopen-cache
      - ./hf-cache:/root/.cache/huggingface

      # 出力
      - ./outputs:/opt/Irodori-TTS/gradio_outputs

      # ログファイル
      - ./logs/irodori:/var/log/irodori

      # ボイスファイル
      - ./voices:/app/voices

    devices:
      - /dev/dxg:/dev/dxg

    cap_add:
      - SYS_PTRACE

    security_opt:
      - seccomp=unconfined

    ipc: host
    shm_size: "8g"

    healthcheck:
      disable: true
EOF

else
    echo "Production series (7.0 - 7.8) 用 docker-compose.yml を生成"

    cat > docker-compose.yml << EOF
services:
  irodori:
    build:
      context: .
      dockerfile: Dockerfile

    container_name: irodori-tts
    restart: unless-stopped

    ports:
      - "7860:7860"
      - "7861:7861"
      - "8088:8088"

    group_add:
      - video

    volumes:
      # override パッチ
      - ./overrides/infer.py:/opt/Irodori-TTS/infer.py
      - ./overrides/gradio_app.py:/opt/Irodori-TTS/gradio_app.py
      - ./overrides/gradio_app_voicedesign.py:/opt/Irodori-TTS/gradio_app_voicedesign.py
      - ./overrides/irodori_tts/inference_runtime.py:/opt/Irodori-TTS/irodori_tts/inference_runtime.py
      - ./overrides/irodori_tts/rocm_compat.py:/opt/Irodori-TTS/irodori_tts/rocm_compat.py

      # benchmark
      - ./benchmark.py:/opt/Irodori-TTS/benchmark.py

      # ROCm ライブラリ (7.0〜7.8 / ざっくり版)
      - /opt/rocm/lib/:/opt/rocm/lib/
      - /usr/lib/wsl/lib/:/usr/lib/wsl/lib/

      # キャッシュ
      - ./miopen-cache:/tmp/miopen-cache
      - ./hf-cache:/root/.cache/huggingface

      # 出力
      - ./outputs:/opt/Irodori-TTS/gradio_outputs

      # ログファイル
      - ./logs/irodori:/var/log/irodori

      # ボイスファイル
      - ./voices:/app/voices

    devices:
      - /dev/dxg:/dev/dxg

    cap_add:
      - SYS_PTRACE

    security_opt:
      - seccomp=unconfined

    ipc: host
    shm_size: "8g"

    healthcheck:
      disable: true
EOF
fi
 
echo
echo '============================================'
echo '5-6. Docker availability check'
echo '============================================'
 
 
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi
 
echo
echo '============================================'
echo '5-7. Docker build'
echo '============================================'

$COMPOSE build --no-cache
 
echo
echo '============================================'
echo '5-8. Docker start'
echo '============================================'
$COMPOSE up -d

echo '============================================'
echo '5-9. Create WSL launcher script (launch.sh)'
echo '============================================'

LAUNCH_DIR="$HOME/.local/share/irodori-tts"
mkdir -p "$LAUNCH_DIR"

cat > "$LAUNCH_DIR/launch.sh" << 'EOF'
#!/usr/bin/env bash
set -e
cd ~/docker/irodori-tts-docker
docker compose up -d
EOF

chmod +x "$LAUNCH_DIR/launch.sh"

echo "Created: $LAUNCH_DIR/launch.sh"

echo '============================================'
echo '5-10. Create Windows shortcut via PowerShell'
echo '============================================'

# Windows のユーザー名を取得
WINUSER=$(powershell.exe -NoProfile -Command '$env:USERNAME' | tr -d '\r')

# プロジェクト側のアイコン（あればコピー）
ICON_SRC="$HOME/docker/irodori-tts-docker/irodori-tts.ico"

# Unsloth と同じ仕組みだがアプリ名は Irodori-TTS（安定パス）
ICON_DST_DIR="/mnt/c/Users/$WINUSER/AppData/Local/Irodori-TTS"
ICON_DST="$ICON_DST_DIR/irodori-tts.ico"

mkdir -p "$ICON_DST_DIR"
if [ -f "$ICON_SRC" ]; then
    cp -f "$ICON_SRC" "$ICON_DST"
fi

# WSL の distro とランチャー
DISTRO="${WSL_DISTRO_NAME:-}"
LAUNCHER="$HOME/.local/share/irodori-tts/launch.sh"

# Build wsl args like Unsloth does (double-quoted distro and launcher)
_css_wsl_args=""
if [ -n "$DISTRO" ]; then
    _css_wsl_args="-d \"$DISTRO\" "
fi
_css_wsl_args="${_css_wsl_args}-- bash -l -c \"exec \\\"$LAUNCHER\\\"\""

# Detect whether Windows Terminal (wt.exe) is available
_css_use_wt=false
if command -v wt.exe >/dev/null 2>&1; then
    _css_use_wt=true
fi

if [ "$_css_use_wt" = true ]; then
    _css_sc_target='wt.exe'
    _css_sc_args="wsl.exe $_css_wsl_args"
else
    _css_sc_target='wsl.exe'
    _css_sc_args="$_css_wsl_args"
fi

# Escape single quotes for PowerShell single-quoted string embedding
_css_sc_args_ps=$(printf '%s' "$_css_sc_args" | sed "s/'/''/g")

# Shortcut name per-distro (Irodori-TTS style)
if [ -n "$DISTRO" ]; then
    _css_lnk_name="Irodori-TTS (WSL - ${DISTRO}).lnk"
else
    _css_lnk_name="Irodori-TTS (WSL).lnk"
fi
_css_lnk_name_ps=$(printf '%s' "$_css_lnk_name" | sed "s/'/''/g")

# Create temp PowerShell script
_css_ps1_tmp=$(mktemp /tmp/irodori-tts-shortcut-XXXXXX.ps1 2>/dev/null) || true
if [ -n "$_css_ps1_tmp" ]; then
    cat > "$_css_ps1_tmp" << WSLPS1_EOF
\$WshShell = New-Object -ComObject WScript.Shell
\$targetExe = (Get-Command '$_css_sc_target' -ErrorAction SilentlyContinue).Source
if (-not \$targetExe) { exit 1 }

# Icon path in LOCALAPPDATA for Irodori-TTS
\$iconDir = Join-Path \$env:LOCALAPPDATA 'Irodori-TTS'
\$iconPath = Join-Path \$iconDir 'irodori-tts.ico'
\$preIconHash = \$null
if (Test-Path -LiteralPath \$iconPath) {
    try { \$preIconHash = (Get-FileHash -LiteralPath \$iconPath -Algorithm SHA256).Hash } catch {}
}
if (-not (Test-Path -LiteralPath \$iconPath)) {
    try {
        New-Item -ItemType Directory -Force -Path \$iconDir | Out-Null
        # (Optional) network fetch omitted; WSL already copied icon if available
    } catch {}
}
\$hasIcon = \$false
if (Test-Path -LiteralPath \$iconPath) {
    try { \$b = [System.IO.File]::ReadAllBytes(\$iconPath); if (\$b.Length -ge 4 -and \$b[0] -eq 0 -and \$b[1] -eq 0 -and \$b[2] -eq 1 -and \$b[3] -eq 0) { \$hasIcon = \$true } } catch {}
}

\$locations = @(
    [Environment]::GetFolderPath('Desktop'),
    (Join-Path \$env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
)
\$created = @()
\$firstShortcut = \$false

foreach (\$dir in \$locations) {
    if (-not \$dir -or -not (Test-Path \$dir)) { continue }
    \$linkPath = Join-Path \$dir '$_css_lnk_name_ps'
    if (-not (Test-Path -LiteralPath \$linkPath)) { \$firstShortcut = \$true }
    \$shortcut = \$WshShell.CreateShortcut(\$linkPath)
    \$shortcut.TargetPath = \$targetExe
    \$shortcut.Arguments = '$_css_sc_args_ps'
    \$shortcut.Description = 'Launch Irodori-TTS (WSL)'
    if (\$hasIcon) { \$shortcut.IconLocation = "\$iconPath,0" }
    \$shortcut.Save()
    \$created += \$linkPath
}

\$iconChanged = \$false
if (\$hasIcon) {
    if (-not \$preIconHash) {
        \$iconChanged = \$true
    } else {
        try {
            \$postIconHash = (Get-FileHash -LiteralPath \$iconPath -Algorithm SHA256).Hash
            \$iconChanged = (\$postIconHash -ne \$preIconHash)
        } catch { \$iconChanged = \$true }
    }
} elseif (\$preIconHash) {
    \$iconChanged = \$true
}

# Per-item refresh (SHChangeNotify on each created .lnk), then global assoc change
try {
    Add-Type -Namespace IrodoriShell -Name IconRefresh -MemberDefinition '[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern void SHChangeNotify(int e, uint f, string a, System.IntPtr b);' -ErrorAction SilentlyContinue
    foreach (\$p in \$created) { try { [IrodoriShell.IconRefresh]::SHChangeNotify(0x00002000, 0x0005, \$p, [System.IntPtr]::Zero) } catch {} }
    [IrodoriShell.IconRefresh]::SHChangeNotify(0x08000000, 0, \$null, [System.IntPtr]::Zero)
} catch {}

# Heavier on-disk icon-cache clear + StartMenuExperienceHost tile rebuild only on first install or real icon change
if (\$created.Count -gt 0 -and (\$firstShortcut -or \$iconChanged)) {
    try { & "\$env:SystemRoot\System32\ie4uinit.exe" -ClearIconCache } catch {}
    try { & "\$env:SystemRoot\System32\ie4uinit.exe" -show } catch {}
    try {
        \$smeh = Join-Path \$env:LOCALAPPDATA 'Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\TempState'
        if (Test-Path -LiteralPath \$smeh) {
            Get-ChildItem -LiteralPath \$smeh -Filter 'TileCache_*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path \$smeh 'StartUnifiedTileModelCache.dat') -Force -ErrorAction SilentlyContinue
            Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}
WSLPS1_EOF

    # Convert WSL path → Windows path
    PS1_WIN=$(wslpath -w "$_css_ps1_tmp" 2>/dev/null)
    if [ -n "$PS1_WIN" ]; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" >/dev/null 2>&1 || true
    fi
    rm -f "$_css_ps1_tmp"
fi

echo "Windows shortcut created on Desktop (Irodori-TTS)."

echo
echo '============================================'
echo 'Setup completed'
echo '============================================'
