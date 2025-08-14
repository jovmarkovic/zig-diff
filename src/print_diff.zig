const std = @import("std");
const DiffOp = @import("backtrack.zig").DiffOp;
const Operation = @import("backtrack.zig").Operation;

pub const DiffMode = enum {
    Normal,
    Unified,
};

const UnifiedLine = struct {
    op: DiffOp,
    is_context: bool,
};

pub const DiffPrinter = struct {
    allocator: std.mem.Allocator,
    stdout: std.fs.File.Writer,
    a: []const []const u8,
    b: []const []const u8,
    mode: DiffMode,

    pub fn init(
        allocator: std.mem.Allocator,
        a: []const []const u8,
        b: []const []const u8,
        mode: DiffMode,
    ) DiffPrinter {
        return DiffPrinter{
            .allocator = allocator,
            .stdout = std.io.getStdOut().writer(),
            .a = a,
            .b = b,
            .mode = mode,
        };
    }
    pub fn print(self: *DiffPrinter, diffs: []const DiffOp) !void {
        return switch (self.mode) {
            .Unified => self.printUnified(diffs),
            .Normal => self.printNormal(diffs),
        };
    }

    // Helper to print ranges in GNU diff style
    fn rangeStr(allocator: std.mem.Allocator, start: usize, end: usize) ![]u8 {
        if (start == end) {
            return try std.fmt.allocPrint(allocator, "{}", .{start});
        } else {
            return try std.fmt.allocPrint(allocator, "{},{}", .{ start, end });
        }
    }

    fn printUnified(self: *DiffPrinter, diffs: []const DiffOp) !void {
        const context = 3;
        var buffer = std.ArrayList(UnifiedLine).init(self.allocator);
        defer buffer.deinit();

        // Buffer all lines with context flag
        for (diffs) |diff| {
            const is_context = diff.op == .Keep;
            try buffer.append(.{ .op = diff, .is_context = is_context });
        }

        var i: usize = 0;
        while (i < buffer.items.len) {
            // Skip leading context lines not near changes
            if (buffer.items[i].is_context) {
                i += 1;
                continue;
            }

            // Start hunk context lines before the first change line
            const hunk_start = if (i >= context) i - context else 0;

            // Find end of hunk, including trailing context
            var hunk_end = i + 1;
            var last_change = i;

            while (hunk_end < buffer.items.len) {
                if (!buffer.items[hunk_end].is_context)
                    last_change = hunk_end;

                if (hunk_end > last_change + context) {
                    var j = hunk_end;
                    while (j < buffer.items.len and buffer.items[j].is_context) : (j += 1) {}
                    if (j == buffer.items.len or j - (last_change + 1) > 2 * context)
                        break;

                    hunk_end = j;
                    continue;
                }
                hunk_end += 1;
            }

            try self.printUnifiedHunk(buffer.items[hunk_start..hunk_end]);
            i = hunk_end;
        }
    }

    fn printUnifiedHunk(self: *DiffPrinter, buffer: []const UnifiedLine) !void {
        var min_orig: usize = std.math.maxInt(usize);
        var max_orig: usize = 0;
        var min_new: usize = std.math.maxInt(usize);
        var max_new: usize = 0;

        // Find min/max line numbers
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

        // Unified diff ranges are 1-based; 0 length allowed
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

        try self.stdout.print("@@ -{d},{d} +{d},{d} @@\n", .{ orig_start, orig_len, new_start, new_len });

        // Print lines with prefix
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
            try self.stdout.print("{c}{s}\n", .{ prefix, line });
        }
    }

    fn printNormal(self: *DiffPrinter, diffs: []const DiffOp) !void {
        var hunk = std.ArrayList(DiffOp).init(self.allocator);
        defer hunk.deinit();

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

    fn printNormalHunk(self: *DiffPrinter, ops: []const DiffOp) !void {
        var min_orig: usize = std.math.maxInt(usize);
        var max_orig: usize = 0;
        var min_new: usize = std.math.maxInt(usize);
        var max_new: usize = 0;

        // Find min/max line numbers in original and new files, ignoring Inserts or Deletes accordingly
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

        // Ranges in GNU diff are 1-based
        var orig_start: usize = 0;
        var orig_end: usize = 0;
        var new_start: usize = 0;
        var new_end: usize = 0;

        if (has_orig and has_new) {
            // Change
            cmd = "c";
            orig_start = min_orig + 1;
            orig_end = max_orig + 1;
            new_start = min_new + 1;
            new_end = max_new + 1;
        } else if (has_orig and !has_new) {
            // Delete
            cmd = "d";
            orig_start = min_orig + 1;
            orig_end = max_orig + 1;
            if (min_orig == 0) {
                new_start = 0; // deletion before first line of new file
            } else {
                new_start = min_orig; // delete after this line in new file (1-based)
            }
            new_end = new_start;
        } else if (!has_orig and has_new) {
            // Add
            cmd = "a";
            if (min_new == 0) {
                orig_start = 0; // insert before first line
            } else {
                orig_start = min_new; // insert after this line in old file
            }
            orig_end = orig_start;
            new_start = min_new + 1;
            new_end = max_new + 1;
        }

        const orig_range = try rangeStr(self.allocator, orig_start, orig_end);
        defer self.allocator.free(orig_range);

        const new_range = try rangeStr(self.allocator, new_start, new_end);
        defer self.allocator.free(new_range);

        // Print command line
        try self.stdout.print("{s}{s}{s}\n", .{ orig_range, cmd, new_range });

        // Print deleted lines (<) for delete or change
        if (std.mem.eql(u8, cmd, "d") or std.mem.eql(u8, cmd, "c")) {
            for (ops) |op| {
                if (op.op == .Delete) {
                    try self.stdout.print("< {s}\n", .{self.a[op.orig_line]});
                }
            }
        }

        // For change, print separator
        if (std.mem.eql(u8, cmd, "c")) {
            try self.stdout.print("---\n", .{});
        }

        // Print inserted lines (>) for add or change
        if (std.mem.eql(u8, cmd, "a") or std.mem.eql(u8, cmd, "c")) {
            for (ops) |op| {
                if (op.op == .Insert) {
                    try self.stdout.print("> {s}\n", .{self.b[@as(usize, @intCast(op.new_line))]});
                }
            }
        }
    }
};
