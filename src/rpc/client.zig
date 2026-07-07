const std = @import("std");
const types = @import("./types.zig");

/// JSON-RPC client for Ethereum
pub const RpcClient = struct {
    allocator: std.mem.Allocator,
    endpoint: []const u8,
    next_id: u64,

    /// Create a new RPC client
    pub fn init(allocator: std.mem.Allocator, endpoint: []const u8) !RpcClient {
        const endpoint_copy = try allocator.dupe(u8, endpoint);
        return .{
            .allocator = allocator,
            .endpoint = endpoint_copy,
            .next_id = 1,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: RpcClient) void {
        self.allocator.free(self.endpoint);
    }

    /// Get next request ID
    fn getNextId(self: *RpcClient) u64 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    /// Make a JSON-RPC call
    pub fn call(
        self: *RpcClient,
        method: []const u8,
        params: std.json.Value,
    ) !std.json.Value {
        const id = self.getNextId();
        const request = try types.JsonRpcRequest.init(self.allocator, method, params, id);

        // Serialize request to JSON
        const request_str = try std.json.Stringify.valueAlloc(self.allocator, request, .{});
        defer self.allocator.free(request_str);

        // Make HTTP request
        var transport = try HttpTransport.init(self.allocator, self.endpoint);
        defer transport.deinit();

        try transport.addHeader("Content-Type", "application/json");

        const response_body = try transport.send(request_str);
        defer self.allocator.free(response_body);

        // Parse response
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            response_body,
            .{},
        );
        defer parsed.deinit();

        // Extract result or error
        if (parsed.value != .object) {
            return error.InvalidJsonRpcResponse;
        }

        const obj = parsed.value.object;

        // Check for error
        if (obj.get("error")) |err| {
            if (err != .null) {
                return error.JsonRpcError;
            }
        }

        // Get result
        const result = obj.get("result") orelse return error.MissingResult;

        // Return owned copy of the result
        return try copyJsonValue(self.allocator, result);
    }

    /// Make a JSON-RPC call with array parameters
    pub fn callWithParams(
        self: *RpcClient,
        method: []const u8,
        params: []const std.json.Value,
    ) !std.json.Value {
        const params_array = std.json.Value{ .array = std.json.Array.fromOwnedSlice(self.allocator, @constCast(params)) };
        return try self.call(method, params_array);
    }

    /// Make a JSON-RPC call with no parameters
    pub fn callNoParams(self: *RpcClient, method: []const u8) !std.json.Value {
        // Create empty array using fromOwnedSlice with empty slice
        const empty_slice: []std.json.Value = &[_]std.json.Value{};
        const params = std.json.Value{ .array = std.json.Array.fromOwnedSlice(self.allocator, @constCast(empty_slice)) };
        return try self.call(method, params);
    }
};

/// Errors surfaced by the HTTP transport.
pub const TransportError = error{
    /// The underlying std.http.Client.fetch call failed (DNS, TCP, TLS,
    /// timeout, etc.).
    HttpRequestFailed,
    /// The server responded with a non-2xx status.
    HttpStatusError,
} || std.mem.Allocator.Error;

/// HTTP(S) transport for the JSON-RPC client.
///
/// Built on `std.http.Client` (which performs TLS for `https://`
/// endpoints) driven by a `std.Io.Threaded` event loop. Each transport
/// owns its own client + loop; `RpcClient.call` currently constructs one
/// per request, so the connection is not pooled across calls — fine for a
/// low-frequency polling consumer. A future optimization is to hoist the
/// client into `RpcClient` and reuse it (keep-alive) across calls.
pub const HttpTransport = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    headers: std.StringHashMap([]const u8),
    threaded: *std.Io.Threaded,
    client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !HttpTransport {
        const url_copy = try allocator.dupe(u8, url);
        errdefer allocator.free(url_copy);

        const threaded = try allocator.create(std.Io.Threaded);
        errdefer allocator.destroy(threaded);
        threaded.* = std.Io.Threaded.init(allocator, .{});

        return .{
            .allocator = allocator,
            .url = url_copy,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .threaded = threaded,
            .client = .{ .allocator = allocator, .io = threaded.io() },
        };
    }

    pub fn deinit(self: *HttpTransport) void {
        self.client.deinit();
        self.threaded.deinit();
        self.allocator.destroy(self.threaded);
        self.allocator.free(self.url);

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }

    pub fn addHeader(self: *HttpTransport, key: []const u8, value: []const u8) !void {
        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.headers.put(key_copy, value_copy);
    }

    /// POST `request` to the endpoint and return the response body. Caller
    /// owns the returned slice.
    pub fn send(self: *HttpTransport, request: []const u8) ![]u8 {
        // Build the extra-headers slice from the configured headers.
        var extra = try self.allocator.alloc(std.http.Header, self.headers.count());
        defer self.allocator.free(extra);
        var it = self.headers.iterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) {
            extra[i] = .{ .name = entry.key_ptr.*, .value = entry.value_ptr.* };
        }

        var resp = std.Io.Writer.Allocating.init(self.allocator);
        defer resp.deinit();

        const result = self.client.fetch(.{
            .location = .{ .url = self.url },
            .method = .POST,
            .payload = request,
            .response_writer = &resp.writer,
            .extra_headers = extra,
        }) catch return error.HttpRequestFailed;

        // Accept any 2xx.
        const code = @intFromEnum(result.status);
        if (code < 200 or code >= 300) return error.HttpStatusError;

        return try self.allocator.dupe(u8, resp.written());
    }
};

