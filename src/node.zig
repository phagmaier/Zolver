const std = @import("std");
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const print = std.debug.print;

// Import GameState and aliases
const GameStateModule = @import("gamestate.zig");
const GameState = GameStateModule.GameState;
const Action = GameStateModule.Action; // Fixed: Alias correctly to the Enum
const BETSIZES = GameStateModule.BETSIZES;

pub const Edge = struct {
    action: Action,
    amount: f32,
    child: ?*Node,
};

pub const Node = struct {
    regrets: []f32,
    strategy_sum: []f32,
    // Changed []*Edge to []Edge for cache locality (it's much faster)
    edges: []Edge,
};
