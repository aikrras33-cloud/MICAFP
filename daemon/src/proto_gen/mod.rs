// ─────────────────────────────────────────────────────────────────────────────
// proto_gen — prost-build generated code from proto/shield.proto.
//
// This is a marker module: daemon/build.rs invokes
// `prost_build::Config::new().out_dir("src/proto_gen").compile_protos(...)`
// which writes the generated `.rs` files into this directory at build
// time. Each `.proto` file produces a corresponding file named after the
// proto package path — for `shield.proto` (package `unifiedshield.v1`),
// the file is `unifiedshield.v1.rs` and is `include!`d here.
//
// When `protoc` (the C binutils prost-build shells out to) is not
// available, daemon/build.rs catches the failure and emits a
// `cargo:rustc-cfg` flag `has_proto_gen` only on success. This file is
// `include!`d conditionally on that flag so the daemon stays buildable
// in environments without protoc (e.g. CI sandboxes).
//
// Per directive GEMINI-ENG-DIR-V1.0 §3.23 (GEMINI-STEP-2).
// ─────────────────────────────────────────────────────────────────────────────

// When prost-build succeeds, daemon/build.rs emits `cargo:rustc-cfg=has_proto_gen`.
// The generated file `unifiedshield.v1.rs` is written next to this `mod.rs`
// (in the same `src/proto_gen/` directory), so the include! path is bare.
#[cfg(has_proto_gen)]
include!("unifiedshield.v1.rs");

// When prost-build could not run (no protoc, no .proto file, etc.), the
// module is a no-op. This keeps the rest of the daemon buildable; the IPC
// layer simply has no generated types to call.
#[cfg(not(has_proto_gen))]
#[allow(dead_code)]
const _PROTO_GEN_STUB_MARKER: () = ();
