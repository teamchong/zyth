/// CPython Bytes Operations
const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

export fn PyBytes_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyBytes_FromStringAndSize(str, @intCast(len));
}

export fn PyBytes_FromStringAndSize(str: [*]const u8, len: isize) callconv(.c) ?*cpython.PyObject {
    const bytes = allocator.create(cpython.PyBytesObject) catch return null;
    
    bytes.ob_base.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = undefined,
    };
    bytes.ob_base.ob_size = len;
    bytes.ob_shash = -1;
    
    // Allocate data
    const ulen: usize = @intCast(len);
    const data = allocator.alloc(u8, ulen + 1) catch {
        allocator.destroy(bytes);
        return null;
    };
    
    @memcpy(data[0..ulen], str[0..ulen]);
    data[ulen] = 0; // Null terminate
    
    // Store pointer after struct
    const bytes_ptr = @intFromPtr(bytes) + @sizeOf(cpython.PyBytesObject);
    @as(*[*]u8, @ptrFromInt(bytes_ptr)).* = data.ptr;
    
    return @ptrCast(&bytes.ob_base.ob_base);
}

export fn PyBytes_AsString(obj: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));
    const bytes_ptr = @intFromPtr(bytes) + @sizeOf(cpython.PyBytesObject);
    const data_ptr = @as(*[*]const u8, @ptrFromInt(bytes_ptr)).*;
    return @ptrCast(data_ptr);
}

export fn PyBytes_Size(obj: *cpython.PyObject) callconv(.c) isize {
    const bytes = @as(*cpython.PyBytesObject, @ptrCast(obj));
    return bytes.ob_base.ob_size;
}

export fn PyBytes_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 1;
}

export fn PyBytes_Concat(bytes_ptr: **cpython.PyObject, newpart: *cpython.PyObject) callconv(.c) void {
    _ = bytes_ptr;
    _ = newpart;
    // TODO: Implement concatenation
}

test "PyBytes_FromString" {
    const bytes = PyBytes_FromString("hello");
    try std.testing.expect(bytes != null);
    try std.testing.expectEqual(@as(isize, 5), PyBytes_Size(bytes.?));
}
