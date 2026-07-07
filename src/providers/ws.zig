const std = @import("std");
const Provider = @import("./provider.zig").Provider;
const Hash = @import("../primitives/hash.zig").Hash;
const FilterOptions = @import("../rpc/types.zig").FilterOptions;

/// WebSocket provider for Ethereum (real-time subscriptions)
pub const WsProvider = struct {
    provider: Provider,
    ws_url: []const u8,
    subscriptions: std.StringHashMap(Subscription),
    allocator: std.mem.Allocator,
    client: ?*WsClient,
    connected: bool,
    next_request_id: u64,

    /// Create a new WebSocket provider
    pub fn init(allocator: std.mem.Allocator, url: []const u8) !WsProvider {
        const provider = try Provider.init(allocator, url);
        const ws_url = try allocator.dupe(u8, url);

        return .{
            .provider = provider,
            .ws_url = ws_url,
            .subscriptions = std.StringHashMap(Subscription).init(allocator),
            .allocator = allocator,
            .client = null,
            .connected = false,
            .next_request_id = 1,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *WsProvider) void {
        if (self.connected) {
            self.disconnect();
        }

        self.allocator.free(self.ws_url);

        var it = self.subscriptions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.subscriptions.deinit();

        self.provider.deinit();
    }

    /// Get the underlying provider
    pub fn getProvider(self: *WsProvider) *Provider {
        return &self.provider;
    }

    /// Connect to WebSocket endpoint
    pub fn connect(self: *WsProvider) !void {
        if (self.connected) {
            return error.AlreadyConnected;
        }

        // Parse URL to extract host and port
        const url_info = try parseWsUrl(self.ws_url);

        // Create WebSocket client
        const client = try self.allocator.create(WsClient);
        errdefer self.allocator.destroy(client);

        client.* = WsClient{
            .allocator = self.allocator,
            .host = url_info.host,
            .port = url_info.port,
            .path = url_info.path,
            .use_tls = url_info.use_tls,
            .stream = null,
        };

        // Connect to the server
        try client.connect();

        self.client = client;
        self.connected = true;
    }

    /// Disconnect from WebSocket
    pub fn disconnect(self: *WsProvider) void {
        if (self.client) |client| {
            client.disconnect();
            self.allocator.destroy(client);
            self.client = null;
        }
        self.connected = false;
    }

    /// Check if connected
    pub fn isConnected(self: WsProvider) bool {
        return self.connected and self.client != null;
    }

    /// Subscribe to new blocks
    pub fn subscribeNewHeads(self: *WsProvider) ![]const u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        const request_id = self.getNextRequestId();
        const request = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_subscribe\",\"params\":[\"newHeads\"]}}",
            .{request_id},
        );
        defer self.allocator.free(request);

        // Send subscription request
        const response = try self.sendRequest(request);
        defer self.allocator.free(response);

        // Parse subscription ID from response
        const sub_id = try self.parseSubscriptionId(response);

        // Store subscription
        try self.subscriptions.put(sub_id, .{ .type = .new_heads, .request_id = request_id });

        return sub_id;
    }

    /// Subscribe to pending transactions
    pub fn subscribePendingTransactions(self: *WsProvider) ![]const u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        const request_id = self.getNextRequestId();
        const request = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_subscribe\",\"params\":[\"newPendingTransactions\"]}}",
            .{request_id},
        );
        defer self.allocator.free(request);

        const response = try self.sendRequest(request);
        defer self.allocator.free(response);

        const sub_id = try self.parseSubscriptionId(response);
        try self.subscriptions.put(sub_id, .{ .type = .pending_transactions, .request_id = request_id });

        return sub_id;
    }

    /// Subscribe to logs with filter
    pub fn subscribeLogs(self: *WsProvider, filter: FilterOptions) ![]const u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        const request_id = self.getNextRequestId();

        // Build filter JSON
        var filter_json = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer filter_json.deinit(self.allocator);

        try filter_json.appendSlice(self.allocator, "{");
        if (filter.address) |addr| {
            try filter_json.appendSlice(self.allocator, "\"address\":\"");
            const addr_hex = try addr.toHex(self.allocator);
            defer self.allocator.free(addr_hex);
            try filter_json.appendSlice(self.allocator, addr_hex);
            try filter_json.appendSlice(self.allocator, "\",");
        }
        if (filter.topics) |_| {
            try filter_json.appendSlice(self.allocator, "\"topics\":[],");
        }
        // Remove trailing comma if present
        if (filter_json.items.len > 1 and filter_json.items[filter_json.items.len - 1] == ',') {
            _ = filter_json.pop();
        }
        try filter_json.appendSlice(self.allocator, "}");

        const request = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_subscribe\",\"params\":[\"logs\",{s}]}}",
            .{ request_id, filter_json.items },
        );
        defer self.allocator.free(request);

        const response = try self.sendRequest(request);
        defer self.allocator.free(response);

        const sub_id = try self.parseSubscriptionId(response);
        try self.subscriptions.put(sub_id, .{ .type = .logs, .request_id = request_id });

        return sub_id;
    }

    /// Subscribe to sync events
    pub fn subscribeSyncing(self: *WsProvider) ![]const u8 {
        if (!self.connected) {
            return error.NotConnected;
        }

        const request_id = self.getNextRequestId();
        const request = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_subscribe\",\"params\":[\"syncing\"]}}",
            .{request_id},
        );
        defer self.allocator.free(request);

        const response = try self.sendRequest(request);
        defer self.allocator.free(response);

        const sub_id = try self.parseSubscriptionId(response);
        try self.subscriptions.put(sub_id, .{ .type = .syncing, .request_id = request_id });

        return sub_id;
    }

    /// Unsubscribe from a subscription
    pub fn unsubscribe(self: *WsProvider, subscription_id: []const u8) !void {
        if (!self.connected) {
            return error.NotConnected;
        }

        const request_id = self.getNextRequestId();
        const request = try std.fmt.allocPrint(
            self.allocator,
            "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"eth_unsubscribe\",\"params\":[\"{s}\"]}}",
            .{ request_id, subscription_id },
        );
        defer self.allocator.free(request);

        const response = try self.sendRequest(request);
        defer self.allocator.free(response);

        // Remove from local subscriptions
        if (self.subscriptions.remove(subscription_id)) {
            self.allocator.free(subscription_id);
        }
    }

    /// Send request and receive response
    pub fn sendRequest(self: *WsProvider, request: []const u8) ![]u8 {
        if (!self.connected or self.client == null) {
            return error.NotConnected;
        }

        const client = self.client.?;
        return try client.sendMessage(request);
    }

    /// Receive next message (blocking)
    pub fn receiveMessage(self: *WsProvider) ![]u8 {
        if (!self.connected or self.client == null) {
            return error.NotConnected;
        }

        const client = self.client.?;
        return try client.receiveMessage();
    }

    /// Get next request ID
    fn getNextRequestId(self: *WsProvider) u64 {
        const id = self.next_request_id;
        self.next_request_id += 1;
        return id;
    }

    /// Parse subscription ID from JSON response
    fn parseSubscriptionId(self: *WsProvider, response: []const u8) ![]const u8 {
        // Simple JSON parsing to extract "result" field
        const result_start = std.mem.indexOf(u8, response, "\"result\":\"") orelse return error.InvalidResponse;
        const id_start = result_start + 10; // Length of "result":"
        const id_end = std.mem.indexOfPos(u8, response, id_start, "\"") orelse return error.InvalidResponse;

        const sub_id = response[id_start..id_end];
        return try self.allocator.dupe(u8, sub_id);
    }

    /// Get URL for debugging
    pub fn getUrl(self: WsProvider) []const u8 {
        return self.ws_url;
    }

    /// Get subscription count
    pub fn getSubscriptionCount(self: WsProvider) usize {
        return self.subscriptions.count();
    }
};

