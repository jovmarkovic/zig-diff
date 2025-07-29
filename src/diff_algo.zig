// A basic implementation of Myers' Diff algorithm in Zig.
// This computes the shortest edit script (SES) between two sequences,
// representing changes (insertions, deletions, keeps) to transform one sequence into another.
//
// The algorithm uses a dynamic programming approach with a "trace" of intermediate vectors (V arrays)
// that store the furthest-reaching points on each diagonal k at each edit distance d.
// The trace is essential for backtracking to reconstruct the actual diff operations.
//
// Reference: Myers, Eugene W. "An O(ND) Difference Algorithm and Its Variations." Algorithmica, 1986.

const std = @import("std");

/// The trace stores snapshots of the vector V at each edit distance d,
/// where V[k + offset] stores the furthest x coordinate reached on diagonal k.
pub const Trace = std.ArrayList([]usize);

/// Computes the Myers diff trace for two sequences with lengths `a_len` and `b_len`.
///
/// - `allocator` is used to allocate temporary arrays and trace memory.
/// - `comparison` is a function that returns true if elements at given indices are equal.
///
/// Returns a trace of vectors that can be used to backtrack and reconstruct the diff.
///
/// The algorithm tries increasing edit distances `d` from 0 to max (a_len + b_len).
/// For each diagonal `k` from -d to d (step 2), it calculates the furthest `x` reached.
/// It then "follows the snake," advancing while elements match on both sequences.
///
/// Once the end of both sequences is reached (`x >= a_len` and `y >= b_len`),
/// the trace is returned for later backtracking.
///
/// Throws on allocation failures.
pub fn myersDiff(
    allocator: std.mem.Allocator,
    a_len: usize,
    b_len: usize,
    ctx: ?*anyopaque,
    compare: fn (ctx: ?*anyopaque, usize, usize) bool,
) !Trace {
    var trace = Trace.init(allocator);
    // Defer trace.deinit() is ran from fn main

    // Maximum number of steps needed (worst case: delete all a_len lines + insert all b_len lines)
    const max_d = a_len + b_len;

    // Offset added to diagonal indices k to map to vector indices (to avoid negative indexing)
    const offset: isize = @intCast(max_d);

    // Size of vector V: 2 * max_d + 1 to cover all possible diagonals [-max_d, max_d]
    const vec_size = 2 * max_d + 1;

    // Allocate vector V that holds the furthest x coordinate for each diagonal k at current d
    var v = try allocator.alloc(usize, vec_size);
    defer allocator.free(v);

    // Initialize origin: at d=0, the furthest reaching point on diagonal 0 is (0,0)
    // The indexing is shifted by offset, so diagonal k=0 is at v[offset]
    v[max_d + 1] = 0; // Note: using max_d instead of offset to match var type

    // Iterate over increasing edit distances d = 0..max_d
    var d: usize = 0;
    while (d <= max_d) : (d += 1) {
        // Make a copy of vector V at current d and save in trace for backtracking
        const v_copy = try allocator.dupe(usize, v);
        try trace.append(v_copy);

        // For each diagonal k in [-d, d], stepping by 2 (only odd or even k at each d)
        var k: isize = -@as(isize, @intCast(d));
        while (k <= d) : (k += 2) {
            // Move diagonal index into positive range by adding offset to it
            const o_k: usize = @intCast(offset + k);

            var x: usize = 0;

            // Decide whether to move down (insert) or right (delete)
            // The choice depends on which of the two possible previous positions
            // leads to a further x coordinate:
            // - If at lower boundary of k or v[k-1] + 1 < v[k+1], move down (insert)
            // - Otherwise move right (delete)
            if (k == -@as(isize, @intCast(d)) or (k != @as(isize, @intCast(d)) and v[o_k - 1] < v[o_k + 1])) {
                // Insert: advance along diagonal k+1 (down in the grid)
                x = v[o_k + 1];
            } else {
                // Delete: advance along diagonal k-1 (right in the grid)
                x = v[o_k - 1] + 1;
            }

            // Calculate y coordinate on diagonal k: y = x - k
            var y = @as(isize, @intCast(x)) - k;

            // Follow "snake" — advance diagonally while elements match
            while (x < a_len and @as(usize, @intCast(y)) < b_len and compare(ctx, x, @as(usize, @intCast(y)))) {
                x += 1;
                y += 1;
            }

            // Update vector V for diagonal k at edit distance d
            v[o_k] = x;

            // If reached end of both sequences, minimal edit script is found
            if (x >= a_len and @as(usize, @intCast(y)) >= b_len) {
                return trace;
            }
        }
    }

    unreachable; // Should never reach here since solution always found within max_d steps
}
