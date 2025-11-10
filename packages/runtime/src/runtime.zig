/// Zyth Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");

/// Python exception types mapped to Zig errors
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
};

/// Python object representation
pub const PyObject = struct {
    ref_count: usize,
    type_id: TypeId,
    data: *anyopaque,

    pub const TypeId = enum {
        int,
        float,
        bool,
        string,
        list,
        tuple,
        dict,
        none,
    };
};

/// Reference counting
pub fn incref(obj: *PyObject) void {
    obj.ref_count += 1;
}

pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    obj.ref_count -= 1;
    if (obj.ref_count == 0) {
        // Free internal data based on type
        switch (obj.type_id) {
            .int => {
                const data: *PyInt = @ptrCast(@alignCast(obj.data));
                allocator.destroy(data);
            },
            .list => {
                const data: *PyList = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items.items) |item| {
                    decref(item, allocator);
                }
                data.items.deinit(data.allocator);
                allocator.destroy(data);
            },
            .tuple => {
                const data: *PyTuple = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items) |item| {
                    decref(item, allocator);
                }
                allocator.free(data.items);
                allocator.destroy(data);
            },
            .string => {
                const data: *PyString = @ptrCast(@alignCast(obj.data));
                allocator.free(data.data);
                allocator.destroy(data);
            },
            .dict => {
                const data: *PyDict = @ptrCast(@alignCast(obj.data));
                // Decref all values
                var it = data.map.valueIterator();
                while (it.next()) |value| {
                    decref(value.*, allocator);
                }
                data.map.deinit();
                allocator.destroy(data);
            },
            else => {},
        }
        allocator.destroy(obj);
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    switch (obj.type_id) {
        .int => {
            const data: *PyInt = @ptrCast(@alignCast(obj.data));
            std.debug.print("{}", .{data.value});
        },
        .string => {
            const data: *PyString = @ptrCast(@alignCast(obj.data));
            std.debug.print("{s}", .{data.data});
        },
        else => {
            // For other types, print the pointer (fallback)
            std.debug.print("{*}", .{obj});
        },
    }
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(obj.type_id == .list);
    const data: *PyList = @ptrCast(@alignCast(obj.data));

    std.debug.print("[", .{});
    for (data.items.items, 0..) |item, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        // Print each element based on its type
        switch (item.type_id) {
            .int => {
                const int_data: *PyInt = @ptrCast(@alignCast(item.data));
                std.debug.print("{}", .{int_data.value});
            },
            .string => {
                const str_data: *PyString = @ptrCast(@alignCast(item.data));
                std.debug.print("'{s}'", .{str_data.data});
            },
            else => {
                std.debug.print("{*}", .{item});
            },
        }
    }
    std.debug.print("]", .{});
}

/// Python integer type
pub const PyInt = struct {
    value: i64,

    pub fn create(allocator: std.mem.Allocator, val: i64) !*PyObject {
        const obj = try allocator.create(PyObject);
        const int_data = try allocator.create(PyInt);
        int_data.value = val;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .int,
            .data = int_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .int);
        const data: *PyInt = @ptrCast(@alignCast(obj.data));
        return data.value;
    }
};

/// Helper functions for operations that can raise exceptions

/// Integer division with zero check
pub fn divideInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @divTrunc(a, b);
}

/// Modulo with zero check
pub fn moduloInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @mod(a, b);
}

