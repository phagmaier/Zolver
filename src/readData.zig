const std = @import("std");
const builtin = @import("builtin");
const Card = @import("card.zig");

//FILE FORMAT:

//NOTES:
//Order agnostic identifies everything based on [label]
//P1 == Firt to act
//P2 == SECOND TO ACT
//S == suited A == ALL
//For Pairs don't include
//Cards are formated as rank1 rank2 (T == 10)
//[PTA] == PLAYER TO ACT

//[p1 hands]
//reads everything in here until we get to [/p2 hands]
//[/p1 hands]

//[p2 hands]
////reads everything in here until we get to [/p2 hands]
//[/p2 hands]

//[PTA] playerToAct (p1 or p2)
//[STREET] WHAT STREET ARE YOU CURRENTLY ON
//[PREV ACTION] NONE if start of the street else BET, CHECK, ALL IN (can't do call or check check because then we are just on a new street)
//[BET] PREV BET SIZE
//[STACK1] player 1's stack (in BB's)
//[STACK2] Player 2's Stack in BB's
//[POT] current pot size
//[BB SIZE] size of the big blind (minimum bet size)

const Hand = struct {
    c1: u32,
    c2: u32,
    pub fn init(c1: u32, c2: u32) Hand {
        return .{ .c1 = c1, .c2 = c2 };
    }
};
pub const FileData = struct {
    isp1: bool, //Which player is acting first
    p1hands: []Hand,
    p2hands: []Hand,
    stack1: f32,
    stack2: f32,
    pot: f32,
    bb: f32,
    street: u8,
    pub fn init(isp1: bool, p1hands: []Hand, p2hands: []Hand, stack1: f32, stack2: f32, pot: f32, bb: f32, street: u8) FileData {
        return .{ .isp1 = isp1, .p1hands = p1hands, .p2hands = p2hands, .stack1 = stack1, .stack2 = stack2, .pot = pot, .bb = bb, .street = street };
    }
};

fn skipLeadingWhiteSpace(buffer: []u8) []u8 {
    var scaler: usize = 0;
    for (buffer) |char| {
        if (std.ascii.isWhitespace(char)) {
            scaler += 1;
        } else {
            break;
        }
    }
    return buffer[scaler..];
}
fn parse(slice: *[]u8) !FileData {
    while (slice.len) {}
}

pub fn readfile(allocator: std.mem.Allocator) !FileData {
    const file = try std.fs.cwd().openFile("../Data/data.txt", .{}) catch |err| {
        std.debug.print("Expected A ../Data/data.txt file. This is where the hand data is stored\n", .{});
        return err;
    };

    //Set this when complete

    defer file.close();

    // Let Zig handle the dynamic allocation!
    const max_size = 1024 * 1024 * 1024; // 1GB limit
    const contents = try file.readToEndAlloc(allocator, max_size);
    var slice = contents[0..];

    defer allocator.free(contents);
}

test "Get Player Data" {
    var da = std.heap.DebugAllocator(.{}){};
    defer _ = da.deinit();
    const temp_allocator = da.allocator();

    // Keep your arena usage (unchanged)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
}
