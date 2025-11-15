# NumPy FFI - Current Status

**Date:** 2025-01-15
**Achievement:** Python C API FFI foundation complete (80% working)

---

## ✅ What Works

### 1. Python Interpreter Embedding ✅
- PYTHONHOME configuration (wchar_t* conversion)
- Virtual environment detection and sys.path modification
- Python initialization and finalization
- No segfaults in basic operations

**Test:**
```bash
VIRTUAL_ENV=/path/to/.venv pyaot examples/numpy_test.py
```
**Output:**
```
Using Python home: /path/to/python
Adding to sys.path: /path/to/venv/lib/python3.12/site-packages
NumPy imported successfully!
```

### 2. Module Imports ✅
- `import numpy` works
- `import numpy as np` works
- Module tracking in codegen
- No crashes on import

### 3. Module Attribute Access ✅
- `np.array` resolves correctly
- Generates `python.getattr(allocator, np, "array")`
- Returns Python function objects

### 4. Function Call Codegen ✅
- Detects Python function calls
- Generates `python.callPythonFunction()`
- Converts arguments to Python objects

### 5. Type Conversion (Partial) ✅
- Integer literals → `python.fromInt()`
- Float literals → `python.fromFloat()`
- Bool literals → `python.fromInt(0/1)`
- String literals → Already PyString
- **List literals → `python.listFromInts()` for integer lists**

### 6. Python Object Printing ✅
- `python.printPyObject()` uses `PyObject_Str()`
- Converts Python objects to strings for display

---

## ❌ What Doesn't Work

### 1. NumPy Array Creation - CRASHES ❌
**Code:**
```python
import numpy as np
a = np.array([1, 2, 3, 4, 5])
```

**Error:**
```
Segmentation fault at address 0x7d
???:?:?: 0x106f39630 in ??? (libpython3.12.dylib)
???:?:?: 0x106199063 in ??? (_multiarray_umath.cpython-312-darwin.so)
```

**Root Cause (Suspected):**
- NumPy initialization not happening
- GIL (Global Interpreter Lock) issues
- Thread state problems
- Memory alignment issues in PyObject_CallObject
- NumPy expecting specific Python runtime setup

### 2. Operators on Python Objects ❌
**Code:**
```python
doubled = a * 2
```
**Error:**
```
error: incompatible types: '*anyopaque' and 'comptime_int'
```

**Fix Required:** Generate Python C API operator calls (PyNumber_Multiply, etc.)

### 3. Print Python Objects (Partial) ⚠️
- Works with `python.printPyObject()` for FFI objects
- Doesn't work inline: `print("Array:", a)` → only prints "Array:"

---

## Architecture

### Generated Code Flow

**Python:**
```python
import numpy as np
a = np.array([1, 2, 3, 4, 5])
print(a)
```

**Generated Zig:**
```zig
try python.initialize();
defer python.finalize();

const np = try python.importModule(allocator, "numpy");

// Create Python list from integers
const a = try python.callPythonFunction(
    allocator,
    try python.getattr(allocator, np, "array"),
    &[_]*anyopaque{@ptrCast(try python.listFromInts(&[_]i64{1, 2, 3, 4, 5}))}
);

// Print Python object
python.printPyObject(a);
std.debug.print("\\n", .{});
```

### Runtime Functions

**packages/runtime/src/python.zig:**
- `initialize()` - Configure PYTHONHOME, Py_InitializeEx(0)
- `importModule()` - PyImport_ImportModule
- `getattr()` - PyObject_GetAttrString
- `callPythonFunction()` - PyObject_CallObject ← **CRASHES HERE**
- `fromInt/fromFloat/fromString()` - Type conversions
- `listFromInts()` - Create Python list from Zig array
- `convertPyListToPython()` - Convert PyAOT list to Python list
- `printPyObject()` - PyObject_Str + PyUnicode_AsUTF8

---

## Why NumPy Crashes

### Hypothesis 1: GIL Not Acquired
Python C API requires GIL (Global Interpreter Lock) for multi-threading.

**Evidence:** Py_InitializeEx(0) should acquire GIL for main thread automatically.

**Possible Fix:** Explicitly acquire GIL before calling PyObject_CallObject:
```zig
const state = c.PyGILState_Ensure();
defer c.PyGILState_Release(state);
const result = c.PyObject_CallObject(@ptrCast(@alignCast(func)), py_args);
```

