// One deterministic battle: aliens spawn from the waves and walk their lanes,
// field towers bought with credits shoot them, and leaks cost lives (D-034).
//
// Determinism rules (docs/BUILD_PROMPT.md, Combat simulation):
// - a fixed 20 ticks per second, integer math only, the battle's own SimRng only
// - entities update in ascending id order, and ids are handed out in spawn or
//   placement order; every targeting tie goes to the lower id
// - no engine physics, navigation, timers or random functions
//
// Inputs arrive already validated by the GDScript loaders (sim_config.gd,
// battle_spec.gd); setup() re-checks what could otherwise crash or overflow.
// tools/reference/sim_model.py states the same rules a second way.
#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "core/lane_path.h"
#include "core/sim_rng.h"

namespace aetd::sim {

// How a tower picks among the aliens it can hit (D-034, D-036).
enum Targeting : int64_t { TARGET_FIRST = 0, TARGET_STRONGEST = 1 };

// The six classes, in config/schema/common.schema.json's order.
enum EnemyClass : int64_t { SWARM = 0, ARMORED = 1, SHIELDED = 2, AIR = 3, CLOAKED = 4, TITAN = 5 };
inline constexpr size_t CLASS_COUNT = 6;

struct EnemyType {
	int64_t hp_x100 = 0;
	int64_t armor = 0;
	int64_t shield_x100 = 0;
	int64_t speed_mtps = 0;
	bool air = false;
	int64_t leak_lives = 0;
	int64_t class_index = SWARM;
	int64_t kill_credits_x100 = 0;
	// spawn_on_death: killed by a tower, it releases release_count aliens of
	// type release_index where it fell. -1 for none.
	int64_t release_index = -1;
	int64_t release_count = 0;
	// False when it has an ability this sim version doesn't run; setup refuses
	// a battle that would spawn it.
	bool supported = true;
};

// A tower type as the battle needs it: config lookups (counter ratings, the
// shield multiplier for its damage type) already resolved by sim/core/battle.gd.
struct TowerType {
	int64_t cost_credits = 0;
	int64_t damage_x100 = 0;
	int64_t shots_per_s_x100 = 0;
	int64_t range_mt = 0;
	int64_t splash_mt = 0;
	int64_t shield_mult_bp = 10000;
	int64_t pierce_bp = 0;
	// Counter rating against each class; 0 means it can't hit that class.
	std::array<int64_t, CLASS_COUNT> rating_bp{};
	// Damage share against a cloaked alien nothing reveals; 0 means it can't target one.
	int64_t unrevealed_bp = 0;
	int64_t targeting = TARGET_FIRST;
	// False when it has an ability this sim version doesn't run.
	bool supported = true;
};

struct FieldUpgrades {
	int64_t max_level = 1;
	int64_t first_upgrade_cost_bp = 0;
	int64_t cost_growth_bp = 0;
	int64_t damage_growth_bp = 0;
	int64_t range_step_bp = 0;
	int64_t sell_refund_bp = 0;
};

struct DamageRules {
	int64_t armor_constant = 100;
	int64_t max_reduction_bp = 0;
	int64_t min_damage_x100 = 0;
};

struct BattleConfig {
	std::string config_hash;
	int64_t config_version = 0;
	// In index order: the position of each id in sorted id order.
	std::vector<EnemyType> enemies;
	std::vector<TowerType> towers;
	FieldUpgrades upgrades;
	DamageRules damage;
	int64_t regen_per_second_x100 = 0;
	int64_t regen_delay_ticks = 0;
	int64_t retarget_ticks = 1;
};

struct LaneSpec {
	LanePath ground;
	std::optional<LanePath> air;
};

struct SpawnGroup {
	int64_t enemy_index = 0;
	int64_t lane_index = 0;
	int64_t count = 0;
	int64_t first_tick = 0;
	int64_t interval_ticks = 0;
	int64_t jitter_ticks = 0;
	// The wave's scaling of HP and kill credits.
	int64_t hp_bp = 10000;
	int64_t credits_bp = 10000;
	// Which wave it belongs to (an index into BattleSpec::wave_starts).
	int64_t wave_index = 0;
};

// CALL_WAVE brings the next wave in now, for a bonus (D-036).
enum CommandKind : int64_t { PLACE = 1, UPGRADE = 2, SELL = 3, CALL_WAVE = 4 };

struct Command {
	int64_t tick = 0;
	int64_t kind = PLACE;
	// The tower type to place, or -1 for upgrade and sell.
	int64_t tower_index = -1;
	int64_t col = 0;
	int64_t row = 0;
};

struct BuildTile {
	int64_t col = 0;
	int64_t row = 0;
};

struct BattleSpec {
	std::string battle_id;
	int64_t seed = 0;
	int64_t max_ticks = 0;
	int64_t lives = 1;
	int64_t credits = 0;
	// Tower type indices the player may build in this battle.
	std::vector<int64_t> tower_set;
	std::vector<BuildTile> build_tiles;
	std::vector<LaneSpec> lanes;
	std::vector<SpawnGroup> groups;
	std::vector<Command> commands;
	// Each wave's start tick; every group belongs to one and starts no earlier.
	std::vector<int64_t> wave_starts;
	// Calling a wave early pays this many credits a second it skips, up to the max.
	int64_t call_credits_per_s = 0;
	int64_t call_credits_max = 0;
	// A wave whose every alien dies without a leak pays this.
	int64_t clean_wave_credits = 0;
};

struct Alien {
	int64_t id = 0;
	int64_t type_index = 0;
	int64_t lane_index = 0;
	int64_t class_index = SWARM;
	bool air = false;
	const LanePath *path = nullptr;
	int64_t distance_mt = 0;
	// Movement carried over between ticks, in mt x TICK_RATE, so speeds that
	// don't divide by 20 still cover the exact distance over time.
	int64_t move_accum = 0;
	int64_t speed_mtps = 0;
	int64_t hp_x100 = 0;
	int64_t max_hp_x100 = 0;  // from the type and hp_bp, both hashed; Strongest targeting reads it (D-036)
	int64_t shield_x100 = 0;
	int64_t max_shield_x100 = 0;
	int64_t regen_accum = 0;
	int64_t last_hit_tick = 0;
	int64_t leak_lives = 0;
	int64_t kill_credits_x100 = 0;
	// Its wave's scaling, which aliens it releases inherit.
	int64_t hp_bp = 10000;
	int64_t credits_bp = 10000;
	int64_t wave_index = 0;
	// Where distance_mt puts it on its path, refreshed after every move.
	int64_t x = 0;
	int64_t y = 0;
	bool leaked = false;
	bool dead = false;
};

struct Tower {
	int64_t id = 0;
	int64_t type_index = 0;
	int64_t level = 1;
	int64_t col = 0;
	int64_t row = 0;
	int64_t x = 0;
	int64_t y = 0;
	int64_t charge = 0;
	int64_t target_id = 0;
	int64_t next_pick_tick = 0;
	int64_t spent_x100 = 0;
	// Derived from the type and level.
	int64_t damage_x100 = 0;
	int64_t range_mt = 0;
};

// What happened in the last tick, for drawing it. Not part of the state.
enum EventKind : int64_t {
	SHOT = 1, KILL = 2, LEAK = 3, PLACED = 4, UPGRADED = 5, SOLD = 6, REFUSED = 7,
	WAVE_DONE = 8,  // a = wave index, b = 1 if no alien of it leaked (it paid the clean-wave bonus)
	CALLED = 9,  // a = wave index called early, b = the bonus paid, x100
};

struct Event {
	int64_t kind = SHOT;
	int64_t a = 0;  // tower id (SHOT, PLACED, UPGRADED, SOLD), alien id (KILL, LEAK) or command index (REFUSED)
	int64_t b = 0;  // target alien id (SHOT)
	int64_t x = 0;
	int64_t y = 0;
};

enum Outcome : int64_t { RUNNING = 0, CLEARED = 1, TIMED_OUT = 2, LOST = 3 };

class Battle {
public:
	// A checkpoint hash every 100 ticks (5 seconds) lets a golden-test mismatch
	// be traced to the first stretch of the battle that diverged.
	static constexpr int64_t CHECKPOINT_TICKS = 100;
	// Spawn keys pack the spawn tick above a 20-bit spawn sequence number.
	static constexpr int SEQ_BITS = 20;
	static constexpr int64_t SEQ_MASK = (int64_t(1) << SEQ_BITS) - 1;
	// One shot's worth of charge: 20 ticks x 100.
	static constexpr int64_t SHOT_CHARGE = 2000;
	// Derived stats (level damage and range, wave HP, costs in credits) cap here.
	static constexpr int64_t MAX_STAT = 1000000000;

