const std = @import("std");
const uint_utils = @import("../primitives/uint.zig");
const Provider = @import("../providers/provider.zig").Provider;
const Address = @import("../primitives/address.zig").Address;
const Transaction = @import("../types/transaction.zig").Transaction;
const time_compat = @import("../time_compat.zig");

/// Gas price strategy
pub const GasStrategy = enum {
    slow,
    standard,
    fast,
    custom,
};

/// Gas price configuration
pub const GasConfig = struct {
    strategy: GasStrategy,
    max_fee_per_gas: ?u256,
    max_priority_fee_per_gas: ?u256,
    gas_limit: ?u64,
    multiplier: f64, // Multiplier for gas price (e.g., 1.1 = 110%)

    pub fn default() GasConfig {
        return .{
            .strategy = .standard,
            .max_fee_per_gas = null,
            .max_priority_fee_per_gas = null,
            .gas_limit = null,
            .multiplier = 1.0,
        };
    }

    pub fn slow() GasConfig {
        return .{
            .strategy = .slow,
            .max_fee_per_gas = null,
            .max_priority_fee_per_gas = null,
            .gas_limit = null,
            .multiplier = 0.9, // 90% of base
        };
    }

    pub fn fast() GasConfig {
        return .{
            .strategy = .fast,
            .max_fee_per_gas = null,
            .max_priority_fee_per_gas = null,
            .gas_limit = null,
            .multiplier = 1.2, // 120% of base
        };
    }

    pub fn custom(max_fee: u256, max_priority_fee: u256) GasConfig {
        return .{
            .strategy = .custom,
            .max_fee_per_gas = max_fee,
            .max_priority_fee_per_gas = max_priority_fee,
            .gas_limit = null,
            .multiplier = 1.0,
        };
    }
};

/// EIP-1559 fee data
pub const FeeData = struct {
    max_fee_per_gas: u256,
    max_priority_fee_per_gas: u256,
    base_fee_per_gas: u256,
    last_block_number: u64,

    pub fn estimatedCost(self: FeeData, gas_limit: u64) u256 {
        return self.max_fee_per_gas * gas_limit;
    }
};

/// Gas middleware for automatic gas price and limit management
pub const GasMiddleware = struct {
    provider: *Provider,
    config: GasConfig,
    allocator: std.mem.Allocator,
    cached_fee_data: ?FeeData,
    cache_timestamp: i64,
    cache_ttl_seconds: i64,

    /// Create a new gas middleware
    pub fn init(allocator: std.mem.Allocator, provider: *Provider, config: GasConfig) GasMiddleware {
        return .{
            .provider = provider,
            .config = config,
            .allocator = allocator,
            .cached_fee_data = null,
            .cache_timestamp = 0,
            .cache_ttl_seconds = 12, // Cache for 12 seconds (1 block)
        };
    }

    /// Get current gas price (legacy)
    pub fn getGasPrice(self: *GasMiddleware) !u256 {
        const base_price = try self.provider.getGasPrice();

        // Apply multiplier
        const multiplier_int = @as(u64, @intFromFloat(self.config.multiplier * 100.0));
        const adjusted_price = base_price * multiplier_int;
        return adjusted_price / 100;
    }

    /// Get EIP-1559 fee data
    pub fn getFeeData(self: *GasMiddleware) !FeeData {
        // Check cache
        const now: i64 = time_compat.nowSeconds();
        if (self.cached_fee_data) |cached| {
            if (now - self.cache_timestamp < self.cache_ttl_seconds) {
                return cached;
            }
        }

        // Custom strategy: use provided values
        if (self.config.strategy == .custom) {
            if (self.config.max_fee_per_gas) |max_fee| {
                if (self.config.max_priority_fee_per_gas) |max_priority| {
                    const fee_data = FeeData{
                        .max_fee_per_gas = max_fee,
                        .max_priority_fee_per_gas = max_priority,
                        .base_fee_per_gas = if (max_fee >= max_priority) max_fee - max_priority else 0,
                        .last_block_number = try self.provider.getBlockNumber(),
                    };
                    self.cached_fee_data = fee_data;
                    self.cache_timestamp = now;
                    return fee_data;
                }
            }
        }

        // Get base fee from latest block
        const block_number = try self.provider.getBlockNumber();
        const latest_block = try self.provider.getLatestBlock();
        defer latest_block.deinit();

        const base_fee = latest_block.header.base_fee_per_gas orelse blk: {
            // Fallback to gas price for pre-EIP-1559 networks
            const gas_price = try self.getGasPrice();
            break :blk gas_price;
        };

        // Calculate max priority fee based on strategy
        const priority_fee = try self.calculatePriorityFee(base_fee);

        // Calculate max fee = base fee + priority fee
        const max_fee = base_fee + priority_fee;

        const fee_data = FeeData{
            .max_fee_per_gas = max_fee,
            .max_priority_fee_per_gas = priority_fee,
            .base_fee_per_gas = base_fee,
            .last_block_number = block_number,
        };

        // Cache the result
        self.cached_fee_data = fee_data;
        self.cache_timestamp = now;

        return fee_data;
    }

    /// Calculate priority fee based on strategy
    fn calculatePriorityFee(self: *GasMiddleware, base_fee: u256) !u256 {
        _ = base_fee; // Reserved for future use

        // Try to get max priority fee from provider
        var eth = self.provider.getEth();
        const suggested_priority = eth.maxPriorityFeePerGas() catch {
            // Fallback: 2.5 gwei for standard, adjust for strategy
            return @as(u256, 2_500_000_000);
        };

        // Apply strategy multiplier
        const multiplier_int = @as(u64, @intFromFloat(self.config.multiplier * 100.0));
        const adjusted = suggested_priority * multiplier_int;
        return adjusted / 100;
    }

    /// Estimate gas limit for a transaction
    pub fn estimateGasLimit(self: *GasMiddleware, from: Address, to: Address, data: []const u8) !u64 {
        // Use configured gas limit if provided
        if (self.config.gas_limit) |limit| {
            return limit;
        }

        // Build call params for estimation
        const call_params = @import("../rpc/types.zig").CallParams{
            .from = from,
            .to = to,
            .gas = null,
            .gas_price = null,
            .value = null,
            .data = data,
            .block_parameter = .latest,
        };

        // Estimate gas
        const estimated = try self.provider.eth.estimateGas(call_params);

        // Add 20% buffer for safety
        const buffer_multiplier: u64 = 120;
        const with_buffer = (estimated * buffer_multiplier) / 100;

        return with_buffer;
    }

    /// Apply gas settings to a transaction
    pub fn applyGasSettings(self: *GasMiddleware, tx: *Transaction) !void {
        const fee_data = try self.getFeeData();

        switch (tx.type) {
            .eip1559, .eip4844, .eip7702 => {
                // EIP-1559 transactions
                tx.max_fee_per_gas = fee_data.max_fee_per_gas;
                tx.max_priority_fee_per_gas = fee_data.max_priority_fee_per_gas;
            },
            .legacy, .eip2930 => {
                // Legacy transactions - use max_fee_per_gas as gas_price
                tx.gas_price = fee_data.max_fee_per_gas;
            },
        }
    }

    /// Calculate total transaction cost
    pub fn calculateTxCost(self: *GasMiddleware, gas_limit: u64) !u256 {
        const fee_data = try self.getFeeData();
        return fee_data.estimatedCost(gas_limit);
    }

    /// Check if account has sufficient balance for transaction
    pub fn checkSufficientBalance(
        self: *GasMiddleware,
        from: Address,
        value: u256,
        gas_limit: u64,
    ) !bool {
        const balance = try self.provider.getBalance(from);
        const tx_cost = try self.calculateTxCost(gas_limit);
        const total_cost = value + tx_cost;

        return balance >= total_cost;
    }

    /// Clear cached fee data
    pub fn clearCache(self: *GasMiddleware) void {
        self.cached_fee_data = null;
        self.cache_timestamp = 0;
    }

    /// Set cache TTL
    pub fn setCacheTtl(self: *GasMiddleware, seconds: i64) void {
        self.cache_ttl_seconds = seconds;
    }

    /// Get gas price in gwei
    pub fn getGasPriceGwei(self: *GasMiddleware) !f64 {
        const price = try self.getGasPrice();
        const price_u64 = uint_utils.u256ToU64(price) catch 0;
        const gwei = @as(f64, @floatFromInt(price_u64)) / 1_000_000_000.0;
        return gwei;
    }
};

