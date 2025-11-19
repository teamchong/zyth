/// Direct BLAS/LAPACK calls for NumPy compatibility
/// Zero overhead - no PyObject* conversion
///
/// This module provides direct C library calls for numerical operations,
/// bypassing Python's interpreter entirely for maximum performance.

const std = @import("std");

// BLAS C interface - Direct extern declarations
// Note: This requires linking with a BLAS implementation (OpenBLAS, Apple Accelerate, etc.)
// We declare functions directly instead of @cImport to avoid header path issues

// BLAS Level 1: cblas_ddot - dot product
extern "c" fn cblas_ddot(N: c_int, X: [*c]const f64, incX: c_int, Y: [*c]const f64, incY: c_int) f64;

// BLAS Level 3: cblas_dgemm - matrix multiplication
extern "c" fn cblas_dgemm(
    Order: c_int,
    TransA: c_int,
    TransB: c_int,
    M: c_int,
    N: c_int,
    K: c_int,
    alpha: f64,
    A: [*c]const f64,
    lda: c_int,
    B: [*c]const f64,
    ldb: c_int,
    beta: f64,
    C: [*c]f64,
    ldc: c_int,
) void;

// BLAS constants
const CblasRowMajor: c_int = 101;
const CblasNoTrans: c_int = 111;

/// Create array from integer slice
/// Converts i64 → f64 for BLAS compatibility
pub fn array(data: []const i64, allocator: std.mem.Allocator) ![]f64 {
    const result = try allocator.alloc(f64, data.len);
    for (data, 0..) |val, i| {
        result[i] = @floatFromInt(val);
    }
    return result;
}

/// Create array from float slice (no conversion needed)
pub fn arrayFloat(data: []const f64, allocator: std.mem.Allocator) ![]f64 {
    const result = try allocator.alloc(f64, data.len);
    @memcpy(result, data);
    return result;
}

/// Vector dot product using BLAS Level 1
/// Computes: a · b = sum(a[i] * b[i])
pub fn dot(a: []const f64, b: []const f64) f64 {
    std.debug.assert(a.len == b.len);

    // Use BLAS ddot: double precision dot product
    return cblas_ddot(
        @intCast(a.len),  // N: number of elements
        a.ptr,            // X: pointer to first vector
        1,                // incX: stride for X
        b.ptr,            // Y: pointer to second vector
        1                 // incY: stride for Y
    );
}

/// Sum all elements in array
/// Uses BLAS dasum for absolute values, but we want regular sum
/// So we use a simple loop for now (could optimize with SIMD later)
pub fn sum(arr: []const f64) f64 {
    var total: f64 = 0.0;
    for (arr) |val| {
        total += val;
    }
    return total;
}

/// Calculate mean (average) of array elements
pub fn mean(arr: []const f64) f64 {
    if (arr.len == 0) return 0.0;
    const total = sum(arr);
    return total / @as(f64, @floatFromInt(arr.len));
}

/// Transpose matrix (in-place for square matrices, allocates for non-square)
/// For MVP, we'll just support square matrices in-place
/// rows: number of rows in original matrix
/// cols: number of columns in original matrix
pub fn transpose(matrix: []f64, rows: usize, cols: usize, allocator: std.mem.Allocator) ![]f64 {
    // Allocate result matrix with swapped dimensions
    const result = try allocator.alloc(f64, rows * cols);

    // Transpose: result[j][i] = matrix[i][j]
    // In row-major layout: result[j*rows + i] = matrix[i*cols + j]
    for (0..rows) |i| {
        for (0..cols) |j| {
            result[j * rows + i] = matrix[i * cols + j];
        }
    }

    return result;
}

/// Matrix-matrix multiplication using BLAS Level 3
/// Computes: C = alpha*A*B + beta*C
/// For basic matmul: C = A*B, we use alpha=1, beta=0
pub fn matmul(a: []const f64, b: []const f64, m: usize, n: usize, k: usize, allocator: std.mem.Allocator) ![]f64 {
    // A: m x k matrix
    // B: k x n matrix
    // C: m x n matrix (result)

    const result = try allocator.alloc(f64, m * n);
    @memset(result, 0.0);

    // Use BLAS dgemm: double precision general matrix multiply
    cblas_dgemm(
        CblasRowMajor,          // Row-major layout
        CblasNoTrans,           // Don't transpose A
        CblasNoTrans,           // Don't transpose B
        @intCast(m),            // M: rows of A
        @intCast(n),            // N: cols of B
        @intCast(k),            // K: cols of A, rows of B
        1.0,                    // alpha: scalar for A*B
        a.ptr,                  // A matrix
        @intCast(k),            // lda: leading dimension of A
        b.ptr,                  // B matrix
        @intCast(n),            // ldb: leading dimension of B
        0.0,                    // beta: scalar for C
        result.ptr,             // C matrix (result)
        @intCast(n)             // ldc: leading dimension of C
    );

    return result;
}

/// Get array length
pub fn len(arr: []const f64) usize {
    return arr.len;
}

test "array creation" {
    const allocator = std.testing.allocator;

    const data = [_]i64{1, 2, 3, 4, 5};
    const arr = try array(&data, allocator);
    defer allocator.free(arr);

    try std.testing.expectEqual(@as(usize, 5), arr.len);
    try std.testing.expectEqual(@as(f64, 1.0), arr[0]);
    try std.testing.expectEqual(@as(f64, 5.0), arr[4]);
}

test "dot product" {
    const a = [_]f64{1.0, 2.0, 3.0};
    const b = [_]f64{4.0, 5.0, 6.0};

    const result = dot(&a, &b);
    // Expected: 1*4 + 2*5 + 3*6 = 4 + 10 + 18 = 32
    try std.testing.expectEqual(@as(f64, 32.0), result);
}

test "sum" {
    const arr = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const result = sum(&arr);
    // Expected: 1 + 2 + 3 + 4 + 5 = 15
    try std.testing.expectEqual(@as(f64, 15.0), result);
}

test "mean" {
    const arr = [_]f64{1.0, 2.0, 3.0, 4.0, 5.0};
    const result = mean(&arr);
    // Expected: 15 / 5 = 3.0
    try std.testing.expectEqual(@as(f64, 3.0), result);
}
