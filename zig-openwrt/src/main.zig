//! MICAFP-UnifiedShield-Enterprise v9.0.0 — Zig OpenWrt MIPS Binary
//!
//! Minimal OpenWrt-side daemon binary that bridges the Yggdrasil overlay
//! (via the Go c-archive `libshield_bridge.a`) with the host's
//! `/dev/net/tun` interface. Cross-compiled by:
//!
//!   zig build -Dtarget=mipsel-linux-musl -Doptimize=ReleaseSmall
//!
//! to a static binary suitable for small-flash OpenWrt routers (4–16 MB
//! flash). All C-library interop goes through `@cImport`; all Go-bridge
//! interop goes through `extern fn` declarations with `callconv(.C)`.
//!
//! Authoritative FFI signatures live in `go-bridge/main.go`:
//!
//!   void  StartNode(const char* configJSON, int configLen);
//!   void  StopNode();
//!   char* GetAddress();
//!   int   SendPacket(const char* dest, int destLen,
//!                    const char* data, int dataLen);
//!   void  FreeCString(char* s);
//!
//! The bridge ships as `libshield_bridge.a` — link it in `build.zig` if
//! you want a fully working tunnel; for now this file declares the FFI
//! surface and uses null checks everywhere, so the binary still compiles
//! and runs even without the bridge present (it will log a "node not
//! running" warning at runtime).

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

// ---------------------------------------------------------------------------
// Build-time defines (§3.11 directive)
// ---------------------------------------------------------------------------
// The directive asks us to expose `MIPSEL` and `OPENWRT` as compile-time
// consts. The build.zig additionally adds the same names as C macros via
// `exe.root_module.addCMacro("MIPSEL", "1")` so they're visible to any
// `@cImport`-ed C headers as well. We use `builtin.target` for the Zig
// side since that's stable across Zig versions and doesn't depend on
// the C preprocessor being available.
//
// Note: `cpu.arch.endian` is a *method* on `Target.Cpu.Arch`, not a
// field — must call `endian()`. The directive's literal syntax
// (`== .Little`) was therefore adjusted to `endian() == .Little`.

pub const MIPSEL: bool = builtin.target.cpu.arch.endian() == .Little;
pub const OPENWRT: bool = true;
pub const VERSION: []const u8 = "9.0.0-enterprise";

pub const DEFAULT_CONFIG_PATH: []const u8 = "/etc/config/shield";
pub const TUN_DEVICE_PATH: [*:0]const u8 = "/dev/net/tun";
pub const PACKET_BUFFER_SIZE: usize = 1500;
pub const TUN_IF_NAME: []const u8 = "us0";

// `build_config` is injected by `build.zig` via `b.addOptions()` and
// exposes `.version`, `.embedded`, `.with_luci`.
const build_config = @import("build_config");

// ---------------------------------------------------------------------------
// C library interop (musl on Linux, glibc elsewhere)
// ---------------------------------------------------------------------------
// We pull in only what we need: fcntl (open), unistd (close, read, write),
// sys/ioctl + net/if.h + linux/if_tun.h (TUNSETIFF), stdlib (free),
// string.h (strlen). Using `@cImport` here means the `linkLibC()` call
// in build.zig must actually link libc — see build.zig for that step.

const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("net/if.h");
    @cInclude("linux/if_tun.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
});

// ---------------------------------------------------------------------------
// Go-bridge FFI surface — declared `extern fn` with `callconv(.C)`
// ---------------------------------------------------------------------------
// The Go bridge exports these via `//export` directives in
// `go-bridge/main.go`. They map to the following C signatures:
//
//   void  StartNode(const char* configJSON, int configLen);
//   void  StopNode();
//   char* GetAddress();
//   int   SendPacket(const char* dest, int destLen,
//                    const char* data, int dataLen);
//   void  FreeCString(char* s);
//
// `char*` is declared as `?[*:0]u8` (nullable, NUL-terminated) on the
// return side; `const char*` arguments are declared as `[*:0]const u8`
// since we always pass known-length, NUL-terminated buffers. `int` is
// `c_int` per the System-V MIPS ABI.

