const std = @import("std");

var no_diffs: bool = true;

/// Prints a unified diff-style output comparing two text buffers line by line.
/// Always uses 'c' to report differences, even for added/removed EOF lines.
pub fn printNormalDiff(
    file1: []const u8,
    file2: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    var lines1 = std.mem.splitScalar(u8, file1, '\n');
    var lines2 = std.mem.splitScalar(u8, file2, '\n');

    var idx1: usize = 1;
    var idx2: usize = 1;

    var line1_opt = lines1.next();
    var line2_opt = lines2.next();

    while (line1_opt != null or line2_opt != null) {
        const line1_raw = line1_opt orelse "";
        const line2_raw = line2_opt orelse "";

        const line1 = std.mem.trimRight(u8, line1_raw, "\r");
        const line2 = std.mem.trimRight(u8, line2_raw, "\r");

        if (line1_opt != null and line2_opt != null) {
            if (std.mem.eql(u8, line1, line2)) {
                // Identical
                idx1 += 1;
                idx2 += 1;
                line1_opt = lines1.next();
                line2_opt = lines2.next();
                continue;
            }
        }

        // Difference found
        no_diffs = false;

        const printable_line1 = if (line1.len == 0) "[empty line]" else line1;
        const printable_line2 = if (line2.len == 0) "[empty line]" else line2;

        try stdout.print("{d}c\n", .{idx1});

        if (line1_opt != null) {
            try stdout.print("< {s}\n", .{printable_line1});
        } else {
            try stdout.writeAll("< [no line]\n");
        }

        try stdout.writeAll("---\n");

        if (line2_opt != null) {
            try stdout.print("> {s}\n", .{printable_line2});
        } else {
            try stdout.writeAll("> [no line]\n");
        }

        // Next iteration
        if (line1_opt != null) {
            idx1 += 1;
            line1_opt = lines1.next();
        }
        if (line2_opt != null) {
            idx2 += 1;
            line2_opt = lines2.next();
        }
    }

    if (no_diffs) try stdout.print("No Differences found.\n", .{});
}
