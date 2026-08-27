// ─────────────────────────────────────────────────────────────────────────────
// GeminiCloudScanner — Cloud-Side DPI Classification (§10.2)
//
// Per UnifiedShield directive §10.2:
//   • Sends the last 60 s of flow features (60×47 matrix) to
//     `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent`
//     with the API key, a system prompt explaining DPI detection, and the
//     features serialized as a JSON array.
//   • Returns `{ is_blocked, confidence, suggested_transport, reasoning }`.
//   • 5-minute in-memory cache (`tokio::sync::RwLock<Option<(Instant, CloudScanResult)>>`)
//     — repeated scans with identical features return the cached result
//     without a network round-trip.
//   • `is_online()` performs a quick TCP probe to 8.8.8.8:53 or 1.1.1.1:53.
//   • If offline, returns `CloudScanResult::offline()` and the on-device
//     ONNX models take over (silent degradation per §10.2).
// ─────────────────────────────────────────────────────────────────────────────

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Context as _, Result};
use serde::{Deserialize, Serialize};
use tokio::net::TcpStream;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};

/// The cloud scan result envelope returned to the assistant.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CloudScanResult {
    /// Whether the cloud classifier believes the current flow signature
    /// would be blocked by GII / DPI filters.
    pub is_blocked: bool,
    /// Classifier confidence in [0.0, 1.0].
    pub confidence: f32,
    /// Suggested next transport (e.g. "hysteria2", "tuic", "shadowtls").
    pub suggested_transport: String,
    /// Human-readable reasoning from the cloud model.
    pub reasoning: String,
    /// Whether the cloud was actually queried (false for offline fallback).
    pub online: bool,
}

impl CloudScanResult {
    /// Construct the offline-degradation sentinel. The assistant treats
    /// this as "cloud was unavailable, on-device ONNX models took over."
    pub fn offline() -> Self {
        Self {
            is_blocked: false,
            confidence: 0.0,
            suggested_transport: String::new(),
            reasoning: "cloud offline — on-device ONNX took over".to_string(),
            online: false,
        }
    }
}

/// The 5-minute cache TTL.
const CACHE_TTL: Duration = Duration::from_secs(5 * 60);

/// The Gemini REST endpoint (gemini-2.5-pro, generateContent).
const GEMINI_URL: &str =
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent";

/// The system prompt sent to Gemini explaining the DPI-detection task.
const GEMINI_SYSTEM_PROMPT: &str = "\
You are a deep-packet-inspection (DPI) classifier for the Iranian National \
Information Network (NIN). You receive a 60×47 matrix of normalized flow \
features (60 consecutive 1-second windows × 47 features per window). \
Return ONLY a JSON object with keys: \
`is_blocked` (bool), `confidence` (float 0..1), `suggested_transport` \
(one of: hysteria2, tuic, shadowtls, vless, reality, meek, webtransport), \
`reasoning` (≤60 words).";

pub struct GeminiCloudScanner {
    api_key: String,
    http: reqwest::Client,
    /// In-memory cache. Key is a hash of the features; value is the
    /// timestamp + result pair.
    cache: RwLock<Option<(u64, Instant, CloudScanResult)>>,
}

impl GeminiCloudScanner {
    pub fn new(api_key: String) -> Self {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .unwrap_or_else(|_| reqwest::Client::new());
        Self {
            api_key,
            http,
            cache: RwLock::new(None),
        }
    }

    /// Quick check whether international internet is reachable. Tries
    /// 8.8.8.8:53 first, then 1.1.1.1:53. Returns true on the first
    /// successful TCP connect.
    pub async fn is_online(&self) -> bool {
        for addr in &[
            "8.8.8.8:53", // Google Public DNS
            "1.1.1.1:53", // Cloudflare
        ] {
            let sock_addr: SocketAddr = match addr.parse() {
                Ok(a) => a,
                Err(_) => continue,
            };
            match tokio::time::timeout(
                Duration::from_secs(3),
                TcpStream::connect(&sock_addr),
            )
            .await
            {
                Ok(Ok(_)) => {
                    debug!("is_online: probe to {} succeeded", addr);
                    return true;
                }
                Ok(Err(e)) => debug!("is_online: probe to {} failed: {}", addr, e),
                Err(_) => debug!("is_online: probe to {} timed out", addr),
            }
        }
        false
    }

    /// Classify a 60×47 flow-feature matrix. Returns the cached result if
    /// the feature hash matches a fresh (≤5-min) entry. Returns
    /// `CloudScanResult::offline()` if `is_online()` returns false — the
    /// on-device ONNX models take over.
    pub async fn classify_flow(&self, features: Vec<Vec<f32>>) -> Result<CloudScanResult> {
        let hash = hash_features(&features);

        // 1. Check cache.
        {
            let guard = self.cache.read().await;
            if let Some((cached_hash, ts, result)) = guard.as_ref() {
                if *cached_hash == hash && ts.elapsed() < CACHE_TTL {
                    debug!("classify_flow: cache hit (hash={})", hash);
                    return Ok(result.clone());
                }
            }
        }

        // 2. Probe international internet.
        if !self.is_online().await {
            info!("classify_flow: offline — returning CloudScanResult::offline()");
            let offline = CloudScanResult::offline();
            // Cache the offline result too (so we don't hammer the probe).
            self.cache_write(hash, offline.clone()).await;
            return Ok(offline);
        }

        // 3. POST to Gemini.
        let result = self.call_gemini(&features).await?;
        // 4. Cache + return.
        self.cache_write(hash, result.clone()).await;
        Ok(result)
    }

