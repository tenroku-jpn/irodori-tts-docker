#!/bin/bash
set -e

# ============================================
# systemd 風ユニット管理関数
# ============================================

LOG_DIR="/var/log/irodori"
mkdir -p "$LOG_DIR"

PID_DIR="/run/irodori"
mkdir -p "$PID_DIR"

# systemd 風: サービス起動
start_service() {
    local name="$1"
    local cmd="$2"
    local log="$LOG_DIR/${name}.log"
    local pidfile="$PID_DIR/${name}.pid"

    echo "[systemd] Starting $name ..."
    eval "$cmd" >> "$log" 2>&1 &
    local pid=$!
    echo $pid > "$pidfile"
    echo "[systemd] $name started with PID $pid"
}

# systemd 風: サービス停止
stop_service() {
    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"

    if [[ -f "$pidfile" ]]; then
        local pid=$(cat "$pidfile")
        echo "[systemd] Stopping $name (PID $pid)"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f "$pidfile"
    fi
}

# systemd 風: サービス監視
monitor_service() {
    local name="$1"
    local pidfile="$PID_DIR/${name}.pid"

    if [[ ! -f "$pidfile" ]]; then
        echo "[systemd] $name pidfile missing → restarting"
        return 1
    fi

    local pid=$(cat "$pidfile")
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "[systemd] $name crashed → restarting"
        return 1
    fi

    return 0
}

# systemd 風: SIGTERM handler
terminate_all() {
    echo "[systemd] SIGTERM received → stopping all services..."
    stop_service "webui"
    stop_service "voicedesign"
    stop_service "api"
    exit 0
}
trap terminate_all SIGTERM

# ============================================
# ROCm / DXG / MIOPEN 環境
# ============================================
export HSA_ENABLE_DXG_DETECTION=1
export MIOPEN_FIND_MODE=FAST
export MIOPEN_USER_DB_PATH=/tmp/miopen-cache
export PYTORCH_HIP_ALLOC_CONF="garbage_collection_threshold:0.8,max_split_size_mb:512"
export TOKENIZERS_PARALLELISM=false
export LD_LIBRARY_PATH=/opt/rocm/lib:/opt/rocm/lib64:/usr/lib/wsl/lib:$LD_LIBRARY_PATH

mkdir -p /tmp/miopen-cache

# ============================================
# systemd 風: サービス起動
# ============================================

start_service "webui" \
    "python3 /opt/Irodori-TTS/gradio_app.py --server-name 0.0.0.0 --server-port 7860"

start_service "voicedesign" \
    "python3 /opt/Irodori-TTS/gradio_app_voicedesign.py --server-name 0.0.0.0 --server-port 7861"

start_service "api" \
    "python3 -m irodori_openai_tts --host 0.0.0.0 --port 8088"

echo '[systemd] All services started.'

# ============================================
# systemd 風: Watchdog（プロセス監視）
# ============================================
while true; do
    sleep 2

    if ! monitor_service "webui"; then
        start_service "webui" \
            "python3 /opt/Irodori-TTS/gradio_app.py --server-name 0.0.0.0 --server-port 7860"
    fi

    if ! monitor_service "voicedesign"; then
        start_service "voicedesign" \
            "python3 /opt/Irodori-TTS/gradio_app_voicedesign.py --server-name 0.0.0.0 --server-port 7861"
    fi

    if ! monitor_service "api"; then
        start_service "api" \
            "python3 -m irodori_openai_tts --host 0.0.0.0 --port 8088"
    fi
done
