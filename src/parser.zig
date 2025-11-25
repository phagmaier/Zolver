const std = @import("std");
const Card = @import("card.zig");

// ============================================================================
// Enums
// ============================================================================

pub const Player = enum {
    p1,
    p2,
};

pub const Street = enum {
    preflop,
    flop,
    turn,
    river,

    pub fn fromStr(s: []const u8) !Street {
        if (eqlIgnoreCase(s, "preflop")) return .preflop;
        if (eqlIgnoreCase(s, "flop")) return .flop;
        if (eqlIgnoreCase(s, "turn")) return .turn;
        if (eqlIgnoreCase(s, "river")) return .river;
        return error.InvalidStreet;
    }
};

pub const Action = enum {
    none,
    bet,
    check,
    allin,

    pub fn fromStr(s: []const u8) !Action {
        if (eqlIgnoreCase(s, "none")) return .none;
        if (eqlIgnoreCase(s, "bet")) return .bet;
        if (eqlIgnoreCase(s, "check")) return .check;
        if (eqlIgnoreCase(s, "allin")) return .allin;
        return error.InvalidAction;
    }
};

// ============================================================================
// Hand (two hole cards)
// ============================================================================

pub const Hand = struct {
    c1: Card.Card,
    c2: Card.Card,

    pub fn init(c1: Card.Card, c2: Card.Card) Hand {
        return .{ .c1 = c1, .c2 = c2 };
    }

    pub fn print(self: Hand) void {
        const s1 = Card.get_card_str(self.c1) catch [2]u8{ '?', '?' };
        const s2 = Card.get_card_str(self.c2) catch [2]u8{ '?', '?' };
        std.debug.print("{s}{s}", .{ s1, s2 });
    }
};

// ============================================================================
// State - the main output struct
// ============================================================================

pub const State = struct {
    pta: Player,
    street: Street,
    prev_action: Action,
    bet: f32,
    stack1: f32,
    stack2: f32,
    pot: f32,
    bb: f32,

    board: std.ArrayList(Card.Card),
    p1_range: std.ArrayList(Hand),
    p2_range: std.ArrayList(Hand),

    pub fn init() State {
        return .{
            .pta = .p1,
            .street = .preflop,
            .prev_action = .none,
            .bet = 0,
            .stack1 = 100,
            .stack2 = 100,
            .pot = 0,
            .bb = 1,
            .board = std.ArrayList(Card.Card).empty,
            .p1_range = std.ArrayList(Hand).empty,
            .p2_range = std.ArrayList(Hand).empty,
        };
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.board.deinit(allocator);
        self.p1_range.deinit(allocator);
        self.p2_range.deinit(allocator);
    }

    pub fn print(self: *const State) void {
        std.debug.print("\n=== State ===\n", .{});
        std.debug.print("PTA: {s}\n", .{@tagName(self.pta)});
        std.debug.print("Street: {s}\n", .{@tagName(self.street)});
        std.debug.print("Prev Action: {s}\n", .{@tagName(self.prev_action)});
        std.debug.print("Bet: {d:.2}\n", .{self.bet});
        std.debug.print("Stack1: {d:.2}, Stack2: {d:.2}\n", .{ self.stack1, self.stack2 });
        std.debug.print("Pot: {d:.2}, BB: {d:.2}\n", .{ self.pot, self.bb });

        std.debug.print("Board: ", .{});
        for (self.board.items) |card| {
            const s = Card.get_card_str(card) catch [2]u8{ '?', '?' };
            std.debug.print("{s} ", .{s});
        }
        std.debug.print("\n", .{});

        std.debug.print("P1 Range ({d} hands): ", .{self.p1_range.items.len});
        for (self.p1_range.items, 0..) |hand, i| {
            if (i > 5) {
                std.debug.print("...", .{});
                break;
            }
            hand.print();
            std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});

        std.debug.print("P2 Range ({d} hands): ", .{self.p2_range.items.len});
        for (self.p2_range.items, 0..) |hand, i| {
            if (i > 5) {
                std.debug.print("...", .{});
                break;
            }
            hand.print();
            std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
    }
};

