/// String/List/Dict methods - .split(), .append(), .keys(), etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate code for text.split(separator)
/// Example: "a b c".split(" ") -> std.mem.split(u8, text, sep)
pub fn genSplit(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Generate: std.mem.split(u8, text, sep)
    try self.output.appendSlice(self.allocator, "std.mem.split(u8, ");
    try self.genExpr(obj); // The string object
    try self.output.appendSlice(self.allocator, ", ");
    try self.genExpr(args[0]); // The separator
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate code for list.append(item)
/// NOTE: Zig arrays are fixed size, need ArrayList for dynamic appending
pub fn genAppend(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = obj; // Unused for now - will need when detecting ArrayList vs array
    if (args.len != 1) {
        return;
    }

    // For now: compile error placeholder
    // TODO: Need to detect if obj is ArrayList vs array
    try self.output.appendSlice(
        self.allocator,
        "@compileError(\"list.append() requires ArrayList, not yet supported\")",
    );
}

// TODO: Implement string methods
// - text.upper() -> []const u8
// - text.lower() -> []const u8
// - text.strip() -> []const u8
// - text.replace(old, new) -> []const u8

// TODO: Implement list methods
// - list.pop() -> T
// - list.extend(other)
// - list.insert(index, item)
// - list.remove(item)

// TODO: Implement dict methods
// - dict.get(key) -> ?V
// - dict.keys() -> []K
// - dict.values() -> []V
// - dict.items() -> [][2]{K, V}
