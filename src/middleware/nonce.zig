const std = @import("std");
const Address = @import("../primitives/address.zig").Address;
const Provider = @import("../providers/provider.zig").Provider;

// std.time.timestamp / milliTimestamp were removed in Zig 0.16 (moved
// under std.Io). Read the wall clock directly via libc.
fn wallClockSeconds() i64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    return @intCast(ts.sec);
}

/// Nonce management strategy
pub const NonceStrategy = enum {
    /// Get nonce from provider for each transaction
    provider,
    /// Track nonce locally and increment
    local,
    /// Hybrid: verify with provider periodically
    hybrid,
};

/// Pending transaction tracking
pub const PendingTransaction = struct {
    nonce: u64,
    timestamp: i64,
    hash: ?[32]u8,
};

/// Nonce middleware for automatic nonce management
pub const NonceMiddleware = struct {
    provider: *Provider,
    strategy: NonceStrategy,
    allocator: std.mem.Allocator,
    nonce_cache: std.AutoHashMap(Address, u64),
    pending_txs: std.AutoHashMap(Address, std.ArrayList(PendingTransaction)),
    last_sync: std.AutoHashMap(Address, i64),
    sync_interval_seconds: i64,

    /// Create a new nonce middleware
    pub fn init(allocator: std.mem.Allocator, provider: *Provider, strategy: NonceStrategy) !NonceMiddleware {
        return .{
            .provider = provider,
            .strategy = strategy,
            .allocator = allocator,
            .nonce_cache = std.AutoHashMap(Address, u64).init(allocator),
            .pending_txs = std.AutoHashMap(Address, std.ArrayList(PendingTransaction)).init(allocator),
            .last_sync = std.AutoHashMap(Address, i64).init(allocator),
            .sync_interval_seconds = 30, // Sync every 30 seconds for hybrid mode
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *NonceMiddleware) void {
        self.nonce_cache.deinit();

        // Free pending transaction lists
        var pending_it = self.pending_txs.iterator();
        while (pending_it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.pending_txs.deinit();

        self.last_sync.deinit();
    }

    /// Get next nonce for an address
    pub fn getNextNonce(self: *NonceMiddleware, address: Address) !u64 {
        switch (self.strategy) {
            .provider => {
                // Always query provider
                return try self.provider.getTransactionCount(address);
            },
            .local => {
                // Use cached nonce, initialize if needed
                if (self.nonce_cache.get(address)) |nonce| {
                    return nonce;
                } else {
                    const nonce = try self.provider.getTransactionCount(address);
                    try self.nonce_cache.put(address, nonce);
                    return nonce;
                }
            },
            .hybrid => {
                // Check if we need to sync with provider
                const now = wallClockSeconds();
                const should_sync = blk: {
                    if (self.last_sync.get(address)) |last| {
                        break :blk (now - last) >= self.sync_interval_seconds;
                    }
                    break :blk true;
                };

                if (should_sync) {
                    const nonce = try self.provider.getTransactionCount(address);
                    try self.nonce_cache.put(address, nonce);
                    try self.last_sync.put(address, now);
                    return nonce;
                } else if (self.nonce_cache.get(address)) |nonce| {
                    return nonce;
                } else {
                    const nonce = try self.provider.getTransactionCount(address);
                    try self.nonce_cache.put(address, nonce);
                    try self.last_sync.put(address, now);
                    return nonce;
                }
            },
        }
    }

    /// Reserve a nonce for a transaction (increments local counter)
    pub fn reserveNonce(self: *NonceMiddleware, address: Address) !u64 {
        const nonce = try self.getNextNonce(address);

        // Increment local cache for local and hybrid strategies
        if (self.strategy != .provider) {
            try self.nonce_cache.put(address, nonce + 1);
        }

        return nonce;
    }

    /// Track a pending transaction
    pub fn trackPendingTx(self: *NonceMiddleware, address: Address, nonce: u64, tx_hash: ?[32]u8) !void {
        const pending_tx = PendingTransaction{
            .nonce = nonce,
            .timestamp = wallClockSeconds(),
            .hash = tx_hash,
        };

        // Check if list exists, create if not
        if (!self.pending_txs.contains(address)) {
            const new_list = try std.ArrayList(PendingTransaction).initCapacity(self.allocator, 0);
            try self.pending_txs.put(address, new_list);
        }

        // Get mutable reference to the list
        const list_ptr = self.pending_txs.getPtr(address) orelse return;
        try list_ptr.append(self.allocator, pending_tx);
    }

    /// Get pending transaction count for an address
    pub fn getPendingCount(self: NonceMiddleware, address: Address) usize {
        if (self.pending_txs.get(address)) |list| {
            return list.items.len;
        }
        return 0;
    }

    /// Clear pending transactions for an address
    pub fn clearPending(self: *NonceMiddleware, address: Address) void {
        if (self.pending_txs.getPtr(address)) |list| {
            list.clearRetainingCapacity();
        }
    }

    /// Remove a specific pending transaction by nonce
    pub fn removePendingTx(self: *NonceMiddleware, address: Address, nonce: u64) void {
        if (self.pending_txs.getPtr(address)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i].nonce == nonce) {
                    _ = list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Sync nonce with provider (force refresh)
    pub fn syncNonce(self: *NonceMiddleware, address: Address) !u64 {
        const nonce = try self.provider.getTransactionCount(address);
        try self.nonce_cache.put(address, nonce);
        try self.last_sync.put(address, wallClockSeconds());
        return nonce;
    }

    /// Reset nonce for an address (clears cache and pending)
    pub fn resetNonce(self: *NonceMiddleware, address: Address) void {
        _ = self.nonce_cache.remove(address);
        _ = self.last_sync.remove(address);
        self.clearPending(address);
    }

    /// Set nonce manually for an address
    pub fn setNonce(self: *NonceMiddleware, address: Address, nonce: u64) !void {
        try self.nonce_cache.put(address, nonce);
    }

    /// Get cached nonce (without querying provider)
    pub fn getCachedNonce(self: NonceMiddleware, address: Address) ?u64 {
        return self.nonce_cache.get(address);
    }

    /// Set sync interval for hybrid mode
    pub fn setSyncInterval(self: *NonceMiddleware, seconds: i64) void {
        self.sync_interval_seconds = seconds;
    }

    /// Check if nonce is in pending transactions
    pub fn isNoncePending(self: NonceMiddleware, address: Address, nonce: u64) bool {
        if (self.pending_txs.get(address)) |list| {
            for (list.items) |pending| {
                if (pending.nonce == nonce) return true;
            }
        }
        return false;
    }

    /// Get oldest pending transaction for an address
    pub fn getOldestPending(self: NonceMiddleware, address: Address) ?PendingTransaction {
        if (self.pending_txs.get(address)) |list| {
            if (list.items.len > 0) {
                var oldest = list.items[0];
                for (list.items[1..]) |pending| {
                    if (pending.timestamp < oldest.timestamp) {
                        oldest = pending;
                    }
                }
                return oldest;
            }
        }
        return null;
    }

    /// Clean up old pending transactions (older than timeout)
    pub fn cleanupOldPending(self: *NonceMiddleware, address: Address, timeout_seconds: i64) void {
        if (self.pending_txs.getPtr(address)) |list| {
            const now = wallClockSeconds();
            var i: usize = 0;
            while (i < list.items.len) {
                if (now - list.items[i].timestamp > timeout_seconds) {
                    _ = list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }

    /// Get nonce gap (difference between provider and local)
    pub fn getNonceGap(self: *NonceMiddleware, address: Address) !i64 {
        const provider_nonce = try self.provider.getTransactionCount(address);
        const local_nonce = self.getCachedNonce(address) orelse provider_nonce;
        return @as(i64, @intCast(local_nonce)) - @as(i64, @intCast(provider_nonce));
    }
};

// Tests
test "nonce middleware creation" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    try std.testing.expectEqual(NonceStrategy.local, middleware.strategy);
}

test "nonce middleware set and get" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);
    try middleware.setNonce(addr, 42);

    const cached = middleware.getCachedNonce(addr);
    try std.testing.expect(cached != null);
    try std.testing.expectEqual(@as(u64, 42), cached.?);
}

test "nonce middleware reset" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);
    try middleware.setNonce(addr, 42);

    middleware.resetNonce(addr);
    const cached = middleware.getCachedNonce(addr);
    try std.testing.expect(cached == null);
}

test "nonce middleware pending tracking" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);

    try middleware.trackPendingTx(addr, 5, null);
    try middleware.trackPendingTx(addr, 6, null);

    try std.testing.expectEqual(@as(usize, 2), middleware.getPendingCount(addr));
}

