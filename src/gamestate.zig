const std = @import("std");
pub const Action = enum { FOLD, CHECK, CALL, BET, ALLIN };
pub const Street = enum { FLOP, TURN, RIVER };
pub const BETSIZES: [3]f32 = .{ 0.25, 0.5, 1.0 }; //START WITH JUST THREE ADD MORE LATER
const MAXNUMBETS = 2; //No reraising the reraise can change later
const print = std.debug.print("std");

pub const GameState = struct {
    street: Street,
    action: Action,
    bet: f32,
    isp1: bool,
    pot: f32,
    stack1: f32,
    stack2: f32,
    isTerm: bool,
    numbets: u8,

    pub fn init(street: Street, action: Action, bet: f32, isp1: bool, pot: f32, stack1: f32, stack2: f32, isTerm: bool, numbets: u8) GameState {
        return .{
            .street = street,
            .action = action,
            .bet = bet,
            .isp1 = isp1,
            .pot = pot,
            .stack1 = stack1,
            .stack2 = stack2,
            .isTerm = isTerm,
            .numbets = numbets,
        };
    }
    pub fn printState(self: *GameState) void {
        print("Street: {any}, Action: {any}, Bet: {d}, PLAYER1?: {any}, POT: {d}, STACK1: {d}, STACK2: {d} TERM?: {any}, NUMBETS:{d}\n", .{ self.street, self.action, self.bet, self.isp1, self.pot, self.stack1, self.stack2, self.isTerm, self.numbets });
    }
    //these are called on current game state to get next game state
    fn updateBet(self: *GameState, bet: f32, player1: bool) void {
        self.pot += bet;
        if (player1) self.stack1 -= bet;
        if (!player1) self.stack2 -= bet;
    }

    inline fn nextStreet(self: *GameState) void {
        switch (self.street) {
            .FLOP => self.street = .TURN,
            else => self.street = .RIVER,
        }
    }

    inline fn nextPlayer(self: *GameState) bool {
        return switch (self.action) {
            .CHECK => !self.isp1,
            .BET => !self.isp1,
            .ALLIN => !self.isp1,
            .CALL => true,
            else => unreachable,
        };
    }

    pub fn getFoldGameState(self: *GameState) ?GameState {
        if (self.numbets == 0) return null;
        var new = self.*;
        new.isp1 = self.nextPlayer();
        new.action = .FOLD;
        new.bet = 0;
        new.isTerm = true;
        new.numbets = 0;
        return new;
    }

    pub fn getCheckGameState(self: *GameState) ?GameState {
        if (self.numbets > 0) return null;
        var new = self.*;
        self.isp1 = self.nextPlayer();
        new.action = .CHECK;
        new.numbets = 0;
        new.bet = 0;
        if (!new.isp1 and self.street == .RIVER) new.isTerm = true;
        if (new.isp1) new.nextStreet();
        return new;
    }

    pub fn getBetGameState(self: *GameState, bet: f32) ?GameState {
        //if bet would make you or other player go all in then it's just considered an all in
        if (self.numbets >= 2 or self.action == .ALLIN or self.stack1 <= bet or self.stack2 <= bet) return null;
        var new = self.*;
        new.isp1 = self.nextPlayer();
        new.action = .BET;
        new.numbets += 1;
        new.bet = bet;
        new.pot += bet;
        if (new.isp1) new.stack1 -= bet;
        if (!new.isp1) new.stack2 -= bet;
        return new;
    }

    pub fn getAllInGameState(self: *GameState) ?GameState {
        if (self.action == .ALLIN) return null;
        var new = self.*;
        new.isp1 = self.nextPlayer();
        new.numbets += 1;
        new.bet = @min(new.stack1, new.stack2);
        new.pot += new.bet;
        if (new.isp1) new.stack1 -= new.bet;
        if (!new.isp1) new.stack2 -= new.bet;
        return new;
    }

    pub fn getCallGameState(self: *GameState) ?GameState {
        if (self.numbets == 0) return null;
        var new = self.*;
        new.isp1 = self.nextPlayer();
        new.pot += self.bet;
        if (new.isp1) new.stack1 -= new.bet;
        if (!new.isp1) new.stack2 -= new.bet;
        new.numbets = 0;
        if (self.street == .RIVER) new.isTerm = true;
        new.sreet = self.nextStreet();
        return new;
    }
};
