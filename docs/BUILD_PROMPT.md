# Build prompt: Alien Empire Tower Defense

Copied on 2026-11-08 from the owner's doc "Build Prompt: Alien Empire Tower Defense" (revision 180, dated 2026-11-07): https://claude.ai/artifact/6b2Lg4ftqEJgGGAWeVz7TD

The doc is the source of truth. When it changes, update this copy in the same commit and log the change in `docs/DECISIONS.md`.

## Role and mission

You are the lead engineer and systems designer for a fair-to-play alien tower defense game for Android. You will build it milestone by milestone with the owner, who makes the design calls and playtests every build.

Build a playable, server-backed game that ships on Google Play. Prefer simple, testable systems over clever ones. When a choice changes the game's feel, economy or fairness, propose options and wait for the owner.

Everything you make must be original. Never copy code, art, names, text or balance data from any existing game.

## The game in one page

Players run a human colony on an alien world. They defend it with towers against alien swarms and raid other players' colonies, and spending buys at most a small, capped head start.

- **Defend (PvE):** Alien waves attack your colony along fixed lanes. Your permanent towers fight, and during a wave you can drop temporary field towers with battle credits.
- **Raid (async PvP):** Raid any colony on your server as often as your army allows. Its towers and garrison defend on their own, so the owner never needs to be online. Drain what its Warehouse doesn't secure, or overrun it and send it fleeing across the map.
- **Grow (empire):** Gather Alloy, Energy and Xenite, upgrade buildings, research technology, recruit commanders and unlock new tower and unit types.
- **Explore (sector map):** Each server has a shared map of points of interest: alien nests, roaming monsters, resource deposits, relic sites and event anomalies. Players and clans compete for them asynchronously.
- **Belong (social):** Clans (alliances) with chat, clan tasks, help, co-op alien bosses, weekly clan wars and an event calendar that's always full.
- **Story:** A campaign told in acts, with a new chapter every 60 to 90 days. Each chapter introduces a new alien, tower or unit.

Sessions work at any length. A 5-minute check-in collects, upgrades and plays one battle; a 12-hour day never runs out of meaningful goals (see Engagement).

The setting is original sci-fi. The enemy is a hive species: Swarmers, Carapace Brutes, Shield Drones, Skimmers, Phasers and Hive Carriers. Every name here is a working name the owner can change.

## Design pillars

Seven rules override everything else. If a feature breaks one, cut or change the feature.

1. **Mostly fair to play.** Spending buys a small, capped head start (resources, limited speed-ups, shields, a season pass billed weekly), never raid dominance. A max spender progresses at most 15% faster than an engaged free player and can never buy stat boosts.
2. **Compressed power.** Progression adds options (new towers, units, abilities, layouts) more than bigger numbers. A base 3 levels higher is stronger, never immune.
3. **Underdogs can hurt giants.** A well-played raid from 3 levels below should still breach a stronger base. Punching up pays more; punching down pays less.
4. **War with consequences, not bullying.** Anyone can be raided again and again until their colony is overrun and teleported. Farming far weaker players pays little, new players are protected, and every victim gets real tools for revenge.
5. **Never run out of things to do.** Someone playing 12 hours a day, every day, always has a meaningful next goal. Rewards taper after daily caps, but play never dead-ends.
6. **The server is the authority.** The phone only displays and sends input. The server decides or verifies every resource change, timer, raid result and reward.
7. **Original content.** Every name, image, sound, text and number is made for this game. Genre conventions are fine; copying another game is not.

## Tech stack and architecture

Godot 4 runs the game on the phone, Nakama runs the backend, and a headless copy of the game's own simulation re-checks every battle on the server.

_(The source doc has an architecture diagram here: phone, backend, sim worker, database and remote config.)_

The phone and the sim worker run the same sim core, so a replayed battle gives the identical result; any mismatch means tampering.

- **Client:** Godot 4 (latest stable), GDScript, exported as an Android App Bundle. It handles rendering, input, UI and sound. Play Billing, ads, push notifications, Google sign-in and Play Integrity come from Godot plugins, so each one gets tested on a real phone in M0.
- **Sim core:** pure GDScript battle logic with no engine physics, no rendering and no floating-point math. The same files run on the phone and on the server.
- **Backend:** Nakama (open source) with PostgreSQL. Use its built-in accounts, storage, groups for clans, chat, leaderboards, tournaments, notifications and purchase validation. Write game logic as Nakama server modules in TypeScript or Go.
- **Sim worker:** Godot running headless on the server. It takes a battle (seed, layout snapshot, command log), replays it with the sim core and returns the result to Nakama.
- **Remote config:** every balance number lives in versioned JSON files that Nakama serves at login. The client never hard-codes balance. A battle always runs on the config version it started with, even if a new one is published mid-battle.
- **Hosting:** start with Docker Compose on one small cloud server running Nakama, PostgreSQL and the sim worker. Back up the database daily to separate storage. Scale out only when load requires it.
- **Repo layout:** `client/` (Godot project), `sim/` (shared sim core, copied into client and worker at build time), `server/` (Nakama modules), `config/` (balance JSON plus schema), `tools/` (balance and fairness simulators), `docs/`.

Rules:

- Content is data. Towers, units, aliens, buildings, research, commanders and waves are config entries checked against a JSON schema, never code.
- The sim core is the only battle logic. Never re-implement combat in TypeScript or Go.
- Every battle record stores its sim version and config version. The server keeps every sim version still in use and forces a client update when one retires.

## Combat simulation

One deterministic simulation runs every battle, so the same inputs give the same result on any phone and on the server.

Determinism rules:

- Fixed tick of 20 per second. PvE battles end when the waves end; raids end at 180 seconds or when the Core falls.
- Integer math only. Store HP and damage ×100, positions in thousandths of a tile, percentages in basis points. No floats inside the sim.
- A small seeded random generator (xorshift or PCG) written inside the sim. Never use engine random functions. The server issues each battle's seed.
- Update entities in ascending ID order and break every targeting tie by ID.
- No engine physics or navigation. Lanes are precomputed waypoint lists saved with the layout.
- Golden tests: recorded battles whose final state hash must match exactly on desktop, on an Android build and on the sim worker.
- **Speed:** a full 180-second raid replays in under 100 ms on one server core. Towers find targets through a spatial grid and re-pick targets every few ticks, not every tick.

Damage pipeline, always in this order (every value comes from config):

1. Start from the tower's or unit's damage at its tier and level.
2. Add the bonus pool (research, commanders, buildings), passed through the soft cap described under Progression.
3. Multiply by the counter: Strong 1.5, Neutral 1.0, Weak 0.5, Can't hit 0.
4. In raids only, apply the raid modifiers (underdog, revenge, dig-in) from the modifier table in PvP raids.
5. Shields take damage first: EMP ×3.0, Thermal ×0.5, everything else ×1.0.
6. Then hull: armor reduction = armor ÷ (armor + 100). Piercing ignores 75% of armor.
7. Floors: total reduction from armor and resist effects never exceeds 60%, and every hit deals at least 1 point.

Status effects:

- **Slow:** stacks from all sources to a 40% maximum.
- **Reveal:** a cloaked target stays targetable for 3 seconds after leaving a Sensor's range.
- **Mark:** +10% damage taken; does not stack.
- **Stun:** Titans and raid commanders are immune.
- **Shield regen:** 15 per second after 3 seconds without taking damage.

Targeting rule per tower, chosen by the owner of the layout: First (closest to the Core, default), Strongest, Weakest or Fastest.

Raids also simulate units fighting units. Garrison and attacking units target the nearest enemy unit in range first, then towers, walls and finally the Core. Each fight's casualties feed the hospital rules in PvP raids.

## Towers, aliens and raid units

Every tower counters specific enemy classes, and aliens (PvE) and raid units (PvP) share the same six classes. One counter chart governs both modes.

