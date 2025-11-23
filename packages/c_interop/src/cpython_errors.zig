/// CPython Error Handling
const std = @import("std");
const cpython = @import("cpython_object.zig");

/// Thread-local error state
threadlocal var error_type: ?*cpython.PyObject = null;
threadlocal var error_value: ?*cpython.PyObject = null;
threadlocal var error_traceback: ?*cpython.PyObject = null;

export fn PyErr_SetString(exception: *cpython.PyObject, message: [*:0]const u8) callconv(.c) void {
    error_type = exception;
    error_value = PyBytes_FromString(message);
    error_traceback = null;
}

export fn PyErr_SetObject(exception: *cpython.PyObject, value: *cpython.PyObject) callconv(.c) void {
    error_type = exception;
    error_value = value;
    error_traceback = null;
    if (value != null) Py_INCREF(value);
}

export fn PyErr_Occurred() callconv(.c) ?*cpython.PyObject {
    return error_type;
}

export fn PyErr_Clear() callconv(.c) void {
    if (error_type) |t| { Py_DECREF(t); error_type = null; }
    if (error_value) |v| { Py_DECREF(v); error_value = null; }
    if (error_traceback) |tb| { Py_DECREF(tb); error_traceback = null; }
}

export fn PyErr_Fetch(ptype: **cpython.PyObject, pvalue: **cpython.PyObject, ptraceback: **cpython.PyObject) callconv(.c) void {
    ptype.* = error_type orelse @ptrFromInt(0);
    pvalue.* = error_value orelse @ptrFromInt(0);
    ptraceback.* = error_traceback orelse @ptrFromInt(0);
    error_type = null;
    error_value = null;
    error_traceback = null;
}

export fn PyErr_Restore(err_type: *cpython.PyObject, value: *cpython.PyObject, traceback: *cpython.PyObject) callconv(.c) void {
    PyErr_Clear();
    error_type = err_type;
    error_value = value;
    error_traceback = traceback;
}

export fn PyErr_Print() callconv(.c) void {
    if (error_value) |v| {
        _ = v;
        // TODO: Print error message
    }
}

extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyBytes_FromString([*:0]const u8) callconv(.c) ?*cpython.PyObject;

test "PyErr basic" {
    PyErr_Clear();
    try std.testing.expect(PyErr_Occurred() == null);
}
