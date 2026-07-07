/// Centralized error handling for Zigeth
/// Provides standardized error sets and formatting utilities
const std = @import("std");

/// Core Zigeth error set - common errors across all modules
pub const ZigethError = error{
    // General errors
    OutOfMemory,
    Unexpected,
    InvalidInput,
    InvalidState,
    NotImplemented,

    // Network errors
    NetworkError,
    ConnectionFailed,
    Timeout,
    InvalidResponse,

    // RPC errors
    RpcError,
    JsonRpcError,
    MissingResult,
    InvalidJsonRpcResponse,

    // Blockchain errors
    BlockNotFound,
    TransactionNotFound,
    ReceiptNotFound,
    ContractNotFound,

    // Validation errors
    InvalidAddress,
    InvalidHash,
    InvalidSignature,
    InvalidTransaction,
    InvalidBlock,

    // Data errors
    InvalidHex,
    InvalidHexLength,
    InvalidEncoding,
    InvalidDecoding,

    // Crypto errors
    InvalidPrivateKey,
    InvalidPublicKey,
    SigningFailed,
    VerificationFailed,

    // Wallet errors
    InvalidMnemonic,
    InvalidKeystore,
    InvalidPassword,
    WalletLocked,

    // Smart contract errors
    ContractCallFailed,
    ContractDeployFailed,
    AbiEncodingFailed,
    AbiDecodingFailed,

    // Account Abstraction errors
    InvalidUserOperation,
    InvalidEntryPoint,
    InvalidPaymaster,
    InvalidBundler,
    PaymasterRejected,
    BundlerRejected,
    UserOperationReverted,

    // Configuration errors
    MissingConfiguration,
    InvalidConfiguration,
    NoRpcClient,

    // Authorization errors
    Unauthorized,
    InsufficientFunds,
    GasTooLow,
    NonceTooLow,
};

/// RPC-specific errors with codes
pub const RpcErrorCode = enum(i64) {
    parse_error = -32700,
    invalid_request = -32600,
    method_not_found = -32601,
    invalid_params = -32602,
    internal_error = -32603,

    // ERC-4337 specific
    user_operation_rejected = -32500,
    paymaster_rejected = -32501,
    opcode_violation = -32502,
    out_of_time_range = -32503,
    throttled_or_banned = -32504,
    stake_too_low = -32505,
    unsupported_aggregator = -32506,
    invalid_signature = -32507,

    // Custom server errors
    transaction_underpriced = -32000,
    insufficient_funds = -32001,
    nonce_too_low = -32002,
    intrinsic_gas_too_low = -32003,

    pub fn toError(self: RpcErrorCode) ZigethError {
        return switch (self) {
            .invalid_request => ZigethError.InvalidInput,
            .method_not_found => ZigethError.NotImplemented,
            .invalid_params => ZigethError.InvalidInput,
            .user_operation_rejected, .paymaster_rejected => ZigethError.PaymasterRejected,
            .invalid_signature => ZigethError.InvalidSignature,
            .insufficient_funds => ZigethError.InsufficientFunds,
            .nonce_too_low => ZigethError.NonceTooLow,
            .intrinsic_gas_too_low => ZigethError.GasTooLow,
            else => ZigethError.RpcError,
        };
    }

    pub fn toString(self: RpcErrorCode) []const u8 {
        return switch (self) {
            .parse_error => "Parse error",
            .invalid_request => "Invalid request",
            .method_not_found => "Method not found",
            .invalid_params => "Invalid params",
            .internal_error => "Internal error",
            .user_operation_rejected => "UserOperation rejected",
            .paymaster_rejected => "Paymaster rejected",
            .opcode_violation => "Opcode violation",
            .out_of_time_range => "Out of time range",
            .throttled_or_banned => "Throttled or banned",
            .stake_too_low => "Stake too low",
            .unsupported_aggregator => "Unsupported aggregator",
            .invalid_signature => "Invalid signature",
            .transaction_underpriced => "Transaction underpriced",
            .insufficient_funds => "Insufficient funds",
            .nonce_too_low => "Nonce too low",
            .intrinsic_gas_too_low => "Gas too low",
        };
    }
};

