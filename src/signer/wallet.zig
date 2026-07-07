const std = @import("std");
const Address = @import("../primitives/address.zig").Address;
const Hash = @import("../primitives/hash.zig").Hash;
const Signature = @import("../primitives/signature.zig").Signature;
const u256ToU64 = @import("../primitives/uint.zig").u256ToU64;
const Transaction = @import("../types/transaction.zig").Transaction;
const PrivateKey = @import("../crypto/secp256k1.zig").PrivateKey;
const PublicKey = @import("../crypto/secp256k1.zig").PublicKey;
const Signer = @import("../crypto/ecdsa.zig").Signer;
const keccak = @import("../crypto/keccak.zig");
const SignerInterface = @import("./signer.zig").SignerInterface;
const SignerCapabilities = @import("./signer.zig").SignerCapabilities;

/// Software wallet with private key
pub const Wallet = struct {
    private_key: PrivateKey,
    signer: Signer,
    address: Address,
    allocator: std.mem.Allocator,
    capabilities: SignerCapabilities,

    /// Create a new wallet from a private key
    pub fn init(allocator: std.mem.Allocator, private_key: PrivateKey) !Wallet {
        const signer = Signer.init(private_key);
        const address = try signer.getAddress();

        return .{
            .private_key = private_key,
            .signer = signer,
            .address = address,
            .allocator = allocator,
            .capabilities = SignerCapabilities.full(),
        };
    }

    /// Create a wallet from a private key hex string
    pub fn fromPrivateKeyHex(allocator: std.mem.Allocator, hex: []const u8) !Wallet {
        const hex_module = @import("../utils/hex.zig");

        // Remove 0x prefix if present
        const hex_clean = if (std.mem.startsWith(u8, hex, "0x"))
            hex[2..]
        else
            hex;

        if (hex_clean.len != 64) {
            return error.InvalidPrivateKeyLength;
        }

        const key_bytes = try hex_module.hexToBytes(allocator, hex_clean);
        defer allocator.free(key_bytes);

        if (key_bytes.len != 32) {
            return error.InvalidPrivateKeyLength;
        }

        var key_array: [32]u8 = undefined;
        @memcpy(&key_array, key_bytes);

        const private_key = try PrivateKey.fromBytes(key_array);
        return try init(allocator, private_key);
    }

    /// Generate a new random wallet
    pub fn generate(allocator: std.mem.Allocator) !Wallet {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
        var prng = std.Random.DefaultPrng.init(@intCast(ts.sec));
        const random = prng.random();
        const private_key = try PrivateKey.generate(random);
        return try init(allocator, private_key);
    }

    /// Get the wallet's address
    pub fn getAddress(self: Wallet) !Address {
        return self.address;
    }

    /// Get the private key (use with caution!)
    pub fn getPrivateKey(self: Wallet) PrivateKey {
        return self.private_key;
    }

    /// Get the public key
    pub fn getPublicKey(self: *Wallet) !PublicKey {
        return try self.signer.getPublicKey();
    }

    /// Export private key as hex string
    pub fn exportPrivateKey(self: Wallet) ![]u8 {
        const hex_module = @import("../utils/hex.zig");
        const hex = try hex_module.bytesToHex(self.allocator, &self.private_key.bytes);
        return hex;
    }

    /// Sign a transaction
    pub fn signTransaction(self: *Wallet, tx: *Transaction, chain_id: u64) !Signature {
        // Set chain ID for EIP-155
        tx.chain_id = chain_id;

        // Get transaction hash
        const tx_hash = try self.getTransactionHash(tx, chain_id);

        // Sign the hash
        const sig = try self.signer.signHash(tx_hash.bytes);

        // Adjust v value for EIP-155
        const v = sig.getRecoveryId();
        const eip155_v = Signature.eip155V(v, chain_id);

        return Signature.init(sig.r, sig.s, eip155_v);
    }

    /// Get transaction hash for signing
    fn getTransactionHash(self: *Wallet, tx: *Transaction, chain_id: u64) !Hash {
        const RlpEncoder = @import("../rlp/encode.zig").Encoder;
        const RlpItem = @import("../rlp/encode.zig").RlpItem;

        var encoder = RlpEncoder.init(self.allocator);
        defer encoder.deinit();

        switch (tx.type) {
            .legacy => {
                // Legacy transaction with EIP-155
                try encoder.startList();
                try encoder.appendItem(.{ .uint = tx.nonce });
                try encoder.appendItem(.{ .uint = u256ToU64(tx.gas_price orelse 0) catch 0 });
                try encoder.appendItem(.{ .uint = tx.gas_limit });

                if (tx.to) |to_addr| {
                    try encoder.appendItem(.{ .bytes = &to_addr.bytes });
                } else {
                    try encoder.appendItem(.{ .bytes = &[_]u8{} });
                }

                try encoder.appendItem(.{ .uint = u256ToU64(tx.value) catch 0 });
                try encoder.appendItem(.{ .bytes = tx.data.data });

                // EIP-155: add chain_id, 0, 0
                try encoder.appendItem(.{ .uint = chain_id });
                try encoder.appendItem(.{ .uint = 0 });
                try encoder.appendItem(.{ .uint = 0 });

                const encoded = try encoder.finish();
                defer self.allocator.free(encoded);

                return keccak.hash(encoded);
            },
            .eip2930, .eip1559, .eip4844, .eip7702 => {
                // Typed transactions
                try encoder.startList();
                try encoder.appendItem(.{ .uint = chain_id });
                try encoder.appendItem(.{ .uint = tx.nonce });

                switch (tx.type) {
                    .eip2930 => {
                        try encoder.appendItem(.{ .uint = u256ToU64(tx.gas_price orelse 0) catch 0 });
                    },
                    .eip1559, .eip4844, .eip7702 => {
                        try encoder.appendItem(.{ .uint = u256ToU64(tx.max_priority_fee_per_gas orelse 0) catch 0 });
                        try encoder.appendItem(.{ .uint = u256ToU64(tx.max_fee_per_gas orelse 0) catch 0 });
                    },
                    else => unreachable,
                }

                try encoder.appendItem(.{ .uint = tx.gas_limit });

                if (tx.to) |to_addr| {
                    try encoder.appendItem(.{ .bytes = &to_addr.bytes });
                } else {
                    try encoder.appendItem(.{ .bytes = &[_]u8{} });
                }

                try encoder.appendItem(.{ .uint = u256ToU64(tx.value) catch 0 });
                try encoder.appendItem(.{ .bytes = tx.data.data });

                // Access list (empty for now)
                try encoder.appendItem(.{ .list = &[_]RlpItem{} });

                // EIP-4844 specific
                if (tx.type == .eip4844) {
                    const blob_fee = u256ToU64(tx.max_fee_per_blob_gas orelse 0) catch 0;
                    try encoder.appendItem(.{ .uint = blob_fee });
                    // Encode blob versioned hashes as list of bytes32
                    if (tx.blob_versioned_hashes) |hashes| {
                        var hash_items = try self.allocator.alloc(RlpItem, hashes.len);
                        defer self.allocator.free(hash_items);
                        for (hashes, 0..) |h, i| {
                            hash_items[i] = .{ .bytes = &h.bytes };
                        }
                        try encoder.appendItem(.{ .list = hash_items });
                    } else {
                        try encoder.appendItem(.{ .list = &[_]RlpItem{} });
                    }
                }

                // EIP-7702 specific
                if (tx.type == .eip7702) {
                    try encoder.appendItem(.{ .list = &[_]RlpItem{} }); // authorization list
                }

                const encoded = try encoder.finish();
                defer self.allocator.free(encoded);

                // Prepend transaction type
                const tx_type: u8 = switch (tx.type) {
                    .eip2930 => 0x01,
                    .eip1559 => 0x02,
                    .eip4844 => 0x03,
                    .eip7702 => 0x04,
                    else => unreachable,
                };

                var type_prefixed = try self.allocator.alloc(u8, encoded.len + 1);
                defer self.allocator.free(type_prefixed);
                type_prefixed[0] = tx_type;
                @memcpy(type_prefixed[1..], encoded);

                return keccak.hash(type_prefixed);
            },
        }
    }

    /// Sign a message hash
    pub fn signHash(self: *Wallet, hash: [32]u8) !Signature {
        return try self.signer.signHash(Hash.fromBytes(hash));
    }

    /// Sign a message (with Ethereum prefix)
    pub fn signMessage(self: *Wallet, message: []const u8) !Signature {
        return try self.signer.signPersonalMessage(self.allocator, message);
    }

    /// Sign typed data (EIP-712)
    pub fn signTypedData(self: *Wallet, domain_hash: [32]u8, message_hash: [32]u8) !Signature {
        // EIP-712: keccak256("\x19\x01" ‖ domainSeparator ‖ hashStruct(message))
        var data: [66]u8 = undefined;
        data[0] = 0x19;
        data[1] = 0x01;
        @memcpy(data[2..34], &domain_hash);
        @memcpy(data[34..66], &message_hash);

        const hash = keccak.hash(&data);
        return try self.signer.signHash(hash);
    }

    /// Verify a signature
    pub fn verifySignature(self: *Wallet, hash: [32]u8, signature: Signature) !bool {
        const ecdsa = @import("../crypto/ecdsa.zig");
        const recovered_addr = try ecdsa.recoverAddress(Hash.fromBytes(hash), signature);
        return std.mem.eql(u8, &recovered_addr.bytes, &self.address.bytes);
    }

    /// Get signer interface
    pub fn asInterface(self: *Wallet) SignerInterface {
        const signerInterface = @import("./signer.zig").signerInterface;
        return signerInterface(Wallet, self);
    }

    /// Get capabilities
    pub fn getCapabilities(self: Wallet) SignerCapabilities {
        return self.capabilities;
    }
};

