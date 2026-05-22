import subprocess
import time
import json
from pathlib import Path
import torch
import soundfile as sf
import platform

BASE = Path(__file__).resolve().parent

TEXT = (
    "これは Irodori-TTS のベンチマーク用テキストです。"
    "実際の利用を想定して、ある程度の長さの文章を生成しています。"
    "音声合成モデルの性能を測定するために、この文章を複数回生成します。"
)

N_RUNS = 10

INFER = BASE / "infer.py"
BENCH_TXT = BASE / "bench.txt"

BENCH_TXT.write_text(TEXT, encoding="utf-8")

times = []

for i in range(N_RUNS):
    out_wav = BASE / f"bench_{i}.wav"
    start = time.time()
    subprocess.run(
        [
            "python", INFER,
            "--hf-checkpoint", "Aratako/Irodori-TTS-500M-v3",
            "--text", TEXT,
            "--no-ref",
            "--output-wav", str(out_wav)
        ],
        check=True
    )

    end = time.time()
    times.append(end - start)

# 音声長（最初の生成結果を使用）
audio_path = BASE / "bench_0.wav"
audio, sr = sf.read(str(audio_path))
duration = len(audio) / sr

rtf = (sum(times) / len(times)) / duration

if torch.version.hip:
    backend = "ROCm"
elif torch.cuda.is_available():
    backend = "CUDA"
else:
    backend = "CPU"

result = {
    "model": "Irodori-TTS-500M-v3",
    "text_length": len(TEXT),
    "runs": N_RUNS,
    "avg_sec": sum(times) / len(times),
    "min_sec": min(times),
    "max_sec": max(times),
    "audio_duration_sec": duration,
    "rtf": rtf,
    "environment": {
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else "CPU",
        "pytorch": torch.__version__,
        "backend": backend,
    },
}

print(json.dumps(result, indent=2, ensure_ascii=False))


gpu_name = result["environment"]["gpu"]
avg = result["avg_sec"]
rtf = result["rtf"]
driver = result["environment"]["backend"]
os_name = platform.platform()

print("\n## GPU 別ベンチマーク比較")
print("| GPU | 平均推論時間 | RTF | ドライバ | OS |")
print(f"| {gpu_name} | {avg:.2f}s | {rtf:.2f} | {driver} | {os_name} |")
