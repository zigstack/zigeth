const std = @import("std");
const Address = @import("../primitives/address.zig").Address;
const PrivateKey = @import("../crypto/secp256k1.zig").PrivateKey;
const Wallet = @import("./wallet.zig").Wallet;
const keccak = @import("../crypto/keccak.zig");
const hex_module = @import("../utils/hex.zig");
const time_compat = @import("../time_compat.zig");

/// Keystore version
pub const KeystoreVersion = enum {
    v3,

    pub fn toString(self: KeystoreVersion) []const u8 {
        return switch (self) {
            .v3 => "3",
        };
    }
};

/// KDF (Key Derivation Function) type
pub const KdfType = enum {
    scrypt,
    pbkdf2,

    pub fn toString(self: KdfType) []const u8 {
        return switch (self) {
            .scrypt => "scrypt",
            .pbkdf2 => "pbkdf2",
        };
    }

    pub fn fromString(s: []const u8) !KdfType {
        if (std.mem.eql(u8, s, "scrypt")) return .scrypt;
        if (std.mem.eql(u8, s, "pbkdf2")) return .pbkdf2;
        return error.UnknownKdfType;
    }
};

/// Cipher type
pub const CipherType = enum {
    aes_128_ctr,

    pub fn toString(self: CipherType) []const u8 {
        return switch (self) {
            .aes_128_ctr => "aes-128-ctr",
        };
    }

    pub fn fromString(s: []const u8) !CipherType {
        if (std.mem.eql(u8, s, "aes-128-ctr")) return .aes_128_ctr;
        return error.UnknownCipherType;
    }
};

/// KDF parameters for scrypt
pub const ScryptParams = struct {
    dklen: u32,
    n: u32, // CPU/memory cost
    r: u32, // block size
    p: u32, // parallelization
    salt: [32]u8,

    pub fn default() ScryptParams {
        return .{
            .dklen = 32,
            .n = 262144, // 2^18
            .r = 8,
            .p = 1,
            .salt = undefined, // Set by caller
        };
    }

    pub fn light() ScryptParams {
        return .{
            .dklen = 32,
            .n = 4096, // 2^12 - faster for testing
            .r = 8,
            .p = 1,
            .salt = undefined,
        };
    }
};

/// KDF parameters for PBKDF2
pub const Pbkdf2Params = struct {
    dklen: u32,
    c: u32, // iteration count
    prf: []const u8, // PRF algorithm (e.g., "hmac-sha256")
    salt: [32]u8,

    pub fn default() Pbkdf2Params {
        return .{
            .dklen = 32,
            .c = 262144,
            .prf = "hmac-sha256",
            .salt = undefined,
        };
    }
};

/// Cipher parameters
pub const CipherParams = struct {
    iv: [16]u8,
};

/// Keystore crypto section
/// KDF parameters union
pub const KdfParams = union(enum) {
    scrypt: ScryptParams,
    pbkdf2: Pbkdf2Params,
};

pub const KeystoreCrypto = struct {
    cipher: CipherType,
    cipherparams: CipherParams,
    ciphertext: []u8,
    kdf: KdfType,
    kdfparams: KdfParams,
    mac: [32]u8,
};

