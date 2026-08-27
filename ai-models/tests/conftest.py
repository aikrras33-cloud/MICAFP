"""Shared pytest fixtures + sys.path bootstrap for the UnifiedShield AI-models test suite.

This conftest.py is loaded automatically by pytest when tests under
``ai-models/tests/`` are executed. It:

1. Registers the ``smoke`` marker so ``pytest -m smoke`` works without warnings.
2. Inserts ``ai-models/``, ``ai-models/train/`` and ``ai-models/quantize/``
   on ``sys.path`` so test modules can ``import dataset_collector``,
   ``import dpi_classifier_train``, ``import quantize_models``, etc.
3. Provides shared fixtures:
   - ``synthetic_packets``  : list of 10 packet dicts (for feature_engineering)
   - ``tiny_onnx_model_path``: tiny MatMul+Add ONNX file (for quantize/validate)
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# ────────────────────────── sys.path bootstrap ──────────────────────────

AI_MODELS_ROOT = Path(__file__).resolve().parent.parent
TRAIN_DIR = AI_MODELS_ROOT / "train"
QUANT_DIR = AI_MODELS_ROOT / "quantize"

for _p in (AI_MODELS_ROOT, TRAIN_DIR, QUANT_DIR):
    _p_str = str(_p)
    if _p_str not in sys.path:
        sys.path.insert(0, _p_str)


# ────────────────────────── marker registration ──────────────────────────

def pytest_configure(config):  # noqa: D401
    """Register the ``smoke`` marker to silence PytestUnknownMarkWarning."""
    config.addinivalue_line(
        "markers",
        "smoke: lightweight 1-epoch / 1-step smoke test of the AI training pipeline",
    )


# ────────────────────────── fixtures ─────────────────────────────────────

@pytest.fixture
def synthetic_packets() -> list[dict]:
    """Return 10 synthetic packet dicts (the analog of a 1-second no-PCAP capture).

    Each packet dict exposes the fields expected by
    ``feature_engineering.extract_features_from_packets``:
    ``timestamp`` (epoch ms), ``size`` (bytes), ``direction`` ('fwd'|'bwd'),
    ``tcp_flags`` dict, ``tcp_window`` int.
    """
    import random

    rng = random.Random(42)
    packets: list[dict] = []
    base_ts = 1_700_000_000_000.0  # epoch ms
    for i in range(10):
        pkt = {
            "timestamp": base_ts + i * rng.uniform(1.0, 20.0),  # ms
            "size": rng.randint(64, 1500),
            "direction": "fwd" if i % 2 == 0 else "bwd",
            "tcp_flags": {
                "syn": i == 0,
                "ack": i > 0,
                "fin": i == 9,
                "rst": i == 5,
                "psh": i % 3 == 0,
                "urg": False,
            },
            "tcp_window": rng.randint(8192, 65535),
        }
        packets.append(pkt)
    return packets


@pytest.fixture
def synthetic_flow_metadata() -> dict:
    """Metadata dict accompanying :func:`synthetic_packets` for feature extraction."""
    return {
        "rst_after_syn": 0,
        "rst_timing_ms": 0.0,
        "http_status_code": 0,
        "tls_version": 0x0303,
        "tls_cipher_count": 12,
        "tls_ext_count": 6,
        "tls_sni_len": 18,
        "tls_alpn_count": 1,
        "tls_session_id_len": 32,
        "rtt_mean": 80.0,
        "rtt_std": 15.0,
        "retransmits": 0,
        "out_of_order": 0,
        "dns_rcode": 0,
        "dns_answer_count": 1,
        "dns_poisoned": 0,
        "sni_filtered": 0,
        "active_duration": 200.0,
        "idle_duration": 0.0,
    }


@pytest.fixture
def tiny_onnx_model_path(tmp_path):
    """Create a tiny ONNX model (MatMul + Add: y = W·x + b) and return its path.

    Input:  ``[1, 4]`` float32
    Output: ``[1, 2]`` float32

    This is the smallest possible ONNX model that has trainable weights
    (a ``MatMul`` initializer), so it exercises both ``quantize_models`` and
    ``validate_onnx`` end-to-end without depending on PyTorch.

    Skips the test if ``onnx`` is not installed.
    """
    onnx = pytest.importorskip("onnx")
    from onnx import helper, TensorProto
    import numpy as np

    model_path = tmp_path / "tiny_smoke.onnx"

    input_info = helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, 4])
    output_info = helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 2])

    W = np.array(
        [[1.0, 0.0], [0.0, 1.0], [0.5, 0.5], [-0.5, 0.5]], dtype=np.float32
    )
    B = np.array([0.1, -0.1], dtype=np.float32)

    W_init = helper.make_tensor(
        "W", TensorProto.FLOAT, list(W.shape), W.flatten().tolist()
    )
    B_init = helper.make_tensor(
        "B", TensorProto.FLOAT, list(B.shape), B.flatten().tolist()
    )

    matmul_node = helper.make_node("MatMul", ["input", "W"], ["hidden"])
    add_node = helper.make_node("Add", ["hidden", "B"], ["output"])

    graph = helper.make_graph(
        [matmul_node, add_node],
        "tiny_smoke_graph",
        [input_info],
        [output_info],
        [W_init, B_init],
    )
    model = helper.make_model(
        graph,
        producer_name="unifiedshield_tests",
        opset_imports=[helper.make_operatorsetid("", 17)],
    )
    onnx.checker.check_model(model)
    onnx.save(model, str(model_path))

    return model_path