	Battle() = default;
	// Aliens point into this battle's own lanes, so a battle is never copied.
	Battle(const Battle &) = delete;
	Battle &operator=(const Battle &) = delete;

	// Prepares the battle, forgetting any earlier one. Returns false and fills
	// errors if the inputs are unusable; the battle is then empty.
	bool setup(BattleConfig config, BattleSpec spec);
	// Forgets any earlier battle: no aliens, no inputs, not ready to run.
	void reset();
	// Adds a player command for this tick or a later one, after the ones
	// already queued. Returns "" or what's wrong with it; a refused command
	// isn't queued. The state decides later whether it can apply.
	std::string queue_command(const Command &command);
	// Runs one 50 ms tick.
	void advance();
	// Runs to the end.
	void run();
	// SHA-256 of everything that can affect the rest of the battle.
	std::string state_hash() const;

	const BattleConfig &config() const { return config_; }
	const BattleSpec &spec() const { return spec_; }
	bool ready() const { return ready_; }
	// What a tower of this type costs to take from `level` to the next level, x100.
	int64_t upgrade_cost_x100(int64_t type_index, int64_t level) const;
	// What selling this tower would return, x100.
	int64_t refund_x100(const Tower &tower) const;
	// The tower on this build tile, or nullptr.
	const Tower *tower_at(int64_t col, int64_t row) const;