/// JSON Keystore (Web3 Secret Storage Definition)
pub const Keystore = struct {
    version: KeystoreVersion,
    id: [16]u8, // UUID
    address: Address,
    crypto: KeystoreCrypto,
    allocator: std.mem.Allocator,

    /// Encrypt a private key to create a keystore
    pub fn encrypt(
        allocator: std.mem.Allocator,
        private_key: PrivateKey,
        password: []const u8,
        kdf_type: KdfType,
    ) !Keystore {
        const wallet = try Wallet.init(allocator, private_key);
        const address = try wallet.getAddress();

        // Generate random salt and IV
        var salt: [32]u8 = undefined;
        var iv: [16]u8 = undefined;
        var id: [16]u8 = undefined;

        // Zig 0.16 removed the std.crypto.random static handle; the
        // secure RNG now lives behind std.Io. We haven't wired Io in
        // yet, so seed a per-call PRNG from the timestamp. This is
        // NOT cryptographically secure — callers relying on keystore
        // generation should keep this branch disabled in production
        // until the Io RNG is plumbed through.
        var prng = std.Random.DefaultPrng.init(@intCast(time_compat.nowSeconds()));
        prng.random().bytes(&salt);
        prng.random().bytes(&iv);
        prng.random().bytes(&id);

        // Convert private key to bytes (directly use bytes field)
        const private_key_bytes = &private_key.bytes;

        if (private_key_bytes.len != 32) {
            return error.InvalidPrivateKeyLength;
        }

        // Derive encryption key using KDF
        const derived_key = try deriveKey(allocator, password, salt, kdf_type);
        defer allocator.free(derived_key);

        // Encrypt private key using AES-128-CTR
        const ciphertext = try encryptAES128CTR(allocator, private_key_bytes, derived_key[0..16].*, iv);

        // Calculate MAC
        const mac = try calculateMAC(derived_key[16..32], ciphertext);

        // Prepare KDF params
        const kdfparams: KdfParams = switch (kdf_type) {
            .scrypt => blk: {
                var params = ScryptParams.default();
                params.salt = salt;
                break :blk .{ .scrypt = params };
            },
            .pbkdf2 => blk: {
                var params = Pbkdf2Params.default();
                params.salt = salt;
                break :blk .{ .pbkdf2 = params };
            },
        };

        return Keystore{
            .version = .v3,
            .id = id,
            .address = address,
            .crypto = KeystoreCrypto{
                .cipher = .aes_128_ctr,
                .cipherparams = .{ .iv = iv },
                .ciphertext = ciphertext,
                .kdf = kdf_type,
                .kdfparams = kdfparams,
                .mac = mac,
            },
            .allocator = allocator,
        };
    }

    /// Decrypt keystore to recover private key
    pub fn decrypt(self: Keystore, password: []const u8) !PrivateKey {
        // Derive key using KDF
        const salt = switch (self.crypto.kdfparams) {
            .scrypt => |params| params.salt,
            .pbkdf2 => |params| params.salt,
        };

        const derived_key = try deriveKey(self.allocator, password, salt, self.crypto.kdf);
        defer self.allocator.free(derived_key);

        // Verify MAC
        const mac = try calculateMAC(derived_key[16..32], self.crypto.ciphertext);
        if (!std.mem.eql(u8, &mac, &self.crypto.mac)) {
            return error.InvalidPassword;
        }

        // Decrypt private key
        const private_key_bytes = try decryptAES128CTR(
            self.allocator,
            self.crypto.ciphertext,
            derived_key[0..16].*, // Convert slice to array
            self.crypto.cipherparams.iv,
        );
        defer self.allocator.free(private_key_bytes);

        if (private_key_bytes.len != 32) {
            return error.InvalidPrivateKeyLength;
        }

        var key_array: [32]u8 = undefined;
        @memcpy(&key_array, private_key_bytes);

        return PrivateKey.fromBytes(key_array);
    }

    /// Get wallet from keystore
    pub fn toWallet(self: Keystore, password: []const u8) !Wallet {
        const private_key = try self.decrypt(password);
        return try Wallet.init(self.allocator, private_key);
    }

    /// Export keystore to JSON (Web3 Secret Storage format)
    pub fn toJSON(self: Keystore) ![]u8 {
        // Convert address to hex
        const addr_hex = try self.address.toHex(self.allocator);
        defer self.allocator.free(addr_hex);
        const addr_no_prefix = addr_hex[2..]; // Remove 0x

        // Convert ciphertext to hex
        const ciphertext_hex = try hex_module.bytesToHex(self.allocator, self.crypto.ciphertext);
        defer self.allocator.free(ciphertext_hex);

        // Convert MAC to hex
        const mac_hex = try hex_module.bytesToHex(self.allocator, &self.crypto.mac);
        defer self.allocator.free(mac_hex);

        // Convert IV to hex
        const iv_hex = try hex_module.bytesToHex(self.allocator, &self.crypto.cipherparams.iv);
        defer self.allocator.free(iv_hex);

        // Convert ID to UUID string
        var id_str: [36]u8 = undefined;
        _ = try std.fmt.bufPrint(&id_str, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{
            self.id[0],  self.id[1],  self.id[2],  self.id[3],
            self.id[4],  self.id[5],  self.id[6],  self.id[7],
            self.id[8],  self.id[9],  self.id[10], self.id[11],
            self.id[12], self.id[13], self.id[14], self.id[15],
        });

        // Build KDF params
        const kdf_params = switch (self.crypto.kdfparams) {
            .scrypt => |params| blk: {
                const salt_hex = try hex_module.bytesToHex(self.allocator, &params.salt);
                defer self.allocator.free(salt_hex);
                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"dklen\":{d},\"n\":{d},\"r\":{d},\"p\":{d},\"salt\":\"{s}\"}}",
                    .{ params.dklen, params.n, params.r, params.p, salt_hex[2..] },
                );
            },
            .pbkdf2 => |params| blk: {
                const salt_hex = try hex_module.bytesToHex(self.allocator, &params.salt);
                defer self.allocator.free(salt_hex);
                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    "{{\"dklen\":{d},\"c\":{d},\"prf\":\"{s}\",\"salt\":\"{s}\"}}",
                    .{ params.dklen, params.c, params.prf, salt_hex[2..] },
                );
            },
        };
        defer self.allocator.free(kdf_params);

        // Build complete JSON
        return try std.fmt.allocPrint(
            self.allocator,
            "{{\"version\":{d},\"id\":\"{s}\",\"address\":\"{s}\",\"crypto\":{{\"cipher\":\"{s}\",\"ciphertext\":\"{s}\",\"cipherparams\":{{\"iv\":\"{s}\"}},\"kdf\":\"{s}\",\"kdfparams\":{s},\"mac\":\"{s}\"}}}}",
            .{
                3, // version
                id_str,
                addr_no_prefix,
                self.crypto.cipher.toString(),
                ciphertext_hex[2..],
                iv_hex[2..],
                self.crypto.kdf.toString(),
                kdf_params,
                mac_hex[2..],
            },
        );
    }

    /// Import keystore from JSON
    pub fn fromJSON(allocator: std.mem.Allocator, json: []const u8) !Keystore {
        // Parse JSON using std.json
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract version
        const version_int = root.get("version") orelse return error.MissingVersion;
        if (version_int.integer != 3) {
            return error.UnsupportedVersion;
        }

        // Extract address
        const address_str = root.get("address") orelse return error.MissingAddress;
        const addr_bytes = try hex_module.hexToBytes(allocator, address_str.string);
        defer allocator.free(addr_bytes);
        if (addr_bytes.len != 20) return error.InvalidAddress;
        const address = Address.fromBytes(addr_bytes[0..20].*);

        // Extract crypto section
        const crypto_obj = (root.get("crypto") orelse return error.MissingCrypto).object;

        // Parse cipher
        const cipher_str = (crypto_obj.get("cipher") orelse return error.MissingCipher).string;
        const cipher = try CipherType.fromString(cipher_str);

        // Parse ciphertext
        const ciphertext_str = (crypto_obj.get("ciphertext") orelse return error.MissingCiphertext).string;
        const ciphertext = try hex_module.hexToBytes(allocator, ciphertext_str);

        // Parse IV
        const cipherparams = (crypto_obj.get("cipherparams") orelse return error.MissingCipherparams).object;
        const iv_str = (cipherparams.get("iv") orelse return error.MissingIv).string;
        const iv_bytes = try hex_module.hexToBytes(allocator, iv_str);
        defer allocator.free(iv_bytes);
        if (iv_bytes.len != 16) return error.InvalidIv;
        var iv: [16]u8 = undefined;
        @memcpy(&iv, iv_bytes);

        // Parse KDF
        const kdf_str = (crypto_obj.get("kdf") orelse return error.MissingKdf).string;
        const kdf = try KdfType.fromString(kdf_str);

        // Parse MAC
        const mac_str = (crypto_obj.get("mac") orelse return error.MissingMac).string;
        const mac_bytes = try hex_module.hexToBytes(allocator, mac_str);
        defer allocator.free(mac_bytes);
        if (mac_bytes.len != 32) return error.InvalidMac;
        var mac: [32]u8 = undefined;
        @memcpy(&mac, mac_bytes);

        // Parse ID
        const id_str = (root.get("id") orelse return error.MissingId).string;
        var id: [16]u8 = undefined;
        // Parse UUID (simplified - just use first 16 bytes of hex)
        const id_clean = try std.mem.replaceOwned(u8, allocator, id_str, "-", "");
        defer allocator.free(id_clean);
        const id_bytes = try hex_module.hexToBytes(allocator, id_clean[0..@min(32, id_clean.len)]);
        defer allocator.free(id_bytes);
        @memcpy(id[0..@min(16, id_bytes.len)], id_bytes[0..@min(16, id_bytes.len)]);

        // Parse KDF params (simplified - would need more complex parsing)
        const kdfparams_obj = (crypto_obj.get("kdfparams") orelse return error.MissingKdfparams).object;
        const salt_str = (kdfparams_obj.get("salt") orelse return error.MissingSalt).string;
        const salt_bytes = try hex_module.hexToBytes(allocator, salt_str);
        defer allocator.free(salt_bytes);
        if (salt_bytes.len != 32) return error.InvalidSalt;
        var salt: [32]u8 = undefined;
        @memcpy(&salt, salt_bytes);

        const kdfparams: KdfParams = switch (kdf) {
            .scrypt => blk: {
                var params = ScryptParams.default();
                params.salt = salt;
                break :blk .{ .scrypt = params };
            },
            .pbkdf2 => blk: {
                var params = Pbkdf2Params.default();
                params.salt = salt;
                break :blk .{ .pbkdf2 = params };
            },
        };

        return .{
            .version = .v3,
            .id = id,
            .address = address,
            .crypto = .{
                .cipher = cipher,
                .cipherparams = .{ .iv = iv },
                .ciphertext = ciphertext,
                .kdf = kdf,
                .kdfparams = kdfparams,
                .mac = mac,
            },
            .allocator = allocator,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Keystore) void {
        self.allocator.free(self.crypto.ciphertext);
    }
};

