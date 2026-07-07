//! Zeth - Ethereum library for Zig
//!
//! This library provides primitives, RPC client, and utilities
//! for interacting with Ethereum networks.

const std = @import("std");

// Re-export main modules
pub const primitives = struct {
    pub const Address = @import("primitives/address.zig").Address;
    pub const Hash = @import("primitives/hash.zig").Hash;
    pub const Bytes = @import("primitives/bytes.zig").Bytes;
    pub const Signature = @import("primitives/signature.zig").Signature;

    // u256 Ethereum utility functions
    // Use native `u256` type for values
    // Use these functions for Ethereum-specific conversions:
    pub const u256FromBytes = @import("primitives/uint.zig").u256FromBytes;
    pub const u256ToBytes = @import("primitives/uint.zig").u256ToBytes;
    pub const u256FromHex = @import("primitives/uint.zig").u256FromHex;
    pub const u256ToHex = @import("primitives/uint.zig").u256ToHex;
    pub const u256ToU64 = @import("primitives/uint.zig").u256ToU64;

    pub const Bloom = @import("primitives/bloom.zig").Bloom;
};
pub const types = struct {
    pub const Transaction = @import("types/transaction.zig").Transaction;
    pub const TransactionType = @import("types/transaction.zig").TransactionType;
    pub const Block = @import("types/block.zig").Block;
    pub const BlockHeader = @import("types/block.zig").BlockHeader;
    pub const Receipt = @import("types/receipt.zig").Receipt;
    pub const TransactionStatus = @import("types/receipt.zig").TransactionStatus;
    pub const Log = @import("types/log.zig").Log;
    pub const AccessList = @import("types/access_list.zig").AccessList;
    pub const AccessListEntry = @import("types/access_list.zig").AccessList.AccessListEntry;
    pub const Authorization = @import("types/transaction.zig").Authorization;
    pub const AuthorizationList = @import("types/transaction.zig").AuthorizationList;
};

pub const crypto = struct {
    pub const keccak = @import("crypto/keccak.zig");
    pub const secp256k1 = @import("crypto/secp256k1.zig");
    pub const ecdsa = @import("crypto/ecdsa.zig");
    pub const utils = @import("crypto/utils.zig");

    // Re-export commonly used types
    pub const Keccak256 = keccak.Keccak256;
    pub const PrivateKey = secp256k1.PrivateKey;
    pub const PublicKey = secp256k1.PublicKey;
    pub const Signer = ecdsa.Signer;
    pub const TransactionSigner = ecdsa.TransactionSigner;
};

pub const abi = struct {
    pub const abi_types = @import("abi/types.zig");
    pub const encode = @import("abi/encode.zig");
    pub const decode = @import("abi/decode.zig");
    pub const abi_packed = @import("abi/packed.zig");

    // Re-export commonly used types
    pub const AbiType = abi_types.AbiType;
    pub const AbiValue = abi_types.AbiValue;
    pub const Function = abi_types.Function;
    pub const Event = abi_types.Event;
    pub const Parameter = abi_types.Parameter;
    pub const Encoder = encode.Encoder;
    pub const Decoder = decode.Decoder;
    pub const PackedEncoder = abi_packed.PackedEncoder;
    pub const PackedValue = abi_packed.PackedValue;
    pub const encodeFunctionCall = encode.encodeFunctionCall;
    pub const decodeFunctionReturn = decode.decodeFunctionReturn;
    pub const encodePacked = abi_packed.encodePacked;
    pub const hashPacked = abi_packed.hashPacked;
};

