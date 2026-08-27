"""Smoke test for ``ai-models/quantize/quantize_models.py`` (§3.13).

Creates a tiny ONNX model (MatMul + Add: y = W·x + b, 4→2) via the shared
``tiny_onnx_model_path`` fixture, then calls
``quantize_models.quantize_model_int8`` with dynamic quantization (no
calibration data — required because the tiny model has no real-data
distribution). Asserts:

* The quantized output file exists and is non-empty.
* A ``.quant_meta.json`` sidecar is written.

Skips if ``onnxruntime`` is not installed (``quantize_models`` imports
``onnxruntime.quantization`` at module top-level).
"""

from __future__ import annotations

import json

import pytest

# quantize_models.py top-level imports onnxruntime.quantization — skip whole
# test file if either onnx or onnxruntime is unavailable.
pytest.importorskip("onnx")
pytest.importorskip("onnxruntime")

pytestmark = pytest.mark.smoke


def test_quantize_tiny_model(tiny_onnx_model_path, tmp_path):
    """Dynamic INT8 quantization of the tiny ONNX fixture produces a non-empty file."""
    import quantize_models

    input_path = tiny_onnx_model_path
    output_path = tmp_path / "tiny_model_int8.onnx"

    quantize_models.quantize_model_int8(
        input_path=str(input_path),
        output_path=str(output_path),
        calibration_data_path=None,   # dynamic quantization (no calibration set)
        per_channel=True,
    )

    # ─── Quantized ONNX file exists and is non-empty ───────────────────
    assert output_path.exists(), f"Quantized ONNX file not created: {output_path}"
    assert output_path.stat().st_size > 0, (
        f"Quantized ONNX file is empty: {output_path}"
    )

    # ─── Metadata sidecar exists and is parseable JSON ────────────────
    meta_path = output_path.with_suffix(".quant_meta.json")
    assert meta_path.exists(), f"Quantization metadata not written: {meta_path}"
    meta = json.loads(meta_path.read_text())
    assert meta["input_path"] == str(input_path.resolve()) or meta["input_path"].endswith(
        input_path.name
    )
    assert meta["output_path"] == str(output_path.resolve()) or meta[
        "output_path"
    ].endswith(output_path.name)
    assert meta["weight_type"] == "int8"
    assert meta["quantization_type"] == "dynamic"
    assert meta["per_channel"] is True
    # Size reduction may be negative for a tiny model (metadata overhead), so
    # we only assert the field is present, not its sign.
    assert "reduction_pct" in meta
    assert "original_size_mb" in meta
    assert "quantized_size_mb" in meta


def test_quantized_model_runs_in_onnxruntime(tiny_onnx_model_path, tmp_path):
    """The quantized model is loadable in onnxruntime and produces finite output."""
    import numpy as np
    import onnxruntime as ort
    import quantize_models

    output_path = tmp_path / "tiny_model_int8_runtime.onnx"
    quantize_models.quantize_model_int8(
        input_path=str(tiny_onnx_model_path),
        output_path=str(output_path),
        calibration_data_path=None,
        per_channel=False,
    )

    session = ort.InferenceSession(str(output_path))
    input_meta = session.get_inputs()[0]
    assert input_meta.name == "input"

    # Random input of the tiny model's expected shape [1, 4]
    test_input = np.random.randn(*[d if isinstance(d, int) else 1
                                   for d in input_meta.shape]).astype(np.float32)
    output = session.run(None, {input_meta.name: test_input})

    assert len(output) == 1
    out = output[0]
    # Output shape must match the tiny fixture ([1, 2])
    assert out.shape[-1] == 2
    assert np.all(np.isfinite(out)), "Quantized model produced NaN/Inf output"


def test_quantize_all_models_smoke(tmp_path):
    """``quantize_all_models`` walks a directory of ONNX files end-to-end."""
    # Reuse the fixture logic to create a tiny model under models/
    from onnx import helper, TensorProto
    import numpy as np
    import quantize_models

    models_dir = tmp_path / "models"
    models_dir.mkdir()
    onnx_path = models_dir / "tiny.onnx"

    W = np.eye(4, dtype=np.float32)[:, :2]  # (4, 2)
    B = np.array([0.0, 0.0], dtype=np.float32)
    W_init = helper.make_tensor("W", TensorProto.FLOAT, list(W.shape), W.flatten().tolist())
    B_init = helper.make_tensor("B", TensorProto.FLOAT, list(B.shape), B.flatten().tolist())
    in_info = helper.make_tensor_value_info("input", TensorProto.FLOAT, [1, 4])
    out_info = helper.make_tensor_value_info("output", TensorProto.FLOAT, [1, 2])
    graph = helper.make_graph(
        [
            helper.make_node("MatMul", ["input", "W"], ["h"]),
            helper.make_node("Add", ["h", "B"], ["output"]),
        ],
        "g",
        [in_info],
        [out_info],
        [W_init, B_init],
    )
    model = helper.make_model(
        graph,
        producer_name="pytest",
        opset_imports=[helper.make_operatorsetid("", 17)],
    )
    import onnx
    onnx.checker.check_model(model)
    onnx.save(model, str(onnx_path))

    # quantize_all_models globs *.onnx under models_dir; if no calibration
    # data file is present it falls back to dynamic quantization (which is
    # what we want for the smoke test).
    quantize_models.quantize_all_models(models_dir=str(models_dir))

    quantized = models_dir / "tiny_int8.onnx"
    assert quantized.exists(), f"quantize_all_models did not produce {quantized}"
    assert quantized.stat().st_size > 0
