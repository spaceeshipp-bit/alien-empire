# Balance config

Every balance number in the game lives here, never in code. The sim, the server and the tools all read these files, so retuning means editing JSON, not rewriting code.

- `balance/` holds the current config, one file per area.
- `schema/` holds a JSON Schema for each file. Every field has a description; read the schema to learn what a knob does.
- The server will publish versioned snapshots at login (M4). Until then, the client and the tests load a bundle built from these files.

## Units: whole numbers only

The sim never uses floating-point math, so config files never contain decimals. The tools refuse any file with a decimal point. Each field name ends in its unit:

| Suffix | Meaning | Example from the build prompt |
| --- | --- | --- |
| `_x100` | value × 100 | Swarmer HP 40 → `hp_x100: 4000` |
| `_mt` | thousandths of a tile | range 1.8 tiles → `range_mt: 1800` |
| `_mtps` | thousandths of a tile per second | speed 0.7 → `speed_mtps: 700` |
| `_bp` | basis points, 10000 = 100% | Strong 1.5 → `15000`; ignores 75% of armor → `7500` |
| `_ms` | milliseconds, a multiple of 50 (one sim tick) | Reveal lingers 3 s → `linger_ms: 3000` |
| `shots_per_s_x100` | shots per second × 100 | 2.5 shots per second → `250` |

Plain integers without a suffix, such as `armor` or `cost_credits`, are used as written.

## Changing a number

1. Edit the file in `balance/`.
2. Raise `config_version` in `balance/manifest.json` when you publish a change (M4 adds the publish tool).
3. Run `python3 tools/config_tool.py validate`. CI runs the same check and, from M2 on, the balance and fairness simulators.

Changing a field's name or meaning also means raising `schema_version` and updating its schema.

## What's here in M0

M0 covers the combat tables the build prompt specifies: towers, aliens, the counter chart, the damage pipeline constants and status effects. Buildings, raids, the economy and the rest arrive with their milestones. Values the build prompt doesn't give yet, such as slow duration, are left out until the owner sets them (see Open questions in `docs/DECISIONS.md`).
