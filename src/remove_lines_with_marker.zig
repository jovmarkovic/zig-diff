const std = @import("std");

/// Removes lines from buffer that start with a given marker excluding whitespaces
/// and optionally skips empty or whitespace-only lines.
///
/// - allocator: Allocate memory for the output buffer.
/// - buffer: The input text to process.
/// - marker: Lines that start with this (after leading spaces/tabs) will be removed. Can be empty.
/// - skipEmptyLines: If true, lines that are only whitespace are also removed.
///
/// Returns a newly allocated slice with filtered lines.
/// Caller is responsible for freeing the returned slice.
pub fn removeMarkedLines(
    allocator: std.mem.Allocator,
    buffer: []const u8,
    marker: []const u8,
    skipEmptyLines: bool,
) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    // Normalize CRLF to LF
    const normalized = try std.mem.replaceOwned(u8, allocator, buffer, "\r\n", "\n");
    defer allocator.free(normalized);

    var iter = std.mem.splitScalar(u8, normalized, '\n');
    var first = true;

    while (iter.next()) |line| {
        const trimmed_left = std.mem.trimLeft(u8, line, " \t");

        if (skipEmptyLines and std.mem.trim(u8, line, " \t").len == 0) {
            continue;
        }

        if (marker.len > 0 and std.mem.startsWith(u8, trimmed_left, marker)) {
            continue;
        }

        if (!first) try list.append('\n');
        first = false;

        try list.appendSlice(line);
    }

    return list.toOwnedSlice();
}
