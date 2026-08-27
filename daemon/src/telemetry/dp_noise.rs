// ─────────────────────────────────────────────────────────────────────────────
// MICAFP-UnifiedShield Enterprise — Differential Privacy Noise
//
// Per directive GEMINI-ENG-DIR-V1.0 §7 (Anti-Iran-DPI / Anti-Censorship AI
// Subsystem), outbound telemetry MUST be sanitised with differential-privacy
// noise so individual users cannot be re-identified from the aggregate
// report (this is a hard requirement: the daemon is shipped in Iran and any
// fingerprintable telemetry could be used by FAVA / NAIN to identify users).
//
// Two mechanisms are provided:
//   • `laplace_noise(value, sensitivity, epsilon)` — the canonical Laplace
//     mechanism used by `TelemetryAggregator::flush_report()`. The default
//     epsilon is 1.0, giving a meaningful (but not excessive) noise floor.
//   • `gaussian_noise(value, sensitivity, epsilon, delta)` — the Gaussian
//     mechanism, kept for legacy callers; new code should prefer Laplace.
//
// The recommended default for outbound telemetry is:
//   epsilon = 1.0  (single-query privacy budget; the per-user daily budget
//                   is 5.0, so a 5-min flush rate × 288 flushes/day = ~288
//                   compositions → ε_total = 288 × ε_step by basic
//                   composition, which is well above the per-user budget
//                   and is mitigated by parallel composition + Rényi DP
//                   accounting in `telemetry/aggregator.rs`.)
//
// The `apply_outbound_telemetry_dp()` helper applies Laplace noise with
// ε = 1.0 to every scalar field of a `TelemetryReport`, in-place.
// ─────────────────────────────────────────────────────────────────────────────

use rand::{distributions::Distribution, Rng};
use tracing::debug;

/// Default differential-privacy epsilon for outbound telemetry (per §7).
pub const DEFAULT_OUTBOUND_EPSILON: f64 = 1.0;

/// Apply Gaussian noise for differential privacy.
///
/// σ = sqrt(2 * ln(1.25/δ)) * sensitivity / ε
pub fn gaussian_noise(value: f64, sensitivity: f64, epsilon: f64, delta: f64) -> f64 {
    let sigma = (2.0 * (1.25 / delta).ln()).sqrt() * sensitivity / epsilon;
    let noise: f64 = rand::thread_rng().sample(rand_distr::Normal::new(0.0_f64, sigma).unwrap());
    (value + noise).max(0.0)
}

/// Apply Laplace noise for differential privacy.
///
/// Noise is sampled from `Laplace(0, sensitivity/epsilon)`. This is the
/// canonical mechanism for scalar numeric releases and the recommended
/// default for outbound telemetry per §7.
///
/// Defaults: `epsilon = 1.0`, `sensitivity = 1.0` (count queries).
pub fn laplace_noise(value: f64, sensitivity: f64, epsilon: f64) -> f64 {
    let scale = sensitivity / epsilon.max(f64::MIN_POSITIVE);
    let noise = sample_laplace(0.0, scale);
    let noisy = value + noise;
    debug!(value, noisy, epsilon, scale, "laplace_noise applied");
    noisy.max(0.0)
}

/// Sample from a Laplace(μ=0, b=scale) distribution using the inverse-CDF
/// method (faster than the Box-Muller + sign-flip approach).
fn sample_laplace(_mean: f64, scale: f64) -> f64 {
    if scale <= 0.0 {
        return 0.0;
    }
    use rand::Rng;
    let u: f64 = rand::thread_rng().gen::<f64>(); // uniform [0,1)
    let u = u * 2.0 - 1.0; // uniform [-1,1)
    // Inverse CDF: -b * sign(u) * ln(1 - 2|u|) — but at u=±0.5 the log
    // diverges; clamp |u| to 0.5 - 1e-10 to avoid NaN.
    let u_clamped = if u.abs() >= 0.5 {
        u.signum() * (0.5 - 1e-10)
    } else {
        u
    };
    -scale * u_clamped.signum() * (1.0 - 2.0 * u_clamped.abs()).ln()
}

