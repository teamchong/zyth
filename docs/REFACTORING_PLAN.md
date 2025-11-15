# File Splitting Refactoring Plan

## Overview
Split two large files to improve maintainability and enable better multi-agent collaboration.

## Priority 1: src/parser.zig (1,402 lines)

### Current Structure
Single Parser struct with all parsing methods embedded.

### Target Structure
```
src/parser/
├── parser.zig         (~200 lines) - Core Parser struct, public API
├── statements.zig     (~400 lines) - Statement parsing
├── expressions.zig    (~500 lines) - Expression parsing
├── postfix.zig        (~200 lines) - Postfix, call, subscript
└── literals.zig       (~200 lines) - List, dict, tuple literals
```

### Detailed Split Plan

#### src/parser/parser.zig (~200 lines)
**Keep:**
- ParseError enum
- Parser struct definition
- `pub fn parse()` - Main entry point
- `fn parseStatement()` - Dispatcher to statement parsers
- Helper methods: `peek()`, `current()`, `advance()`, `expect()`, `match()`, etc.

**Imports:**
```zig
const statements = @import("parser/statements.zig");
const expressions = @import("parser/expressions.zig");
const postfix = @import("parser/postfix.zig");
const literals = @import("parser/literals.zig");
```

#### src/parser/statements.zig (~400 lines)
**Move from parser.zig lines 140-610:**
- `pub fn parseExprOrAssign()` (line 140)
- `pub fn parseFunctionDef()` (line 250)
- `pub fn parseClassDef()` (line 324)
- `pub fn parseIf()` (line 361)
- `pub fn parseFor()` (line 425)
- `pub fn parseWhile()` (line 474)
- `pub fn parseReturn()` (line 496)
- `pub fn parseAssert()` (line 520)
- `pub fn parseImport()` (line 548)
- `pub fn parseImportFrom()` (line 573)
- `pub fn parseBlock()` (line 611)

#### src/parser/expressions.zig (~500 lines)
**Move from parser.zig lines 631-954:**
- `pub fn parseExpression()` (line 631)
- `pub fn parseOrExpr()` (line 635)
- `pub fn parseAndExpr()` (line 657)
- `pub fn parseNotExpr()` (line 678)
- `pub fn parseComparison()` (line 696)
- `pub fn parseBitOr()` (line 763)
- `pub fn parseBitXor()` (line 795)
- `pub fn parseBitAnd()` (line 827)
- `pub fn parseAddSub()` (line 859)
- `pub fn parseMulDiv()` (line 893)
- `pub fn parsePower()` (line 931)

#### src/parser/postfix.zig (~200 lines)
**Move from parser.zig lines 955-1287:**
- `pub fn parsePostfix()` (line 955)
- `pub fn parseCall()` (line 1116)
- `pub fn parsePrimary()` (line 1141)

#### src/parser/literals.zig (~200 lines)
**Move from parser.zig lines 1288-end:**
- `pub fn parseList()` (line 1288)
- `pub fn parseListComp()` (line 1331)
- `pub fn parseDict()` (line 1372)
- `pub fn parseTuple()` (if exists)

### Migration Steps
1. Create `src/parser/` directory
2. Extract statements.zig (test compile)
3. Extract expressions.zig (test compile)
4. Extract postfix.zig (test compile)
5. Extract literals.zig (test compile)
6. Update parser.zig imports
7. Run full test suite
8. Delete old parser.zig sections

---

## Priority 2: src/codegen/classes.zig (967 lines)

### Current Structure
All class-related codegen in single file.

### Target Structure
```
src/codegen/classes/
├── classes.zig          (~200 lines) - Core visitClassDef
├── attributes.zig       (~150 lines) - Attribute access
├── methods.zig          (~350 lines) - Method calls & dispatch
├── instantiation.zig    (~100 lines) - Class instantiation
└── python_ffi.zig       (~200 lines) - Python FFI wrappers
```

### Detailed Split Plan

#### src/codegen/classes/classes.zig (~200 lines)
**Keep:**
- Helper functions: `methodNeedsAllocator()`, `inferReturnType()`
- `pub fn visitClassDef()` (lines 95-352) - Main class definition codegen

#### src/codegen/classes/attributes.zig (~150 lines)
**Move:**
- `pub fn visitAttribute()` (lines 9-37)
- Attribute access codegen

#### src/codegen/classes/methods.zig (~350 lines)
**Move:**
- `pub fn visitMethodCall()` (lines 416-793) - 378 lines!
- All method dispatch logic
- String/List/Dict method handling

#### src/codegen/classes/instantiation.zig (~100 lines)
**Move:**
- `pub fn visitClassInstantiation()` (lines 38-58)
- `fn wrapPrimitiveIfNeeded()` (lines 353-379)
- `fn wrapPrimitiveWithDecref()` (lines 380-415)

#### src/codegen/classes/python_ffi.zig (~200 lines)
**Move:**
- `fn visitPythonFunctionCall()` (lines 794-874)
- `fn convertToPythonObject()` (lines 875-end)
- NumPy/Python FFI wrappers

### Migration Steps
1. Create `src/codegen/classes/` directory
2. Extract methods.zig (largest section first)
3. Extract python_ffi.zig
4. Extract instantiation.zig
5. Extract attributes.zig
6. Update classes.zig imports
7. Update src/codegen/expressions.zig imports
8. Run full test suite

---

## Testing Strategy

### After Each File Split
```bash
# 1. Verify compilation
make build

# 2. Run core tests
pytest tests/test_regression.py -k "class" -v
pytest tests/test_regression.py -k "function" -v

# 3. Verify working examples
pyaot examples/class_simple.py
pyaot examples/function_simple.py
```

### Full Validation
```bash
# Run all tests
pytest tests/test_regression.py -v

# Check for any regressions
# Before: 54/86 passing
# After: Should still be 54/86 passing (no change)
```

---

## Rollback Plan

If issues occur:
```bash
git diff src/parser/ src/codegen/classes/
git checkout -- src/parser/ src/codegen/classes/
```

---

## Success Criteria

- ✅ No file > 500 lines in parser/ or classes/
- ✅ All existing tests still pass (54/86)
- ✅ Code compiles without warnings
- ✅ Clear module boundaries with minimal coupling
- ✅ Easy to find code (good file organization)

---

## Timeline Estimate

- **parser.zig split**: 2-3 hours
- **classes.zig split**: 1-2 hours
- **Testing & validation**: 1 hour
- **Total**: 4-6 hours

---

## Benefits

1. **Multi-agent collaboration** - Different agents can work on parser/statements.zig vs parser/expressions.zig simultaneously
2. **Easier navigation** - Find code faster with clear module boundaries
3. **Reduced cognitive load** - Each file focuses on one concern
4. **Better testability** - Can unit test individual modules
5. **Follows CLAUDE.md guidelines** - "Keep files manageable for multi-agent development"
