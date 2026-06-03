from __future__ import annotations

import torch


def patch_missing_reduce_op() -> None:
    """Patch incomplete torch.distributed builds found in some ROCm environments."""
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