// ============================================================================
// Utility functions
// ============================================================================

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn trimWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;

    while (start < end and std.ascii.isWhitespace(s[start])) start += 1;
    while (end > start and std.ascii.isWhitespace(s[end - 1])) end -= 1;

    return s[start..end];
}

fn charToRank(c: u8) !u32 {
    return switch (std.ascii.toLower(c)) {
        '2' => 0,
        '3' => 1,
        '4' => 2,
        '5' => 3,
        '6' => 4,
        '7' => 5,
        '8' => 6,
        '9' => 7,
        't' => 8,
        'j' => 9,
        'q' => 10,
        'k' => 11,
        'a' => 12,
        else => error.InvalidRank,
    };
}

fn charToSuit(c: u8) !u32 {
    return switch (std.ascii.toLower(c)) {
        's' => 0, // SPADE
        'h' => 1, // HEART
        'd' => 2, // DIAMOND
        'c' => 3, // CLUB
        else => error.InvalidSuit,
    };
}

// ============================================================================
// Card parsing (specific cards like "Ah", "Kd")
// ============================================================================

fn parseSpecificCard(s: []const u8) !Card.Card {
    if (s.len != 2) return error.InvalidCard;
    const rank = try charToRank(s[0]);
    const suit = try charToSuit(s[1]);
    return Card.makeCard(rank, suit);
}

// ============================================================================
// Hand notation parsing (AKs, 77+, A5s+, etc.)
// ============================================================================

const SUITS = [4]u32{ 0, 1, 2, 3 }; // spade, heart, diamond, club

fn addSuitedCombos(list: *std.ArrayList(Hand), rank1: u32, rank2: u32, allocator: std.mem.Allocator) !void {
    // 4 suited combos: same suit for both cards
    for (SUITS) |suit| {
        const c1 = Card.makeCard(rank1, suit);
        const c2 = Card.makeCard(rank2, suit);
        try list.append(allocator, Hand.init(c1, c2));
    }
}

fn addOffsuitCombos(list: *std.ArrayList(Hand), rank1: u32, rank2: u32, allocator: std.mem.Allocator) !void {
    // 12 offsuit combos: different suits
    for (SUITS) |s1| {
        for (SUITS) |s2| {
            if (s1 != s2) {
                const c1 = Card.makeCard(rank1, s1);
                const c2 = Card.makeCard(rank2, s2);
                try list.append(allocator, Hand.init(c1, c2));
            }
        }
    }
}

fn addPairCombos(list: *std.ArrayList(Hand), rank: u32, allocator: std.mem.Allocator) !void {
    // 6 pair combos: C(4,2) = 6
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        var j: u32 = i + 1;
        while (j < 4) : (j += 1) {
            const c1 = Card.makeCard(rank, i);
            const c2 = Card.makeCard(rank, j);
            try list.append(allocator, Hand.init(c1, c2));
        }
    }
}

fn addAllCombos(list: *std.ArrayList(Hand), rank1: u32, rank2: u32, allocator: std.mem.Allocator) !void {
    if (rank1 == rank2) {
        try addPairCombos(list, rank1, allocator);
    } else {
        try addSuitedCombos(list, rank1, rank2, allocator);
        try addOffsuitCombos(list, rank1, rank2, allocator);
    }
}

const HandType = enum {
    suited,
    offsuit,
    all,
};