| Tower | Role | Swarm | Armored | Shielded | Air | Cloaked | Titan |
|---|---|---|---|---|---|---|---|
| Pulse Turret | Generalist, ground and air | Neutral | Weak | Neutral | Neutral | Neutral* | Neutral |
| Plasma Torch | Short-range splash | Strong | Weak | Neutral, half vs shields | Can't hit | Hits unrevealed at 50% | Neutral |
| Railgun | Long range, pierces armor | Weak | Strong | Neutral | Can't hit | Neutral* | Strong |
| Ion Disruptor | EMP, slows 20% | Weak | Weak | Strong, ×3 vs shields | Neutral | Neutral* | Neutral |
| Flak Battery | Anti-air splash | Can't hit | Can't hit | Can't hit | Strong | Can't hit | Can't hit |
| Sensor Beacon | Reveals cloaked, marks +10% | — | — | — | — | Reveals | — |

*Needs a Sensor Beacon in range to target Cloaked enemies.

Starting tower stats (tier 1, level 1):

| Tower | Cost (credits) | Damage | Shots per second | Range (tiles) | Splash (tiles) |
|---|---|---|---|---|---|
| Pulse Turret | 100 | 10 | 2.0 | 3.0 | — |
| Plasma Torch | 150 | 5 | 2.5 | 1.8 | 1.0 |
| Railgun | 200 | 50 | 0.5 | 5.0 | — |
| Ion Disruptor | 150 | 10 | 1.6 | 3.0 | — |
| Flak Battery | 150 | 12 | 1.2 | 3.5 | 0.8 |
| Sensor Beacon | 125 | — | — | 3.0 | — |

I ran these numbers: each tower's best matchup scores about 22 to 29 points of range-adjusted damage per 100 credits, while the Pulse Turret scores 15 to 20 against most classes. That gap is the reason to build counters. The balance simulator replaces this hand math in M2.

Field tower upgrades (PvE battles): 4 levels. Upgrade cost = 0.8 × build cost × 1.5 per level after the first; damage ×1.45 and range +5% per level; selling refunds 70%. Upgrading is worse per credit than building new (a level 4 Pulse Turret drops from 20 to 12.7 damage per second per 100 credits) but saves space.

| Alien | Class | HP | Armor | Shield | Speed (tiles/s) | Notes |
|---|---|---|---|---|---|---|
| Swarmer | Swarm | 40 | 0 | 0 | 2.0 | Packs of 8 to 30 |
| Carapace Brute | Armored | 360 | 150 | 0 | 0.7 | A leak costs 3 lives |
| Shield Drone | Shielded | 80 | 20 | 240 | 1.2 | Shield regenerates |
| Skimmer | Air | 80 | 10 | 0 | 1.6 | Flies a route 40% shorter |
| Phaser | Cloaked | 140 | 30 | 0 | 1.4 | Invisible unless revealed |
| Hive Carrier | Titan | 2,500 | 100 | 400 | 0.5 | Releases 6 Swarmers when destroyed |

New aliens from story chapters each bring a twist, such as a burrower that skips part of a lane, a healer or a splitter.

Raid units (default: human colony forces):

| Unit | Class | Supply | Role |
|---|---|---|---|
| Trooper squad | Swarm | 2 | Cheap, fast, comes in numbers |
| Hornet gunship | Air | 4 | Ignores lanes, fragile |
| Aegis walker | Shielded | 5 | Projects a shield over nearby units |
| Ghost infiltrator | Cloaked | 5 | Disables one tower for 5 seconds on reaching it |
| Bulwark mech | Armored | 6 | Soaks tower fire |
| Breacher titan | Titan | 15 | Slow, targets towers and walls, one per raid |

- Raid units start from the alien stats of their class, with separate PvP multipliers in config, so PvP tuning never breaks PvE.
- Troops persist. Survivors come home after a raid, and fallen units are wounded or killed (see PvP raids).
- Each march is limited by supply: 40 plus 2 per Nexus level.
- Each unit has a load, the loot it can carry home. Starting values: Trooper squad 20, Hornet gunship 10, Ghost infiltrator 15, Aegis walker 30, Bulwark mech 60, Breacher titan none. Load grows ×1.42 per Nexus level, in step with building costs, so a full army's haul stays worth the trip.
- Units fight units on a cycle: Swarm beats Cloaked, Cloaked beats Shielded, Shielded beats Air, Air beats Armored, and Armored beats Swarm (Strong 1.5, Weak 0.5). Titans are Weak against every unit but deal triple damage to towers and walls.
- Defenders field a garrison. Troops kept at home pour out of the Core to meet attackers in the lanes, alongside the towers.
- Defenders also get walls, which slow units but can never seal a lane, and one-use traps (mine, stasis field, decoy) that re-arm free after each raid.
- A defender's assigned commander adds its passive bonus in defense, never its active ability.

## Base, buildings and progression

Progression mostly unlocks new options. Raw power grows slowly, and every stacked bonus hits a soft cap.

The base:

- A grid colony map with 2 lanes at the start and 3 from Nexus 10. Lanes run from the map edge to the Core.
- Tower slots: 10 plus 1 per 3 Nexus levels (18 at Nexus 25). Towers sit on pads beside the lanes.
- A layout editor with 2 free save slots. The server re-validates every saved layout: lanes open, slot limits respected, nothing overlapping.

| Building | What it does | Unlocks at Nexus |
|---|---|---|
| Command Nexus | Base level; caps every other building; sets tower slots | Start |
| Alloy Extractor (×3) | Alloy per hour | Start |
| Fusion Reactor (×3) | Energy per hour | Start |
| Warehouse | Storage cap; secures a fixed amount of each resource from raids, rising each level | Start |
| Research Lab | Research; +2% research speed per level | 2 |
| Foundry | Tower tiers and permanent tower levels | 3 |
| Barracks | Troop training, training queue and garrison size | 4 |
| Hospital | Beds for wounded troops; when full, further fallen troops die | 4 |
| Xenite Refinery | Xenite per hour | 5 |
| Command Academy | Commanders and their max level | 6 |
| Defense Grid | +1% tower HP per level, counted in the bonus pool | 8 |

Curves (all config knobs):

- Cost at level L = base × 1.42^(L − 1). Build time = base × 1.40^(L − 1). The Nexus costs twice as much and takes twice as long.
- Production = base × 1.25^(L − 1). It grows slower than cost, so each upgrade pays back more slowly as you climb.
- Warehouse storage = base × 1.45^(L − 1), always at least the cost of the next Nexus upgrade. Its secured amount per resource = base × 1.35^(L − 1), so higher levels keep more at risk.
- Hospital beds = base × 1.30^(L − 1), with research adding more.
- Max level 15 in the first version, 25 by Update 3. Two builders for everyone; a third is earned through play, and a fourth can be won for 7 days in events. Builders are never sold.

Power compression:

- Tower tiers T1 to T5 unlock at Foundry 1, 5, 10, 15 and 20. Each tier adds 15% damage and HP (T5 = 1.75×), plus a new look and one perk.
- Permanent tower levels within a tier add up to 20%.
- The bonus pool (weapon research, commander passives, Defense Grid, clan tech, relic sites) counts fully up to +30%, at half value from +30% to +90%, and not at all beyond. Maximum effective bonus: +60%.
- Net effect: a maxed tower is about 3.4× a brand-new one (1.75 × 1.2 × 1.6). A base 3 Nexus levels higher is typically 20% to 35% stronger in raw stats, before the underdog modifier.

Research:

- Four branches: Weapons, Defense, Raid and Economy. Each node has 10 levels; cost and time grow ×1.35 per level; node level n needs Research Lab level 2n.
- Weapons, Defense and Raid nodes feed the soft-capped bonus pool. Economy nodes (production, build speed) only speed up progress.

Commanders:

- Earned through the story, events, the clan shop and achievements. Never sold and never in paid random boxes; their skins can be sold.
- Each has one passive that boosts a tower or unit class, and one active ability for PvE and raids, such as Orbital Strike, EMP Pulse or Rally.
- Rarity changes the ability more than the numbers. Max passive runs from 8% (Common) to 14% (Legendary), inside the soft-capped pool.
- Max level = 2 × Command Academy level, raised with battle XP and Xenite.

