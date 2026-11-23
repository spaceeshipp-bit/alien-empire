# Design review

Written 2026-11-23 for the owner's request: review prior decisions, make the game fun and engaging, make base building feel special, and add mini-games inside the base.

Every battle number below was measured with the reference model (`tools/reference/sim_model.py`) on config changed in memory. No code, config or existing doc was edited. "Owner" in a row means the change alters the build prompt, so it needs the owner's approval.

## 1. Prior decisions

Most decisions are engineering calls (D-001 to D-030) and are right: keep them. The C++ sim (D-026) and the reference model (D-028) are what make replays, bots and mini-games cheap later. The ones that affect fun:

| Decision | Verdict | Better alternative | Approval |
| --- | --- | --- | --- |
| M1-C: the pressure tool picks the credits | Change | It can't: no credits fit these waves. Set the waves and credits from playthroughs (section 2). | No |
| M1-F: how wave pressure is read | Change | The reading overstates what credits can buy by 1.3 to 3 times. Measure it in the sim (section 2). | Owner, if the done-when wording changes |
| D-034: every tower targets First | Change | A Railgun shoots Swarmers while the Brute walks past. Give each tower a default rule in config: Railgun Strongest, the others First. | Owner (the prompt names First as the default) |
| M1-E: waves on a timer only | Change | First wave starts on a tap. Add "send next wave" and a 2× speed button (section 2). | Bonus credits: owner. The rest: no |
| Map default: 18 build tiles | Change | The stage pays for about 12 towers, so tiles never run out and upgrades (worse per credit by design) are never the right choice. Use 12 or 13 tiles, 3 or 4 of them clearly best. | No |
| Map default: lanes one tile from each pad | Change | Add one hairpin pocket per lane, 2 tiles wide, with a pad that sees 5 or more lane tiles. It gives the Plasma Torch a home. | No |
| M1-A: Pulse, Torch, Railgun against Swarmer, Brute, Skimmer | Keep | It teaches "counter" and "can't hit" in one map. | — |
| Q2: 20 lives, Brute leak 3 | Keep | Three stars at 18 or more lives, two at 10, one for a clear. | No |
| Q3: no spawn jitter | Keep in the sim | Add a small sideways offset in the view only, so streams don't look like a conveyor belt. | No |
| D-015: range +5% of base, refund 70% of all spent | Keep | Add a placement ghost with a confirm tap, so a mis-tap never costs 30%. | No |
| Hits land on the firing tick; D-031, D-032 art and colors | Keep | — | — |
| D-033: M1 before the M0 phone check | Keep | The 60 fps check is still the biggest unknown; get the performance screen onto a phone soon. | — |

Three things in the build prompt itself hurt the feel. They are the owner's numbers, so they are flagged, not changed:

- **Time on target is too short.** A Swarmer moves 2.0 tiles a second. The Plasma Torch, the swarm counter, has it in range for at most 1.8 seconds and deals at most 34 damage to its 40 HP. Alone, it can never kill one. On this map it deals 28. Measured: one Torch on the best tile kills 0 of 8 Swarmers; one Pulse Turret kills 2 of 8.
- **Kills are the only income.** A leak means less money, then more leaks. Easing waves 1 to 3 in a test made the stage harder at wave 8, because income fell with the kill count.
- **HP ×1.09 a wave crosses shot counts in jumps.** A 40 HP Swarmer takes 4 Pulse shots; wave 2's 43.6 HP takes 5, a 25% step.

## 2. M1 stage: fun and balance

### What the measurements say

- **The current stage can't be won at any spend it allows.** With the whole 10-tower reference layout built before wave 1 (1,500 credits; the stage pays 929 before the last wave), it still loses, in wave 9. It clears only with every tower at level 4, which is 7,200 credits.
- **`--tune` finds nothing because the waves pull both ways.** Waves 1 to 3 need credits to double across 14 kills. Wave 10 then needs less than that growth gives.
- **The tool's ratio is far kinder than the sim.** With the recommended list below:

| Waves | Tool ratio | What the sim did |
| --- | --- | --- |
| 1 to 3, Swarmer streams | 0.44 to 0.51 | No leaks; the layout fails if HP rises 1.3 to 1.75 times |
| 4 to 7, mixed | 0.40 to 0.54 | No leaks; in waves 6 and 7 only because the bot buys mid-wave |
| 10, as recommended | 0.59 | 7 lives lost; the stage clears with 10 of 20 |
| 10, enlarged to the target | 0.80 to 0.82 | The bot lost all 12 to 17 lives it had left and killed at most a third of the wave |

So **0.4 to 0.6 on early waves is reachable. 0.8 to 1.0 on the last wave is not**: the ceiling a paid-for layout survives is about 0.6.

Why the reading is kind:

1. It counts the kill zone as every tile any tower covers. A tower only fires across its own stretch.
2. It spends every credit at the best rate. Real purchases are lumpy and sit unspent.
3. First targeting spreads damage over aliens that escape with a sliver of HP.
4. It ignores splash, which is the one thing that helps late.

### How to read the metric

Keep the build prompt's formula and bands. Measure "what the credits can buy" in the sim instead of on paper:

