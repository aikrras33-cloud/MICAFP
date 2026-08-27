# UnifiedShield AI-Model Training Pipeline — Full CI Reference

This file documents the **full** training pipeline for the UnifiedShield
v9.0.0-enterprise AI models. The pipeline requires a real CI environment
with a CUDA-capable GPU (or a beefy CPU box) and is **NOT** exercised by the
lightweight smoke tests in `ai-models/tests/`.

> **Directive reference:** GEMINI-ENG-DIR-V1.0 §3.10 (AI model training)
> and §11 Step 5.3–5.11. The smoke-test scaffolding under §3.13 lives in
> `ai-models/tests/` and only runs 1-epoch / 1-step invocations of each
> script to verify imports, tensor shapes, and end-to-end ONNX export.
> The commands below are the directive-mandated full training runs.

---

## 0. Prerequisites

A clean Python ≥ 3.10 venv with:

```bash
python3 -m venv .venv
source .venv/bin/activate

# Train/quantize pipeline
pip install -r ai-models/train/requirements.txt
pip install tensorboard          # required by adversarial_traffic_gan.py top-level import

# Test scaffolding
pip install -r ai-models/tests/requirements.txt
```

`ai-models/train/requirements.txt` pins:
- `torch>=2.2.0`
- `numpy>=1.24.0`
- `onnx>=1.15.0`
- `onnxruntime>=1.17.0`
- `onnxruntime-extensions>=0.10.0`
- `scapy>=2.5.0`

For CUDA builds, install the CUDA-matched `torch` wheel from
<https://pytorch.org/get-started/locally/> before installing the rest.

### GPU recommendation

| Model            | Epochs  | Hidden | Approx. GPU memory | Wall-time (1× A100) |
| ---------------- | ------- | ------ | ------------------ | ------------------- |
| DPI classifier   | 200     | 256³   | ~2 GB              | ~25 min             |
| Traffic predictor| 100     | 128×2  | ~3 GB              | ~40 min             |
| Traffic GAN      | 500     | 2048   | ~6 GB              | ~3 h                |

Run all three sequentially in CI — total ≈ 4 h on 1× A100.

---

## 1. Dataset collection

```bash
mkdir -p ai-models/data ai-models/models

cd ai-models
python3 train/dataset_collector.py
# → writes ai-models/data/dpi_dataset.npz      (X: (5200, 47), y: 0..4)
# → writes ai-models/data/traffic_dataset.npz  (X: (5200, 47), y: 0.0/1.0 binary)
# → writes ai-models/data/dpi_dataset_raw.json (first 100 samples, debug only)
```

Outputs (per `dataset_collector.collect_dataset`):
- 2000 normal flows + 1000 TLS-RST + 600 HTTP-403 + 800 DNS-poison + 800 SNI-filter
  = 5200 samples × 47 features
- 5-class label set (0=normal, 1=tls_rst, 2=http_403, 3=dns_poison, 4=sni_filter)
- Binary `traffic_dataset.npz` collapses to `(y > 0)`.

---

## 2. Train DPI classifier (§3.10 / Step 5.3–5.5)

```bash
cd ai-models
python3 train/dpi_classifier_train.py
# defaults: data_path="data/dpi_dataset.npz", epochs=200, batch_size=256,
#          lr=3e-4, weight_decay=0.01, val_split=0.15, output_dir="models"
```

Artifacts written to `ai-models/models/`:
- `dpi_classifier_best.pt`      — best val-acc PyTorch state_dict
- `dpi_classifier.onnx`         — opset-17 ONNX (FP32)
- `dpi_classifier_meta.json`    — metadata (num_features=47, num_classes=8, …)

**Architecture:** `47 → [LayerNorm + GELU + Dropout + 256-residual]×3 → 128 → 8`,
optimizer `AdamW 3e-4`, scheduler `CosineAnnealingLR T_max=200 η_min=1e-6`,
loss `CrossEntropyLoss` with inverse-frequency class weights, gradient
clip `max_norm=1.0`.

---

## 3. Train traffic predictor (§3.10 / Step 5.6–5.8)

```bash
cd ai-models
python3 train/traffic_predictor_train.py
# defaults: data_path="data/traffic_dataset.npz", epochs=100, batch_size=128,
#          lr=1e-3, weight_decay=0.01, seq_len=10, val_split=0.15,
#          output_dir="models"
```

Artifacts written to `ai-models/models/`:
- `traffic_predictor_best.pt`
- `traffic_predictor.onnx`         — opset-17 ONNX (FP32)
- `traffic_predictor_meta.json`    — metadata (feature_dim=47, seq_len=10, …)

**Architecture:** `Embedding 47→64` → `BiLSTM 2-layer h=128` →
`Self-Attention 256→1` → `FC 256→128→1`; loss `BCEWithLogitsLoss`,
gradient clip `max_norm=1.0`, CosineAnnealing `T_max=100`.

---

## 4. Train adversarial-traffic GAN (§3.10 / Step 5.9–5.10)

