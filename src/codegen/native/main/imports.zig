/// Import handling and module compilation
const std = @import("std");
const ast = @import("../../../ast.zig");
const core = @import("core.zig");
const NativeCodegen = core.NativeCodegen;
const statements = @import("../statements.zig");
const import_resolver = @import("../../../import_resolver.zig");

/// Infer return type from type string
fn inferReturnTypeFromString(
    type_name: []const u8,
) @import("../../../analysis/native_types.zig").NativeType {
    if (std.mem.eql(u8, type_name, "int")) return .int;
    if (std.mem.eql(u8, type_name, "float")) return .float;
    if (std.mem.eql(u8, type_name, "str")) return .{ .string = .runtime };
    if (std.mem.eql(u8, type_name, "bool")) return .bool;

    return .int;
}

/// Compile a Python module to a Zig module file
/// Returns error if module .py file cannot be found
/// Accepts optional type_inferrer to register module function return types
pub fn compileModuleToZig(
    module_name: []const u8,
    source_file_dir: ?[]const u8,
    allocator: std.mem.Allocator,
    main_type_inferrer: ?*@import("../../../analysis/native_types.zig").TypeInferrer,
) !void {
    // Use import resolver to find the .py file
    const py_path = try import_resolver.resolveImport(module_name, source_file_dir, allocator) orelse {
        std.debug.print("Error: Cannot find module '{s}.py'\n", .{module_name});
        std.debug.print("Searched in: ", .{});
        if (source_file_dir) |dir| {
            std.debug.print("{s}/, ", .{dir});
        }
        std.debug.print("./, examples/\n", .{});
        return error.ModuleNotFound;
    };
    defer allocator.free(py_path);

    // Read source
    const source = try std.fs.cwd().readFileAlloc(allocator, py_path, 10 * 1024 * 1024);
    defer allocator.free(source);

    // Lex, parse, analyze
    const lexer_mod = @import("../../../lexer.zig");
    const parser_mod = @import("../../../parser.zig");
    const semantic_types_mod = @import("../../../analysis/types.zig");
    const lifetime_analysis_mod = @import("../../../analysis/lifetime.zig");
    const native_types_mod = @import("../../../analysis/native_types.zig");

    var lex = try lexer_mod.Lexer.init(allocator, source);
    defer lex.deinit();
    const tokens = try lex.tokenize();
    defer allocator.free(tokens);

    var p = parser_mod.Parser.init(allocator, tokens);
    var tree = try p.parse();
    defer tree.deinit(allocator);

    if (tree != .module) return error.InvalidAST;

    var semantic_info = semantic_types_mod.SemanticInfo.init(allocator);
    defer semantic_info.deinit();
    _ = try lifetime_analysis_mod.analyzeLifetimes(&semantic_info, tree, 1);

    var type_inferrer = try native_types_mod.TypeInferrer.init(allocator);
    defer type_inferrer.deinit();
    try type_inferrer.analyze(tree.module);

    // Use full codegen to generate proper module code
    var codegen = try NativeCodegen.init(allocator, &type_inferrer, &semantic_info);
    defer codegen.deinit();

    // Generate imports
    try codegen.emit("const std = @import(\"std\");\n");
    try codegen.emit("const runtime = @import(\"./runtime.zig\");\n\n");

    // Generate only function and class definitions (make all functions pub)
    for (tree.module.body) |stmt| {
        if (stmt == .function_def or stmt == .class_def) {
            // For functions, we need to make them pub
            if (stmt == .function_def) {
                const func = stmt.function_def;
                try codegen.emit("pub ");

                // Generate async keyword if needed
                if (func.is_async) {
                    try codegen.emit("async ");
                }

                try codegen.emit("fn ");
                try codegen.emit(func.name);
                try codegen.emit("(");

                // Parameters with type inference
                for (func.args, 0..) |arg, i| {
                    if (i > 0) try codegen.emit(", ");
                    try codegen.emit(arg.name);
                    try codegen.emit(": ");

                    // Try to infer parameter type
                    const param_type = type_inferrer.var_types.get(arg.name) orelse native_types_mod.NativeType.int;
                    const type_str = switch (param_type) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string => "[]const u8",
                        else => "i64",
                    };
                    try codegen.emit(type_str);
                }

                // Add allocator parameter for module functions
                if (func.args.len > 0) try codegen.emit(", ");
                try codegen.emit("allocator: std.mem.Allocator");

                try codegen.emit(") !"); // Add ! for error return

                // Infer return type from function
                const return_type = if (func.return_type) |ret_type_name|
                    inferReturnTypeFromString(ret_type_name)
                else
                    native_types_mod.NativeType.int;

                // Register module function return type in main type inferrer
                if (main_type_inferrer) |type_inf| {
                    // Format: "module.function" -> return type
                    const qualified_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, func.name });
                    try type_inf.func_return_types.put(qualified_name, return_type);
                    // Note: qualified_name is kept allocated for the lifetime of the map
                }

                const return_type_str = switch (return_type) {
                    .int => "i64",
                    .float => "f64",
                    .bool => "bool",
                    .string => "[]const u8",
                    else => "i64",
                };
                try codegen.emit(return_type_str);
                try codegen.emit(" {\n");

                codegen.indent();

                // Generate function body in a temporary buffer first
                const saved_output = codegen.output;
                codegen.output = std.ArrayList(u8){};

                for (func.body) |body_stmt| {
                    try codegen.generateStmt(body_stmt);
                }

                const body_code = try codegen.output.toOwnedSlice(allocator);
                defer allocator.free(body_code);

                // Restore original output
                codegen.output = saved_output;

                // Check if "allocator" was used in the generated body
                const allocator_used = std.mem.indexOf(u8, body_code, "allocator") != null;

                // If allocator not used, add suppression at start
                if (!allocator_used) {
                    try codegen.emitIndent();
                    try codegen.emit("std.mem.doNotOptimizeAway(&allocator);\n");
                }

                // Emit the actual body
                try codegen.output.appendSlice(allocator, body_code);

                codegen.dedent();
                try codegen.emit("}\n\n");
            } else {
                // For classes, use the full codegen
                try statements.genClassDef(codegen, stmt.class_def);
            }
        }
    }

    const zig_code = try codegen.output.toOwnedSlice(allocator);
    defer allocator.free(zig_code);

    // Create .build directory if it doesn't exist
    std.fs.cwd().makeDir(".build") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Write to .build/module_name.zig
    const zig_path = try std.fmt.allocPrint(allocator, ".build/{s}.zig", .{module_name});
    defer allocator.free(zig_path);

    const file = try std.fs.cwd().createFile(zig_path, .{});
    defer file.close();
    try file.writeAll(zig_code);
}

