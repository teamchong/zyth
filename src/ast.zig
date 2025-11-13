const std = @import("std");

/// AST node types matching Python's ast module
pub const Node = union(enum) {
    module: Module,
    assign: Assign,
    binop: BinOp,
    compare: Compare,
    boolop: BoolOp,
    call: Call,
    name: Name,
    constant: Constant,
    if_stmt: If,
    for_stmt: For,
    while_stmt: While,
    function_def: FunctionDef,
    class_def: ClassDef,
    return_stmt: Return,
    list: List,
    subscript: Subscript,
    attribute: Attribute,
    expr_stmt: ExprStmt,

    pub const Module = struct {
        body: []Node,
    };

    pub const Assign = struct {
        targets: []Node,
        value: *Node,
    };

    pub const BinOp = struct {
        left: *Node,
        op: Operator,
        right: *Node,
    };

    pub const Call = struct {
        func: *Node,
        args: []Node,
    };

    pub const Name = struct {
        id: []const u8,
    };

    pub const Constant = struct {
        value: Value,
    };

    pub const If = struct {
        condition: *Node,
        body: []Node,
        else_body: []Node,
    };

    pub const For = struct {
        target: *Node,
        iter: *Node,
        body: []Node,
    };

    pub const While = struct {
        condition: *Node,
        body: []Node,
    };

    pub const FunctionDef = struct {
        name: []const u8,
        args: []Arg,
        body: []Node,
    };

    pub const ClassDef = struct {
        name: []const u8,
        body: []Node,
    };

    pub const Return = struct {
        value: ?*Node,
    };

    pub const Compare = struct {
        left: *Node,
        ops: []CompareOp,
        comparators: []Node,
    };

    pub const BoolOp = struct {
        op: BoolOperator,
        values: []Node,
    };

    pub const List = struct {
        elts: []Node,
    };

    pub const Subscript = struct {
        value: *Node,
        slice: *Node,
    };

    pub const Attribute = struct {
        value: *Node,
        attr: []const u8,
    };

    pub const ExprStmt = struct {
        value: *Node,
    };
};

pub const Operator = enum {
    Add,
    Sub,
    Mult,
    Div,
    FloorDiv,
    Mod,
    Pow,
    BitAnd,
    BitOr,
    BitXor,
};

pub const CompareOp = enum {
    Eq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    In,
    NotIn,
};

pub const BoolOperator = enum {
    And,
    Or,
};

pub const Value = union(enum) {
    int: i64,
    float: f64,
    string: []const u8,
    bool: bool,
};

pub const Arg = struct {
    name: []const u8,
    type_annotation: ?[]const u8,
};

/// Parse JSON AST from Python's ast.dump()
pub fn parseFromJson(allocator: std.mem.Allocator, json_str: []const u8) !Node {
    // TODO: Implement JSON → AST parsing
    // For now, this is a stub that will be implemented in Phase 1
    _ = allocator;
    _ = json_str;
    return error.NotImplemented;
}