/// Python list type
pub const PyList = struct {
    items: std.ArrayList(*PyObject),
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        const obj = try allocator.create(PyObject);
        const list_data = try allocator.create(PyList);

        // Initialize ArrayList using 0.15.x unmanaged pattern
        list_data.* = PyList{
            .items = .{}, // Empty unmanaged ArrayList
            .allocator = allocator,
        };

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .list,
            .data = list_data,
        };
        return obj;
    }

    pub fn append(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        try data.items.append(data.allocator, item);
        incref(item);
    }

    pub fn pop(obj: *PyObject, allocator: std.mem.Allocator) PythonError!*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        if (data.items.items.len == 0) {
            return PythonError.IndexError;
        }
        // pop() returns the last element and removes it
        const item = data.items.items[data.items.items.len - 1];
        _ = data.items.pop(); // Remove it from the list
        // Don't decref - we're transferring ownership to caller
        _ = allocator; // Unused but kept for consistency
        return item;
    }

    pub fn getItem(obj: *PyObject, idx: usize) PythonError!*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        if (idx >= data.items.items.len) {
            return PythonError.IndexError;
        }
        return data.items.items[idx];
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        return data.items.items.len;
    }

    pub fn contains(obj: *PyObject, value: *PyObject) bool {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Check each item in the list
        for (data.items.items) |item| {
            // For now, only support comparing integers
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    return true;
                }
            }
            // Could add string comparison here later
        }
        return false;
    }

    pub fn slice(obj: *PyObject, allocator: std.mem.Allocator, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        const list_len: i64 = @intCast(data.items.items.len);
        const step: i64 = step_opt orelse 1;

        if (step == 0) {
            return PythonError.ValueError; // Step cannot be zero
        }

        // Handle defaults and bounds
        var start: i64 = start_opt orelse (if (step > 0) 0 else list_len - 1);
        var end: i64 = end_opt orelse (if (step > 0) list_len else -list_len - 1);

        // Handle negative indices
        if (start < 0) start = @max(0, list_len + start);
        if (end < 0) end = @max(0, list_len + end);

        // Clamp to valid range
        start = @max(0, @min(start, list_len));
        end = @max(0, @min(end, list_len));

        // Create new list
        const new_list = try create(allocator);
        const new_data: *PyList = @ptrCast(@alignCast(new_list.data));

        // Copy elements with step
        if (step > 0) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_usize: usize = @intCast(step);
            var i: usize = start_idx;
            while (i < end_idx) : (i += step_usize) {
                const item = data.items.items[i];
                try new_data.items.append(allocator, item);
                incref(item);
            }
        } else {
            // Negative step - iterate backwards
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            var i: usize = start_idx;
            while (i > end_idx) {
                const item = data.items.items[i];
                try new_data.items.append(allocator, item);
                incref(item);
                if (i < step_neg) break;
                i -= step_neg;
            }
        }

        return new_list;
    }

    pub fn extend(obj: *PyObject, other: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        std.debug.assert(other.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const other_data: *PyList = @ptrCast(@alignCast(other.data));

        // Append all items from other list
        for (other_data.items.items) |item| {
            try data.items.append(data.allocator, item);
            incref(item);
        }
    }

    pub fn remove(obj: *PyObject, allocator: std.mem.Allocator, value: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const alloc = allocator; // Use passed allocator for consistency
        _ = alloc;

        // Find and remove first occurrence
        for (data.items.items, 0..) |item, i| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    // Found it - remove and decref
                    const removed = data.items.orderedRemove(i);
                    decref(removed, data.allocator);
                    return;
                }
            }
        }
        // If not found, Python raises ValueError, but we'll silently ignore for now
    }

    pub fn reverse(obj: *PyObject) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        std.mem.reverse(*PyObject, data.items.items);
    }

    pub fn count(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        var count_val: i64 = 0;
        for (data.items.items) |item| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    count_val += 1;
                }
            }
        }
        return count_val;
    }

    pub fn index(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Find first occurrence
        for (data.items.items, 0..) |item, i| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    return @intCast(i);
                }
            }
        }
        // If not found, Python raises ValueError, but we'll return -1 for now
        return -1;
    }

    pub fn insert(obj: *PyObject, allocator: std.mem.Allocator, idx: i64, value: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const alloc = allocator; // Use passed allocator for consistency
        _ = alloc;

        const list_len: i64 = @intCast(data.items.items.len);
        var index_pos: i64 = idx;

        // Handle negative indices
        if (index_pos < 0) index_pos = @max(0, list_len + index_pos);

        // Clamp to valid range
        index_pos = @max(0, @min(index_pos, list_len));

        const insert_idx: usize = @intCast(index_pos);
        try data.items.insert(data.allocator, insert_idx, value);
        incref(value);
    }

    pub fn clear(obj: *PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        _ = allocator;

        // Decref all items
        for (data.items.items) |item| {
            decref(item, data.allocator);
        }

        data.items.clearAndFree(data.allocator);
    }

    pub fn sort(obj: *PyObject) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Simple bubble sort for integer lists
        const items = data.items.items;
        if (items.len <= 1) return;

        var i: usize = 0;
        while (i < items.len) : (i += 1) {
            var j: usize = 0;
            while (j < items.len - i - 1) : (j += 1) {
                if (items[j].type_id == .int and items[j + 1].type_id == .int) {
                    const val_j = PyInt.getValue(items[j]);
                    const val_j1 = PyInt.getValue(items[j + 1]);
                    if (val_j > val_j1) {
                        // Swap
                        const temp = items[j];
                        items[j] = items[j + 1];
                        items[j + 1] = temp;
                    }
                }
            }
        }
    }

    pub fn copy(obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        const new_list = try create(allocator);
        const new_data: *PyList = @ptrCast(@alignCast(new_list.data));

        // Copy all items and incref
        for (data.items.items) |item| {
            try new_data.items.append(allocator, item);
            incref(item);
        }

        return new_list;
    }

    pub fn len_method(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        return @intCast(data.items.items.len);
    }

    pub fn min(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        if (data.items.items.len == 0) return 0;

        var min_val: i64 = std.math.maxInt(i64);
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                const val = PyInt.getValue(item);
                if (val < min_val) {
                    min_val = val;
                }
            }
        }

        return min_val;
    }

    pub fn max(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        if (data.items.items.len == 0) return 0;

        var max_val: i64 = std.math.minInt(i64);
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                const val = PyInt.getValue(item);
                if (val > max_val) {
                    max_val = val;
                }
            }
        }

        return max_val;
    }

    pub fn sum(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        var total: i64 = 0;
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                total += PyInt.getValue(item);
            }
        }

        return total;
    }
};

