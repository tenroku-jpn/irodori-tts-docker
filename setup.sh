#!/bin/bash
set -e
 
sudo -v
 
echo '============================================'
echo '5-1. System package install'
echo '============================================'
 
sudo apt update
sudo apt install -y git wget curl build-essential cmake python3-setuptools python3-wheel python3-pip python3-dev pkg-config
 
echo
echo '============================================'
echo '5-2. ROCm for WSL install'
echo '============================================'
# ROCm installation (based on AMD's official documentation)
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2.1/docs/install/installrad/native_linux/install-radeon.html
 
if dpkg -l | grep -q rocm-core; then
    echo "ROCm already installed. Skipping."
else
    cd ~
        sudo apt update
       
    if [ ! -f amdgpu-install_7.2.1.70201-1_all.deb ]; then
        wget https://repo.radeon.com/amdgpu-install/7.2.1/ubuntu/noble/amdgpu-install_7.2.1.70201-1_all.deb
    fi
 
    sudo apt install -y ./amdgpu-install_7.2.1.70201-1_all.deb
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
echo '5-4. Apply ROCm environment (/etc/environment)'
echo '============================================'
# Apply ROCm runtime optimizations

sudo sh -c 'cat >> /etc/profile' << 'EOF'
export HSA_FORCE_FINE_GRAIN_PCIE=1
export HSA_ENABLE_SDMA=0
export HSA_ENABLE_DXG_DETECTION=1
export MIOPEN_FIND_MODE=FAST
export MIOPEN_USER_DB_PATH=/tmp/miopen-cache
export PYTORCH_HIP_ALLOC_CONF="garbage_collection_threshold:0.8,max_split_size_mb:512"
export OMP_NUM_THREADS=4
export TOKENIZERS_PARALLELISM=false
EOF

source /etc/profile

echo
echo '============================================'
echo '5-5. GPU detection'
echo '============================================'
 
rocminfo | grep -i gfx || echo '[WARNING] GPU may not be detected correctly.'
 
echo
echo '============================================'
echo '5-6. Docker availability check'
echo '============================================'
 
docker --version
docker compose version
 
echo
echo '============================================'
echo '5-7. Docker build'
echo '============================================'
 
cd ~/docker/irodori-tts-docker
docker compose build --no-cache
 
echo
echo '============================================'
echo '5-8. Docker start'
echo '============================================'
 
docker compose up -d
 
echo
echo '============================================'
echo 'Setup completed'
echo '============================================'
