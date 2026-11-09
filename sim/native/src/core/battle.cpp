#include "core/battle.h"

#include <algorithm>

#include "core/fx.h"
#include "core/state_hasher.h"

namespace aetd::sim {
namespace {

// 1,000 tiles, as battle_spec.gd allows: far beyond any map, and small enough
// that squared distances can't overflow.
constexpr int64_t MAX_COORD_MT = 1000000;
constexpr int64_t MAX_STAT = 1000000000;
constexpr int64_t MAX_TICKS = 72000;

bool in_range(int64_t v, int64_t lo, int64_t hi) { return v >= lo && v <= hi; }

bool coords_ok(const LanePath &path) {
	for (size_t i = 0; i < path.xs.size(); i++) {
		if (!in_range(path.xs[i], 0, MAX_COORD_MT) || !in_range(path.ys[i], 0, MAX_COORD_MT)) {
			return false;
		}
	}
	return path.xs.size() >= 2;
}

} // namespace

void Battle::reset() {
	tick = 0;
	outcome = RUNNING;
	aliens.clear();
	spawned_count = 0;
	leaked_count = 0;
	leaked_lives = 0;
	checkpoints.clear();
	errors.clear();
	entity_updates = 0;
	config_ = BattleConfig();
	spec_ = BattleSpec();
	rng_ = SimRng();
	next_id_ = 1;
	spawn_keys_.clear();
	spawn_group_.clear();
	spawn_cursor_ = 0;
	ready_ = false;
}

bool Battle::setup(BattleConfig config, BattleSpec spec) {
	// Aliens point into spec_'s lanes, so they go before the lanes are replaced.
	reset();
	config_ = std::move(config);
	spec_ = std::move(spec);
	if (!in_range(spec_.seed, 0, SimRng::MAX_SEED)) {
		errors.push_back("seed out of range");
	}
	if (!in_range(spec_.max_ticks, 1, MAX_TICKS)) {
		errors.push_back("max_ticks out of range");
	}
	for (size_t e = 0; e < config_.enemies.size(); e++) {
		const EnemyType &t = config_.enemies[e];
		if (!in_range(t.hp_x100, 1, MAX_STAT) || !in_range(t.armor, 0, MAX_STAT) || !in_range(t.shield_x100, 0, MAX_STAT) ||
				!in_range(t.speed_mtps, 1, MAX_STAT) || !in_range(t.leak_lives, 1, MAX_STAT)) {
			errors.push_back("enemy " + std::to_string(e) + ": a stat is out of range");
		}
	}
	for (size_t l = 0; l < spec_.lanes.size(); l++) {
		const LaneSpec &lane = spec_.lanes[l];
		if (!coords_ok(lane.ground) || (lane.air && !coords_ok(*lane.air))) {
			errors.push_back("lane " + std::to_string(l) + ": a path is missing points or out of bounds");
		}
	}
	int64_t total_spawns = 0;
	for (size_t g = 0; g < spec_.groups.size(); g++) {
		const SpawnGroup &group = spec_.groups[g];
		const std::string where = "group " + std::to_string(g);
		if (!in_range(group.enemy_index, 0, int64_t(config_.enemies.size()) - 1)) {
			errors.push_back(where + ": unknown enemy");
			continue;
		}
		if (!in_range(group.lane_index, 0, int64_t(spec_.lanes.size()) - 1)) {
			errors.push_back(where + ": unknown lane");
			continue;
		}
		if (!in_range(group.count, 1, SEQ_MASK) || !in_range(group.first_tick, 0, MAX_TICKS * 2) ||
				!in_range(group.interval_ticks, 0, MAX_TICKS) || !in_range(group.jitter_ticks, 0, MAX_TICKS)) {
			errors.push_back(where + ": a value is out of range");
			continue;
		}
		if (config_.enemies[group.enemy_index].air && !spec_.lanes[group.lane_index].air) {
			errors.push_back(where + ": air enemy needs an air route");
		}
		total_spawns += group.count;
	}
	if (total_spawns > SEQ_MASK) {
		errors.push_back("too many spawns: " + std::to_string(total_spawns));
	}
	if (!errors.empty()) {
		return false;
	}
	rng_.set_seed(spec_.seed);
	build_spawn_plan();
	ready_ = true;
	return true;
}

void Battle::advance() {
	if (!ready_ || outcome != RUNNING) {
		return;
	}
	spawn_due();
	entity_updates += int64_t(aliens.size());
	if (move_aliens()) {
		aliens.erase(std::remove_if(aliens.begin(), aliens.end(), [](const Alien &a) { return a.leaked; }), aliens.end());
	}
	tick += 1;
	if (tick % CHECKPOINT_TICKS == 0) {
		checkpoints.push_back(state_hash().substr(0, 16));
	}
	if (spawn_cursor_ >= spawn_keys_.size() && aliens.empty()) {
		outcome = CLEARED;
	} else if (tick >= spec_.max_ticks) {
		outcome = TIMED_OUT;
	}
}

void Battle::run() {
	while (ready_ && outcome == RUNNING) {
		advance();
	}
}

std::string Battle::state_hash() const {
	StateHasher h;
	h.add_int(SIM_VERSION);
	h.add_string(config_.config_hash);
	h.add_int(spec_.seed);
	h.add_int(tick);
	h.add_int(outcome);
	for (uint32_t word : rng_.state()) {
		h.add_int(word);
	}
	h.add_int(next_id_);
	h.add_int(int64_t(spawn_cursor_));
	h.add_int(spawned_count);
	h.add_int(leaked_count);
	h.add_int(leaked_lives);
	h.add_int(int64_t(aliens.size()));
	for (const Alien &a : aliens) {
		const Point pos = a.path->position_at(a.distance_mt);
		h.add_int(a.id);
		h.add_int(a.type_index);
		h.add_int(a.lane_index);
		h.add_int(a.air ? 1 : 0);
		h.add_int(a.distance_mt);
		h.add_int(a.move_accum);
		h.add_int(a.hp_x100);
		h.add_int(a.shield_x100);
		h.add_int(pos.x);
		h.add_int(pos.y);
	}
	return h.finish_hex();
}

// Spawn times are fixed at setup: groups in spec order, units in group order,
// each with its seeded jitter. Keys sort by tick, then by that order; every key
// is unique, so the sort has a single possible result.
void Battle::build_spawn_plan() {
	spawn_keys_.clear();
	spawn_group_.clear();
	int64_t seq = 0;
	for (size_t gi = 0; gi < spec_.groups.size(); gi++) {
		const SpawnGroup &g = spec_.groups[gi];
		for (int64_t n = 0; n < g.count; n++) {
			int64_t spawn_tick = g.first_tick + n * g.interval_ticks;
			if (g.jitter_ticks > 0) {
				spawn_tick += rng_.range_int(0, g.jitter_ticks);
			}
			spawn_keys_.push_back((spawn_tick << SEQ_BITS) | seq);
			spawn_group_.push_back(int64_t(gi));
			seq += 1;
		}
	}
	std::sort(spawn_keys_.begin(), spawn_keys_.end());
	spawn_cursor_ = 0;
}

void Battle::spawn_due() {
	while (spawn_cursor_ < spawn_keys_.size() && (spawn_keys_[spawn_cursor_] >> SEQ_BITS) <= tick) {
		const int64_t seq = spawn_keys_[spawn_cursor_] & SEQ_MASK;
		spawn(spec_.groups[size_t(spawn_group_[size_t(seq)])]);
		spawn_cursor_ += 1;
	}
}

void Battle::spawn(const SpawnGroup &group) {
	const EnemyType &type = config_.enemies[size_t(group.enemy_index)];
	const LaneSpec &lane = spec_.lanes[size_t(group.lane_index)];
	Alien a;
	a.id = next_id_++;
	a.type_index = group.enemy_index;
	a.lane_index = group.lane_index;
	a.air = type.air;
	a.path = type.air ? &*lane.air : &lane.ground;
	a.speed_mtps = type.speed_mtps;
	a.hp_x100 = type.hp_x100;
	a.shield_x100 = type.shield_x100;
	a.leak_lives = type.leak_lives;
	aliens.push_back(a);
	spawned_count += 1;
}

// Moves every alien in id order. Returns true if any reached the Core.
bool Battle::move_aliens() {
	bool any_leaked = false;
	for (Alien &a : aliens) {
		a.move_accum += a.speed_mtps;
		const int64_t step_mt = a.move_accum / TICK_RATE;
		a.move_accum -= step_mt * TICK_RATE;
		a.distance_mt += step_mt;
		if (a.distance_mt >= a.path->length) {
			a.distance_mt = a.path->length;
			a.leaked = true;
			leaked_count += 1;
			leaked_lives += a.leak_lives;
			any_leaked = true;
		}
	}
	return any_leaked;
}

} // namespace aetd::sim
