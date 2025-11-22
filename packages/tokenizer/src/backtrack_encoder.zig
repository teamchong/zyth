/// EXACT PORT of rs-bpe's backtrack_encoder.rs
/// Based on: rs-bpe/bpe/src/backtrack_encoder.rs lines 1-87
const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;

// MUST match tokenizer.Pair exactly
pub const Pair = struct {
    left: u32,
    right: u32,

    pub fn hash(self: Pair) u64 {
        return (@as(u64, self.left) << 32) | self.right;
    }

    pub fn eql(a: Pair, b: Pair) bool {
        return a.left == b.left and a.right == b.right;
    }
};

pub const PairContext = struct {
    pub fn hash(_: PairContext, p: Pair) u64 {
        return p.hash();
    }

    pub fn eql(_: PairContext, a: Pair, b: Pair) bool {
        return Pair.eql(a, b);
    }
};

/// Port of rs-bpe BacktrackEncoder struct
pub const BacktrackEncoder = struct {
    allocator: Allocator,
    text: []const u8,
    tokens: std.ArrayList(u32),
    next_token: ?u32,
    pos: usize,
    bitfield: BitField,

    // BPE data
    aho_corasick: *const AhoCorasick,
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    split_table: *const std.AutoHashMap(u32, Pair),
    pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),

    /// Port of rs-bpe::new() (line 22-34)
    pub fn init(
        allocator: Allocator,
        text: []const u8,
        aho_corasick: *const AhoCorasick,
        vocab_r: *const std.AutoHashMap(u32, []const u8),
        split_table: *const std.AutoHashMap(u32, Pair),
        pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    ) !BacktrackEncoder {
        var tokens = std.ArrayList(u32){};
        try tokens.ensureTotalCapacity(allocator, text.len / 3);

        // bpe.next_match(text) (line 31)
        const first_token = aho_corasick.longestMatch(text, 0);

        return BacktrackEncoder{
            .allocator = allocator,
            .text = text,
            .tokens = tokens,
            .next_token = first_token,
            .pos = 0,
            .bitfield = try BitField.init(allocator, text.len + 1),
            .aho_corasick = aho_corasick,
            .vocab_r = vocab_r,
            .split_table = split_table,
            .pair_lookup = pair_lookup,
        };
    }

    pub fn deinit(self: *BacktrackEncoder) void {
        self.tokens.deinit(self.allocator);
        self.bitfield.deinit();
    }

    /// Port of rs-bpe step() (lines 37-70)
    pub fn step(self: *BacktrackEncoder) ?u32 {
        var token = self.next_token orelse return null;
        const last = if (self.tokens.items.len > 0) self.tokens.items[self.tokens.items.len - 1] else null;

        while (true) {
            const token_len = self.tokenLen(token);
            const end_pos = self.pos + token_len;

            // Check: bitfield.is_set(end_pos) && is_valid_token_pair(last, token)
            const bitfield_ok = self.bitfield.isSet(end_pos);
            const pair_ok = if (last) |last_token|
                isValidTokenPairImpl(self.pair_lookup, self.split_table, last_token, token)
            else
                true;

            if (bitfield_ok and pair_ok) {
                // Valid path - accept token
                self.tokens.append(self.allocator, token) catch return null;
                self.pos = end_pos;
                self.next_token = self.aho_corasick.longestMatch(self.text, end_pos);
                break;
            } else if (self.nextPrefix(token)) |shorter| {
                // Try shorter token
                token = shorter;
            } else {
                // Backtrack
                self.bitfield.clear(self.pos);
                if (self.tokens.items.len > 0) {
                    _ = self.tokens.pop();
                }
                self.pos -= if (last) |t| self.tokenLen(t) else 0;
                self.next_token = last;
                break;
            }
        }

        return self.next_token;
    }

    /// Encode full text (call step() until done)
    pub fn encode(self: *BacktrackEncoder) ![]u32 {
        while (self.step()) |_| {}
        return try self.tokens.toOwnedSlice(self.allocator);
    }

    /// Get token length in bytes (port of bpe.token_len)
    fn tokenLen(self: *const BacktrackEncoder, token: u32) usize {
        if (self.vocab_r.get(token)) |bytes| {
            return bytes.len;
        }
        return 1; // Single byte fallback
    }

    /// Port of bpe.next_prefix - find next shorter prefix match
    fn nextPrefix(self: *const BacktrackEncoder, token: u32) ?u32 {
        const token_bytes = self.vocab_r.get(token) orelse return null;
        if (token_bytes.len <= 1) return null;

        // Try progressively shorter prefixes
        var len = token_bytes.len - 1;
        while (len > 0) : (len -= 1) {
            const prefix = token_bytes[0..len];
            // Search for this prefix in vocab via Aho-Corasick
            if (self.aho_corasick.longestMatch(prefix, 0)) |shorter_token| {
                // Verify it's actually this prefix
                if (self.vocab_r.get(shorter_token)) |shorter_bytes| {
                    if (std.mem.eql(u8, shorter_bytes, prefix)) {
                        return shorter_token;
                    }
                }
            }
        }

        return null;
    }
};

/// EXACT PORT of rs-bpe is_valid_token_pair (from byte_pair_encoding.rs lines 112-148)
fn isValidTokenPairImpl(
    pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    split_table: *const std.AutoHashMap(u32, Pair),
    token1_arg: u32,
    token2_arg: u32,
) bool {
    var token1 = token1_arg;
    var token2 = token2_arg;
    var limit: u32 = std.math.maxInt(u32);

    while (true) {
        // Check if this pair exists in pair_lookup
        if (pair_lookup.get(Pair{ .left = token1, .right = token2 })) |combined| {
            if (combined < limit) {
                return false;
            }
            return true;
        }

        if (token1 > token2) {
            limit = token1;
            if (split_table.get(token1)) |split| {
                token1 = split.right;
                if (token1 == limit) {
                    limit = token2 + 1;
                    if (split_table.get(token2)) |split2| {
                        token2 = split2.left;
                        if (token2 + 1 == limit) {
                            return true;
                        }
                    } else {
                        return true;
                    }
                }
            } else {
                return true;
            }
        } else {
            limit = token2 + 1;
            if (split_table.get(token2)) |split| {
                token2 = split.left;
                if (token2 + 1 == limit) {
                    limit = token1;
                    if (split_table.get(token1)) |split2| {
                        token1 = split2.right;
                        if (token1 == limit) {
                            return true;
                        }
                    } else {
                        return true;
                    }
                }
            } else {
                return true;
            }
        }
    }
}

/// BitField for tracking visited positions
const BitField = struct {
    bits: []u64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !BitField {
        const num_words = (size + 63) / 64;
        const bits = try allocator.alloc(u64, num_words);
        @memset(bits, 0xFFFFFFFFFFFFFFFF); // All bits set initially
        return BitField{ .bits = bits, .allocator = allocator };
    }

    pub fn deinit(self: *BitField) void {
        self.allocator.free(self.bits);
    }

    pub inline fn isSet(self: *const BitField, pos: usize) bool {
        const word = pos >> 6;
        const bit = @as(u6, @truncate(pos));
        return (self.bits[word] & (@as(u64, 1) << bit)) != 0;
    }

    pub inline fn clear(self: *BitField, pos: usize) void {
        const word = pos >> 6;
        const bit = @as(u6, @truncate(pos));
        self.bits[word] &= ~(@as(u64, 1) << bit);
    }
};
