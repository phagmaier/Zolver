const std = @import("std");
const Allocator = std.mem.Allocator;
const GameStateModule = @import("gamestate.zig");
const GameState = GameStateModule.GameState;
const Action = GameStateModule.Action;
const Street = GameStateModule.Street;
const BETSIZES = GameStateModule.BETSIZES;

// =============================================================================
// TYPES
// =============================================================================

/// Terminal node - game is over, no more actions
pub const Terminal = struct {
    pot: f32,
    folded_p1: ?bool, // null = showdown, true = P1 folded, false = P2 folded

    pub fn fold(pot: f32, folder_is_p1: bool) Terminal {
        return .{ .pot = pot, .folded_p1 = folder_is_p1 };
    }

    pub fn showdown(pot: f32) Terminal {
        return .{ .pot = pot, .folded_p1 = null };
    }
};

/// One outcome of a chance event (one possible card)
/// Each outcome has its OWN subtree with its OWN regret storage
pub const ChanceOutcome = struct {
    card: u8, // 0-51 card index
    child: EdgeChild,
};

/// What an edge leads to - could be another decision, a chance event, or terminal
pub const EdgeChild = union(enum) {
    terminal: Terminal,
    decision: *Node,
    chance: []ChanceOutcome,
};

/// An edge from a decision node - represents one possible action
pub const Edge = struct {
    action: Action,
    bet_size: f32, // The total wager amount (for BET/ALLIN), 0 otherwise
    child: EdgeChild,
};

/// A decision node - a player must choose an action here
/// Contains regret and strategy storage for CFR
pub const Node = struct {
    is_p1: bool,
    edges: []Edge,
    regrets: []f32, // [num_hands * num_edges] - flattened 2D array
    strategy_sum: []f32, // [num_hands * num_edges] - for averaging

    pub fn create(arena: Allocator) !*Node {
        const self = try arena.create(Node);
        self.* = .{
            .is_p1 = undefined,
            .edges = &.{},
            .regrets = &.{},
            .strategy_sum = &.{},
        };
        return self;
    }

    /// Finalize the node after all edges have been determined
    /// Allocates regret/strategy arrays sized for [num_hands × num_edges]
    pub fn finalize(
        self: *Node,
        arena: Allocator,
        is_p1: bool,
        edges: []const Edge,
        num_hands: usize,
    ) !void {
        self.is_p1 = is_p1;
        self.edges = try arena.dupe(Edge, edges);

        const size = edges.len * num_hands;
        if (size > 0) {
            self.regrets = try arena.alloc(f32, size);
            self.strategy_sum = try arena.alloc(f32, size);
            @memset(self.regrets, 0);
            @memset(self.strategy_sum, 0);
        }
    }

    /// Access regret for a specific hand and action
    /// Layout: regrets[hand_idx * num_actions + action_idx]
    pub fn getRegret(self: *const Node, hand_idx: usize, action_idx: usize) f32 {
        return self.regrets[hand_idx * self.edges.len + action_idx];
    }

    pub fn setRegret(self: *Node, hand_idx: usize, action_idx: usize, value: f32) void {
        self.regrets[hand_idx * self.edges.len + action_idx] = value;
    }

    pub fn addRegret(self: *Node, hand_idx: usize, action_idx: usize, delta: f32) void {
        self.regrets[hand_idx * self.edges.len + action_idx] += delta;
    }
};

// =============================================================================
// TREE BUILDING
// =============================================================================

/// Context passed through tree building to avoid parameter explosion
const BuildContext = struct {
    arena: Allocator,
    temp: Allocator,
    num_hands_p1: usize,
    num_hands_p2: usize,
    bb: f32,
};

/// Main entry point: builds the complete game tree from a starting state
///
/// The tree represents ALL possible action sequences. Each path through the
/// tree is a unique game history. Chance nodes branch on all possible cards.
///
/// Memory: Uses arena allocator for all persistent tree data.
/// The temp allocator is used for working memory during construction.
pub fn buildTree(
    state: *GameState,
    arena: Allocator,
    temp: Allocator,
    num_hands_p1: usize,
    num_hands_p2: usize,
    bb: f32,
) !*Node {
    const ctx = BuildContext{
        .arena = arena,
        .temp = temp,
        .num_hands_p1 = num_hands_p1,
        .num_hands_p2 = num_hands_p2,
        .bb = bb,
    };
    return buildDecisionNode(state, ctx);
}

