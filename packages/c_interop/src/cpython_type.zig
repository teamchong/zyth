/// CPython Type Operations
///
/// This implements type system operations for creating and managing types.
/// Critical for NumPy dtype system and custom array types.

const std = @import("std");
const cpython = @import("cpython_object.zig");

const allocator = std.heap.c_allocator;

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Check if object is a type
export fn PyType_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    // Check if it's PyType_Type or subclass
    _ = type_obj;
    
    // Simplified check
    return 0; // TODO: Implement properly
}

/// Check if object is exact type
export fn PyType_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    // Check if exactly PyType_Type
    _ = type_obj;
    
    return 0; // TODO: Implement properly
}

/// Finalize type object
export fn PyType_Ready(type_obj: *cpython.PyTypeObject) callconv(.c) c_int {
    // Initialize type object
    _ = type_obj;
    
    // Set tp_base if needed
    // Fill in inherited slots
    // Initialize __dict__
    
    // For now, just mark as ready
    return 0;
}

/// Generic type allocation
export fn PyType_GenericAlloc(type_obj: *cpython.PyTypeObject, nitems: isize) callconv(.c) ?*cpython.PyObject {
    const basic_size: usize = @intCast(type_obj.tp_basicsize);
    const item_size: usize = @intCast(type_obj.tp_itemsize);
    const num_items: usize = @intCast(nitems);
    
    const total_size = basic_size + (item_size * num_items);
    
    const memory = allocator.alignedAlloc(u8, @alignOf(cpython.PyObject), total_size) catch return null;
    
    const obj = @as(*cpython.PyObject, @ptrCast(@alignCast(memory.ptr)));
    obj.ob_refcnt = 1;
    obj.ob_type = type_obj;
    
    return obj;
}

/// Generic new
export fn PyType_GenericNew(type_obj: *cpython.PyTypeObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = kwargs;
    
    return PyType_GenericAlloc(type_obj, 0);
}

/// Check if type is subtype
export fn PyType_IsSubtype(a: *cpython.PyTypeObject, b: *cpython.PyTypeObject) callconv(.c) c_int {
    if (a == b) return 1;
    
    // Check base chain
    var current = a.tp_base;
    while (current) |base| {
        if (base == b) return 1;
        current = base.tp_base;
    }
    
    return 0;
}

/// Get type name
export fn PyType_GetName(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    if (type_obj.tp_name) |name| {
        // Create string from name
        // TODO: Use PyUnicode_FromString
        _ = name;
    }
    
    return null;
}

/// Get type qualified name
export fn PyType_GetQualName(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    // For now, same as GetName
    return PyType_GetName(type_obj);
}

/// Get type module
export fn PyType_GetModule(type_obj: *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    _ = type_obj;
    
    // Return module object
    // TODO: Look up in type's __dict__
    return null;
}

/// Get type module state
export fn PyType_GetModuleState(type_obj: *cpython.PyTypeObject) callconv(.c) ?*anyopaque {
    _ = type_obj;
    
    // Return module state pointer
    return null;
}

/// Modified type (invalidate caches)
export fn PyType_Modified(type_obj: *cpython.PyTypeObject) callconv(.c) void {
    // Increment version tag to invalidate caches
    _ = type_obj;
    
    // TODO: Implement version tagging
}

/// Has feature flag
export fn PyType_HasFeature(type_obj: *cpython.PyTypeObject, feature: c_ulong) callconv(.c) c_int {
    if ((type_obj.tp_flags & feature) \!= 0) {
        return 1;
    }
    return 0;
}

/// Get flags
export fn PyType_GetFlags(type_obj: *cpython.PyTypeObject) callconv(.c) c_ulong {
    return type_obj.tp_flags;
}

// Type feature flags (from CPython)
pub const Py_TPFLAGS_HEAPTYPE: c_ulong = (1 << 9);
pub const Py_TPFLAGS_BASETYPE: c_ulong = (1 << 10);
pub const Py_TPFLAGS_READY: c_ulong = (1 << 12);
pub const Py_TPFLAGS_READYING: c_ulong = (1 << 13);
pub const Py_TPFLAGS_HAVE_GC: c_ulong = (1 << 14);
pub const Py_TPFLAGS_DEFAULT: c_ulong = Py_TPFLAGS_HAVE_GC;

// Tests
test "PyType function exports" {
    _ = PyType_Ready;
    _ = PyType_GenericNew;
    _ = PyType_IsSubtype;
}
