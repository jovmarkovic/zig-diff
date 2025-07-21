const std = @import("std");
const rm = @import("remove_lines_with_marker.zig");
const compare = @import("compare.zig");

const FileBuffers = struct {
    buf1: []u8,
    buf2: []u8,
};

const help_msg =
    \\Usage: {s} [options] <file1> <file2>
    \\
    \\Options:
    \\  -m, --marker <text>     Remove lines starting with this marker (quotes allowed)
    \\  -s, --skip-empty        Remove empty lines from comparison
    \\  -m '' -s, --skip-empty  Remove only empty lines
    \\  -h, --help              Show this help message
;

fn readTwoFiles(
    allocator: std.mem.Allocator,
    path1: []const u8,
    path2: []const u8,
    max_size: usize,
) !FileBuffers {
    const file1 = try std.fs.cwd().openFile(path1, .{ .mode = .read_only });
    defer file1.close();

    const file2 = try std.fs.cwd().openFile(path2, .{ .mode = .read_only });
    defer file2.close();

    const buf1 = try file1.readToEndAlloc(allocator, max_size);
    const buf2 = try file2.readToEndAlloc(allocator, max_size);

    return FileBuffers{
        .buf1 = buf1,
        .buf2 = buf2,
    };
}

fn stripQuotes(string: []const u8) []const u8 {
    if (string.len >= 2) {
        const start = string[0];
        const end = string[string.len - 1];

        if ((start == '\'' and end == '\'') or (start == '"' and end == '"')) {
            return string[1 .. string.len - 1];
        }
    }
    return string;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var marker: ?[]const u8 = null;
    var marker_flag: bool = false;
    var skip_flag: bool = false;

    var i: usize = 1; // Add binary name by default
    while (i < args.len) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.print(help_msg, .{args[0]});
            return;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--marker")) {
            //try stdout.print("marker: {any} \n", .{marker});
            marker_flag = true;

            // +3 because of marker flag and two files
            if (i + 1 >= args.len) {
                //try stdout.print("This should be -m null: {s}\n", .{arg});
                // If no value is provided, skip marker logic
                marker = null;
                i += 1; // Add marker flag
            } else {
                var raw_val: [:0]u8 = args[i + 1];

                //try stdout.print("This should be -m not null: {s}\n", .{arg});
                //try stdout.print("This should be marker: {s}\n", .{raw_val});
                const val = stripQuotes(raw_val[0..raw_val.len]); //Drop the null termination
                marker = if (val.len == 0) null else val;
                i += 2; // Add marker flag and marker value
            }
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--skip-empty")) {
            //try stdout.print("Printing i var: {d}\n", .{i});
            //try stdout.print("This should be -s: {s}\n", .{arg});
            skip_flag = true;
            //try stdout.print("This should be true: {any}\n", .{skip_flag});
            i += 1; // Add skip flag
        } else {
            break; // positional args start here
        }
    }

    const remaining = args.len - i;
    if (remaining != 2) {
        try stdout.print("Usage: {s} [-m <marker>] [-s] <file1> <file2>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const path1 = args[i];
    const path2 = args[i + 1];
    const max_size = 10 * 1024 * 1024;

    const buffers = try readTwoFiles(allocator, path1, path2, max_size);

    const cleaned1 = if (marker_flag or skip_flag) try rm.removeMarkedLines(allocator, buffers.buf1, marker, skip_flag) else buffers.buf1;
    const cleaned2 = if (marker_flag or skip_flag) try rm.removeMarkedLines(allocator, buffers.buf2, marker, skip_flag) else buffers.buf2;

    try compare.printNormalDiff(cleaned1, cleaned2);
    //try stdout.print("Cleaned File 1:\n{s}\n", .{cleaned1});
    //try stdout.print("Cleaned File 2:\n{s}\n", .{cleaned2});
}