/// Build a decision node and all its children recursively
///
/// A decision node is where a player must choose an action.
/// We enumerate all legal actions from the current state.
fn buildDecisionNode(state: *GameState, ctx: BuildContext) Allocator.Error!*Node {
    std.debug.assert(!state.isTerm); // Decision nodes are never terminal

    const node = try Node.create(ctx.arena);
    var edges = std.ArrayListUnmanaged(Edge){};
    defer edges.deinit(ctx.temp);

    // Try each possible action and build edges for valid ones
    // Order matters for consistency: FOLD, CHECK, CALL, ALLIN, then BETs

    if (state.getFoldGameState()) |next| {
        try edges.append(ctx.temp, try buildEdge(next, state.street, ctx));
    }

    if (state.getCheckGameState()) |next| {
        try edges.append(ctx.temp, try buildEdge(next, state.street, ctx));
    }

    if (state.getCallGameState()) |next| {
        try edges.append(ctx.temp, try buildEdge(next, state.street, ctx));
    }

    if (state.getAllInGameState()) |next| {
        try edges.append(ctx.temp, try buildEdge(next, state.street, ctx));
    }

    for (BETSIZES) |pct| {
        if (state.getBetGameState(pct, ctx.bb)) |next| {
            try edges.append(ctx.temp, try buildEdge(next, state.street, ctx));
        }
    }

    // Finalize: copy edges to arena and allocate regret arrays
    const num_hands = if (state.isp1) ctx.num_hands_p1 else ctx.num_hands_p2;
    try node.finalize(ctx.arena, state.isp1, edges.items, num_hands);

    return node;
}

/// Build an edge (action + child) from a resulting game state
fn buildEdge(next_state: GameState, prev_street: Street, ctx: BuildContext) Allocator.Error!Edge {
    return Edge{
        .action = next_state.action,
        .bet_size = next_state.bet,
        .child = try buildChild(next_state, prev_street, ctx),
    };
}

/// Determine what kind of child node an action leads to
///
/// This is the core routing logic:
/// 1. FOLD → Terminal (opponent wins)
/// 2. All-in call before river → Runout (deal remaining cards, then showdown)
/// 3. Any other terminal → Showdown
/// 4. Street changed → Chance node (deal next card)
/// 5. Same street → Decision node (other player acts)
fn buildChild(state: GameState, prev_street: Street, ctx: BuildContext) Allocator.Error!EdgeChild {
    // CASE 1: Fold - always terminal, opponent wins pot
    if (state.action == .FOLD) {
        // getFoldGameState flips isp1, so folder was !state.isp1
        return .{ .terminal = Terminal.fold(state.pot, !state.isp1) };
    }

    // CASE 2: All-in call before river - need to run out remaining cards
    // Detection: terminal + CALL + not river = must be all-in call
    // (Normal calls on flop/turn go to next street, not terminal)
    if (state.isTerm and state.action == .CALL and state.street != .RIVER) {
        return .{ .chance = try buildRunout(state.pot, state.street, ctx) };
    }

    // CASE 3: Other terminal states (river call, river check-check)
    if (state.isTerm) {
        return .{ .terminal = Terminal.showdown(state.pot) };
    }

    // CASE 4: Street transition - create chance node for next card
    if (state.street != prev_street) {
        return .{ .chance = try buildStreetTransition(state, ctx) };
    }

    // CASE 5: Same street, action continues - create decision node
    var mutable = state;
    return .{ .decision = try buildDecisionNode(&mutable, ctx) };
}

/// Build chance outcomes for a street transition (normal play, not all-in)
///
/// When transitioning from flop→turn or turn→river, we create one subtree
/// for each possible card that could be dealt.
///
/// Number of cards:
/// - Flop→Turn: 49 cards (52 - 3 flop cards)
/// - Turn→River: 48 cards (52 - 4 board cards)
fn buildStreetTransition(state: GameState, ctx: BuildContext) Allocator.Error![]ChanceOutcome {
    const num_cards: usize = switch (state.street) {
        .TURN => 49, // Transitioned TO turn, 52 - 3 = 49 possible
        .RIVER => 48, // Transitioned TO river, 52 - 4 = 48 possible
        .FLOP => unreachable, // Can't transition TO flop in postflop solver
    };

    const outcomes = try ctx.arena.alloc(ChanceOutcome, num_cards);

    // Create a SEPARATE subtree for each possible card
    // Each subtree has its own regret storage - this is essential!
    // The optimal strategy after A♠ turn differs from K♥ turn.
    for (0..num_cards) |i| {
        var mutable = state;
        outcomes[i] = .{
            .card = @intCast(i), // Index into remaining deck (computed during CFR)
            .child = .{ .decision = try buildDecisionNode(&mutable, ctx) },
        };
    }

    return outcomes;
}

/// Build a runout for all-in situations before the river
///
/// When both players are all-in, no more decisions are possible.
/// We still need to deal the remaining cards to determine the winner.
/// This creates a chain of chance nodes leading to showdown terminals.
fn buildRunout(pot: f32, street: Street, ctx: BuildContext) Allocator.Error![]ChanceOutcome {
    return switch (street) {
        .FLOP => try buildRunoutFromFlop(pot, ctx),
        .TURN => try buildRunoutFromTurn(pot, ctx),
        .RIVER => unreachable, // River all-in is just a showdown, no runout
    };
}

