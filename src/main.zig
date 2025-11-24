const std = @import("std");
const builtin = @import("builtin");
const NodeModule = @import("node.zig");
const GameStateModule = @import("gamestate.zig");
const GameState = GameStateModule.GameState;
const Edge = NodeModule.Edge;

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const temp_allocator = if (builtin.mode == .Debug)
        da.allocator()
    else
        std.heap.smp_allocator;

    // Keep your arena usage (unchanged)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    std.debug.print("Initializing Tree...\n", .{});

    var root_state = GameState.init(.FLOP, true, 100.0, 1000.0, 1000.0);

    // Your original ArrayList usage (unchanged)
    var root_list = std.ArrayListUnmanaged(Edge){};
    defer root_list.deinit(temp_allocator);

    try NodeModule.buildTree(&root_state, &root_list, arena_allocator, temp_allocator, 1);

    if (root_list.items.len == 0) {
        std.debug.print("Error: Tree is empty!\n", .{});
        return;
    }
}
