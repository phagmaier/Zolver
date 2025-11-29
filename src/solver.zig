const std = @import("std");
const GameStateModule = @import("gamestate.zig");
const NodeModule = @import("node.zig");
const Hand = @import("parser.zig").Hand;
const EvaluatorModule = @import("evaluator.zig");
const Evaluator = EvaluatorModule.Evaluator;
const Allocator = std.mem.Allocator;
const Action = GameStateModule.Action;

const CfrContext = struct {
    p1: Action,
    p2: Action,
    hands_p1: []Hand,
    hands_p2: []Hand,
    board: [5]u32,
    boardlen: u8,
    evaluator: *Evaluator,
    utility_scratch: []f32,
};

pub fn card_conflict(hand: Hand, board: []u32) bool {
    for (board) |card| {
        if (hand.c1 == card or hand.c2 == card) {
            return true;
        }
    }
    return false;
}

fn getUtils(allocator: Allocator, context: *CfrContext, pot: f32) ![][]u32 {
    const showDown = (context.p1 != .FOLD and context.p2 != .FOLD);
    var results = try allocator.alloc([]f32, context.hands_p1.len);
    var board: [7]u32 = undefined;
    @memcpy(board, context.board);
    for (0..context.hands_p1.len) |i| {
        if (!card_conflict(context.hands_p1[i], board[0..5])) {
            board[5] = context.hands_p1[i].c1;
            board[6] = context.hands_p1[i].c2;
            const val1 = context.evaluator.handStrength(board);
            results[i] = try _getUtil(allocator, showDown, pot, val1, context.hands_p2, &board, context.evaluator, context.p1);
        }
    }
}

pub fn _getUtil(allocator: Allocator, showDown: bool, pot: f32, val1: f32, p2Hands: []Hand, board: *[]u32, evaluator: *Evaluator, p1Action: Action) ![]f32 {
    var results = try allocator.alloc(f32, p2Hands.len);
    if (showDown) {
        for (p2Hands, 0..p2Hands.len) |hand, i| {
            if (!card_conflict(hand, board[0..5])) {
                board[5] = hand.c1;
                board[6] = hand.c2;
                const val2 = evaluator.handStrength(board);
                results[i] = if (val1 > val2) pot else -pot;
            }
        }
    } else {
        const result: f32 = if (p1Action == .FOLD) -pot else pot;
        for (p2Hands, 0..p2Hands.len) |hand, i| {
            if (!card_conflict(hand, board[0..5])) results[i] = result;
        }
    }
}