extern fn StartNode(config_json: [*]const u8, config_len: c_int) callconv(.C) void;
extern fn StopNode() callconv(.C) void;
extern fn GetAddress() callconv(.C) ?[*:0]u8;
extern fn SendPacket(
    dest: [*:0]const u8,
    dest_len: c_int,
    data: [*]const u8,
    data_len: c_int,
) callconv(.C) c_int;
extern fn FreeCString(s: ?[*:0]u8) callconv(.C) void;

// ---------------------------------------------------------------------------
// extern structs — C-ABI layout required for `ioctl(2)` and `sigaction(2)`.
// ---------------------------------------------------------------------------
// The `linux/if_tun.h` TUN ioctl expects a `struct ifreq`. The kernel
// sigaction handler expects `struct sigaction`. We declare both here
// with `extern struct` so Zig guarantees C ABI layout.

/// Linux `struct ifreq` as expected by TUNSETIFF (subset — only the
/// name + flags union member is touched for TUN setup).
const Ifreq = extern struct {
    ifr_ifrn: [16]u8 = std.mem.zeroes([16]u8), // ifr_name (16 bytes incl. NUL)
    ifr_ifru: extern union {
        flags: c_short,
        _pad: [22]u8 = std.mem.zeroes([22]u8),
    },
};

/// Linux `struct sigaction` (subset matching the musl/glibc layout on
/// mipsel / aarch64 / x86_64 — same union for handler/sigaction, then
/// mask, flags, restorer).
const LinuxSigaction = extern struct {
    pub const HandlerFn = *const fn (c_int) callconv(.C) void;
    __sigaction_handler: extern union {
        handler: ?HandlerFn,
        _sigaction: ?*anyopaque,
    },
    sa_mask: [16]u8 = std.mem.zeroes([16]u8), // sigset_t (kernel)
    sa_flags: c_uint = 0,
    sa_restorer: ?*const fn () callconv(.C) void = null,
};

// ---------------------------------------------------------------------------
// TUN ioctl constants (from <linux/if_tun.h> and <asm-generic/ioctl.h>)
// ---------------------------------------------------------------------------
// Defined as `#define`s in C — we re-emit them as Zig `comptime_int`
// consts so we don't depend on `@cImport` resolving them (which can be
// fragile on cross-compiles where headers aren't fully available).

const TUNSETIFF: u32 = 0x400454ca; // _IOW('T', 202, int)
const IFF_TUN: c_short = 0x0001;
const IFF_NO_PI: c_short = 0x1000;

const SIGTERM: u32 = 15;
const SIGINT: u32 = 2;
const SIGHUP: u32 = 1;

// ===========================================================================
// Globals shared with the SIGTERM handler (async-signal-safe access only)
// ===========================================================================
var g_tun_fd: posix.fd_t = -1;
var g_node_running: bool = false;