pub const rlp = struct {
    pub const encode = @import("rlp/encode.zig");
    pub const decode = @import("rlp/decode.zig");
    pub const ethereum = @import("rlp/packed.zig");

    // Re-export commonly used types
    pub const Encoder = encode.Encoder;
    pub const Decoder = decode.Decoder;
    pub const RlpItem = encode.RlpItem;
    pub const RlpValue = decode.RlpValue;
    pub const encodeItem = encode.encodeItem;
    pub const encodeList = encode.encodeList;
    pub const encodeBytes = encode.encodeBytes;
    pub const encodeUint = encode.encodeUint;
    pub const decodeValue = decode.decode;
    pub const decodeBytes = decode.decodeBytes;
    pub const decodeList = decode.decodeList;
    pub const decodeUint = decode.decodeUint;
    pub const TransactionEncoder = ethereum.TransactionEncoder;
    pub const EthereumEncoder = ethereum.EthereumEncoder;
    pub const EthereumDecoder = ethereum.EthereumDecoder;
};

pub const providers = struct {
    pub const Provider = @import("providers/provider.zig").Provider;
    pub const HttpProvider = @import("providers/http.zig").HttpProvider;
    pub const WsProvider = @import("providers/ws.zig").WsProvider;
    pub const IpcProvider = @import("providers/ipc.zig").IpcProvider;
    pub const MockProvider = @import("providers/mock.zig").MockProvider;
    pub const Networks = @import("providers/http.zig").Networks;
    pub const SocketPaths = @import("providers/ipc.zig").SocketPaths;
};

pub const rpc = struct {
    pub const client = @import("rpc/client.zig");
    pub const rpc_types = @import("rpc/types.zig");
    pub const eth = @import("rpc/eth.zig");
    pub const net = @import("rpc/net.zig");
    pub const web3 = @import("rpc/web3.zig");
    pub const debug = @import("rpc/debug.zig");

    // Re-export commonly used types
    pub const RpcClient = client.RpcClient;
    pub const HttpTransport = client.HttpTransport;
    pub const EthNamespace = eth.EthNamespace;
    pub const NetNamespace = net.NetNamespace;
    pub const Web3Namespace = web3.Web3Namespace;
    pub const DebugNamespace = debug.DebugNamespace;
    pub const BlockParameter = rpc_types.BlockParameter;
    pub const CallParams = rpc_types.CallParams;
    pub const TransactionParams = rpc_types.TransactionParams;
    pub const FilterOptions = rpc_types.FilterOptions;
};

pub const contract = struct {
    pub const Contract = @import("contract/contract.zig").Contract;
    pub const CallBuilder = @import("contract/call.zig").CallBuilder;
    pub const CallParams = @import("contract/call.zig").CallParams;
    pub const CallResult = @import("contract/call.zig").CallResult;
    pub const callView = @import("contract/call.zig").callView;
    pub const callMutating = @import("contract/call.zig").callMutating;
    pub const DeployBuilder = @import("contract/deploy.zig").DeployBuilder;
    pub const DeployReceipt = @import("contract/deploy.zig").DeployReceipt;
    pub const ParsedEvent = @import("contract/event.zig").ParsedEvent;
    pub const EventFilter = @import("contract/event.zig").EventFilter;
    pub const parseEvent = @import("contract/event.zig").parseEvent;
    pub const parseEvents = @import("contract/event.zig").parseEvents;
    pub const getEventSignatureHash = @import("contract/event.zig").getEventSignatureHash;
};

pub const sol = struct {
    pub const sol_types = @import("sol/types.zig");
    pub const macros = @import("sol/macros.zig");

    // Re-export commonly used types
    pub const SolidityType = sol_types.SolidityType;
    pub const SolidityValue = sol_types.SolidityValue;
    pub const StandardInterface = sol_types.StandardInterface;
    pub const parseType = sol_types.parseType;
    pub const ContractBinding = macros.ContractBinding;
    pub const FunctionCall = macros.FunctionCall;
    pub const EventFilter = macros.EventFilter;
    pub const Erc20Contract = macros.Erc20Contract;
    pub const Erc721Contract = macros.Erc721Contract;
    pub const Erc1155Contract = macros.Erc1155Contract;
    pub const AbiParser = macros.AbiParser;
    pub const ParsedAbi = macros.ParsedAbi;
    pub const Selectors = macros.Selectors;
    pub const ValueConversion = macros.ValueConversion;
};

