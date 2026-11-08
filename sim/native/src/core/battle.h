// One deterministic battle. M0 skeleton: aliens spawn from the waves, walk
// their lanes and leak at the Core. Towers, damage and commands arrive in M1.
//
// Determinism rules (docs/BUILD_PROMPT.md, Combat simulation):
// - a fixed 20 ticks per second, integer math only, the battle's own SimRng only
// - entities update in ascending id order, and ids are handed out in spawn order
// - no engine physics, navigation, timers or random functions
//
// Inputs arrive already validated by the GDScript loaders (sim_config.gd,
// battle_spec.gd); setup() re-checks what could otherwise crash or overflow.
#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

#include "core/lane_path.h"
#include "core/sim_rng.h"

namespace aetd::sim {

struct EnemyType {
	int64_t hp_x100 = 0;
	int64_t armor = 0;
	int64_t shield_x100 = 0;
	int64_t speed_mtps = 0;
	bool air = false;
	int64_t leak_lives = 0;
};

struct BattleConfig {
	std::string config_hash;
	int64_t config_version = 0;
	// In index order: the position of each alien id in sorted id order.
	std::vector<EnemyType> enemies;
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
};

struct BattleSpec {
	std::string battle_id;
	int64_t seed = 0;
	int64_t max_ticks = 0;
	std::vector<LaneSpec> lanes;
	std::vector<SpawnGroup> groups;
};

struct Alien {
	int64_t id = 0;
	int64_t type_index = 0;
	int64_t lane_index = 0;
	bool air = false;
	const LanePath *path = nullptr;
	int64_t distance_mt = 0;
	// Movement carried over between ticks, in mt x TICK_RATE, so speeds that
	// don't divide by 20 still cover the exact distance over time.
	int64_t move_accum = 0;
	int64_t speed_mtps = 0;
	int64_t hp_x100 = 0;
	int64_t shield_x100 = 0;
	int64_t leak_lives = 0;
	bool leaked = false;
};

enum Outcome : int64_t { RUNNING = 0, CLEARED = 1, TIMED_OUT = 2 };

class Battle {
public:
	// A checkpoint hash every 100 ticks (5 seconds) lets a golden-test mismatch
	// be traced to the first stretch of the battle that diverged.
	static constexpr int64_t CHECKPOINT_TICKS = 100;
	// Spawn keys pack the spawn tick above a 20-bit spawn sequence number.
	static constexpr int SEQ_BITS = 20;
	static constexpr int64_t SEQ_MASK = (int64_t(1) << SEQ_BITS) - 1;

	Battle() = default;
	// Aliens point into this battle's own lanes, so a battle is never copied.
	Battle(const Battle &) = delete;
	Battle &operator=(const Battle &) = delete;

	// Prepares the battle. Returns false and fills errors if the inputs are unusable.
	bool setup(BattleConfig config, BattleSpec spec);
	// Runs one 50 ms tick.
	void advance();
	// Runs to the end.
	void run();
	// SHA-256 of everything that can affect the rest of the battle.
	std::string state_hash() const;

	const BattleConfig &config() const { return config_; }
	const BattleSpec &spec() const { return spec_; }

	int64_t tick = 0;
	Outcome outcome = RUNNING;
	// Live aliens in ascending id order.
	std::vector<Alien> aliens;
	int64_t spawned_count = 0;
	int64_t leaked_count = 0;
	int64_t leaked_lives = 0;
	std::vector<std::string> checkpoints;
	std::vector<std::string> errors;
	// Alien updates so far, for speed measurements. Not part of the battle state.
	int64_t entity_updates = 0;

private:
	BattleConfig config_;
	BattleSpec spec_;
	SimRng rng_;
	int64_t next_id_ = 1;
	std::vector<int64_t> spawn_keys_;
	std::vector<int64_t> spawn_group_;
	size_t spawn_cursor_ = 0;
	bool ready_ = false;

	void build_spawn_plan();
	void spawn_due();
	void spawn(const SpawnGroup &group);
	bool move_aliens();
};

} // namespace aetd::sim
