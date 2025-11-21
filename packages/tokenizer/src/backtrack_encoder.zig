/// Backtracking encoder - port of rs-bpe's algorithm
/// Greedy forward pass with backtracking on invalid pairs
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const BacktrackEncoder = struct {
    allocator: Allocator,
    text: []const u8,
    tokens: std.ArrayList(u32),
    pos: usize,
    bitfield: BitField,

    // Vocab lookups
    vocab: *const std.StringHashMap(u32),
    vocab_r: *const std.AutoHashMap(u32, []const u8),

    pub fn init(
        allocator: Allocator,
        text: []const u8,
        vocab: *const std.StringHashMap(u32),
        vocab_r: *const std.AutoHashMap(u32, []const u8),
    ) !BacktrackEncoder {
        var tokens = std.ArrayList(u32){};
        try tokens.ensureTotalCapacity(allocator, text.len / 3);

        return BacktrackEncoder{
            .allocator = allocator,
            .text = text,
            .tokens = tokens,
            .pos = 0,
            .bitfield = try BitField.init(allocator, text.len + 1),
            .vocab = vocab,
            .vocab_r = vocab_r,
        };
    }

    pub fn deinit(self: *BacktrackEncoder) void {
        self.tokens.deinit(self.allocator);
        self.bitfield.deinit();
    }

    /// Find longest token match starting at current position
    fn nextMatch(self: *BacktrackEncoder) ?u32 {
        if (self.pos >= self.text.len) return null;

        // Try progressively longer sequences
        var best_token: ?u32 = null;
        var max_len: usize = 1;

        // Start with single byte
        const byte = self.text[self.pos];
        const byte_slice = self.text[self.pos..self.pos+1];
        if (self.vocab.get(byte_slice)) |token| {
            best_token = token;
        } else {
            best_token = byte; // Fallback
        }

        // Try longer matches (greedy longest)
        var len: usize = 2;
        while (self.pos + len <= self.text.len and len <= 512) : (len += 1) {
            const slice = self.text[self.pos..self.pos+len];
            if (self.vocab.get(slice)) |token| {
                best_token = token;
                max_len = len;
            }
        }

        return best_token;
    }

    /// Find next shorter prefix of current token
    fn nextPrefix(self: *BacktrackEncoder, _: u32, token_len: usize) ?u32 {
        if (token_len <= 1) return null;

        // Try progressively shorter prefixes
        var len = token_len - 1;
        while (len > 0) : (len -= 1) {
            const slice = self.text[self.pos..self.pos+len];
            if (self.vocab.get(slice)) |shorter_token| {
                return shorter_token;
            }
        }

        return null;
    }

    /// Check if token pair is valid (can be merged)
    fn isValidPair(self: *BacktrackEncoder, left: u32, right: u32) bool {
        const left_bytes = self.vocab_r.get(left) orelse return false;
        const right_bytes = self.vocab_r.get(right) orelse return false;

        // Concatenate and check if merged token exists
        var buffer: [1024]u8 = undefined;
        const total_len = left_bytes.len + right_bytes.len;
        if (total_len > buffer.len) return false;

        @memcpy(buffer[0..left_bytes.len], left_bytes);
        @memcpy(buffer[left_bytes.len..total_len], right_bytes);

        return self.vocab.contains(buffer[0..total_len]);
    }

    /// Get token length in bytes
    fn tokenLen(self: *BacktrackEncoder, token: u32) usize {
        if (self.vocab_r.get(token)) |bytes| {
            return bytes.len;
        }
        return 1; // Single byte fallback
    }

    /// Main encoding loop - rs-bpe backtracking algorithm
    pub fn encode(self: *BacktrackEncoder) ![]u32 {
        while (self.pos < self.text.len) {
            var token = self.nextMatch() orelse break;

            while (true) {
                const token_length = self.tokenLen(token);
                const end_pos = self.pos + token_length;

                // Check if we can use this token
                const can_use = blk: {
                    if (!self.bitfield.isSet(end_pos)) break :blk false;

                    if (self.tokens.items.len > 0) {
                        const last = self.tokens.items[self.tokens.items.len - 1];
                        if (!self.isValidPair(last, token)) break :blk false;
                    }

                    break :blk true;
                };

                if (can_use) {
                    // Accept token and move forward
                    try self.tokens.append(self.allocator, token);
                    self.pos = end_pos;
                    break;
                } else {
                    // Try shorter prefix
                    if (self.nextPrefix(token, token_length)) |shorter| {
                        token = shorter;
                        continue;
                    }

                    // Backtrack: remove last token
                    if (self.tokens.items.len > 0) {
                        const last = self.tokens.items[self.tokens.items.len - 1];
                        _ = self.tokens.pop();
                        const last_len = self.tokenLen(last);
                        self.bitfield.clear(self.pos);
                        self.pos -= last_len;
                        break;
                    }

                    // Can't proceed - skip this position
                    self.pos += 1;
                    break;
                }
            }
        }

        return try self.tokens.toOwnedSlice(self.allocator);
    }
};

/// BitField for tracking valid positions
const BitField = struct {
    bits: []u64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !BitField {
        const num_words = (size + 63) / 64;
        const bits = try allocator.alloc(u64, num_words);
        @memset(bits, 0xFFFFFFFFFFFFFFFF); // All bits set
        return BitField{ .bits = bits, .allocator = allocator };
    }

    pub fn deinit(self: *BitField) void {
        self.allocator.free(self.bits);
    }

    pub inline fn isSet(self: *const BitField, pos: usize) bool {
        const word = pos >> 6;
        if (word >= self.bits.len) return false;
        const bit = @as(u6, @truncate(pos));
        return (self.bits[word] & (@as(u64, 1) << bit)) != 0;
    }

    pub inline fn clear(self: *BitField, pos: usize) void {
        const word = pos >> 6;
        if (word >= self.bits.len) return;
        const bit = @as(u6, @truncate(pos));
        self.bits[word] &= ~(@as(u64, 1) << bit);
    }
};