pub const signer = struct {
    const signer_mod = @import("signer/signer.zig");
    const wallet_mod = @import("signer/wallet.zig");
    const keystore_mod = @import("signer/keystore.zig");
    const ledger_mod = @import("signer/ledger.zig");

    pub const SignerInterface = signer_mod.SignerInterface;
    pub const SignerType = signer_mod.SignerType;
    pub const SignerCapabilities = signer_mod.SignerCapabilities;
    pub const signerInterface = signer_mod.signerInterface;

    pub const Wallet = wallet_mod.Wallet;
    pub const HDWallet = wallet_mod.HDWallet;
    pub const Mnemonic = wallet_mod.Mnemonic;

    pub const Keystore = keystore_mod.Keystore;
    pub const KeystoreVersion = keystore_mod.KeystoreVersion;
    pub const KdfType = keystore_mod.KdfType;
    pub const CipherType = keystore_mod.CipherType;
    pub const ScryptParams = keystore_mod.ScryptParams;
    pub const Pbkdf2Params = keystore_mod.Pbkdf2Params;

    pub const LedgerWallet = ledger_mod.LedgerWallet;
    pub const LedgerModel = ledger_mod.LedgerModel;
    pub const DerivationPath = ledger_mod.DerivationPath;
    pub const APDU = ledger_mod.APDU;
};

// Error handling and reporting
pub const errors = @import("errors.zig");
pub const ZigethError = errors.ZigethError;
pub const ErrorContext = errors.ErrorContext;
pub const ErrorFormatter = errors.ErrorFormatter;
pub const ErrorReporter = errors.ErrorReporter;
pub const RpcErrors = errors.RpcErrors;
pub const TransactionErrors = errors.TransactionErrors;
pub const ContractErrors = errors.ContractErrors;
pub const WalletErrors = errors.WalletErrors;
pub const AccountAbstractionErrors = errors.AccountAbstractionErrors;

pub const utils = struct {
    pub const hex = @import("utils/hex.zig");
    pub const format = @import("utils/format.zig");
    pub const units = @import("utils/units.zig");
    pub const checksum = @import("utils/checksum.zig");
};

/// Cross-platform wall-clock + sleep helpers (0.16 moved std.time.timestamp
/// / std.time.sleep behind std.Io).
pub const time_compat = @import("time_compat.zig");

pub const middleware = struct {
    const gas_mod = @import("middleware/gas.zig");
    const nonce_mod = @import("middleware/nonce.zig");
    const signer_mod = @import("middleware/signer.zig");

    pub const GasStrategy = gas_mod.GasStrategy;
    pub const GasConfig = gas_mod.GasConfig;
    pub const FeeData = gas_mod.FeeData;
    pub const GasMiddleware = gas_mod.GasMiddleware;

    pub const NonceStrategy = nonce_mod.NonceStrategy;
    pub const PendingTransaction = nonce_mod.PendingTransaction;
    pub const NonceMiddleware = nonce_mod.NonceMiddleware;

    pub const SignerConfig = signer_mod.SignerConfig;
    pub const SignerMiddleware = signer_mod.SignerMiddleware;
};

