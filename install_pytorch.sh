#!/bin/bash
set -e
 
# Note: AMD's reference uses PyTorch 2.9.1 for ROCm 7.2.1, but Irodori‑TTS requires
# torch>=2.10.0. The PyTorch version used here is updated accordingly.
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/install/installrad/wsl/install-pytorch.html
source /tmp/config.env
 
cd /tmp/wheels
 
pip3 install --upgrade pip setuptools wheel
pip3 install numpy==1.26.4
 
case "$ROCM_VERSION" in
    "7.2.1"|"7.2.2"|"7.2.3")
                pip install \
                        torch==$TORCH_VERSION \
                        torchvision==$VISION_VERSION \
                        torchaudio==$AUDIO_VERSION \
                        triton==$TRITON_VERSION \
                        -f "$WHEEL_URL"
        ;;
    "7.11.0"|"7.12.0"|"7.13.0")
                pip install --index-url "$WHEEL_URL/$PACK_NAME/" \
                        "torch==$TORCH_VERSION" \
                        "torchaudio==$AUDIO_VERSION" \
                        "torchvision==$VISION_VERSION" \
                        "triton==$TRITON_VERSION"
        ;;
    *)
        echo "Unknown ROCm version: $ROCM_VERSION"
        exit 1
        ;;
esac
 
pip install pillow jinja2 markupsafe typing-extensions filelock fsspec