Catch-up: a player more than 3 Nexus levels below their server's median gets +50% production and build speed until they reach it.

## PvP raids

Raiding is unlimited and lucrative. Hit any colony on your server as often as your army can, drain everything its Warehouse doesn't secure, and overrun it to send it fleeing across the map.

Raid flow:

1. Pick a colony on the sector map and scout it for a small Energy cost. The report shows its towers, garrison, commander, Integrity and unsecured resources.
2. March your army there. Travel takes 1 to 20 minutes by distance (about 3 minutes to a near neighbor), and marching armies are visible on the map.
3. On arrival, the server snapshots the defender (towers, garrison, traps, commander) and issues a seed. You deploy units at lane entrances and fire commander abilities for up to 180 seconds. If you're not in the app when the army arrives, or you choose auto-deploy, the server fights with your saved attack plan: which units go down which lane, in what order, and when abilities fire. A rally fights with its leader's plan if the leader is away.
4. The client submits the command log and the sim worker replays it. Auto-deployed battles run entirely on the server. The server's result always stands.
5. In one transaction, the server applies casualties to both sides, loot, Integrity damage and war score, and stores the replay for 7 days.
6. Survivors march home carrying the loot. The defender gets the full battle report and replay, with push alerts bundled so a siege doesn't flood their phone (see UX).

There are no raid tickets and no daily caps. Armies limit themselves: wounded troops need healing, the dead need retraining, and every hit costs travel time. Loot tapers after 15 winning raids a day (full, then 50%, then 20% after 30), but raids never stop.

Definitions used throughout:

- **Hit:** a raid that reaches at least a Partial breach, or whose army fills at least half the attacker's supply limit. Smaller failed raids still fight, but don't count toward dig-in, defense rewards, war score or the hit budget.
- **Power:** one strength score. Each unit or tower is worth √(effective HP × damage per second) at its tier, level and bonuses. Army power sums a march; colony power sums its towers, garrison and traps.
- **War score:** 3 for a Partial, 6 for a Major, 10 for a Total, 10 more for an overrun and 5 for a defense that holds. Punching up adds 20% per level, hitting 3 or more levels down halves it, and War Banner raids double it.
- **Clan strength:** the sum of members' colony power, with AI squadmates at half. It's used to match clans for clan war.

Results:

- Partial breach at 40% base damage, Major at 70%, Total when the Core falls.
- Loot is the smaller of two amounts: the army's carry capacity (the load of every surviving unit), or the defender's unsecured resources × the breach share (Partial 30%, Major 60%, Total 100%), after the loot modifiers below. Repeated raids can mill a colony's unsecured resources dry, but Warehouse-secured resources can never be taken.
- **Integrity:** every colony has 100. A Partial costs 10, a Major 25 and a Total 40. Integrity regrows 10 per hour, faster with Alloy repairs.
- **Overrun:** at 0 Integrity the colony is overrun. It teleports to a random free spot in its own ring, far from its attacker, with Integrity back at 100, and whoever finished it earns an overrun bonus and war score. That player can't hit it again for 6 hours; anyone else can. Its owner can't use targeted relocation for 24 hours, then gets one free move back to their clan's territory.
- A defense that holds a counted hit below 40% pays the defender a reward and war score, up to 3 times a day.
- Towers are never lost. They're back at full strength right after every raid; it's the garrison, the resources and the Integrity that wear down.

Hospital and casualties:

- Every fallen unit ends up wounded or dead. Wounded fill free hospital beds, and once the beds are full the rest die.
- **Attacker:** 80% of fallen units are wounded and 20% die, so raiding never costs too much. Healing costs 10% of training cost and takes a quarter of the training time.
- **Defender:** at even power, 70% of fallen units are wounded. Wounded share = 0.7 + 0.2 × (attacker power ÷ defender power − 1), kept between 0.6 and 0.9.
- The battle decides how many units fall, so a stronger army still kills more. The split only decides how many come back, which keeps a much stronger attacker from wiping out a weaker player's whole army.

Who you can hit and what it pays:

- Any colony on your server's map, except players under new-player protection, an active peace shield, or Entrenched status against stronger attackers (below).
- **Punching up:** attacker units get +5% damage and HP per level of gap, max +25%. Loot +10% per level, max +50%.
- **Same level:** no modifier.
- **Punching down:** loot shrinks 20% per level beyond 2 levels below, to a 10% minimum. Overruns still count, but farming much weaker players stops paying.

Limits on hitting weaker players apply only when the attacker is 3 or more Nexus levels above the target. Even fights and punching up stay unlimited.

- **Hit budget:** each stronger attacker gets 3 hits on the same colony per 12 hours, and all stronger attackers together get 6 per 24 hours.
- **Shrinking loot:** a stronger attacker's repeat hits on the same colony pay 100%, then 60%, then 30% of normal loot, on top of the punching-down reduction.
- **Entrenched:** once the combined budget is spent, the colony is closed to stronger attackers until the window rolls over. Peers and weaker players can still hit it. After an overrun by a stronger attacker, the colony is Entrenched against stronger attackers for 2 hours.
- **Visible budget:** scout reports and the map show how many hits a colony has left against stronger attackers.
- **Revenge is exempt:** revenge raids, by the victim or by clanmates on their behalf, never count against any budget.
- **Distress call:** when a member becomes Entrenched, their clan is alerted and gets revenge bonuses against the attackers.

**Dig-in** applies to every colony. Each hit taken adds +5% tower and garrison strength for 12 hours, up to +25%. Sieges escalate instead of turning into free farming, and rallies or fast, well-timed strikes can still break through.

**War Banner:** players who want full consequences can raise it. It removes their hit budget, Entrenched status and new-player protection, and gives +20% loot on their own raids and double war score. Dig-in still applies. Lowering the banner takes 24 hours, and everyone can see who flies one.

Vengeance:

- **Revenge list:** everyone who hit you in the last 72 hours. Revenge raids get +10% unit damage and +25% loot, for you and for clanmates striking on your behalf.
- **Bounties:** put your own resources on someone from your revenge list; whoever overruns them collects. A quarter of each bounty is destroyed, accounts linked to the poster can't claim it, and Gems can't fund bounties.
- **War news:** a server feed of overruns, big wins and claimed bounties.

Raid modifiers and how they stack:

| Combat modifier | Side | Effect | Cap |
|---|---|---|---|
| Underdog | Attacker | +5% unit damage and HP per level punched up | +25% |
| Revenge | Attacker | +10% unit damage | +10% |
| Dig-in | Defender | +5% tower and garrison strength per hit taken in the last 12 hours | +25% |

Attacker modifiers add together, capped at +35%, and apply at step 4 of the damage pipeline, after the soft-capped bonus pool.

| Loot modifier | Effect |
|---|---|
| Punching up | +10% per level, max +50% |
| Punching down | −20% per level beyond 2 levels below, 10% minimum |
| Revenge | +25% |
| War Banner, on the attacker | +20% |
| Repeat hits by a stronger attacker | 100%, then 60%, then 30% |
| Daily taper | Full for 15 winning raids, then 50%, then 20% after 30 |

Loot modifiers multiply, and their combined bonus is capped at +75%. Loot arrives as Alloy and Energy in proportion to the defender's unsecured amounts, and carry capacity is always the final cap.

War tactics:

- **Scouting:** reports older than 30 minutes are marked stale.
- **Rallies:** up to 5 clanmates combine armies under one commander against one colony, and loot splits by contribution. This is how weaker players bring down a giant.
- **Auto-deploy:** save up to 3 attack plans (lanes, unit order, ability timing). Use them for repeat hits, for rallies or to fight while you're away; a hands-on raid usually does better.
- **Reinforcements:** clanmates station troops in your colony; their wounded go to their own hospitals.
- **Garrison choice:** decide which troops stay home to defend and which march out.
- **Traps, decoys, targeting rules and saved layouts,** plus timing attacks around shields and Integrity regrowth.
- **Teleport tactics:** an overrun colony lands in its own ring, far from its attacker, buying its owner time to regroup and plan revenge.

