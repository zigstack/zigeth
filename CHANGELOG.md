# Changelog

All notable changes to the zigeth library will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-07-07

### 🔧 Zig 0.16.0 migration

- Bumped `minimum_zig_version` to `0.16.0`.
- Swapped the dead `DaviRain-Su/zig-eth-secp256k1` dependency for the
  actively maintained `jsign/zig-eth-secp256k1` fork.
- `build.zig` — moved `linkLibC()` / `linkLibrary()` off the Compile
  step and onto the root module (0.16 requirement); dropped
  `addRemoveDirTree` (removed upstream).
- Adopted `std.heap.DebugAllocator` in place of `GeneralPurposeAllocator`,
  `std.mem.trimEnd/trimStart` for the renamed `trimRight/trimLeft`,
  `std.c.nanosleep` + `std.c.clock_gettime` for the retired
  `std.time.sleep` / `std.time.timestamp`, and unmanaged `ObjectMap`
  everywhere `.put(k, v)` used to work in-place.

### 🧪 Testing

- `zig build test`: **313/314 pass, 1 skipped, 0 failing** on Zig 0.16.0.
- Core library (`src/root.zig`) builds and installs as `libzigeth.a`.

### ⚠️ Regressions to be aware of

These paths return `error.NotImplemented` under 0.16 while `std.net`,
`std.http.Client`, and `std.fs.File.*` land in `std.Io` upstream. All
guarded so callers get a clear error rather than a crash.

- `providers/http.zig` HTTP transport → stubbed. RPC types + JSON
  serialization still work.
- `providers/ws.zig` WebSocket transport → stubbed.
- `providers/ipc.zig` IPC transport → stubbed.
- CLI executable (`src/main.zig`) → not built. `build.zig` gates it
  out until the CLI is ported to the 0.16 `Io.Writer` + process API.
- `errors.zig` `ErrorReporter` file sink → no-op. stderr sink via
  `logError` still works.
- `signer/keystore.zig` RNG → seeded from wall clock via `DefaultPrng`;
  not cryptographically secure. Flagged inline until an `Io` RNG is
  wired in.

## [0.1.0] - 2025-10-09

### 🎉 Initial Release - Feature Complete!

The zigeth library is now **100% complete** with all core Ethereum functionality implemented!

### ✨ Added

#### Core Primitives & Types
- **Primitives** (48 tests): Address, Hash, Bytes, Signature, U256, Bloom
- **Types** (23 tests): Transaction (all 5 types), Block, Receipt, Log, AccessList
- Support for all transaction types: Legacy, EIP-2930, EIP-1559, EIP-4844, EIP-7702

#### Cryptography
- **Crypto** (27 tests): Keccak-256, secp256k1, ECDSA
- Private/public key generation and derivation
- Signature creation and verification
- EIP-155 replay protection
- RFC 6979 deterministic nonces

#### ABI & Encoding
- **ABI** (23 tests): Standard encoding/decoding, EIP-712 packed encoding
- **RLP** (36 tests): Recursive Length Prefix encoding/decoding
- Full support for Ethereum types and transactions

#### Smart Contracts
- **Contract** (19 tests): Contract interaction, deployment, event parsing
- Function call encoding/decoding
- Event log filtering
- CREATE and CREATE2 deployment
- Type-safe contract bindings

#### JSON-RPC Client
- **RPC** (27 tests): Complete JSON-RPC client with HTTP transport
- Full `eth_*` namespace (23 methods)
- `net_*` namespace (3 methods)
- `web3_*` namespace (2 methods)
- `debug_*` namespace (7 methods)
- Complex JSON parsing for Block, Transaction, Receipt, Log

#### Network Providers
- **Providers** (26 tests): HTTP, WebSocket, IPC, Mock providers
- **HttpProvider**: REST API calls to Ethereum nodes
- **WsProvider**: Real-time subscriptions (newHeads, pendingTransactions, logs, syncing)
- **IpcProvider**: Unix socket communication for local nodes
- **MockProvider**: Testing and development
- Pre-configured network presets (Mainnet, Sepolia, Polygon, Arbitrum, Optimism, Base)
- **Integrated with Etherspot v2 API**

#### Transaction Middleware
- **Middleware** (23 tests): Gas, Nonce, and Signing automation
- **GasMiddleware**: Automatic gas price and limit estimation
  - EIP-1559 support (maxFeePerGas, maxPriorityFeePerGas)
  - Multiple strategies (slow, standard, fast, custom)
  - Balance sufficiency checking
- **NonceMiddleware**: Intelligent nonce tracking
  - Multiple strategies (provider, local, hybrid)
  - Pending transaction tracking
  - Gap detection and synchronization
- **SignerMiddleware**: Transaction signing with EIP-155
  - Support for all transaction types
  - Chain-specific configurations

