const std = @import("std");
const rm = @import("remove_lines_with_marker.zig");
const compare = @import("compare.zig");

/// Holds the raw file contents for both files
const FileBuffers = struct {
    buf1: []u8,
    buf2: []u8,
};

/// Help message displayed with -h
const help_msg =
    \\Usage: {s} [options] <file1> <file2>
    \\
    \\Options:
    \\  -m "#", --marker '//'  Remove lines starting with this marker - (double) quotes not mandatory
    \\  -s, --skip-empty       Remove empty lines from comparison
    \\  -p, --print            Prints the files with out comparison 
    \\  -h, --help             Show this help message
    \\
;

/// Reads two files into memory till EOF
fn readTwoFiles(
    allocator: std.mem.Allocator,
    path1: []const u8,
    path2: []const u8,
    max_size: usize,
) !FileBuffers {

    // read_only for safety
    const file1 = try std.fs.cwd().openFile(path1, .{ .mode = .read_only });
    defer file1.close();

    const file2 = try std.fs.cwd().openFile(path2, .{ .mode = .read_only });
    defer file2.close();

    const buf1 = try file1.readToEndAlloc(allocator, max_size);
    const buf2 = try file2.readToEndAlloc(allocator, max_size);

    return FileBuffers{ .buf1 = buf1, .buf2 = buf2 };
}

/// Removes surrounding single or double quotes from a string
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

/// Entry point of the program
pub fn main() !void {

    // ArenaAllocator per Zig's own docu recommendation
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    //Implicitly set marker to empty string
    var marker: []const u8 = "";
    var marker_flag = false;
    var skip_flag = false;
    var print_only = false;

    // Parse CLI flags
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];

        // Help
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.print(help_msg, .{args[0]});
            return;
        }

        // Marker
        else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--marker")) {
            marker_flag = true;
            marker = stripQuotes(args[i + 1]);
            i += 2;
        }

        // Skip empty
        else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--skip-empty")) {
            skip_flag = true;
            i += 1;
        }

        // Print only
        else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--print")) {
            print_only = true;
            i += 1;
        }

        // Stop at first positional argument
        else {
            break;
        }
    }

    const remaining = args.len - i;

    // Error out if empty marker provided
    if (remaining != 2) {
        try stdout.print("Usage: {s} [-m <marker>] [-s] <file1> <file2>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const path1 = args[i];
    const path2 = args[i + 1];
    const max_size = 10 * 1024 * 1024; // 10MB max

    // Read both files
    const buffers = try readTwoFiles(allocator, path1, path2, max_size);

    // Optionally filter lines based on marker/empty lines
    const cleaned1 = if (marker_flag or skip_flag)
        try rm.removeMarkedLines(allocator, buffers.buf1, marker, skip_flag)
    else
        buffers.buf1;

    const cleaned2 = if (marker_flag or skip_flag)
        try rm.removeMarkedLines(allocator, buffers.buf2, marker, skip_flag)
    else
        buffers.buf2;

    if (print_only) {
        // Print processed files only, skip diff
        try stdout.print("Processed File 1 ({s}):\n{s}\n", .{ path1, cleaned1 });
        try stdout.print("Processed File 2 ({s}):\n{s}\n", .{ path2, cleaned2 });
        return;
    }
    // Output diff results
    try compare.printNormalDiff(cleaned1, cleaned2);
}