// Tests
test "gas config default" {
    const config = GasConfig.default();
    try std.testing.expectEqual(GasStrategy.standard, config.strategy);
    try std.testing.expectEqual(@as(f64, 1.0), config.multiplier);
}

test "gas config slow" {
    const config = GasConfig.slow();
    try std.testing.expectEqual(GasStrategy.slow, config.strategy);
    try std.testing.expectEqual(@as(f64, 0.9), config.multiplier);
}

test "gas config fast" {
    const config = GasConfig.fast();
    try std.testing.expectEqual(GasStrategy.fast, config.strategy);
    try std.testing.expectEqual(@as(f64, 1.2), config.multiplier);
}

test "gas config custom" {
    const max_fee = @as(u256, 50_000_000_000);
    const max_priority = @as(u256, 2_000_000_000);
    const config = GasConfig.custom(max_fee, max_priority);

    try std.testing.expectEqual(GasStrategy.custom, config.strategy);
    try std.testing.expect(config.max_fee_per_gas != null);
    try std.testing.expect(config.max_priority_fee_per_gas != null);
}

test "fee data estimated cost" {
    const fee_data = FeeData{
        .max_fee_per_gas = @as(u256, 50_000_000_000), // 50 gwei
        .max_priority_fee_per_gas = @as(u256, 2_000_000_000), // 2 gwei
        .base_fee_per_gas = @as(u256, 48_000_000_000), // 48 gwei
        .last_block_number = 1000,
    };

    const cost = fee_data.estimatedCost(21000); // Standard transfer gas
    try std.testing.expect(cost > 0);
}

test "gas middleware creation" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    const config = GasConfig.default();
    const middleware = GasMiddleware.init(allocator, &provider, config);

    try std.testing.expectEqual(GasStrategy.standard, middleware.config.strategy);
    try std.testing.expect(middleware.cached_fee_data == null);
}

test "gas middleware cache ttl" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    const config = GasConfig.default();
    var middleware = GasMiddleware.init(allocator, &provider, config);

    middleware.setCacheTtl(30);
    try std.testing.expectEqual(@as(i64, 30), middleware.cache_ttl_seconds);
}

test "gas middleware clear cache" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    const config = GasConfig.default();
    var middleware = GasMiddleware.init(allocator, &provider, config);

    middleware.cached_fee_data = FeeData{
        .max_fee_per_gas = @as(u256, 50_000_000_000),
        .max_priority_fee_per_gas = @as(u256, 2_000_000_000),
        .base_fee_per_gas = @as(u256, 48_000_000_000),
        .last_block_number = 1000,
    };

    middleware.clearCache();
    try std.testing.expect(middleware.cached_fee_data == null);
}
