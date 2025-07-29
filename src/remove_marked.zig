const std = @import("std");

/// Filters lines from the input slice of lines by removing:
/// - Lines that start with the given `marker` (ignoring leading whitespace),
/// - Optionally, lines that are empty or contain only whitespace.
///
/// Parameters:
/// - `allocator`: Allocator used to allocate memory for the returned filtered slice.
/// - `lines_in`: Slice of input lines (each line is a slice of bytes) to process.
/// - `marker`: A byte slice; if a line (after trimming leading whitespace) starts with this marker, remove it.
///             Pass an empty slice to disable marker filtering.
/// - `skipEmptyLines`: If true, lines that are empty or contain only whitespace will be excluded.
///
/// Returns:
/// - A newly allocated slice of slices representing the filtered lines.
/// - The caller is responsible for freeing the returned slice.
///
/// Notes:
/// - The returned lines reference the original underlying buffers, so the lifetime of the original data
///   must outlive the returned slice.
/// - This function does **not** modify or concatenate lines; it simply filters out unwanted lines.
pub fn removeMarkedLines(
    allocator: std.mem.Allocator,
    lines_in: []const []const u8,
    marker: []const u8,
    skipEmptyLines: bool,
) ![]const []const u8 {
    var lines_out = std.ArrayList([]const u8).init(allocator);
    defer lines_out.deinit();

    for (lines_in) |line| {
        const trimmed_left = std.mem.trimLeft(u8, line, " \t");

        if (skipEmptyLines and std.mem.trim(u8, line, " \t").len == 0) {
            continue;
        }

        if (marker.len > 0 and std.mem.startsWith(u8, trimmed_left, marker)) {
            continue;
        }

        try lines_out.append(line);
    }

    return lines_out.toOwnedSlice();
}