/// Subscription information
const Subscription = struct {
    type: SubscriptionType,
    request_id: u64,

    const SubscriptionType = enum {
        new_heads,
        pending_transactions,
        logs,
        syncing,
    };
};

/// WebSocket URL information
const WsUrlInfo = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    use_tls: bool,
};

/// Parse WebSocket URL
fn parseWsUrl(url: []const u8) !WsUrlInfo {
    var use_tls = false;
    var remaining = url;

    // Check protocol
    if (std.mem.startsWith(u8, url, "wss://")) {
        use_tls = true;
        remaining = url[6..];
    } else if (std.mem.startsWith(u8, url, "ws://")) {
        remaining = url[5..];
    } else {
        return error.InvalidWebSocketUrl;
    }

    // Find path separator
    const path_start = std.mem.indexOf(u8, remaining, "/") orelse remaining.len;
    const host_port = remaining[0..path_start];
    const path = if (path_start < remaining.len) remaining[path_start..] else "/";

    // Parse host and port
    var host: []const u8 = undefined;
    var port: u16 = if (use_tls) 443 else 80;

    if (std.mem.indexOf(u8, host_port, ":")) |colon_idx| {
        host = host_port[0..colon_idx];
        const port_str = host_port[colon_idx + 1 ..];
        port = try std.fmt.parseInt(u16, port_str, 10);
    } else {
        host = host_port;
    }

    return WsUrlInfo{
        .host = host,
        .port = port,
        .path = path,
        .use_tls = use_tls,
    };
}