/// Error context for better debugging
pub const ErrorContext = struct {
    module: []const u8,
    operation: []const u8,
    details: ?[]const u8 = null,
    code: ?i64 = null,

    pub fn init(module: []const u8, operation: []const u8) ErrorContext {
        return .{
            .module = module,
            .operation = operation,
        };
    }

    pub fn withDetails(self: ErrorContext, details: []const u8) ErrorContext {
        return .{
            .module = self.module,
            .operation = self.operation,
            .details = details,
            .code = self.code,
        };
    }

    pub fn withCode(self: ErrorContext, code: i64) ErrorContext {
        return .{
            .module = self.module,
            .operation = self.operation,
            .details = self.details,
            .code = code,
        };
    }
};

/// Format error for display
pub fn formatError(
    allocator: std.mem.Allocator,
    err: anyerror,
    context: ?ErrorContext,
) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    if (context) |ctx| {
        try result.print(allocator, "[{s}] ", .{ctx.module});

        if (ctx.code) |code| {
            try result.print(allocator, "Error {}: ", .{code});
        }

        try result.print(allocator, "{s} failed: {s}", .{ ctx.operation, @errorName(err) });

        if (ctx.details) |details| {
            try result.print(allocator, "\n  Details: {s}", .{details});
        }
    } else {
        try result.print(allocator, "Error: {s}", .{@errorName(err)});
    }

    return try result.toOwnedSlice(allocator);
}

/// Log error with context
pub fn logError(
    err: anyerror,
    context: ?ErrorContext,
) void {
    if (context) |ctx| {
        std.log.err("[{s}] {s} failed: {s}", .{ ctx.module, ctx.operation, @errorName(err) });
        if (ctx.details) |details| {
            std.log.err("  Details: {s}", .{details});
        }
        if (ctx.code) |code| {
            std.log.err("  Code: {}", .{code});
        }
    } else {
        std.log.err("Error: {s}", .{@errorName(err)});
    }
}

/// Error result type for operations that may fail
pub fn ErrorResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: struct {
            error_type: anyerror,
            context: ErrorContext,
        },

        pub fn isOk(self: @This()) bool {
            return switch (self) {
                .ok => true,
                .err => false,
            };
        }

        pub fn unwrap(self: @This()) !T {
            return switch (self) {
                .ok => |value| value,
                .err => |e| e.error_type,
            };
        }

        pub fn unwrapOr(self: @This(), default: T) T {
            return switch (self) {
                .ok => |value| value,
                .err => default,
            };
        }
    };
}

/// Module-specific error sets
pub const RpcErrors = error{
    // Connection
    ConnectionFailed,
    Timeout,
    NetworkError,

    // Protocol
    InvalidJsonRpcResponse,
    JsonRpcError,
    MissingResult,
    InvalidResponse,

    // Method-specific
    MethodNotFound,
    InvalidParams,
    InternalError,
};

pub const TransactionErrors = error{
    InvalidTransaction,
    InvalidNonce,
    NonceTooLow,
    GasTooLow,
    InsufficientFunds,
    TransactionUnderpriced,
    InvalidChainId,
    InvalidSignature,
};

pub const ContractErrors = error{
    ContractNotFound,
    ContractCallFailed,
    ContractDeployFailed,
    AbiEncodingFailed,
    AbiDecodingFailed,
    InvalidFunctionSelector,
    InvalidEventSignature,
};

pub const WalletErrors = error{
    InvalidPrivateKey,
    InvalidMnemonic,
    InvalidKeystore,
    InvalidPassword,
    WalletLocked,
    SigningFailed,
};

pub const AccountAbstractionErrors = error{
    InvalidUserOperation,
    InvalidEntryPoint,
    InvalidPaymaster,
    InvalidBundler,
    InvalidSender,
    InvalidCallGasLimit,
    InvalidVerificationGasLimit,
    InvalidMaxFeePerGas,
    InvalidPaymasterData,
    PaymasterRejected,
    BundlerRejected,
    UserOperationReverted,
    NoRpcClient,
};