/// Python tuple type (immutable sequence)
pub const PyTuple = struct {
    items: []*PyObject,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, size: usize) !*PyObject {
        const obj = try allocator.create(PyObject);
        const tuple_data = try allocator.create(PyTuple);

        // Allocate fixed-size array for items
        const items = try allocator.alloc(*PyObject, size);

        tuple_data.* = PyTuple{
            .items = items,
            .allocator = allocator,
        };

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .tuple,
            .data = tuple_data,
        };
        return obj;
    }

    pub fn setItem(obj: *PyObject, idx: usize, item: *PyObject) void {
        std.debug.assert(obj.type_id == .tuple);
        const data: *PyTuple = @ptrCast(@alignCast(obj.data));
        std.debug.assert(idx < data.items.len);
        data.items[idx] = item;
        incref(item);
    }

    pub fn getItem(obj: *PyObject, idx: usize) PythonError!*PyObject {
        std.debug.assert(obj.type_id == .tuple);
        const data: *PyTuple = @ptrCast(@alignCast(obj.data));
        if (idx >= data.items.len) {
            return PythonError.IndexError;
        }
        return data.items[idx];
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .tuple);
        const data: *PyTuple = @ptrCast(@alignCast(obj.data));
        return data.items.len;
    }

    pub fn len_method(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .tuple);
        const data: *PyTuple = @ptrCast(@alignCast(obj.data));
        return @intCast(data.items.len);
    }
};

