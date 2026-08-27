"""Smoke test for ``ai-models/quantize/validate_onnx.py`` (§3.13).

Uses the shared ``tiny_onnx_model_path`` fixture to obtain a tiny MatMul+Add
ONNX model, then calls ``validate_onnx.validate_onnx_model`` and asserts the
returned report dict is non-empty and well-formed:

* ``valid`` is True (no errors, no NaN/Inf output)
* ``info`` block contains the expected keys (opset_version, input_shape, etc.)
* The 50-iteration inference benchmark produces a finite ``avg_inference_ms``

Skips if ``onnx`` or ``onnxruntime`` is not installed.
"""

from __future__ import annotations

import pytest

pytest.importorskip("onnx")
pytest.importorskip("onnxruntime")

pytestmark = pytest.mark.smoke


def test_validate_tiny_onnx_model(tiny_onnx_model_path):
    """``validate_onnx_model`` returns a well-formed report dict for the tiny fixture."""
    import validate_onnx

    report = validate_onnx.validate_onnx_model(
        model_path=str(tiny_onnx_model_path),
        expected_input_shape=None,    # tiny fixture has a concrete [1, 4] shape
        expected_output_shape=None,
        expected_opset=17,
        test_inference=True,
    )

    # ─── Report structure ─────────────────────────────────────────────
    assert isinstance(report, dict)
    assert report, "Validation report is empty"
    assert "valid" in report
    assert "errors" in report
    assert "warnings" in report
    assert "info" in report

    # ─── The tiny model must validate cleanly ──────────────────────────
    assert report["valid"] is True, f"Validation errors: {report.get('errors')}"
    assert report["errors"] == []

    info = report["info"]
    assert info["opset_version"] == 17
    assert info["input_name"] == "input"
    assert info["output_name"] == "output"

    # The tiny fixture has concrete [1, 4] input / [1, 2] output shapes
    assert tuple(info["input_shape"]) == (1, 4)
    assert tuple(info["output_shape"]) == (1, 2)

    # Inference test results
    assert "inference_output_shape" in info
    assert info["inference_output_shape"] == [1, 2]
    assert "avg_inference_ms" in info
    assert info["avg_inference_ms"] >= 0.0
    assert "std_inference_ms" in info
    assert info["std_inference_ms"] >= 0.0

    # Model metadata
    assert "size_mb" in info
    assert info["size_mb"] >= 0.0
    assert "param_count" in info
    # W (4×2 = 8) + B (2) = 10 trainable parameters
    assert info["param_count"] == 10


def test_validate_missing_file_returns_invalid(tmp_path):
    """Validating a non-existent file returns ``valid=False`` with an error string."""
    import validate_onnx

    missing = tmp_path / "does_not_exist.onnx"
    report = validate_onnx.validate_onnx_model(model_path=str(missing))

    assert isinstance(report, dict)
    assert report["valid"] is False
    assert len(report["errors"]) >= 1
    assert any("not found" in e.lower() for e in report["errors"])


def test_validate_all_models_smoke(tmp_path):
    """``validate_all_models`` walks a directory and writes a JSON report."""
    import json
    import validate_onnx
    from onnx import helper, TensorProto
    import numpy as np
    import onnx

    # Build a 2-model directory to exercise the loop
    models_dir = tmp_path / "models"
    models_dir.mkdir()

    for name in ("tiny_a.onnx", "tiny_b.onnx"):
        W = np.eye(4, dtype=np.float32)[:, :2]
        B = np.array([0.1, -0.1], dtype=np.float32)
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
        onnx.checker.check_model(model)
        onnx.save(model, str(models_dir / name))

    validate_onnx.validate_all_models(models_dir=str(models_dir))

    report_path = models_dir / "validation_report.json"
    assert report_path.exists(), f"validate_all_models did not write {report_path}"
    reports = json.loads(report_path.read_text())
    assert isinstance(reports, list)
    assert len(reports) == 2
    assert all(r["valid"] for r in reports), "One or more validation reports invalid"
