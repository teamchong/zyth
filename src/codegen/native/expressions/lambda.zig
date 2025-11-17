/// Lambda expression code generation
/// Generates anonymous functions as named functions with function pointers
/// With closure support using Zig structs
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

const ClosureError = error{
    NotAClosure,
} || CodegenError;
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const lambda_closure = @import("lambda_closure.zig");

/// Generate lambda expression as anonymous function
/// Strategy: Generate named function at module level, return function pointer
///
/// Example:
///   Python: lambda x: x * 2
///   Zig:    fn __lambda_0(x: i64) i64 { return x * 2; }
///           &__lambda_0
pub fn genLambda(self: *NativeCodegen, lambda: ast.Node.Lambda) ClosureError!void {
    // Check if this is a closure (lambda returning lambda)
    if (lambda.body.* == .lambda) {
        // Try closure generation
        lambda_closure.genClosureLambda(self, lambda) catch {
            // If closure generation fails, fall back to regular lambda
            // This can happen if closure support is incomplete
        };
        return;
    }

    // Check if lambda references variables from outer scope (not its parameters)
    const captured_vars = try findCapturedVars(self, lambda);
    defer self.allocator.free(captured_vars);

    if (captured_vars.len > 0) {
        // This lambda captures outer variables - treat as closure
        try lambda_closure.genSimpleClosureLambda(self, lambda, captured_vars);
        // Note: The caller (assignment) needs to mark this variable as a closure
        // We can't do it here because we don't know the variable name
        return;
    }

    // Generate unique lambda function name
    const lambda_name = try std.fmt.allocPrint(
        self.allocator,
        "__lambda_{d}",
        .{self.lambda_counter},
    );
    // Don't free yet - we need it for later
    self.lambda_counter += 1;

    // Save current output position - we'll generate lambda function separately
    const current_output = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(current_output);

    // Generate lambda function definition
    var lambda_func = std.ArrayList(u8){};

    // Function signature: fn __lambda_N(
    try lambda_func.writer(self.allocator).print("fn {s}(", .{lambda_name});

    // Parameters with type inference
    for (lambda.args, 0..) |arg, i| {
        if (i > 0) try lambda_func.appendSlice(self.allocator, ", ");

        // Infer parameter type from body expression
        // For now, default to i64 (can be enhanced with type inference)
        const param_type = "i64"; // TODO: Enhance with type inference

        try lambda_func.writer(self.allocator).print("{s}: {s}", .{
            arg.name,
            param_type,
        });
    }

    // Infer return type from body expression
    const return_type = try inferReturnType(self, lambda.body.*);
    try lambda_func.writer(self.allocator).print(") {s} {{\n", .{return_type});

    // Generate body - single return expression
    try lambda_func.appendSlice(self.allocator, "    return ");

    // Generate body expression in temporary output
    const saved_output = self.output;
    self.output = std.ArrayList(u8){};

    // Import expressions module to generate body
    const expressions = @import("../expressions.zig");
    try expressions.genExpr(self, lambda.body.*);

    const body_code = try self.output.toOwnedSlice(self.allocator);
    self.output = saved_output;

    try lambda_func.appendSlice(self.allocator, body_code);
    self.allocator.free(body_code);

    try lambda_func.appendSlice(self.allocator, ";\n}\n\n");

    // Store lambda function for later prepending to module
    try self.lambda_functions.append(self.allocator, try lambda_func.toOwnedSlice(self.allocator));

    // Restore original output
    self.output = std.ArrayList(u8){};
    try self.output.appendSlice(self.allocator, current_output);

    // Generate function pointer reference in current context
    try self.output.appendSlice(self.allocator, "&");
    try self.output.appendSlice(self.allocator, lambda_name);

    // Free lambda_name now
    self.allocator.free(lambda_name);
}

/// Public function to check if lambda captures outer variables
pub fn lambdaCapturesVars(self: *NativeCodegen, lambda: ast.Node.Lambda) bool {
    const captured_vars = findCapturedVars(self, lambda) catch return false;
    defer self.allocator.free(captured_vars);
    return captured_vars.len > 0;
}

/// Find variables captured from outer scope (not lambda parameters)
fn findCapturedVars(self: *NativeCodegen, lambda: ast.Node.Lambda) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Find all variable references in lambda body
    try findVarReferences(self, lambda.body.*, &captured);

    // Remove lambda parameters from captured list
    var filtered = std.ArrayList([]const u8){};
    for (captured.items) |var_name| {
        var is_param = false;
        for (lambda.args) |arg| {
            if (std.mem.eql(u8, var_name, arg.name)) {
                is_param = true;
                break;
            }
        }
        if (!is_param) {
            // Check if this variable is actually declared in outer scope
            if (self.isDeclared(var_name)) {
                try filtered.append(self.allocator, var_name);
            }
        }
    }

    captured.deinit(self.allocator);
    return filtered.toOwnedSlice(self.allocator);
}

/// Recursively find all variable references in AST
fn findVarReferences(self: *NativeCodegen, node: ast.Node, captured: *std.ArrayList([]const u8)) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Add to captured list if not already there
            for (captured.items) |existing| {
                if (std.mem.eql(u8, existing, n.id)) return;
            }
            try captured.append(self.allocator, n.id);
        },
        .binop => |b| {
            try findVarReferences(self, b.left.*, captured);
            try findVarReferences(self, b.right.*, captured);
        },
        .call => |c| {
            try findVarReferences(self, c.func.*, captured);
            for (c.args) |arg| {
                try findVarReferences(self, arg, captured);
            }
        },
        .compare => |cmp| {
            try findVarReferences(self, cmp.left.*, captured);
            for (cmp.comparators) |comp| {
                try findVarReferences(self, comp, captured);
            }
        },
        else => {},
    }
}

/// Infer return type from lambda body expression
fn inferReturnType(self: *NativeCodegen, body: ast.Node) CodegenError![]const u8 {
    const inferred_type = self.type_inferrer.inferExpr(body) catch {
        return "i64"; // Default fallback
    };

    return switch (inferred_type) {
        .int => "i64",
        .float => "f64",
        .bool => "bool",
        .string => "[]const u8",
        .list => |_| "std.ArrayList(i64)", // Simplified - would need element type
        .dict => "std.StringHashMap(i64)", // Simplified
        else => "i64", // Fallback
    };
}