First generate synthetic traffic captures (real deployments must replace
this with actual `.npy` files captured by the daemon's FAVA-DPI recorder):

```bash
cd ai-models
python3 train/adversarial_traffic_gan.py \
    --generate-synthetic \
    --data-dir ./traffic_captures \
    --synthetic-samples 10000
# → traffic_captures/{packet_sizes,inter_arrival_times,byte_histograms,traffic_types}.npy
```

Then run the full WGAN-GP training loop:

```bash
cd ai-models
python3 train/adversarial_traffic_gan.py \
    --data-dir ./traffic_captures \
    --epochs 500 \
    --batch-size 64 \
    --lr-d 1e-4 \
    --lr-g 1e-4 \
    --n-critic 5 \
    --lambda-gp 10.0 \
    --output-dir ./models \
    --device auto
```

Artifacts written to `ai-models/models/`:
- `traffic_gan.onnx`               — Generator wrapper (opset-17, INT8-quantized in-script)
- `traffic_gan_int8.onnx`          — INT8 dynamic-quantized copy
- `best_model.pt`, `final_model.pt` — combined Generator+Discriminator checkpoint
- `checkpoint_epoch_{50,100,…,500}.pt`
- `logs/`                          — TensorBoard event files (`tensorboard --logdir models/logs`)

**Architecture:** WGAN-GP with 1D-CNN Discriminator (3 parallel
Conv1d branches for packet_sizes / inter_arrival_times / byte_histograms)
and a Linear-2048 Generator producing (pkt_sizes, iat, byte_hist).
`λ_gp = 10`, critic updates per generator step `n_critic = 5`.

---

## 5. Quantize to INT8 (§3.11 / Step 5.11)

```bash
cd ai-models
python3 quantize/quantize_models.py
# walks ai-models/models/*.onnx and writes *_int8.onnx + .quant_meta.json
# uses static quantization with ai-models/models/dpi_dataset.npz as calibration
# data when present, else dynamic quantization.
```

Per-model INT8 outputs:
- `dpi_classifier_int8.onnx` + `dpi_classifier_int8.quant_meta.json`
- `traffic_predictor_int8.onnx` + `traffic_predictor_int8.quant_meta.json`
- `traffic_gan_int8.onnx` (already produced in-script, re-quantized idempotently)

Expected size reduction: 4×–8× on FP32 → INT8 (per-channel QDQ format,
`QuantType.QInt8`, `ActivationSymmetric + WeightSymmetric`).

---

## 6. Validate ONNX models (§3.12)

```bash
cd ai-models
python3 quantize/validate_onnx.py
# walks ai-models/models/*.onnx, runs onnx.checker + onnxruntime inference,
# benchmarks 50 iterations, writes ai-models/models/validation_report.json
```

The validation report contains per-model:
- `valid` (bool), `errors` (list[str]), `warnings` (list[str])
- `info`: `opset_version`, `input_shape`, `output_shape`, `size_mb`,
  `param_count`, `inference_output_shape`, `inference_output_dtype`,
  `avg_inference_ms`, `std_inference_ms`

Expected per-model inference latency: < 5 ms on CPU, < 1 ms on GPU.

---

## 7. Smoke tests (§3.13) — already in this repo

Run lightweight 1-epoch / 1-step verifications (no GPU needed):

```bash
cd <repo-root>
pip install -r ai-models/tests/requirements.txt
pytest ai-models/tests/ -v
# Optional: filter to only smoke-marked tests
pytest ai-models/tests/ -v -m smoke
# Optional: with coverage
pytest ai-models/tests/ -v --cov=train --cov=quantize --cov-report=term-missing
```

The smoke suite is **not** a substitute for §3.10 / Step 5.3–5.11; it only
verifies that:
- every script imports cleanly,
- the model architectures produce the directive-mandated tensor shapes
  (47 features → 8 DPI classes; 47 → 1 binary predictor; 384-dim GAN
  feature vector),
- ONNX export + onnxruntime round-trip succeeds for tiny synthetic inputs,
- the WGAN-GP loss is finite after a single critic + generator step.

---

## 8. CI integration (GitHub Actions snippet)

Drop the following into `.github/workflows/ai-models-train.yml`:

```yaml
name: ai-models-train
on:
  schedule: [ { cron: "0 4 * * 0" } ]   # weekly Sunday 04:00 UTC
  workflow_dispatch: {}
jobs:
  train:
    runs-on: self-hosted           # GPU runner
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: pip install -r ai-models/train/requirements.txt
      - run: pip install -r ai-models/tests/requirements.txt
      - run: pip install tensorboard
      - name: Smoke
        run: pytest ai-models/tests/ -v -m smoke
      - name: Dataset
        run: python3 ai-models/train/dataset_collector.py
      - name: DPI
        run: python3 ai-models/train/dpi_classifier_train.py
      - name: Traffic predictor
        run: python3 ai-models/train/traffic_predictor_train.py
      - name: GAN synthetic data
        run: |
          python3 ai-models/train/adversarial_traffic_gan.py \
            --generate-synthetic --data-dir ai-models/traffic_captures \
            --synthetic-samples 10000
      - name: GAN train
        run: |
          python3 ai-models/train/adversarial_traffic_gan.py \
            --data-dir ai-models/traffic_captures --epochs 500 \
            --output-dir ai-models/models
      - name: Quantize
        run: python3 ai-models/quantize/quantize_models.py
      - name: Validate
        run: python3 ai-models/quantize/validate_onnx.py
      - uses: actions/upload-artifact@v4
        with:
          name: ai-models-v9.0.0-enterprise
          path: ai-models/models/
```

---

## 9. Post-training deployment

The committed ONNX artifacts (after a successful CI run) feed:
1. The Rust `unifiedshield` daemon via `ort` (CPU inference on the host)
2. The browser extensions (chrome / firefox) via `onnxruntime-web`
   (WebAssembly backend, INT8-quantized weights — see §3.11)
3. The Flutter mobile apps via the `unifiedshield` FFI (Android NDK /
   iOS framework) — see `core/micafp-transport-core`.

**Never commit unquantized FP32 ONNX files** to the repo — only the INT8
versions are small enough (< 5 MB each) for in-app bundling.