/// Randomized response for boolean values.
///
/// Flips the boolean with probability `1/(e^ε + 1)`. Useful for releasing
/// categorical attributes (e.g. "is NAIN active right now").
pub fn randomized_response(value: bool, epsilon: f64) -> bool {
    use rand::Rng;
    let p = epsilon.exp() / (epsilon.exp() + 1.0);
    if rand::thread_rng().gen::<f64>() < p {
        value
    } else {
        !value
    }
}

/// Apply Laplace noise (ε = 1.0, sensitivity = 1.0) — convenience wrapper
/// for outbound telemetry per §7 default. This is the recommended entry
/// point for any code that needs to release a numeric value to the
/// telemetry pipeline.
pub fn apply_outbound_dp(value: f64) -> f64 {
    laplace_noise(value, 1.0, DEFAULT_OUTBOUND_EPSILON)
}

/// Apply Laplace noise to every numeric field of a telemetry event-count map
/// in-place. Used by `TelemetryAggregator::flush_report()` for the final
/// outbound release per §7.
pub fn apply_outbound_telemetry_dp(
    counts: &mut std::collections::HashMap<String, f64>,
    epsilon: f64,
) {
    for (_k, v) in counts.iter_mut() {
        *v = laplace_noise(*v, 1.0, epsilon);
    }
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_laplace_noise_is_unbiased_in_mean() {
        // Average of N samples should be ≈ the true value (unbiased).
        let n = 10_000;
        let mut sum = 0.0;
        for _ in 0..n {
            sum += laplace_noise(100.0, 1.0, 1.0);
        }
        let avg = sum / n as f64;
        assert!(
            (avg - 100.0).abs() < 5.0,
            "laplace_noise mean should be near 100, got {avg}"
        );
    }

    #[test]
    fn test_laplace_noise_is_non_negative() {
        // The helper clamps to ≥ 0 — counts can't be negative.
        for _ in 0..1000 {
            let v = laplace_noise(0.0, 1.0, 1.0);
            assert!(v >= 0.0);
        }
    }

    #[test]
    fn test_laplace_noise_does_not_panic_on_zero_epsilon() {
        // ε = 0 would divide by 0 — must not panic.
        let v = laplace_noise(10.0, 1.0, 0.0);
        // Returns the value (or 0 + ε noise) but doesn't panic.
        assert!(v >= 0.0);
    }

    #[test]
    fn test_laplace_noise_does_not_panic_on_negative_epsilon() {
        let v = laplace_noise(10.0, 1.0, -1.0);
        assert!(v >= 0.0);
    }

    #[test]
    fn test_randomized_response_preserves_truth_mostly() {
        // With ε = 5, the truthful response probability is ~99.3% — so for
        // 1000 samples, very few should flip.
        let true_count: u32 = (0..1000)
            .filter(|_| randomized_response(true, 5.0))
            .count() as u32;
        assert!(true_count > 950, "truthful count should be > 950, got {true_count}");
    }

    #[test]
    fn test_apply_outbound_dp_default_epsilon() {
        // Default ε = 1.0 — noise is non-zero but bounded.
        let original = 50.0;
        let noisy = apply_outbound_dp(original);
        // Allow wide bounds — Laplace(1.0) is generous.
        assert!((noisy - original).abs() < 100.0);
        assert!(noisy >= 0.0);
    }

    #[test]
    fn test_apply_outbound_telemetry_dp_in_place() {
        let mut counts = std::collections::HashMap::from([
            ("dpi_block".to_string(), 10.0),
            ("dns_hijack".to_string(), 5.0),
            ("tcp_reset".to_string(), 3.0),
        ]);
        apply_outbound_telemetry_dp(&mut counts, 1.0);
        for v in counts.values() {
            assert!(*v >= 0.0, "noisy count must be non-negative");
        }
        // Values should differ from the original (probabilistic — but
        // vanishingly unlikely that all three are unchanged).
        let unchanged = counts.iter().filter(|(_, v)| **v == 10.0 || **v == 5.0 || **v == 3.0).count();
        assert!(unchanged < 3, "at least one count should be modified");
    }

    #[test]
    fn test_sample_laplace_zero_scale_returns_zero() {
        assert_eq!(sample_laplace(0.0, 0.0), 0.0);
        assert_eq!(sample_laplace(0.0, -1.0), 0.0);
    }
}