/// Runout from flop: deal turn (49 cards) then river (48 cards each)
fn buildRunoutFromFlop(pot: f32, ctx: BuildContext) Allocator.Error![]ChanceOutcome {
    const turn_outcomes = try ctx.arena.alloc(ChanceOutcome, 49);

    for (0..49) |turn_idx| {
        // For each turn card, create river chance outcomes
        const river_outcomes = try ctx.arena.alloc(ChanceOutcome, 48);

        for (0..48) |river_idx| {
            river_outcomes[river_idx] = .{
                .card = @intCast(river_idx),
                .child = .{ .terminal = Terminal.showdown(pot) },
            };
        }

        turn_outcomes[turn_idx] = .{
            .card = @intCast(turn_idx),
            .child = .{ .chance = river_outcomes },
        };
    }

    return turn_outcomes;
}

/// Runout from turn: deal river (48 cards)
fn buildRunoutFromTurn(pot: f32, ctx: BuildContext) Allocator.Error![]ChanceOutcome {
    const river_outcomes = try ctx.arena.alloc(ChanceOutcome, 48);

    for (0..48) |river_idx| {
        river_outcomes[river_idx] = .{
            .card = @intCast(river_idx),
            .child = .{ .terminal = Terminal.showdown(pot) },
        };
    }

    return river_outcomes;
}

// =============================================================================
// TREE STATISTICS (for debugging/verification)
// =============================================================================

pub const TreeStats = struct {
    decision_nodes: usize,
    chance_nodes: usize,
    terminal_fold: usize,
    terminal_showdown: usize,
    total_edges: usize,
    max_depth: usize,
};

pub fn computeStats(root: *Node) TreeStats {
    var stats = TreeStats{
        .decision_nodes = 0,
        .chance_nodes = 0,
        .terminal_fold = 0,
        .terminal_showdown = 0,
        .total_edges = 0,
        .max_depth = 0,
    };
    computeStatsRecursive(root, &stats, 0);
    return stats;
}

fn computeStatsRecursive(node: *Node, stats: *TreeStats, depth: usize) void {
    stats.decision_nodes += 1;
    stats.total_edges += node.edges.len;
    stats.max_depth = @max(stats.max_depth, depth);

    for (node.edges) |edge| {
        switch (edge.child) {
            .terminal => |t| {
                if (t.folded_p1 != null) {
                    stats.terminal_fold += 1;
                } else {
                    stats.terminal_showdown += 1;
                }
            },
            .decision => |child| {
                computeStatsRecursive(child, stats, depth + 1);
            },
            .chance => |outcomes| {
                stats.chance_nodes += 1;
                for (outcomes) |outcome| {
                    countChanceChild(outcome.child, stats, depth + 1);
                }
            },
        }
    }
}

fn countChanceChild(child: EdgeChild, stats: *TreeStats, depth: usize) void {
    switch (child) {
        .terminal => |t| {
            if (t.folded_p1 != null) {
                stats.terminal_fold += 1;
            } else {
                stats.terminal_showdown += 1;
            }
        },
        .decision => |node| {
            computeStatsRecursive(node, stats, depth);
        },
        .chance => |outcomes| {
            stats.chance_nodes += 1;
            for (outcomes) |outcome| {
                countChanceChild(outcome.child, stats, depth + 1);
            }
        },
    }
}

// =============================================================================
// TESTS
// =============================================================================

test "build simple tree - flop P1 to act" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const num_hands: usize = 10;
    const bb: f32 = 1.0;

    var state = GameState.init(.FLOP, true, 100.0, 500.0, 500.0);

    std.debug.print("BUILDING TREE\n", .{});
    const root = try buildTree(&state, arena.allocator(), allocator, num_hands, num_hands, bb);

    std.debug.print("BUILT TREE\n", .{});
    // Basic sanity checks
    try std.testing.expect(root.is_p1 == true);
    try std.testing.expect(root.edges.len > 0);
    try std.testing.expect(root.regrets.len == root.edges.len * num_hands);

    const stats = computeStats(root);
    std.debug.print("\nTree Stats:\n", .{});
    std.debug.print("  Decision nodes: {}\n", .{stats.decision_nodes});
    std.debug.print("  Chance nodes: {}\n", .{stats.chance_nodes});
    std.debug.print("  Terminal (fold): {}\n", .{stats.terminal_fold});
    std.debug.print("  Terminal (showdown): {}\n", .{stats.terminal_showdown});
    std.debug.print("  Total edges: {}\n", .{stats.total_edges});
    std.debug.print("  Max depth: {}\n", .{stats.max_depth});
}

test "verify edge actions are correct" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var state = GameState.init(.FLOP, true, 100.0, 500.0, 500.0);
    const root = try buildTree(&state, arena.allocator(), allocator, 10, 10, 1.0);
    var has_check = false;
    var has_fold = false;
    var has_call = false;
    var has_allin = false;
    var num_bets: usize = 0;

    for (root.edges) |edge| {
        switch (edge.action) {
            .CHECK => has_check = true,
            .FOLD => has_fold = true,
            .CALL => has_call = true,
            .ALLIN => has_allin = true,
            .BET => num_bets += 1,
        }
    }

    try std.testing.expect(has_check);
    try std.testing.expect(!has_fold); // Can't fold with no bet
    try std.testing.expect(!has_call); // Can't call with no bet
    try std.testing.expect(has_allin);
    try std.testing.expect(num_bets == BETSIZES.len);
}