- **Sim pressure** = 1 ÷ the largest HP multiplier at which the reference layout, bought with the credits banked at the wave's start, still kills the wave with no leak. 0.5 means your money could kill the wave twice; 1.0 means exactly once. A 9-step search takes under a second a wave in the Python model.
- **Two bot gates**, which are the real test:
  - the reference bot clears with 10 to 16 of 20 lives;
  - a Pulse-only bot loses.

Sim pressure is strict: it ignores towers bought mid-wave, so it reads 1.2 to 1.4 on waves the bot clears cleanly. Either count half the wave's own kill credits, or accept 1.0 to 1.3 on the last wave. The owner should approve whichever wording replaces "wave pressure is within target".

### Numbers to try

Checked: the reference bot clears in 396 seconds with 10 of 20 lives, 12 towers and 2 upgrades. It leaks nothing through wave 7, 3 in wave 8 and 3 in wave 10. The Pulse-only bot loses to the Brutes. The tool passes waves 1 to 3 (0.44, 0.47, 0.51) and reads 0.59 on wave 10.

- **Starting credits:** 300 (three Pulse Turrets, or a Railgun and a Pulse).
- **Kill credits:** Swarmer 4, Skimmer 10, Brute 30. With the current 3, 8 and 25 the same list loses at wave 6.
- **Unchanged:** 20 lives, HP ×1.09 and kill credits ×1.03 a wave, every tower and alien stat.
- **Income:** 1,588 credits banked by wave 10; 294 aliens in all.
- **Reference layout, in buying order:** Pulse (4,4), (4,7), (4,10), (3,13); Railgun (2,8); Torch (2,5), (6,6); Railgun (6,9); Torch (2,11), (6,12); Pulse (5,13), (4,1).

| Wave | Starts | Groups (count, lane, delay into the wave, spacing) |
| --- | --- | --- |
| 1 | 10 s | 18 Swarmers west, every 1.2 s |
| 2 | 46 s | 22 Swarmers east, every 1.0 s |
| 3 | 82 s | 14 Swarmers west, every 1.6 s; 14 east, +0.8 s, every 1.6 s |
| 4 | 118 s | 5 Skimmers west, every 4 s; 14 Swarmers east, +6 s, every 1.2 s |
| 5 | 154 s | 20 Swarmers east, every 1.0 s; 1 Brute west, +18 s |
| 6 | 190 s | 20 Swarmers west, every 0.5 s; 20 east, +11 s, every 0.5 s |
| 7 | 226 s | 6 Skimmers west, every 3 s; 16 Swarmers west, +2 s, every 1.2 s; 2 Brutes east, +12 s, every 10 s |
| 8 | 262 s | 16 Swarmers west, every 1.0 s; 16 east, +9 s, every 1.0 s; 3 Skimmers east, +4 s, every 5 s |
| 9 | 298 s | 18 Swarmers east, every 1.0 s; 1 Brute west, +8 s; 1 Brute east, +16 s |
| 10 | 334 s | 30 Swarmers west, every 1.1 s; 30 east, +0.55 s, every 1.1 s; 5 Skimmers east, +3 s, every 6 s; 1 Brute west, +20 s; 1 Brute east, +28 s |

The rules behind the list, for any retune:

- **Streams, not bursts.** Each wave spawns over 17 to 33 seconds. Long streams keep towers firing, and they are the only shape where the paper ratio is close to the sim.
- **Brutes close a wave.** A Brute that enters first is overtaken by Swarmers, and every Railgun turns to them. A wave-5 Brute needs 10 Railgun shots, about 20 seconds of one gun.
- **Skimmers arrive before the ground group**, so the four center Pulse Turrets aren't busy.
- **Income is fragile.** Re-run the bots after any change to a count.

### Tower feel

- **Pulse Turret:** fine as the opener. Show HP bars, so a half-killed Swarmer reads as progress.
- **Plasma Torch:** weak until two overlap. Give it the hairpin pads, and draw a lingering burn so the player sees what it did.
- **Railgun:** the most satisfying shot in the stage when it hits a Brute, and wasted when it doesn't. Default it to Strongest.
- **Upgrades:** currently a trap. Fewer pads fix this without touching the prompt's costs.

### Feel features for M1

| Feature | Add now? | Note |
| --- | --- | --- |
| First wave starts on a tap | Yes | Lets a new player read the map. Client only. |
| 2× speed | Yes | The stage runs 6.6 minutes. Client only: two sim ticks a step. |
| Next-wave strip: class icons of what's coming, with a warning when nothing you own can hit it | Yes | Turns the counter chart into a decision before the wave. |
| Placement ghost with range ring and lit lane tiles | Yes | The clearest fix for bad placement. |
| Credit pops, kill pops, Core flash and haptic on a leak, a heavier one for a Brute | Yes | Cheap, code-drawn. |
| End screen: stars, kills per tower, a "best tower" line | Yes | Gives a reason to replay. |
| Send next wave early, paying 1 credit per second skipped, at most 15 | Yes, if the owner agrees | A new sim command and a new credit source. |
| Credits for clearing a wave | Not yet | Steadies income, but the prompt says credits come from kills. Test in M2's simulator. Owner. |
| Interest on unspent credits | No | Rewards hoarding and punishes new players. |

