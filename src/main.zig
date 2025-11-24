const std = @import("std");
const NodeModule = @import("node.zig");
const GameStateModule = @import("gamestate.zig");

const GameState = GameStateModule.GameState;
const Edge = NodeModule.Edge;

fn writeIndent(writer: anytype, n: usize) !void {
    // small stack buffer for indentation (max 64 spaces)
    var indent_buf: [64]u8 = undefined;
    const cap = if (n <= indent_buf.len) n else indent_buf.len;
    for (indent_buf[0..cap]) |*b| b.* = ' ';
    try writer.writeAll(indent_buf[0..cap]);
}

/// Writes a single Edge as a JSON object (pretty-printed).
/// - writer: the std.io.Writer interface (use `&file_writer.interface`)
/// - edge: the edge to serialize
/// - indent: current indentation (spaces)
fn writeEdgeJson(writer: anytype, edge: Edge, indent: usize) !void {
    // Opening
    try writeIndent(writer, indent);
    try writer.writeAll("{\n");

    // "action": "..."
    try writeIndent(writer, indent + 2);
    try writer.writeAll("\"action\": \"");
    // assume @tagName(edge.action) -> []const u8; if not, convert appropriately
    try writer.writeAll(@tagName(edge.action));
    try writer.writeAll("\",\n");

    // "amount": <float with 2 decimals>
    // Format float into a small stack buffer to ensure reproducible formatting across std versions.
    var amt_buf: [32]u8 = undefined;
    const amt_slice = try std.fmt.bufPrint(&amt_buf, "{:.2}", .{edge.amount});
    try writeIndent(writer, indent + 2);
    try writer.writeAll("\"amount\": ");
    try writer.writeAll(amt_slice);
    try writer.writeAll(",\n");

    // children
    if (edge.child) |node| {
        try writeIndent(writer, indent + 2);
        try writer.writeAll("\"children\": [\n");

        for (node.edges, 0..) |child_edge, i| {
            // recurse
            try writeEdgeJson(writer, child_edge, indent + 4);
            if (i < node.edges.len - 1) {
                try writer.writeAll(",\n");
            } else {
                try writer.writeAll("\n");
            }
        }

        try writeIndent(writer, indent + 2);
        try writer.writeAll("]\n");
    } else {
        try writeIndent(writer, indent + 2);
        try writer.writeAll("\"children\": null\n");
    }

    // Closing
    try writeIndent(writer, indent);
    try writer.writeAll("}");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const temp_allocator = gpa.allocator();

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

    const root_edge = root_list.items[0];
    const child_count = if (root_edge.child) |n| n.edges.len else 0;
    std.debug.print("Tree Built. Root Children: {d}\n", .{child_count});

    // Create the file and writer using the 0.15.2 pattern you showed
    const cwd = std.fs.cwd();
    const file = try cwd.createFile("tree_output.json", .{ .truncate = true, .read = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface; // this is the std.io.Writer interface you use with print/writeAll/flush

    // If you want the root to be an array of edges, write "[" then each element.
    // Here we write the single root object (no surrounding array).
    try writeEdgeJson(writer, root_edge, 0);
    try writer.flush(); // must flush before closing

    std.debug.print("Tree dumped to tree_output.json\n", .{});
}