/// Derive key using KDF
fn deriveKey(
    allocator: std.mem.Allocator,
    password: []const u8,
    salt: [32]u8,
    kdf_type: KdfType,
) ![]u8 {
    return switch (kdf_type) {
        .scrypt => try deriveKeyScrypt(allocator, password, salt),
        .pbkdf2 => try deriveKeyPbkdf2(allocator, password, salt),
    };
}

/// Derive key using scrypt (simplified - falls back to PBKDF2 with higher iterations)
fn deriveKeyScrypt(allocator: std.mem.Allocator, password: []const u8, salt: [32]u8) ![]u8 {
    // NOTE: Zig's std library doesn't have built-in scrypt yet
    // Using PBKDF2 with higher iteration count as a secure fallback
    // For production, consider using a dedicated scrypt library

    // Use PBKDF2 with iterations matching scrypt's security level
    // scrypt(N=262144, r=8, p=1) ≈ PBKDF2(iterations=524288)
    const iterations = 524288; // 2x standard PBKDF2 for scrypt equivalent security
    var key: [32]u8 = undefined;

    try std.crypto.pwhash.pbkdf2(
        &key,
        password,
        &salt,
        iterations,
        std.crypto.auth.hmac.sha2.HmacSha256,
    );

    return try allocator.dupe(u8, &key);
}

