/// Miscellaneous statement code generation (return, print, import, assert)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate return statement
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    try self.emitIndent();
    try self.emit("return ");
    if (ret.value) |value| {
        try self.genExpr(value.*);
    }
    try self.emit(";\n");
}

/// Generate from-import statement: from module import names
/// For MVP, just comment out imports - assume functions are in same file
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    try self.emitIndent();
    try self.emit("// from ");
    try self.emit(import.module);
    try self.emit(" import ");

    for (import.names, 0..) |name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(name);
        // Handle aliases if present
        if (import.asnames[i]) |asname| {
            try self.emit(" as ");
            try self.emit(asname);
        }
    }
    try self.emit("\n");
}

/// Generate print() function call
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

    try self.output.appendSlice(self.allocator, "std.debug.print(\"");

    // Generate format string
    for (args, 0..) |arg, i| {
        const arg_type = try self.type_inferrer.inferExpr(arg);
        const fmt = switch (arg_type) {
            .int => "{d}",
            .float => "{d}",
            .bool => "{}",
            .string => "{s}",
            else => "{any}",
        };
        try self.output.appendSlice(self.allocator, fmt);

        if (i < args.len - 1) {
            try self.output.appendSlice(self.allocator, " ");
        }
    }

    try self.output.appendSlice(self.allocator, "\\n\", .{");

    // Generate arguments
    for (args, 0..) |arg, i| {
        try self.genExpr(arg);
        if (i < args.len - 1) {
            try self.output.appendSlice(self.allocator, ", ");
        }
    }

    try self.output.appendSlice(self.allocator, "});\n");
}

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!(condition)) { std.debug.panic("Assertion failed", .{}); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (!(");
    try self.genExpr(assert_node.condition.*);
    try self.output.appendSlice(self.allocator, ")) {\n");

    self.indent();
    try self.emitIndent();

    if (assert_node.msg) |msg| {
        // assert x, "message"
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Assertion failed: {s}\", .{");
        try self.genExpr(msg.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // assert x
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Assertion failed\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}