/// Error formatter for pretty printing
pub const ErrorFormatter = struct {
    allocator: std.mem.Allocator,
    use_colors: bool,

    pub fn init(allocator: std.mem.Allocator, use_colors: bool) ErrorFormatter {
        return .{
            .allocator = allocator,
            .use_colors = use_colors,
        };
    }

    /// Format error as JSON
    pub fn toJson(
        self: ErrorFormatter,
        err: anyerror,
        context: ?ErrorContext,
    ) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, "{");
        try result.appendSlice(self.allocator, "\"error\":\"");
        try result.appendSlice(self.allocator, @errorName(err));
        try result.appendSlice(self.allocator, "\"");

        if (context) |ctx| {
            try result.appendSlice(self.allocator, ",\"module\":\"");
            try result.appendSlice(self.allocator, ctx.module);
            try result.appendSlice(self.allocator, "\",\"operation\":\"");
            try result.appendSlice(self.allocator, ctx.operation);
            try result.appendSlice(self.allocator, "\"");

            if (ctx.details) |details| {
                try result.appendSlice(self.allocator, ",\"details\":\"");
                try result.appendSlice(self.allocator, details);
                try result.appendSlice(self.allocator, "\"");
            }

            if (ctx.code) |code| {
                const code_str = try std.fmt.allocPrint(self.allocator, ",\"code\":{}", .{code});
                defer self.allocator.free(code_str);
                try result.appendSlice(self.allocator, code_str);
            }
        }

        try result.appendSlice(self.allocator, "}");
        return try result.toOwnedSlice(self.allocator);
    }

    /// Format error as human-readable text
    pub fn toText(
        self: ErrorFormatter,
        err: anyerror,
        context: ?ErrorContext,
    ) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);
        const a = self.allocator;

        if (self.use_colors) {
            try result.appendSlice(a, "\x1b[31m"); // Red
        }

        try result.appendSlice(a, "❌ Error");

        if (context) |ctx| {
            try result.print(a, " in {s}.{s}", .{ ctx.module, ctx.operation });
        }

        if (self.use_colors) {
            try result.appendSlice(a, "\x1b[0m"); // Reset
        }

        try result.print(a, ": {s}\n", .{@errorName(err)});

        if (context) |ctx| {
            if (ctx.code) |code| {
                try result.print(a, "   Code: {}\n", .{code});
            }
            if (ctx.details) |details| {
                try result.print(a, "   Details: {s}\n", .{details});
            }
        }

        return try result.toOwnedSlice(a);
    }

    /// Format error as structured log entry
    pub fn toLog(
        self: ErrorFormatter,
        err: anyerror,
        context: ?ErrorContext,
    ) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(self.allocator);
        const a = self.allocator;

        try result.appendSlice(a, "[ERROR] ");
        try result.appendSlice(a, @errorName(err));

        if (context) |ctx| {
            try result.print(a, " module={s} operation={s}", .{ ctx.module, ctx.operation });

            if (ctx.code) |code| {
                try result.print(a, " code={}", .{code});
            }

            if (ctx.details) |details| {
                try result.print(a, " details=\"{s}\"", .{details});
            }
        }

        return try result.toOwnedSlice(a);
    }
};

/// Helper macro-like functions for common error patterns
/// Wrap an error with context
pub fn wrapError(
    err: anyerror,
    context: ErrorContext,
) anyerror {
    logError(err, context);
    return err;
}

/// Assert condition or return error with context
pub fn assertOrError(
    condition: bool,
    err: anyerror,
    context: ErrorContext,
) !void {
    if (!condition) {
        logError(err, context);
        return err;
    }
}

/// Try operation and log error on failure
pub fn tryWithContext(
    comptime T: type,
    operation: anyerror!T,
    context: ErrorContext,
) !T {
    return operation catch |err| {
        logError(err, context);
        return err;
    };
}

/// Error recovery utilities
pub const ErrorRecovery = struct {
    /// Retry an operation with exponential backoff
    pub fn retryWithBackoff(
        comptime T: type,
        operation: anytype,
        max_retries: u32,
        initial_delay_ms: u64,
    ) !T {
        var retries: u32 = 0;
        var delay_ms = initial_delay_ms;

        while (retries < max_retries) : (retries += 1) {
            if (operation()) |result| {
                return result;
            } else |err| {
                if (retries == max_retries - 1) {
                    return err;
                }

                std.log.warn("Operation failed (attempt {}/{}): {s}, retrying in {}ms", .{
                    retries + 1,
                    max_retries,
                    @errorName(err),
                    delay_ms,
                });

                // std.time.sleep was removed in Zig 0.16; use libc.
                var req: std.c.timespec = .{
                    .sec = @intCast(delay_ms / 1000),
                    .nsec = @intCast((delay_ms % 1000) * std.time.ns_per_ms),
                };
                _ = std.c.nanosleep(&req, null);
                delay_ms *= 2; // Exponential backoff
            }
        }

        unreachable;
    }

    /// Try operation with fallback
    pub fn tryWithFallback(
        comptime T: type,
        primary: anyerror!T,
        fallback: anyerror!T,
    ) !T {
        return primary catch |err| {
            std.log.warn("Primary operation failed: {s}, trying fallback", .{@errorName(err)});
            return fallback;
        };
    }
};

