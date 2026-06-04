#!/usr/bin/env python3

import json
import platform
import subprocess
import time

import torch
from huggingface_hub import hf_hub_download

from irodori_tts.inference_runtime import (
    InferenceRuntime,
    RuntimeKey,
    SamplingRequest,
)

TEXT = (
    "これは Irodori-TTS のベンチマーク用テキストです。"
    "実際の利用を想定して、ある程度の長さの文章を生成しています。"
)

HF_CHECKPOINT = "Aratako/Irodori-TTS-500M-v3"
CODEC_REPO = "Aratako/Semantic-DACVAE-Japanese-32dim"

PRECISIONS = ["fp32", "bf16"]
DECODE_MODES = ["sequential", "batch"]

NUM_STEPS = 40
N_RUNS = 20


def resolve_checkpoint():
    return hf_hub_download(
        repo_id=HF_CHECKPOINT,
        filename="model.safetensors",
    )


def load_runtime(precision: str):
    checkpoint_path = resolve_checkpoint()

    return InferenceRuntime.from_key(
        RuntimeKey(
            checkpoint=checkpoint_path,
            model_device="cuda",
            codec_repo=CODEC_REPO,
            model_precision=precision,
            codec_device="cuda",
            codec_precision=precision,
            codec_deterministic_encode=True,
            codec_deterministic_decode=True,
        )
    )


def infer_once(runtime, text, decode_mode):
    result = runtime.synthesize(
        SamplingRequest(
            text=text,
            no_ref=True,
            num_candidates=1,
            decode_mode=decode_mode,
            num_steps=NUM_STEPS,
            cfg_scale_text=3.0,
            cfg_scale_caption=3.0,
            cfg_scale_speaker=5.0,
            cfg_guidance_mode="independent",
            t_schedule_mode="linear",
            sway_coeff=-1.0,
        ),
        log_fn=None,
    )

    return result.audio, result.sample_rate


def benchmark(runtime, decode_mode):
    # warmup
    infer_once(runtime, TEXT, decode_mode)

    times = []

    for _ in range(N_RUNS):
        start = time.perf_counter()
        audio, sr = infer_once(runtime, TEXT, decode_mode)
        end = time.perf_counter()

        times.append(end - start)

    avg = sum(times) / len(times)

    # audio: Tensor [channels, samples]
    duration = audio.shape[-1] / sr

    rtf = avg / duration

    return {
        "avg_sec": avg,
        "audio_sec": duration,
        "rtf": rtf,
    }

def main():
    results = []

    for precision in PRECISIONS:
        print(f"\nLoading {precision} ...")

        runtime = load_runtime(precision)

        for decode_mode in DECODE_MODES:
            print(f"Benchmarking {precision} / {decode_mode}")

            r = benchmark(runtime, decode_mode)

            results.append(
                {
                    "precision": precision,
                    "decode_mode": decode_mode,
                    **r,
                }
            )

    print("\n=== RESULTS ===")

    gpu = torch.cuda.get_device_name(0)
    pytorch = torch.__version__
    os_name = platform.platform()

    backend = "ROCm" if torch.version.hip else "CUDA"

    print("\n## Irodori-TTS ベンチマーク結果")
    print("| GPU | Precision | decode | avg(sec) | RTF | Backend | PyTorch | OS |")
    print("|------|------|------|------:|------:|------|------|------|")

    for r in results:
        print(
            f"| {gpu} | {r['precision']} | {r['decode_mode']} | "
            f"{r['avg_sec']:.2f} | {r['rtf']:.3f} | "
            f"{backend} | {pytorch} | {os_name} |"
        )

    print("\nJSON:")
    print(json.dumps(results, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()