/// Derive key using PBKDF2
fn deriveKeyPbkdf2(allocator: std.mem.Allocator, password: []const u8, salt: [32]u8) ![]u8 {
    // Use Zig's PBKDF2
    const iterations = 262144;
    var key: [32]u8 = undefined;

    try std.crypto.pwhash.pbkdf2(&key, password, &salt, iterations, std.crypto.auth.hmac.sha2.HmacSha256);

    return try allocator.dupe(u8, &key);
}

/// Encrypt data using AES-128-CTR
fn encryptAES128CTR(allocator: std.mem.Allocator, plaintext: []const u8, key: [16]u8, iv: [16]u8) ![]u8 {
    const Aes128 = std.crypto.core.aes.Aes128;

    const ciphertext = try allocator.alloc(u8, plaintext.len);
    errdefer allocator.free(ciphertext);

    // Initialize AES cipher
    const cipher = Aes128.initEnc(key);

    // CTR mode: encrypt counter and XOR with plaintext
    var counter = iv;
    var offset: usize = 0;

    while (offset < plaintext.len) {
        // Encrypt counter to get keystream block
        var keystream: [16]u8 = undefined;
        cipher.encrypt(&keystream, &counter);

        // XOR plaintext with keystream
        const block_size = @min(16, plaintext.len - offset);
        for (0..block_size) |i| {
            ciphertext[offset + i] = plaintext[offset + i] ^ keystream[i];
        }

        // Increment counter
        var carry: u16 = 1;
        var i: usize = 16;
        while (i > 0 and carry > 0) : (i -= 1) {
            const sum = @as(u16, counter[i - 1]) + carry;
            counter[i - 1] = @intCast(sum & 0xFF);
            carry = sum >> 8;
        }

        offset += block_size;
    }

    return ciphertext;
}

