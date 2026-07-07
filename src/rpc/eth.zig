const std = @import("std");
const RpcClient = @import("./client.zig").RpcClient;
const types = @import("./types.zig");
const Address = @import("../primitives/address.zig").Address;
const Hash = @import("../primitives/hash.zig").Hash;
const uint_utils = @import("../primitives/uint.zig");
const Bytes = @import("../primitives/bytes.zig").Bytes;
const Signature = @import("../primitives/signature.zig").Signature;
const Block = @import("../types/block.zig").Block;
const Transaction = @import("../types/transaction.zig").Transaction;
const Receipt = @import("../types/receipt.zig").Receipt;
const Log = @import("../types/log.zig").Log;

/// Ethereum namespace (eth_*) methods
pub const EthNamespace = struct {
    client: *RpcClient,

    pub fn init(client: *RpcClient) EthNamespace {
        return .{ .client = client };
    }

    /// eth_blockNumber - Returns the current block number
    pub fn blockNumber(self: EthNamespace) !u64 {
        const result = try self.client.callNoParams("eth_blockNumber");
        defer @import("./free_json.zig").freeJsonValue(self.client.allocator, result);

        // Parse hex string to u64
        if (result != .string) {
            return error.InvalidResponse;
        }

        const hex_str = result.string;
        return try parseHexU64(hex_str);
    }

    /// eth_getBalance - Returns the balance of an account
    pub fn getBalance(self: EthNamespace, address: Address, block: types.BlockParameter) !u256 {
        const addr_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(addr_hex);

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = addr_hex },
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getBalance", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try uint_utils.u256FromHex(result.string);
    }

    /// eth_getTransactionCount - Returns the number of transactions sent from an address
    pub fn getTransactionCount(self: EthNamespace, address: Address, block: types.BlockParameter) !u64 {
        const addr_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(addr_hex);

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = addr_hex },
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getTransactionCount", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_getBlockByNumber - Returns information about a block by number
    pub fn getBlockByNumber(self: EthNamespace, block: types.BlockParameter, full_tx: bool) !Block {
        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = block_param },
            .{ .bool = full_tx },
        };

        const result = try self.client.callWithParams("eth_getBlockByNumber", &params);

        if (result == .null) {
            return error.BlockNotFound;
        }

        if (result != .object) {
            return error.InvalidResponse;
        }

        return try parseBlockFromJson(self.client.allocator, result.object, full_tx);
    }

    /// eth_getBlockByHash - Returns information about a block by hash
    pub fn getBlockByHash(self: EthNamespace, hash: Hash, full_tx: bool) !Block {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params = [_]std.json.Value{
            .{ .string = hash_hex },
            .{ .bool = full_tx },
        };

        const result = try self.client.callWithParams("eth_getBlockByHash", &params);

        if (result == .null) {
            return error.BlockNotFound;
        }

        if (result != .object) {
            return error.InvalidResponse;
        }

        return try parseBlockFromJson(self.client.allocator, result.object, full_tx);
    }

    /// eth_getTransactionByHash - Returns a transaction by hash
    pub fn getTransactionByHash(self: EthNamespace, hash: Hash) !Transaction {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params = [_]std.json.Value{
            .{ .string = hash_hex },
        };

        const result = try self.client.callWithParams("eth_getTransactionByHash", &params);

        if (result == .null) {
            return error.TransactionNotFound;
        }

        if (result != .object) {
            return error.InvalidResponse;
        }

        return try parseTransactionFromJson(self.client.allocator, result.object);
    }

    /// eth_getTransactionReceipt - Returns the receipt of a transaction
    pub fn getTransactionReceipt(self: EthNamespace, hash: Hash) !Receipt {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params = [_]std.json.Value{
            .{ .string = hash_hex },
        };

        const result = try self.client.callWithParams("eth_getTransactionReceipt", &params);

        if (result == .null) {
            return error.ReceiptNotFound;
        }

        if (result != .object) {
            return error.InvalidResponse;
        }

        return try parseReceiptFromJson(self.client.allocator, result.object);
    }

    /// eth_call - Executes a message call (doesn't create a transaction)
    pub fn call(self: EthNamespace, params: types.CallParams, block: types.BlockParameter) ![]u8 {
        const call_obj = try callParamsToJson(self.client.allocator, params);
        defer call_obj.deinit();

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var rpc_params = [_]std.json.Value{
            call_obj.value,
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_call", &rpc_params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        // Parse hex result
        const hex_module = @import("../utils/hex.zig");
        return try hex_module.hexToBytes(self.client.allocator, result.string);
    }

    /// eth_estimateGas - Estimates gas needed for a transaction
    pub fn estimateGas(self: EthNamespace, params: types.CallParams) !u64 {
        const call_obj = try callParamsToJson(self.client.allocator, params);
        defer call_obj.deinit();

        var rpc_params = [_]std.json.Value{
            call_obj.value,
        };

        const result = try self.client.callWithParams("eth_estimateGas", &rpc_params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_gasPrice - Returns the current gas price in wei
    pub fn gasPrice(self: EthNamespace) !u256 {
        const result = try self.client.callNoParams("eth_gasPrice");

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try uint_utils.u256FromHex(result.string);
    }

    /// eth_maxPriorityFeePerGas - Returns the current max priority fee per gas
    pub fn maxPriorityFeePerGas(self: EthNamespace) !u256 {
        const result = try self.client.callNoParams("eth_maxPriorityFeePerGas");

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try uint_utils.u256FromHex(result.string);
    }

    /// eth_feeHistory - Returns historical gas information
    pub fn feeHistory(
        self: EthNamespace,
        block_count: u64,
        newest_block: types.BlockParameter,
        reward_percentiles: ?[]const f64,
    ) !types.FeeHistory {
        const block_count_hex = try std.fmt.allocPrint(self.client.allocator, "0x{x}", .{block_count});
        defer self.client.allocator.free(block_count_hex);

        const block_param = try blockParameterToString(self.client.allocator, newest_block);
        defer self.client.allocator.free(block_param);

        var percentiles_array = std.json.Array.init(self.client.allocator);
        defer percentiles_array.deinit();

        if (reward_percentiles) |percentiles| {
            for (percentiles) |p| {
                try percentiles_array.append(.{ .float = p });
            }
        }

        var params = [_]std.json.Value{
            .{ .string = block_count_hex },
            .{ .string = block_param },
            .{ .array = percentiles_array },
        };

        const result = try self.client.callWithParams("eth_feeHistory", &params);

        // TODO: Parse JSON fee history object
        _ = result;
        return error.NotImplemented;
    }

    /// eth_getCode - Returns code at a given address
    pub fn getCode(self: EthNamespace, address: Address, block: types.BlockParameter) ![]u8 {
        const addr_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(addr_hex);

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = addr_hex },
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getCode", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        // Parse hex bytecode
        const hex_module = @import("../utils/hex.zig");
        return try hex_module.hexToBytes(self.client.allocator, result.string);
    }

    /// eth_getStorageAt - Returns the value from a storage position
    pub fn getStorageAt(self: EthNamespace, address: Address, position: u256, block: types.BlockParameter) !Hash {
        const addr_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(addr_hex);

        const position_hex = try uint_utils.u256ToHex(position, self.client.allocator);
        defer self.client.allocator.free(position_hex);

        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = addr_hex },
            .{ .string = position_hex },
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getStorageAt", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try Hash.fromHex(result.string);
    }

    /// eth_getLogs - Returns an array of logs matching the filter
    pub fn getLogs(self: EthNamespace, filter: types.FilterOptions) ![]Log {
        const filter_obj = try filterOptionsToJson(self.client.allocator, filter);
        defer filter_obj.deinit();

        var params = [_]std.json.Value{
            filter_obj.value,
        };

        const result = try self.client.callWithParams("eth_getLogs", &params);

        // Parse JSON logs array
        if (result != .array) {
            return error.InvalidResponse;
        }

        var logs = try std.ArrayList(Log).initCapacity(self.client.allocator, 0);
        errdefer {
            for (logs.items) |log| {
                log.deinit();
            }
            logs.deinit();
        }

        for (result.array.items) |log_json| {
            if (log_json != .object) {
                return error.InvalidResponse;
            }

            const log = try parseLogFromJson(self.client.allocator, log_json.object);
            try logs.append(self.client.allocator, log);
        }

        return try logs.toOwnedSlice(self.client.allocator);
    }

    /// eth_sendRawTransaction - Sends a signed transaction
    pub fn sendRawTransaction(self: EthNamespace, signed_tx: []const u8) !Hash {
        const hex_module = @import("../utils/hex.zig");
        const tx_hex = try hex_module.bytesToHex(self.client.allocator, signed_tx);
        defer self.client.allocator.free(tx_hex);

        var params = [_]std.json.Value{
            .{ .string = tx_hex },
        };

        const result = try self.client.callWithParams("eth_sendRawTransaction", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try Hash.fromHex(result.string);
    }

    /// eth_sendTransaction - Creates and sends a transaction
    pub fn sendTransaction(self: EthNamespace, params: types.TransactionParams) !Hash {
        const tx_obj = try transactionParamsToJson(self.client.allocator, params);
        defer tx_obj.deinit();

        var rpc_params = [_]std.json.Value{
            tx_obj.value,
        };

        const result = try self.client.callWithParams("eth_sendTransaction", &rpc_params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try Hash.fromHex(result.string);
    }

    /// eth_chainId - Returns the chain ID
    pub fn chainId(self: EthNamespace) !u64 {
        const result = try self.client.callNoParams("eth_chainId");
        defer @import("./free_json.zig").freeJsonValue(self.client.allocator, result);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_syncing - Returns sync status
    pub fn syncing(self: EthNamespace) !types.SyncStatus {
        const result = try self.client.callNoParams("eth_syncing");

        // Result is either false or an object with sync info
        if (result == .bool and !result.bool) {
            return types.SyncStatus{ .syncing = false };
        }

        if (result != .object) {
            return error.InvalidResponse;
        }

        // TODO: Parse sync status object
        return types.SyncStatus{ .syncing = true };
    }

    /// eth_getBlockTransactionCountByHash - Returns the number of transactions in a block
    pub fn getBlockTransactionCountByHash(self: EthNamespace, hash: Hash) !u64 {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params = [_]std.json.Value{
            .{ .string = hash_hex },
        };

        const result = try self.client.callWithParams("eth_getBlockTransactionCountByHash", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_getBlockTransactionCountByNumber - Returns the number of transactions in a block
    pub fn getBlockTransactionCountByNumber(self: EthNamespace, block: types.BlockParameter) !u64 {
        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getBlockTransactionCountByNumber", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_getUncleCountByBlockHash - Returns the number of uncles in a block
    pub fn getUncleCountByBlockHash(self: EthNamespace, hash: Hash) !u64 {
        const hash_hex = try hash.toHex(self.client.allocator);
        defer self.client.allocator.free(hash_hex);

        var params = [_]std.json.Value{
            .{ .string = hash_hex },
        };

        const result = try self.client.callWithParams("eth_getUncleCountByBlockHash", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_getUncleCountByBlockNumber - Returns the number of uncles in a block
    pub fn getUncleCountByBlockNumber(self: EthNamespace, block: types.BlockParameter) !u64 {
        const block_param = try blockParameterToString(self.client.allocator, block);
        defer self.client.allocator.free(block_param);

        var params = [_]std.json.Value{
            .{ .string = block_param },
        };

        const result = try self.client.callWithParams("eth_getUncleCountByBlockNumber", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try parseHexU64(result.string);
    }

    /// eth_accounts - Returns list of addresses owned by client
    pub fn accounts(self: EthNamespace) ![]Address {
        const result = try self.client.callNoParams("eth_accounts");

        if (result != .array) {
            return error.InvalidResponse;
        }

        var addresses = try std.ArrayList(Address).initCapacity(self.client.allocator, 0);
        errdefer addresses.deinit(self.client.allocator);

        for (result.array.items) |item| {
            if (item != .string) {
                return error.InvalidResponse;
            }
            const addr = try Address.fromHex(item.string);
            try addresses.append(self.client.allocator, addr);
        }

        return try addresses.toOwnedSlice(self.client.allocator);
    }

    /// eth_sign - Signs data with an address
    pub fn sign(self: EthNamespace, address: Address, data: []const u8) ![]u8 {
        const addr_hex = try address.toHex(self.client.allocator);
        defer self.client.allocator.free(addr_hex);

        const hex_module = @import("../utils/hex.zig");
        const data_hex = try hex_module.bytesToHex(self.client.allocator, data);
        defer self.client.allocator.free(data_hex);

        var params = [_]std.json.Value{
            .{ .string = addr_hex },
            .{ .string = data_hex },
        };

        const result = try self.client.callWithParams("eth_sign", &params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        return try hex_module.hexToBytes(self.client.allocator, result.string);
    }

    /// eth_signTransaction - Signs a transaction
    pub fn signTransaction(self: EthNamespace, params: types.TransactionParams) ![]u8 {
        const tx_obj = try transactionParamsToJson(self.client.allocator, params);
        defer tx_obj.deinit();

        var rpc_params = [_]std.json.Value{
            tx_obj.value,
        };

        const result = try self.client.callWithParams("eth_signTransaction", &rpc_params);

        if (result != .string) {
            return error.InvalidResponse;
        }

        const hex_module = @import("../utils/hex.zig");
        return try hex_module.hexToBytes(self.client.allocator, result.string);
    }
};

/// Helper functions for parameter conversion
/// Convert BlockParameter to string for RPC
fn blockParameterToString(allocator: std.mem.Allocator, block: types.BlockParameter) ![]u8 {
    return switch (block) {
        .tag => |tag| switch (tag) {
            .latest => try allocator.dupe(u8, "latest"),
            .earliest => try allocator.dupe(u8, "earliest"),
            .pending => try allocator.dupe(u8, "pending"),
            .safe => try allocator.dupe(u8, "safe"),
            .finalized => try allocator.dupe(u8, "finalized"),
        },
        .number => |num| try std.fmt.allocPrint(allocator, "0x{x}", .{num}),
        .hash => |hash_value| try std.fmt.allocPrint(allocator, "0x{s}", .{try hash_value.toHex(allocator)}),
    };
}

/// Parse hex string to u64
fn parseHexU64(hex_str: []const u8) !u64 {
    // Remove 0x prefix if present
    const str = if (std.mem.startsWith(u8, hex_str, "0x")) hex_str[2..] else hex_str;
    return try std.fmt.parseInt(u64, str, 16);
}

/// JSON object wrapper for automatic cleanup
const JsonObjectWrapper = struct {
    value: std.json.Value,
    allocator: std.mem.Allocator,

    fn deinit(self: *JsonObjectWrapper) void {
        if (self.value == .object) {
            // Free all string values that were allocated
            var iter = self.value.object.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.* == .string) {
                    self.allocator.free(entry.value_ptr.string);
                }
            }
            self.value.object.deinit(self.allocator);
        }
    }
};

/// Convert CallParams to JSON object
fn callParamsToJson(allocator: std.mem.Allocator, params: types.CallParams) !JsonObjectWrapper {
    var obj = std.json.ObjectMap.empty;

    // Required fields
    if (params.to) |to| {
        const to_hex = try to.toHex(allocator);
        try obj.put(allocator, "to", .{ .string = to_hex });
    }

    // Optional fields
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
        const value_hex = try uint_utils.u256ToHex(value, allocator);
        try obj.put(allocator, "value", .{ .string = value_hex });
    }

    if (params.gas) |gas| {
        const gas_hex = try std.fmt.allocPrint(allocator, "0x{x}", .{gas});
        try obj.put(allocator, "gas", .{ .string = gas_hex });
    }

    if (params.gas_price) |gas_price| {
        const gp_hex = try uint_utils.u256ToHex(gas_price, allocator);
        try obj.put(allocator, "gasPrice", .{ .string = gp_hex });
    }

    return JsonObjectWrapper{
        .value = .{ .object = obj },
        .allocator = allocator,
    };
}

/// Convert TransactionParams to JSON object
fn transactionParamsToJson(allocator: std.mem.Allocator, params: types.TransactionParams) !JsonObjectWrapper {
    var obj = std.json.ObjectMap.empty;

    const from_hex = try params.from.toHex(allocator);
    try obj.put(allocator, "from", .{ .string = from_hex });

    if (params.to) |to| {
        const to_hex = try to.toHex(allocator);
        try obj.put(allocator, "to", .{ .string = to_hex });
    }

    if (params.data) |data| {
        const hex_module = @import("../utils/hex.zig");
        const data_hex = try hex_module.bytesToHex(allocator, data);
        try obj.put(allocator, "data", .{ .string = data_hex });
    }

    if (params.value) |value| {
        const value_hex = try uint_utils.u256ToHex(value, allocator);
        try obj.put(allocator, "value", .{ .string = value_hex });
    }

    if (params.gas) |gas| {
        const gas_hex = try std.fmt.allocPrint(allocator, "0x{x}", .{gas});
        try obj.put(allocator, "gas", .{ .string = gas_hex });
    }

    if (params.gas_price) |gas_price| {
        const gp_hex = try uint_utils.u256ToHex(gas_price, allocator);
        try obj.put(allocator, "gasPrice", .{ .string = gp_hex });
    }

    if (params.nonce) |nonce| {
        const nonce_hex = try std.fmt.allocPrint(allocator, "0x{x}", .{nonce});
        try obj.put(allocator, "nonce", .{ .string = nonce_hex });
    }

    return JsonObjectWrapper{
        .value = .{ .object = obj },
        .allocator = allocator,
    };
}

/// Convert FilterOptions to JSON object
fn filterOptionsToJson(allocator: std.mem.Allocator, filter: types.FilterOptions) !JsonObjectWrapper {
    var obj = std.json.ObjectMap.empty;

    if (filter.from_block) |from| {
        const from_str = try blockParameterToString(allocator, from);
        try obj.put(allocator, "fromBlock", .{ .string = from_str });
    }

    if (filter.to_block) |to| {
        const to_str = try blockParameterToString(allocator, to);
        try obj.put(allocator, "toBlock", .{ .string = to_str });
    }

    if (filter.address) |addr| {
        const addr_hex = try addr.toHex(allocator);
        try obj.put(allocator, "address", .{ .string = addr_hex });
    }

    if (filter.topics) |topics| {
        var topics_array = std.json.Array.init(allocator);
        for (topics) |topic_opt| {
            if (topic_opt) |topic| {
                const topic_hex = try topic.toHex(allocator);
                try topics_array.append(.{ .string = topic_hex });
            } else {
                try topics_array.append(.null);
            }
        }
        try obj.put(allocator, "topics", .{ .array = topics_array });
    }

    if (filter.block_hash) |hash| {
        const hash_hex = try hash.toHex(allocator);
        try obj.put(allocator, "blockHash", .{ .string = hash_hex });
    }

    return JsonObjectWrapper{
        .value = .{ .object = obj },
        .allocator = allocator,
    };
}

/// Parse a Log from JSON object
fn parseLogFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Log {
    const hex_module = @import("../utils/hex.zig");

    // Required fields
    const address_str = obj.get("address") orelse return error.MissingField;
    if (address_str != .string) return error.InvalidFieldType;
    const address = try Address.fromHex(address_str.string);

    const data_str = obj.get("data") orelse return error.MissingField;
    if (data_str != .string) return error.InvalidFieldType;
    const data_bytes = try hex_module.hexToBytes(allocator, data_str.string);
    const data = try Bytes.fromSlice(allocator, data_bytes);
    allocator.free(data_bytes);

    // Parse topics array
    const topics_json = obj.get("topics") orelse return error.MissingField;
    if (topics_json != .array) return error.InvalidFieldType;

    var topics = try std.ArrayList(Hash).initCapacity(allocator, 0);
    defer topics.deinit(allocator);

    for (topics_json.array.items) |topic_val| {
        if (topic_val != .string) return error.InvalidFieldType;
        const topic = try Hash.fromHex(topic_val.string);
        try topics.append(allocator, topic);
    }

    // Create log with required fields
    var log = try Log.init(allocator, address, topics.items, data);

    // Optional fields
    if (obj.get("blockNumber")) |block_num| {
        if (block_num == .string) {
            log.block_number = try parseHexU64(block_num.string);
        }
    }

    if (obj.get("transactionHash")) |tx_hash| {
        if (tx_hash == .string) {
            log.transaction_hash = try Hash.fromHex(tx_hash.string);
        }
    }

    if (obj.get("transactionIndex")) |tx_idx| {
        if (tx_idx == .string) {
            log.transaction_index = try parseHexU64(tx_idx.string);
        }
    }

    if (obj.get("logIndex")) |log_idx| {
        if (log_idx == .string) {
            log.log_index = try parseHexU64(log_idx.string);
        }
    }

    if (obj.get("blockHash")) |block_hash| {
        if (block_hash == .string) {
            log.block_hash = try Hash.fromHex(block_hash.string);
        }
    }

    if (obj.get("removed")) |removed| {
        if (removed == .bool) {
            log.removed = removed.bool;
        }
    }

    return log;
}

/// Parse a Transaction from JSON object
fn parseTransactionFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Transaction {
    const hex_module = @import("../utils/hex.zig");
    const TransactionType = @import("../types/transaction.zig").TransactionType;

    // Parse transaction type
    const tx_type_val = obj.get("type") orelse obj.get("transactionType");
    var tx_type: TransactionType = .legacy;
    if (tx_type_val) |type_val| {
        if (type_val == .string) {
            const type_num = try parseHexU64(type_val.string);
            tx_type = @enumFromInt(type_num);
        }
    }

    // Parse required fields
    const nonce_str = obj.get("nonce") orelse return error.MissingField;
    if (nonce_str != .string) return error.InvalidFieldType;
    const nonce = try parseHexU64(nonce_str.string);

    const gas_limit_str = obj.get("gas") orelse return error.MissingField;
    if (gas_limit_str != .string) return error.InvalidFieldType;
    const gas_limit = try parseHexU64(gas_limit_str.string);

    const value_str = obj.get("value") orelse return error.MissingField;
    if (value_str != .string) return error.InvalidFieldType;
    const value = try uint_utils.u256FromHex(value_str.string);

    const data_str = obj.get("input") orelse obj.get("data") orelse return error.MissingField;
    if (data_str != .string) return error.InvalidFieldType;
    const data_bytes = try hex_module.hexToBytes(allocator, data_str.string);
    const data = try Bytes.fromSlice(allocator, data_bytes);
    allocator.free(data_bytes);

    // Parse optional to address
    var to: ?Address = null;
    if (obj.get("to")) |to_val| {
        if (to_val == .string) {
            to = try Address.fromHex(to_val.string);
        }
    }

    // Parse gas price fields based on transaction type
    var gas_price: ?u256 = null;
    var max_fee_per_gas: ?u256 = null;
    var max_priority_fee_per_gas: ?u256 = null;

    if (tx_type == .legacy or tx_type == .eip2930) {
        if (obj.get("gasPrice")) |gp| {
            if (gp == .string) {
                gas_price = try uint_utils.u256FromHex(gp.string);
            }
        }
    }

    if (tx_type == .eip1559 or tx_type == .eip4844) {
        if (obj.get("maxFeePerGas")) |max_fee| {
            if (max_fee == .string) {
                max_fee_per_gas = try uint_utils.u256FromHex(max_fee.string);
            }
        }
        if (obj.get("maxPriorityFeePerGas")) |max_priority| {
            if (max_priority == .string) {
                max_priority_fee_per_gas = try uint_utils.u256FromHex(max_priority.string);
            }
        }
    }

    // Parse EIP-4844 specific fields
    var max_fee_per_blob_gas: ?u256 = null;
    var blob_versioned_hashes: ?[]Hash = null;

    if (tx_type == .eip4844) {
        if (obj.get("maxFeePerBlobGas")) |blob_fee| {
            if (blob_fee == .string) {
                max_fee_per_blob_gas = try uint_utils.u256FromHex(blob_fee.string);
            }
        }
        if (obj.get("blobVersionedHashes")) |hashes_val| {
            if (hashes_val == .array) {
                const hashes_array = hashes_val.array;
                if (hashes_array.items.len > 0) {
                    var hashes = try allocator.alloc(Hash, hashes_array.items.len);
                    for (hashes_array.items, 0..) |hash_val, i| {
                        if (hash_val == .string) {
                            hashes[i] = try Hash.fromHex(hash_val.string);
                        }
                    }
                    blob_versioned_hashes = hashes;
                }
            }
        }
    }

    // Create base transaction
    var tx = Transaction{
        .type = tx_type,
        .from = null,
        .to = to,
        .nonce = nonce,
        .gas_limit = gas_limit,
        .gas_price = gas_price,
        .max_fee_per_gas = max_fee_per_gas,
        .max_priority_fee_per_gas = max_priority_fee_per_gas,
        .value = value,
        .data = data,
        .chain_id = null,
        .access_list = null,
        .authorization_list = null,
        .max_fee_per_blob_gas = max_fee_per_blob_gas,
        .blob_versioned_hashes = blob_versioned_hashes,
        .signature = null,
        .hash = null,
        .block_hash = null,
        .block_number = null,
        .transaction_index = null,
        .allocator = allocator,
    };

    // Parse optional fields
    if (obj.get("from")) |from_val| {
        if (from_val == .string) {
            tx.from = try Address.fromHex(from_val.string);
        }
    }

    if (obj.get("chainId")) |chain_val| {
        if (chain_val == .string) {
            tx.chain_id = try parseHexU64(chain_val.string);
        }
    }

    if (obj.get("hash")) |hash_val| {
        if (hash_val == .string) {
            tx.hash = try Hash.fromHex(hash_val.string);
        }
    }

    if (obj.get("blockHash")) |block_hash_val| {
        if (block_hash_val == .string) {
            tx.block_hash = try Hash.fromHex(block_hash_val.string);
        }
    }

    if (obj.get("blockNumber")) |block_num_val| {
        if (block_num_val == .string) {
            tx.block_number = try parseHexU64(block_num_val.string);
        }
    }

    if (obj.get("transactionIndex")) |tx_idx_val| {
        if (tx_idx_val == .string) {
            tx.transaction_index = try parseHexU64(tx_idx_val.string);
        }
    }

    // Parse signature (v, r, s)
    const v_val = obj.get("v");
    const r_val = obj.get("r");
    const s_val = obj.get("s");

    if (v_val != null and r_val != null and s_val != null) {
        if (v_val.? == .string and r_val.? == .string and s_val.? == .string) {
            const v = try parseHexU64(v_val.?.string);
            const r = try uint_utils.u256FromHex(r_val.?.string);
            const s = try uint_utils.u256FromHex(s_val.?.string);

            tx.signature = Signature.init(uint_utils.u256ToBytes(r), uint_utils.u256ToBytes(s), @intCast(v));
        }
    }

    return tx;
}

/// Parse a Receipt from JSON object
fn parseReceiptFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Receipt {
    const TransactionStatus = @import("../types/receipt.zig").TransactionStatus;

    // Required fields
    const tx_hash_str = obj.get("transactionHash") orelse return error.MissingField;
    if (tx_hash_str != .string) return error.InvalidFieldType;
    const transaction_hash = try Hash.fromHex(tx_hash_str.string);

    const tx_index_str = obj.get("transactionIndex") orelse return error.MissingField;
    if (tx_index_str != .string) return error.InvalidFieldType;
    const transaction_index = try parseHexU64(tx_index_str.string);

    const block_hash_str = obj.get("blockHash") orelse return error.MissingField;
    if (block_hash_str != .string) return error.InvalidFieldType;
    const block_hash = try Hash.fromHex(block_hash_str.string);

    const block_num_str = obj.get("blockNumber") orelse return error.MissingField;
    if (block_num_str != .string) return error.InvalidFieldType;
    const block_number = try parseHexU64(block_num_str.string);

    const from_str = obj.get("from") orelse return error.MissingField;
    if (from_str != .string) return error.InvalidFieldType;
    const from = try Address.fromHex(from_str.string);

    // Optional to address
    var to: ?Address = null;
    if (obj.get("to")) |to_val| {
        if (to_val == .string) {
            to = try Address.fromHex(to_val.string);
        }
    }

    const cum_gas_str = obj.get("cumulativeGasUsed") orelse return error.MissingField;
    if (cum_gas_str != .string) return error.InvalidFieldType;
    const cumulative_gas_used = try parseHexU64(cum_gas_str.string);

    const gas_used_str = obj.get("gasUsed") orelse return error.MissingField;
    if (gas_used_str != .string) return error.InvalidFieldType;
    const gas_used = try parseHexU64(gas_used_str.string);

    const eff_gas_price_str = obj.get("effectiveGasPrice") orelse return error.MissingField;
    if (eff_gas_price_str != .string) return error.InvalidFieldType;
    const effective_gas_price = try uint_utils.u256FromHex(eff_gas_price_str.string);

    // Parse logs
    const logs_json = obj.get("logs") orelse return error.MissingField;
    if (logs_json != .array) return error.InvalidFieldType;

    var logs = try std.ArrayList(Log).initCapacity(allocator, 0);
    defer logs.deinit(allocator);

    for (logs_json.array.items) |log_json| {
        if (log_json != .object) return error.InvalidFieldType;
        const log = try parseLogFromJson(allocator, log_json.object);
        try logs.append(allocator, log);
    }

    const logs_bloom_str = obj.get("logsBloom") orelse return error.MissingField;
    if (logs_bloom_str != .string) return error.InvalidFieldType;
    const logs_bloom = try @import("../primitives/bloom.zig").Bloom.fromHex(logs_bloom_str.string);

    const tx_type_str = obj.get("type") orelse return error.MissingField;
    if (tx_type_str != .string) return error.InvalidFieldType;
    const transaction_type = @as(u8, @intCast(try parseHexU64(tx_type_str.string)));

    // Parse status or root
    var status: ?TransactionStatus = null;
    var root: ?Hash = null;

    if (obj.get("status")) |status_val| {
        if (status_val == .string) {
            const status_num = try parseHexU64(status_val.string);
            status = @enumFromInt(status_num);
        }
    }

    if (obj.get("root")) |root_val| {
        if (root_val == .string) {
            root = try Hash.fromHex(root_val.string);
        }
    }

    // Optional contract address
    var contract_address: ?Address = null;
    if (obj.get("contractAddress")) |addr_val| {
        if (addr_val == .string) {
            contract_address = try Address.fromHex(addr_val.string);
        }
    }

    return Receipt{
        .transaction_hash = transaction_hash,
        .transaction_index = transaction_index,
        .block_hash = block_hash,
        .block_number = block_number,
        .from = from,
        .to = to,
        .cumulative_gas_used = cumulative_gas_used,
        .gas_used = gas_used,
        .effective_gas_price = effective_gas_price,
        .contract_address = contract_address,
        .logs = try logs.toOwnedSlice(allocator),
        .logs_bloom = logs_bloom,
        .transaction_type = transaction_type,
        .status = status,
        .root = root,
        .allocator = allocator,
    };
}

/// Parse a Block from JSON object
fn parseBlockFromJson(allocator: std.mem.Allocator, obj: std.json.ObjectMap, full_tx: bool) !Block {
    const hex_module = @import("../utils/hex.zig");
    const BlockHeader = @import("../types/block.zig").BlockHeader;
    const Bloom = @import("../primitives/bloom.zig").Bloom;

    // Parse hash
    const hash_str = obj.get("hash") orelse return error.MissingField;
    if (hash_str != .string) return error.InvalidFieldType;
    const hash = try Hash.fromHex(hash_str.string);

    // Parse header fields
    const parent_hash_str = obj.get("parentHash") orelse return error.MissingField;
    if (parent_hash_str != .string) return error.InvalidFieldType;
    const parent_hash = try Hash.fromHex(parent_hash_str.string);

    const uncle_hash_str = obj.get("sha3Uncles") orelse return error.MissingField;
    if (uncle_hash_str != .string) return error.InvalidFieldType;
    const uncle_hash = try Hash.fromHex(uncle_hash_str.string);

    const miner_str = obj.get("miner") orelse return error.MissingField;
    if (miner_str != .string) return error.InvalidFieldType;
    const miner = try Address.fromHex(miner_str.string);

    const state_root_str = obj.get("stateRoot") orelse return error.MissingField;
    if (state_root_str != .string) return error.InvalidFieldType;
    const state_root = try Hash.fromHex(state_root_str.string);

    const tx_root_str = obj.get("transactionsRoot") orelse return error.MissingField;
    if (tx_root_str != .string) return error.InvalidFieldType;
    const transactions_root = try Hash.fromHex(tx_root_str.string);

    const receipts_root_str = obj.get("receiptsRoot") orelse return error.MissingField;
    if (receipts_root_str != .string) return error.InvalidFieldType;
    const receipts_root = try Hash.fromHex(receipts_root_str.string);

    const logs_bloom_str = obj.get("logsBloom") orelse return error.MissingField;
    if (logs_bloom_str != .string) return error.InvalidFieldType;
    const logs_bloom = try Bloom.fromHex(logs_bloom_str.string);

    const difficulty_str = obj.get("difficulty") orelse return error.MissingField;
    if (difficulty_str != .string) return error.InvalidFieldType;
    const difficulty = try uint_utils.u256FromHex(difficulty_str.string);

    const number_str = obj.get("number") orelse return error.MissingField;
    if (number_str != .string) return error.InvalidFieldType;
    const number = try parseHexU64(number_str.string);

    const gas_limit_str = obj.get("gasLimit") orelse return error.MissingField;
    if (gas_limit_str != .string) return error.InvalidFieldType;
    const gas_limit_block = try parseHexU64(gas_limit_str.string);

    const gas_used_str = obj.get("gasUsed") orelse return error.MissingField;
    if (gas_used_str != .string) return error.InvalidFieldType;
    const gas_used = try parseHexU64(gas_used_str.string);

    const timestamp_str = obj.get("timestamp") orelse return error.MissingField;
    if (timestamp_str != .string) return error.InvalidFieldType;
    const timestamp = try parseHexU64(timestamp_str.string);

    const extra_data_str = obj.get("extraData") orelse return error.MissingField;
    if (extra_data_str != .string) return error.InvalidFieldType;
    const extra_data_bytes = try hex_module.hexToBytes(allocator, extra_data_str.string);
    const extra_data = try Bytes.fromSlice(allocator, extra_data_bytes);
    allocator.free(extra_data_bytes);

    const mix_hash_str = obj.get("mixHash") orelse return error.MissingField;
    if (mix_hash_str != .string) return error.InvalidFieldType;
    const mix_hash = try Hash.fromHex(mix_hash_str.string);

    const nonce_str = obj.get("nonce") orelse return error.MissingField;
    if (nonce_str != .string) return error.InvalidFieldType;
    const block_nonce = try parseHexU64(nonce_str.string);

    // Optional fields for different forks
    var base_fee_per_gas: ?u256 = null;
    if (obj.get("baseFeePerGas")) |base_fee| {
        if (base_fee == .string) {
            base_fee_per_gas = try uint_utils.u256FromHex(base_fee.string);
        }
    }

    var withdrawals_root: ?Hash = null;
    if (obj.get("withdrawalsRoot")) |wd_root| {
        if (wd_root == .string) {
            withdrawals_root = try Hash.fromHex(wd_root.string);
        }
    }

    var blob_gas_used: ?u64 = null;
    if (obj.get("blobGasUsed")) |blob_gas| {
        if (blob_gas == .string) {
            blob_gas_used = try parseHexU64(blob_gas.string);
        }
    }

    var excess_blob_gas: ?u64 = null;
    if (obj.get("excessBlobGas")) |excess| {
        if (excess == .string) {
            excess_blob_gas = try parseHexU64(excess.string);
        }
    }

    var parent_beacon_block_root: ?Hash = null;
    if (obj.get("parentBeaconBlockRoot")) |beacon| {
        if (beacon == .string) {
            parent_beacon_block_root = try Hash.fromHex(beacon.string);
        }
    }

    // Create header
    const header = BlockHeader{
        .parent_hash = parent_hash,
        .uncle_hash = uncle_hash,
        .miner = miner,
        .state_root = state_root,
        .transactions_root = transactions_root,
        .receipts_root = receipts_root,
        .logs_bloom = logs_bloom,
        .difficulty = difficulty,
        .number = number,
        .gas_limit = gas_limit_block,
        .gas_used = gas_used,
        .timestamp = timestamp,
        .extra_data = extra_data,
        .mix_hash = mix_hash,
        .nonce = block_nonce,
        .base_fee_per_gas = base_fee_per_gas,
        .withdrawals_root = withdrawals_root,
        .blob_gas_used = blob_gas_used,
        .excess_blob_gas = excess_blob_gas,
        .parent_beacon_block_root = parent_beacon_block_root,
    };

    // Parse transactions
    const transactions_json = obj.get("transactions") orelse return error.MissingField;
    if (transactions_json != .array) return error.InvalidFieldType;

    var transactions = try std.ArrayList(Transaction).initCapacity(allocator, 0);
    defer transactions.deinit(allocator);

    if (full_tx) {
        // Full transaction objects
        for (transactions_json.array.items) |tx_json| {
            if (tx_json != .object) return error.InvalidFieldType;
            const tx = try parseTransactionFromJson(allocator, tx_json.object);
            try transactions.append(allocator, tx);
        }
    } else {
        // Just transaction hashes - create minimal transaction structs
        for (transactions_json.array.items) |tx_hash_json| {
            if (tx_hash_json != .string) return error.InvalidFieldType;
            const tx_hash = try Hash.fromHex(tx_hash_json.string);

            // Create minimal transaction with just hash
            const empty_data = try Bytes.fromSlice(allocator, &[_]u8{});
            const tx = Transaction{
                .type = .legacy,
                .from = null,
                .to = null,
                .nonce = 0,
                .gas_limit = 0,
                .gas_price = null,
                .max_fee_per_gas = null,
                .max_priority_fee_per_gas = null,
                .value = 0,
                .data = empty_data,
                .chain_id = null,
                .access_list = null,
                .authorization_list = null,
                .max_fee_per_blob_gas = null,
                .blob_versioned_hashes = null,
                .signature = null,
                .hash = tx_hash,
                .block_hash = null,
                .block_number = null,
                .transaction_index = null,
                .allocator = allocator,
            };
            try transactions.append(allocator, tx);
        }
    }

    // Parse uncles (uncle hashes only)
    const uncles_json = obj.get("uncles") orelse return error.MissingField;
    if (uncles_json != .array) return error.InvalidFieldType;

    return Block{
        .hash = hash,
        .header = header,
        .transactions = try transactions.toOwnedSlice(allocator),
        .uncles = &[_]Hash{}, // TODO: Parse uncles from JSON
        .total_difficulty = 0, // TODO: Parse total difficulty
        .size = 0, // TODO: Parse size from JSON
        .allocator = allocator,
    };
}

test "eth namespace creation" {
    const allocator = std.testing.allocator;

    var client = try RpcClient.init(allocator, "http://localhost:8545");
    defer client.deinit();

    const eth = EthNamespace.init(&client);
    try std.testing.expect(eth.client.endpoint.len > 0);
}

test "block parameter to string" {
    const allocator = std.testing.allocator;

    const latest = try blockParameterToString(allocator, .{ .tag = .latest });
    defer allocator.free(latest);
    try std.testing.expectEqualStrings("latest", latest);

    const number = try blockParameterToString(allocator, .{ .number = 12345 });
    defer allocator.free(number);
    try std.testing.expectEqualStrings("0x3039", number);
}

test "parse hex u64" {
    const value1 = try parseHexU64("0x10");
    try std.testing.expectEqual(@as(u64, 16), value1);

    const value2 = try parseHexU64("3039");
    try std.testing.expectEqual(@as(u64, 12345), value2);

    const value3 = try parseHexU64("0xff");
    try std.testing.expectEqual(@as(u64, 255), value3);
}

test "call params to json" {
    const allocator = std.testing.allocator;

    const addr = Address.fromBytes([_]u8{0x12} ** 20);
    const params = types.CallParams{
        .to = addr,
        .from = null,
        .data = null,
        .value = null,
        .gas = 21000,
        .gas_price = null,
    };

    var json_obj = try callParamsToJson(allocator, params);
    defer json_obj.deinit();

    try std.testing.expect(json_obj.value == .object);
    try std.testing.expect(json_obj.value.object.contains("to"));
    try std.testing.expect(json_obj.value.object.contains("gas"));
}
