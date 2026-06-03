#!/bin/bash

LOG_DIR="/var/log/irodori"
mkdir -p "$LOG_DIR"

CMD_WEBUI="python3 /opt/Irodori-TTS/gradio_app.py --server-name 0.0.0.0 --server-port 7860"
CMD_VOICEDESIGN="python3 /opt/Irodori-TTS/gradio_app_voicedesign.py --server-name 0.0.0.0 --server-port 7861"
CMD_API="python3 -m irodori_openai_tts --host 0.0.0.0 --port 8088"

start_webui() {
    echo "[systemd] Starting webui..."
    pkill -f "gradio_app.py" 2>/dev/null
    $CMD_WEBUI >> "$LOG_DIR/webui.log" 2>&1 &
}

start_voicedesign() {
    echo "[systemd] Starting voicedesign..."
    pkill -f "gradio_app_voicedesign.py" 2>/dev/null
    $CMD_VOICEDESIGN >> "$LOG_DIR/voicedesign.log" 2>&1 &
}

start_api() {
    echo "[systemd] Starting api..."
    pkill -f "irodori_openai_tts" 2>/dev/null
    $CMD_API >> "$LOG_DIR/api.log" 2>&1 &
}

# ポート監視（軽量）
port_alive() {
    ss -ltn | grep -Fq ":$1"
}

# --- 起動 ---
start_webui
start_voicedesign
start_api

echo "[systemd] Waiting 60 seconds for services to fully start..."
sleep 60   # ← ★ これが決定的に重要

# --- 監視ループ ---
while true; do
    sleep 10

    if ! port_alive 7860; then
        echo "[systemd] webui dead → restart"
        start_webui
    fi

    if ! port_alive 7861; then
        echo "[systemd] voicedesign dead → restart"
        start_voicedesign
    fi

    if ! port_alive 8088; then
        echo "[systemd] api dead → restart"
        start_api
    fi
done
