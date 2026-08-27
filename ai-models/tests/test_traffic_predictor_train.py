"""1-epoch smoke test for ``ai-models/train/traffic_predictor_train.py`` (§3.13).

Builds a tiny synthetic dataset of 20 samples × 47 features with binary
labels (y ∈ {0, 1}, float dtype — the script loads y as float32 and uses
``nn.BCEWithLogitsLoss``). Runs ``train()`` for a single epoch on CPU with
``seq_len=1`` (so ``y`` is unsqueezed to shape ``(N, 1)`` matching the
``(B, 1)`` logits returned by the LSTM head — avoiding a shape mismatch in
BCEWithLogitsLoss), then asserts:

* ``traffic_predictor_best.pt`` is written (state_dict non-empty)
* ``traffic_predictor.onnx`` is written
* ``traffic_predictor_meta.json`` is written

The full 100-epoch GPU run is documented in ``ai-models/TRAINING.md``.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

# The script imports onnx + onnxruntime at top level — skip the whole test if
# those packages are absent (mirrors the dpi_classifier smoke test).
pytest.importorskip("torch")
pytest.importorskip("onnx")
pytest.importorskip("onnxruntime")

pytestmark = pytest.mark.smoke


def _make_tiny_traffic_dataset(path: Path, n: int = 20,
                                feature_dim: int = 47) -> None:
    """Write a tiny ``X``/``y`` .npz with binary float labels for BCEWithLogitsLoss."""
    rng = np.random.default_rng(7)
    X = rng.standard_normal((n, feature_dim)).astype(np.float32)
    y = (rng.random(n) > 0.5).astype(np.float32)
    np.savez(path, X=X, y=y)


def test_traffic_predictor_1_epoch_smoke(tmp_path):
    """Run ``traffic_predictor_train.train`` for 1 epoch on a 20-sample dataset."""
    import torch
    import traffic_predictor_train

    data_path = tmp_path / "traffic_dataset.npz"
    _make_tiny_traffic_dataset(data_path)

    output_dir = tmp_path / "models"

    model = traffic_predictor_train.train(
        data_path=str(data_path),
        epochs=1,
        batch_size=4,
        lr=1e-3,
        weight_decay=0.01,
        seq_len=1,   # avoids BCEWithLogitsLoss shape mismatch (see module docstring)
        val_split=0.15,
        output_dir=str(output_dir),
    )

    # ─── In-memory state_dict non-empty ────────────────────────────────
    sd = model.state_dict()
    assert len(sd) > 0, "Live model state_dict is empty"
    total_params = sum(t.numel() for t in sd.values())
    assert total_params > 0, "All model parameter tensors are empty"

    # ─── Persisted best checkpoint ────────────────────────────────────
    best_pt = output_dir / "traffic_predictor_best.pt"
    assert best_pt.exists(), f"Best checkpoint not written: {best_pt}"
    assert best_pt.stat().st_size > 0, f"Best checkpoint is empty: {best_pt}"

    persisted_sd = torch.load(str(best_pt), map_location="cpu", weights_only=True)
    assert len(persisted_sd) > 0, "Persisted state_dict is empty"
    assert any(t.numel() > 0 for t in persisted_sd.values()), (
        "Persisted state_dict has no non-empty tensors"
    )

    # ─── ONNX export ───────────────────────────────────────────────────
    onnx_file = output_dir / "traffic_predictor.onnx"
    assert onnx_file.exists(), f"ONNX file not written: {onnx_file}"
    assert onnx_file.stat().st_size > 0, f"ONNX file is empty: {onnx_file}"

    # ─── Metadata json ─────────────────────────────────────────────────
    meta_file = output_dir / "traffic_predictor_meta.json"
    assert meta_file.exists(), f"Metadata json not written: {meta_file}"
    meta = json.loads(meta_file.read_text())
    assert meta["model"] == "TrafficPredictor"
    assert meta["feature_dim"] == 47
    assert meta["seq_len"] == 1


def test_traffic_predictor_default_dims():
    """TrafficPredictor defaults to the directive-mandated 47-dim feature input."""
    import traffic_predictor_train

    # Defaults declared in the class signature
    sig_default = traffic_predictor_train.TrafficPredictor.__init__.__defaults__
    # (hidden_size, num_layers, dropout) — but we care about the kw default
    # ``feature_dim=47`` from the function signature.
    import inspect
    params = inspect.signature(traffic_predictor_train.TrafficPredictor.__init__).parameters
    assert params["feature_dim"].default == 47, (
        f"TrafficPredictor feature_dim default must be 47, got {params['feature_dim'].default}"
    )
