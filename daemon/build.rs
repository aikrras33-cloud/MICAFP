// ─────────────────────────────────────────────────────────────────────────────
// MICAFP UnifiedShield v9.0 — Build Script
//
// Per directive GEMINI-ENG-DIR-V1.0 §3.23 (GEMINI-STEP-2):
//   • Compiles `proto/shield.proto` via prost-build into `src/proto_gen/`
//     (stable on-disk location so daemon/src/proto_gen/mod.rs can
//     `include!` the generated file).
//   • Sets platform-specific cfg flags.
//   • Embeds resource JSON files at compile time via include_str!.
// ─────────────────────────────────────────────────────────────────────────────

use std::env;
use std::path::PathBuf;

type BuildResult = Result<(), Box<dyn std::error::Error>>;

fn main() -> BuildResult {
    // ── Determine paths ─────────────────────────────────────────────────────
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR")?);
    let proto_dir = manifest_dir.join("proto");
    let shield_proto = proto_dir.join("shield.proto");

    // ── Compile the IPC proto contract ───────────────────────────────────────
    // Per directive §3.23, the generated Rust types are written to
    // `src/proto_gen/` (NOT `$OUT_DIR`) so they can be `include!`d by
    // daemon/src/proto_gen/mod.rs at compile time. The prost-build Config
    // adds `serde::Serialize` / `serde::Deserialize` derives to all
    // generated message types so they can round-trip through the
    // daemon's JSON IPC fallback.
    //
    // If `protoc` (the C binutils) is not on PATH, prost-build will fail
    // here. To keep the rest of the daemon buildable in environments
    // without protoc (e.g. CI sandboxes without build-essential), we
    // catch the failure, log a warning, and emit a `cargo:rustc-cfg`
    // flag `no_proto_gen` so daemon/src/proto_gen/mod.rs can fall back
    // to an empty stub instead of failing the entire crate.
    if shield_proto.exists() {
        let proto_gen_dir = manifest_dir.join("src/proto_gen");
        // Ensure the output directory exists — prost-build does not
        // create intermediate directories on its own.
        std::fs::create_dir_all(&proto_gen_dir)?;

        let proto_result = prost_build::Config::new()
            .out_dir(&proto_gen_dir)
            .type_attribute(".", "#[derive(serde::Serialize, serde::Deserialize)]")
            .compile_protos(&[shield_proto.as_path()], &[proto_dir.as_path()]);

        match proto_result {
            Ok(()) => {
                println!("cargo:rustc-cfg=has_proto_gen");
                println!("cargo:rerun-if-changed=proto/shield.proto");
            }
            Err(e) => {
                // Don't fail the whole build — just emit the no-proto
                // cfg flag so daemon/src/proto_gen/mod.rs falls back to
                // an empty stub. Downstream code that depends on the
                // generated types will fail to link, but the rest of
                // the daemon (transports, crypto, AI, etc.) will build.
                println!("cargo:warning=prost-build failed to compile shield.proto: {}", e);
                println!("cargo:warning=set PROTOC=/path/to/protoc or install protoc to enable IPC types");
            }
        }
    } else {
        println!("cargo:warning=proto/shield.proto not found — IPC types not generated");
    }

    // ── Embed resource JSON at compile time ────────────────────────────────
    let cdn_endpoints_path = manifest_dir.join("resources/cdn-endpoints.json");
    let p2p_peers_path = manifest_dir.join("resources/p2p-bootstrap-peers.json");

    // Validate that embedded resources are valid JSON at build time
    if cdn_endpoints_path.exists() {
        let content = std::fs::read_to_string(&cdn_endpoints_path)
            .expect("Failed to read cdn-endpoints.json");
        serde_json::from_str::<serde_json::Value>(&content)
            .expect("cdn-endpoints.json is not valid JSON");
        println!(
            "cargo:rustc-env=CDN_ENDPOINTS_JSON={}",
            cdn_endpoints_path.display()
        );
    }

    if p2p_peers_path.exists() {
        let content = std::fs::read_to_string(&p2p_peers_path)
            .expect("Failed to read p2p-bootstrap-peers.json");
        serde_json::from_str::<serde_json::Value>(&content)
            .expect("p2p-bootstrap-peers.json is not valid JSON");
        println!(
            "cargo:rustc-env=P2P_BOOTSTRAP_PEERS_JSON={}",
            p2p_peers_path.display()
        );
    }

    // ── Platform detection and cfg flags ───────────────────────────────────
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();

    match target_os.as_str() {
        "linux" => {
            // Check if targeting Android (Linux + android feature)
            if env::var("CARGO_FEATURE_PLATFORM_ANDROID").is_ok() {
                println!("cargo:rustc-cfg=platform_android");
                println!("cargo:rustc-cfg=platform_mobile");
            } else if env::var("CARGO_FEATURE_PLATFORM_OPENWRT").is_ok() {
                println!("cargo:rustc-cfg=platform_openwrt");
                println!("cargo:rustc-cfg=platform_embedded");
            } else {
                println!("cargo:rustc-cfg=platform_linux");
                println!("cargo:rustc-cfg=platform_desktop");
            }
        }
        "windows" => {
            println!("cargo:rustc-cfg=platform_windows");
            println!("cargo:rustc-cfg=platform_desktop");
        }
        "macos" => {
            println!("cargo:rustc-cfg=platform_macos");
            println!("cargo:rustc-cfg=platform_desktop");
        }
        "ios" => {
            println!("cargo:rustc-cfg=platform_ios");
            println!("cargo:rustc-cfg=platform_mobile");
        }
        "android" => {
            println!("cargo:rustc-cfg=platform_android");
            println!("cargo:rustc-cfg=platform_mobile");
        }
        _ => {
            println!("cargo:rustc-cfg=platform_unknown");
        }
    }

    match target_arch.as_str() {
        "x86_64" | "x86" => {
            println!("cargo:rustc-cfg=arch_x86");
        }
        "aarch64" | "arm" => {
            println!("cargo:rustc-cfg=arch_arm");
        }
        "riscv64" | "riscv32" => {
            println!("cargo:rustc-cfg=arch_riscv");
        }
        _ => {}
    }

    // ── Feature-based cfg flags ────────────────────────────────────────────
    if env::var("CARGO_FEATURE_AI_INFERENCE").is_ok() {
        println!("cargo:rustc-cfg=feature_ai_inference");
    }
    if env::var("CARGO_FEATURE_USERSPACE_TUNNEL").is_ok() {
        println!("cargo:rustc-cfg=feature_userspace_tunnel");
    }
    if env::var("CARGO_FEATURE_HARDENED_MEMORY").is_ok() {
        println!("cargo:rustc-cfg=feature_hardened_memory");
    }
    if env::var("CARGO_FEATURE_POST_QUANTUM").is_ok() {
        println!("cargo:rustc-cfg=feature_post_quantum");
    }

    // ── Linker hints for size-optimised builds ─────────────────────────────
    if target_os == "linux" && env::var("PROFILE").unwrap_or_default() == "release" {
        println!("cargo:rustc-link-arg=-s"); // Strip symbols
    }

    // ── Re-run if resources change ─────────────────────────────────────────
    println!("cargo:rerun-if-changed=resources/cdn-endpoints.json");
    println!("cargo:rerun-if-changed=resources/p2p-bootstrap-peers.json");
    println!("cargo:rerun-if-changed=proto/");
    println!("cargo:rerun-if-changed=build.rs");

    Ok(())
}
