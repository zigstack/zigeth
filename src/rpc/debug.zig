const std = @import("std");
const RpcClient = @import("./client.zig").RpcClient;
const types = @import("./types.zig");
const Hash = @import("../primitives/hash.zig").Hash;
const Address = @import("../primitives/address.zig").Address;
const u256FromHex = @import("../primitives/uint.zig").u256FromHex;

/// Debug namespace (debug_*) methods
/// These methods are typically only available on development nodes
pub const DebugNamespace = struct {
    client: *RpcClient,

    pub fn init(client: *RpcClient) DebugNamespace {
        return .{ .client = client };
    }

    /// debug_traceTransaction - Returns the trace of a transaction
    pub fn traceTransaction(self: DebugNamespace, hash: Hash, options: ?TraceOptions) !TraceResult {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params: [2]std.json.Value = undefined;
        params[0] = .{ .string = hash_hex };

        if (options) |opts| {
            const opts_obj = try traceOptionsToJson(self.client.allocator, opts);
            defer opts_obj.deinit();
            params[1] = opts_obj.value;

            const result = try self.client.callWithParams("debug_traceTransaction", params[0..2]);
            return try parseTraceResult(self.client.allocator, result);
        } else {
            const result = try self.client.callWithParams("debug_traceTransaction", params[0..1]);
            return try parseTraceResult(self.client.allocator, result);
        }
    }

    /// debug_traceBlockByNumber - Returns the trace of all transactions in a block
    pub fn traceBlockByNumber(self: DebugNamespace, block: types.BlockParameter, options: ?TraceOptions) ![]TraceResult {
        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params: [2]std.json.Value = undefined;
        params[0] = .{ .string = block_param };

        if (options) |opts| {
            const opts_obj = try traceOptionsToJson(self.client.allocator, opts);
            defer opts_obj.deinit();
            params[1] = opts_obj.value;

            const result = try self.client.callWithParams("debug_traceBlockByNumber", params[0..2]);
            return try parseTraceResults(self.client.allocator, result);
        } else {
            const result = try self.client.callWithParams("debug_traceBlockByNumber", params[0..1]);
            return try parseTraceResults(self.client.allocator, result);
        }
    }

    /// debug_traceBlockByHash - Returns the trace of all transactions in a block
    pub fn traceBlockByHash(self: DebugNamespace, hash: Hash, options: ?TraceOptions) ![]TraceResult {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params: [2]std.json.Value = undefined;
        params[0] = .{ .string = hash_hex };

        if (options) |opts| {
            const opts_obj = try traceOptionsToJson(self.client.allocator, opts);
            defer opts_obj.deinit();
            params[1] = opts_obj.value;

            const result = try self.client.callWithParams("debug_traceBlockByHash", params[0..2]);
            return try parseTraceResults(self.client.allocator, result);
        } else {
            const result = try self.client.callWithParams("debug_traceBlockByHash", params[0..1]);
            return try parseTraceResults(self.client.allocator, result);
        }
    }

    /// debug_traceCall - Executes and returns trace of a call
    pub fn traceCall(
        self: DebugNamespace,
        call_params: types.CallParams,
        block: types.BlockParameter,
        options: ?TraceOptions,
    ) !TraceResult {
        const call_obj = try callParamsToJson(self.client.allocator, call_params);
        defer call_obj.deinit();

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params: [3]std.json.Value = undefined;
        params[0] = call_obj.value;
        params[1] = .{ .string = block_param };

        if (options) |opts| {
            const opts_obj = try traceOptionsToJson(self.client.allocator, opts);
            defer opts_obj.deinit();
            params[2] = opts_obj.value;

            const result = try self.client.callWithParams("debug_traceCall", params[0..3]);
            return try parseTraceResult(self.client.allocator, result);
        } else {
            const result = try self.client.callWithParams("debug_traceCall", params[0..2]);
            return try parseTraceResult(self.client.allocator, result);
        }
    }

    /// debug_storageRangeAt - Returns storage range
    pub fn storageRangeAt(
        self: DebugNamespace,
        block_hash: Hash,
        tx_index: u64,
        address: Address,
        start_key: Hash,
        limit: u64,
    ) !StorageRange {
        const block_hash_hex = try block_hash.toHex(self.client.allocator);
        defer self.client.allocator.free(block_hash_hex);

        const tx_index_hex = try std.fmt.allocPrint(self.client.allocator, "0x{x}", .{tx_index});
        defer self.client.allocator.free(tx_index_hex);

        const address_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(address_hex);

        const start_key_hex = try start_key.toHex(self.client.allocator);
        defer self.client.allocator.free(start_key_hex);

        var params = [_]std.json.Value{
            .{ .string = block_hash_hex },
            .{ .integer = @intCast(tx_index) },
            .{ .string = address_hex },
            .{ .string = start_key_hex },
            .{ .integer = @intCast(limit) },
        };

        const result = try self.client.callWithParams("debug_storageRangeAt", &params);

        if (result != .object) {
            return error.InvalidResponse;
        }

        return try parseStorageRange(self.client.allocator, result.object);
    }

    /// debug_getModifiedAccountsByNumber - Returns accounts modified in a block
    pub fn getModifiedAccountsByNumber(
        self: DebugNamespace,
        start_block: u64,
        end_block: u64,
    ) ![]Address {
        const start_hex = try std.fmt.allocPrint(self.client.allocator, "0x{x}", .{start_block});
        defer self.client.allocator.free(start_hex);

        const end_hex = try std.fmt.allocPrint(self.client.allocator, "0x{x}", .{end_block});
        defer self.client.allocator.free(end_hex);

        var params = [_]std.json.Value{
            .{ .string = start_hex },
            .{ .string = end_hex },
        };

        const result = try self.client.callWithParams("debug_getModifiedAccountsByNumber", &params);

        if (result != .array) {
            return error.InvalidResponse;
        }

        return try parseAddressArray(self.client.allocator, result.array);
    }

    /// debug_getModifiedAccountsByHash - Returns accounts modified in a block
    pub fn getModifiedAccountsByHash(
        self: DebugNamespace,
        start_hash: Hash,
        end_hash: Hash,
    ) ![]Address {
        const start_hex = try start_hash.toHex(self.client.allocator);
        defer self.client.allocator.free(start_hex);

        const end_hex = try end_hash.toHex(self.client.allocator);
        defer self.client.allocator.free(end_hex);

        var params = [_]std.json.Value{
            .{ .string = start_hex },
            .{ .string = end_hex },
        };

        const result = try self.client.callWithParams("debug_getModifiedAccountsByHash", &params);

        if (result != .array) {
            return error.InvalidResponse;
        }

        return try parseAddressArray(self.client.allocator, result.array);
    }
};