/// HD Wallet (BIP-32/BIP-44) - Framework
pub const HDWallet = struct {
    master_key: PrivateKey,
    chain_code: [32]u8,
    allocator: std.mem.Allocator,
    path: []const u8,

    /// Create HD wallet from seed
    pub fn fromSeed(allocator: std.mem.Allocator, seed: []const u8) !HDWallet {
        if (seed.len < 16 or seed.len > 64) {
            return error.InvalidSeedLength;
        }

        // TODO: Implement BIP-32 key derivation
        // For now, use seed as master key (simplified)
        var master_key_bytes: [32]u8 = undefined;
        @memcpy(master_key_bytes[0..@min(32, seed.len)], seed[0..@min(32, seed.len)]);

        const master_key = try PrivateKey.fromBytes(master_key_bytes);

        return .{
            .master_key = master_key,
            .chain_code = [_]u8{0} ** 32,
            .allocator = allocator,
            .path = "m",
        };
    }

    /// Derive child wallet at path (e.g., "m/44'/60'/0'/0/0")
    pub fn deriveChild(self: HDWallet, path: []const u8) !Wallet {
        // TODO: Implement proper BIP-32/BIP-44 derivation
        _ = path;
        return try Wallet.init(self.allocator, self.master_key);
    }

    /// Get wallet at index (simplified derivation)
    pub fn getWallet(self: HDWallet, index: u32) !Wallet {
        // TODO: Implement proper derivation
        _ = index;
        return try Wallet.init(self.allocator, self.master_key);
    }
};

