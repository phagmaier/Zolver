const std = @import("std");
const builtin = @import("builtin");
const NodeModule = @import("node.zig");
const GameStateModule = @import("gamestate.zig");
const Parser = @import("parser.zig");
const Hand = Parser.Hand;
const GameState = GameStateModule.GameState;
const Edge = NodeModule.Edge;

pub fn parse_to_start(path: []const u8, temp_allocator: std.mem.Allocator) !struct { state: GameState, h1: []Hand, h2: []Hand, bb: f32 } {
    // 1. Parse the file into the temporary Parser state
    var root_state = try Parser.parseFile(path, temp_allocator);
    // We clean up the board/parser shell, but we will "steal" the hand ranges via toOwnedSlice later
    defer root_state.board.deinit(temp_allocator);

    // 2. Map Street (Parser.Street -> GameState.Street)
    const street: GameStateModule.Street = switch (root_state.street) {
        .flop => .FLOP,
        .turn => .TURN,
        .river => .RIVER,
        else => return error.InvalidStreet,
    };

    // 3. Map Action and Betting State
    var action: GameStateModule.Action = .CHECK;
    var numbets: u8 = 0;
    var current_bet_p1: f32 = 0;
    var current_bet_p2: f32 = 0;

    switch (root_state.prev_action) {
        .none => {
            // "None" means start of street -> implicitly a Check state with 0 bets
            action = .CHECK;
            numbets = 0;
        },
        .check => {
            // "Check" -> Check state with 0 bets
            action = .CHECK;
            numbets = 0;
        },
        .bet => {
            action = .BET;
            numbets = 1;
            // If it is P1's turn (pta=p1), then P2 is the one who bet previously
            if (root_state.pta == .p1) {
                current_bet_p2 = root_state.bet;
                current_bet_p1 = 0;
            } else {
                current_bet_p1 = root_state.bet;
                current_bet_p2 = 0;
            }
        },
        .allin => {
            action = .ALLIN;
            numbets = 1;
            if (root_state.pta == .p1) {
                current_bet_p2 = root_state.bet;
                current_bet_p1 = 0;
            } else {
                current_bet_p1 = root_state.bet;
                current_bet_p2 = 0;
            }
        },
    }

    // 4. Initialize GameState
    // We use .init() for defaults, then override with specific parser data
    var game_state = GameState.init(street, (root_state.pta == .p1), // isp1
        root_state.pot, root_state.stack1, root_state.stack2);

    // Override internal state based on the mappings above
    game_state.action = action;
    game_state.bet = root_state.bet;
    game_state.numbets = numbets;
    game_state.current_bet_p1 = current_bet_p1;
    game_state.current_bet_p2 = current_bet_p2;

    // 5. Extract Hands
    // We use toOwnedSlice so the caller becomes the owner of this memory.
    // This prevents double-freeing or losing the data when root_state goes out of scope.
    const h1 = try root_state.p1_range.toOwnedSlice(temp_allocator);
    const h2 = try root_state.p2_range.toOwnedSlice(temp_allocator);

    return .{
        .state = game_state,
        .h1 = h1,
        .h2 = h2,
        .bb = root_state.bb,
    };
}

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const temp_allocator = if (builtin.mode == .Debug)
        da.allocator()
    else
        std.heap.smp_allocator;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    std.debug.print("Initializing Tree...\n", .{});

    // --- usage of parse_to_start ---
    const parsed_data = try parse_to_start("../Data/exampleData.txt", temp_allocator);

    // We now have ownership of these slices, so we should defer freeing them (or let arena handle it if we copied them)
    defer temp_allocator.free(parsed_data.h1);
    defer temp_allocator.free(parsed_data.h2);

    var root_state = parsed_data.state;
    const bb = parsed_data.bb;
    const h1 = parsed_data.h1;
    const h2 = parsed_data.h2;

    std.debug.print("Parsed State: Street={any}, Pot={d}, BB={d}\n", .{ root_state.street, root_state.pot, bb });
    std.debug.print("Hands: P1={d}, P2={d}\n", .{ h1.len, h2.len });

    var root_list = std.ArrayListUnmanaged(Edge){};
    defer root_list.deinit(temp_allocator);

    // Since you don't need this just make a function in Node called start and pass all this data
    try NodeModule.buildTree(&root_state, &root_list, arena_allocator, temp_allocator, @intCast(h1.len), @intCast(h2.len), bb);

    if (root_list.items.len == 0) {
        std.debug.print("Error: Tree is empty!\n", .{});
        return;
    }
}
