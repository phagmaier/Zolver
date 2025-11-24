pub const Action = enum { FOLD, CHECK, CALL, BET, ALLIN };
pub const Street = enum { FLOP, TURN, RIVER };
pub const BETSIZES: [3]f32 = .{ 0.25, 0.5, 1.0 }; //START WITH JUST THREE ADD MORE LATER
const MAXNUMBETS = 2; //No reraising the reraise can change later

pub const GameState = struct {
    street: Street,
    action: Action,
    bet: f32,
    prevbet: f32,
    isp1: bool,
    pot: f32,
    stack1: f32,
    stack2: f32,
    isTerm: bool,
    showdown: bool,
    numbets: u8,
    streetDone: bool,

    pub fn init(street: Street, action: Action, bet: f32, prevbet: f32, isp1: bool, pot: f32, stack1: f32, stack2: f32, isTerm: bool, numbets: u8, streetDone: bool) GameState {
        return .{
            .street = street,
            .action = action,
            .bet = bet,
            .prevbet = prevbet,
            .isp1 = isp1,
            .pot = pot,
            .stack1 = stack1,
            .stack2 = stack2,
            .isTerm = isTerm,
            .numbets = numbets,
            .streetDone = streetDone,
        };
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

    //If  you can only go all in this will be false or if the number of bets is maxxed out
    //if other player is all in no bet can only call or fold
    pub fn getBetGameState(self: *GameState, bet: f32) ?GameState {}

    pub fn getAllinGameState(self: *GameState) GameState {}

    pub fn getCallGameState(self: *GameState) ?GameState {
        if (self.bet == 0) {
            return null;
        }
        var next = self.*;
        next.action = .CALL;
        const stack = if (self.p1) &next.stack1 else &next.stack2;
        //If bet bigger then stack can't call can only go all in
        if (stack.* <= self.bet) {
            next.pot += stack.*;
            stack.* = 0;
            next.isTerm = true;
            return next;
        }
    }

    //Can't fold if no bet no reason to
    pub fn getFoldGameState(self: *GameState) ?GameState {
        if (self.bet == 0) {
            return null;
        }
        var next = self.*;
        next.action = .FOLD;
        next.isTerm = true;
        return next;
    }

    //for now ignore initial
    //we make start nodes manually
    pub fn getCheckGameState(self: *GameState) ?GameState {
        //parent node could have called
        if (self.numbets > 0 and !self.streetDone) return null;
        var new = self.*;
        new.action = .CHECK;
        if (self.streetDone) {
            new.isp1 = true;
            new.nextStreet();
        } else {
            new.isp1 = false;
            new.streetDone = true;
            if (new.street == .RIVER) {
                new.isTerm = true;
            }
        }
        return new;
    }
};
