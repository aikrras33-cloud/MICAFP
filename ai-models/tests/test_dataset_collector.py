"""Smoke test for ``ai-models/train/dataset_collector.py`` (GEMINI-ENG-DIR-V1.0 §3.13).

The dataset collector exposes synthetic flow generators that are the analog
of a "1-second, no-PCAP" capture: they produce flow-feature dicts entirely
in-memory without needing a live packet socket or a PCAP file. This test
verifies the generators return well-typed, non-empty lists for a tiny sample
count so that downstream training scripts can ingest them.

**Does NOT** call ``collect_dataset()`` — that generates 5,200 samples and
writes two ``.npz`` files; it is exercised by the full CI training run
documented in ``ai-models/TRAINING.md``.
"""

from __future__ import annotations

import pytest

pytestmark = pytest.mark.smoke


def test_dataset_collector_importable():
    """Module imports cleanly (numpy is the only hard dependency)."""
    import dataset_collector  # noqa: F401

    assert hasattr(dataset_collector, "generate_normal_flow")
    assert hasattr(dataset_collector, "generate_tls_rst_flow")
    assert hasattr(dataset_collector, "generate_dns_poison_flow")
    assert hasattr(dataset_collector, "generate_http_403_flow")
    assert hasattr(dataset_collector, "generate_sni_filter_flow")
    assert hasattr(dataset_collector, "collect_dataset")


def test_generate_normal_flow_returns_list_of_dicts():
    """``generate_normal_flow`` returns a list of dicts of length == num_samples."""
    from dataset_collector import generate_normal_flow

    samples = generate_normal_flow(num_samples=5)
    assert isinstance(samples, list)
    assert len(samples) == 5
    for s in samples:
        assert isinstance(s, dict)
        # Label sanity: normal = 0
        assert s["label"] == 0
        assert s["label_name"] == "normal"


def test_generate_tls_rst_flow_returns_fava_signature():
    """``generate_tls_rst_flow`` produces the FAVA 95-320ms timing signature."""
    from dataset_collector import generate_tls_rst_flow

    samples = generate_tls_rst_flow(num_samples=3)
    assert isinstance(samples, list)
    assert len(samples) == 3
    for s in samples:
        assert s["label"] == 1
        assert s["label_name"] == "tls_rst"
        assert 95.0 <= s["rst_timing_ms"] <= 320.0, (
            f"FAVA RST timing out of [95, 320] ms band: {s['rst_timing_ms']}"
        )
        assert s["rst_after_syn"] == 1


def test_all_class_generators_smoke():
    """Smoke-test the remaining 3 class generators (DNS poison / HTTP 403 / SNI filter)."""
    from dataset_collector import (
        generate_dns_poison_flow,
        generate_http_403_flow,
        generate_sni_filter_flow,
    )

    dns = generate_dns_poison_flow(num_samples=2)
    assert len(dns) == 2 and dns[0]["label"] == 3 and dns[0]["dns_poisoned"] == 1

    http = generate_http_403_flow(num_samples=2)
    assert len(http) == 2 and http[0]["label"] == 2 and http[0]["http_status_code"] == 403

    sni = generate_sni_filter_flow(num_samples=2)
    assert len(sni) == 2 and sni[0]["label"] == 4 and sni[0]["sni_filtered"] == 1


def test_synthetic_capture_dict_structure():
    """A 1-sample synthetic capture yields a well-formed dict (subset of the 47
    feature keys the ``collect_dataset`` script enumerates —
    ``generate_normal_flow`` populates 38 keys; ``collect_dataset`` later
    pads the feature matrix to 47 columns with ``s.get(k, 0.0)`` defaults).

    This test only asserts the presence of the core DPI-feature keys
    produced by the synthetic generator — the 47-feature contract is enforced
    by ``test_feature_engineering.py::test_feature_vector_shape_is_47``.
    """
    from dataset_collector import generate_normal_flow

    samples = generate_normal_flow(num_samples=1)
    s = samples[0]

    # Core feature keys that ``generate_normal_flow`` MUST populate (subset of
    # the 47-feature contract — these are the fields the script's
    # ``collect_dataset`` later uses to build the X matrix).
    must_have_keys = [
        "packet_inter_arrival_mean", "packet_size_mean",
        "flow_duration", "total_packets", "total_bytes",
        "tcp_flags_syn", "tcp_flags_rst", "tcp_window_size",
        "tls_version", "tls_sni_length",
        "connection_rtt", "retransmission_count",
        "rst_after_syn", "rst_timing_ms",
        "http_status_code", "dns_poisoned", "sni_filtered",
        "entropy_packet_sizes", "burst_count",
        "label", "label_name",
    ]
    missing = [k for k in must_have_keys if k not in s]
    assert not missing, f"Missing core feature keys in synthetic sample: {missing}"

    # Type sanity: label is a small int; label_name is a string; numeric
    # features are int/float, not bool/list.
    assert isinstance(s["label"], int) and 0 <= s["label"] <= 7
    assert isinstance(s["label_name"], str) and s["label_name"]
    assert isinstance(s["flow_duration"], (int, float))
    assert isinstance(s["tcp_flags_rst"], int)