/// Python string type
pub const PyString = struct {
    data: []const u8,

    pub fn create(allocator: std.mem.Allocator, str: []const u8) !*PyObject {
        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        const owned = try allocator.dupe(u8, str);
        str_data.data = owned;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

    pub fn getValue(obj: *PyObject) []const u8 {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        return data.data;
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        return data.data.len;
    }

    pub fn concat(allocator: std.mem.Allocator, a: *PyObject, b: *PyObject) !*PyObject {
        std.debug.assert(a.type_id == .string);
        std.debug.assert(b.type_id == .string);
        const a_data: *PyString = @ptrCast(@alignCast(a.data));
        const b_data: *PyString = @ptrCast(@alignCast(b.data));

        const result = try allocator.alloc(u8, a_data.data.len + b_data.data.len);
        @memcpy(result[0..a_data.data.len], a_data.data);
        @memcpy(result[a_data.data.len..], b_data.data);

        const obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        str_data.data = result;

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return obj;
    }

    pub fn upper(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
        for (data.data, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }

        const new_obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        str_data.data = result;

        new_obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return new_obj;
    }

    pub fn lower(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
        for (data.data, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }

        const new_obj = try allocator.create(PyObject);
        const str_data = try allocator.create(PyString);
        str_data.data = result;

        new_obj.* = PyObject{
            .ref_count = 1,
            .type_id = .string,
            .data = str_data,
        };
        return new_obj;
    }

    pub fn contains(obj: *PyObject, substring: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(substring.type_id == .string);
        const haystack_data: *PyString = @ptrCast(@alignCast(obj.data));
        const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

        const haystack = haystack_data.data;
        const needle = needle_data.data;

        // Empty string is always contained
        if (needle.len == 0) return true;

        // Needle longer than haystack
        if (needle.len > haystack.len) return false;

        // Search for substring
        var i: usize = 0;
        while (i <= haystack.len - needle.len) : (i += 1) {
            if (std.mem.eql(u8, haystack[i..i + needle.len], needle)) {
                return true;
            }
        }
        return false;
    }

    pub fn slice(obj: *PyObject, allocator: std.mem.Allocator, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const str_len: i64 = @intCast(data.data.len);
        const step: i64 = step_opt orelse 1;

        if (step == 0) {
            return PythonError.ValueError; // Step cannot be zero
        }

        // Handle defaults and bounds
        var start: i64 = start_opt orelse (if (step > 0) 0 else str_len - 1);
        var end: i64 = end_opt orelse (if (step > 0) str_len else -str_len - 1);

        // Handle negative indices
        if (start < 0) start = @max(0, str_len + start);
        if (end < 0) end = @max(0, str_len + end);

        // Clamp to valid range
        start = @max(0, @min(start, str_len));
        end = @max(0, @min(end, str_len));

        // If step is 1, we can use simple substring extraction (optimization)
        if (step == 1) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const substring = data.data[start_idx..end_idx];
            return try create(allocator, substring);
        }

        // Calculate result size for step != 1
        var result_len: usize = 0;
        if (step > 0) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_usize: usize = @intCast(step);
            if (end_idx > start_idx) {
                result_len = (end_idx - start_idx + step_usize - 1) / step_usize;
            }
        } else {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            if (start_idx > end_idx) {
                result_len = (start_idx - end_idx + step_neg - 1) / step_neg;
            }
        }

        // Allocate result buffer
        const result = try allocator.alloc(u8, result_len);
        var result_idx: usize = 0;

        // Fill result with step
        if (step > 0) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_usize: usize = @intCast(step);
            var i: usize = start_idx;
            while (i < end_idx and result_idx < result_len) : (i += step_usize) {
                result[result_idx] = data.data[i];
                result_idx += 1;
            }
        } else {
            // Negative step - iterate backwards
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            var i: usize = start_idx;
            while (i > end_idx and result_idx < result_len) {
                result[result_idx] = data.data[i];
                result_idx += 1;
                if (i < step_neg) break;
                i -= step_neg;
            }
        }

        // Create new string from result
        return try create(allocator, result);
    }

    pub fn split(allocator: std.mem.Allocator, obj: *PyObject, separator: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(separator.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const sep_data: *PyString = @ptrCast(@alignCast(separator.data));

        const str = data.data;
        const sep = sep_data.data;

        // Create result list
        const result = try PyList.create(allocator);

        // Handle empty separator (split into chars)
        if (sep.len == 0) {
            for (str) |c| {
                const char_obj = try create(allocator, &[_]u8{c});
                try PyList.append(result, char_obj);
            }
            return result;
        }

        // Split by separator
        var start: usize = 0;
        var i: usize = 0;
        while (i <= str.len - sep.len) {
            if (std.mem.eql(u8, str[i..i + sep.len], sep)) {
                // Found separator - add substring
                const part = str[start..i];
                const part_obj = try create(allocator, part);
                try PyList.append(result, part_obj);
                i += sep.len;
                start = i;
            } else {
                i += 1;
            }
        }

        // Add final part
        const final_part = str[start..];
        const final_obj = try create(allocator, final_part);
        try PyList.append(result, final_obj);

        return result;
    }

    pub fn strip(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str = data.data;

        // Find first non-whitespace
        var start: usize = 0;
        while (start < str.len and std.ascii.isWhitespace(str[start])) : (start += 1) {}

        // Find last non-whitespace
        var end: usize = str.len;
        while (end > start and std.ascii.isWhitespace(str[end - 1])) : (end -= 1) {}

        // Create stripped string
        const stripped = str[start..end];
        return try create(allocator, stripped);
    }

    pub fn replace(allocator: std.mem.Allocator, obj: *PyObject, old: *PyObject, new: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(old.type_id == .string);
        std.debug.assert(new.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const old_data: *PyString = @ptrCast(@alignCast(old.data));
        const new_data: *PyString = @ptrCast(@alignCast(new.data));

        const str = data.data;
        const old_str = old_data.data;
        const new_str = new_data.data;

        // Count occurrences to allocate result
        var count: usize = 0;
        var i: usize = 0;
        while (i <= str.len - old_str.len) {
            if (std.mem.eql(u8, str[i..i + old_str.len], old_str)) {
                count += 1;
                i += old_str.len;
            } else {
                i += 1;
            }
        }

        // If no replacements, return copy of original
        if (count == 0) {
            return try create(allocator, str);
        }

        // Calculate result size and allocate
        const result_len = str.len - (count * old_str.len) + (count * new_str.len);
        const result = try allocator.alloc(u8, result_len);

        // Build result string
        var src_idx: usize = 0;
        var dst_idx: usize = 0;
        while (src_idx < str.len) {
            if (src_idx <= str.len - old_str.len and std.mem.eql(u8, str[src_idx..src_idx + old_str.len], old_str)) {
                // Copy replacement
                @memcpy(result[dst_idx..dst_idx + new_str.len], new_str);
                src_idx += old_str.len;
                dst_idx += new_str.len;
            } else {
                // Copy original char
                result[dst_idx] = str[src_idx];
                src_idx += 1;
                dst_idx += 1;
            }
        }

        return try create(allocator, result);
    }

    pub fn startswith(obj: *PyObject, prefix: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(prefix.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const prefix_data: *PyString = @ptrCast(@alignCast(prefix.data));

        const str = data.data;
        const pre = prefix_data.data;

        if (pre.len > str.len) return false;
        return std.mem.eql(u8, str[0..pre.len], pre);
    }

    pub fn endswith(obj: *PyObject, suffix: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(suffix.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const suffix_data: *PyString = @ptrCast(@alignCast(suffix.data));

        const str = data.data;
        const suf = suffix_data.data;

        if (suf.len > str.len) return false;
        return std.mem.eql(u8, str[str.len - suf.len..], suf);
    }

    pub fn find(obj: *PyObject, substring: *PyObject) i64 {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(substring.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

        const haystack = data.data;
        const needle = needle_data.data;

        // Empty string is found at position 0
        if (needle.len == 0) return 0;

        // Needle longer than haystack
        if (needle.len > haystack.len) return -1;

        // Search for substring
        var i: usize = 0;
        while (i <= haystack.len - needle.len) : (i += 1) {
            if (std.mem.eql(u8, haystack[i..i + needle.len], needle)) {
                return @intCast(i);
            }
        }
        return -1;
    }

    pub fn count_substr(obj: *PyObject, substring: *PyObject) i64 {
        std.debug.assert(obj.type_id == .string);
        std.debug.assert(substring.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const needle_data: *PyString = @ptrCast(@alignCast(substring.data));

        const str = data.data;
        const sub = needle_data.data;

        if (sub.len == 0) return 0;
        if (sub.len > str.len) return 0;

        var count_val: i64 = 0;
        var i: usize = 0;
        while (i <= str.len - sub.len) {
            if (std.mem.eql(u8, str[i..i + sub.len], sub)) {
                count_val += 1;
                i += sub.len; // Move past this occurrence
            } else {
                i += 1;
            }
        }
        return count_val;
    }

    pub fn join(allocator: std.mem.Allocator, separator: *PyObject, list: *PyObject) !*PyObject {
        std.debug.assert(separator.type_id == .string);
        std.debug.assert(list.type_id == .list);
        const sep_data: *PyString = @ptrCast(@alignCast(separator.data));
        const list_data: *PyList = @ptrCast(@alignCast(list.data));

        const sep = sep_data.data;
        const items = list_data.items.items;

        if (items.len == 0) {
            return try create(allocator, "");
        }

        // Calculate total length
        var total_len: usize = 0;
        for (items) |item| {
            if (item.type_id == .string) {
                const item_data: *PyString = @ptrCast(@alignCast(item.data));
                total_len += item_data.data.len;
            }
        }
        total_len += sep.len * (items.len - 1);

        // Build result
        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        for (items, 0..) |item, i| {
            if (item.type_id == .string) {
                const item_data: *PyString = @ptrCast(@alignCast(item.data));
                @memcpy(result[pos..pos + item_data.data.len], item_data.data);
                pos += item_data.data.len;

                if (i < items.len - 1) {
                    @memcpy(result[pos..pos + sep.len], sep);
                    pos += sep.len;
                }
            }
        }

        return try create(allocator, result);
    }

    pub fn isdigit(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str = data.data;

        if (str.len == 0) return false;

        for (str) |c| {
            if (!std.ascii.isDigit(c)) {
                return false;
            }
        }
        return true;
    }

    pub fn isalpha(obj: *PyObject) bool {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));
        const str = data.data;

        if (str.len == 0) return false;

        for (str) |c| {
            if (!std.ascii.isAlphabetic(c)) {
                return false;
            }
        }
        return true;
    }

    pub fn capitalize(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        if (data.data.len == 0) {
            return try create(allocator, "");
        }

        const result = try allocator.alloc(u8, data.data.len);
        result[0] = std.ascii.toUpper(data.data[0]);

        for (data.data[1..], 0..) |c, i| {
            result[i + 1] = std.ascii.toLower(c);
        }

        return try create(allocator, result);
    }

    pub fn swapcase(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
        for (data.data, 0..) |c, i| {
            if (std.ascii.isUpper(c)) {
                result[i] = std.ascii.toLower(c);
            } else if (std.ascii.isLower(c)) {
                result[i] = std.ascii.toUpper(c);
            } else {
                result[i] = c;
            }
        }

        return try create(allocator, result);
    }

    pub fn title(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const result = try allocator.alloc(u8, data.data.len);
        var prev_was_alpha = false;

        for (data.data, 0..) |c, i| {
            if (std.ascii.isAlphabetic(c)) {
                if (!prev_was_alpha) {
                    result[i] = std.ascii.toUpper(c);
                } else {
                    result[i] = std.ascii.toLower(c);
                }
                prev_was_alpha = true;
            } else {
                result[i] = c;
                prev_was_alpha = false;
            }
        }

        return try create(allocator, result);
    }

    pub fn center(allocator: std.mem.Allocator, obj: *PyObject, width: i64) !*PyObject {
        std.debug.assert(obj.type_id == .string);
        const data: *PyString = @ptrCast(@alignCast(obj.data));

        const w: usize = @intCast(width);
        if (w <= data.data.len) {
            return try create(allocator, data.data);
        }

        const total_padding = w - data.data.len;
        const left_padding = total_padding / 2;
        const right_padding = total_padding - left_padding;
        _ = right_padding; // Calculated for clarity, actual padding is handled by slice

        const result = try allocator.alloc(u8, w);
        @memset(result[0..left_padding], ' ');
        @memcpy(result[left_padding..left_padding + data.data.len], data.data);
        @memset(result[left_padding + data.data.len..], ' ');

        return try create(allocator, result);
    }
};

/// Python dict type (simplified - using StringHashMap)
pub const PyDict = struct {
    map: std.StringHashMap(*PyObject),

    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        const obj = try allocator.create(PyObject);
        const dict_data = try allocator.create(PyDict);
        dict_data.map = std.StringHashMap(*PyObject).init(allocator);

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .dict,
            .data = dict_data,
        };
        return obj;
    }

    pub fn set(obj: *PyObject, key: []const u8, value: *PyObject) !void {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        try data.map.put(key, value);
        incref(value);
    }

    pub fn get(obj: *PyObject, key: []const u8) ?*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        return data.map.get(key);
    }

    pub fn contains(obj: *PyObject, key: []const u8) bool {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        return data.map.contains(key);
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        return data.map.count();
    }

    pub fn keys(obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));

        // Create list to hold keys
        const result = try PyList.create(allocator);

        // Add all keys as PyString objects
        var iterator = data.map.keyIterator();
        while (iterator.next()) |key| {
            const key_obj = try PyString.create(allocator, key.*);
            try PyList.append(result, key_obj);
        }

        return result;
    }

    pub fn values(obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));

        // Create list to hold values
        const result = try PyList.create(allocator);

        // Add all values
        var iterator = data.map.valueIterator();
        while (iterator.next()) |value| {
            try PyList.append(result, value.*);
        }

        return result;
    }

    pub fn getWithDefault(obj: *PyObject, allocator: std.mem.Allocator, key: []const u8, default: *PyObject) *PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        _ = allocator;
        // Returns borrowed reference - caller must incref if needed
        return data.map.get(key) orelse default;
    }

    pub fn get_method(obj: *PyObject, allocator: std.mem.Allocator, key: *PyObject, default: *PyObject) *PyObject {
        std.debug.assert(obj.type_id == .dict);
        std.debug.assert(key.type_id == .string);
        const key_data: *PyString = @ptrCast(@alignCast(key.data));
        return getWithDefault(obj, allocator, key_data.data, default);
    }

    pub fn pop(obj: *PyObject, allocator: std.mem.Allocator, key: []const u8) ?*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        _ = allocator;

        // Get value before removing
        if (data.map.fetchRemove(key)) |entry| {
            return entry.value;
        }
        return null;
    }

    pub fn pop_method(obj: *PyObject, allocator: std.mem.Allocator, key: *PyObject) ?*PyObject {
        std.debug.assert(obj.type_id == .dict);
        std.debug.assert(key.type_id == .string);
        const key_data: *PyString = @ptrCast(@alignCast(key.data));
        return pop(obj, allocator, key_data.data);
    }

    pub fn clear(obj: *PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        const alloc = allocator; // Use passed allocator for consistency
        _ = alloc;

        // Decref all values before clearing
        var iterator = data.map.valueIterator();
        while (iterator.next()) |value| {
            decref(value.*, data.map.allocator);
        }

        data.map.clearAndFree();
    }

    pub fn items(obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));

        // Create list to hold items
        const result = try PyList.create(allocator);

        // Add all (key, value) pairs as 2-element tuples
        var iterator = data.map.iterator();
        while (iterator.next()) |entry| {
            const pair = try PyTuple.create(allocator, 2);
            const key_obj = try PyString.create(allocator, entry.key_ptr.*);
            PyTuple.setItem(pair, 0, key_obj);
            PyTuple.setItem(pair, 1, entry.value_ptr.*);
            try PyList.append(result, pair);
        }

        return result;
    }

    pub fn update(obj: *PyObject, other: *PyObject) !void {
        std.debug.assert(obj.type_id == .dict);
        std.debug.assert(other.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));
        const other_data: *PyDict = @ptrCast(@alignCast(other.data));

        // Copy all entries from other dict
        var iterator = other_data.map.iterator();
        while (iterator.next()) |entry| {
            try data.map.put(entry.key_ptr.*, entry.value_ptr.*);
            incref(entry.value_ptr.*);
        }
    }

    pub fn copy(obj: *PyObject, allocator: std.mem.Allocator) !*PyObject {
        std.debug.assert(obj.type_id == .dict);
        const data: *PyDict = @ptrCast(@alignCast(obj.data));

        const new_dict = try create(allocator);
        const new_data: *PyDict = @ptrCast(@alignCast(new_dict.data));

        // Copy all entries
        var iterator = data.map.iterator();
        while (iterator.next()) |entry| {
            try new_data.map.put(entry.key_ptr.*, entry.value_ptr.*);
            incref(entry.value_ptr.*);
        }

        return new_dict;
    }
};

