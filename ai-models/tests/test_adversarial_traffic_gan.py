"""1-step smoke test for ``ai-models/train/adversarial_traffic_gan.py`` (§3.13).

Instead of invoking the top-level ``train()`` function (which would spin up
a ``torch.utils.data.DataLoader`` with ``num_workers=4`` and a TensorBoard
``SummaryWriter`` plus a 500-epoch loop), this test directly exercises **one
critic step + one generator step** of the WGAN-GP inner training loop using
synthetic random data. This validates:

* The ``Generator`` and ``Discriminator`` modules construct and forward correctly.
* ``compute_gradient_penalty`` produces a finite scalar (WGAN-GP term).
* Both ``d_loss`` and ``g_loss`` are finite after one optimizer step.

The full 500-epoch GPU run is documented in ``ai-models/TRAINING.md``.

Skips if ``torch`` or ``tensorboard`` is not installed (the script does
``from torch.utils.tensorboard import SummaryWriter`` at module top-level).
"""

from __future__ import annotations

import math

import pytest

pytest.importorskip("torch")
pytest.importorskip("tensorboard")  # adversarial_traffic_gan.py top-level import

pytestmark = pytest.mark.smoke


def test_gan_constants_and_dims():
    """Constants declared in the script match the directive's expectations."""
    import adversarial_traffic_gan as gan

    assert gan.MAX_PACKETS == 64
    assert gan.BYTE_HIST_DIM == 256
    assert gan.NOISE_DIM == 128
    assert gan.TRAFFIC_TYPE_DIM == 3
    assert gan.FEATURE_DIM == 64 * 2 + 256  # = 384


def test_gan_one_step_smoke():
    """One critic step + one generator step → both losses finite."""
    import torch
    import torch.nn.functional as F
    import adversarial_traffic_gan as gan

    torch.manual_seed(42)

    device = torch.device("cpu")
    batch_size = 4  # >1 so BatchNorm1d in Discriminator is happy

    # ─── Construct models ────────────────────────────────────────────
    generator = gan.Generator(gan.NOISE_DIM, gan.TRAFFIC_TYPE_DIM).to(device)
    discriminator = gan.Discriminator(gan.FEATURE_DIM).to(device)

    g_params_before = [p.detach().clone() for p in generator.parameters()]
    d_params_before = [p.detach().clone() for p in discriminator.parameters()]

    opt_g = torch.optim.Adam(generator.parameters(), lr=1e-4, betas=(0.5, 0.999))
    opt_d = torch.optim.Adam(discriminator.parameters(), lr=1e-4, betas=(0.5, 0.999))

    # ─── Synthetic batch (substitute for DataLoader) ─────────────────
    real_features = torch.randn(batch_size, gan.FEATURE_DIM, device=device)
    # All-browsing one-hot: shape (B, TRAFFIC_TYPE_DIM) = (4, 3)
    traffic_type = torch.zeros(batch_size, gan.TRAFFIC_TYPE_DIM, device=device)
    traffic_type[:, 0] = 1.0

    # ─── 1 critic step ───────────────────────────────────────────────
    opt_d.zero_grad()
    d_real = discriminator(real_features)  # (B, 1)

    noise = torch.randn(batch_size, gan.NOISE_DIM, device=device)
    fake_features = generator.generate_feature_vector(noise, traffic_type).detach()
    d_fake = discriminator(fake_features)  # (B, 1)

    gp = gan.compute_gradient_penalty(
        discriminator, real_features, fake_features, device
    )
    lambda_gp = 10.0
    d_loss = d_fake.mean() - d_real.mean() + lambda_gp * gp
    d_loss.backward()
    opt_d.step()

    d_loss_val = d_loss.item()
    assert math.isfinite(d_loss_val), (
        f"Discriminator loss not finite after 1 step: {d_loss_val}"
    )

    # ─── 1 generator step ─────────────────────────────────────────────
    opt_g.zero_grad()
    noise = torch.randn(batch_size, gan.NOISE_DIM, device=device)
    fake_features = generator.generate_feature_vector(noise, traffic_type)
    d_fake = discriminator(fake_features)
    g_loss = -d_fake.mean()
    g_loss.backward()
    opt_g.step()

    g_loss_val = g_loss.item()
    assert math.isfinite(g_loss_val), (
        f"Generator loss not finite after 1 step: {g_loss_val}"
    )

    # ─── Verify parameters actually changed ───────────────────────────
    g_params_after = [p.detach().clone() for p in generator.parameters()]
    d_params_after = [p.detach().clone() for p in discriminator.parameters()]

    g_changed = any(
        not torch.allclose(b, a) for a, b in zip(g_params_before, g_params_after)
    )
    d_changed = any(
        not torch.allclose(b, a) for a, b in zip(d_params_before, d_params_after)
    )
    assert g_changed, "Generator parameters did not update in 1 step"
    assert d_changed, "Discriminator parameters did not update in 1 step"


def test_generator_output_shapes():
    """The Generator's three output heads have the directive-mandated shapes."""
    import torch
    import adversarial_traffic_gan as gan

    torch.manual_seed(0)
    gen = gan.Generator(gan.NOISE_DIM, gan.TRAFFIC_TYPE_DIM)
    gen.eval()

    noise = torch.randn(2, gan.NOISE_DIM)
    traffic_type = torch.zeros(2, gan.TRAFFIC_TYPE_DIM)
    traffic_type[:, 0] = 1.0

    with torch.no_grad():
        pkt, iat, hist = gen(noise, traffic_type)

    assert pkt.shape == (2, gan.MAX_PACKETS)  # (2, 64)
    assert iat.shape == (2, gan.MAX_PACKETS)
    assert hist.shape == (2, gan.BYTE_HIST_DIM)  # (2, 256)

    # Generated packet sizes ∈ [0, 1500] bytes (Sigmoid head × 1500)
    assert (pkt >= 0).all() and (pkt <= 1500.0).all()
    # Byte histogram is a normalized distribution (sums to ~1 along dim=1)
    assert torch.allclose(hist.sum(dim=1), torch.ones(2), atol=1e-4)

    # ``generate_feature_vector`` concatenates to FEATURE_DIM
    fv = gen.generate_feature_vector(noise, traffic_type)
    assert fv.shape == (2, gan.FEATURE_DIM)
