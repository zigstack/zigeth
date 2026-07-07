//! Cross-platform wall-clock + sleep helpers.
//!
//! Zig 0.16 removed `std.time.timestamp` / `std.time.sleep` (they moved
//! behind `std.Io`). Rather than thread an `Io` handle through every call
//! site that only needs a coarse timestamp or a backoff sleep, this module
//! reaches the OS directly:
//!
//!   * POSIX (Linux, macOS, *BSD) — `clock_gettime(REALTIME)` + `nanosleep`
//!     via libc (the library already links libc).
//!   * Windows — `GetSystemTimeAsFileTime` + `Sleep` via self-declared
//!     kernel32 externs (the 0.16 stdlib no longer re-exports them).

const std = @import("std");
const builtin = @import("builtin");

const is_windows = builtin.os.tag == .windows;

// kernel32 bindings — 0.16's std.os.windows.kernel32 no longer declares
// these, so bind them here. `.winapi` is the calling convention 0.16 uses
// for Win32 entry points.
extern "kernel32" fn GetSystemTimeAsFileTime(lpSystemTimeAsFileTime: *FileTime) callconv(.winapi) void;
extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;

const FileTime = extern struct {
    dwLowDateTime: u32,
    dwHighDateTime: u32,
};

// Number of seconds between the Windows FILETIME epoch (1601-01-01) and the
// Unix epoch (1970-01-01).
const filetime_to_unix_secs: u64 = 11_644_473_600;

/// Wall-clock seconds since the Unix epoch.
pub fn nowSeconds() i64 {
    if (is_windows) {
        var ft: FileTime = undefined;
        GetSystemTimeAsFileTime(&ft);
        // FILETIME counts 100-nanosecond intervals since 1601.
        const ticks = (@as(u64, ft.dwHighDateTime) << 32) | ft.dwLowDateTime;
        const unix_secs = ticks / 10_000_000 -% filetime_to_unix_secs;
        return @intCast(unix_secs);
    } else {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
        return @intCast(ts.sec);
    }
}

/// Sleep for `ms` milliseconds (best-effort; not guaranteed monotonic).
pub fn sleepMs(ms: u64) void {
    if (is_windows) {
        Sleep(@intCast(ms));
    } else {
        var req: std.c.timespec = .{
            .sec = @intCast(ms / 1000),
            .nsec = @intCast((ms % 1000) * std.time.ns_per_ms),
        };
        _ = std.c.nanosleep(&req, null);
    }
}

test "nowSeconds returns a plausible unix timestamp" {
    const now = nowSeconds();
    // Sometime after 2020-01-01 (1577836800) — sanity floor.
    try std.testing.expect(now > 1_577_836_800);
}
