const std = @import("std");

/// Struct holding the parsed lines (as slices) from two input files.
pub const FileBuffers = struct {
    lines1: []const []const u8, // Lines from first file
    lines2: []const []const u8, // Lines from second file
};

/// Context used to compare lines between two files for equality.
/// Used in diffing algorithms to abstract how equality is checked.
pub const EqlContext = struct {
    f1: []const []const u8,
    f2: []const []const u8,

    /// Compares lines at given indices `i` and `j` from the two file buffers.
    /// Returns true if the lines are equal.
    pub fn compare(self: *EqlContext, i: usize, j: usize) bool {
        if (i >= self.f1.len or j >= self.f2.len) return false;
        return std.mem.eql(u8, self.f1[i], self.f2[j]);
    }
};

/// Comparison adapter function that casts a generic pointer to `EqlContext`.
/// Calls the compare method which is used for passing comparison into
/// diff and backtrack functions.
pub fn eql(ctx: ?*anyopaque, i: usize, j: usize) bool {
    const eql_ctx: *EqlContext = @alignCast(@ptrCast(ctx.?));
    return eql_ctx.compare(i, j);
}

/// Reads two files into memory and splits them into lines.
///
/// - `allocator`: Allocator used for memory management.
/// - `path1`: Path to the first file.
/// - `path2`: Path to the second file.
/// - `max_size`: Maximum size in bytes allowed to read from each file.
///
/// Returns a `FileBuffers` struct containing line slices for each file.
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

/// Splits a buffer into lines (based on `\n`) and returns a slice of string slices.
/// Each line is a slice into the original buffer.
///
/// - `allocator`: Allocator used for the resulting list.
/// - `buffer`: The input text buffer to split.
///
/// Returns: `[]const []const u8` — list of line slices.
pub fn collectLines(allocator: std.mem.Allocator, buffer: []const u8) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).init(allocator);
    defer lines.deinit();

    var iter = std.mem.splitScalar(u8, buffer, '\n');
    while (iter.next()) |line| {
        try lines.append(line);
    }
    return lines.toOwnedSlice();
}

/// Removes surrounding quotes (single `'` or double `"`) from a string.
///
/// - `string`: The input string which may be quoted.
/// Returns: Unquoted view into the same string, or the original if not quoted.
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