// Tests
test "PyInt creation and retrieval" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);
    defer decref(obj, allocator);

    try std.testing.expectEqual(@as(i64, 42), PyInt.getValue(obj));
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
}

test "PyList append and retrieval" {
    const allocator = std.testing.allocator;
    const list = try PyList.create(allocator);
    defer decref(list, allocator);

    const item1 = try PyInt.create(allocator, 10);
    const item2 = try PyInt.create(allocator, 20);

    try PyList.append(list, item1);
    try PyList.append(list, item2);

    // Transfer ownership to list (decref our references)
    decref(item1, allocator);
    decref(item2, allocator);

    try std.testing.expectEqual(@as(usize, 2), PyList.len(list));
    try std.testing.expectEqual(@as(i64, 10), PyInt.getValue(try PyList.getItem(list, 0)));
    try std.testing.expectEqual(@as(i64, 20), PyInt.getValue(try PyList.getItem(list, 1)));
}

test "PyString creation" {
    const allocator = std.testing.allocator;
    const obj = try PyString.create(allocator, "hello");
    defer decref(obj, allocator);

    const value = PyString.getValue(obj);
    try std.testing.expectEqualStrings("hello", value);
}

test "PyDict set and get" {
    const allocator = std.testing.allocator;
    const dict = try PyDict.create(allocator);
    defer decref(dict, allocator);

    const value = try PyInt.create(allocator, 100);
    try PyDict.set(dict, "key", value);

    // Transfer ownership to dict
    decref(value, allocator);

    const retrieved = PyDict.get(dict, "key");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(i64, 100), PyInt.getValue(retrieved.?));
}

test "reference counting" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);

    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    incref(obj);
    try std.testing.expectEqual(@as(usize, 2), obj.ref_count);

    decref(obj, allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    decref(obj, allocator);
    // Object should be destroyed here
}
