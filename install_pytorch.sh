#!/bin/bash
set -e
 
# Note: AMD's reference uses PyTorch 2.9.1 for ROCm 7.2.1, but Irodori‑TTS requires
# torch>=2.10.0. The PyTorch version used here is updated accordingly.
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/install/installrad/wsl/install-pytorch.html
#            https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/README.html
#            https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/frameworks/pytorch/install.html
 
source /tmp/config.env
 
cd /tmp/wheels
 
pip3 install numpy==1.26.4
 
if dpkg --compare-versions "$ROCM_VERSION_SHORT" ge "7.9"; then
    echo "Preview series (7.9+)"
    pip3 install --index-url "$WHEEL_URL" \
        "torch[device-$LLVM_TARGET]==$TORCH_VERSION+rocm$ROCM_VERSION" \
        "torchvision[device-$LLVM_TARGET]==$VISION_VERSION+rocm$ROCM_VERSION" \
        "torchaudio==$AUDIO_VERSION+rocm$ROCM_VERSION"
    python3 -c "import torch; print(torch.cuda.is_available())"
else
    echo "Install Production series (7.0 - 7.8)"
    pip3 install \
            torch==$TORCH_VERSION \
            torchvision==$VISION_VERSION \
            torchaudio==$AUDIO_VERSION \
            -f "$WHEEL_URL"
fi
 
pip3 install pillow jinja2 markupsafe typing-extensions filelock fsspec
 
