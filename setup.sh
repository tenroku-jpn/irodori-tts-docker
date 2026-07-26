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
echo '5-3. Build librocdxg'
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
echo '5-4. GPU detection'
echo '============================================'
 
export HSA_ENABLE_DXG_DETECTION=1
 
grep -q "HSA_ENABLE_DXG_DETECTION=1" ~/.bashrc || \
    echo 'export HSA_ENABLE_DXG_DETECTION=1' >> ~/.bashrc
 
if ! rocminfo | grep -iq gfx; then
    echo '[WARNING] GPU may not be detected correctly.'
fi
 
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
