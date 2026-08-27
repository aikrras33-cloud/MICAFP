// ─────────────────────────────────────────────────────────────────────────────
// MICAFP-UnifiedShield Enterprise — Probe Resistance Server
//
// Per directive GEMINI-ENG-DIR-V1.0 §7 (Anti-Iran-DPI / Anti-Censorship AI
// Subsystem), the daemon's public port MUST be indistinguishable from a benign
// Iranian web service to passive and active probers (censors, GFW-style
// follow-up connections, FAVA v1/v2 active probing).
//
// Behaviour:
//   • On inbound TCP connection, parse the first bytes as an HTTP/1.1 request.
//   • If the request carries a valid `X-Shield-Auth` header whose value
//     matches `HMAC-SHA256(secret, path || body)`, forward the stream to the
//     internal VPN tunnel — this is a legitimate client.
//   • If no valid auth token is present, respond as a benign Iranian site
//     (default: `ap.shaparak.ir` payment-gateway front, or `bmi.ir` bank
//     front) with a 200 OK + a realistic-looking HTML page, and log the probe
//     attempt for telemetry / threat-intel.
//   • The `is_likely_probe` heuristic flags requests that look like an active
//     censor probe: missing User-Agent, missing Accept-Encoding, suspicious
//     `Sec-Fetch-Mode: cors` (browsers always send this), etc.
//
// The ProbeResistanceServer is intentionally self-contained — it owns its own
// TCP accept loop and does not depend on the rest of the obfuscation stack so
// it can be installed in front of any transport entry point.
// ─────────────────────────────────────────────────────────────────────────────

use std::sync::Arc;
use std::time::Duration;

use hmac::{Hmac, Mac};
use sha2::Sha256;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::time::timeout;
use tracing::{debug, info, warn};

type HmacSha256 = Hmac<Sha256>;

/// Default benign front-host. `ap.shaparak.ir` is Iran's national payment
/// gateway — very low probability of being censored by Iranian DPI.
pub const DEFAULT_FRONT_HOST: &str = "ap.shaparak.ir";

/// Maximum number of bytes to read for the HTTP request line + headers
/// (auth verification only needs headers; the body is forwarded afterwards).
const MAX_HEADER_BYTES: usize = 8 * 1024;

/// Read timeout for the first probe packet (censors are slow, browsers are
/// fast — we cap at 5s so a slow probe can't starve the accept loop).
const PROBE_READ_TIMEOUT: Duration = Duration::from_secs(5);

/// A minimal HTTP/1.1 request representation used by the auth check.
#[derive(Debug, Clone, Default)]
pub struct HttpRequest {
    /// HTTP method (GET, POST, …).
    pub method: String,
    /// URL path (without query string).
    pub path: String,
    /// Lower-cased header map (one entry per name; later values win).
    pub headers: std::collections::HashMap<String, String>,
    /// Raw body bytes (only the first chunk — the full body is not buffered).
    pub body: Vec<u8>,
}

impl HttpRequest {
    /// Get a header value, case-insensitively. Header names are stored
    /// lower-cased during parsing.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .get(&name.to_lowercase())
            .map(|v| v.as_str())
    }

    /// `User-Agent` header value (None if absent).
    pub fn user_agent(&self) -> Option<&str> {
        self.header("user-agent")
    }

    /// `Accept-Encoding` header value (None if absent).
    pub fn accept_encoding(&self) -> Option<&str> {
        self.header("accept-encoding")
    }

    /// `Sec-Fetch-Mode` header value (None if absent — real browsers send it).
    pub fn sec_fetch_mode(&self) -> Option<&str> {
        self.header("sec-fetch-mode")
    }

    /// `X-Shield-Auth` header value — the HMAC auth token.
    pub fn shield_auth(&self) -> Option<&str> {
        self.header("x-shield-auth")
    }
}

/// The probe-resistance server. Construct with [`ProbeResistanceServer::new`],
/// then run [`ProbeResistanceServer::run`] in a `tokio::spawn` background task.
pub struct ProbeResistanceServer {
    /// HMAC secret shared with legitimate clients. NEVER sent in plaintext.
    secret: Arc<[u8]>,
    /// Front-host to impersonate for probe responses.
    front_host: String,
}

