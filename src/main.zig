const std = @import("std");
const rm = @import("remove_marked.zig");
const diff_algo = @import("diff_algo.zig");
const trackDiff = @import("backtrack.zig").trackDiff;
const helpers = @import("helpers.zig");

/// Help message displayed with -h
const help_msg =
    \\Usage: {s} [options] <file1> <file2>
    \\
    \\Options:
    \\  --normal               Sets diffing mode to normal (default)
    \\  --color                Applies colors to diff output if stdout is TTY
    \\  -m "#", --marker '//'  Remove lines starting with this marker;
    \\                           (double) quotes not mandatory
    \\    
    \\  -s, --skip-empty       Remove empty lines from comparison
    \\  -p, --print            Prints the files without comparison;
    \\                           includes header with filename and EOF footer
    \\                           if stdout is not TTY, remove colors
    \\
    \\  -u, --unified          Sets diffing mode to unified
    \\  -h, --help             Show this help message
    \\
;
fn isStdoutTTY() bool {
    return std.posix.isatty(1);
}

/// Entry point of the program
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var marker: []const u8 = "";
    var marker_flag = false;
    var skip_flag = false;
    var print_only = false;
    var mode: []const u8 = "normal";
    var colo: helpers.ColorMode = .never;

    // Parse CLI flags
    var i: usize = 1;
    while (i < args.len) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.print(help_msg, .{args[0]});
            return;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--marker")) {
            marker_flag = true;
            marker = helpers.stripQuotes(args[i + 1]);
            i += 2;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--skip-empty")) {
            skip_flag = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--unified")) {
            mode = "unified";
            i += 1;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--print")) {
            colo = if (isStdoutTTY()) .auto else .never;
            print_only = true;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--color")) {
            colo = if (isStdoutTTY()) .auto else .never;
            i += 1;
        } else if (std.mem.eql(u8, arg, "--normal")) {
            mode = "normal";
            i += 1;
        } else {
            break;
        }
    }

    const paint = helpers.Colors.paint(colo);
    var printer = helpers.Printer.init(stdout, paint);

    const remaining = args.len - i;
    if (remaining != 2) {
        try stdout.print("Usage: {s} [-m <marker>] [-s] <file1> <file2>\n", .{args[0]});
        return error.InvalidArgs;
    }

    const path1 = args[i];
    const path2 = args[i + 1];

    const buffers = try helpers.readTwoFiles(allocator, path1, path2);

    const processed = if (marker_flag or skip_flag) "Processed " else "";

    const cleaned1 = if (processed.len > 0)
        try rm.removeMarkedLines(allocator, buffers.lines1, marker, skip_flag)
    else
        buffers.lines1;

    const cleaned2 = if (processed.len > 0)
        try rm.removeMarkedLines(allocator, buffers.lines2, marker, skip_flag)
    else
        buffers.lines2;

    if (print_only) {
        //FILE 1
        try stdout.print("{s}{s}File 1 ({s}):{s}\n", .{ paint.header, processed, path1, paint.reset });
        for (cleaned1[0 .. cleaned1.len - 1]) |line| try stdout.print("{s}\n", .{line});
        const last1 = cleaned1[cleaned1.len - 1];
        if (last1.len == 0) {
            // Last line is empty -> show EOF instead
            try stdout.print("{s}EOF{s}\n", .{ paint.header, paint.reset });
        } else {
            try stdout.print("{s}\n", .{last1});
            try stdout.print("{s}EOF{s}\n", .{ paint.header, paint.reset });
        }
        //FILE 2
        try stdout.print("{s}{s}File 2 ({s}):{s}\n", .{ paint.header, processed, path2, paint.reset });
        for (cleaned2[0 .. cleaned2.len - 1]) |line| try stdout.print("{s}\n", .{line});
        const last2 = cleaned2[cleaned2.len - 1];
        if (last2.len == 0) {
            // Last line is empty -> show EOF instead
            try stdout.print("{s}EOF{s}\n", .{ paint.header, paint.reset });
        } else {
            try stdout.print("{s}\n", .{last2});
            try stdout.print("{s}EOF{s}\n", .{ paint.header, paint.reset });
        }
        return;
    }

    var eql_ctx = helpers.EqlContext{ .f1 = cleaned1, .f2 = cleaned2 };

    const trace = try diff_algo.myersDiff(
        allocator,
        cleaned1.len,
        cleaned2.len,
        &eql_ctx,
        helpers.eql,
    );
    defer trace.deinit();

    try trackDiff(
        allocator,
        trace,
        cleaned1,
        cleaned2,
        mode,
        &printer,
        true,
    );
}
