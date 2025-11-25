# State File Spec

```ini
[game]
pta = p1
street = flop
prev_action = bet
bet = 3.5
stack1 = 97.5
stack2 = 100
pot = 7
bb = 1

[board]
Ah Kd 7c

[p1_range]
AKs AQs+ 77+ KK
AJo ATo+

[p2_range]
AA KK QQ JJ TT 99+
AKs AQs AJs
```

## Parsing Rules

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


## TO-DO
Add/write a quick little function that the user can call and it will make a default example in this format