impl ProbeResistanceServer {
    /// Construct with the shared HMAC secret. The secret should be derived
    /// from the user's license key + device secret (see security/).
    pub async fn new(auth_token_secret: String) -> Self {
        Self {
            secret: Arc::from(auth_token_secret.into_bytes()),
            front_host: DEFAULT_FRONT_HOST.to_string(),
        }
    }

    /// Construct with an explicit front-host override (e.g. `bmi.ir`).
    #[allow(dead_code)]
    pub async fn with_front_host(auth_token_secret: String, front_host: String) -> Self {
        Self {
            secret: Arc::from(auth_token_secret.into_bytes()),
            front_host,
        }
    }

    /// Compute the expected HMAC-SHA256 token for the given path + body.
    ///
    /// The token format is: `hex(HMAC-SHA256(secret, path || ":" || body))`.
    /// The trailing colon disambiguates `(/foo, "bar")` from `(/foobar, "")`.
    pub fn expected_token(&self, path: &str, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(&self.secret)
            .expect("HMAC accepts any key length");
        mac.update(path.as_bytes());
        mac.update(b":");
        mac.update(body);
        hex::encode(mac.finalize().into_bytes())
    }

    /// Constant-time token comparison (delegates to `subtle`-style compare).
    fn token_matches(&self, expected: &str, candidate: &str) -> bool {
        if expected.len() != candidate.len() {
            return false;
        }
        // Constant-time equality.
        let mut diff: u8 = 0;
        for (a, b) in expected.bytes().zip(candidate.bytes()) {
            diff |= a ^ b;
        }
        diff == 0
    }

    /// Verify a request's `X-Shield-Auth` token against the expected HMAC.
    pub fn verify_request(&self, request: &HttpRequest) -> bool {
        let Some(provided) = request.shield_auth() else {
            return false;
        };
        let expected = self.expected_token(&request.path, &request.body);
        self.token_matches(&expected, provided)
    }

    /// Heuristic: does this request look like an active censor probe?
    ///
    /// True when ANY of the following holds:
    ///   • Missing `User-Agent` header (every browser/curl sends one).
    ///   • Missing `Accept-Encoding` header.
    ///   • `Sec-Fetch-Mode: cors` without an `Origin` header (impossible for
    ///     a real browser — fetch() always sets Origin when in cors mode).
    ///   • `User-Agent` starts with `curl/` or `python-requests/` and
    ///     `X-Shield-Auth` is absent (clearly not a legitimate client).
    pub fn is_likely_probe(request: &HttpRequest) -> bool {
        // Missing User-Agent — a strong signal.
        if request.user_agent().is_none() {
            return true;
        }
        // Missing Accept-Encoding — every modern browser sends it.
        if request.accept_encoding().is_none() {
            return true;
        }
        // Sec-Fetch-Mode without Origin — impossible.
        if let Some(mode) = request.sec_fetch_mode() {
            if mode.eq_ignore_ascii_case("cors") && request.header("origin").is_none() {
                return true;
            }
        }
        // curl / python-requests UAs without auth token.
        if let Some(ua) = request.user_agent() {
            let ua_lc = ua.to_lowercase();
            if (ua_lc.starts_with("curl/") || ua_lc.starts_with("python-requests/"))
                && request.shield_auth().is_none()
            {
                return true;
            }
        }
        false
    }

    /// Main TCP accept loop. Should be run as a background tokio task — it
    /// only returns on a fatal listener error.
    ///
    /// Connections are accepted and dispatched to `handle_connection` on
    /// their own task. Each connection has a 5s read timeout for the first
    /// line so a slow censor probe can't starve the accept loop.
    pub async fn run(&self, listener: TcpListener) -> anyhow::Result<()> {
        info!(
            front_host = %self.front_host,
            addr = ?listener.local_addr(),
            "ProbeResistanceServer: accepting connections (front: {})",
            self.front_host
        );

        loop {
            let (stream, peer) = match listener.accept().await {
                Ok(v) => v,
                Err(e) => {
                    warn!(error = %e, "ProbeResistanceServer: accept() failed");
                    continue;
                }
            };

            let secret = Arc::clone(&self.secret);
            let front_host = self.front_host.clone();
            tokio::spawn(async move {
                if let Err(e) =
                    handle_connection(stream, peer.to_string(), &secret, &front_host).await
                {
                    debug!(peer = %peer, error = %e, "ProbeResistanceServer: connection handler exited");
                }
            });
        }
    }
}