/// Scan AST for import statements and collect module names with registry lookup
/// Returns list of modules that need to be compiled from Python source
pub fn collectImports(
    self: *NativeCodegen,
    module: ast.Node.Module,
    source_file_dir: ?[]const u8,
) !std.ArrayList([]const u8) {
    var imports = std.ArrayList([]const u8){};

    // Collect unique Python module names from import statements
    var module_names = std.StringHashMap(void).init(self.allocator);
    defer module_names.deinit();

    // Clear previous from-imports
    self.from_imports.clearRetainingCapacity();

    for (module.body) |stmt| {
        // Handle both "import X" and "from X import Y"
        switch (stmt) {
            .import_stmt => |imp| {
                const module_name = imp.module;
                try module_names.put(module_name, {});
            },
            .import_from => |imp| {
                const module_name = imp.module;
                try module_names.put(module_name, {});

                // Store from-import info for symbol re-export generation
                try self.from_imports.append(self.allocator, core.FromImportInfo{
                    .module = module_name,
                    .names = imp.names,
                    .asnames = imp.asnames,
                });
            },
            else => {},
        }
    }

    // Process each module using registry
    var iter = module_names.keyIterator();
    while (iter.next()) |python_module| {
        if (self.import_registry.lookup(python_module.*)) |info| {
            switch (info.strategy) {
                .zig_runtime, .c_library => {
                    // Include modules with Zig implementations
                    try imports.append(self.allocator, python_module.*);
                },
                .compile_python => {
                    // Include for compilation (will be handled in generate())
                    try imports.append(self.allocator, python_module.*);
                },
                .unsupported => {
                    std.debug.print("Warning: Module '{s}' not supported yet\n", .{python_module.*});
                },
            }
        } else {
            // Module not in registry - check if it's a local .py file
            const is_local = try import_resolver.isLocalModule(
                python_module.*,
                source_file_dir,
                self.allocator,
            );

            if (is_local) {
                // Local user module - add to imports list for compilation
                try imports.append(self.allocator, python_module.*);
            } else {
                // External package not in registry - skip with warning
                std.debug.print("Warning: External module '{s}' not found, skipping import\n", .{python_module.*});
            }
        }
    }

    return imports;
}
