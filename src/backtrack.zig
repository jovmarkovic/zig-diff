const std = @import("std");
const helpers = @import("helpers.zig");
const DiffAlgo = @import("diff_algo.zig");
const DiffPrinter = @import("print_diff.zig").DiffPrinter;
const DiffMode = @import("print_diff.zig").DiffMode;

/// Represents the type of edit operation in the diff.
pub const Operation = enum {
    Keep, // Lines are identical in both sequences (no change).
    Insert, // Lines inserted in the new sequence.
    Delete, // Lines deleted from the original sequence.
};

/// Represents a single diff operation with line indexes.
/// `orig_line` is the index in the original sequence.
/// `new_line` is the index in the new sequence (signed because vars using it can be negative).
pub const DiffOp = struct {
    op: Operation,
    orig_line: usize,
    new_line: isize,
};

/// trackDiff reconstructs the diff operations between two sequences of lines `a` and `b`
/// using a previously computed diff trace.
///
/// Parameters:
/// - allocator: memory allocator for dynamic allocations.
/// - trace: ArrayList of V arrays from Myers algorithm representing the path trace.
/// - a, b: slices of lines (original and new files).
/// - compare: callback function that compares elements at given indices.
/// - printDiff: boolean flag controlling whether to print the diff output.
///
/// Returns:
/// - Error if allocation or printing fails.
///
/// How it works:
/// - Uses the Myers diff algorithm's trace of vectors `v` to backtrack the path of
///   changes from end to start.
/// - Builds a list of diff operations (`DiffOp`) representing inserts, deletes, and matches.
/// - The backtracking reconstructs the diff in reverse order, so it reverses the operations list at the end.
/// - Optionally prints the diff using `DiffPrinter`.
///
pub fn trackDiff(
    allocator: std.mem.Allocator,
    trace: std.ArrayList([]usize), // Trace from Myers algorithm: snapshots of vectors 'v' at each step
    a: []const []const u8, // Original sequence of lines
    b: []const []const u8, // New sequence of lines
    mode: []const u8, // diff mode
    printer: *helpers.Printer,
    print_diff: bool, // Whether to print the diff after calculation
) !void {
    // Sets printing mode
    var diff_mode: DiffMode = undefined;
    if (std.mem.eql(u8, mode, "normal")) {
        diff_mode = DiffMode.Normal;
    } else if (std.mem.eql(u8, mode, "unified")) {
        diff_mode = DiffMode.Unified;
    } else {
        std.debug.print("UNKNOWN DIFF MODE SPECIFIED!!!\n", .{});
        return;
    }

    // Offset is used to translate from k (diagonal index) to array index in v
    const offset: isize = @intCast(a.len + b.len);

    // Start backtracking from the last trace snapshot (furthest step)
    var d = trace.items.len - 1;

    // x and y represent current coordinates in the edit graph (indices into a and b)
    var x = a.len - 1;
    var y: isize = @intCast(b.len - 1);

    // Variables to hold previous diagonal and coordinates during backtracking
    var prev_k: isize = 0;
    var prev_x: usize = 0;
    var prev_y: isize = 0;

    // List to accumulate diff operations while backtracking
    // var diffs = try std.ArrayList(DiffOp).initCapacity(allocator, a.len + b.len);
    var diffs: std.ArrayList(DiffOp) = .empty;
    defer diffs.deinit(allocator);

    // Main backtracking loop from the end of the trace to the beginning
    while (d >= 0) : (d -= 1) {
        // Current vector v snapshot at step d
        const v_copy = trace.items[d];

        // Compute current diagonal k = x - y
        const k: isize = @as(isize, @intCast(x)) - y;

        // Translate diagonal k to index in v array using offset
        const o_k: usize = @intCast(offset + k);

        // Decide whether the previous step was an Insert (move up) or Delete (move left)
        if (k == -@as(isize, @intCast(d)) or (k != @as(isize, @intCast(d)) and v_copy[o_k - 1] < v_copy[o_k + 1])) {
            // Insert operation: came from diagonal k + 1 (up)
            prev_k = k + 1;
        } else {
            // Delete operation: came from diagonal k - 1 (left)
            prev_k = k - 1;
        }

        // Previous x coordinate on the path
        prev_x = v_copy[@as(usize, @intCast(prev_k + offset))];

        // Previous y coordinate derived from prev_x and prev_k (y = x - k)
        prev_y = @as(isize, @intCast(prev_x)) - prev_k;

        // Follow diagonal moves (Keep operations) as long as a[x-1] == b[y-1]
        while (x > prev_x and y > prev_y) {
            // Keep operation means lines are equal and unchanged
            x -= 1;
            y -= 1;

            try diffs.append(allocator, .{
                .op = Operation.Keep,
                .orig_line = x,
                .new_line = y,
            });
        }

        // Handle the non-diagonal move (Insert or Delete)
        if (x == prev_x) {
            // Insert operation: line inserted in b at position y-1
            y -= 1;
            if (y >= 0) {
                try diffs.append(allocator, .{
                    .op = Operation.Insert,
                    .orig_line = x, // Usually the unchanged line before insert
                    .new_line = y,
                });
            }
        } else if (y == prev_y) {
            // Delete operation: line deleted from a at position x-1
            x -= 1;
            try diffs.append(allocator, .{
                .op = Operation.Delete,
                .orig_line = x,
                .new_line = y, // Position in new sequence before delete
            });
        }

        // Move to previous coordinates for next iteration
        x = prev_x;
        y = prev_y;

        if (d == 0) break; // End when all steps are processed
    }

    // The diff operations were appended backwards (from end to start),
    // reverse to restore normal chronological order
    std.mem.reverse(DiffOp, diffs.items);

    if (print_diff) {
        // Initialize DiffPrinter to format and print
        var diffPrinter = DiffPrinter.init(
            allocator,
            a,
            b,
            diff_mode,
            printer,
        );

        try diffPrinter.print(diffs.items);
    }
}