/// Handle a single inbound connection: parse the HTTP request, verify auth,
/// and either forward to the tunnel or respond as a benign Iranian site.
async fn handle_connection(
    mut stream: tokio::net::TcpStream,
    peer: String,
    secret: &[u8],
    front_host: &str,
) -> anyhow::Result<()> {
    // Read up to MAX_HEADER_BYTES with a 5s timeout.
    let mut buf = vec![0u8; MAX_HEADER_BYTES];
    let n = match timeout(PROBE_READ_TIMEOUT, stream.read(&mut buf)).await {
        Ok(Ok(n)) => n,
        Ok(Err(e)) => return Err(anyhow::anyhow!("read: {e}")),
        Err(_) => return Err(anyhow::anyhow!("read timeout")),
    };
    if n == 0 {
        return Ok(());
    }
    let raw = &buf[..n];

    // Parse the HTTP request. If parsing fails, treat it as a probe and
    // respond with the benign HTML page.
    let request = match parse_http_request(raw) {
        Some(r) => r,
        None => {
            warn!(peer = %peer, "ProbeResistanceServer: malformed HTTP — responding as benign site");
            return emit_benign_response(&mut stream, front_host, None).await;
        }
    };

    // Build the auth checker from the secret.
    let server = ProbeResistor(secret);

    // Compute the expected token.
    let expected = server.expected_token(&request.path, &request.body);

    let auth_ok = request
        .shield_auth()
        .map(|v| token_matches(expected.as_bytes(), v.as_bytes()))
        .unwrap_or(false);

    if auth_ok {
        info!(peer = %peer, path = %request.path, "ProbeResistanceServer: authenticated client — forwarding to tunnel");
        // Forward the raw bytes already consumed + relay the rest of the stream.
        // In production: hand `stream` off to the TransportManager's tunnel
        // pipeline (e.g. via `tokio::io::copy` to the inner transport).
        // For now, emit a 101 Switching Protocols and close.
        stream
            .write_all(b"HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: shield-tunnel\r\n\r\n")
            .await?;
        return Ok(());
    }

    // Not authenticated — log and respond as benign Iranian site.
    let probe = ProbeResistanceServer::is_likely_probe(&request);
    warn!(
        peer = %peer,
        path = %request.path,
        ua = ?request.user_agent(),
        likely_probe = probe,
        "ProbeResistanceServer: unauthenticated request — responding as benign site"
    );

    emit_benign_response(&mut stream, front_host, Some(&request)).await
}

/// Internal helper for `expected_token` — wraps a secret slice so we can
/// reuse the HMAC logic without exposing `Arc<[u8]>` plumbing.
struct ProbeResistor<'a>(&'a [u8]);

impl<'a> ProbeResistor<'a> {
    fn expected_token(&self, path: &str, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(self.0)
            .expect("HMAC accepts any key length");
        mac.update(path.as_bytes());
        mac.update(b":");
        mac.update(body);
        hex::encode(mac.finalize().into_bytes())
    }
}