Protection:

- New players are protected until Nexus 6 or day 3, whichever comes first. Attacking anyone ends it early.
- Peace shields (8 hours, 24 hours or 3 days) come from events, achievements, the clan shop or the store. Attacking or scouting drops your shield, and you can't raise a new one for 2 hours afterwards, so every attack leaves a window for revenge. Bought shields can cover at most 3 days in any 7.

Raid rating is Elo-style (K = 32), with 30-day seasons, a soft reset and leagues split by Nexus band. Practice raids on bot bases, clanmates' layouts and Layout Workshop challenges stay unlimited and free, and give mastery XP only.

## Sector map and points of interest

Each server has a shared sector map whose points of interest players and clans fight over asynchronously. Level bands keep the strongest players off the weakest players' spots.

- One map per server shows colonies, points of interest and clan territory. Players pan, zoom and tap anything for details.
- Every colony on the map can be raided, except players under new-player protection or a peace shield. An overrun colony teleports to a random free spot in its own ring, far from its attacker.
- Sending a force takes 1 to 20 minutes of travel, by distance: about 3 minutes to a near neighbor and 15 to 20 to cross the map. Earned speed-ups shorten it. Each player has 2 march slots, 3 from Nexus 15.

Layout for 1,000 active colonies per server:

- **Rings:** new colonies spawn in the outer ring (tier 1–3 nests and deposits). The middle ring holds tiers 4–7, and the center holds tiers 8–10, the relic sites and the Hive Core. Better loot pulls strong players inward, away from new players.
- **Density over size:** about 30 neighbors within a 3-minute march, 15 to 20 minutes to march across the whole map, and colonies covering about 10% of the land.

| Point of interest | What you do | Rewards | Contested? |
|---|---|---|---|
| Alien nest (tiers 1–10) | Attack with a strike force in a PvE battle against the nest's layout | Resources, commander XP, codex entries | No; respawns every 30 minutes |
| Roaming monsters (tiers 1–10) | Hunt wandering packs of Swarmers, Brutes and Skimmers in a quick PvE battle | Resources, codex entries, task progress | No; new packs appear every hour |
| Resource deposit (tiers 1–6) | Send a harvester team that gathers for 1 to 4 hours | Alloy, Energy or Xenite | Yes: any player can raid the deposit's 3-tower outpost while you gather |
| Relic site | Clans capture it during scheduled Relic Wars and set its defense layout | Clan-wide bonus and clan currency | Yes: clan against clan, async raids on the relic's layout |
| Anomaly | Appears during calendar events with story missions, puzzles and mini-bosses | Event currency, story, cosmetics | No |
| Hive core (server boss) | Everyone on the server attacks it during its event | Server-wide rewards by total damage, plus personal milestones | No |

Fairness rules on the map:

- Every nest, monster pack and deposit tier has a Nexus band. You can only attack or gather from tiers matched to your level, so top players can't camp low-tier deposits.
- A clan can hold at most 3 relic sites, and relic bonuses count toward the soft-capped bonus pool.
- A raided harvester team loses at most 30% of what it carries.
- A harvester team that loses a fight takes casualties under the same hospital rules as any army.

**AI rival colonies** keep the map alive before it fills. They belong to the story's rival faction and always carry an AI badge.

- Each gets a hidden temperament when it spawns: Raider (hits players often), Even-keeled (mostly defends, raids now and then), Turtle (rarely attacks), Vengeful (strikes back at whoever hits it) or Wildcard (switches temperament every few days). The mix is weighted per server, so no two neighborhoods play the same.
- Timing, targets and army mixes are randomized within each temperament, so players can't script around them.
- AI raids follow every player rule: protection, the hit budget, shrinking loot and dig-in all apply. Each player takes at most 2 AI raids a day, fewer as the server fills.
- They're raided like players, with loot, Integrity and overruns. They give war score and task progress, but no raid rating.
- A fresh map starts with about 400 AI colonies, never more. They leave a few at a time as real players arrive, packing up or driven out in a story event, and are gone by about 800 active players. None leaves mid-fight with a player.
- Their layouts come from a library of designed and generated bases, tougher toward the center rings.

Map state lives in Nakama storage and updates over its realtime socket, with polling as a fallback. Every map battle uses the same sim and server verification as raids.

## PvE: story campaign, invasions and events

PvE gives every player, paying or not, a steady path to every gameplay reward. It teaches the counter system through a story told in acts.

Story campaign:

- Three acts of 20 stages: Landfall at launch, then The Hive Stirs and Into the Brood by Update 3 (working titles).
- Story beats arrive in short, skippable dialogue panels before and after stages, with deeper lore in the codex.
- The original cast: the player's colony commander, recruitable commanders, a xenobiologist who explains each alien, and a rival colony faction that gives raids a reason in the story.
- Act 1 introduces all six towers and enemy classes, two or three stages apart. Acts 2 and 3 remix them with new alien abilities.
- Stars for lives kept; star totals unlock rewards. Every stage has Normal, Hard and Nightmare modes with modifiers.
- Every 60 to 90 days, a story chapter of about 10 stages brings a new alien, tower or unit.
- First clears give resources and occasional unlocks. Replays give 30% rewards, which then taper (see Engagement).

Difficulty:

- Within a stage, wave HP grows ×1.09 per wave and kill credits ×1.03 per wave.
- Across stages, HP grows ×1.02 per stage, so stage 60 is about 3.2× stage 1. That matches compressed player power (a maxed tower is about 3.4×). Later stages get harder mainly through tougher mixes, more lanes and new alien abilities.
- Wave pressure for the balance simulator: required damage per second = total wave HP ÷ (spawn time + time in the kill zone), compared with what the player's credits can buy. Target ratio: 0.4 to 0.6 on early waves, 0.8 to 1.0 on the last wave, about 1.1 on boss waves.

More PvE:

- **Base invasions:** every 8 hours an alien wave hits your own base layout, or anytime with an invasion beacon. Clearing it pays resources; failing costs nothing but the reward.
- **Field towers:** in every PvE battle, kills earn credits for temporary towers that vanish afterwards.
- **Endless mode:** waves scale until you fall, with a weekly mutator and a weekly leaderboard per server, split by Nexus band.
- **Daily puzzle:** one fixed map and tower set, the same for everyone on the server, scored by lives and credits left.
- **Events:** rotating 3- to 7-day events with a twist, such as Air-only waves or double Cloaked. Every gameplay reward is earnable for free, and an optional $2.99 event pass adds exclusive cosmetics (see Economy).
- **Clan boss:** a giant Hive Carrier that clan members attack asynchronously over 48 hours. Everyone is rewarded by the clan's total damage, with small cosmetic extras for top contributors.

## Servers, clans and chat

A server is a label on players, not a separate machine. One backend hosts every server, each with its own map, ladder, clans, chat and event calendar.

Servers:

- Every player record carries a server ID. Raids, the sector map, ladders, clans, chat channels and events all filter by it.
- Each server's map is built for 1,000 active colonies. Open a new server when the newest one passes about 1,000 active players (active means played in the last 14 days); new players join the newest server by default but may pick an older one. A server must also be fun with just 150 to 300 daily players; AI colonies and squadmates fill the gaps.
- Colonies inactive for 14 days leave the map and return when their player does, so the map stays alive.
- Each server has a fixed daily reset time, shown in the player's local time.
- Merge a server that stays under 300 daily actives for 14 days into one of similar age. Name clashes get a free rename, clans carry over, ladders reset to the season start and the map is rebuilt.
- One free transfer per 90 days, only to a server whose median Nexus level is within 3 of the player's.

Clans (also called alliances):

