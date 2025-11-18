const std = @import("std");
const ComptimeValue = @import("comptime_eval.zig").ComptimeValue;

/// String method evaluation helpers
pub const StringOps = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StringOps {
        return .{ .allocator = allocator };
    }

    pub fn evalUpper(self: StringOps, s: []const u8) ?ComptimeValue {
        const result = self.allocator.alloc(u8, s.len) catch return null;
        for (s, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }
        return ComptimeValue{ .string = result };
    }

    pub fn evalLower(self: StringOps, s: []const u8) ?ComptimeValue {
        const result = self.allocator.alloc(u8, s.len) catch return null;
        for (s, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return ComptimeValue{ .string = result };
    }

    pub fn evalStrip(self: StringOps, s: []const u8) ?ComptimeValue {
        var start: usize = 0;
        var end: usize = s.len;

        // Strip leading whitespace
        while (start < end and std.ascii.isWhitespace(s[start])) {
            start += 1;
        }

        // Strip trailing whitespace
        while (end > start and std.ascii.isWhitespace(s[end - 1])) {
            end -= 1;
        }

        const result = self.allocator.alloc(u8, end - start) catch return null;
        @memcpy(result, s[start..end]);
        return ComptimeValue{ .string = result };
    }

    pub fn evalReplace(self: StringOps, s: []const u8, old: []const u8, new: []const u8) ?ComptimeValue {
        if (old.len == 0) return null; // Cannot replace empty string

        // Count occurrences
        var count: usize = 0;
        var i: usize = 0;
        while (i + old.len <= s.len) {
            if (std.mem.eql(u8, s[i .. i + old.len], old)) {
                count += 1;
                i += old.len;
            } else {
                i += 1;
            }
        }

        if (count == 0) {
            // No replacement needed, return copy
            const result = self.allocator.alloc(u8, s.len) catch return null;
            @memcpy(result, s);
            return ComptimeValue{ .string = result };
        }

        // Allocate result buffer
        const new_len = s.len - (count * old.len) + (count * new.len);
        const result = self.allocator.alloc(u8, new_len) catch return null;

        // Perform replacement
        i = 0;
        var j: usize = 0;
        while (i < s.len) {
            if (i + old.len <= s.len and std.mem.eql(u8, s[i .. i + old.len], old)) {
                @memcpy(result[j .. j + new.len], new);
                j += new.len;
                i += old.len;
            } else {
                result[j] = s[i];
                j += 1;
                i += 1;
            }
        }

        return ComptimeValue{ .string = result };
    }

    pub fn evalSplit(self: StringOps, s: []const u8, sep: []const u8) ?ComptimeValue {
        if (sep.len == 0) return null; // Cannot split by empty string

        var parts = std.ArrayList(ComptimeValue){};

        var i: usize = 0;
        var start: usize = 0;

        while (i + sep.len <= s.len) {
            if (std.mem.eql(u8, s[i .. i + sep.len], sep)) {
                // Found separator, add part
                const part = self.allocator.alloc(u8, i - start) catch {
                    parts.deinit(self.allocator);
                    return null;
                };
                @memcpy(part, s[start..i]);
                parts.append(self.allocator, ComptimeValue{ .string = part }) catch {
                    parts.deinit(self.allocator);
                    return null;
                };
                i += sep.len;
                start = i;
            } else {
                i += 1;
            }
        }

        // Add final part
        const final_part = self.allocator.alloc(u8, s.len - start) catch {
            parts.deinit(self.allocator);
            return null;
        };
        @memcpy(final_part, s[start..]);
        parts.append(self.allocator, ComptimeValue{ .string = final_part }) catch {
            parts.deinit(self.allocator);
            return null;
        };

        const result_slice = parts.toOwnedSlice(self.allocator) catch return null;
        return ComptimeValue{ .list = result_slice };
    }
};