// Zig 0.16 removed std.net; keep a stub Stream so the WebSocket client
// module still compiles. Actual TCP transport is a follow-up port.
const WsStream = struct {
    pub fn close(_: WsStream) void {}
    pub fn write(_: WsStream, _: []const u8) !usize {
        return error.NotImplemented;
    }
    pub fn read(_: WsStream, _: []u8) !usize {
        return error.NotImplemented;
    }
};

/// Simple WebSocket client (basic implementation)
const WsClient = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    path: []const u8,
    use_tls: bool,
    stream: ?WsStream,

    /// Connect to WebSocket server
    pub fn connect(self: *WsClient) !void {
        _ = self;
        // std.net was removed in Zig 0.16; the TCP+TLS transport hasn't
        // been ported to the new Io-based sockets yet.
        return error.NotImplemented;
    }

    /// Disconnect from WebSocket server
    pub fn disconnect(self: *WsClient) void {
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
    }

    /// Send WebSocket handshake
    fn sendHandshake(self: *WsClient) !void {
        const stream = self.stream orelse return error.NotConnected;

        // Generate WebSocket key (simplified)
        const key = "dGhlIHNhbXBsZSBub25jZQ=="; // Base64 encoded random bytes

        // Build handshake request
        const handshake = try std.fmt.allocPrint(
            self.allocator,
            "GET {s} HTTP/1.1\r\n" ++
                "Host: {s}:{d}\r\n" ++
                "Upgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Sec-WebSocket-Key: {s}\r\n" ++
                "Sec-WebSocket-Version: 13\r\n" ++
                "\r\n",
            .{ self.path, self.host, self.port, key },
        );
        defer self.allocator.free(handshake);

        _ = try stream.write(handshake);

        // Read handshake response
        var response_buf: [4096]u8 = undefined;
        const bytes_read = try stream.read(&response_buf);
        const response = response_buf[0..bytes_read];

        // Verify handshake response
        if (!std.mem.containsAtLeast(u8, response, 1, "101 Switching Protocols")) {
            return error.HandshakeFailed;
        }
    }

    /// Send WebSocket message
    pub fn sendMessage(self: *WsClient, message: []const u8) ![]u8 {
        const stream = self.stream orelse return error.NotConnected;

        // Build WebSocket frame (text frame, no masking for simplicity)
        var frame = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer frame.deinit(self.allocator);

        // Opcode: text frame (0x81)
        try frame.append(self.allocator, 0x81);

        // Payload length
        if (message.len < 126) {
            try frame.append(self.allocator, @intCast(message.len));
        } else if (message.len < 65536) {
            try frame.append(self.allocator, 126);
            try frame.append(self.allocator, @intCast(message.len >> 8));
            try frame.append(self.allocator, @intCast(message.len & 0xFF));
        } else {
            try frame.append(self.allocator, 127);
            var i: usize = 7;
            while (i >= 0) : (i -= 1) {
                try frame.append(self.allocator, @intCast((message.len >> @intCast(i * 8)) & 0xFF));
            }
        }

        // Payload
        try frame.appendSlice(self.allocator, message);

        // Send frame
        _ = try stream.write(frame.items);

        // Receive response
        return try self.receiveMessage();
    }

    /// Receive WebSocket message
    pub fn receiveMessage(self: *WsClient) ![]u8 {
        const stream = self.stream orelse return error.NotConnected;

        var response = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        errdefer response.deinit(self.allocator);

        // Read frame header
        var header: [2]u8 = undefined;
        _ = try stream.read(&header);

        const opcode = header[0] & 0x0F;
        if (opcode == 0x08) { // Close frame
            return error.ConnectionClosed;
        }

        // Parse payload length
        var payload_len: u64 = header[1] & 0x7F;
        if (payload_len == 126) {
            var len_bytes: [2]u8 = undefined;
            _ = try stream.read(&len_bytes);
            payload_len = (@as(u64, len_bytes[0]) << 8) | len_bytes[1];
        } else if (payload_len == 127) {
            var len_bytes: [8]u8 = undefined;
            _ = try stream.read(&len_bytes);
            payload_len = 0;
            for (len_bytes) |byte| {
                payload_len = (payload_len << 8) | byte;
            }
        }

        // Read payload
        try response.ensureTotalCapacity(self.allocator, @intCast(payload_len));
        var remaining = payload_len;
        while (remaining > 0) {
            var buf: [4096]u8 = undefined;
            const to_read = @min(remaining, buf.len);
            const bytes_read = try stream.read(buf[0..to_read]);
            if (bytes_read == 0) break;
            try response.appendSlice(self.allocator, buf[0..bytes_read]);
            remaining -= bytes_read;
        }

        return response.toOwnedSlice(self.allocator);
    }
};

