"""Smoke test for ``ai-models/train/feature_engineering.py`` (GEMINI-ENG-DIR-V1.0 §3.13).

Feeds 10 synthetic packet dicts (provided by the ``synthetic_packets``
fixture in conftest.py) through ``extract_features_from_packets`` and
verifies the resulting ``FlowFeatures.to_array()`` has shape ``(47,)`` —
the directive-mandated feature dimension for the DPI classifier and
traffic predictor inputs.
"""

from __future__ import annotations

import numpy as np
import pytest

pytestmark = pytest.mark.smoke


def test_extract_features_returns_flowfeatures_instance(synthetic_packets, synthetic_flow_metadata):
    """``extract_features_from_packets`` returns a ``FlowFeatures`` object."""
    from feature_engineering import extract_features_from_packets, FlowFeatures

    feats = extract_features_from_packets(synthetic_packets, synthetic_flow_metadata)
    assert isinstance(feats, FlowFeatures)


def test_feature_vector_shape_is_47(synthetic_packets, synthetic_flow_metadata):
    """The directive mandates feature_dim == 47 for DPI + traffic predictor inputs."""
    from feature_engineering import extract_features_from_packets

    feats = extract_features_from_packets(synthetic_packets, synthetic_flow_metadata)
    arr = feats.to_array()
    assert isinstance(arr, np.ndarray)
    assert arr.shape == (47,), (
        f"Expected feature_dim == 47 per directive, got shape {arr.shape}"
    )
    assert arr.dtype == np.float32


def test_feature_names_length_is_47():
    """``FEATURE_NAMES`` global must list exactly 47 entries (asserted at import time)."""
    from feature_engineering import FEATURE_NAMES

    assert len(FEATURE_NAMES) == 47
    # No duplicates
    assert len(set(FEATURE_NAMES)) == 47


def test_empty_packet_list_does_not_raise():
    """Edge case: an empty packet list must yield a zeroed 47-dim vector, not an exception."""
    from feature_engineering import extract_features_from_packets

    feats = extract_features_from_packets([], {})
    arr = feats.to_array()
    assert arr.shape == (47,)
    assert np.all(arr == 0.0), "Empty packet list should produce zeroed 47-vector"


def test_compute_shannon_entropy_smoke():
    """``compute_shannon_entropy`` is finite and non-negative for varied inputs."""
    from feature_engineering import compute_shannon_entropy

    # Repeated uniform values → entropy 0
    assert compute_shannon_entropy([5.0] * 10) == 0.0
    # Varied values → entropy > 0 and finite
    e = compute_shannon_entropy([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
    assert np.isfinite(e) and e >= 0.0
    # Edge: length < 2 → 0
    assert compute_shannon_entropy([1.0]) == 0.0
    assert compute_shannon_entropy([]) == 0.0
