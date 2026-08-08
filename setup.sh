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

# Windows のユーザー名を WSL から取得
WINUSER=$(powershell.exe -NoProfile -Command '$env:USERNAME' | tr -d '\r')

ICON_SRC="$HOME/docker/irodori-tts-docker/irodori-tts.ico"
ICON_DST="/mnt/c/Users/$WINUSER/AppData/Local/Irodori-TTS/irodori-tts.ico"

mkdir -p "$(dirname "$ICON_DST")"
cp "$ICON_SRC" "$ICON_DST"

# PowerShell に渡すための Windows パスを WSL 側で完成させる
ICON_WIN="C:\\Users\\$WINUSER\\AppData\\Local\\Irodori-TTS\\irodori-tts.ico,0"

PS1_TMP=$(mktemp /tmp/irodori-tts-shortcut-XXXXXX.ps1)

cat > "$PS1_TMP" << EOF
\$WshShell = New-Object -ComObject WScript.Shell

\$desktop = [Environment]::GetFolderPath('Desktop')
\$lnk = Join-Path \$desktop 'Irodori-TTS.lnk'

\$shortcut = \$WshShell.CreateShortcut(\$lnk)
\$shortcut.TargetPath = 'wt.exe'

\$shortcut.Arguments = 'wsl.exe -d "$WSL_DISTRO_NAME" -- bash -l -c "exec ~/.local/share/irodori-tts/launch.sh"'

# アイコン指定（WSL 側で完成させた文字列をそのまま使う）
\$shortcut.IconLocation = "$ICON_WIN"

\$shortcut.Description = 'Launch Irodori-TTS (WSL)'
\$shortcut.Save()
EOF

PS1_WIN=$(wslpath -w "$PS1_TMP")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" >/dev/null 2>&1
rm -f "$PS1_TMP"

echo "Windows shortcut created on Desktop."

echo
echo '============================================'
echo 'Setup completed'
echo '============================================'