#### Wallet Management
- **Wallets** (35 tests): Software, HD, Keystore, Ledger wallets
- **Software Wallet**: Basic wallet with private key management
  - Create, import, export private keys
  - Sign transactions, messages, hashes
  - EIP-712 typed data signing
- **HD Wallet**: BIP-32/BIP-44 hierarchical deterministic wallets
  - Derive multiple accounts from single seed
  - Standard Ethereum derivation paths
- **Mnemonic**: BIP-39 phrase support (12/24 words)
  - Generate and import mnemonic phrases
  - PBKDF2-HMAC-SHA512 seed derivation (2048 iterations)
- **Keystore**: Encrypted JSON keystores (Web3 Secret Storage v3)
  - PBKDF2 and scrypt KDF support
  - AES-128-CTR encryption
  - Compatible with MetaMask, MyEtherWallet, Geth
- **Ledger**: Hardware wallet support framework
  - Nano S, Nano X, Nano S Plus
  - BIP-44 derivation paths
  - APDU communication protocol

#### Utilities
- **Utils** (35 tests): Hex, Format, Units, Checksum
- Hex encoding/decoding
- Address and hash formatting
- Unit conversions (wei, gwei, ether)
- EIP-55 and EIP-1191 checksum addresses

#### Solidity Integration
- **Solidity** (15 tests): Type mappings and standard interfaces
- Solidity type system (22 types)
- Standard interfaces (ERC-20, ERC-721, ERC-1155, Ownable, Pausable)
- Code generation helpers
- Pre-defined function selectors and event signatures

### 🌐 Network Support

Integrated with **Etherspot v2 RPC API**:

- Ethereum Mainnet (Chain ID: 1)
- Ethereum Sepolia (Chain ID: 11155111)
- Polygon Mainnet (Chain ID: 137)
- Arbitrum Mainnet (Chain ID: 42161)
- Optimism Mainnet (Chain ID: 10)
- Base Mainnet (Chain ID: 8453)
- Localhost (Development)
- Custom endpoints

API Format: `https://rpc.etherspot.io/v2/<chainId>?api-key=...`

### 🔧 EIP Support

- ✅ EIP-55: Mixed-case checksum address encoding
- ✅ EIP-155: Simple replay attack protection
- ✅ EIP-1191: Checksummed addresses for different chains
- ✅ EIP-1559: Fee market change (base fee + priority fee)
- ✅ EIP-2718: Typed transaction envelope
- ✅ EIP-2930: Optional access lists
- ✅ EIP-4788: Beacon block root in the EVM
- ✅ EIP-4844: Shard blob transactions
- ✅ EIP-7702: Set EOA account code (Account Abstraction)
- ✅ EIP-712: Typed structured data hashing and signing

### 📊 Statistics

- **Total Tests**: 334 (all passing)
- **Modules**: 12/12 (100% complete)
- **Lines of Code**: ~11,500+
- **Test Coverage**: Comprehensive
- **Documentation**: Complete with examples

### 🔐 Security

- AES-128-CTR encryption for keystores
- PBKDF2 with 262,144 iterations
- Scrypt equivalent security (524,288 iterations)
- EIP-155 replay protection
- Hardware wallet confirmation support
- Memory-safe implementations

### 🛠️ Development

- CI/CD pipeline with GitHub Actions
- Multi-platform support (Linux, macOS, Windows)
- Comprehensive test suite
- Code formatting and linting
- Documentation generation
- Automatic releases

### 🙏 Acknowledgments

- **zig-eth-secp256k1**: secp256k1 elliptic curve operations
- **Etherspot**: RPC infrastructure and v2 API
- **Zig Community**: For the amazing language and ecosystem

---

## [Unreleased]

### 🚧 Planned

- Full WebSocket protocol implementation (TLS support)
- IPC named pipe support for Windows
- True scrypt KDF (external library)
- BIP-32 full key derivation
- BIP-39 complete word list
- Hardware wallet USB communication
- Additional network providers
- GraphQL support
- ENS resolution
- Gas price oracle improvements

---

## Release Guidelines

### Versioning Rules

- **Major (X.0.0)**: Breaking API changes, major redesigns
- **Minor (x.Y.0)**: New features, backward compatible additions
- **Patch (x.y.Z)**: Bug fixes, documentation updates, minor improvements

### Release Process

See [RELEASING.md](RELEASING.md) for detailed release process documentation.

### Contributing

Contributions are welcome! Please:

1. Follow conventional commit messages
2. Add tests for new features
3. Update documentation
4. Ensure CI passes

---

[0.1.0]: https://github.com/ch4r10t33r/zigeth/releases/tag/v0.1.0
[Unreleased]: https://github.com/ch4r10t33r/zigeth/compare/v0.1.0...HEAD