/// Mnemonic (BIP-39) - Framework
pub const Mnemonic = struct {
    words: []const []const u8,
    allocator: std.mem.Allocator,

    /// Generate a new mnemonic (12/24 words)
    pub fn generate(allocator: std.mem.Allocator, word_count: usize) !Mnemonic {
        if (word_count != 12 and word_count != 24) {
            return error.InvalidWordCount;
        }

        // TODO: Implement BIP-39 word generation
        const words = try allocator.alloc([]const u8, word_count);
        for (words, 0..) |*word, i| {
            _ = i;
            word.* = "word"; // Placeholder
        }

        return .{
            .words = words,
            .allocator = allocator,
        };
    }

    /// Create mnemonic from phrase
    pub fn fromPhrase(allocator: std.mem.Allocator, phrase: []const u8) !Mnemonic {
        // Split by spaces
        var words = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        defer words.deinit(allocator);

        var iter = std.mem.splitScalar(u8, phrase, ' ');
        while (iter.next()) |word| {
            if (word.len > 0) {
                const word_copy = try allocator.dupe(u8, word);
                try words.append(allocator, word_copy);
            }
        }

        return .{
            .words = try words.toOwnedSlice(allocator),
            .allocator = allocator,
        };
    }

    /// Convert to seed (for HD wallet)
    pub fn toSeed(self: Mnemonic, passphrase: []const u8) ![]u8 {
        // BIP-39: PBKDF2-HMAC-SHA512 with 2048 iterations
        // Salt = "mnemonic" + passphrase
        const phrase = try self.toPhrase();
        defer self.allocator.free(phrase);

        var salt = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer salt.deinit(self.allocator);
        try salt.appendSlice(self.allocator, "mnemonic");
        try salt.appendSlice(self.allocator, passphrase);

        // Derive 64-byte seed using PBKDF2-HMAC-SHA512
        var seed: [64]u8 = undefined;
        try std.crypto.pwhash.pbkdf2(
            &seed,
            phrase,
            salt.items,
            2048, // BIP-39 standard iteration count
            std.crypto.auth.hmac.sha2.HmacSha512,
        );

        return try self.allocator.dupe(u8, &seed);
    }

    /// Get phrase as string
    pub fn toPhrase(self: Mnemonic) ![]u8 {
        var phrase = try std.ArrayList(u8).initCapacity(self.allocator, 0);
        defer phrase.deinit(self.allocator);

        for (self.words, 0..) |word, i| {
            if (i > 0) try phrase.append(self.allocator, ' ');
            try phrase.appendSlice(self.allocator, word);
        }

        return phrase.toOwnedSlice(self.allocator);
    }

    /// Free memory
    pub fn deinit(self: *Mnemonic) void {
        for (self.words) |word| {
            self.allocator.free(word);
        }
        self.allocator.free(self.words);
    }
};

