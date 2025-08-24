const std = @import("std");

/// Enum to control whether colored output should be used.
pub const ColorMode = enum {
    auto, // Enable color automatically if output is a TTY
    always, // Always use color
    never, // Never use color
};

/// Holds ANSI escape codes for various diff elements.
pub const Colors = struct {
    header: []const u8, // Color for file headers and EOF marker
    insert: []const u8, // Color for inserted lines
    delete: []const u8, // Color for deleted lines
    reset: []const u8, // Reset color to terminal default

    /// Returns a `Colors` struct populated based on the selected `ColorMode`.
    /// - `.never` disables all colors.
    /// - `.always` and `.auto` enable ANSI escape codes.
    pub fn paint(mode: ColorMode) Colors {
        return switch (mode) {
            .never => .{
                .header = "",
                .insert = "",
                .delete = "",
                .reset = "",
            },
            .always, .auto => .{
                .header = "\x1b[36m", // turquoise / cyan
                .insert = "\x1b[32m", // green
                .delete = "\x1b[31m", // red
                .reset = "\x1b[0m",
            },
        };
    }
};

/// Helper struct for printing diff output with optional colors.
pub const Printer = struct {
    writer: @TypeOf(std.io.getStdOut().writer()), // Output writer (usually stdout)
    colors: Colors, // Colors to use for printing

    /// Initializes a `Printer` with a writer and color settings.
    pub fn init(writer: anytype, colors: Colors) Printer {
        return Printer{
            .writer = writer,
            .colors = colors,
        };
    }

    /// Prints a formatted string with color applied if enabled.
    /// - `fmt` and `args`: Like `std.io.Writer.print` format string and arguments.
    /// - `color`: ANSI escape sequence to use, or empty to disable coloring.
    pub fn printColor(
        self: *Printer,
        comptime fmt: []const u8,
        args: anytype,
        color: []const u8,
    ) !void {
        if (self.colors.header.len > 0) {
            try self.writer.print("{s}" ++ fmt ++ "{s}", .{color} ++ args ++ .{self.colors.reset});
        } else {
            try self.writer.print(fmt, args);
        }
    }

    /// Prints formatted output without any color.
    pub fn printRaw(self: *Printer, comptime fmt: []const u8, args: anytype) !void {
        try self.writer.print(fmt, args);
    }
};

/// Holds slices of lines from two files for comparison.
pub const FileBuffers = struct {
    lines1: []const []const u8, // Lines from first file
    lines2: []const []const u8, // Lines from second file
};

/// Context used for comparing lines between two file buffers.
pub const EqlContext = struct {
    f1: []const []const u8,
    f2: []const []const u8,

    /// Compares lines at the given indices `i` and `j`.
    /// Returns `true` if lines are equal.
    pub fn compare(self: *EqlContext, i: usize, j: usize) bool {
        if (i >= self.f1.len or j >= self.f2.len) return false;
        return std.mem.eql(u8, self.f1[i], self.f2[j]);
    }
};

/// Adapter function for generic equality callbacks.
/// - `ctx`: Pointer to `EqlContext`.
/// - `i`, `j`: Line indices.
/// Returns `true` if lines are equal.
pub fn eql(ctx: ?*anyopaque, i: usize, j: usize) bool {
    const eql_ctx: *EqlContext = @alignCast(@ptrCast(ctx.?));
    return eql_ctx.compare(i, j);
}

/// Reads two files and splits them into line slices.
/// - `allocator`: Memory allocator for storing slices.
/// - `path1`, `path2`: Paths to input files.
/// Returns: `FileBuffers` containing slices of lines from each file.
pub fn readTwoFiles(
    allocator: std.mem.Allocator,
    path1: []const u8,
    path2: []const u8,
) !FileBuffers {
    const file1 = try std.fs.cwd().openFile(path1, .{ .mode = .read_only });
    const stat1 = try file1.stat();
    const size1 = stat1.size;
    defer file1.close();

    const file2 = try std.fs.cwd().openFile(path2, .{ .mode = .read_only });
    const stat2 = try file2.stat();
    const size2 = stat2.size;
    defer file2.close();

    const buf1 = try file1.readToEndAlloc(allocator, size1);
    const buf2 = try file2.readToEndAlloc(allocator, size2);

    const lines1 = try collectLines(allocator, buf1);
    const lines2 = try collectLines(allocator, buf2);

    return FileBuffers{ .lines1 = lines1, .lines2 = lines2 };
}

/// Splits a buffer into lines based on '\n'.
/// - `allocator`: Memory allocator for resulting array of slices.
/// - `buffer`: The input file buffer.
/// Returns: array of line slices.
pub fn collectLines(allocator: std.mem.Allocator, buffer: []const u8) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var iter = std.mem.splitScalar(u8, buffer, '\n');
    while (iter.next()) |line| {
        try lines.append(line);
    }

    return lines.toOwnedSlice();
}

/// Strips surrounding quotes from a string (single `'` or double `"`).
/// - `string`: Input string which may be quoted.
/// Returns: string slice without quotes, or the original if no quotes found.
pub fn stripQuotes(string: []const u8) []const u8 {
    if (string.len >= 2) {
        const start = string[0];
        const end = string[string.len - 1];
        if ((start == '\'' and end == '\'') or (start == '"' and end == '"')) {
            return string[1 .. string.len - 1];
        }
    }
    return string;
}