	int64_t tick = 0;
	Outcome outcome = RUNNING;
	// Live aliens in ascending id order.
	std::vector<Alien> aliens;
	// Towers in ascending id order.
	std::vector<Tower> towers;
	int64_t spawned_count = 0;
	int64_t leaked_count = 0;
	int64_t leaked_lives = 0;
	int64_t lives = 0;
	int64_t credits_x100 = 0;
	int64_t kills = 0;
	int64_t refused_commands = 0;
	// Each wave's start tick now (calling a wave early moves the later ones),
	// its aliens not yet resolved (planned spawns plus live ones), whether one
	// leaked, and whether it's done.
	std::vector<int64_t> wave_starts;
	std::vector<int64_t> wave_pending;
	std::vector<int64_t> wave_leaked;
	std::vector<int64_t> wave_done;
	std::vector<std::string> checkpoints;
	std::vector<std::string> errors;
	std::vector<Event> events;
	// Alien and tower updates so far, for speed measurements. Not part of the state.
	int64_t entity_updates = 0;

private:
	BattleConfig config_;
	BattleSpec spec_;
	SimRng rng_;
	int64_t next_id_ = 1;
	int64_t next_tower_id_ = 1;
	std::vector<int64_t> spawn_keys_;
	std::vector<int64_t> spawn_group_;
	size_t spawn_cursor_ = 0;
	size_t command_cursor_ = 0;
	bool ready_ = false;
	// Which tower id stands on each build tile (0 for none), in spec order.
	std::vector<int64_t> tile_tower_;
	// (row * 1000 + col, build tile index), sorted, to find a tile by position.
	std::vector<std::pair<int64_t, int64_t>> tile_lookup_;
	// Tower types the spec allows, by type index.
	std::vector<bool> allowed_;

	// The spatial grid that towers search (D-034): cells over the bounding box
	// of every path, holding alien indices in id order. It only narrows the
	// search; every candidate is checked by exact distance.
	int64_t grid_min_x_ = 0;
	int64_t grid_min_y_ = 0;
	int64_t grid_max_x_ = 0;
	int64_t grid_max_y_ = 0;
	int64_t grid_cell_ = 1000;
	int64_t grid_cols_ = 1;
	int64_t grid_rows_ = 1;
	std::vector<std::vector<int32_t>> grid_;
	int64_t grid_tick_ = -1;
	std::vector<int32_t> found_;
	// Ids of aliens killed this tick that release others, in order of death.
	std::vector<int64_t> releases_;

	void reset_after_errors();
	void build_spawn_plan();
	void spawn_due();
	void spawn(const SpawnGroup &group);
	void add_alien(int64_t enemy_index, int64_t lane_index, int64_t hp_bp, int64_t credits_bp, int64_t distance_mt,
			int64_t wave_index);
	void call_wave(int64_t index);
	void finish_waves();
	void release();
	bool move_aliens();
	void regenerate_shields();
	void apply_commands();
	void apply(const Command &command, int64_t index);
	void towers_act();
	void set_up_grid();
	void fill_grid();
	void search(int64_t x, int64_t y, int64_t radius);
	Alien *find_alien(int64_t id);
	bool can_hit(const TowerType &type, const Alien &alien) const;
	Alien *pick_target(const Tower &tower, const TowerType &type);
	void fire(const Tower &tower, const TowerType &type, Alien &target);
	void hit(const Tower &tower, const TowerType &type, Alien &alien);
	int64_t tile_index(int64_t col, int64_t row) const;
	int64_t level_damage(int64_t type_index, int64_t level) const;
	int64_t level_range(int64_t type_index, int64_t level) const;
};

} // namespace aetd::sim