// Tests
test "wallet creation from private key" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    var wallet = try Wallet.init(allocator, private_key);

    const addr = try wallet.getAddress();
    try std.testing.expect(!addr.isZero());
}

test "wallet generate" {
    const allocator = std.testing.allocator;

    var wallet = try Wallet.generate(allocator);
    const addr = try wallet.getAddress();
    try std.testing.expect(!addr.isZero());
}

test "wallet sign message" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    var wallet = try Wallet.init(allocator, private_key);

    const message = "Hello, Ethereum!";
    const sig = try wallet.signMessage(message);

    try std.testing.expect(sig.isValid());
}

test "wallet sign hash" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    var wallet = try Wallet.init(allocator, private_key);

    const hash = [_]u8{0xAB} ** 32;
    const sig = try wallet.signHash(hash);

    try std.testing.expect(sig.isValid());
}

test "wallet verify signature" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    var wallet = try Wallet.init(allocator, private_key);

    const hash = [_]u8{0xAB} ** 32;
    const sig = try wallet.signHash(hash);

    const valid = try wallet.verifySignature(hash, sig);
    try std.testing.expect(valid);
}

test "wallet capabilities" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const wallet = try Wallet.init(allocator, private_key);

    const caps = wallet.getCapabilities();
    try std.testing.expect(caps.can_sign_transactions);
    try std.testing.expect(caps.can_sign_messages);
    try std.testing.expect(caps.supports_eip712);
}

test "mnemonic from phrase" {
    const allocator = std.testing.allocator;

    const phrase = "word word word word word word word word word word word word";
    var mnemonic = try Mnemonic.fromPhrase(allocator, phrase);
    defer mnemonic.deinit();

    try std.testing.expectEqual(@as(usize, 12), mnemonic.words.len);
}

test "hd wallet from seed" {
    const allocator = std.testing.allocator;

    const seed = [_]u8{0xAB} ** 32;
    const hd_wallet = try HDWallet.fromSeed(allocator, &seed);

    var wallet = try hd_wallet.deriveChild("m/44'/60'/0'/0/0");
    const addr = try wallet.getAddress();
    try std.testing.expect(!addr.isZero());
}

test "wallet from private key hex" {
    const allocator = std.testing.allocator;

    const hex = "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    var wallet = try Wallet.fromPrivateKeyHex(allocator, hex);

    const addr = try wallet.getAddress();
    try std.testing.expect(!addr.isZero());
}

test "wallet export private key" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const wallet = try Wallet.init(allocator, private_key);

    const exported = try wallet.exportPrivateKey();
    defer allocator.free(exported);

    try std.testing.expect(exported.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, exported, "0x"));
}

test "wallet sign typed data" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    var wallet = try Wallet.init(allocator, private_key);

    const domain_hash = [_]u8{0xAB} ** 32;
    const message_hash = [_]u8{0xCD} ** 32;

    const sig = try wallet.signTypedData(domain_hash, message_hash);
    try std.testing.expect(sig.isValid());
}

test "mnemonic to seed" {
    const allocator = std.testing.allocator;

    const phrase = "word word word word word word word word word word word word";
    var mnemonic = try Mnemonic.fromPhrase(allocator, phrase);
    defer mnemonic.deinit();

    const seed = try mnemonic.toSeed("");
    defer allocator.free(seed);

    try std.testing.expectEqual(@as(usize, 64), seed.len);
}

test "mnemonic to phrase" {
    const allocator = std.testing.allocator;

    const phrase = "word word word word word word word word word word word word";
    var mnemonic = try Mnemonic.fromPhrase(allocator, phrase);
    defer mnemonic.deinit();

    const result = try mnemonic.toPhrase();
    defer allocator.free(result);

    try std.testing.expectEqualStrings(phrase, result);
}