- Up to 30 members: a leader, officers and members. The leader sets join rules (open, request or invite, plus a minimum Nexus level).
- **Clan help:** tap to cut a clanmate's timer by 1% (minimum 1 minute), up to 10 helps per timer. Free, never sold.
- **Clan tech:** members donate resources to a clan tech tree whose bonuses enter each member's soft-capped pool.
- **Clan tasks:** shared weekly goals, such as 500 nests cleared, that reward every member who contributed.
- **Clan war:** weekly, over 2 days, matched by total clan strength. Each member gets 2 war raids, the higher total breach wins, and war raids never take resources.
- **Relic Wars:** scheduled clan fights over relic sites on the sector map, listed on the event calendar.
- **Clan shop:** war, boss and relic currency buys cosmetics, commander shards and speed-ups. All earned.
- **Clan merges:** both leaders agree and officers confirm. The merged clan keeps the higher clan level, the best of each tech node, the summed currency and both war histories, and picks a name and emblem. If the roster would pass 30, the leaders choose who moves, with notice to everyone. Relic sites over the 3-site cap are released. A clan can merge once per 30 days.
- A player who leaves a clan waits 24 hours before joining another clan's war.

**AI squadmates:** a clan can recruit AI members to fill gaps: up to 5 while it has fewer than 10 real members, 1 fewer for every 5 more, and none at 30.