/// Trace options for debug calls
pub const TraceOptions = struct {
    disable_storage: ?bool = null,
    disable_stack: ?bool = null,
    enable_memory: ?bool = null,
    enable_return_data: ?bool = null,
    tracer: ?[]const u8 = null,
    timeout: ?[]const u8 = null,
};

/// Result of a trace operation
pub const TraceResult = struct {
    gas: u64,
    return_value: []const u8,
    struct_logs: []StructLog,
    allocator: std.mem.Allocator,

    pub fn deinit(self: TraceResult) void {
        self.allocator.free(self.return_value);
        for (self.struct_logs) |log| {
            log.deinit();
        }
        if (self.struct_logs.len > 0) {
            self.allocator.free(self.struct_logs);
        }
    }
};

/// Individual step in execution trace
pub const StructLog = struct {
    pc: u64,
    op: []const u8,
    gas: u64,
    gas_cost: u64,
    depth: u64,
    stack: ?[]u256 = null,
    memory: ?[]const u8 = null,
    storage: ?std.StringHashMap(Hash) = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: StructLog) void {
        if (self.stack) |stack| {
            self.allocator.free(stack);
        }
        if (self.memory) |memory| {
            self.allocator.free(memory);
        }
        if (self.storage) |*storage| {
            var it = storage.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            storage.deinit();
        }
    }
};

/// Storage range result
pub const StorageRange = struct {
    storage: std.StringHashMap(StorageEntry),
    next_key: ?Hash,
    allocator: std.mem.Allocator,

    pub const StorageEntry = struct {
        key: Hash,
        value: Hash,
    };

    pub fn deinit(self: *StorageRange) void {
        var it = self.storage.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.storage.deinit();
    }
};

/// Helper functions
/// JSON object wrapper for automatic cleanup
const JsonObjectWrapper = struct {
    value: std.json.Value,
    allocator: std.mem.Allocator,

    fn deinit(self: *JsonObjectWrapper) void {
        if (self.value == .object) {
            self.value.object.deinit(self.allocator);
        }
    }
};

/// Convert BlockParameter to string
fn blockParameterToString(allocator: std.mem.Allocator, block: types.BlockParameter) ![]u8 {
    return switch (block) {
        .latest => try allocator.dupe(u8, "latest"),
        .earliest => try allocator.dupe(u8, "earliest"),
        .pending => try allocator.dupe(u8, "pending"),
        .safe => try allocator.dupe(u8, "safe"),
        .finalized => try allocator.dupe(u8, "finalized"),
        .number => |num| try std.fmt.allocPrint(allocator, "0x{x}", .{num}),
    };
}