/// Constant-time token comparison.
fn token_matches(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff: u8 = 0;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Parse a raw HTTP/1.1 request into [`HttpRequest`] for auth checking.
///
/// Returns `None` if the request is not parseable as HTTP/1.1 (e.g. binary
/// TLS handshake bytes, malformed request line). In that case the caller
/// treats the connection as a probe and emits the benign HTML response.
fn parse_http_request(raw: &[u8]) -> Option<HttpRequest> {
    let text = std::str::from_utf8(raw).ok()?;

    // Split request-line + headers from the body.
    let (head, body) = match text.find("\r\n\r\n") {
        Some(idx) => (&text[..idx], &text[idx + 4..]),
        None => (text, ""),
    };

    let mut lines = head.split("\r\n");
    let request_line = lines.next()?;
    let mut parts = request_line.split_whitespace();
    let method = parts.next()?.to_string();
    let raw_path = parts.next()?;
    // Strip the query string from the path for HMAC verification.
    let path = raw_path.split('?').next().unwrap_or(raw_path).to_string();

    let mut headers = std::collections::HashMap::new();
    for line in lines {
        if let Some((name, value)) = line.split_once(':') {
            headers.insert(
                name.trim().to_lowercase(),
                value.trim().to_string(),
            );
        }
    }

    Some(HttpRequest {
        method,
        path,
        headers,
        body: body.as_bytes().to_vec(),
    })
}

/// Emit a benign 200 OK response mimicking `ap.shaparak.ir` / `bmi.ir` style.
///
/// The response includes:
///   • A realistic set of headers (Server, Content-Type, Cache-Control, …)
///   • A small but plausible HTML page with Persian text matching the front.
///   • No trace of the daemon's identity (no `X-Shield-*` headers).
async fn emit_benign_response(
    stream: &mut tokio::net::TcpStream,
    front_host: &str,
    request: Option<&HttpRequest>,
) -> anyhow::Result<()> {
    let body = benign_html_page(front_host);
    let body_len = body.len();

    let extra_headers = if let Some(req) = request {
        if ProbeResistanceServer::is_likely_probe(req) {
            // For probe-shaped requests, mimic a server that just sits there
            // and serves the homepage — no special behavior.
            String::from("X-Frame-Options: DENY\r\n")
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    let response = format!(
        "HTTP/1.1 200 OK\r\n\
         Server: nginx\r\n\
         Date: Thu, 01 Jan 2026 00:00:00 GMT\r\n\
         Content-Type: text/html; charset=utf-8\r\n\
         Content-Length: {body_len}\r\n\
         Connection: close\r\n\
         Cache-Control: public, max-age=300\r\n\
         {extra_headers}\
         \r\n"
    );

    stream.write_all(response.as_bytes()).await?;
    stream.write_all(&body).await?;
    stream.flush().await?;
    Ok(())
}

/// Generate a benign HTML page for the given front-host.
///
/// This is intentionally small and low-overhead — the goal is "looks
/// plausible to a censor parsing the first few bytes", not "fools a
/// human reviewer".
fn benign_html_page(front_host: &str) -> Vec<u8> {
    let html = match front_host {
        "bmi.ir" => {
            // Bank Melli Iran homepage front.
            "<!DOCTYPE html>\n\
             <html lang=\"fa\" dir=\"rtl\">\n\
             <head>\n  \
               <meta charset=\"utf-8\">\n  \
               <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  \
               <title>بانک ملی ایران</title>\n\
             </head>\n\
             <body>\n  \
               <h1>بانک ملی ایران</h1>\n  \
               <p>به سامانه اینترنتی بانک ملی ایران خوش آمدید.</p>\n  \
               <p>صفحه اصلی — در حال بارگذاری...</p>\n\
             </body>\n\
             </html>\n"
        }
        _ => {
            // Default: Shaparak (national payment gateway) front.
            "<!DOCTYPE html>\n\
             <html lang=\"fa\" dir=\"rtl\">\n\
             <head>\n  \
               <meta charset=\"utf-8\">\n  \
               <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  \
               <title>درگاه پرداخت الکترونیک شاپرک</title>\n\
             </head>\n\
             <body>\n  \
               <h1>درگاه پرداخت الکترونیک شاپرک</h1>\n  \
               <p>به سامانه شاپرک خوش آمدید. لطفاً شکیبا باشید.</p>\n  \
               <p>صفحه اصلی — پرداخت آنلاین.</p>\n\
             </body>\n\
             </html>\n"
        }
    };
    html.as_bytes().to_vec()
}

// ── Tests ───────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_expected_token_stability() {
        let server = ProbeResistanceServer {
            secret: Arc::from(b"test-secret".to_vec()),
            front_host: DEFAULT_FRONT_HOST.to_string(),
        };
        let t1 = server.expected_token("/api/v1/connect", b"hello");
        let t2 = server.expected_token("/api/v1/connect", b"hello");
        assert_eq!(t1, t2, "expected_token must be deterministic");
        assert_eq!(t1.len(), 64, "HMAC-SHA256 hex = 64 chars");
    }

    #[test]
    fn test_expected_token_path_disambiguation() {
        let server = ProbeResistanceServer {
            secret: Arc::from(b"test-secret".to_vec()),
            front_host: DEFAULT_FRONT_HOST.to_string(),
        };
        let t1 = server.expected_token("/foo", b"bar");
        let t2 = server.expected_token("/foobar", b"");
        // Different inputs MUST produce different tokens.
        assert_ne!(t1, t2);
    }

    #[test]
    fn test_token_matches_constant_time() {
        assert!(token_matches(b"abc", b"abc"));
        assert!(!token_matches(b"abc", b"abd"));
        assert!(!token_matches(b"abc", b"abcd"));
        assert!(!token_matches(b"abcd", b"abc"));
    }

    #[test]
    fn test_parse_http_request_get() {
        let raw = b"GET /api/v1/connect HTTP/1.1\r\nHost: example.com\r\nUser-Agent: Mozilla/5.0\r\nAccept-Encoding: gzip\r\n\r\n";
        let req = parse_http_request(raw).expect("parse");
        assert_eq!(req.method, "GET");
        assert_eq!(req.path, "/api/v1/connect");
        assert_eq!(req.user_agent(), Some("Mozilla/5.0"));
        assert_eq!(req.accept_encoding(), Some("gzip"));
        assert!(req.shield_auth().is_none());
    }

    #[test]
    fn test_parse_http_request_post_with_body() {
        let raw = b"POST /api/v1/connect HTTP/1.1\r\nHost: example.com\r\nX-Shield-Auth: deadbeef\r\nContent-Length: 5\r\n\r\nhello";
        let req = parse_http_request(raw).expect("parse");
        assert_eq!(req.method, "POST");
        assert_eq!(req.path, "/api/v1/connect");
        assert_eq!(req.shield_auth(), Some("deadbeef"));
        assert_eq!(req.body, b"hello");
    }

    #[test]
    fn test_parse_http_request_query_string_stripped() {
        let raw = b"GET /api/v1/connect?token=abc HTTP/1.1\r\nHost: example.com\r\n\r\n";
        let req = parse_http_request(raw).expect("parse");
        assert_eq!(req.path, "/api/v1/connect");
    }

    #[test]
    fn test_parse_http_request_malformed_returns_none() {
        assert!(parse_http_request(b"\x16\x03\x01\x00\x05\x01").is_none());
        assert!(parse_http_request(b"").is_none());
    }

    #[test]
    fn test_is_likely_probe_missing_user_agent() {
        let req = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            headers: std::collections::HashMap::from([
                ("accept-encoding".into(), "gzip".into()),
            ]),
            body: vec![],
        };
        assert!(ProbeResistanceServer::is_likely_probe(&req));
    }

    #[test]
    fn test_is_likely_probe_missing_accept_encoding() {
        let req = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            headers: std::collections::HashMap::from([
                ("user-agent".into(), "Mozilla/5.0".into()),
            ]),
            body: vec![],
        };
        assert!(ProbeResistanceServer::is_likely_probe(&req));
    }

    #[test]
    fn test_is_likely_probe_curl_without_auth() {
        let req = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            headers: std::collections::HashMap::from([
                ("user-agent".into(), "curl/8.5.0".into()),
                ("accept-encoding".into(), "gzip".into()),
            ]),
            body: vec![],
        };
        assert!(ProbeResistanceServer::is_likely_probe(&req));
    }

    #[test]
    fn test_is_likely_probe_legit_browser() {
        let req = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            headers: std::collections::HashMap::from([
                ("user-agent".into(), "Mozilla/5.0".into()),
                ("accept-encoding".into(), "gzip, br".into()),
                ("sec-fetch-mode".into(), "navigate".into()),
            ]),
            body: vec![],
        };
        // Legit browser request without probe markers.
        assert!(!ProbeResistanceServer::is_likely_probe(&req));
    }

    #[test]
    fn test_is_likely_probe_sec_fetch_cors_without_origin() {
        let req = HttpRequest {
            method: "GET".into(),
            path: "/".into(),
            headers: std::collections::HashMap::from([
                ("user-agent".into(), "Mozilla/5.0".into()),
                ("accept-encoding".into(), "gzip, br".into()),
                ("sec-fetch-mode".into(), "cors".into()),
            ]),
            body: vec![],
        };
        assert!(ProbeResistanceServer::is_likely_probe(&req));
    }

    #[test]
    fn test_benign_html_page_shaparak_default() {
        let page = benign_html_page(DEFAULT_FRONT_HOST);
        let s = std::str::from_utf8(&page).unwrap();
        assert!(s.contains("شاپرک"), "default front must mention Shaparak");
    }

    #[test]
    fn test_benign_html_page_bmi() {
        let page = benign_html_page("bmi.ir");
        let s = std::str::from_utf8(&page).unwrap();
        assert!(s.contains("بانک ملی"), "bmi.ir front must mention Bank Melli");
    }
}