- **Personas:** Buddies chat, cheer and tap clan help. War-ready squadmates scout, reinforce, join rallies and propose targets.
- **Chat:** a small language model writes their clan chat, about the game only. They reply to @mentions and take simple orders, such as scouting a colony. Off-topic questions get a friendly redirect back to the game.
- **Honesty:** they always carry an AI badge, say they're AI if asked, never push purchases, never flirt or ask for personal details, and go through the same chat filters as players.
- **Limits:** their war score counts at half weight, and they can't hold relic sites on their own.
- **Why game talk only:** California's companion chatbot law, in effect since 1 January 2026, exempts game bots only when their replies stay about the game ([source](https://perkinscoie.com/insights/update/california-companion-chatbot-law-now-effect)). Any message about self-harm gets a fixed safety reply with help resources and is flagged for review.
- **Decisions:** the game's own AI picks targets, orders and timing; the language model only writes the words. Filters stop players from rewriting their instructions through chat.
- **Reporting:** every AI message has a report button, as Google Play requires for AI-generated content ([source](https://android-developers.googleblog.com/2024/06/enabling-safe-ai-experiences.html?hl=es)). Reports feed the filters, and safety testing is documented before release, since Google may ask to see it.
- **Cost:** a monthly spending cap on the language model, with pre-written lines once it's reached. The privacy policy names the AI provider.

Chat and moderation (Google Play's user-generated content policy requires reporting, blocking and moderation):

- Channels: server, clan, and private messages between friends. Text and emotes at launch.
- Profanity filter per language, rate limits and slow mode.
- Report and block on every message and profile, with reports going to a moderator queue. Reports from several established players auto-mute the sender until a moderator reviews them.
- Moderator tools: mute, ban, delete messages, review reports and see an account's history. Chat rules live in the Terms. Trusted volunteer moderators from the player community share the queue with the owner.
- Players can turn off private messages. The target audience is 13 and over; the game is not designed for children.

## Engagement: tasks, event calendar and endless play

A 12-hour player always has a next goal, and a 20-minute player still keeps pace. Resource rewards taper after daily caps, while mastery, rankings and cosmetics never stop.

Tasks with bonuses:

- **Daily tasks:** 8 per day from a pool weighted by level and recent play. Completing 4, 6 and 8 opens bronze, silver and gold bonus chests.
- **Streaks:** consecutive days with 4 or more dailies raise a streak bonus up to day 7. A missed day drops the streak by 2 days, not to zero.
- **Weekly tasks:** 10 per week, with a weekly bonus chest and season pass XP.
- **Task chains:** story-linked goals across several stages and nests, with a bigger reward at the end.
- **Achievements:** 300 or more long-term goals, such as destroying 10,000 Swarmers or winning 50 raids against higher levels. They give titles, profile frames and Gems.
- **Clan tasks:** shared weekly goals (see Clans).

Server event calendar:

- An in-game calendar shows every scheduled event for the next 4 weeks in local time, with rules, rewards and leaderboard brackets.
- A repeating weekly rhythm, for example: Monday–Tuesday Build Rush (upgrade bonuses), Wednesday Nest Hunt, Thursday–Friday Clan War, Saturday–Sunday Relic Wars, and a server boss every second weekend.
- Each month brings a season start and a new pass, plus holiday specials. A new story chapter lands every 60 to 90 days.
- Events are config templates scheduled through LiveOps, so the calendar is never empty. Players opt in to reminders per event type.

| Activity | Limit | What it gives after daily caps |
|---|---|---|
| Story stages (Normal, Hard, Nightmare) | None | Mastery XP, stars, codex |
| Alien nests on the map | None | Mastery XP, codex entries |
| Endless mode | None | Leaderboard score |
| Daily puzzle | 1 scored run a day, unlimited retries | Score |
| Raids | None; troops, healing and travel time set the pace | Loot at 50% after 15 winning raids, 20% after 30; war score in full |
| Practice raids | None | Mastery XP |
| Layout Workshop | None | Likes, creator rank, cosmetics |
| Clan help, boss, war and relics | Per event | Clan rewards |
| Mastery tracks | None | Cosmetics and titles |
| Codex and collections | None | Lore and cosmetics |

- **Layout Workshop:** players design challenge bases and publish them to their server for others to attack for fun. Likes and plays build a creator rank, and layout names are moderated like chat.
- **Mastery:** every tower, unit and commander has a mastery track earned by use, unlocking skins, effects and titles. Mastery never adds combat stats.
- **Codex:** entries for every alien, tower, commander and story character, unlocked by play.

Reward taper keeps marathon players from running away with a server:

- Each mode pays full resources for its first battles of the day (for example 15 story stages or 20 nests), then 50% for the next batch, then 10%. Raid loot tapers too, after 15 winning raids and never below 20%, and raids themselves never stop.
- Mastery XP, leaderboard score, achievements and cosmetics never taper.
- **Rested bonus:** time away banks double rewards for the next battles, up to 8 hours' worth, so casual players close the gap.

Targets for the population simulator: by day 60, a 12-hour-a-day player has at most 1.5× the base progress of a 2-hour-a-day player, and a 30-minute-a-day player stays within 5 Nexus levels of the 2-hour player.

## Economy and monetization

Spending buys a small, capped head start. Everything that decides a battle is earned by playing. Players still get plenty of reasons to buy: a season pass with real convenience, event passes, cosmetics everyone sees on the map and in replays, shields, and gifts that help their clan.

| Resource | Comes from | Spent on | Raidable |
|---|---|---|---|
| Credits | Kills during a battle | Field towers, that battle only | No |
| Alloy | Extractors, battles, deposits, raids | Buildings, towers | Unprotected share only |
| Energy | Reactors, battles, deposits, raids | Research, units, rerolls | Unprotected share only |
| Xenite | Refinery, nests, events, bosses, story | Tower tiers, commanders | No |
| Gems (premium) | Achievements, events, weekly chests, the pass, purchases | Cosmetics, the season pass (1,000 Gems a week), layout slots, capped speed-ups | No |

Every source and sink writes to the economy ledger. Config sets a daily resource budget per Nexus level, and the population simulator keeps sources ÷ sinks between 0.9 and 1.2.

Earned speed-ups are generous, so most players get the benefits without paying:

- **Sources:** daily and weekly chests, streaks, events, achievements, the free pass track, clan help and the clan shop, nests and monster packs, and optional rewarded ads.
- **Sizes:** 5 minutes, 1 hour, 8 hours and 24 hours, plus big 3-day speed-ups from events and achievements.
- **Works on everything:** earned speed-ups work on buildings, research, training and healing. Bought ones only work on buildings and research.
- **Target:** earned speed-ups cover at least a quarter of an engaged free player's build and research time (see Fairness targets).

What money can buy (everything that speeds up progress counts toward the 15% limit):

- **Cosmetics, unlimited:** tower and unit skins, projectile effects, base themes, commander outfits, profile frames, emotes, raid banners, name and emblem changes.
- **Season pass:** $9.99 a week, billed weekly, with a premium reward track, weekly challenges and daily supply drops (details below). The free track still holds every gameplay reward.
- **Peace shields:** 8 hours, 24 hours or 3 days, also earnable in play. After you attack or scout, you can't raise a shield for 2 hours, so your targets always get a window for revenge. Bought shields can cover at most 3 days in any 7; earned ones don't count toward that.
- **Relocation:** random or targeted teleports to move your colony, also earnable in play. Targeted relocation has a 24-hour cooldown, bought or earned.
- **Resource and speed-up packs:** two a week, a $0.99 pack and a $4.99 pack, together worth at most half a day of normal play. Bought speed-ups work on buildings and research only. The $0.99 pack keeps them within reach for most players, and the weekly limit stops anyone stacking them.
- **Paid progress budget:** at their caps, packs add about 7% and the season pass about 8% (its +5% boost plus supply drops), so a max spender stays within the 15% limit, measured against a free player who also collects the earned speed-ups. Any new paid speed-up has to fit inside that total. In money, progress costs at most about $70 a month (the season pass plus both weekly packs); everything beyond that is cosmetic.
- **Starter pack:** once per account, cosmetics plus a small resource bundle.
- **Event passes:** $2.99 for each rotating event, with exclusive event cosmetics, a title and extra event currency for the event's cosmetic shop. Every gameplay reward in an event stays free, so event passes add no progress and sit outside the 15% budget.
- **Gem packs:** four sizes from $0.99 to $19.99, and the first purchase of each size gives double Gems. No single purchase costs more than $19.99.
- **Founder's pack (soft launch only):** $9.99 for a founder title, profile frame and base theme that early supporters keep forever.
- **Offers:** limited-time bundles appear in the store and at most once a day as a pop-up, never during or right after a battle.
- **Clan gifts:** every purchase drops a small gift chest for each clanmate, so spending helps the whole clan.
- **Rewarded ads (optional):** up to 5 a day, each worth at most 3% of a typical day's resources. No forced or interstitial ads.

Season pass ($9.99 a week):

- **Billing:** an auto-renewing Google Play subscription with a weekly billing period ([source](https://support.google.com/googleplay/android-developer/answer/140504)), priced per region in Play Console. Before purchase, the store shows the weekly price, that it renews every week until canceled, and what's included. Settings link straight to Google Play's subscription page to cancel, and benefits last to the end of the paid week ([source](https://support.google.com/googleplay/android-developer/answer/9900533?hl=en)).
- **Fun:** a premium track each 30-day season with animated skins, a base theme, kill effects, emotes and a raid banner. Each week brings 5 Pass Ops, challenges with a twist such as "win a raid with Air units only", paying pass XP and a weekly crate, plus a pass-only challenge stage with its own leaderboard.
- **Needed benefits:** +5% production and +5% build and research speed, auto-collect, 2 extra layout slots, a daily supply drop of speed-ups and resources, 2 extra daily task rerolls, and one 8-hour peace shield a week, inside the bought-shield limit. Together they come to about 8% of progress, inside the 15% cap.
- **Attainable:** any week can be unlocked with 1,000 Gems instead of money, and an engaged free player earns about 500 Gems a week, enough for every other week. Joining mid-season unlocks premium rewards for every tier already reached, and each renewal drops a gift chest for every clanmate.
- **Never in the pass:** stat boosts, healing or training speed-ups, march slots, builders or commanders.

Never sold: stat boosts, tower or unit levels, tiers, commanders, Xenite, healing or training speed-ups, march slots, builders or paid random boxes. If a random reward is ever sold, Google Play requires showing the odds before purchase. No spend-based VIP levels, because permanent perks compound.

Payments:

- Google Play Billing for every digital purchase. The server validates each purchase through Nakama before granting anything, and grants are idempotent.
- Refunds and chargebacks revoke what was granted; an account in the negative can't buy again until it's settled.
- Prices are set per region in Play Console and shown in local currency.

## Fairness targets and simulators

Build two simulators before tuning anything, and treat these targets as automated tests that must pass on every config change.

1. **Balance simulator:** runs the real sim core headless across thousands of scripted PvE battles and raids. It reports wave pressure, tower value per credit by class, and raid breach rates by level gap.
2. **Population simulator:** a server of 2,000 bot players over 90 days, using the real economy, timers, caps and store rules. Play styles: 30 minutes a day, 2 hours a day, 12 hours a day, light spender, max spender, aggressive raider and clan-focused player.

| Target | Passes when |
|---|---|
| Paid progress | Max spender has at most 15% more base progress than the 2-hour free player at day 60 |
| Earned speed-ups | Earned speed-ups cover at least 25% of the 2-hour free player's build and research time at day 60 |
| Pass access | The 2-hour free player earns enough Gems for the season pass at least every other week |
| Paid raid power | Max spender wins at most 52% of raids against free players at the same Nexus level |
| Marathon progress | 12-hour player has at most 1.5× the base progress of the 2-hour player at day 60 |
| Casual pace | 30-minute player stays within 5 Nexus levels of the 2-hour player at day 60 |
| Underdog, 3 levels | Attacker 3 levels below with a fitting army reaches Partial breach or better in at least 60% of raids |
| Underdog, 5 levels | Partial breach or better in at least 35% of raids |
| Vengeance rally | A 5-player rally, each 3 levels below the target, reaches Major breach or better in at least 50% of attempts |
| Strength gap | A base 3 levels higher is 20% to 35% stronger in raw stats and under 20% after modifiers |
| Raiding pays | A winning even-level raid's loot is at least 5× its healing and retraining cost |
| Attacker recovery | Healing a typical winning even-level raid takes at most 15 minutes |
| Farming weaker players | Raids on targets 5 or more levels below earn at most 25% of the loot per hour of even-level raiding |
| Secured resources | No raid ever takes Warehouse-secured resources |
| New players | Zero raids land on players under new-player protection |
| Tower variety | Every tower type is at least 10% of placements in the top 100 layouts |
| PvE pace | The 2-hour player clears Act 1 on Normal by day 7 and on Hard by day 30 |
| Level pace | The 2-hour player reaches Nexus 15 around day 100, and no one reaches it before day 70 |
| Economy | Sources ÷ sinks stay between 0.9 and 1.2 at every Nexus level |

Both simulators run in CI on every config change and publish a short report. A failing target blocks the config release.

Live check from the first closed test: players overrun in their first 14 days should keep at least 80% of the day-30 retention of players never overrun. If they don't, tighten the weaker-player limits in config.

## Anti-cheat, security and data model

Assume the phone is hacked. The server owns all state, replays battles and checks every request.

- **Accounts:** a device account for an instant start, with Google sign-in linking for recovery and new phones. Session tokens with refresh.
- **Every request** checks inputs, ownership and costs, and carries a client request ID so a retry never applies twice.
- **Server time only** for timers, shields, Integrity regrowth, marches and events. Device clocks are ignored.
- **Transactions:** every economy change runs in one database transaction and writes a ledger row: who, what, why, before and after.
- **Battle verification:** the sim worker replays PvE rewards, map battles and raids. A mismatch rejects the result and flags the account; repeat flags remove the player from leaderboards, then ban.
- **Device integrity:** a Play Integrity API check at login, used as a risk signal rather than an automatic ban.
- **Alt accounts:** no trading or gifting between players, and clan donations go only to clan tech. Fights between linked accounts (same device, Play Integrity signals or matching play patterns) give no loot, war score or rewards, including outpost raids, rallies and bounties. A shared network address is only a weak signal, since mobile carriers put many players behind one address.
- **Rate limits** per account and per network address.
- **Dropped connections:** a battle can resume within 60 seconds. After that, a PvE battle counts as a loss without penalty, and a raid ends with the damage already done.
- **Admin console:** Nakama's console plus custom pages for bans, refunds, logged economy grants, config publishing and server merges.

| Record | Key fields |
|---|---|
| Player | id, server_id, name, nexus_level, raid_rating, integrity, map_position, shield_until, protection_until, clan_id, created_at |
| Layout | player_id, slot, towers, walls, traps, lanes, active, validated_hash |
| Building | player_id, type, level, upgrade_ends_at |
| Wallet | player_id, alloy, energy, xenite, gems, secured_amounts |
| Troops | player_id, type, available, wounded, marching, garrisoned, reinforcing |
| Commander, Research, Mastery | player_id, type, level, xp |
| Raid | id, attackers, defender, server_id, seed, sim_version, config_version, snapshot, command_log, result, casualties, loot, integrity_damage, replay_ref, created_at |
| Map point | id, server_id, type, tier, position, holder, respawn_at |
| March | id, player_id, target, departs_at, arrives_at, force, rally_id |
| Rally | id, leader, target, members, launch_at |
| Attack plan | player_id, slot, deployments, ability_timings |
| Bounty | id, target, poster, amount, claimed_by |
| Clan | id, server_id, name, members, roles, tech, currency, wars, merged_from |
| Task, Achievement, Event | owner (player or server), progress, schedule, rewards |
| Purchase | id, player_id, product, token, status, granted_items |
| Subscription | player_id, product, period_end, auto_renew, status, paid_with |
| Ledger | id, player_id, delta, reason, ref, at |
| Config | version, json, published_at |
| AI agent | id, server_id, temperament, mood, colony_id, clan_id, persona |

Operations: daily backups with a tested restore, monitoring of CPU, request latency, errors and the sim worker queue, alerts, and a staging environment that mirrors production.

## UX, accessibility, performance, art and audio

Build for cheap Android phones first. If it runs smoothly on a phone with 3 GB of RAM, it runs everywhere.

Performance:

- 60 fps target with a 30 fps battery saver. Up to 300 entities on screen, with object pooling for units and projectiles.
- Keep the first download under 150 MB; deliver extra art and audio after install through Play Asset Delivery.
- Cold start under 5 seconds on a mid-range phone.
- Test on low, mid and high-end devices and on the oldest Android version supported.

Onboarding and UX:

- A 5-minute tutorial teaches tower placement and the counter system, then a guided raid on a bot base. It also explains the new-player shield.
- Every tower and enemy shows its class icon; a long press shows what it's strong and weak against.
- Portrait throughout, playable one-handed. Lanes run top to bottom with the Core at the bottom.
- The map opens clean: resources, alerts and the nav bar. Chat, marches, the target card and the minimap slide in when tapped.
- Push notifications for finished upgrades, raids on your base, clan wars and events. Android 13 and later asks permission first, and each type can be turned off. Raid alerts are bundled into one summary every 30 minutes at most, with an immediate alert when Integrity drops below 25 or the colony is overrun.
- Every timer shows its end time in local time.

Accessibility and language:

- Class colors that work for color-blind players, always paired with a shape or icon.
- Text size, reduced motion and haptics settings, plus subtitles for any voice lines.
- All text in string tables from day one, with English at launch.

Art and audio:

- **Art direction:** a top-down view with flat, bright shapes on dark ground and glowing effects, as on the concept boards (redo their map and raid screens in portrait at the style test). Cyan marks you, teal your clan, amber rivals, and magenta the AI and the hive. Motion comes from code, such as recoil, squash and stretch, and pulses, instead of frame-by-frame animation, which keeps art affordable.
- **The hive:** all six aliens share violet shells, glowing yellow eyes and glowing spots, with a class-colored glow on top, so they read as one species. Each silhouette stays distinct at small sizes.
- Placeholder shapes until the core loop is fun (end of M2). Then a style test with one tower, one alien and one tile, checked at phone size.
- AI-generated art is fine with a commercial license, from tools like Scenario or PixelLab. Keep an asset log: file, tool, prompt, date and license.
- Never prompt with another game's name, characters or art. Every alien design is original.
- A distinct sound for each tower and alien class, 3 to 5 music tracks, and separate volume sliders.

## Analytics, LiveOps and launch on Google Play

Measure retention and fairness from the first test, tune through remote config, and plan around Google Play's 14-day closed test.

Analytics:

- Events: tutorial steps, sessions, stage starts, clears and fails, raid starts and results with level gap, map battles, purchases, pass renewals and cancellations, ad views, shields, task completions and chat reports.
- Dashboards: day 1, 7 and 30 retention, session length, the stage funnel, raid outcomes by level gap, retention after being overrun, payer versus free progress, marathon versus casual progress, and economy sources and sinks.
- Collect only what these need, keyed by anonymous player IDs.

LiveOps:

- Remote config with versions and one-tap rollback.
- Event calendar templates scheduled 4 weeks ahead.
- A/B tests only on knobs that don't touch combat (rewards, timers, UI), never on fairness rules or prices. Combat balance changes go to a whole server at once, since players in different test groups raid each other.
- Feature flags, a maintenance banner and a forced-update gate.
- A content cadence one person can keep: each 30-day season brings a pass and an event rotation, and every 60 to 90 days a story chapter brings a new alien, tower or unit.
- Crash and error reporting on client and server.

Getting players:

- Players cost more than building or hosting. Strategy games average about $4 per Android install ([source](https://foxdata.com/en/blogs/2026-mobile-game-user-acquisition-cost-benchmarks-how-much-should-you-spend/)), so keeping a few hundred people playing daily through ads alone could cost thousands of dollars a month.
- Start with free channels: Play pre-registration, a Discord, short gameplay clips and content creators. Lead with "fair to play": paid progress is capped at 15% and never costs more than about $70 a month.
- Soft-launch one server in a couple of smaller English-speaking countries for 4 to 8 weeks. Fix retention there, then launch worldwide and spend on ads.
- Expect less revenue per player than the genre leaders; that's the price of fairness. Sell cosmetics other players see, such as base themes on the map and skins in raid replays.

Google Play checklist:

- A personal Play Console account costs a one-time $25. New personal accounts must run a closed test with at least 12 testers opted in for 14 days straight before production, so recruit 20 or more.
- Run the closed test during M8 and M9 so it doubles as a playtest.
- Store listing, screenshots and a short video; the content rating questionnaire; target audience 13 and over; the Data safety form; a privacy policy URL; Terms of Service.
- In-app account deletion plus a web deletion link, which Google requires for apps with accounts.
- AI-generated content (Update 1): a report button on every AI squadmate message, restricted content blocked, and safety testing documented.
- Subscriptions: the season pass shows its weekly price, weekly renewal and contents before purchase, with a cancel link in settings. Show the weekly price as a weekly price, never converted to a monthly figure.
- Ads: a consent prompt where required (such as in the EEA), and ads declared in the listing.
- Target the Android API level Google currently requires.
- A staged rollout: 10%, then 50%, then 100%.
- Player support: an in-game help form, a FAQ and a community channel for testers.

## First version and updates

Launch small, then grow. The first version proves the core loop with real players, and everything else ships as updates. Rough estimate: the first version is most of a year of steady work for one person with AI help, mostly content, balance and testing.

1. **Launch:** story Act 1, base invasions, endless mode and the daily puzzle; all 6 towers and 6 enemy classes; three commanders; base building to Nexus 15; raids on a basic colony map with garrisons, hospitals, the Warehouse, overruns, revenge and the weaker-player limits; AI rival colonies; clans with chat, help and tasks; daily and weekly tasks, achievements and a simple weekly event calendar; the store, the season pass billed weekly, a founder's pack for the soft launch, and rewarded ads; one server, with a second opening only when the first fills, soft-launched in a couple of smaller countries before going worldwide.
2. **Update 1:** alien nests, roaming monsters, resource deposits and anomalies on the map, more calendar events with event passes, AI squadmates, mastery and the codex.
3. **Update 2:** clan war, clan tech, rallies, reinforcements, bounties and war news.
4. **Update 3:** relic sites and Relic Wars, the server boss, clan merges, the Layout Workshop, Acts 2 and 3, and Nexus 25.
5. **Update 4 (later):** server-vs-server events that reuse async raids across servers, giving top players a long-term goal.

Soft-launch first, then spend on ads to fill the server (see Getting players). War features feel empty without a busy map, and AI colonies only bridge the gap.

From the first closed test, track retention after being overrun (see Fairness targets), and tighten the weaker-player limits through config if it drops.

## Build milestones

Ten milestones, each ending in something the owner can play on a phone. Don't start the next until the current one's tests pass.

1. **M0 Foundations:** repo, CI, config schema, sim core skeleton (fixed tick, integer math, seeded random), golden-test harness, and a test build that tries each Godot plugin (Play Billing, ads, push notifications, Google sign-in, Play Integrity).
    - Done when the same battle produces an identical hash on desktop, on Android and headless, and every plugin works on a real phone.

2. **M1 PvE slice:** one map, 3 towers, 3 aliens, 10 waves, field towers, placeholder art.
    - Done when it holds 60 fps on a low-end phone and wave pressure is within target.

3. **M2 Full combat:** all 6 towers and 6 enemy classes, upgrades, status effects, targeting rules, balance simulator v1, and an offline raid prototype: deploy units against a saved base layout with a garrison.
    - Done when each tower wins its best matchup in the simulator, 10 to 20 outside players have tried both defending and raiding, and the owner says both are fun.

4. **M3 Base and buildings (local):** layout editor, lane validator, buildings, timers and resources stored on the phone.
    - Done when layouts save and load and no layout can seal a lane.

5. **M4 Backend:** Nakama, PostgreSQL and Docker; accounts; server-owned economy, timers and ledger; remote config; sim worker.
    - Done when a modified client can't change resources, closing the app mid-upgrade loses nothing, and the sim worker replays a full raid in under 100 ms.

6. **M5 Raids:** online raids built on the M2 prototype, with deployment and auto-deploy, server verification, scouting, hospitals and casualties, carry capacity, Integrity and overrun teleports, level-gap rules, peace shields, replays, revenge, practice raids.
    - Done when tampered raid logs are rejected and every protection rule has a passing test.

7. **M6 Progression and fairness:** research, commanders, tiers, soft cap, reward taper, rested bonus, catch-up, population simulator.
    - Done when every fairness target passes.

8. **M7 Colony map and clans:** one server with automatic opening of the next, a basic colony map with AI rival colonies, marches, clans with chat, help and tasks, report and block.
    - Done when AI colonies keep an empty map busy and a second server opens fully isolated from the first.

9. **M8 Content and engagement:** story Act 1 with dialogue, Hard and Nightmare modes, tasks, streaks, achievements, a weekly event calendar, endless mode, daily puzzle.
    - Done when a scripted 12-hour session never hits a dead end and the calendar is filled 4 weeks ahead.

10. **M9 Store, polish and launch:** cosmetics, the weekly season pass subscription, capped packs, Gem packs, the founder's pack, rewarded ads, Play Billing with server validation, tutorial, art and audio, accessibility, analytics, account deletion, the 14-day closed test, the soft launch, then the staged worldwide rollout.
    - Done when purchases are verified, refunds revoke items, no purchase changes battle stats, and at least 99% of sessions are crash-free.

After launch, ship Updates 1 to 4 from First version and updates, each with its own tests.

## Working rules for the AI builder

Work in small, tested steps, bring design calls to the owner, and never guess at facts.

- Keep `docs/DECISIONS.md`: every design or technical decision with its date, the options considered and the reason.
- Before each milestone, post a short plan of systems, files and tests. After it, post what changed, how to try it on a phone, and open issues.
- Ask the owner before changing a design pillar, the monetization rules, a fairness target, or anything players would notice in balance.
- Keep every balance number in `config/`, never in code, and document each new knob in the config schema.
- Write tests with every system. The sim's golden tests and the fairness targets run in CI.
- Make small commits with clear messages. No dead code, and no TODO without a matching issue.
- Never state store policies, prices or platform rules from memory. Check the current official docs and link them in `docs/DECISIONS.md`.
- Use only licensed libraries and assets, and record each license. Never copy code, art, text, names or data from other games.
- If something in this prompt turns out not to work, say so and propose a change instead of quietly diverging.

## Open decisions for you

These calls are yours. The builder uses the defaults below until you change them.

| Decision | Default | Other options |
|---|---|---|
| Game title | Not chosen yet | — |
| Raid units | Human colony forces | Captured alien strains bred in a lab |
| Orientation | Portrait throughout, played one-handed | Landscape battles with portrait menus |
| Max base level | 15 at launch, 25 by Update 3 | 20 at launch |
| Raid limits | None: troops, healing and travel time set the pace | Daily raid tickets |
| Raid loot taper | Full for 15 winning raids a day, then 50%, then 20% after 30 | None, or stricter |
| Auto-deploy | Saved attack plans fight when you're away | Manual raids only |
| Who you can hit | Anyone on your server; loot shrinks below −2 levels | A hard floor, such as 5 levels below |
| Hit budget against weaker players | Attackers 3+ levels above: 3 hits each per 12 hours, 6 in total per 24 hours | Tighter, looser or none |
| Dig-in | +5% per hit taken, max +25%, for 12 hours | Off |
| War Banner | Opt-in: no limits, +20% loot, double war score | Not offered |
| New-player protection | Until Nexus 6 or day 3 | None, or longer |
| Protection after an overrun | 2 hours against stronger attackers, 6 hours against the player who overran you | None, or longer |
| Casualty split | Attacker 80% wounded; defender 60% to 90% by power | Harsher or gentler |
| Peace shields | Earned or bought, with bought shields covering at most 3 days a week; no new shield for 2 hours after you attack or scout | Sold with no revenge window |
| Healing and training speed-ups | Not sold | Sold, which makes war pay-to-win |
| Earned speed-ups | Generous: at least a quarter of build and research time, usable on everything | Fewer, or buildings and research only |
| Extra march slot | Earned only | A 7-day rental |
| Fourth builder | Won for 7 days in events, never sold | Sold for 7 days, if other paid speed-ups shrink to stay under 15% |
| AI rival colonies | About 400 on a fresh map, gone by about 800 players | Off |
| Underdog bonus | +5% per level, max +25% | 3% to 8% per level |
| Paid progress cap | 15% faster than an engaged free player | 0% to 20% |
| Season pass | $9.99 a week, billed weekly, or 1,000 earned Gems a week | $4.99 a week, $9.99 a month, or cosmetics only |
| Weekly packs | Two: $0.99 and $4.99, together worth half a day of play | One pack, or bigger packs inside the 15% budget |
| Event passes | $2.99 per event, cosmetics only | With small speed-ups, if weekly packs shrink to make room |
| Biggest single purchase | $19.99 | Larger Gem packs |
| Rewarded ads | Up to 5 a day | None, or more |
| Clan size | 30 | 20 to 50 |
| Relic sites per clan | 3 | 1 to 5 |
| Season length | 30 days | 14 to 60 days |
| Content cadence | Pass and events every 30 days; a story chapter with a new alien, tower or unit every 60 to 90 days | Faster, with more help |
| Server size | 1,000 colonies active in the last 14 days, fun from 150 daily players; next server opens past that | Larger or smaller maps |
| Reward taper | Full, then 50%, then 10% | Gentler or stricter |
| Story | Act 1 at launch, Acts 2 and 3 by Update 3, then a chapter every 60 to 90 days | A larger launch campaign |
| AI squadmates | Up to 5 per small clan, always labeled AI, game talk only | Fewer, or off |

Change any default here and the builder updates the config and `docs/DECISIONS.md` to match.