/// Convert CallParams to JSON object
fn callParamsToJson(allocator: std.mem.Allocator, params: types.CallParams) !JsonObjectWrapper {
    var obj = std.json.ObjectMap.empty;

    if (params.to) |to| {
        const to_hex = try to.toHex(allocator);
        try obj.put(allocator, "to", .{ .string = to_hex });
    }

    if (params.from) |from| {
        const from_hex = try from.toHex(allocator);
        try obj.put(allocator, "from", .{ .string = from_hex });
    }

    if (params.data) |data| {
        const hex_module = @import("../utils/hex.zig");
        const data_hex = try hex_module.bytesToHex(allocator, data);
        try obj.put(allocator, "data", .{ .string = data_hex });
    }

    if (params.value) |value| {
        const value_hex = try value.toHex(allocator);
        try obj.put(allocator, "value", .{ .string = value_hex });
    }

    if (params.gas) |gas| {
        const gas_hex = try std.fmt.allocPrint(allocator, "0x{x}", .{gas});
        try obj.put(allocator, "gas", .{ .string = gas_hex });
    }

    return JsonObjectWrapper{
        .value = .{ .object = obj },
        .allocator = allocator,
    };
}

/// Convert TraceOptions to JSON object
fn traceOptionsToJson(allocator: std.mem.Allocator, options: TraceOptions) !JsonObjectWrapper {
    var obj = std.json.ObjectMap.empty;

    if (options.disable_storage) |val| {
        try obj.put(allocator, "disableStorage", .{ .bool = val });
    }

    if (options.disable_stack) |val| {
        try obj.put(allocator, "disableStack", .{ .bool = val });
    }

    if (options.enable_memory) |val| {
        try obj.put(allocator, "enableMemory", .{ .bool = val });
    }

    if (options.enable_return_data) |val| {
        try obj.put(allocator, "enableReturnData", .{ .bool = val });
    }

    if (options.tracer) |tracer| {
        try obj.put(allocator, "tracer", .{ .string = tracer });
    }

    if (options.timeout) |timeout| {
        try obj.put(allocator, "timeout", .{ .string = timeout });
    }

    return JsonObjectWrapper{
        .value = .{ .object = obj },
        .allocator = allocator,
    };
}

/// Parse hex string to u64
fn parseHexU64(hex_str: []const u8) !u64 {
    const str = if (std.mem.startsWith(u8, hex_str, "0x")) hex_str[2..] else hex_str;
    return try std.fmt.parseInt(u64, str, 16);
}