## 3. Base building that feels special

The principle: **the colony shows your history, and everything that delights is cosmetic or already budgeted.** Nothing below adds combat stats, paid speed or client-side authority.

**Progression you can see**

- Each building has four looks (levels 1, 5, 10, 15), built from code-drawn parts as in `docs/ART.md`: more tanks, antennas, brighter glow.
- The Nexus has named eras every five levels. Reaching one plays a 5-second ignition: lights spread along the roads and the ground tiles change.
- The two builders are visible drones. They fly to the site, raise scaffolding in three stages, and the player taps the last bolt to finish.
- Stock is visible: the Warehouse yard fills and empties with the wallet, so a full store looks rich and a raid visibly takes something.

**Moments of delight**

- **Raid scars.** After a raid, scorch marks stay where the attackers broke through. One free tap repairs each, then the replay and the revenge button are offered. Returning to a raided base becomes a ritual, not just a loss report.
- **Highlight reel.** After each 8-hour invasion, the game replays the ten seconds where your layout did the most damage. The deterministic sim makes this free.
- **Survey finds.** Clearing rubble plots as the Nexus grows turns up codex entries and decorations, never resources.

**Collection and identity**

- Colony name, emblem and base theme, shown on the sector map and in replays.
- Monuments from achievements: decorations with no stats, placed freely.
- A colony log written by the game: "Day 3: held the first raid."
- Named layouts with a defense record. An overrun moves the colony but keeps all of this, plus a "Rebuilt" ribbon.

**Layout editor that teaches**

- A coverage overlay: which lane tiles each tower reaches, and where the last five raids broke through.
- "Test my layout": a free practice wave against the base, for mastery XP only.

**Onboarding**

- The first ten minutes: the Nexus drops from orbit, the player places one Extractor and one tower, and a small wave tests it at once.
- The first five upgrades take under a minute each.
- A "next best step" chip whenever a builder is idle, and an always-visible track of the next unlock.

Owner approval is needed only for land plots, if they change where buildings may go.

## 4. Mini-games inside the base

Rules for all of them, to keep the fairness caps intact:

- The server issues the seed; the client sends its input log; the sim worker replays it. No score is trusted from the phone.
- They mint no new resources. They pay mastery XP, cosmetics or information, or they are the way an already-budgeted reward is collected.
- One scored run a day each, unlimited retries, never sold and never skipped with Gems.

| Rank | Mini-game | Where | What you do | Reuses the battle sim? | Reward | Effort | Fits |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | **Red Team** | Barracks | Attack your own active layout with a fixed small army. Then change the layout and replay your old attack against it: if it now fails, the fix is proven. | Yes, the raid sim, and the replay is free | Mastery XP; a badge per patched breach | Small, after the raid prototype | M3 local, M5 online |
| 2 | **Par Drills** | Foundry | A fixed alien pack on your own lanes and a credit budget. Hold with no leaks using the fewest credits; each drill has a par. | Yes, the PvE sim | Tower mastery XP; counts toward daily tasks | Small | M2 or M3 |
| 3 | **Hive Signal** | Research Lab | Match a pulse pattern to decode part of the next invasion: which classes, which lane. | No; the forecast comes from the invasion's server seed | Information only, so you can adjust the layout | Small | M4 |
| 4 | **Specimen Bench** | Research Lab | The xenobiologist shows a silhouette or glow; pick the tower that counters it, against a clock. | No; answers come from the counter config | Codex entries, a title | Small | M3 as teaching, M8 with the codex |
| 5 | **Salvage Sweep** | Warehouse | After an invasion, draw one fuel-limited route for a hauler through the wreckage. | No; a small integer scoring rule in the sim library | Scrap, spent only on decorations | Medium | M8 |

Red Team ranks first because it makes the layout editor a game of its own. Mini-games are new scope, so all five need the owner's approval.

## 5. Top 10 recommendations

| # | Recommendation | When | Owner approval |
| --- | --- | --- | --- |
| 1 | Replace the wave list and credits with section 2's numbers | Now (M1) | No |
| 2 | Judge wave pressure with sim pressure and the two bot gates | Now (M1) | Yes, for the done-when wording |
| 3 | Brutes close waves; Railgun defaults to Strongest | Now (M1) | Yes, for the default |
| 4 | Start on a tap, 2× speed, next-wave strip, placement ghost | Now (M1) | No |
| 5 | Cut to 12 or 13 pads and add a hairpin pocket per lane | Now (M1) | No |
| 6 | Send next wave early for a small bonus | Now (M1) | Yes |
| 7 | Hit feedback, stars and a per-tower end screen | Now (M1) | No |
| 8 | After the playtest, decide Torch range or alien speed; test credits for clearing a wave | Soon (M2) | Yes |
| 9 | Visible colony growth, builder drones, raid scars, colony log, coverage overlay | Soon (M3) | No |
| 10 | Red Team and Par Drills in M3; the other three mini-games later | Soon, then later | Yes |