test "nonce middleware clear pending" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);

    try middleware.trackPendingTx(addr, 5, null);
    try middleware.trackPendingTx(addr, 6, null);

    middleware.clearPending(addr);
    try std.testing.expectEqual(@as(usize, 0), middleware.getPendingCount(addr));
}

test "nonce middleware remove specific pending" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);

    try middleware.trackPendingTx(addr, 5, null);
    try middleware.trackPendingTx(addr, 6, null);
    try middleware.trackPendingTx(addr, 7, null);

    middleware.removePendingTx(addr, 6);
    try std.testing.expectEqual(@as(usize, 2), middleware.getPendingCount(addr));
}

test "nonce middleware is nonce pending" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .local);
    defer middleware.deinit();

    const addr = Address.fromBytes([_]u8{1} ** 20);

    try middleware.trackPendingTx(addr, 5, null);

    try std.testing.expect(middleware.isNoncePending(addr, 5));
    try std.testing.expect(!middleware.isNoncePending(addr, 6));
}

test "nonce middleware sync interval" {
    const allocator = std.testing.allocator;

    var provider = try Provider.init(allocator, "http://localhost:8545");
    defer provider.deinit();

    var middleware = try NonceMiddleware.init(allocator, &provider, .hybrid);
    defer middleware.deinit();

    middleware.setSyncInterval(60);
    try std.testing.expectEqual(@as(i64, 60), middleware.sync_interval_seconds);
}