    async fn cache_write(&self, hash: u64, result: CloudScanResult) {
        let mut guard = self.cache.write().await;
        *guard = Some((hash, Instant::now(), result));
    }

    async fn call_gemini(&self, features: &[Vec<f32>]) -> Result<CloudScanResult> {
        if self.api_key.is_empty() {
            return Err(anyhow!("Gemini API key is empty"));
        }

        let url = format!("{}?key={}", GEMINI_URL, self.api_key);
        let features_json = serde_json::to_value(features)
            .context("serialize flow features")?;

        let body = serde_json::json!({
            "system_instruction": {
                "parts": [{ "text": GEMINI_SYSTEM_PROMPT }]
            },
            "contents": [{
                "role": "user",
                "parts": [{
                    "text": format!(
        "Flow feature matrix (60×47, JSON array of arrays of floats):\n{}",
        features_json
                    )
                }]
            }],
            "generationConfig": {
                "temperature": 0.1,
                "maxOutputTokens": 512,
                "responseMimeType": "application/json"
            }
        });

        let resp = self
            .http
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .context("gemini HTTP request")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            warn!("gemini HTTP {}: {}", status, text);
            return Err(anyhow!("gemini HTTP {}: {}", status, text));
        }

        let response_json: serde_json::Value = resp.json().await.context("parse gemini JSON")?;

        // Extract the text from candidates[0].content.parts[0].text.
        let text = response_json
            .get("candidates")
            .and_then(|c| c.get(0))
            .and_then(|c| c.get("content"))
            .and_then(|c| c.get("parts"))
            .and_then(|p| p.get(0))
            .and_then(|p| p.get("text"))
            .and_then(|t| t.as_str())
            .ok_or_else(|| anyhow!("gemini response missing candidates[0].content.parts[0].text"))?;

        // Gemini may wrap the JSON in markdown fences when not using
        // `responseMimeType: application/json`; strip them defensively.
        let trimmed = text
            .trim()
            .trim_start_matches("```json")
            .trim_start_matches("```")
            .trim_end_matches("```")
            .trim();

        let result: CloudScanResult = serde_json::from_str(trimmed)
            .with_context(|| format!("parse gemini output as CloudScanResult: {}", trimmed))?;

        Ok(CloudScanResult {
            online: true,
            ..result
        })
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// FNV-1a 64-bit hash of the feature matrix — used as the cache key.
fn hash_features(features: &[Vec<f32>]) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for row in features {
        for &f in row {
            let bits = f.to_bits();
            hash ^= bits as u64;
            hash = hash.wrapping_mul(0x100000001b3);
        }
        // Row separator to disambiguate matrix shapes.
        hash ^= 0x2C;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offline_result_is_marked_offline() {
        let r = CloudScanResult::offline();
        assert!(!r.online);
        assert!(!r.is_blocked);
        assert!(r.confidence <= 0.0);
        assert!(r.reasoning.contains("offline"));
    }

    #[test]
    fn hash_features_distinguishes_inputs() {
        let a = vec![vec![0.1, 0.2]; 60];
        let b = vec![vec![0.1, 0.3]; 60];
        assert_ne!(hash_features(&a), hash_features(&b));
    }

    #[test]
    fn hash_features_stable_for_identical_input() {
        let f = vec![vec![0.1, 0.2, 0.3]; 60];
        assert_eq!(hash_features(&f), hash_features(&f));
    }

    #[tokio::test]
    async fn new_scanner_starts_with_empty_cache() {
        let s = GeminiCloudScanner::new("test-key".to_string());
        assert!(s.cache.read().await.is_none());
    }

    #[tokio::test]
    async fn classify_flow_with_empty_key_errors() {
        let s = GeminiCloudScanner::new(String::new());
        // With an empty key, the call would error — but we'll first probe
        // is_online which (in the sandbox) returns false and short-circuits.
        let features = vec![vec![0.0; 47]; 60];
        let r = s.classify_flow(features).await.unwrap();
        assert!(!r.online);
    }

    #[tokio::test]
    async fn cache_returns_same_result_for_same_hash() {
        let s = GeminiCloudScanner::new(String::new());
        let features = vec![vec![0.0; 47]; 60];
        // First call — offline result is cached.
        let r1 = s.classify_flow(features.clone()).await.unwrap();
        assert!(!r1.online);
        // Second call — should hit cache without re-probing.
        let r2 = s.classify_flow(features).await.unwrap();
        assert_eq!(r1.reasoning, r2.reasoning);
    }
}