pub const account_abstraction = struct {
    const aa = @import("account_abstraction/account_abstraction.zig");

    // Re-export all account abstraction modules
    pub const types = aa.types;
    pub const bundler = aa.bundler;
    pub const paymaster = aa.paymaster;
    pub const smart_account = aa.smart_account;
    pub const entrypoint = aa.entrypoint;
    pub const gas = aa.gas;
    pub const utils = aa.utils;

    // Re-export commonly used types
    pub const EntryPointVersion = aa.EntryPointVersion;
    pub const UserOperation = aa.UserOperation; // Default: v0.6
    pub const UserOperationV06 = aa.UserOperationV06;
    pub const UserOperationV07 = aa.UserOperationV07;
    pub const UserOperationV08 = aa.UserOperationV08;
    pub const UserOperationJson = aa.UserOperationJson;
    pub const UserOperationReceipt = aa.UserOperationReceipt;
    pub const GasEstimates = aa.GasEstimates;
    pub const PaymasterData = aa.PaymasterData;

    // Re-export clients
    pub const BundlerClient = aa.BundlerClient;
    pub const PaymasterClient = aa.PaymasterClient;
    pub const PaymasterMode = aa.PaymasterMode;
    pub const PaymasterStub = aa.PaymasterStub;
    pub const TokenQuote = aa.TokenQuote;

    // Re-export smart account types
    pub const SmartAccount = aa.SmartAccount;
    pub const AccountFactory = aa.AccountFactory;
    pub const Call = aa.Call;

    // Re-export EntryPoint
    pub const EntryPoint = aa.EntryPoint;
    pub const DepositInfo = aa.DepositInfo;
    pub const ValidationResult = aa.ValidationResult;

    // Re-export gas utilities
    pub const GasEstimator = aa.GasEstimator;
    pub const GasPrices = aa.GasPrices;
    pub const GasOverhead = aa.GasOverhead;

    // Re-export utilities
    pub const UserOpUtils = aa.UserOpUtils;
    pub const UserOpHash = aa.UserOpHash;
    pub const PackedUserOperation = aa.PackedUserOperation;
};

test {
    std.testing.refAllDecls(@This());

    // Primitives
    _ = @import("primitives/address.zig");
    _ = @import("primitives/hash.zig");
    _ = @import("primitives/bytes.zig");
    _ = @import("primitives/signature.zig");
    _ = @import("primitives/uint.zig");
    _ = @import("primitives/bloom.zig");

    // Types
    _ = @import("types/transaction.zig");
    _ = @import("types/block.zig");
    _ = @import("types/receipt.zig");
    _ = @import("types/log.zig");
    _ = @import("types/access_list.zig");

    // Crypto
    _ = @import("crypto/keccak.zig");
    _ = @import("crypto/secp256k1.zig");
    _ = @import("crypto/ecdsa.zig");
    _ = @import("crypto/utils.zig");

    // ABI
    _ = @import("abi/types.zig");
    _ = @import("abi/encode.zig");
    _ = @import("abi/decode.zig");
    _ = @import("abi/packed.zig");

    // RLP
    _ = @import("rlp/encode.zig");
    _ = @import("rlp/decode.zig");
    _ = @import("rlp/packed.zig");

    // Providers
    _ = @import("providers/provider.zig");
    _ = @import("providers/http.zig");
    _ = @import("providers/ws.zig");
    _ = @import("providers/ipc.zig");
    _ = @import("providers/mock.zig");

    // RPC
    _ = @import("rpc/client.zig");
    _ = @import("rpc/types.zig");
    _ = @import("rpc/eth.zig");
    _ = @import("rpc/net.zig");
    _ = @import("rpc/web3.zig");
    _ = @import("rpc/debug.zig");

    // Contract
    _ = @import("contract/contract.zig");
    _ = @import("contract/call.zig");
    _ = @import("contract/deploy.zig");
    _ = @import("contract/event.zig");

    // Sol
    _ = @import("sol/types.zig");
    _ = @import("sol/macros.zig");

    // Signer
    _ = @import("signer/signer.zig");
    _ = @import("signer/wallet.zig");
    _ = @import("signer/keystore.zig");
    _ = @import("signer/ledger.zig");

    // Utils
    _ = @import("utils/hex.zig");
    _ = @import("utils/format.zig");
    _ = @import("utils/units.zig");
    _ = @import("utils/checksum.zig");

    // Middleware
    _ = @import("middleware/gas.zig");
    _ = @import("middleware/nonce.zig");
    _ = @import("middleware/signer.zig");

    // Errors
    _ = @import("errors.zig");
}
