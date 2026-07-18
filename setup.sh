#!/bin/bash
set -e
 
sudo -v
 
echo '============================================'
echo '5-1. System package install'
echo '============================================'
 
sudo apt update
sudo apt install -y git wget curl build-essential cmake \
                             python3-setuptools python3-wheel python3-pip python3-dev pkg-config \
                             fzf
 
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
 
cat <<EOF > config.env
ROCM_VERSION="$ROCM_VERSION"
TORCH_VERSION="$TORCH_VERSION"
VISION_VERSION="$VISION_VERSION"
AUDIO_VERSION="$AUDIO_VERSION"
TRITON_VERSION="$TRITON_VERSION"
WHEEL_URL="$WHEEL_URL"
GPU_FILE="$GPU_FILE"
GPU_URL="$GPU_URL"
 
GPU="$_GPU"
ARCHITECTURE="$ARCHITECTURE"
LLVM_TARGET="$LLVM_TARGET"
SUPPORT="$SUPPORT"
PACK_NAME="$PACK_NAME"
 
EOF
 
echo "config.env を生成しました:"
cat config.env
 
echo '============================================'
echo '5-2. ROCm for WSL install'
echo '============================================'
# ROCm installation (based on AMD's official documentation)
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/native_linux/install-radeon.html
 
if dpkg -s rocm-core >/dev/null 2>&1; then
    echo "ROCm already installed. Skipping."
else
    cd ~
        sudo apt update
 
    if [ ! -f $GPU_FILE ]; then
        wget $GPU_URL
    fi
 
    sudo apt install -y "./$GPU_FILE"
    sudo amdgpu-install -y --usecase=rocm --no-dkms
fi
 
echo
echo '============================================'
echo '5-3. Build librocdxg'
echo '============================================'
# Build librocdxg, the DXG bridge library used by modern ROCm releases to
# interface with the GPU exposed by WSL2 (/dev/dxg). Older ROCm builds included
# similar functionality internally, but current versions require this library.
# Reference: https://github.com/ROCm/librocdxg
 
if [ -f /usr/local/lib/librocdxg.so ]; then
    echo "librocdxg already installed. Skipping."
else
    cd ~
 
    if [ ! -d librocdxg ]; then
        git clone https://github.com/ROCm/librocdxg.git
    fi
 
    cd librocdxg
 
    # Set the Windows SDK path (adjust version number if different)
    export win_sdk='/mnt/c/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/'
 
    # Build the library
    mkdir -p build
    cd build
    cmake .. -DWIN_SDK="${win_sdk}/shared"
    make
    sudo make install
fi
 
echo
echo '============================================'
echo '5-4. GPU detection'
echo '============================================'

grep -q "HSA_ENABLE_DXG_DETECTION=1" ~/.bashrc || echo 'export HSA_ENABLE_DXG_DETECTION=1' >> ~/.bashrc
source ~/.bashrc

rocminfo | grep -i gfx || echo '[WARNING] GPU may not be detected correctly.'
 
echo
echo '============================================'
echo '5-5. Docker availability check'
echo '============================================'
 
 
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
else
    COMPOSE="docker-compose"
fi
 
echo
echo '============================================'
echo '5-6. Docker build'
echo '============================================'
cd ~/docker/irodori-tts-docker
$COMPOSE build --no-cache
 
echo
echo '============================================'
echo '5-7. Docker start'
echo '============================================'
$COMPOSE up -d
 
echo
echo '============================================'
echo 'Setup completed'
echo '============================================'
