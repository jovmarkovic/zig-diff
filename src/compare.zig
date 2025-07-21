const std = @import("std");

var no_diffs: bool = true;

/// Prints a unified diff-style output comparing two text buffers line by line.
///
/// Lines that are identical are not printed.
/// Differences are reported in standard diff format:
/// - `c` for changed lines,
/// - `a` for lines added in file2,
/// - `d` for lines deleted from file1.
///
/// Empty lines are explicitly marked as "[empty line]" for clarity.
///
/// Params:
/// - `file1`: The first text buffer to compare (usually the "original").
/// - `file2`: The second text buffer to compare (usually the "modified").
///
/// Returns:
/// - `void` on success or propagates errors from stdout writes.
pub fn printNormalDiff(
    file1: []const u8,
    file2: []const u8,
) !void {
    const stdout = std.io.getStdOut().writer();

    // Split both buffers into lines on newline characters.
    var lines1 = std.mem.splitScalar(u8, file1, '\n');
    var lines2 = std.mem.splitScalar(u8, file2, '\n');

    // Line indexes start at 1 for diff format (human-friendly).
    var idx1: usize = 1;
    var idx2: usize = 1;

    // Get the first line of each file (optional because lines may end).
    var line1_opt = lines1.next();
    var line2_opt = lines2.next();

    // Loop until both line streams are exhausted.
    while (line1_opt != null or line2_opt != null) {
        // Trim trailing carriage returns '\r' for Windows compatibility.
        const line1 = std.mem.trimRight(u8, line1_opt orelse "", "\r");
        const line2 = std.mem.trimRight(u8, line2_opt orelse "", "\r");

        if (line1_opt != null and line2_opt != null) {
            // Both files have a line to compare.
            if (std.mem.eql(u8, line1, line2)) {
                // Lines are identical; no output, just advance.
                line1_opt = lines1.next();
                line2_opt = lines2.next();
                idx1 += 1;
                idx2 += 1;
            } else {
                // Lines differ; print a "change" diff block.
                no_diffs = false;

                // Replace empty lines with visible marker.
                const printable_line1 = if (line1.len == 0) "[empty line]" else line1;
                const printable_line2 = if (line2.len == 0) "[empty line]" else line2;

                // Print the diff header with line numbers.
                try stdout.print("{d}c{d}\n", .{ idx1, idx2 });
                try stdout.print("< {s}\n", .{printable_line1});
                try stdout.print("---\n", .{});
                try stdout.print("> {s}\n", .{printable_line2});

                // Advance to next lines.
                line1_opt = lines1.next();
                line2_opt = lines2.next();
                idx1 += 1;
                idx2 += 1;
            }
        } else if (line1_opt != null) {
            // file2 ended but file1 still has lines -> lines deleted.
            no_diffs = false;
            const printable_line1 = if (line1.len == 0) "[empty line]" else line1;

            // Print the deletion diff block.
            try stdout.print("{d}d{d}\n", .{ idx1, idx2 - 1 });
            try stdout.print("< {s}\n", .{printable_line1});

            line1_opt = lines1.next();
            idx1 += 1;
        } else if (line2_opt != null) {
            // file1 ended but file2 still has lines -> lines added.
            no_diffs = false;
            const printable_line2 = if (line2.len == 0) "[empty line]" else line2;

            // Print the addition diff block.
            try stdout.print("{d}a{d}\n", .{ idx1 - 1, idx2 });
            try stdout.print("> {s}\n", .{printable_line2});

            line2_opt = lines2.next();
            idx2 += 1;
        }
    }

    // If no differences found, print confirmation.
    if (no_diffs) try stdout.print("No Differences found.\n", .{});
}