fn parseHandNotation(list: *std.ArrayList(Hand), token: []const u8, allocator: std.mem.Allocator) !void {
    if (token.len < 2) return error.InvalidHandNotation;

    const has_plus = token[token.len - 1] == '+';
    const base = if (has_plus) token[0 .. token.len - 1] else token;

    if (base.len < 2) return error.InvalidHandNotation;

    const rank1 = try charToRank(base[0]);
    const rank2 = try charToRank(base[1]);

    // Determine hand type (suited/offsuit/all)
    var hand_type: HandType = .all;
    if (base.len >= 3) {
        const suffix = std.ascii.toLower(base[2]);
        if (suffix == 's') {
            hand_type = .suited;
        } else if (suffix == 'o') {
            hand_type = .offsuit;
        }
    }

    if (has_plus) {
        if (rank1 == rank2) {
            // Pair+ notation: 77+ means 77, 88, 99, ... AA
            var r = rank1;
            while (r <= 12) : (r += 1) {
                try addPairCombos(list, r, allocator);
            }
        } else {
            // Kicker+ notation: A5s+ means A5s, A6s, ... AKs
            // The higher rank stays fixed, lower rank increases
            const high = @max(rank1, rank2);
            var low = @min(rank1, rank2);
            while (low < high) : (low += 1) {
                switch (hand_type) {
                    .suited => try addSuitedCombos(list, high, low, allocator),
                    .offsuit => try addOffsuitCombos(list, high, low, allocator),
                    .all => {
                        try addSuitedCombos(list, high, low, allocator);
                        try addOffsuitCombos(list, high, low, allocator);
                    },
                }
            }
        }
    } else {
        // Single hand notation
        switch (hand_type) {
            .suited => try addSuitedCombos(list, rank1, rank2, allocator),
            .offsuit => try addOffsuitCombos(list, rank1, rank2, allocator),
            .all => try addAllCombos(list, rank1, rank2, allocator),
        }
    }
}

// ============================================================================
// Section parsing
// ============================================================================

const Section = enum {
    none,
    game,
    board,
    p1_range,
    p2_range,
};

fn parseSection(line: []const u8) ?Section {
    const trimmed = trimWhitespace(line);
    if (trimmed.len < 2) return null;
    if (trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return null;

    const name = trimmed[1 .. trimmed.len - 1];
    if (eqlIgnoreCase(name, "game")) return .game;
    if (eqlIgnoreCase(name, "board")) return .board;
    if (eqlIgnoreCase(name, "p1_range")) return .p1_range;
    if (eqlIgnoreCase(name, "p2_range")) return .p2_range;

    return null;
}

fn parseKeyValue(line: []const u8, state: *State) !void {
    // Find the '=' separator
    var sep_idx: ?usize = null;
    for (line, 0..) |c, i| {
        if (c == '=') {
            sep_idx = i;
            break;
        }
    }

    if (sep_idx == null) return; // Not a key-value line

    const key = trimWhitespace(line[0..sep_idx.?]);
    const value = trimWhitespace(line[sep_idx.? + 1 ..]);

    if (eqlIgnoreCase(key, "pta")) {
        if (eqlIgnoreCase(value, "p1")) {
            state.pta = .p1;
        } else if (eqlIgnoreCase(value, "p2")) {
            state.pta = .p2;
        } else {
            return error.InvalidPlayer;
        }
    } else if (eqlIgnoreCase(key, "street")) {
        state.street = try Street.fromStr(value);
    } else if (eqlIgnoreCase(key, "prev_action")) {
        state.prev_action = try Action.fromStr(value);
    } else if (eqlIgnoreCase(key, "bet")) {
        state.bet = try std.fmt.parseFloat(f32, value);
    } else if (eqlIgnoreCase(key, "stack1")) {
        state.stack1 = try std.fmt.parseFloat(f32, value);
    } else if (eqlIgnoreCase(key, "stack2")) {
        state.stack2 = try std.fmt.parseFloat(f32, value);
    } else if (eqlIgnoreCase(key, "pot")) {
        state.pot = try std.fmt.parseFloat(f32, value);
    } else if (eqlIgnoreCase(key, "bb")) {
        state.bb = try std.fmt.parseFloat(f32, value);
    }
    // Unknown keys are silently ignored
}

fn parseTokens(line: []const u8, section: Section, state: *State, allocator: std.mem.Allocator) !void {
    // Tokenize by whitespace and parse each token
    var iter = std.mem.tokenizeAny(u8, line, " \t");
    while (iter.next()) |token| {
        switch (section) {
            .board => {
                const card = try parseSpecificCard(token);
                try state.board.append(allocator, card);
            },
            .p1_range => {
                try parseHandNotation(&state.p1_range, token, allocator);
            },
            .p2_range => {
                try parseHandNotation(&state.p2_range, token, allocator);
            },
            else => {},
        }
    }
}

// ============================================================================
// Main parse function
// ============================================================================

pub fn parse(contents: []const u8, allocator: std.mem.Allocator) !State {
    var state = State.init();
    errdefer state.deinit(allocator);

    var current_section: Section = .none;

    // Split by lines
    var lines = std.mem.splitAny(u8, contents, "\n\r");
    while (lines.next()) |line| {
        const trimmed = trimWhitespace(line);
        if (trimmed.len == 0) continue;

        // Check for section header
        if (parseSection(trimmed)) |section| {
            current_section = section;
            continue;
        }

        // Parse content based on current section
        switch (current_section) {
            .game => try parseKeyValue(trimmed, &state),
            .board, .p1_range, .p2_range => try parseTokens(trimmed, current_section, &state, allocator),
            .none => {}, // Ignore content outside sections
        }
    }

    return state;
}

pub fn parseFile(path: []const u8, allocator: std.mem.Allocator) !State {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Failed to open file: {s}\n", .{path});
        return err;
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB limit
    defer allocator.free(contents);

    return parse(contents, allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "parse hand notation - suited" {
    var list = std.ArrayList(Hand).empty;
    defer list.deinit(std.testing.allocator);

    try parseHandNotation(&list, "AKs", std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), list.items.len);
}

test "parse hand notation - offsuit" {
    var list = std.ArrayList(Hand).empty;
    defer list.deinit(std.testing.allocator);

    try parseHandNotation(&list, "AKo", std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 12), list.items.len);
}

test "parse hand notation - pair" {
    var list = std.ArrayList(Hand).empty;
    defer list.deinit(std.testing.allocator);

    try parseHandNotation(&list, "KK", std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 6), list.items.len);
}

