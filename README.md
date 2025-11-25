# ZOLVER

A work in progress poker solver written in zig

---

##Updates

1. Finished  hand evaluator 
2. Implement logic to build [Game Tree](src/gamestate.zig) recursively
3. Finished Building the [Game Tree Nodes](src/node.zig)
4. Can [parse](src/parser.zig) file of current state/range to solve from [for more details see here](#Parsing-Rules)

---

## Setting up your data file

In order to for the solver to work you must give it the current state from which to solve from. This includes things like Big Bling size, stack sizes, current street, last action, etc...


| Element | Rule |
|---------|------|
| `[section]` | Must be alone on its line |
| Key-value pairs | One per line, `key = value` (spaces around `=` optional) |
| Board cards | Whitespace-separated, can span multiple lines |
| Range hands | Whitespace-separated, can span multiple lines |
| Case | Everything case-insensitive |
| Empty lines | Ignored everywhere |


## Hand Notation


| Pattern | Meaning |
|---------|---------|
| `AKs` | Suited only (4 combos) |
| `AKo` | Offsuit only (12 combos) |
| `AK` | All combos (16 combos) - same as omitting suffix |
| `KK` | Pair (6 combos) |
| `77+` | All pairs 77 and above |
| `A5s+` | A5s through AKs (kicker goes up) |
| `A5o+` | A5o through AKo |
| `A5+` | All A5 through AK combos |


---

## To-Do List

- [ ] On startup return and print message if no file exists of game state (see here)[#Setting-up-your-data-file]
- [ ] Create a way to get a default file with examples if asked for or if no file
- [ ] *FIX GAMESTATE SO THAT IT TAKES IN THE BB TO GUARANTEE BET SIZE IS AT LEAST MIN2*
- [ ] Take file date and convert it to a state and then pass to make trees (don't forget to pass bb as well)
- [ ] make threadpool to run tree in parallel (start with very small state maybe even only 1 bet size)
- [ ] take Kuhn poker logic and transfer that over and make it work with dynamic sized arrays (remeber arrays are 1D but treating them as 2)
- [ ] write it single thread at first make sure logic checks out (small number of hands small number of bet sizes)
- [ ] write function to go through complete solve 2 hands competing
- [ ]
- [ ] once logic is done we thread it and optimize
---
