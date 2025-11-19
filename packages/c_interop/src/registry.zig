// C Library Mapping Registry
// Central registry of all available library mappings

const std = @import("std");
const mapper = @import("mapper.zig");
const detection = @import("detection.zig");

// Re-export public APIs
pub const ImportContext = detection.ImportContext;
pub const MappingRegistry = mapper.MappingRegistry;
pub const FunctionMapping = mapper.FunctionMapping;

// Import all mapping modules
const numpy = @import("mappings/numpy.zig");

/// Global registry containing all available mappings
pub var global_registry: ?*mapper.MappingRegistry = null;

/// Initialize the global registry with all known mappings
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    // Collect all mapping references
    const all_mappings = [_]*const mapper.CLibraryMapping{
        &numpy.numpy_mapping,
        // Add more mappings here as they're implemented
    };

    const registry = try allocator.create(mapper.MappingRegistry);
    registry.* = mapper.MappingRegistry.init(allocator, &all_mappings);
    global_registry = registry;
}

/// Cleanup the global registry
pub fn deinitGlobalRegistry(allocator: std.mem.Allocator) void {
    if (global_registry) |registry| {
        allocator.destroy(registry);
        global_registry = null;
    }
}

/// Get the global registry (must be initialized first)
pub fn getGlobalRegistry() !*mapper.MappingRegistry {
    return global_registry orelse error.RegistryNotInitialized;
}

/// Check if a package is supported
pub fn isPackageSupported(package_name: []const u8) bool {
    if (global_registry) |registry| {
        return registry.findByPackage(package_name) != null;
    }
    return false;
}

/// Get all supported package names
pub fn getSupportedPackages(allocator: std.mem.Allocator) ![]const []const u8 {
    const registry = try getGlobalRegistry();

    var packages = std.ArrayList([]const u8).init(allocator);
    defer packages.deinit();

    for (registry.mappings) |mapping| {
        try packages.append(mapping.package_name);
    }

    return packages.toOwnedSlice();
}

test "registry initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    try initGlobalRegistry(allocator);
    defer deinitGlobalRegistry(allocator);

    const registry = try getGlobalRegistry();

    // Test numpy is registered
    try testing.expect(isPackageSupported("numpy"));

    // Test numpy.sum function exists
    const sum_func = registry.findFunction("numpy.sum");
    try testing.expect(sum_func != null);
    try testing.expectEqualStrings("cblas_dasum", sum_func.?.c_name);
}