/// Parse TraceResult from JSON
fn parseTraceResult(allocator: std.mem.Allocator, json: std.json.Value) !TraceResult {
    if (json != .object) {
        return error.InvalidResponse;
    }

    const obj = json.object;

    // Parse gas
    const gas_val = obj.get("gas") orelse return error.MissingField;
    const gas = if (gas_val == .integer)
        @as(u64, @intCast(gas_val.integer))
    else if (gas_val == .string)
        try parseHexU64(gas_val.string)
    else
        return error.InvalidFieldType;

    // Parse return value
    const return_val = obj.get("returnValue") orelse obj.get("return");
    var return_value: []const u8 = &[_]u8{};
    if (return_val) |rv| {
        if (rv == .string) {
            const hex_module = @import("../utils/hex.zig");
            return_value = try hex_module.hexToBytes(allocator, rv.string);
        }
    }

    // Parse struct logs
    var struct_logs = try std.ArrayList(StructLog).initCapacity(allocator, 0);
    defer struct_logs.deinit();

    if (obj.get("structLogs")) |logs_val| {
        if (logs_val == .array) {
            for (logs_val.array.items) |log_val| {
                if (log_val == .object) {
                    const struct_log = try parseStructLog(allocator, log_val.object);
                    try struct_logs.append(struct_log);
                }
            }
        }
    }

    return TraceResult{
        .gas = gas,
        .return_value = return_value,
        .struct_logs = try struct_logs.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Parse array of TraceResults
fn parseTraceResults(allocator: std.mem.Allocator, json: std.json.Value) ![]TraceResult {
    if (json != .array) {
        return error.InvalidResponse;
    }

    var results = try std.ArrayList(TraceResult).initCapacity(allocator, 0);
    defer results.deinit(allocator);

    for (json.array.items) |item| {
        const trace = try parseTraceResult(allocator, item);
        try results.append(allocator, trace);
    }

    return try results.toOwnedSlice(allocator);
}

/// Parse StructLog from JSON
fn parseStructLog(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !StructLog {
    const pc_val = obj.get("pc") orelse return error.MissingField;
    const pc = if (pc_val == .integer)
        @as(u64, @intCast(pc_val.integer))
    else
        return error.InvalidFieldType;

    const op_val = obj.get("op") orelse return error.MissingField;
    const op = if (op_val == .string)
        op_val.string
    else
        return error.InvalidFieldType;

    const gas_val = obj.get("gas") orelse return error.MissingField;
    const gas = if (gas_val == .integer)
        @as(u64, @intCast(gas_val.integer))
    else
        return error.InvalidFieldType;

    const gas_cost_val = obj.get("gasCost") orelse return error.MissingField;
    const gas_cost = if (gas_cost_val == .integer)
        @as(u64, @intCast(gas_cost_val.integer))
    else
        return error.InvalidFieldType;

    const depth_val = obj.get("depth") orelse return error.MissingField;
    const depth = if (depth_val == .integer)
        @as(u64, @intCast(depth_val.integer))
    else
        return error.InvalidFieldType;

    // Optional fields
    var stack: ?[]u256 = null;
    if (obj.get("stack")) |stack_val| {
        if (stack_val == .array) {
            var stack_items = try std.ArrayList(u256).initCapacity(allocator, 0);
            defer stack_items.deinit(allocator);

            for (stack_val.array.items) |item| {
                if (item == .string) {
                    const value = try u256FromHex(item.string);
                    try stack_items.append(allocator, value);
                }
            }

            stack = try stack_items.toOwnedSlice(allocator);
        }
    }

    var memory: ?[]const u8 = null;
    if (obj.get("memory")) |mem_val| {
        if (mem_val == .array) {
            // Memory is returned as array of hex strings
            var mem_data = try std.ArrayList(u8).initCapacity(allocator, 0);
            defer mem_data.deinit(allocator);

            for (mem_val.array.items) |item| {
                if (item == .string) {
                    const hex_module = @import("../utils/hex.zig");
                    const bytes = try hex_module.hexToBytes(allocator, item.string);
                    defer allocator.free(bytes);
                    try mem_data.appendSlice(allocator, bytes);
                }
            }

            memory = try mem_data.toOwnedSlice(allocator);
        }
    }

    return StructLog{
        .pc = pc,
        .op = op,
        .gas = gas,
        .gas_cost = gas_cost,
        .depth = depth,
        .stack = stack,
        .memory = memory,
        .storage = null, // Storage parsing is complex, can be added if needed
        .allocator = allocator,
    };
}

/// Parse StorageRange from JSON
fn parseStorageRange(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !StorageRange {
    var storage = std.StringHashMap(StorageRange.StorageEntry).init(allocator);

    if (obj.get("storage")) |storage_val| {
        if (storage_val == .object) {
            var it = storage_val.object.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* == .object) {
                    const key_val = entry.value_ptr.object.get("key");
                    const value_val = entry.value_ptr.object.get("value");

                    if (key_val != null and value_val != null) {
                        if (key_val.? == .string and value_val.? == .string) {
                            const key = try Hash.fromHex(key_val.?.string);
                            const value = try Hash.fromHex(value_val.?.string);

                            const entry_key = try allocator.dupe(u8, entry.key_ptr.*);
                            try storage.put(entry_key, .{ .key = key, .value = value });
                        }
                    }
                }
            }
        }
    }

    var next_key: ?Hash = null;
    if (obj.get("nextKey")) |next_val| {
        if (next_val == .string) {
            next_key = try Hash.fromHex(next_val.string);
        }
    }

    return StorageRange{
        .storage = storage,
        .next_key = next_key,
        .allocator = allocator,
    };
}

/// Parse address array from JSON
fn parseAddressArray(allocator: std.mem.Allocator, array: std.json.Array) ![]Address {
    var addresses = try std.ArrayList(Address).initCapacity(allocator, 0);
    defer addresses.deinit(allocator);

    for (array.items) |item| {
        if (item != .string) {
            return error.InvalidFieldType;
        }
        const addr = try Address.fromHex(item.string);
        try addresses.append(allocator, addr);
    }

    return try addresses.toOwnedSlice(allocator);
}

test "debug namespace creation" {
    const allocator = std.testing.allocator;

    var client = try RpcClient.init(allocator, "http://localhost:8545");
    defer client.deinit();

    const debug = DebugNamespace.init(&client);
    try std.testing.expect(debug.client.endpoint.len > 0);
}

test "trace options default" {
    const options = TraceOptions{};
    try std.testing.expect(options.disable_storage == null);
    try std.testing.expect(options.disable_stack == null);
}

test "trace options to json" {
    const allocator = std.testing.allocator;

    const options = TraceOptions{
        .disable_storage = true,
        .enable_memory = true,
        .timeout = "5s",
    };

    var json_obj = try traceOptionsToJson(allocator, options);
    defer json_obj.deinit();

    try std.testing.expect(json_obj.value == .object);
    try std.testing.expect(json_obj.value.object.contains("disableStorage"));
    try std.testing.expect(json_obj.value.object.contains("enableMemory"));
}

test "parse hex u64" {
    const value1 = try parseHexU64("0x10");
    try std.testing.expectEqual(@as(u64, 16), value1);

    const value2 = try parseHexU64("ff");
    try std.testing.expectEqual(@as(u64, 255), value2);
}
