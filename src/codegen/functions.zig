const std = @import("std");
const ast = @import("../ast.zig");
const codegen = @import("../codegen.zig");
const statements = @import("statements.zig");

const ZigCodeGenerator = codegen.ZigCodeGenerator;
const ExprResult = codegen.ExprResult;
const CodegenError = codegen.CodegenError;

/// Generate code for function definition
pub fn visitFunctionDef(self: *ZigCodeGenerator, func: ast.Node.FunctionDef) CodegenError!void {
    if (func.is_async) {
        try emitAsyncFunction(self, func);
    } else {
        try emitSyncFunction(self, func);
    }
}

/// Generate synchronous function
fn emitSyncFunction(self: *ZigCodeGenerator, func: ast.Node.FunctionDef) CodegenError!void {
    // For now, generate simple functions with i64 parameters and return type
    // This handles common cases like fibonacci(n: int) -> int

    var buf = std.ArrayList(u8){};

    // Start function signature
    try buf.writer(self.temp_allocator).print("fn {s}(", .{func.name});

    // Add parameters - assume i64 for now
    for (func.args, 0..) |arg, i| {
        if (i > 0) {
            try buf.writer(self.temp_allocator).writeAll(", ");
        }
        try buf.writer(self.temp_allocator).print("{s}: i64", .{arg.name});
    }

    // Add allocator parameter if needed
    if (self.needs_allocator) {
        if (func.args.len > 0) {
            try buf.writer(self.temp_allocator).writeAll(", ");
        }
        try buf.writer(self.temp_allocator).writeAll("allocator: std.mem.Allocator");
    }

    // Close signature - assume i64 return type for now
    try buf.writer(self.temp_allocator).writeAll(") i64 {");

    try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
    self.indent();

    // Generate function body
    for (func.body) |stmt| {
        try statements.visitNode(self, stmt);
    }

    self.dedent();
    try self.emit("}");
}

/// Generate async function as frame struct
fn emitAsyncFunction(self: *ZigCodeGenerator, func: ast.Node.FunctionDef) CodegenError!void {
    // Generate frame struct
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("const {s}Frame = struct {{", .{func.name});
    try self.emitOwned(try buf.toOwnedSlice(self.temp_allocator));
    self.indent();

    // State enum
    try self.emit("state: enum { start, running, done } = .start,");

    // Parameters as fields
    for (func.args) |arg| {
        var param_buf = std.ArrayList(u8){};
        try param_buf.writer(self.temp_allocator).print("{s}: i64,", .{arg.name});
        try self.emitOwned(try param_buf.toOwnedSlice(self.temp_allocator));
    }

    // Result field
    try self.emit("result: ?i64 = null,");
    try self.emit("");

    // Init function
    try self.emit("pub fn init(");
    self.indent();
    for (func.args, 0..) |arg, i| {
        var init_buf = std.ArrayList(u8){};
        if (i == func.args.len - 1) {
            try init_buf.writer(self.temp_allocator).print("{s}: i64", .{arg.name});
        } else {
            try init_buf.writer(self.temp_allocator).print("{s}: i64,", .{arg.name});
        }
        try self.emitOwned(try init_buf.toOwnedSlice(self.temp_allocator));
    }
    self.dedent();
    try self.emit(") @This() {");
    self.indent();
    try self.emit("return .{");
    self.indent();
    for (func.args) |arg| {
        var field_buf = std.ArrayList(u8){};
        try field_buf.writer(self.temp_allocator).print(".{s} = {s},", .{ arg.name, arg.name });
        try self.emitOwned(try field_buf.toOwnedSlice(self.temp_allocator));
    }
    self.dedent();
    try self.emit("};");
    self.dedent();
    try self.emit("}");
    try self.emit("");

    // Resume function (simplified for Phase 1)
    try self.emit("pub fn resume(self: *@This()) !?i64 {");
    self.indent();
    try self.emit("switch (self.state) {");
    self.indent();
    try self.emit(".start => {");
    self.indent();
    try self.emit("self.state = .running;");

    // Generate function body
    for (func.body) |stmt| {
        try statements.visitNode(self, stmt);
    }

    try self.emit("self.state = .done;");
    try self.emit("return self.result;");
    self.dedent();
    try self.emit("},");
    try self.emit(".running, .done => return self.result,");
    self.dedent();
    try self.emit("}");
    self.dedent();
    try self.emit("}");

    self.dedent();
    try self.emit("};");
    try self.emit("");

    // Wrapper function that creates frame and runs it
    var wrapper_buf = std.ArrayList(u8){};
    try wrapper_buf.writer(self.temp_allocator).print("fn {s}(", .{func.name});
    for (func.args, 0..) |arg, i| {
        if (i > 0) try wrapper_buf.writer(self.temp_allocator).writeAll(", ");
        try wrapper_buf.writer(self.temp_allocator).print("{s}: i64", .{arg.name});
    }
    try wrapper_buf.writer(self.temp_allocator).writeAll(") !i64 {");
    try self.emitOwned(try wrapper_buf.toOwnedSlice(self.temp_allocator));

    self.indent();
    var init_buf = std.ArrayList(u8){};
    try init_buf.writer(self.temp_allocator).print("var frame = {s}Frame.init(", .{func.name});
    for (func.args, 0..) |arg, i| {
        if (i > 0) try init_buf.writer(self.temp_allocator).writeAll(", ");
        try init_buf.writer(self.temp_allocator).print("{s}", .{arg.name});
    }
    try init_buf.writer(self.temp_allocator).writeAll(");");
    try self.emitOwned(try init_buf.toOwnedSlice(self.temp_allocator));

    try self.emit("return (try frame.resume()).?;");
    self.dedent();
    try self.emit("}");
}

/// Generate code for user-defined function call
pub fn visitUserFunctionCall(self: *ZigCodeGenerator, func_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
    var buf = std.ArrayList(u8){};

    // Generate function call: func_name(arg1, arg2, ...)
    try buf.writer(self.temp_allocator).print("{s}(", .{func_name});

    // Add arguments
    for (args, 0..) |arg, i| {
        if (i > 0) {
            try buf.writer(self.temp_allocator).writeAll(", ");
        }
        const arg_result = try self.visitExpr(arg);
        try buf.writer(self.temp_allocator).writeAll(arg_result.code);
    }

    // Add allocator if needed
    if (self.needs_allocator and args.len > 0) {
        try buf.writer(self.temp_allocator).writeAll(", allocator");
    } else if (self.needs_allocator) {
        try buf.writer(self.temp_allocator).writeAll("allocator");
    }

    try buf.writer(self.temp_allocator).writeAll(")");

    return ExprResult{
        .code = try buf.toOwnedSlice(self.temp_allocator),
        .needs_try = false,
    };
}