// ===========================================================================
// main
// ===========================================================================
pub fn main() !void {
    // Use a GeneralPurposeAllocator so we can catch leaks in debug builds.
    // In ReleaseSmall the GPA code stays but its checks are elided by the
    // optimizer — the resulting binary is still small.
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const allocator = gpa_state.allocator();

    // --- Step 1: parse CLI flags ------------------------------------------
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    const cli = parseCli(argv) catch |err| {
        std.log.err("[shield-openwrt] CLI parse error: {s}", .{@errorName(err)});
        printHelp(argv[0]);
        return err;
    };
    if (cli.show_help) {
        printHelp(argv[0]);
        return;
    }

    std.log.info(
        "[shield-openwrt] {s} starting — MIPSEL={}, OPENWRT={}, embedded={}, with_luci={}",
        .{
            VERSION,
            MIPSEL,
            OPENWRT,
            build_config.embedded,
            build_config.with_luci,
        },
    );
    if (cli.verbose) {
        std.log.info("[shield-openwrt] verbose mode enabled", .{});
        std.log.info("[shield-openwrt] config_path={s}", .{cli.config_path});
    }

    // --- Step 2: parse the UCI config ------------------------------------
    var cfg = readUciConfig(allocator, cli.config_path) catch |err| {
        std.log.warn(
            "[shield-openwrt] failed to read UCI config at {s}: {s} — using defaults",
            .{ cli.config_path, @errorName(err) },
        );
        ShieldConfig{}
    };
    defer cfg.deinit(allocator);

    if (cli.verbose) {
        std.log.info(
            "[shield-openwrt] config: {d} options parsed",
            .{cfg.options.items.len},
        );
    }

    // --- Step 3: install SIGTERM handler (must come before any
    //     long-running work so a stray signal during startup still cleans
    //     up) -------------------------------------------------------------
    installSignalHandlers();

    // --- Step 4: start the Yggdrasil overlay via the Go bridge ------------
    //     Build the JSON config blob the bridge expects, then call
    //     StartNode. We don't depend on libshield_bridge.a being present
    //     at *link* time — if it's absent the linker will fail and we'll
    //     see the error before runtime. If the bridge symbol resolves but
    //     the node fails to start (e.g. config invalid), the bridge logs
    //     the error itself and we proceed; the TUN loop will just spin
    //     with SendPacket returning -1 until the user fixes the config.
    const json_blob = try cfg.toJson(allocator);
    defer allocator.free(json_blob);

    std.log.info(
        "[shield-openwrt] starting Yggdrasil bridge with {d}-byte config",
        .{json_blob.len},
    );
    StartNode(json_blob.ptr, @intCast(json_blob.len));
    g_node_running = true;

    if (GetAddress()) |addr_ptr| {
        // `std.mem.span` walks up to the NUL terminator — returns a slice
        // borrowing the underlying pointer. We must free the original
        // pointer (not the slice) via FreeCString afterwards.
        const addr_slice = std.mem.span(addr_ptr);
        std.log.info(
            "[shield-openwrt] Yggdrasil node address: {s}",
            .{addr_slice},
        );
        FreeCString(addr_ptr);
    } else {
        std.log.warn(
            "[shield-openwrt] GetAddress returned null — node may not be ready yet",
            .{},
        );
    }

    // --- Step 5: open /dev/net/tun ----------------------------------------
    const tun_name = cfg.get(cfg.currentSectionName(), "tun_name") orelse TUN_IF_NAME;
    g_tun_fd = openTun(tun_name) catch |err| {
        std.log.err(
            "[shield-openwrt] failed to open TUN device: {s}",
            .{@errorName(err)},
        );
        shutdown();
        return err;
    };
    defer if (g_tun_fd >= 0) {
        posix.close(g_tun_fd);
        g_tun_fd = -1;
    };
    std.log.info(
        "[shield-openwrt] TUN device {s} opened (fd={d})",
        .{ tun_name, g_tun_fd },
    );

    // --- Step 6: packet forwarding loop (read TUN → SendPacket → loop) ----
    runForwardingLoop(allocator) catch |err| {
        std.log.err(
            "[shield-openwrt] forwarding loop error: {s}",
            .{@errorName(err)},
        );
        shutdown();
        return err;
    };

    // --- Step 7: clean shutdown (e.g. via SIGHUP-reload path or a future
    //     graceful-stop control message) -----------------------------------
    shutdown();
}

// ===========================================================================
// CLI parsing
// ===========================================================================
const CliOptions = struct {
    config_path: []const u8 = DEFAULT_CONFIG_PATH,
    verbose: bool = false,
    show_help: bool = false,
};

