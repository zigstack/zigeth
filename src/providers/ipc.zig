const std = @import("std");
const builtin = @import("builtin");
const Provider = @import("./provider.zig").Provider;

// Zig 0.16 moved networking behind std.Io; the previous std.net.Stream
// API is gone. Until this provider is ported to the Io-based sockets,
// we keep a placeholder handle so downstream code keeps compiling.
pub const Stream = struct {
    // No usable state; connect() below always fails NotImplemented.
    pub fn close(_: Stream) void {}
    pub fn write(_: Stream, _: []const u8) !usize {
        return error.NotImplemented;
    }
    pub fn read(_: Stream, _: []u8) !usize {
        return error.NotImplemented;
    }
};

/// IPC provider for local Ethereum nodes (Unix socket communication)
pub const IpcProvider = struct {
    provider: Provider,
    socket_path: []const u8,
    allocator: std.mem.Allocator,
    stream: ?Stream,
    connected: bool,

    /// Create a new IPC provider
    pub fn init(allocator: std.mem.Allocator, socket_path: []const u8) !IpcProvider {
        // For IPC, we use a dummy HTTP endpoint since actual communication
        // would happen through Unix sockets
        const provider = try Provider.init(allocator, "ipc://local");
        const path_copy = try allocator.dupe(u8, socket_path);

        return .{
            .provider = provider,
            .socket_path = path_copy,
            .allocator = allocator,
            .stream = null,
            .connected = false,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *IpcProvider) void {
        if (self.connected) {
            self.disconnect();
        }
        self.allocator.free(self.socket_path);
        self.provider.deinit();
    }

    /// Get the underlying provider
    pub fn getProvider(self: *IpcProvider) *Provider {
        return @constCast(&self.provider);
    }

    /// Connect to IPC socket
    pub fn connect(self: *IpcProvider) !void {
        if (self.connected) {
            return error.AlreadyConnected;
        }

        // Check OS support for Unix sockets
        if (builtin.os.tag == .windows) {
            // Windows uses named pipes, not Unix sockets
            return error.WindowsNamedPipesNotSupported;
        }

        // std.net was removed in Zig 0.16; connectUnixSocket is not yet
        // ported. Surface as NotImplemented until the Io-based sockets land.
        return error.NotImplemented;
    }

    /// Disconnect from IPC socket
    pub fn disconnect(self: *IpcProvider) void {
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        self.connected = false;
    }

    /// Check if connected
    pub fn isConnected(self: IpcProvider) bool {
        return self.connected and self.stream != null;
    }

    /// Get socket path
    pub fn getSocketPath(self: IpcProvider) []const u8 {
        return self.socket_path;
    }

    /// Send JSON-RPC request over IPC
    pub fn sendRequest(self: *IpcProvider, request: []const u8) ![]u8 {
        if (!self.connected or self.stream == null) {
            return error.NotConnected;
        }

        const stream = self.stream.?;

        // Write request to socket
        _ = try stream.write(request);

        // Read response from socket
        var response_buf = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer response_buf.deinit(self.allocator);

        var read_buf: [4096]u8 = undefined;
        while (true) {
            const bytes_read = try stream.read(&read_buf);
            if (bytes_read == 0) break;

            try response_buf.appendSlice(self.allocator, read_buf[0..bytes_read]);

            // Check if we have a complete JSON response
            // (basic check for matching braces)
            const response = response_buf.items;
            if (response.len > 0 and response[response.len - 1] == '}') {
                var open_braces: i32 = 0;
                for (response) |char| {
                    if (char == '{') open_braces += 1;
                    if (char == '}') open_braces -= 1;
                }
                if (open_braces == 0) break;
            }
        }

        return response_buf.toOwnedSlice(self.allocator);
    }

    /// Get stream for direct access
    pub fn getStream(self: *IpcProvider) ?Stream {
        return self.stream;
    }
};

/// Common IPC socket paths
pub const SocketPaths = struct {
    /// Default Geth IPC path (Unix)
    pub const GETH_UNIX = "/tmp/geth.ipc";

    /// Default Geth IPC path (macOS)
    pub const GETH_MACOS = "~/Library/Ethereum/geth.ipc";

    /// Default Geth IPC path (Windows)
    pub const GETH_WINDOWS = "\\\\.\\pipe\\geth.ipc";

    /// Get default path for current OS
    pub fn getDefault() []const u8 {
        return switch (builtin.os.tag) {
            .linux => GETH_UNIX,
            .macos => GETH_MACOS,
            .windows => GETH_WINDOWS,
            else => GETH_UNIX,
        };
    }
};

test "ipc provider creation" {
    const allocator = std.testing.allocator;

    var provider = try IpcProvider.init(allocator, "/tmp/geth.ipc");
    defer provider.deinit();

    try std.testing.expectEqualStrings("/tmp/geth.ipc", provider.getSocketPath());
}

test "ipc socket paths" {
    const default_path = SocketPaths.getDefault();
    try std.testing.expect(default_path.len > 0);

    // Check that it contains expected path components
    try std.testing.expect(
        std.mem.indexOf(u8, SocketPaths.GETH_UNIX, "geth.ipc") != null or
            std.mem.indexOf(u8, SocketPaths.GETH_UNIX, "tmp") != null,
    );
}

test "ipc provider get provider" {
    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "/tmp/geth.ipc");
    defer ipc_provider.deinit();

    const provider = ipc_provider.getProvider();
    try std.testing.expect(provider.rpc_client.endpoint.len > 0);
}

test "ipc provider connection state" {
    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "/tmp/test-geth.ipc");
    defer ipc_provider.deinit();

    // Initially not connected
    try std.testing.expect(!ipc_provider.isConnected());
    try std.testing.expect(ipc_provider.stream == null);

    // Note: We can't actually connect without a running node,
    // so we just verify the connection state logic
    try std.testing.expect(!ipc_provider.connected);
}

test "ipc provider disconnect when not connected" {
    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "/tmp/test-geth.ipc");
    defer ipc_provider.deinit();

    // Should be safe to call disconnect when not connected
    ipc_provider.disconnect();
    try std.testing.expect(!ipc_provider.isConnected());
}

test "ipc provider stream access" {
    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "/tmp/test-geth.ipc");
    defer ipc_provider.deinit();

    // Stream should be null initially
    try std.testing.expect(ipc_provider.getStream() == null);
}

test "ipc provider sendRequest when not connected" {
    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "/tmp/test-geth.ipc");
    defer ipc_provider.deinit();

    const request = "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}";

    // Should return error when not connected
    const result = ipc_provider.sendRequest(request);
    try std.testing.expectError(error.NotConnected, result);
}

test "ipc provider windows named pipes not supported" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var ipc_provider = try IpcProvider.init(allocator, "\\\\.\\pipe\\geth.ipc");
    defer ipc_provider.deinit();

    // Windows named pipes should return error
    const result = ipc_provider.connect();
    try std.testing.expectError(error.WindowsNamedPipesNotSupported, result);
}
