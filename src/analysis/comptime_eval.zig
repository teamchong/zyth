const std = @import("std");
const ast = @import("../ast.zig");
const string_ops = @import("comptime_string.zig");
const list_ops = @import("comptime_list.zig");
const builtin_ops = @import("comptime_builtins.zig");

/// Compile-time evaluator for constant expressions
/// Evaluates arithmetic and logical operations on constant values at compile time
pub const ComptimeEvaluator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ComptimeEvaluator {
        return .{ .allocator = allocator };
    }

    /// Try to evaluate an expression at compile time
    /// Returns null if expression is not constant or cannot be evaluated
    pub fn tryEval(self: *ComptimeEvaluator, node: ast.Node) ?ComptimeValue {
        return switch (node) {
            .constant => |val| switch (val.value) {
                .int => |i| ComptimeValue{ .int = i },
                .float => |f| ComptimeValue{ .float = f },
                .bool => |b| ComptimeValue{ .bool = b },
                .string => |s| ComptimeValue{ .string = s },
            },
            .binop => |op| self.evalBinOp(op),
            .unaryop => |op| self.evalUnaryOp(op),
            .compare => |cmp| self.evalCompare(cmp),
            .boolop => |bop| self.evalBoolOp(bop),
            .call => |call| self.evalCall(call),
            .subscript => |sub| self.evalSubscript(sub),
            .list => |l| self.evalListLiteral(l.elts),
            else => null, // Not constant
        };
    }

    fn evalBinOp(self: *ComptimeEvaluator, op: ast.Node.BinOp) ?ComptimeValue {
        // Recursively evaluate left and right
        const left = self.tryEval(op.left.*) orelse return null;
        const right = self.tryEval(op.right.*) orelse return null;

        // Apply operator
        return switch (op.op) {
            .Add => self.evalAdd(left, right),
            .Sub => self.evalSub(left, right),
            .Mult => self.evalMul(left, right),
            .Div => self.evalDiv(left, right),
            .FloorDiv => self.evalFloorDiv(left, right),
            .Mod => self.evalMod(left, right),
            .Pow => self.evalPow(left, right),
            .BitAnd => self.evalBitAnd(left, right),
            .BitOr => self.evalBitOr(left, right),
            .BitXor => self.evalBitXor(left, right),
        };
    }

    fn evalUnaryOp(self: *ComptimeEvaluator, op: ast.Node.UnaryOp) ?ComptimeValue {
        const operand = self.tryEval(op.operand.*) orelse return null;

        return switch (op.op) {
            .Not => self.evalNot(operand),
            .UAdd => operand, // +x = x
            .USub => self.evalUSub(operand),
        };
    }

    fn evalCompare(self: *ComptimeEvaluator, cmp: ast.Node.Compare) ?ComptimeValue {
        // For simplicity, only handle single comparison (a < b)
        // Chained comparisons (a < b < c) would require more complex logic
        if (cmp.ops.len != 1 or cmp.comparators.len != 1) return null;

        const left = self.tryEval(cmp.left.*) orelse return null;
        const right = self.tryEval(cmp.comparators[0]) orelse return null;
        const op = cmp.ops[0];

        return switch (op) {
            .Eq => self.evalEq(left, right),
            .NotEq => self.evalNe(left, right),
            .Lt => self.evalLt(left, right),
            .LtEq => self.evalLe(left, right),
            .Gt => self.evalGt(left, right),
            .GtEq => self.evalGe(left, right),
            .In, .NotIn => null, // Not implementing membership tests
        };
    }

    fn evalBoolOp(self: *ComptimeEvaluator, bop: ast.Node.BoolOp) ?ComptimeValue {
        // Evaluate all values
        var result: bool = switch (bop.op) {
            .And => true,
            .Or => false,
        };

        for (bop.values) |val_node| {
            const val = self.tryEval(val_node) orelse return null;
            const bool_val = self.toBool(val) orelse return null;

            switch (bop.op) {
                .And => {
                    result = result and bool_val;
                    if (!result) break; // Short-circuit
                },
                .Or => {
                    result = result or bool_val;
                    if (result) break; // Short-circuit
                },
            }
        }

        return ComptimeValue{ .bool = result };
    }

    // Arithmetic operations

    fn evalAdd(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    const result = @addWithOverflow(l, r);
                    if (result[1] != 0) break :blk null; // Overflow
                    break :blk ComptimeValue{ .int = result[0] };
                },
                .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) + r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .float = l + @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .float = l + r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| blk: {
                    // String concatenation
                    const result = std.mem.concat(self.allocator, u8, &[_][]const u8{ l, r }) catch return null;
                    break :blk ComptimeValue{ .string = result };
                },
                else => null,
            },
            else => null,
        };
    }

    fn evalSub(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    const result = @subWithOverflow(l, r);
                    if (result[1] != 0) break :blk null; // Overflow
                    break :blk ComptimeValue{ .int = result[0] };
                },
                .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) - r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .float = l - @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .float = l - r },
                else => null,
            },
            else => null,
        };
    }

    fn evalMul(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    const result = @mulWithOverflow(l, r);
                    if (result[1] != 0) break :blk null; // Overflow
                    break :blk ComptimeValue{ .int = result[0] };
                },
                .float => |r| ComptimeValue{ .float = @as(f64, @floatFromInt(l)) * r },
                .string => null, // int * string not implemented
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .float = l * @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .float = l * r },
                else => null,
            },
            .string => |l| switch (right) {
                .int => |r| blk: {
                    // String repetition
                    if (r < 0) break :blk null;
                    if (r == 0) break :blk ComptimeValue{ .string = "" };
                    if (r > 10000) break :blk null; // Prevent excessive allocation

                    const result = self.allocator.alloc(u8, l.len * @as(usize, @intCast(r))) catch return null;
                    var i: usize = 0;
                    while (i < r) : (i += 1) {
                        @memcpy(result[i * l.len .. (i + 1) * l.len], l);
                    }
                    break :blk ComptimeValue{ .string = result };
                },
                else => null,
            },
            else => null,
        };
    }

    fn evalDiv(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    if (r == 0) break :blk null; // Division by zero
                    // Python 3 division always returns float
                    break :blk ComptimeValue{ .float = @as(f64, @floatFromInt(l)) / @as(f64, @floatFromInt(r)) };
                },
                .float => |r| blk: {
                    if (r == 0.0) break :blk null;
                    break :blk ComptimeValue{ .float = @as(f64, @floatFromInt(l)) / r };
                },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| blk: {
                    if (r == 0) break :blk null;
                    break :blk ComptimeValue{ .float = l / @as(f64, @floatFromInt(r)) };
                },
                .float => |r| blk: {
                    if (r == 0.0) break :blk null;
                    break :blk ComptimeValue{ .float = l / r };
                },
                else => null,
            },
            else => null,
        };
    }

    fn evalFloorDiv(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    if (r == 0) break :blk null; // Division by zero
                    break :blk ComptimeValue{ .int = @divFloor(l, r) };
                },
                .float => |r| blk: {
                    if (r == 0.0) break :blk null;
                    break :blk ComptimeValue{ .float = @floor(@as(f64, @floatFromInt(l)) / r) };
                },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| blk: {
                    if (r == 0) break :blk null;
                    break :blk ComptimeValue{ .float = @floor(l / @as(f64, @floatFromInt(r))) };
                },
                .float => |r| blk: {
                    if (r == 0.0) break :blk null;
                    break :blk ComptimeValue{ .float = @floor(l / r) };
                },
                else => null,
            },
            else => null,
        };
    }

    fn evalMod(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    if (r == 0) break :blk null; // Division by zero
                    break :blk ComptimeValue{ .int = @mod(l, r) };
                },
                else => null,
            },
            else => null,
        };
    }

    fn evalPow(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| blk: {
                    if (r < 0) break :blk null; // Negative exponent -> float
                    if (r > 100) break :blk null; // Prevent excessive computation
                    var result: i64 = 1;
                    var i: i64 = 0;
                    while (i < r) : (i += 1) {
                        const mul_result = @mulWithOverflow(result, l);
                        if (mul_result[1] != 0) break :blk null; // Overflow
                        result = mul_result[0];
                    }
                    break :blk ComptimeValue{ .int = result };
                },
                .float => |r| ComptimeValue{ .float = std.math.pow(f64, @as(f64, @floatFromInt(l)), r) },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .float = std.math.pow(f64, l, @as(f64, @floatFromInt(r))) },
                .float => |r| ComptimeValue{ .float = std.math.pow(f64, l, r) },
                else => null,
            },
            else => null,
        };
    }

    // Bitwise operations

    fn evalBitAnd(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .int = l & r },
                else => null,
            },
            else => null,
        };
    }

    fn evalBitOr(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .int = l | r },
                else => null,
            },
            else => null,
        };
    }

    fn evalBitXor(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .int = l ^ r },
                else => null,
            },
            else => null,
        };
    }

    // Unary operations

    fn evalNot(self: *ComptimeEvaluator, operand: ComptimeValue) ?ComptimeValue {
        const bool_val = self.toBool(operand) orelse return null;
        return ComptimeValue{ .bool = !bool_val };
    }

    fn evalUSub(self: *ComptimeEvaluator, operand: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (operand) {
            .int => |i| blk: {
                const result = @subWithOverflow(0, i);
                if (result[1] != 0) break :blk null; // Overflow
                break :blk ComptimeValue{ .int = result[0] };
            },
            .float => |f| ComptimeValue{ .float = -f },
            else => null,
        };
    }

    // Comparison operations

    fn evalEq(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        const result = switch (left) {
            .int => |l| switch (right) {
                .int => |r| l == r,
                .float => |r| @as(f64, @floatFromInt(l)) == r,
                else => false,
            },
            .float => |l| switch (right) {
                .int => |r| l == @as(f64, @floatFromInt(r)),
                .float => |r| l == r,
                else => false,
            },
            .bool => |l| switch (right) {
                .bool => |r| l == r,
                else => false,
            },
            .string => |l| switch (right) {
                .string => |r| std.mem.eql(u8, l, r),
                else => false,
            },
            .list => |l| switch (right) {
                .list => |r| blk: {
                    if (l.len != r.len) break :blk false;
                    for (l, r) |left_item, right_item| {
                        const item_eq = self.evalEq(left_item, right_item) orelse break :blk false;
                        if (!item_eq.bool) break :blk false;
                    }
                    break :blk true;
                },
                else => false,
            },
        };
        return ComptimeValue{ .bool = result };
    }

    fn evalNe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        const eq_result = self.evalEq(left, right) orelse return null;
        return ComptimeValue{ .bool = !eq_result.bool };
    }

    fn evalLt(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l < r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) < r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l < @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l < r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = std.mem.lessThan(u8, l, r) },
                else => null,
            },
            else => null,
        };
    }

    fn evalLe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l <= r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) <= r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l <= @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l <= r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = !std.mem.lessThan(u8, r, l) },
                else => null,
            },
            else => null,
        };
    }

    fn evalGt(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l > r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) > r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l > @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l > r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = std.mem.lessThan(u8, r, l) },
                else => null,
            },
            else => null,
        };
    }

    fn evalGe(self: *ComptimeEvaluator, left: ComptimeValue, right: ComptimeValue) ?ComptimeValue {
        _ = self;
        return switch (left) {
            .int => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l >= r },
                .float => |r| ComptimeValue{ .bool = @as(f64, @floatFromInt(l)) >= r },
                else => null,
            },
            .float => |l| switch (right) {
                .int => |r| ComptimeValue{ .bool = l >= @as(f64, @floatFromInt(r)) },
                .float => |r| ComptimeValue{ .bool = l >= r },
                else => null,
            },
            .string => |l| switch (right) {
                .string => |r| ComptimeValue{ .bool = !std.mem.lessThan(u8, l, r) },
                else => null,
            },
            else => null,
        };
    }

    // Helper: Convert value to bool (for logical operations)
    fn toBool(self: *ComptimeEvaluator, value: ComptimeValue) ?bool {
        _ = self;
        return switch (value) {
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.len > 0,
            .list => |l| l.len > 0,
        };
    }

    // ========== String & List Operations (Agent 2) ==========


    // ========== String & List Operations (Agent 2) - Delegated to helper modules ==========

    fn tryEvalWrapper(ctx: *anyopaque, node: ast.Node) ?ComptimeValue {
        const self: *ComptimeEvaluator = @ptrCast(@alignCast(ctx));
        return self.tryEval(node);
    }

    fn evalCall(self: *ComptimeEvaluator, call: ast.Node.Call) ?ComptimeValue {
        // Check if it's a method call like "hello".upper()
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            const obj = self.tryEval(attr.value.*) orelse return null;
            return self.evalMethod(obj, attr.attr, call.args);
        }

        // Check if it's a builtin like len([1,2,3])
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            const builtins = builtin_ops.BuiltinOps.init(
                self.allocator,
                @as(*anyopaque, @ptrCast(self)),
                tryEvalWrapper,
            );
            return builtins.evalBuiltin(func_name, call.args);
        }

        return null;
    }

    fn evalMethod(self: *ComptimeEvaluator, obj: ComptimeValue, method: []const u8, args: []ast.Node) ?ComptimeValue {
        if (obj != .string) return null;
        const s = obj.string;
        const str_ops = string_ops.StringOps.init(self.allocator);

        if (std.mem.eql(u8, method, "upper")) {
            return str_ops.evalUpper(s);
        } else if (std.mem.eql(u8, method, "lower")) {
            return str_ops.evalLower(s);
        } else if (std.mem.eql(u8, method, "strip")) {
            return str_ops.evalStrip(s);
        } else if (std.mem.eql(u8, method, "replace")) {
            if (args.len != 2) return null;
            const old = self.tryEval(args[0]) orelse return null;
            const new = self.tryEval(args[1]) orelse return null;
            if (old != .string or new != .string) return null;
            return str_ops.evalReplace(s, old.string, new.string);
        } else if (std.mem.eql(u8, method, "split")) {
            if (args.len != 1) return null;
            const sep = self.tryEval(args[0]) orelse return null;
            if (sep != .string) return null;
            return str_ops.evalSplit(s, sep.string);
        } else if (std.mem.eql(u8, method, "startswith")) {
            if (args.len != 1) return null;
            const prefix = self.tryEval(args[0]) orelse return null;
            if (prefix != .string) return null;
            return ComptimeValue{ .bool = std.mem.startsWith(u8, s, prefix.string) };
        } else if (std.mem.eql(u8, method, "endswith")) {
            if (args.len != 1) return null;
            const suffix = self.tryEval(args[0]) orelse return null;
            if (suffix != .string) return null;
            return ComptimeValue{ .bool = std.mem.endsWith(u8, s, suffix.string) };
        }

        return null;
    }

    fn evalListLiteral(self: *ComptimeEvaluator, items: []ast.Node) ?ComptimeValue {
        const list_helper = list_ops.ListOps.init(
            self.allocator,
            @as(*anyopaque, @ptrCast(self)),
            tryEvalWrapper,
        );
        return list_helper.evalLiteral(items);
    }

    fn evalSubscript(self: *ComptimeEvaluator, sub: ast.Node.Subscript) ?ComptimeValue {
        const value = self.tryEval(sub.value.*) orelse return null;

        // Only handle index subscript (not slices)
        if (sub.slice != .index) return null;
        const index_node = self.tryEval(sub.slice.index.*) orelse return null;

        const list_helper = list_ops.ListOps.init(
            self.allocator,
            @as(*anyopaque, @ptrCast(self)),
            tryEvalWrapper,
        );
        return list_helper.evalSubscript(value, index_node);
    }
};

/// Compile-time constant value
pub const ComptimeValue = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    list: []const ComptimeValue,

    /// Format the value as a string for debugging
    pub fn format(
        self: ComptimeValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .bool => |b| try writer.print("{}", .{b}),
            .string => |s| try writer.print("\"{s}\"", .{s}),
            .list => |l| {
                try writer.writeAll("[");
                for (l, 0..) |item, idx| {
                    if (idx > 0) try writer.writeAll(", ");
                    try item.format(fmt, options, writer);
                }
                try writer.writeAll("]");
            },
        }
    }
};