test "parse hand notation - pair plus" {
    var list = std.ArrayList(Hand).empty;
    defer list.deinit(std.testing.allocator);

    try parseHandNotation(&list, "TT+", std.testing.allocator);
    // TT, JJ, QQ, KK, AA = 5 pairs * 6 combos = 30
    try std.testing.expectEqual(@as(usize, 30), list.items.len);
}

test "parse hand notation - suited plus" {
    var list = std.ArrayList(Hand).empty;
    defer list.deinit(std.testing.allocator);

    try parseHandNotation(&list, "ATs+", std.testing.allocator);
    // ATs, AJs, AQs, AKs = 4 hands * 4 combos = 16
    try std.testing.expectEqual(@as(usize, 16), list.items.len);
}

test "parse full config" {
    const config =
        \\[game]
        \\pta = p1
        \\street = flop
        \\prev_action = bet
        \\bet = 3.5
        \\stack1 = 97.5
        \\stack2 = 100
        \\pot = 7
        \\bb = 1
        \\
        \\[board]
        \\Ah Kd 7c
        \\
        \\[p1_range]
        \\AKs QQ
        \\
        \\[p2_range]
        \\AA KK
    ;

    var state = try parse(config, std.testing.allocator);
    defer state.deinit(std.testing.allocator);

    try std.testing.expectEqual(Player.p1, state.pta);
    try std.testing.expectEqual(Street.flop, state.street);
    try std.testing.expectEqual(Action.bet, state.prev_action);
    try std.testing.expectApproxEqAbs(@as(f32, 3.5), state.bet, 0.01);
    try std.testing.expectEqual(@as(usize, 3), state.board.items.len);
    try std.testing.expectEqual(@as(usize, 10), state.p1_range.items.len); // 4 AKs + 6 QQ
    try std.testing.expectEqual(@as(usize, 12), state.p2_range.items.len); // 6 AA + 6 KK
}
