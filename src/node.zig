const std = @import("std");
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;
const GameStateModule = @import("gamestate.zig");
const GameState = GameStateModule.GameState;
const Action = GameStateModule.Action;
const Parser = @import("parser.zig");
const Hand = Parser.Hand;
const BETSIZES = GameStateModule.BETSIZES;

pub const Edge = struct {
    action: Action,
    amount: f32,
    child: ?*Node,

    pub fn init(arena: Allocator, state: *GameState) !Edge {
        return Edge{ .action = state.action, .amount = state.pot, .child = if (state.isTerm) null else try Node.create(arena) };
    }

    pub fn setChildren(self: *Edge, arena: Allocator, arr: *std.ArrayList(Edge), numCards: usize) !void {
        if (self.child) |child| {
            try child.finalize(arena, arr, numCards);
        }
    }
};

pub const Node = struct {
    regrets: []f32,
    strategy_sum: []f32,
    edges: []Edge,

    pub fn create(arena: Allocator) !*Node {
        var self = try arena.create(Node);
        self.regrets = &.{};
        self.strategy_sum = &.{};
        self.edges = &.{};
        return self;
    }

    pub fn finalize(self: *Node, arena: Allocator, arr: *std.ArrayList(Edge), numCards: usize) !void {
        const size = arr.items.len;

        // Allocate slices in Arena
        self.edges = try arena.alloc(Edge, size);
        @memcpy(self.edges, arr.items);

        self.regrets = try arena.alloc(f32, size * numCards);
        self.strategy_sum = try arena.alloc(f32, size * numCards);
        @memset(self.regrets, 0);
        @memset(self.strategy_sum, 0);
    }
};

pub fn buildTree(state: *GameState, arr: *std.ArrayList(Edge), arena: Allocator, temp_allocator: Allocator, numCards1: usize, numCards2: usize, bb: f32) !void {
    var edge = try Edge.init(arena, state);
    if (state.isTerm) {
        try arr.append(temp_allocator, edge);
        return;
    }
    var childArr = std.ArrayList(Edge).empty;
    defer childArr.deinit(temp_allocator);
    if (state.getFoldGameState()) |cState| {
        var mutable_state = cState;
        try buildTree(&mutable_state, &childArr, arena, temp_allocator, numCards1, numCards2, bb);
    }
    if (state.getCallGameState()) |cState| {
        var mutable_state = cState;
        try buildTree(&mutable_state, &childArr, arena, temp_allocator, numCards1, numCards2, bb);
    }
    if (state.getCheckGameState()) |cState| {
        var mutable_state = cState;
        try buildTree(&mutable_state, &childArr, arena, temp_allocator, numCards1, numCards2, bb);
    }
    if (state.getAllInGameState()) |cState| {
        var mutable_state = cState;
        try buildTree(&mutable_state, &childArr, arena, temp_allocator, numCards1, numCards2, bb);
    }
    for (BETSIZES) |prct| {
        if (state.getBetGameState(prct, bb)) |cState| {
            var mutable_state = cState;
            try buildTree(&mutable_state, &childArr, arena, temp_allocator, numCards1, numCards2, bb);
        }
    }

    const numCards = if (state.isp1) numCards1 else numCards2;
    try edge.setChildren(arena, &childArr, numCards);
    try arr.append(temp_allocator, edge);
}

pub fn cfrm(arr: *std.ArrayList(Edge), h1: []Hand, h2: Hand, allocator: Allocator, stack1: f32, stack2: f32, pta: bool, iterations: usize) !void {
    //const reach: [2][3]f32 = .{ .{ 1, 1, 1 }, .{ 1, 1, 1 } };
    const reach1 = try allocator.alloc(f32, h1.len);
    defer allocator.free(reach1);
    const reach2 = try allocator.alloc(f32, h2.len);
    defer allocator.free(reach2);
    var util = std.ArrayList([]f32).empty; //could probably init capacity
    defer util.deinit(allocator);
    for (0..iterations) |_| {
        for (arr.items) |*edge| {
            try util.append(allocator, try _cfrm(edge, reach1, reach2, stack1, stack2, pta, allocator));
        }

        //need to take care of head nodes here outside of normal program i think. Guess i could
        //manually make a head Edge that would have these as children though?
        //idk deal with that later
        util.clearRetainingCapacity(); //After updating and geting util clear
    }
}

fn _cfrm(edge: *Edge, reach1: []f32, reach2: f32, stack1: f32, stack2: f32, pta: bool, allocator: Allocator) ![]f32 {
    var utils = std.ArrayList([]f32).empty;
    defer utils.deinit(allocator);


    if (edge.child) |node| {
        for(node.edges)|*child_edge|{
            //Need to update reaches and then pass
            //So you need to determine if child node is same player or different player
            //this will determine which reach you need to update
            //you then need to also of course free it when done
            //you can probably allocate both up top and then once done iterating then free it
            //Once you add threading this becomes much harder
        try utils.append(_cfrm(child_edge, reach1, reach2, stack1, stack2, pta, allocator))
        }
    }
}

pub fn start(startState: *GameState, h1: []Hand, h2: []Hand, bb: f32, pta: bool, iterations: usize, arena: Allocator, temp_allocator: Allocator) !void {
    var headNodes = try std.ArrayList(Edge).initCapacity(arena, 1000);
    try buildTree(startState, &headNodes, arena, temp_allocator, h1.len, h2.len, bb);
    try cfrm(&headNodes, h1, h2, temp_allocator, startState.stack1, startState.stack2, pta, iterations);
}

test "Init" {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const temp_allocator = da.allocator();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    std.debug.print("Initializing Tree...\n", .{});
    const bb: f32 = 1;
    const numcards1: usize = 20;
    const numcards2: usize = 20;
    var root_state = GameState.init(.FLOP, true, 100.0, 1000.0, 1000.0);
    var arr = std.ArrayList(Edge).empty;
    defer arr.deinit(temp_allocator);
    try buildTree(&root_state, &arr, arena_allocator, temp_allocator, numcards1, numcards2, bb);
}
