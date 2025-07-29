const std = @import("std");
const DiffOp = @import("backtrack.zig").DiffOp;

/// DiffPrinter is responsible for formatting and printing
/// the difference (diff) between two sets of lines in a
/// style similar to GNU diff's normal output.
///
/// It collects sequences of changes into "hunks" and prints
/// them using the standard diff syntax.
///
/// Fields:
/// - allocator: memory allocator used for temporary allocations.
/// - stdout: output writer (usually stdout).
/// - a, b: the two sequences of lines being compared.
/// - deletedLines: lines from `a` marked for deletion in current hunk.
/// - insertedLines: lines from `b` marked for insertion in current hunk.
/// - hunkOrigStart, hunkOrigEnd: range of original file lines involved in current hunk.
/// - hunkNewStart, hunkNewEnd: range of new file lines involved in current hunk.
/// - inHunk: whether a hunk is currently being constructed.
pub const DiffPrinter = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File.Writer,
    a: []const []const u8,
    b: []const []const u8,

    deletedLines: std.ArrayList([]const u8),
    insertedLines: std.ArrayList([]const u8),

    hunkOrigStart: usize,
    hunkOrigEnd: usize,
    hunkNewStart: usize,
    hunkNewEnd: usize,
    inHunk: bool,

    /// Initialize a DiffPrinter instance.
    /// - allocator: allocator for dynamic memory.
    /// - a, b: slices of lines representing the original and new files.
    pub fn init(
        allocator: std.mem.Allocator,
        a: []const []const u8,
        b: []const []const u8,
    ) DiffPrinter {
        return DiffPrinter{
            .allocator = allocator,
            .stdout = std.io.getStdOut().writer(),
            .a = a,
            .b = b,
            .deletedLines = std.ArrayList([]const u8).init(allocator),
            .insertedLines = std.ArrayList([]const u8).init(allocator),
            .hunkOrigStart = 0,
            .hunkOrigEnd = 0,
            .hunkNewStart = 0,
            .hunkNewEnd = 0,
            .inHunk = false,
        };
    }

    /// Release resources allocated by the DiffPrinter.
    pub fn deinit(self: *DiffPrinter) void {
        self.deletedLines.deinit();
        self.insertedLines.deinit();
    }

    /// Prints the currently accumulated hunk if any.
    ///
    /// A "hunk" is a contiguous group of changes.
    /// The method prints the hunk header with line ranges,
    /// followed by lines deleted (`<`), a separator (`---`),
    /// and lines inserted (`>`), similar to GNU diff.
    ///
    /// After printing, clears the hunk state to start fresh.
    fn printHunk(self: *DiffPrinter) !void {
        if (!self.inHunk) return;

        // Format original file line range, 1-based indices
        const origRange = if (self.hunkOrigEnd == self.hunkOrigStart)
            try std.fmt.allocPrint(self.allocator, "{d}", .{self.hunkOrigStart + 1})
        else
            try std.fmt.allocPrint(self.allocator, "{d},{d}", .{ self.hunkOrigStart + 1, self.hunkOrigEnd + 1 });

        // Format new file line range similarly
        const newRange = if (self.hunkNewEnd == self.hunkNewStart)
            try std.fmt.allocPrint(self.allocator, "{d}", .{self.hunkNewStart + 1})
        else
            try std.fmt.allocPrint(self.allocator, "{d},{d}", .{ self.hunkNewStart + 1, self.hunkNewEnd + 1 });

        defer self.allocator.free(origRange);
        defer self.allocator.free(newRange);

        // Determine hunk action character:
        // 'c' = change (deletions and insertions),
        // 'd' = delete only,
        // 'a' = add only
        var action: []const u8 = "";
        if (self.deletedLines.items.len > 0 and self.insertedLines.items.len > 0) {
            action = "c";
        } else if (self.deletedLines.items.len > 0) {
            action = "d";
        } else if (self.insertedLines.items.len > 0) {
            action = "a";
        }

        // Print hunk header like "3,5c7,9"
        try self.stdout.print("{s}{s}{s}\n", .{ origRange, action, newRange });

        // Print deleted lines prefixed with '< '
        if (self.deletedLines.items.len > 0) {
            for (self.deletedLines.items) |line| {
                try self.stdout.print("< {s}\n", .{line});
            }
        }
        // Print separator line for changes
        if (std.mem.eql(u8, action, "c")) {
            try self.stdout.print("---\n", .{});
        }
        // Print inserted lines prefixed with '> '
        if (self.insertedLines.items.len > 0) {
            for (self.insertedLines.items) |line| {
                try self.stdout.print("> {s}\n", .{line});
            }
        }

        // Reset hunk state to prepare for next hunk
        self.deletedLines.clearRetainingCapacity();
        self.insertedLines.clearRetainingCapacity();
        self.inHunk = false;
    }

    /// Processes and prints a sequence of diff operations.
    ///
    /// Iterates over each diff op and accumulates lines in hunks.
    /// When a "Keep" operation is encountered, prints any pending hunk
    /// and resets state.
    ///
    /// - For Insert ops, lines from `b` are collected as insertedLines,
    ///   and new file hunk range is updated.
    /// - For Delete ops, lines from `a` are collected as deletedLines,
    ///   and original file hunk range is updated.
    ///
    /// After processing all ops, flushes any remaining hunk.
    pub fn print(self: *DiffPrinter, diffs: []const DiffOp) !void {
        for (diffs) |diff| {
            switch (diff.op) {
                .Keep => {
                    // On unchanged lines, print and reset current hunk
                    try self.printHunk();
                },
                .Insert => {
                    // Start a new hunk if none active
                    if (!self.inHunk) {
                        self.inHunk = true;
                        self.hunkOrigStart = diff.orig_line;
                        self.hunkOrigEnd = diff.orig_line;
                        self.hunkNewStart = @as(usize, @intCast(diff.new_line));
                        self.hunkNewEnd = @as(usize, @intCast(diff.new_line));
                    } else {
                        // Extend hunk range for inserted lines
                        self.hunkNewStart = @min(self.hunkNewStart, @as(usize, @intCast(diff.new_line)));
                        self.hunkNewEnd = @max(self.hunkNewEnd, @as(usize, @intCast(diff.new_line)));
                    }
                    // Append inserted line content
                    try self.insertedLines.append(self.b[@as(usize, @intCast(diff.new_line))]);
                },
                .Delete => {
                    if (!self.inHunk) {
                        self.inHunk = true;
                        self.hunkOrigStart = diff.orig_line;
                        self.hunkOrigEnd = diff.orig_line;
                        self.hunkNewStart = @as(usize, @intCast(diff.new_line));
                        self.hunkNewEnd = @as(usize, @intCast(diff.new_line));
                    } else {
                        // Extend hunk range for deleted lines
                        self.hunkOrigStart = @min(self.hunkOrigStart, diff.orig_line);
                        self.hunkOrigEnd = @max(self.hunkOrigEnd, diff.orig_line);
                    }
                    // Append deleted line content
                    try self.deletedLines.append(self.a[diff.orig_line]);
                },
            }
        }

        // Print any remaining hunk after all diffs processed
        try self.printHunk();
    }
};
