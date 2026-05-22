FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_ENABLE_DXG_DETECTION=1
ENV MIOPEN_FIND_MODE=FAST
 
# ---------------------------------------------------------
# 基本ツール
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv python3-setuptools python3-dev \
    cmake pkg-config protobuf-compiler libprotobuf-dev dos2unix \
    git wget ffmpeg libsndfile1 build-essential ca-certificates patch && \
    rm -rf /var/lib/apt/lists/*
 
# ---------------------------------------------------------
# Python venv
# ---------------------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
 
RUN pip3 install --upgrade pip setuptools wheel uv
 
# ---------------------------------------------------------
# SentencePiece 0.1.99
# ---------------------------------------------------------
# Note: No prebuilt ROCm-compatible wheel is available for sentencepiece on Python 3.12,
# so it is built from source during the image build process.
 
WORKDIR /tmp/sentencepiece
 
RUN git clone https://github.com/google/sentencepiece.git .
 
RUN git checkout v0.1.99
 
RUN mkdir build && cd build && \
    cmake .. && make -j"$(nproc)" && make install && ldconfig
 
RUN cd python && python3 setup.py bdist_wheel
 
RUN pip3 install python/dist/sentencepiece-0.1.99-*.whl
 
# ---------------------------------------------------------
# ROCm WHL
# ---------------------------------------------------------
# Note: AMD's reference uses PyTorch 2.9.1 for ROCm 7.2.1, but Irodori‑TTS requires
# torch>=2.10.0. The PyTorch version used here is updated accordingly.
# Reference: https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/install/installrad/wsl/install-pytorch.html
 
WORKDIR /tmp/wheels
 
RUN pip3 install numpy==1.26.4
#RUN pip3 install --upgrade pip3 wheel

RUN wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torch-2.10.0%2Brocm7.2.1.lw.gitb07cec22-cp312-cp312-linux_x86_64.whl
RUN wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchvision-0.25.0%2Brocm7.2.1.git82df5f59-cp312-cp312-linux_x86_64.whl
RUN wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/triton-3.6.0%2Brocm7.2.1.gitba5c1517-cp312-cp312-linux_x86_64.whl
RUN wget https://repo.radeon.com/rocm/manylinux/rocm-rel-7.2.1/torchaudio-2.10.0%2Brocm7.2.1.git5047768f-cp312-cp312-linux_x86_64.whl
RUN pip3 uninstall torch torchvision triton torchaudio
RUN pip3 install torch-2.10.0+rocm7.2.1.lw.gitb07cec22-cp312-cp312-linux_x86_64.whl torchvision-0.25.0+rocm7.2.1.git82df5f59-cp312-cp312-linux_x86_64.whl triton-3.6.0+rocm7.2.1.gitba5c1517-cp312-cp312-linux_x86_64.whl torchaudio-2.10.0+rocm7.2.1.git5047768f-cp312-cp312-linux_x86_64.whl

RUN location=$(pip show torch | grep Location | awk -F ": " '{print $2}') && \
    cd ${location}/torch/lib && \
    rm -f libhsa-runtime64.so*

# ---------------------------------------------------------
# Irodori-TTS
# ---------------------------------------------------------
WORKDIR /opt/Irodori-TTS
RUN git clone https://github.com/Aratako/Irodori-TTS.git .
 
# ---------------------------------------------------------
# Irodori-TTS-Server
# ---------------------------------------------------------
WORKDIR /opt/Irodori-TTS-Server
RUN git clone https://github.com/Aratako/Irodori-TTS-Server.git .
 
COPY requirements.txt .
RUN pip3 install -r requirements.txt
 
# ---------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
EXPOSE 7860 7861 8088
 
ENTRYPOINT ["/entrypoint.sh"]