/// Deep copy a JSON value
fn copyJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |b| .{ .bool = b },
        .integer => |i| .{ .integer = i },
        .float => |f| .{ .float = f },
        .number_string => |ns| .{ .number_string = try allocator.dupe(u8, ns) },
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .array => |arr| blk: {
            var new_array = std.json.Array.init(allocator);
            for (arr.items) |item| {
                const copied = try copyJsonValue(allocator, item);
                try new_array.append(copied);
            }
            break :blk .{ .array = new_array };
        },
        .object => |obj| blk: {
            var new_obj = std.json.ObjectMap.empty;
            var it = obj.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                const value_copy = try copyJsonValue(allocator, entry.value_ptr.*);
                try new_obj.put(allocator, key_copy, value_copy);
            }
            break :blk .{ .object = new_obj };
        },
    };
}

test "rpc client creation" {
    const allocator = std.testing.allocator;

    const client = try RpcClient.init(allocator, "http://localhost:8545");
    defer client.deinit();

    try std.testing.expectEqualStrings("http://localhost:8545", client.endpoint);
    try std.testing.expectEqual(@as(u64, 1), client.next_id);
}

test "rpc client id increment" {
    const allocator = std.testing.allocator;

    var client = try RpcClient.init(allocator, "http://localhost:8545");
    defer client.deinit();

    const id1 = client.getNextId();
    const id2 = client.getNextId();
    const id3 = client.getNextId();

    try std.testing.expectEqual(@as(u64, 1), id1);
    try std.testing.expectEqual(@as(u64, 2), id2);
    try std.testing.expectEqual(@as(u64, 3), id3);
}

test "http transport creation" {
    const allocator = std.testing.allocator;

    var transport = try HttpTransport.init(allocator, "http://localhost:8545");
    defer transport.deinit();

    try std.testing.expectEqualStrings("http://localhost:8545", transport.url);
}

test "http transport headers" {
    const allocator = std.testing.allocator;

    var transport = try HttpTransport.init(allocator, "http://localhost:8545");
    defer transport.deinit();

    try transport.addHeader("Content-Type", "application/json");
    try transport.addHeader("Authorization", "Bearer token123");

    try std.testing.expectEqual(@as(usize, 2), transport.headers.count());
}

test "copy json value string" {
    const allocator = std.testing.allocator;

    const original = std.json.Value{ .string = "hello" };
    const copied = try copyJsonValue(allocator, original);
    defer allocator.free(copied.string);

    try std.testing.expectEqualStrings("hello", copied.string);
}

test "copy json value integer" {
    const allocator = std.testing.allocator;

    const original = std.json.Value{ .integer = 42 };
    const copied = try copyJsonValue(allocator, original);

    try std.testing.expectEqual(@as(i64, 42), copied.integer);
}

test "copy json value bool" {
    const allocator = std.testing.allocator;

    const original = std.json.Value{ .bool = true };
    const copied = try copyJsonValue(allocator, original);

    try std.testing.expect(copied.bool);
}

test "copy json value null" {
    const allocator = std.testing.allocator;

    const original = std.json.Value{ .null = {} };
    const copied = try copyJsonValue(allocator, original);

    try std.testing.expect(copied == .null);
}

test "copy json value array" {
    const allocator = std.testing.allocator;

    var arr = std.json.Array.init(allocator);
    defer arr.deinit();

    try arr.append(.{ .integer = 1 });
    try arr.append(.{ .string = "test" });

    const original = std.json.Value{ .array = arr };
    const copied = try copyJsonValue(allocator, original);
    defer {
        allocator.free(copied.array.items[1].string);
        copied.array.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), copied.array.items.len);
    try std.testing.expectEqual(@as(i64, 1), copied.array.items[0].integer);
    try std.testing.expectEqualStrings("test", copied.array.items[1].string);
}
