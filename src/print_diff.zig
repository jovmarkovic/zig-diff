const std = @import("std");
const Printer = @import("helpers.zig").Printer;
const DiffOp = @import("backtrack.zig").DiffOp;
const Operation = @import("backtrack.zig").Operation;

/// The output mode for the diff printer:
/// - Normal  → traditional `diff` style (`aN`, `dN`, `cN` commands).
/// - Unified → modern unified diff (`@@ -l,r +l,r @@` blocks with +/−).
pub const DiffMode = enum {
    Normal,
    Unified,
};

/// Wrapper for a diff operation with an extra `is_context` flag.
/// Context lines are unchanged lines kept around changes (for unified diff).
const UnifiedLine = struct {
    op: DiffOp,
    is_context: bool,
};

/// A printer that takes diff operations (`DiffOp`) and prints them in
/// either unified or normal format.
pub const DiffPrinter = struct {
    allocator: std.mem.Allocator, // memory allocator
    //stdout: std.fs.File.Writer, // output writer (usually stdout)
    a: []const []const u8, // original file lines
    b: []const []const u8, // new file lines
    mode: DiffMode, // chosen diff printing mode
    printer: *Printer,

    /// Initialize a new printer instance.
    pub fn init(
        allocator: std.mem.Allocator,
        a: []const []const u8,
        b: []const []const u8,
        mode: DiffMode,
        printer: *Printer,
    ) DiffPrinter {
        return DiffPrinter{
            .allocator = allocator,
            //.stdout = std.io.getStdOut().writer(),
            .a = a,
            .b = b,
            .mode = mode,
            .printer = printer,
        };
    }

    /// Print the diff according to the selected mode.
    pub fn print(self: *DiffPrinter, diffs: []const DiffOp) !void {
        return switch (self.mode) {
            .Unified => self.printUnified(diffs),
            .Normal => self.printNormal(diffs),
        };
    }

    /// Helper: format a line range as a string (e.g. `3` or `3,5`).
    fn rangeStr(allocator: std.mem.Allocator, start: usize, end: usize) ![]u8 {
        if (start == end) {
            return try std.fmt.allocPrint(allocator, "{}", .{start});
        } else {
            return try std.fmt.allocPrint(allocator, "{},{}", .{ start, end });
        }
    }

    /// Print a unified diff. Groups edits into "hunks" with `context` lines.
    fn printUnified(self: *DiffPrinter, diffs: []const DiffOp) !void {
        const context = 3; // number of context lines around changes
        var buffer = std.ArrayList(UnifiedLine).init(self.allocator);
        defer buffer.deinit();

        // Convert diff operations into UnifiedLine (with context marking).
        for (diffs) |diff| {
            const is_context = diff.op == .Keep;
            try buffer.append(.{ .op = diff, .is_context = is_context });
        }

        var i: usize = 0;
        while (i < buffer.items.len) {
            // Skip pure context sections (unchanged lines far from edits).
            if (buffer.items[i].is_context) {
                i += 1;
                continue;
            }

            // Start hunk: include some leading context before first change.
            const hunk_start = if (i >= context) i - context else 0;

            // Expand hunk forward to include trailing context after changes.
            var hunk_end = i + 1;
            var last_change = i;

            while (hunk_end < buffer.items.len) {
                if (!buffer.items[hunk_end].is_context)
                    last_change = hunk_end;

                // If the last change is past context (default case lines 3),
                // check if there’s another nearby change (context times 2), merge.
                if (hunk_end > last_change + context) {
                    var j = hunk_end;
                    // Increment hunk end while context lines are found.
                    while (j < buffer.items.len and buffer.items[j].is_context) : (j += 1) {}
                    if (j == buffer.items.len or j - (last_change + 1) > 2 * context)
                        break; // stop this hunk - hunk_end is either at the end or next change is too far.

                    hunk_end = j; // extend hunk to next change
                    continue;
                }
                hunk_end += 1;
            }

            // Print this hunk
            try self.printUnifiedHunk(buffer.items[hunk_start..hunk_end]);
            i = hunk_end; // move to next
        }
    }

    /// Print a single unified diff hunk with `@@ -l,r +l,r @@` header.
    fn printUnifiedHunk(self: *DiffPrinter, buffer: []const UnifiedLine) !void {
        var min_orig: usize = std.math.maxInt(usize);
        var max_orig: usize = 0;
        var min_new: usize = std.math.maxInt(usize);
        var max_new: usize = 0;

        // Determine affected line ranges in both original and new file.
        for (buffer) |entry| {
            switch (entry.op.op) {
                .Keep => {
                    min_orig = @min(min_orig, entry.op.orig_line);
                    max_orig = @max(max_orig, entry.op.orig_line);

                    const new_line = @as(usize, @intCast(entry.op.new_line));
                    min_new = @min(min_new, new_line);
                    max_new = @max(max_new, new_line);
                },
                .Insert => {
                    const new_line = @as(usize, @intCast(entry.op.new_line));
                    min_new = @min(min_new, new_line);
                    max_new = @max(max_new, new_line);
                },
                .Delete => {
                    min_orig = @min(min_orig, entry.op.orig_line);
                    max_orig = @max(max_orig, entry.op.orig_line);
                },
            }
        }

        const has_orig = min_orig != std.math.maxInt(usize);
        const has_new = min_new != std.math.maxInt(usize);

        // Compute unified diff header ranges (1-based indexing).
        var orig_start: usize = 0;
        var orig_len: usize = 0;
        var new_start: usize = 0;
        var new_len: usize = 0;

        if (has_orig) {
            orig_start = min_orig + 1;
            orig_len = max_orig - min_orig + 1;
        }
        if (has_new) {
            new_start = min_new + 1;
            new_len = max_new - min_new + 1;
        }

        // Print hunk header.
        try self.printer.printColor(
            "@@ -{d},{d} +{d},{d} @@\n",
            .{ orig_start, orig_len, new_start, new_len },
            self.printer.colors.header,
        );

        // Print hunk lines with prefixes: ' ' (Keep), '-' (Delete), '+' (Insert).
        for (buffer) |entry| {
            const line: []const u8 = switch (entry.op.op) {
                .Keep => self.a[entry.op.orig_line],
                .Delete => self.a[entry.op.orig_line],
                .Insert => self.b[@as(usize, @intCast(entry.op.new_line))],
            };
            const prefix: u8 = switch (entry.op.op) {
                .Keep => ' ',
                .Delete => '-',
                .Insert => '+',
            };
            try self.printer.printColor(
                ".{c} {s}\n",
                .{ prefix, line },
                switch (prefix) {
                    ' ' => self.printer.colors.reset,
                    '+' => self.printer.colors.insert,
                    '-' => self.printer.colors.delete,
                    else => unreachable,
                },
            );
        }
    }

    /// Print a normal diff (traditional style with `a/d/c` commands).
    fn printNormal(self: *DiffPrinter, diffs: []const DiffOp) !void {
        var hunk = std.ArrayList(DiffOp).init(self.allocator);
        defer hunk.deinit();

        // Group changes into hunks (separated by Keep ops).
        for (diffs) |diff| {
            switch (diff.op) {
                .Keep => {
                    if (hunk.items.len > 0) try self.printNormalHunk(hunk.items);
                    hunk.clearRetainingCapacity();
                },
                .Insert, .Delete => try hunk.append(diff),
            }
        }
        if (hunk.items.len > 0) try self.printNormalHunk(hunk.items);
    }

    /// Print a single normal diff hunk in GNU diff format.
    /// Example:
    ///   3c3
    ///   < old line
    ///   ---
    ///   > new line
    fn printNormalHunk(self: *DiffPrinter, ops: []const DiffOp) !void {
        var min_orig: usize = std.math.maxInt(usize);
        var max_orig: usize = 0;
        var min_new: usize = std.math.maxInt(usize);
        var max_new: usize = 0;

        // Determine affected ranges in original/new files.
        for (ops) |op| {
            if (op.op != .Insert) {
                min_orig = @min(min_orig, op.orig_line);
                max_orig = @max(max_orig, op.orig_line);
            }
            if (op.op != .Delete) {
                const new_line = @as(usize, @intCast(op.new_line));
                min_new = @min(min_new, new_line);
                max_new = @max(max_new, new_line);
            }
        }

        const has_orig = min_orig != std.math.maxInt(usize);
        const has_new = min_new != std.math.maxInt(usize);

        var cmd: []const u8 = "?";

        // Build command line: a (add), d (delete), c (change).
        var orig_start: usize = 0;
        var orig_end: usize = 0;
        var new_start: usize = 0;
        var new_end: usize = 0;

        if (has_orig and has_new) {
            cmd = "c"; // change
            orig_start = min_orig + 1;
            orig_end = max_orig + 1;
            new_start = min_new + 1;
            new_end = max_new + 1;
        } else if (has_orig and !has_new) {
            cmd = "d"; // delete
            orig_start = min_orig + 1;
            orig_end = max_orig + 1;
            new_start = if (min_orig == 0) 0 else min_orig;
            new_end = new_start;
        } else if (!has_orig and has_new) {
            cmd = "a"; // add
            orig_start = if (min_new == 0) 0 else min_new;
            orig_end = orig_start;
            new_start = min_new + 1;
            new_end = max_new + 1;
        }

        const orig_range = try rangeStr(self.allocator, orig_start, orig_end);
        defer self.allocator.free(orig_range);

        const new_range = try rangeStr(self.allocator, new_start, new_end);
        defer self.allocator.free(new_range);

        // Print command header line.
        try self.printer.printColor(
            "{s}{s}{s}\n",
            .{ orig_range, cmd, new_range },
            self.printer.colors.header,
        );

        // Print deleted lines (<) for delete/change
        if (std.mem.eql(u8, cmd, "d") or std.mem.eql(u8, cmd, "c")) {
            for (ops) |op| {
                if (op.op == .Delete) {
                    try self.printer.printColor(
                        "{c} {s}\n",
                        .{ '<', self.a[op.orig_line] },
                        self.printer.colors.delete,
                    );
                }
            }
        }

        // Print separator for change
        if (std.mem.eql(u8, cmd, "c")) {
            try self.printer.printRaw("---\n", .{});
        }

        // Print inserted lines (>) for add/change
        if (std.mem.eql(u8, cmd, "a") or std.mem.eql(u8, cmd, "c")) {
            for (ops) |op| {
                if (op.op == .Insert) {
                    try self.printer.printColor(
                        "{c} {s}\n",
                        .{ '>', self.b[@as(usize, @intCast(op.new_line))] },
                        self.printer.colors.insert,
                    );
                }
            }
        }
    }
};
