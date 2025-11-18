/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async
const std = @import("std");
const ast = @import("../../ast.zig");
const native_types = @import("../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;
const SemanticInfo = @import("../../analysis/types.zig").SemanticInfo;

// Import specialized modules
const json = @import("json.zig");
const http = @import("http.zig");
const async_mod = @import("async.zig");
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");
const analyzer = @import("analyzer.zig");
const dispatch = @import("dispatch.zig");
const statements = @import("statements.zig");
const expressions = @import("expressions.zig");

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
} || native_types.InferError;

pub const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    type_inferrer: *TypeInferrer,
    semantic_info: *SemanticInfo,
    indent_level: usize,

    // Variable scope tracking - stack of scopes (innermost = last)
    scopes: std.ArrayList(std.StringHashMap(void)),

    // Class registry for inheritance support - maps class name to ClassDef
    classes: std.StringHashMap(ast.Node.ClassDef),

    // Counter for unique tuple unpacking temporary variables
    unpack_counter: usize,

    // Lambda support - counter for unique names, storage for lambda function definitions
    lambda_counter: usize,
    lambda_functions: std.ArrayList([]const u8),

    // Track which variables hold closures (for .call() generation)
    closure_vars: std.StringHashMap(void),

    // Track which variables are closure factories (return closures)
    closure_factories: std.StringHashMap(void),

    // Track which variables hold simple lambdas (function pointers)
    lambda_vars: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer, semantic_info: *SemanticInfo) !*NativeCodegen {
        const self = try allocator.create(NativeCodegen);
        var scopes = std.ArrayList(std.StringHashMap(void)){};

        // Initialize with global scope
        const global_scope = std.StringHashMap(void).init(allocator);
        try scopes.append(allocator, global_scope);

        self.* = .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .semantic_info = semantic_info,
            .indent_level = 0,
            .scopes = scopes,
            .classes = std.StringHashMap(ast.Node.ClassDef).init(allocator),
            .unpack_counter = 0,
            .lambda_counter = 0,
            .lambda_functions = std.ArrayList([]const u8){},
            .closure_vars = std.StringHashMap(void).init(allocator),
            .closure_factories = std.StringHashMap(void).init(allocator),
            .lambda_vars = std.StringHashMap(void).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *NativeCodegen) void {
        self.output.deinit(self.allocator);
        // Clean up all scopes
        for (self.scopes.items) |*scope| {
            scope.deinit();
        }
        self.scopes.deinit(self.allocator);
        self.classes.deinit();
        // Clean up lambda functions
        for (self.lambda_functions.items) |lambda_code| {
            self.allocator.free(lambda_code);
        }
        self.lambda_functions.deinit(self.allocator);

        // Clean up closure tracking HashMaps (free keys)
        var closure_iter = self.closure_vars.keyIterator();
        while (closure_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_vars.deinit();

        var factory_iter = self.closure_factories.keyIterator();
        while (factory_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.closure_factories.deinit();

        var lambda_iter = self.lambda_vars.keyIterator();
        while (lambda_iter.next()) |key| {
            self.allocator.free(key.*);
        }
        self.lambda_vars.deinit();

        self.allocator.destroy(self);
    }

    /// Push new scope (call when entering loop/function/block)
    pub fn pushScope(self: *NativeCodegen) !void {
        const new_scope = std.StringHashMap(void).init(self.allocator);
        try self.scopes.append(self.allocator, new_scope);
    }

    /// Pop scope (call when exiting loop/function/block)
    pub fn popScope(self: *NativeCodegen) void {
        if (self.scopes.items.len > 0) {
            const idx = self.scopes.items.len - 1;
            self.scopes.items[idx].deinit();
            _ = self.scopes.pop();
        }
    }

    /// Check if variable declared in any scope (innermost to outermost)
    pub fn isDeclared(self: *NativeCodegen, name: []const u8) bool {
        var i: usize = self.scopes.items.len;
        while (i > 0) {
            i -= 1;
            if (self.scopes.items[i].contains(name)) return true;
        }
        return false;
    }

    /// Declare variable in current (innermost) scope
    pub fn declareVar(self: *NativeCodegen, name: []const u8) !void {
        if (self.scopes.items.len > 0) {
            const current_scope = &self.scopes.items[self.scopes.items.len - 1];
            try current_scope.put(name, {});
        }
    }

    /// Generate native Zig code for module
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        // PHASE 1: Analyze module to determine requirements
        const analysis = try analyzer.analyzeModule(module, self.allocator);

        // PHASE 2: Register all classes for inheritance support
        for (module.body) |stmt| {
            if (stmt == .class_def) {
                try self.classes.put(stmt.class_def.name, stmt.class_def);
            }
        }

        // PHASE 3: Generate imports based on analysis
        try self.emit("const std = @import(\"std\");\n");
        // Always import runtime for formatAny() and other utilities
        try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        if (analysis.needs_string_utils) {
            try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
        }
        try self.emit("\n");

        // PHASE 4: Define __name__ constant (for if __name__ == "__main__" support)
        try self.emit("const __name__ = \"__main__\";\n\n");

        // PHASE 5: Generate class and function definitions (before main)
        for (module.body) |stmt| {
            if (stmt == .class_def) {
                try statements.genClassDef(self, stmt.class_def);
                try self.emit("\n");
            } else if (stmt == .function_def) {
                try statements.genFunctionDef(self, stmt.function_def);
                try self.emit("\n");
            }
        }

        // PHASE 6: Generate main function
        try self.emit("pub fn main() !void {\n");
        self.indent();

        // Setup allocator (only if needed)
        if (analysis.needs_allocator) {
            try self.emitIndent();
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};\n");
            try self.emitIndent();
            try self.emit("defer _ = gpa.deinit();\n");
            try self.emitIndent();
            try self.emit("const allocator = gpa.allocator();\n\n");
        }

        // PHASE 7: Generate statements (skip class/function defs - already handled)
        // This will populate self.lambda_functions
        for (module.body) |stmt| {
            if (stmt != .function_def and stmt != .class_def) {
                try self.generateStmt(stmt);
            }
        }

        self.dedent();
        try self.emit("}\n");

        // PHASE 8: Prepend lambda functions if any were generated
        if (self.lambda_functions.items.len > 0) {
            // Get current output
            const current_output = try self.output.toOwnedSlice(self.allocator);
            defer self.allocator.free(current_output);

            // Rebuild output with lambdas first
            self.output = std.ArrayList(u8){};

            // Add imports
            try self.emit("const std = @import(\"std\");\n");
            try self.emit("const runtime = @import(\"./runtime.zig\");\n");
            if (analysis.needs_string_utils) {
                try self.emit("const string_utils = @import(\"string_utils.zig\");\n");
            }
            try self.emit("\n");

            // Add __name__ constant
            try self.emit("const __name__ = \"__main__\";\n\n");

            // Add lambda functions
            for (self.lambda_functions.items) |lambda_code| {
                try self.output.appendSlice(self.allocator, lambda_code);
            }

            // Find where class/function definitions start (after first two const declarations)
            // Parse current_output to extract everything after imports and __name__
            var lines = std.mem.splitScalar(u8, current_output, '\n');
            var skip_count: usize = 0;
            while (lines.next()) |line| {
                skip_count += 1;
                if (std.mem.indexOf(u8, line, "const __name__") != null) {
                    // Skip this line and the blank line after
                    _ = lines.next(); // blank line
                    skip_count += 1;
                    break;
                }
            }

            // Append the rest of the original output (class/func defs + main)
            var lines2 = std.mem.splitScalar(u8, current_output, '\n');
            var i: usize = 0;
            while (lines2.next()) |line| : (i += 1) {
                if (i >= skip_count) {
                    try self.output.appendSlice(self.allocator, line);
                    try self.output.appendSlice(self.allocator, "\n");
                }
            }
        }

        return self.output.toOwnedSlice(self.allocator);
    }

    pub fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try statements.genAssign(self, assign),
            .aug_assign => |aug| try statements.genAugAssign(self, aug),
            .expr_stmt => |expr| try statements.genExprStmt(self, expr.value.*),
            .if_stmt => |if_stmt| try statements.genIf(self, if_stmt),
            .while_stmt => |while_stmt| try statements.genWhile(self, while_stmt),
            .for_stmt => |for_stmt| try statements.genFor(self, for_stmt),
            .return_stmt => |ret| try statements.genReturn(self, ret),
            .assert_stmt => |assert_node| try statements.genAssert(self, assert_node),
            .try_stmt => |try_node| try statements.genTry(self, try_node),
            .class_def => |class| try statements.genClassDef(self, class),
            .import_stmt => {}, // Native modules - no import needed
            .import_from => |import| try statements.genImportFrom(self, import),
            .pass => try statements.genPass(self),
            .break_stmt => try statements.genBreak(self),
            .continue_stmt => try statements.genContinue(self),
            else => {},
        }
    }

    // Expression generation delegated to expressions.zig
    pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        try expressions.genExpr(self, node);
    }

    // Helper functions - public for use by statements.zig and expressions.zig
    pub fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    pub fn emitIndent(self: *NativeCodegen) CodegenError!void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.output.appendSlice(self.allocator, "    ");
        }
    }

    pub fn indent(self: *NativeCodegen) void {
        self.indent_level += 1;
    }

    pub fn dedent(self: *NativeCodegen) void {
        self.indent_level -= 1;
    }
};
