FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
ENV HSA_ENABLE_DXG_DETECTION=1
ENV MIOPEN_FIND_MODE=FAST
ENV MIOPEN_USER_DB_PATH=/tmp/miopen-cache
ENV LD_LIBRARY_PATH=/opt/rocm/lib:/usr/lib/wsl/lib
ENV PYTORCH_HIP_ALLOC_CONF="garbage_collection_threshold:0.8,max_split_size_mb:512"
ENV TORCH_BLAS_PREFER_HIPBLASLT=1
ENV OMP_NUM_THREADS=4
ENV TOKENIZERS_PARALLELISM=false
ENV PYTORCH_ENABLE_SDP_KERNELS=TRUE
ENV TRITON_CACHE_DIR=/tmp/triton-cache
ENV TORCHINDUCTOR_COMPILE_THREADS=4
ENV PYTORCH_HIP_ALLOC_REUSE_GPU_MEMORY=1
 
COPY config.env /tmp/config.env
 
# ---------------------------------------------------------
# 基本ツール
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-setuptools python3-dev \
    cmake pkg-config protobuf-compiler libprotobuf-dev dos2unix bash curl \
    git wget ffmpeg libsndfile1 build-essential ca-certificates patch iproute2 && \
    rm -rf /var/lib/apt/lists/*
 
# ---------------------------------------------------------
# SentencePiece 0.1.99
# ---------------------------------------------------------
# Note: No prebuilt ROCm-compatible wheel is available for sentencepiece on Python 3.12,
# so it is built from source during the image build process.
RUN pip3 install sentencepiece==0.1.99
 
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
