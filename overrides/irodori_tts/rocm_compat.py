from __future__ import annotations

import os
import torch

# Torch backend tuning
try:
    # ROCm stability
    torch.backends.cuda.enable_flash_sdp(False)
    torch.backends.cuda.enable_mem_efficient_sdp(False)
    torch.backends.cuda.enable_math_sdp(True)

    # matmul tuning
    torch.set_float32_matmul_precision("high")
except Exception:
    pass


def patch_missing_reduce_op() -> None:
    if not hasattr(torch, "distributed"):
        return

    dist = torch.distributed

    if hasattr(dist, "ReduceOp"):
        return

    class _DummyReduceOp:
        SUM = "sum"
        AVG = "avg"
        PRODUCT = "product"
        MIN = "min"
        MAX = "max"
        BAND = "band"
        BOR = "bor"
        BXOR = "bxor"

    dist.ReduceOp = _DummyReduceOp


patch_missing_reduce_op()