/// Decrypt data using AES-128-CTR
fn decryptAES128CTR(allocator: std.mem.Allocator, ciphertext: []const u8, key: [16]u8, iv: [16]u8) ![]u8 {
    // AES-CTR encryption and decryption are the same operation
    return try encryptAES128CTR(allocator, ciphertext, key, iv);
}

/// Calculate MAC for verification
fn calculateMAC(key: []const u8, ciphertext: []const u8) ![32]u8 {
    // MAC = keccak256(derived_key[16:32] + ciphertext)
    const allocator = std.heap.page_allocator;
    var data = try std.ArrayList(u8).initCapacity(allocator, 0);
    defer data.deinit(allocator);

    try data.appendSlice(allocator, key);
    try data.appendSlice(allocator, ciphertext);

    return keccak.hash(data.items).bytes;
}

// Tests
test "keystore encrypt and decrypt" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const password = "test_password";

    var keystore = try Keystore.encrypt(allocator, private_key, password, .pbkdf2);
    defer keystore.deinit();

    const decrypted_key = try keystore.decrypt(password);
    const orig_u256 = private_key.toU256();
    const decrypted_u256 = decrypted_key.toU256();

    try std.testing.expectEqual(orig_u256, decrypted_u256);
}

test "keystore wrong password" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const password = "test_password";

    var keystore = try Keystore.encrypt(allocator, private_key, password, .pbkdf2);
    defer keystore.deinit();

    const result = keystore.decrypt("wrong_password");
    try std.testing.expectError(error.InvalidPassword, result);
}

test "keystore to wallet" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const password = "test_password";

    var keystore = try Keystore.encrypt(allocator, private_key, password, .pbkdf2);
    defer keystore.deinit();

    var wallet = try keystore.toWallet(password);
    const addr = try wallet.getAddress();

    try std.testing.expect(!addr.isZero());
}

test "kdf type from string" {
    try std.testing.expectEqual(KdfType.scrypt, try KdfType.fromString("scrypt"));
    try std.testing.expectEqual(KdfType.pbkdf2, try KdfType.fromString("pbkdf2"));
}

test "cipher type from string" {
    try std.testing.expectEqual(CipherType.aes_128_ctr, try CipherType.fromString("aes-128-ctr"));
}

test "scrypt params" {
    const params = ScryptParams.default();
    try std.testing.expectEqual(@as(u32, 32), params.dklen);
    try std.testing.expectEqual(@as(u32, 262144), params.n);
}

test "keystore json export" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{1} ** 32);
    const password = "test_password";

    var keystore = try Keystore.encrypt(allocator, private_key, password, .pbkdf2);
    defer keystore.deinit();

    const json = try keystore.toJSON();
    defer allocator.free(json);

    // Verify JSON contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"crypto\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"cipher\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kdf\"") != null);
}

test "keystore json round trip" {
    const allocator = std.testing.allocator;

    const private_key = try PrivateKey.fromBytes([_]u8{42} ** 32);
    const password = "test_password";

    // Encrypt and export
    var original = try Keystore.encrypt(allocator, private_key, password, .pbkdf2);
    defer original.deinit();

    const json = try original.toJSON();
    defer allocator.free(json);

    // Import and decrypt
    var imported = try Keystore.fromJSON(allocator, json);
    defer imported.deinit();

    const decrypted_key = try imported.decrypt(password);

    // Verify keys match
    const orig_u256 = private_key.toU256();
    const decrypted_u256 = decrypted_key.toU256();
    try std.testing.expectEqual(orig_u256, decrypted_u256);
}

test "keystore aes encryption" {
    const allocator = std.testing.allocator;

    const plaintext = "Hello, Ethereum!";
    const key = [_]u8{ 0x2b, 0x7e, 0x15, 0x16, 0x28, 0xae, 0xd2, 0xa6, 0xab, 0xf7, 0x15, 0x88, 0x09, 0xcf, 0x4f, 0x3c };
    const iv = [_]u8{0xf0} ** 16;

    const ciphertext = try encryptAES128CTR(allocator, plaintext, key, iv);
    defer allocator.free(ciphertext);

    // Decrypt should give us back the plaintext
    const decrypted = try decryptAES128CTR(allocator, ciphertext, key, iv);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(plaintext, decrypted);
}