/// Error reporting for production environments
///
/// Zig 0.16 removed the std.fs.File API this reporter used to write
/// through; the log_file sink is a no-op until it's ported to the
/// new Io-based file API. Callers still get stderr logging via logError.
pub const ErrorReporter = struct {
    allocator: std.mem.Allocator,
    log_file: ?*anyopaque,

    pub fn init(allocator: std.mem.Allocator, log_file: ?*anyopaque) ErrorReporter {
        return .{
            .allocator = allocator,
            .log_file = log_file,
        };
    }

    pub fn deinit(_: *ErrorReporter) void {}

    /// Report error to log file
    pub fn report(
        self: *ErrorReporter,
        err: anyerror,
        context: ErrorContext,
    ) !void {
        _ = self;
        // Log-file sink disabled during Zig 0.16 migration; stderr only.
        logError(err, context);
    }

    /// Report with stack trace (debug builds)
    pub fn reportWithTrace(
        self: *ErrorReporter,
        err: anyerror,
        context: ErrorContext,
    ) !void {
        try self.report(err, context);

        // In debug builds, print stack trace
        if (@import("builtin").mode == .Debug) {
            std.debug.dumpCurrentStackTrace(@returnAddress());
        }
    }
};

/// Helper for common patterns
pub const Helpers = struct {
    /// Check if error is network-related
    pub fn isNetworkError(err: anyerror) bool {
        return err == error.NetworkError or
            err == error.ConnectionFailed or
            err == error.Timeout;
    }

    /// Check if error is RPC-related
    pub fn isRpcError(err: anyerror) bool {
        return err == error.RpcError or
            err == error.JsonRpcError or
            err == error.InvalidJsonRpcResponse;
    }

    /// Check if error is validation-related
    pub fn isValidationError(err: anyerror) bool {
        return err == error.InvalidAddress or
            err == error.InvalidHash or
            err == error.InvalidSignature or
            err == error.InvalidTransaction;
    }

    /// Check if error is retryable
    pub fn isRetryable(err: anyerror) bool {
        return isNetworkError(err) or
            err == error.Timeout or
            err == error.NonceTooLow;
    }

    /// Get user-friendly error message
    pub fn getUserMessage(err: anyerror) []const u8 {
        return switch (err) {
            error.NetworkError, error.ConnectionFailed => "Network connection failed. Please check your internet connection.",
            error.Timeout => "Request timed out. Please try again.",
            error.InsufficientFunds => "Insufficient funds for transaction.",
            error.NonceTooLow => "Transaction nonce is too low. Please refresh and try again.",
            error.GasTooLow => "Gas limit is too low for this transaction.",
            error.InvalidAddress => "Invalid Ethereum address format.",
            error.InvalidPrivateKey => "Invalid private key format.",
            error.PaymasterRejected => "Paymaster rejected the UserOperation.",
            error.BundlerRejected => "Bundler rejected the UserOperation.",
            error.ContractNotFound => "Smart contract not found at the specified address.",
            else => "An unexpected error occurred.",
        };
    }
};

test "error formatting" {
    const allocator = std.testing.allocator;

    const ctx = ErrorContext.init("RPC", "eth_getBlockByNumber")
        .withCode(-32000)
        .withDetails("Block not found");

    const formatter = ErrorFormatter.init(allocator, false);

    // Test JSON format
    const json = try formatter.toJson(error.BlockNotFound, ctx);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "BlockNotFound") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "RPC") != null);

    // Test text format
    const text = try formatter.toText(error.BlockNotFound, ctx);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "BlockNotFound") != null);

    // Test log format
    const log = try formatter.toLog(error.BlockNotFound, ctx);
    defer allocator.free(log);
    try std.testing.expect(std.mem.indexOf(u8, log, "[ERROR]") != null);
}

test "error helpers" {
    try std.testing.expect(Helpers.isNetworkError(error.NetworkError));
    try std.testing.expect(Helpers.isRpcError(error.JsonRpcError));
    try std.testing.expect(Helpers.isValidationError(error.InvalidAddress));
    try std.testing.expect(Helpers.isRetryable(error.Timeout));

    const msg = Helpers.getUserMessage(error.InsufficientFunds);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Insufficient funds") != null);
}
