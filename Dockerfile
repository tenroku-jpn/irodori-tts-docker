FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_ENABLE_DXG_DETECTION=TRUE \
    MIOPEN_FIND_MODE=FAST \
    MIOPEN_USER_DB_PATH=/tmp/miopen-cache \
    PYTORCH_HIP_ALLOC_CONF=garbage_collection_threshold:0.8,max_split_size_mb:512 \
    OMP_NUM_THREADS=4 \
    TOKENIZERS_PARALLELISM=false \
    LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:/opt/rocm/hip/lib:/usr/lib/wsl/lib \
    TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=TRUE \
    PYTORCH_ENABLE_SDP_KERNELS=TRUE \
    TRITON_CACHE_DIR=/tmp/triton-cache \
    TORCHINDUCTOR_COMPILE_THREADS=4 \
    PYTORCH_HIP_ALLOC_REUSE_GPU_MEMORY=1 \
    FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
    FLASH_ATTENTION_TRITON_AMD_AUTOTUNE=TRUE
 
COPY config.env /tmp/config.env
 
RUN set -a \
    && . /tmp/config.env \
    && set +a
 
# ---------------------------------------------------------
# 基本ツール
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv python3-setuptools python3-dev \
    cmake pkg-config protobuf-compiler libprotobuf-dev dos2unix bash \
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
 
COPY install_pytorch.sh /tmp/install_pytorch.sh
WORKDIR /tmp/wheels
RUN chmod +x /tmp/install_pytorch.sh
RUN /tmp/install_pytorch.sh
 
# ---------------------------------------------------------
# Irodori-TTS
# ---------------------------------------------------------
WORKDIR /opt/Irodori-TTS
RUN git clone https://github.com/Aratako/Irodori-TTS.git .
ENV PYTHONPATH=/opt/Irodori-TTS
 
# ---------------------------------------------------------
# Irodori-TTS-Server
# ---------------------------------------------------------
WORKDIR /opt/Irodori-TTS-Server
RUN git clone https://github.com/Aratako/Irodori-TTS-Server.git .
ENV PYTHONPATH=/opt/Irodori-TTS:/opt/Irodori-TTS-Server:/opt/Irodori-TTS-Server/src
COPY requirements.txt .
RUN pip3 install -r requirements.txt
 
# ---------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
EXPOSE 7860 7861 8088
 
ENTRYPOINT ["/entrypoint.sh"]