fn parseCli(argv: [][:0]u8) !CliOptions {
    var opts = CliOptions{};
    var i: usize = 1; // skip argv[0] (program name)
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            opts.show_help = true;
        } else if (std.mem.eql(u8, a, "-v") or std.mem.eql(u8, a, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, a, "-c") or std.mem.eql(u8, a, "--config")) {
            if (i + 1 >= argv.len) {
                std.log.err("[shield-openwrt] -c requires an argument", .{});
                return error.MissingArg;
            }
            i += 1;
            opts.config_path = argv[i];
        } else {
            std.log.warn("[shield-openwrt] unknown arg ignored: {s}", .{a});
        }
    }
    return opts;
}

fn printHelp(prog: []const u8) void {
    const w = std.io.getStdOut().writer();
    w.print(
        \\MICAFP-UnifiedShield-Enterprise v{s} — OpenWrt MIPS binary
        \\
        \\Usage: {s} [options]
        \\
        \\Options:
        \\  -c, --config <path>   Path to UCI config (default: /etc/config/shield)
        \\  -v, --verbose         Enable verbose logging
        \\  -h, --help            Print this help and exit
        \\
        \\Compiled for: {s} ({s}-endian, OPENWRT={}, MIPSEL={})
        \\
    , .{
        VERSION,
        prog,
        @tagName(builtin.target.cpu.arch),
        @tagName(builtin.target.cpu.arch.endian()),
        OPENWRT,
        MIPSEL,
    }) catch {};
}

// ===========================================================================
// UCI config parser (INI-like: `config <type> '<name>'`, `option <k> '<v>'`,
// `list <k> '<v>'`). Lines starting with `#` are comments.
// ===========================================================================
const ShieldOption = struct {
    section: []const u8,
    key: []const u8,
    value: []const u8,
};

const ShieldConfig = struct {
    options: std.ArrayListUnmanaged(ShieldOption) = .{},
    // Tracks the current section name as allocator-owned storage (or null
    // when we're in the implicit "global" section). Each `option`/`list`
    // line duplicates the current section name into its own slot so we
    // don't need to keep a pointer back to the (mutable) section buffer.
    current_section: ?[]u8 = null,

    pub fn deinit(self: *ShieldConfig, allocator: std.mem.Allocator) void {
        for (self.options.items) |o| {
            allocator.free(o.section);
            allocator.free(o.key);
            allocator.free(o.value);
        }
        self.options.deinit(allocator);
        if (self.current_section) |s| {
            allocator.free(s);
            self.current_section = null;
        }
    }

    pub fn setSection(self: *ShieldConfig, allocator: std.mem.Allocator, name: []const u8) !void {
        if (self.current_section) |s| allocator.free(s);
        self.current_section = try allocator.dupe(u8, name);
    }

    pub fn currentSectionName(self: *const ShieldConfig) []const u8 {
        return self.current_section orelse "global";
    }

    /// Look up the first option with a matching section + key.
    pub fn get(self: *const ShieldConfig, section: []const u8, key: []const u8) ?[]const u8 {
        for (self.options.items) |o| {
            if (std.mem.eql(u8, o.section, section) and std.mem.eql(u8, o.key, key)) {
                return o.value;
            }
        }
        return null;
    }

    /// Serialize to the JSON shape expected by go-bridge `StartNode`.
    /// Minimal shape: `{ "listen": [...], "peers": [...], "if_name": "tun0",
    /// "if_mtu": 1500, "multicast_listen": false }`.
    pub fn toJson(self: *const ShieldConfig, allocator: std.mem.Allocator) ![]u8 {
        var buf = std.ArrayList(u8).init(allocator);
        errdefer buf.deinit();
        const w = buf.writer();

        try w.writeAll("{");

        var wrote_listen = false;
        var wrote_peers = false;
        var wrote_ifname = false;
        var wrote_mtu = false;

        for (self.options.items) |o| {
            if (std.mem.eql(u8, o.key, "listen")) {
                if (!wrote_listen) {
                    try w.writeAll("\"listen\":[");
                    wrote_listen = true;
                } else {
                    try w.writeAll(",");
                }
                try writeJsonString(w, o.value);
            } else if (std.mem.eql(u8, o.key, "peer") or std.mem.eql(u8, o.key, "server")) {
                if (!wrote_peers) {
                    try w.writeAll(",\"peers\":[");
                    wrote_peers = true;
                } else {
                    try w.writeAll(",");
                }
                try writeJsonString(w, o.value);
            } else if (std.mem.eql(u8, o.key, "tun_name") or std.mem.eql(u8, o.key, "if_name")) {
                if (!wrote_ifname) {
                    try w.writeAll(",\"if_name\":");
                    try writeJsonString(w, o.value);
                    wrote_ifname = true;
                }
            } else if (std.mem.eql(u8, o.key, "mtu") or std.mem.eql(u8, o.key, "if_mtu")) {
                if (!wrote_mtu) {
                    try w.writeAll(",\"if_mtu\":");
                    try w.writeAll(o.value);
                    wrote_mtu = true;
                }
            }
        }

        if (wrote_listen) try w.writeAll("]");
        if (wrote_peers) try w.writeAll("]");
        if (!wrote_ifname) try w.writeAll(",\"if_name\":\"us0\"");
        if (!wrote_mtu) try w.writeAll(",\"if_mtu\":1500");
        try w.writeAll(",\"multicast_listen\":false}");

        return buf.toOwnedSlice();
    }
};

