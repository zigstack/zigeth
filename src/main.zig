//! Zigeth CLI - Command line interface for Ethereum interactions
const std = @import("std");
const zigeth = @import("zigeth");

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "version")) {
        std.debug.print("zigeth v0.1.0\n", .{});
    } else if (std.mem.eql(u8, command, "help")) {
        printUsage();
    } else if (std.mem.eql(u8, command, "address")) {
        try handleAddressCommand(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Zigeth - Ethereum library and CLI tool
        \\
        \\Usage: zigeth <command> [options]
        \\
        \\Commands:
        \\  version              Show version information
        \\  help                 Show this help message
        \\  address <command>    Address utilities
        \\
        \\Address commands:
        \\  create               Create a new random address
        \\  checksum <address>   Convert address to checksummed format
        \\
        \\Examples:
        \\  zigeth version
        \\  zigeth address create
        \\
    , .{});
}

fn handleAddressCommand(allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len == 0) {
        std.debug.print("Error: address command requires a subcommand\n", .{});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "create")) {
        // Create a zero address for demonstration
        const addr = zigeth.primitives.Address.fromBytes([_]u8{0} ** 20);
        const hex_str = try addr.toHex(allocator);
        defer allocator.free(hex_str);
        std.debug.print("Address: {s}\n", .{hex_str});
    } else if (std.mem.eql(u8, subcommand, "checksum")) {
        if (args.len < 2) {
            std.debug.print("Error: checksum requires an address argument\n", .{});
            return;
        }
        // This is a placeholder - checksum implementation would go here
        std.debug.print("Checksum not yet implemented\n", .{});
    } else {
        std.debug.print("Unknown address subcommand: {s}\n", .{subcommand});
    }
}

test "address creation" {
    const addr = zigeth.primitives.Address.fromBytes([_]u8{0} ** 20);
    try std.testing.expect(addr.isZero());
}

test "address hex conversion" {
    const allocator = std.testing.allocator;

    const addr = zigeth.primitives.Address.fromBytes([_]u8{ 0xde, 0xad, 0xbe, 0xef } ++ [_]u8{0} ** 16);
    const hex_str = try addr.toHex(allocator);
    defer allocator.free(hex_str);

    try std.testing.expect(std.mem.startsWith(u8, hex_str, "0xdeadbeef"));
}
