const std = @import("std");

const c = @cImport({
    @cInclude("zlib.h");
});

pub fn compress(data: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const bound = c.compressBound(@intCast(data.len));
    var compressed = try allocator.alloc(u8, bound);
    var compressed_len: c.uLongf = bound;

    const rc = c.compress(
        compressed.ptr,
        &compressed_len,
        data.ptr,
        @intCast(data.len)
    );

    if (rc != c.Z_OK) {
        return error.CompressFailed;
    }

    return compressed[0..compressed_len];
}

pub fn decompress(data: []const u8, original_size: usize, allocator: std.mem.Allocator) ![]u8 {
    var decompressed = try allocator.alloc(u8, original_size);
    var decompressed_len: c.uLongf = @intCast(original_size);

    const rc = c.uncompress(
        decompressed.ptr,
        &decompressed_len,
        data.ptr,
        @intCast(data.len)
    );

    if (rc != c.Z_OK) {
        return error.DecompressFailed;
    }

    return decompressed[0..decompressed_len];
}
