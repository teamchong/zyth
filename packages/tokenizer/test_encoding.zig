const std = @import("std");
const Tokenizer = @import("src/tokenizer.zig").Tokenizer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Train a small tokenizer on same data
    const texts = [_][]const u8{
        "Hello, world! This is a test of tokenization.",
        "Hello again! More test text here.",
        "Testing tokenization with various words.",
    };
    
    const texts_slice: []const []const u8 = &texts;
    
    var tokenizer = try Tokenizer.train(allocator, texts_slice, 512);
    defer tokenizer.deinit();

    // Encode the same text
    const test_text = "Hello, world! This is a test of tokenization.";
    const tokens = try tokenizer.encode(test_text);
    defer allocator.free(tokens);

    std.debug.print("PyAOT tokens: [", .{});
    for (tokens, 0..) |token, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("{}", .{token});
    }
    std.debug.print("]\n", .{});
    std.debug.print("Count: {}\n", .{tokens.len});

    // Decode back
    const decoded = try tokenizer.decode(tokens);
    defer allocator.free(decoded);

    std.debug.print("Decoded: '{s}'\n", .{decoded});
    std.debug.print("Match: {}\n", .{std.mem.eql(u8, decoded, test_text)});
}
