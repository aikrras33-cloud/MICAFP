"""1-epoch smoke test for ``ai-models/train/dpi_classifier_train.py`` (§3.13).

Builds a tiny synthetic dataset of 16 samples × 47 features × 8 classes
(every class label is represented at least once so ``torch.bincount`` returns
a size-8 weight vector — a hard requirement of the script's CrossEntropyLoss
class weighting). Runs the ``train()`` function for a single epoch on CPU
with batch_size=4 and val_split=0.25, then asserts:

* ``dpi_classifier_best.pt`` is written (state_dict non-empty)
* ``dpi_classifier.onnx`` is written (export_onnx succeeds)
* ``dpi_classifier_meta.json`` is written

ONNX export is exercised (not skipped) because the script does
``import onnx`` / ``import onnxruntime`` at module top-level — if those
packages are absent the whole test is skipped via the ``importorskip`` calls
below.

The full 200-epoch GPU run is documented in ``ai-models/TRAINING.md``.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

# Top-level skip: dpi_classifier_train.py imports onnx + onnxruntime at module
# load time. If those packages aren't installed, importing the module fails,
# so the whole test must skip — not error.
pytest.importorskip("torch")
pytest.importorskip("onnx")
pytest.importorskip("onnxruntime")

pytestmark = pytest.mark.smoke


def _make_tiny_dpi_dataset(path: Path, n: int = 16, feature_dim: int = 47,
                            num_classes: int = 8) -> None:
    """Write a tiny ``X``/``y`` .npz covering all 8 classes for ``torch.bincount``."""
    rng = np.random.default_rng(42)
    X = rng.standard_normal((n, feature_dim)).astype(np.float32)
    # Tile class labels 0..7 twice → covers every class at least once.
    y = np.tile(np.arange(num_classes, dtype=np.int64), n // num_classes + 1)[:n]
    np.savez(path, X=X, y=y)


def test_dpi_classifier_1_epoch_smoke(tmp_path):
    """Run ``dpi_classifier_train.train`` for 1 epoch on a 16-sample dataset."""
    import torch
    import dpi_classifier_train

    data_path = tmp_path / "dpi_dataset.npz"
    _make_tiny_dpi_dataset(data_path)

    output_dir = tmp_path / "models"

    model = dpi_classifier_train.train(
        data_path=str(data_path),
        epochs=1,
        batch_size=4,
        lr=3e-4,
        weight_decay=0.01,
        val_split=0.25,
        output_dir=str(output_dir),
    )

    # ─── Verify the in-memory model has a non-empty state_dict ───────────
    sd = model.state_dict()
    assert len(sd) > 0, "Live model state_dict is empty"
    total_params = sum(t.numel() for t in sd.values())
    assert total_params > 0, "All model parameter tensors are empty"

    # ─── Verify the persisted best checkpoint ───────────────────────────
    best_pt = output_dir / "dpi_classifier_best.pt"
    assert best_pt.exists(), f"Best checkpoint not written: {best_pt}"
    assert best_pt.stat().st_size > 0, f"Best checkpoint is empty: {best_pt}"

    persisted_sd = torch.load(str(best_pt), map_location="cpu", weights_only=True)
    assert len(persisted_sd) > 0, "Persisted state_dict is empty"
    assert any(t.numel() > 0 for t in persisted_sd.values()), (
        "Persisted state_dict has no non-empty tensors"
    )

    # ─── Verify ONNX export + onnxruntime verification succeeded ────────
    onnx_file = output_dir / "dpi_classifier.onnx"
    assert onnx_file.exists(), f"ONNX file not written: {onnx_file}"
    assert onnx_file.stat().st_size > 0, f"ONNX file is empty: {onnx_file}"

    # ─── Verify metadata json ───────────────────────────────────────────
    meta_file = output_dir / "dpi_classifier_meta.json"
    assert meta_file.exists(), f"Metadata json not written: {meta_file}"
    meta = json.loads(meta_file.read_text())
    assert meta["model"] == "DPIClassifier"
    assert meta["num_features"] == 47
    assert meta["num_classes"] == 8
    assert len(meta["class_names"]) == 8
    assert meta["epochs"] == 1


def test_dpi_classifier_model_dimensions():
    """The DPIClassifier module declares the directive's required dims (47 → 8)."""
    import dpi_classifier_train

    cls = dpi_classifier_train.DPIClassifier
    assert cls.NUM_FEATURES == 47, (
        f"DPIClassifier.NUM_FEATURES must be 47 per directive, got {cls.NUM_FEATURES}"
    )
    assert cls.NUM_CLASSES == 8
    assert len(cls.CLASS_NAMES) == 8