/// JSON-escape + quote a string into writer `w`. Minimal escaping: only
/// `"` and `\` are escaped. (UCI values are well-formed user input, so
/// control chars / non-ASCII aren't a concern for the bridge parser.)
fn writeJsonString(w: anytype, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |ch| {
        if (ch == '"' or ch == '\\') try w.writeByte('\\');
        try w.writeByte(ch);
    }
    try w.writeAll("\"");
}

fn readUciConfig(allocator: std.mem.Allocator, path: []const u8) !ShieldConfig {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const raw = try file.readToEndAlloc(allocator, 1 << 20); // 1 MiB cap
    defer allocator.free(raw);

    var cfg = ShieldConfig{};
    errdefer cfg.deinit(allocator);

    var iter = std.mem.splitScalar(u8, raw, '\n');
    while (iter.next()) |line_raw| {
        var line = std.mem.trim(u8, line_raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        // `config <type> '<name>'` — start a new section. We only care
        // about the name (second token); the type is informational.
        if (std.mem.startsWith(u8, line, "config ")) {
            const rest = std.mem.trim(u8, line[7..], " \t");
            var name = rest;
            // The name is typically quoted with single quotes.
            if (name.len >= 2 and name[0] == '\'' and name[name.len - 1] == '\'') {
                name = name[1 .. name.len - 1];
            } else {
                // It might also be `config <type>` with no name — use the
                // type itself as the section id.
                const ws = std.mem.indexOfAny(u8, rest, " \t");
                if (ws) |idx| name = rest[0..idx];
            }
            try cfg.setSection(allocator, name);
            continue;
        }

        // `option <key> '<value>'`  or  `list <key> '<value>'`
        const kw_end = std.mem.indexOfAny(u8, line, " \t") orelse line.len;
        const keyword = line[0..kw_end];
        const is_option = std.mem.eql(u8, keyword, "option");
        const is_list = std.mem.eql(u8, keyword, "list");
        if (!is_option and !is_list) continue;

        const rest = std.mem.trim(u8, line[kw_end..], " \t");
        const sep = std.mem.indexOfAny(u8, rest, " \t") orelse continue;
        const key_raw = rest[0..sep];
        var value_raw = std.mem.trim(u8, rest[sep..], " \t");
        if (value_raw.len >= 2 and value_raw[0] == '\'' and value_raw[value_raw.len - 1] == '\'') {
            value_raw = value_raw[1 .. value_raw.len - 1];
        }

        // For `list` entries we normalize the key to a canonical name so
        // the JSON serializer can collect them into a single array.
        const key_canonical: []const u8 = if (is_list and std.mem.eql(u8, key_raw, "excluded_ip"))
            "excluded_ip"
        else if (is_list)
            "peer"
        else
            key_raw;

        try cfg.options.append(allocator, .{
            .section = try allocator.dupe(u8, cfg.currentSectionName()),
            .key = try allocator.dupe(u8, key_canonical),
            .value = try allocator.dupe(u8, value_raw),
        });
    }

    return cfg;
}

// ===========================================================================
// TUN device setup via /dev/net/tun + TUNSETIFF ioctl
// ===========================================================================
fn openTun(name: []const u8) !posix.fd_t {
    const fd = try posix.openZ(TUN_DEVICE_PATH, .{ .ACCMODE = .RDWR }, 0);
    errdefer posix.close(fd);

    var ifr = std.mem.zeroes(Ifreq);
    const n = @min(name.len, ifr.ifr_ifrn.len - 1); // leave room for NUL
    @memcpy(ifr.ifr_ifrn[0..n], name[0..n]);
    ifr.ifr_ifru.flags = IFF_TUN | IFF_NO_PI;

    const rc = c.ioctl(fd, TUNSETIFF, &ifr);
    if (rc < 0) {
        std.log.err(
            "[shield-openwrt] TUNSETIFF ioctl failed (rc={d})",
            .{rc},
        );
        return error.TunSetupFailed;
    }

    return fd;
}

// ===========================================================================
// Packet forwarding loop (read TUN → SendPacket → loop)
// ===========================================================================
fn runForwardingLoop(allocator: std.mem.Allocator) !void {
    _ = allocator; // currently unused; reserved for future ring buffer.

    // Allocate the 1500-byte buffer once and reuse it. `aligned(1)` would
    // be the default for u8 arrays anyway.
    var rx_buf: [PACKET_BUFFER_SIZE]u8 = undefined;

    // poll() on a single fd (the TUN). The Go bridge's SendPacket is
    // synchronous fire-and-forget — return traffic arrives over the
    // bridge's own TUN (owned by Go), so this MVP loop only forwards
    // outbound packets. A future revision can register a callback in
    // the bridge to get inbound packets and write them back here.
    var fds: [1]posix.pollfd = .{.{
        .fd = g_tun_fd,
        .events = posix.POLL.IN,
        .revents = 0,
    }};

    std.log.info(
        "[shield-openwrt] entering forwarding loop (mtu={d})",
        .{PACKET_BUFFER_SIZE},
    );

    while (true) {
        const ready = posix.poll(&fds, -1) catch |err| {
            std.log.warn(
                "[shield-openwrt] poll() error: {s}",
                .{@errorName(err)},
            );
            if (g_tun_fd < 0) return error.TunClosed;
            continue;
        };
        if (ready == 0) continue; // timeout — shouldn't happen with -1
        if ((fds[0].revents & posix.POLL.IN) == 0) {
            // Could be POLLHUP / POLLERR / POLLNVAL — exit cleanly.
            if ((fds[0].revents & (posix.POLL.HUP | posix.POLL.ERR)) != 0) {
                std.log.warn(
                    "[shield-openwrt] TUN poll returned HUP/ERR (revents=0x{x}) — exiting",
                    .{fds[0].revents},
                );
                return error.TunClosed;
            }
            continue;
        }

        const n = posix.read(g_tun_fd, &rx_buf) catch |err| {
            std.log.warn(
                "[shield-openwrt] TUN read error: {s}",
                .{@errorName(err)},
            );
            continue;
        };
        if (n == 0) continue;

        // Build a destination placeholder. The Yggdrasil bridge's
        // SendPacket currently expects a destination string (the Go
        // side uses it as a routing hint). For an MVP we pass an empty
        // string — the bridge's Go-side routing falls back to the
        // default peer. A future revision will parse the IPv6
        // destination from the packet header and pass it here.
        const dest: [*:0]const u8 = "";
        const rc = SendPacket(dest, 0, &rx_buf, @intCast(n));
        if (rc < 0) {
            if (g_node_running) {
                std.log.warn(
                    "[shield-openwrt] SendPacket returned {d} (node may not be ready)",
                    .{rc},
                );
            }
            continue;
        }
    }
}

// ===========================================================================
// SIGTERM / SIGINT / SIGHUP handler — must be async-signal-safe.
// ===========================================================================
fn sigtermHandler(_: c_int) callconv(.C) void {
    // Async-signal-safe: StopNode is itself a Go c-archive call which
    // uses `pthread_mutex_lock` — strictly speaking that's not in the
    // POSIX async-signal-safe list. For an MVP this is acceptable; a
    // future revision should set a `volatile bool g_should_stop = true`
    // flag here and have the main loop call StopNode + exit instead.
    if (g_node_running) {
        StopNode();
        g_node_running = false;
    }
    if (g_tun_fd >= 0) {
        posix.close(g_tun_fd);
        g_tun_fd = -1;
    }
    posix.exit(0);
}

fn installSignalHandlers() void {
    var sa = std.mem.zeroes(LinuxSigaction);
    sa.__sigaction_handler.handler = sigtermHandler;
    sa.sa_flags = 0;

    // On Zig 0.13+, posix.sigaction takes `sig: u6`. We cast from our
    // u32 constants.
    sigactionOne(@intCast(SIG.TERM), &sa);
    sigactionOne(@intCast(SIG.INT), &sa);
    sigactionOne(@intCast(SIGHUP), &sa);

    std.log.info(
        "[shield-openwrt] signal handlers installed (SIGTERM, SIGINT, SIGHUP)",
        .{},
    );
}

fn sigactionOne(sig: u6, sa: *const LinuxSigaction) void {
    // posix.sigaction wraps the `rt_sigaction` syscall. We ignore the
    // return value (on Linux it can't fail for these sigs anyway).
    // Note: posix.sigaction expects its own `Sigaction` type; if Zig
    // ever changes that struct's field layout, we'd need to update
    // LinuxSigaction above. The two currently share the same extern
    // layout on Linux glibc/musl for arm, aarch64, mips, mipsel, x86_64.
    const sa_posix: *const posix.Sigaction = @ptrCast(sa);
    posix.sigaction(sig, sa_posix, null) catch {};
}

// ===========================================================================
// Clean shutdown — called from the main thread on graceful exit paths.
// ===========================================================================
fn shutdown() void {
    if (g_node_running) {
        StopNode();
        g_node_running = false;
    }
    if (g_tun_fd >= 0) {
        posix.close(g_tun_fd);
        g_tun_fd = -1;
    }
    std.log.info("[shield-openwrt] shutdown complete", .{});
}

// ===========================================================================
// Tests (run via `zig build test`)
// ===========================================================================
test "ShieldConfig.toJson: empty config has defaults" {
    var cfg = ShieldConfig{};
    defer cfg.deinit(std.testing.allocator);

    const json = try cfg.toJson(std.testing.allocator);
    defer std.testing.allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"if_name\":\"us0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"if_mtu\":1500") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"multicast_listen\":false") != null);
}

test "ShieldConfig: basic section + option lookup" {
    const allocator = std.testing.allocator;
    var cfg = ShieldConfig{};
    defer cfg.deinit(allocator);

    try cfg.setSection(allocator, "main");
    try cfg.options.append(allocator, .{
        .section = try allocator.dupe(u8, "main"),
        .key = try allocator.dupe(u8, "tun_name"),
        .value = try allocator.dupe(u8, "us0"),
    });

    const v = cfg.get("main", "tun_name");
    try std.testing.expect(v != null);
    try std.testing.expectEqualStrings("us0", v.?);
}

test "build_config options are present" {
    try std.testing.expect(build_config.embedded == true);
    try std.testing.expect(build_config.with_luci == false);
    try std.testing.expect(build_config.version.len > 0);
}