### Hypothesis 2: NumPy Not Initialized
NumPy requires `import_array()` in C extensions.

**Evidence:** We're using `PyImport_ImportModule("numpy")` which should trigger this.

**Possible Fix:** Call `PyArray_API` initialization explicitly (requires NumPy C headers).

### Hypothesis 3: Thread State Issues
Python maintains thread state that NumPy might depend on.

**Evidence:** Segfault at low address (0x7d) suggests null pointer.

**Possible Fix:** Ensure thread state is properly set up:
```zig
const tstate = c.PyThreadState_Get();
if (tstate == null) return error.NoThreadState;
```

### Hypothesis 4: Memory Alignment
PyObject structures require specific alignment.

**Evidence:** We use `@ptrCast(@alignCast(...))`  everywhere which should handle this.

**Possible Fix:** Verify alignment of tuple creation in callPythonFunction.

---

## Next Steps (Priority Order)

### 1. Debug NumPy Crash (1-2 days)
**Steps:**
1. Add GIL acquisition around Python calls
2. Add extensive error checking (PyErr_Occurred after each call)
3. Test with simpler Python function (not NumPy)
4. Use Python debugger (gdb with Python support)
5. Check if NumPy works with pure Python C API example

### 2. Simplify Test Case (1 hour)
Test with built-in Python functions instead of NumPy:
```python
import sys
print(sys.version)  # Test getattr + call
```

If this works, the issue is NumPy-specific. If it crashes, issue is in our FFI layer.

### 3. Implement Python Operators (2-3 days)
Once basic calls work, add operator support:
- Detect binary operators on Python objects
- Generate PyNumber_Multiply, PyNumber_Add, etc.
- Handle comparison operators

### 4. Complete Type System (1-2 days)
- Convert all PyAOT types to Python types for FFI
- Handle nested structures (list of lists, etc.)
- Add Python → PyAOT conversion for return values

---

## Files Modified (This Session)

**Core Changes:**
1. `packages/runtime/src/python.zig` (+130 lines)
   - Added wchar_t* conversion
   - Added PYTHONHOME detection
   - Added venv support
   - Added getattr, callPythonFunction
   - Added listFromInts, convertPyListToPython
   - Added printPyObject

2. `src/codegen.zig` (+5 lines)
   - Added `imported_modules` HashMap

3. `src/codegen/statements.zig` (-4 lines)
   - Track imported modules
   - Removed pointless discard statement

4. `src/codegen/classes.zig` (+150 lines)
   - Detect Python function calls
   - Generate FFI call code
   - Type conversion logic
   - Module attribute access detection

5. `src/codegen/builtins.zig` (+15 lines)
   - Detect Python objects in print
   - Call python.printPyObject()

**Documentation:**
6. `examples/README_NUMPY.md` - Updated status
7. `examples/numpy_demo.py` - Simplified demo
8. `benchmarks/numpy_comparison.py` - 9 benchmarks (ready for when FFI works)

---

## Recommendation

**Current status:** 80% complete, blocked on NumPy crash investigation.

**Options:**

**A) Debug NumPy crash (2-3 days)**
- High effort, potentially complex Python C API issues
- May uncover fundamental limitations
- Risk: Might not be solvable without major refactoring

**B) Test with simpler Python libraries first (1 day)**
- Test with `sys`, `os`, `json` modules
- Verify FFI layer works for non-NumPy code
- If successful, proves issue is NumPy-specific
- Lower risk, faster validation

**C) Document current state and move on (0 days)**
- NumPy FFI foundation is solid
- 80% of work complete
- Users can still use PyAOT for non-NumPy code
- Return to NumPy later with more context

**Suggested:** **Option B** - Test with simpler Python modules to validate the FFI layer, then decide whether to pursue NumPy further.

---

## Code Quality

**What's Good:**
- Clean separation: codegen detects patterns, runtime handles FFI
- Proper memory management (defer, allocator tracking)
- Extensible: easy to add more Python API functions
- Well-documented with comments

**What Needs Work:**
- Error handling: many `try` without specific error messages
- Type tracking: limited to basic types
- Testing: no unit tests for FFI layer
- Memory: potential leaks in Python object references

**Technical Debt:**
- GIL management unclear
- Thread safety not considered
- Reference counting between PyAOT and Python unclear
- No cleanup of Python objects returned from FFI
