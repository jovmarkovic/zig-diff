const std = @import("std");

//fn normalizeNewlines(buffer: []const u8, allocator: std.mem.Allocator) ![]u8 {
//    var list = std.ArrayList(u8).init(allocator);
//    var i: usize = 0;
//    while (i < buffer.len) {
//        if (buffer[i] == '\r' and i + 1 < buffer.len and buffer[i + 1] == '\n') {
//            try list.append('\n');
//            i += 2;
//        } else {
//            try list.append(buffer[i]);
//            i += 1;
//        }
//    }
//    return list.toOwnedSlice();
//}

pub fn removeMarkedLines(allocator: std.mem.Allocator, buffer: []const u8, marker: ?[]const u8, skipEmptyLines: bool) ![]u8 {
    // Treat null buffer as empty slice
    const mrk = marker orelse "";

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    //  const normalized = try normalizeNewlines(buffer, allocator);

    const newline_delim: u8 = if (std.mem.indexOf(u8, buffer, "\r\n") != null) '\r' else '\n';
    var iter = std.mem.splitScalar(u8, buffer, newline_delim);

    while (iter.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");

        if (skipEmptyLines) {
            const fully_trimmed = std.mem.trim(u8, line, " \t");
            if (fully_trimmed.len == 0) {
                continue; // skip empty/whitespace-only lines
            }
        }

        if (mrk.len > 0 and std.mem.startsWith(u8, trimmed, mrk)) {
            // skip lines starting with marker after optional indent
            continue;
        }

        try list.appendSlice(line);
        try list.append('\n');
    }

    return list.toOwnedSlice();
}