// Tests
test "ws provider creation" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    try std.testing.expect(std.mem.indexOf(u8, provider.ws_url, "ws://") != null);
    try std.testing.expect(!provider.isConnected());
}

test "ws provider url parsing" {
    const url1 = try parseWsUrl("ws://localhost:8546/");
    try std.testing.expectEqualStrings("localhost", url1.host);
    try std.testing.expectEqual(@as(u16, 8546), url1.port);
    try std.testing.expectEqualStrings("/", url1.path);
    try std.testing.expect(!url1.use_tls);

    const url2 = try parseWsUrl("wss://example.com/rpc");
    try std.testing.expectEqualStrings("example.com", url2.host);
    try std.testing.expectEqual(@as(u16, 443), url2.port);
    try std.testing.expectEqualStrings("/rpc", url2.path);
    try std.testing.expect(url2.use_tls);
}

test "ws provider subscription count" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    try std.testing.expectEqual(@as(usize, 0), provider.getSubscriptionCount());
}

test "ws provider not connected operations" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    // Operations should fail when not connected
    const result1 = provider.subscribeNewHeads();
    try std.testing.expectError(error.NotConnected, result1);

    const result2 = provider.subscribePendingTransactions();
    try std.testing.expectError(error.NotConnected, result2);

    const result3 = provider.subscribeSyncing();
    try std.testing.expectError(error.NotConnected, result3);
}

test "ws provider get url" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    try std.testing.expectEqualStrings("ws://localhost:8546", provider.getUrl());
}

test "ws provider disconnect when not connected" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    // Should be safe to disconnect when not connected
    provider.disconnect();
    try std.testing.expect(!provider.isConnected());
}

test "ws provider request id generation" {
    const allocator = std.testing.allocator;

    var provider = try WsProvider.init(allocator, "ws://localhost:8546");
    defer provider.deinit();

    const id1 = provider.getNextRequestId();
    const id2 = provider.getNextRequestId();
    const id3 = provider.getNextRequestId();

    try std.testing.expectEqual(@as(u64, 1), id1);
    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(u64, 3), id3);
}
