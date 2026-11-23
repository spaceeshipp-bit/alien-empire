#include "core/battle.h"

#include <algorithm>

#include "core/fx.h"
#include "core/state_hasher.h"

namespace aetd::sim {
namespace {

// 1,000 tiles, as battle_spec.gd allows: far beyond any map, and small enough
// that squared distances can't overflow.
constexpr int64_t MAX_COORD_MT = 1000000;
constexpr int64_t MAX_STAT = Battle::MAX_STAT;
constexpr int64_t MAX_TICKS = 72000;
// Multipliers in the damage pipeline stay at or below 10x, scaling factors for
// levels and waves at or below 100x, so no product can overflow (D-034).
constexpr int64_t MAX_MULT_BP = 100000;
constexpr int64_t MAX_SCALE_BP = 1000000;
constexpr int64_t MAX_TILE = 999;
constexpr int64_t MAX_BUILD_TILES = 4096;
constexpr int64_t MAX_LEVEL = 10;
constexpr int64_t MAX_TOWER_TYPES = 64;
constexpr int64_t MAX_COMMANDS = 100000;
constexpr int64_t MAX_RELEASE = 100;
// The grid has at most this many cells a side, and cells at least a tile wide.
constexpr int64_t GRID_SIDE = 64;
constexpr int64_t MIN_CELL_MT = 1000;

bool in_range(int64_t v, int64_t lo, int64_t hi) { return v >= lo && v <= hi; }

int64_t cap(int64_t v) { return std::min(v, MAX_STAT); }

bool coords_ok(const LanePath &path) {
	for (size_t i = 0; i < path.xs.size(); i++) {
		if (!in_range(path.xs[i], 0, MAX_COORD_MT) || !in_range(path.ys[i], 0, MAX_COORD_MT)) {
			return false;
		}
	}
	return path.xs.size() >= 2;
}

bool within(int64_t x0, int64_t y0, int64_t x1, int64_t y1, int64_t radius) {
	const int64_t dx = x1 - x0;
	const int64_t dy = y1 - y0;
	return dx * dx + dy * dy <= radius * radius;
}

int64_t tile_key(int64_t col, int64_t row) { return row * (MAX_TILE + 1) + col; }

} // namespace

void Battle::reset() {
	tick = 0;
	outcome = RUNNING;
	aliens.clear();
	towers.clear();
	spawned_count = 0;
	leaked_count = 0;
	leaked_lives = 0;
	lives = 0;
	credits_x100 = 0;
	kills = 0;
	refused_commands = 0;
	wave_starts.clear();
	wave_pending.clear();
	wave_leaked.clear();
	wave_done.clear();
	releases_.clear();
	checkpoints.clear();
	errors.clear();
	events.clear();
	entity_updates = 0;
	config_ = BattleConfig();
	spec_ = BattleSpec();
	rng_ = SimRng();
	next_id_ = 1;
	next_tower_id_ = 1;
	spawn_keys_.clear();
	spawn_group_.clear();
	spawn_cursor_ = 0;
	command_cursor_ = 0;
	ready_ = false;
	tile_tower_.clear();
	tile_lookup_.clear();
	allowed_.clear();
	grid_.clear();
	grid_tick_ = -1;
	found_.clear();
}

bool Battle::setup(BattleConfig config, BattleSpec spec) {
	// Aliens point into spec_'s lanes, so they go before the lanes are replaced.
	reset();
	config_ = std::move(config);
	spec_ = std::move(spec);
	// Commands go through queue_command below, with the same checks as live ones.
	std::vector<Command> commands = std::move(spec_.commands);
	spec_.commands.clear();
	if (!in_range(spec_.seed, 0, SimRng::MAX_SEED)) {
		errors.push_back("seed out of range");
	}
	if (!in_range(spec_.max_ticks, 1, MAX_TICKS)) {
		errors.push_back("max_ticks out of range");
	}
	if (!in_range(spec_.lives, 1, MAX_STAT) || !in_range(spec_.credits, 0, MAX_STAT) ||
			!in_range(spec_.call_credits_per_s, 0, MAX_STAT) || !in_range(spec_.call_credits_max, 0, MAX_STAT) ||
			!in_range(spec_.clean_wave_credits, 0, MAX_STAT)) {
		errors.push_back("lives or credits out of range");
	}
	if (int64_t(spec_.wave_starts.size()) > SEQ_MASK) {
		errors.push_back("too many waves");
	}
	for (size_t w = 0; w < spec_.wave_starts.size(); w++) {
		if (!in_range(spec_.wave_starts[w], 0, MAX_TICKS * 2)) {
			errors.push_back("wave " + std::to_string(w) + ": start out of range");
		}
	}
	for (size_t e = 0; e < config_.enemies.size(); e++) {
		const EnemyType &t = config_.enemies[e];
		if (!in_range(t.hp_x100, 1, MAX_STAT) || !in_range(t.armor, 0, MAX_STAT) || !in_range(t.shield_x100, 0, MAX_STAT) ||
				!in_range(t.speed_mtps, 1, MAX_STAT) || !in_range(t.leak_lives, 1, MAX_STAT) ||
				!in_range(t.class_index, 0, int64_t(CLASS_COUNT) - 1) || !in_range(t.kill_credits_x100, 0, MAX_STAT)) {
			errors.push_back("enemy " + std::to_string(e) + ": a stat is out of range");
		}
		if (t.release_index != -1) {
			if (!in_range(t.release_index, 0, int64_t(config_.enemies.size()) - 1) || !in_range(t.release_count, 1, MAX_RELEASE)) {
				errors.push_back("enemy " + std::to_string(e) + ": releases an unknown enemy or too many");
			} else if (config_.enemies[size_t(t.release_index)].air != t.air) {
				errors.push_back("enemy " + std::to_string(e) + ": releases an enemy that moves differently");
			} else if (config_.enemies[size_t(t.release_index)].release_index != -1) {
				// One level only: chains could multiply aliens without limit.
				errors.push_back("enemy " + std::to_string(e) + ": releases an enemy that releases others");
			}
		}
	}
	if (int64_t(config_.towers.size()) > MAX_TOWER_TYPES) {
		errors.push_back("too many tower types");
	}
	for (size_t t = 0; t < config_.towers.size(); t++) {
		const TowerType &type = config_.towers[t];
		bool ok = in_range(type.targeting, TARGET_FIRST, TARGET_STRONGEST) &&
				in_range(type.cost_credits, 1, MAX_STAT) && in_range(type.damage_x100, 0, MAX_STAT) &&
				in_range(type.shots_per_s_x100, 0, MAX_STAT) && in_range(type.range_mt, 0, MAX_STAT) &&
				in_range(type.splash_mt, 0, MAX_STAT) && in_range(type.shield_mult_bp, 1, MAX_MULT_BP) &&
				in_range(type.pierce_bp, 0, 10000) && in_range(type.unrevealed_bp, 0, MAX_MULT_BP);
		for (int64_t rating : type.rating_bp) {
			ok = ok && in_range(rating, 0, MAX_MULT_BP);
		}
		if (!ok) {
			errors.push_back("tower " + std::to_string(t) + ": a stat is out of range");
		}
	}
	const FieldUpgrades &u = config_.upgrades;
	if (!in_range(u.max_level, 1, MAX_LEVEL) || !in_range(u.first_upgrade_cost_bp, 0, MAX_SCALE_BP) ||
			!in_range(u.cost_growth_bp, 0, MAX_SCALE_BP) || !in_range(u.damage_growth_bp, 0, MAX_SCALE_BP) ||
			!in_range(u.range_step_bp, 0, MAX_SCALE_BP) || !in_range(u.sell_refund_bp, 0, 10000)) {
		errors.push_back("field upgrades: a value is out of range");
	}
	const DamageRules &d = config_.damage;
	if (!in_range(d.armor_constant, 1, MAX_STAT) || !in_range(d.max_reduction_bp, 0, 10000) ||
			!in_range(d.min_damage_x100, 0, MAX_STAT)) {
		errors.push_back("damage rules: a value is out of range");
	}
	if (!in_range(config_.regen_per_second_x100, 0, MAX_STAT) || !in_range(config_.regen_delay_ticks, 0, MAX_TICKS) ||
			!in_range(config_.retarget_ticks, 1, MAX_TICKS)) {
		errors.push_back("shield regen or retarget time out of range");
	}
	allowed_.assign(config_.towers.size(), false);
	for (int64_t index : spec_.tower_set) {
		if (!in_range(index, 0, int64_t(config_.towers.size()) - 1)) {
			errors.push_back("tower set: unknown tower");
		} else if (allowed_[size_t(index)]) {
			errors.push_back("tower set: tower " + std::to_string(index) + " is listed twice");
		} else if (!config_.towers[size_t(index)].supported) {
			errors.push_back("tower set: tower " + std::to_string(index) + " has an ability this sim version doesn't run");
		} else {
			allowed_[size_t(index)] = true;
		}
	}
	if (int64_t(spec_.build_tiles.size()) > MAX_BUILD_TILES) {
		errors.push_back("too many build tiles");
	}
	for (size_t i = 0; i < spec_.build_tiles.size(); i++) {
		const BuildTile &tile = spec_.build_tiles[i];
		if (!in_range(tile.col, 0, MAX_TILE) || !in_range(tile.row, 0, MAX_TILE)) {
			errors.push_back("build tile " + std::to_string(i) + ": out of range");
			continue;
		}
		tile_lookup_.emplace_back(tile_key(tile.col, tile.row), int64_t(i));
	}
	std::sort(tile_lookup_.begin(), tile_lookup_.end());
	for (size_t i = 1; i < tile_lookup_.size(); i++) {
		if (tile_lookup_[i].first == tile_lookup_[i - 1].first) {
			errors.push_back("build tile " + std::to_string(tile_lookup_[i].second) + ": listed twice");
		}
	}
	for (size_t l = 0; l < spec_.lanes.size(); l++) {
		const LaneSpec &lane = spec_.lanes[l];
		if (!coords_ok(lane.ground) || (lane.air && !coords_ok(*lane.air))) {
			errors.push_back("lane " + std::to_string(l) + ": a path is missing points or out of bounds");
		}
	}
	int64_t total_spawns = 0;
	std::vector<int64_t> wave_groups(spec_.wave_starts.size(), 0);
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
		if (!in_range(group.wave_index, 0, int64_t(spec_.wave_starts.size()) - 1)) {
			errors.push_back(where + ": unknown wave");
			continue;
		}
		if (group.first_tick < spec_.wave_starts[size_t(group.wave_index)]) {
			errors.push_back(where + ": starts before its wave");
		}
		wave_groups[size_t(group.wave_index)] += 1;
		if (!in_range(group.count, 1, SEQ_MASK) || !in_range(group.first_tick, 0, MAX_TICKS * 2) ||
				!in_range(group.interval_ticks, 0, MAX_TICKS) || !in_range(group.jitter_ticks, 0, MAX_TICKS) ||
				!in_range(group.hp_bp, 1, MAX_SCALE_BP) || !in_range(group.credits_bp, 0, MAX_SCALE_BP)) {
			errors.push_back(where + ": a value is out of range");
			continue;
		}
		if (config_.enemies[group.enemy_index].air && !spec_.lanes[group.lane_index].air) {
			errors.push_back(where + ": air enemy needs an air route");
		}
		const EnemyType &type = config_.enemies[group.enemy_index];
		const bool releases = in_range(type.release_index, 0, int64_t(config_.enemies.size()) - 1);
		if (!type.supported || (releases && !config_.enemies[size_t(type.release_index)].supported)) {
			errors.push_back(where + ": enemy has an ability this sim version doesn't run");
		}
		// Every alien it could ever release counts against the limit too.
		total_spawns += group.count * (1 + (releases ? std::min(type.release_count, MAX_RELEASE) : 0));
	}
	if (total_spawns > SEQ_MASK) {
		errors.push_back("too many spawns: " + std::to_string(total_spawns));
	}
	for (size_t w = 0; w < wave_groups.size(); w++) {
		if (wave_groups[w] == 0) {
			errors.push_back("wave " + std::to_string(w) + ": has no group");
		}
	}
	if (int64_t(commands.size()) > MAX_COMMANDS) {
		errors.push_back("too many commands");
	}
	if (!errors.empty()) {
		reset_after_errors();
		return false;
	}
	rng_.set_seed(spec_.seed);
	lives = spec_.lives;
	credits_x100 = spec_.credits * 100;
	tile_tower_.assign(spec_.build_tiles.size(), 0);
	wave_starts = spec_.wave_starts;
	wave_pending.assign(wave_starts.size(), 0);
	wave_leaked.assign(wave_starts.size(), 0);
	wave_done.assign(wave_starts.size(), 0);
	for (const SpawnGroup &group : spec_.groups) {
		wave_pending[size_t(group.wave_index)] += group.count;
	}
	set_up_grid();
	build_spawn_plan();
	ready_ = true;
	for (size_t i = 0; i < commands.size(); i++) {
		const std::string problem = queue_command(commands[i]);
		if (!problem.empty()) {
			errors.push_back("command " + std::to_string(i) + ": " + problem);
		}
	}
	if (!errors.empty()) {
		reset_after_errors();
		return false;
	}
	return true;
}

void Battle::reset_after_errors() {
	std::vector<std::string> kept = std::move(errors);
	reset();
	errors = std::move(kept);
}

std::string Battle::queue_command(const Command &command) {
	if (!ready_) {
		return "the battle isn't set up";
	}
	if (outcome != RUNNING) {
		return "the battle is over";
	}
	const int64_t earliest = spec_.commands.empty() ? tick : std::max(tick, spec_.commands.back().tick);
	if (!in_range(command.tick, earliest, spec_.max_ticks - 1)) {
		return "tick " + std::to_string(command.tick) + " is before tick " + std::to_string(earliest) +
				" or at or after the last tick";
	}
	if (int64_t(spec_.commands.size()) >= MAX_COMMANDS) {
		return "too many commands";
	}
	if (command.kind == CALL_WAVE) {
		if (command.tower_index != -1 || command.col != 0 || command.row != 0) {
			return "call_wave takes no tower or tile";
		}
		spec_.commands.push_back(command);
		return "";
	}
	if (tile_index(command.col, command.row) < 0) {
		return "not a build tile";
	}
	if (command.kind == PLACE) {
		if (!in_range(command.tower_index, 0, int64_t(config_.towers.size()) - 1) || !allowed_[size_t(command.tower_index)]) {
			return "that tower can't be built in this battle";
		}
	} else if (command.kind == UPGRADE || command.kind == SELL) {
		if (command.tower_index != -1) {
			return "upgrade and sell don't name a tower type";
		}
	} else {
		return "unknown command";
	}
	spec_.commands.push_back(command);
	return "";
}

void Battle::advance() {
	if (!ready_ || outcome != RUNNING) {
		return;
	}
	events.clear();
	apply_commands();
	spawn_due();
	entity_updates += int64_t(aliens.size());
	if (move_aliens()) {
		aliens.erase(std::remove_if(aliens.begin(), aliens.end(), [](const Alien &a) { return a.leaked; }), aliens.end());
	}
	regenerate_shields();
	const int64_t kills_before = kills;
	towers_act();
	if (kills != kills_before) {
		release();
		aliens.erase(std::remove_if(aliens.begin(), aliens.end(), [](const Alien &a) { return a.dead; }), aliens.end());
	}
	finish_waves();
	tick += 1;
	if (tick % CHECKPOINT_TICKS == 0) {
		checkpoints.push_back(state_hash().substr(0, 16));
	}
	if (lives <= 0) {
		outcome = LOST;
	} else if (spawn_cursor_ >= spawn_keys_.size() && aliens.empty()) {
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
	h.add_int(lives);
	h.add_int(credits_x100);
	h.add_int(kills);
	h.add_int(refused_commands);
	h.add_int(int64_t(command_cursor_));
	h.add_int(next_tower_id_);
	h.add_int(int64_t(towers.size()));
	for (const Tower &t : towers) {
		h.add_int(t.id);
		h.add_int(t.type_index);
		h.add_int(t.level);
		h.add_int(t.col);
		h.add_int(t.row);
		h.add_int(t.charge);
		h.add_int(t.target_id);
		h.add_int(t.next_pick_tick);
		h.add_int(t.spent_x100);
	}
	h.add_int(int64_t(aliens.size()));
	for (const Alien &a : aliens) {
		h.add_int(a.id);
		h.add_int(a.type_index);
		h.add_int(a.lane_index);
		h.add_int(a.air ? 1 : 0);
		h.add_int(a.distance_mt);
		h.add_int(a.move_accum);
		h.add_int(a.hp_x100);
		h.add_int(a.shield_x100);
		h.add_int(a.x);
		h.add_int(a.y);
		h.add_int(a.regen_accum);
		h.add_int(a.last_hit_tick);
		h.add_int(a.kill_credits_x100);
		h.add_int(a.hp_bp);
		h.add_int(a.credits_bp);
		h.add_int(a.wave_index);
	}
	h.add_int(int64_t(wave_starts.size()));
	for (size_t w = 0; w < wave_starts.size(); w++) {
		h.add_int(wave_starts[w]);
		h.add_int(wave_pending[w]);
		h.add_int(wave_leaked[w]);
		h.add_int(wave_done[w]);
	}
	return h.finish_hex();
}

int64_t Battle::upgrade_cost_x100(int64_t type_index, int64_t level) const {
	const FieldUpgrades &u = config_.upgrades;
	int64_t cost = std::min(config_.towers[size_t(type_index)].cost_credits * 100 * u.first_upgrade_cost_bp / 10000, MAX_STAT * 100);
	for (int64_t l = 1; l < level; l++) {
		cost = std::min(cost * u.cost_growth_bp / 10000, MAX_STAT * 100);
	}
	return cost;
}

int64_t Battle::refund_x100(const Tower &tower) const {
	return tower.spent_x100 * config_.upgrades.sell_refund_bp / 10000;
}

const Tower *Battle::tower_at(int64_t col, int64_t row) const {
	const int64_t index = tile_index(col, row);
	if (index < 0 || tile_tower_.empty() || tile_tower_[size_t(index)] == 0) {
		return nullptr;
	}
	const int64_t id = tile_tower_[size_t(index)];
	const auto it = std::lower_bound(towers.begin(), towers.end(), id, [](const Tower &t, int64_t v) { return t.id < v; });
	return it != towers.end() && it->id == id ? &*it : nullptr;
}

int64_t Battle::tile_index(int64_t col, int64_t row) const {
	if (!in_range(col, 0, MAX_TILE) || !in_range(row, 0, MAX_TILE)) {
		return -1;
	}
	const std::pair<int64_t, int64_t> key(tile_key(col, row), -1);
	const auto it = std::lower_bound(tile_lookup_.begin(), tile_lookup_.end(), key);
	return it != tile_lookup_.end() && it->first == key.first ? it->second : -1;
}

int64_t Battle::level_damage(int64_t type_index, int64_t level) const {
	int64_t damage = config_.towers[size_t(type_index)].damage_x100;
	for (int64_t l = 1; l < level; l++) {
		damage = cap(damage * config_.upgrades.damage_growth_bp / 10000);
	}
	return damage;
}

int64_t Battle::level_range(int64_t type_index, int64_t level) const {
	const int64_t base = config_.towers[size_t(type_index)].range_mt;
	return cap(base * (10000 + config_.upgrades.range_step_bp * (level - 1)) / 10000);
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
	add_alien(group.enemy_index, group.lane_index, group.hp_bp, group.credits_bp, 0, group.wave_index);
}

void Battle::add_alien(int64_t enemy_index, int64_t lane_index, int64_t hp_bp, int64_t credits_bp, int64_t distance_mt,
		int64_t wave_index) {
	const EnemyType &type = config_.enemies[size_t(enemy_index)];
	const LaneSpec &lane = spec_.lanes[size_t(lane_index)];
	Alien a;
	a.id = next_id_++;
	a.type_index = enemy_index;
	a.lane_index = lane_index;
	a.class_index = type.class_index;
	a.air = type.air;
	a.path = type.air ? &*lane.air : &lane.ground;
	a.distance_mt = distance_mt;
	a.speed_mtps = type.speed_mtps;
	a.hp_x100 = std::max<int64_t>(1, cap(type.hp_x100 * hp_bp / 10000));
	a.max_hp_x100 = a.hp_x100;
	a.shield_x100 = type.shield_x100;
	a.max_shield_x100 = type.shield_x100;
	a.last_hit_tick = tick;
	a.leak_lives = type.leak_lives;
	a.kill_credits_x100 = cap(type.kill_credits_x100 * credits_bp / 10000);
	a.hp_bp = hp_bp;
	a.credits_bp = credits_bp;
	a.wave_index = wave_index;
	const Point p = a.path->position_at(a.distance_mt);
	a.x = p.x;
	a.y = p.y;
	aliens.push_back(a);
	spawned_count += 1;
}

// Aliens released by the ones killed this tick join after every tower has
// acted, in order of death, where each fell. They move from the next tick.
void Battle::release() {
	for (int64_t id : releases_) {
		const Alien *dead = find_alien(id);
		const EnemyType &type = config_.enemies[size_t(dead->type_index)];
		const Alien copy = *dead;  // add_alien may move the aliens vector
		for (int64_t n = 0; n < type.release_count; n++) {
			add_alien(type.release_index, copy.lane_index, copy.hp_bp, copy.credits_bp, copy.distance_mt, copy.wave_index);
		}
		wave_pending[size_t(copy.wave_index)] += type.release_count;
	}
	releases_.clear();
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
			lives = std::max<int64_t>(0, lives - a.leak_lives);
			wave_pending[size_t(a.wave_index)] -= 1;
			wave_leaked[size_t(a.wave_index)] = 1;
			any_leaked = true;
		}
		const Point p = a.path->position_at(a.distance_mt);
		a.x = p.x;
		a.y = p.y;
		if (a.leaked) {
			events.push_back({ LEAK, a.id, 0, a.x, a.y });
		}
	}
	return any_leaked;
}

void Battle::regenerate_shields() {
	if (config_.regen_per_second_x100 == 0) {
		return;
	}
	for (Alien &a : aliens) {
		if (a.shield_x100 >= a.max_shield_x100 || tick - a.last_hit_tick < config_.regen_delay_ticks) {
			continue;
		}
		a.regen_accum += config_.regen_per_second_x100;
		const int64_t gain = a.regen_accum / TICK_RATE;
		a.regen_accum -= gain * TICK_RATE;
		a.shield_x100 += gain;
		if (a.shield_x100 >= a.max_shield_x100) {
			a.shield_x100 = a.max_shield_x100;
			a.regen_accum = 0;
		}
	}
}

void Battle::apply_commands() {
	while (command_cursor_ < spec_.commands.size() && spec_.commands[command_cursor_].tick == tick) {
		apply(spec_.commands[command_cursor_], int64_t(command_cursor_));
		command_cursor_ += 1;
	}
}

void Battle::apply(const Command &command, int64_t index) {
	if (command.kind == CALL_WAVE) {
		call_wave(index);
		return;
	}
	const int64_t tile = tile_index(command.col, command.row);
	int64_t &occupant = tile_tower_[size_t(tile)];
	const auto refuse = [&]() {
		refused_commands += 1;
		events.push_back({ REFUSED, index, 0, command.col * 1000 + 500, command.row * 1000 + 500 });
	};
	if (command.kind == PLACE) {
		const int64_t cost = config_.towers[size_t(command.tower_index)].cost_credits * 100;
		if (occupant != 0 || credits_x100 < cost) {
			refuse();
			return;
		}
		Tower t;
		t.id = next_tower_id_++;
		t.type_index = command.tower_index;
		t.col = command.col;
		t.row = command.row;
		t.x = command.col * 1000 + 500;
		t.y = command.row * 1000 + 500;
		t.charge = SHOT_CHARGE;
		t.spent_x100 = cost;
		t.damage_x100 = level_damage(t.type_index, 1);
		t.range_mt = level_range(t.type_index, 1);
		credits_x100 -= cost;
		occupant = t.id;
		towers.push_back(t);
		events.push_back({ PLACED, t.id, 0, t.x, t.y });
		return;
	}
	auto it = std::lower_bound(towers.begin(), towers.end(), occupant, [](const Tower &t, int64_t v) { return t.id < v; });
	if (occupant == 0 || it == towers.end() || it->id != occupant) {
		refuse();
		return;
	}
	if (command.kind == UPGRADE) {
		if (it->level >= config_.upgrades.max_level) {
			refuse();
			return;
		}
		const int64_t cost = upgrade_cost_x100(it->type_index, it->level);
		if (credits_x100 < cost) {
			refuse();
			return;
		}
		credits_x100 -= cost;
		it->spent_x100 += cost;
		it->level += 1;
		it->damage_x100 = level_damage(it->type_index, it->level);
		it->range_mt = level_range(it->type_index, it->level);
		events.push_back({ UPGRADED, it->id, 0, it->x, it->y });
		return;
	}
	credits_x100 += refund_x100(*it);
	events.push_back({ SOLD, it->id, 0, it->x, it->y });
	towers.erase(it);
	occupant = 0;
}

// Brings the next wave (the earliest that hasn't started; ties to the lower
// index) in now. Every wave that hasn't started moves earlier by the same
// amount, with its spawns, so the later waves keep their spacing; waves that
// shared its start come in with it, and the CALLED event names the lowest
// index. The player is paid call_credits_per_s for each second skipped, up to
// call_credits_max.
void Battle::call_wave(int64_t index) {
	int64_t next = -1;
	for (size_t w = 0; w < wave_starts.size(); w++) {
		if (wave_starts[w] > tick && (next < 0 || wave_starts[w] < wave_starts[size_t(next)])) {
			next = int64_t(w);
		}
	}
	if (next < 0) {
		refused_commands += 1;
		events.push_back({ REFUSED, index, 0, 0, 0 });
		return;
	}
	const int64_t skip = wave_starts[size_t(next)] - tick;
	std::vector<bool> moves(wave_starts.size(), false);
	for (size_t w = 0; w < wave_starts.size(); w++) {
		if (wave_starts[w] > tick) {
			moves[w] = true;
			wave_starts[w] -= skip;
		}
	}
	for (size_t i = spawn_cursor_; i < spawn_keys_.size(); i++) {
		const int64_t seq = spawn_keys_[i] & SEQ_MASK;
		const SpawnGroup &group = spec_.groups[size_t(spawn_group_[size_t(seq)])];
		if (moves[size_t(group.wave_index)]) {
			spawn_keys_[i] -= skip << SEQ_BITS;
		}
	}
	// Keys stay unique (each carries its plan position), so the order is unique.
	std::sort(spawn_keys_.begin() + int64_t(spawn_cursor_), spawn_keys_.end());
	const int64_t bonus = std::min(skip * spec_.call_credits_per_s * 100 / TICK_RATE, spec_.call_credits_max * 100);
	credits_x100 += bonus;
	events.push_back({ CALLED, next, bonus, 0, 0 });
}

// A wave is done when every alien it planned has spawned and every one of
// them (and any they released) has died or leaked. If none leaked, it pays the
// clean-wave bonus. A wave can finish before an earlier one; waves that finish
// on the same tick do so in index order.
void Battle::finish_waves() {
	for (size_t w = 0; w < wave_pending.size(); w++) {
		if (wave_done[w] != 0 || wave_pending[w] != 0) {
			continue;
		}
		wave_done[w] = 1;
		const bool clean = wave_leaked[w] == 0;
		if (clean) {
			credits_x100 += spec_.clean_wave_credits * 100;
		}
		events.push_back({ WAVE_DONE, int64_t(w), clean ? 1 : 0, 0, 0 });
	}
}

void Battle::set_up_grid() {
	bool first = true;
	for (const LaneSpec &lane : spec_.lanes) {
		for (const LanePath *path : { &lane.ground, lane.air ? &*lane.air : nullptr }) {
			if (path == nullptr) {
				continue;
			}
			for (size_t i = 0; i < path->xs.size(); i++) {
				if (first) {
					grid_min_x_ = grid_max_x_ = path->xs[i];
					grid_min_y_ = grid_max_y_ = path->ys[i];
					first = false;
				}
				grid_min_x_ = std::min(grid_min_x_, path->xs[i]);
				grid_max_x_ = std::max(grid_max_x_, path->xs[i]);
				grid_min_y_ = std::min(grid_min_y_, path->ys[i]);
				grid_max_y_ = std::max(grid_max_y_, path->ys[i]);
			}
		}
	}
	const int64_t span = std::max(grid_max_x_ - grid_min_x_, grid_max_y_ - grid_min_y_) + 1;
	grid_cell_ = std::max(MIN_CELL_MT, (span + GRID_SIDE - 1) / GRID_SIDE);
	grid_cols_ = (grid_max_x_ - grid_min_x_) / grid_cell_ + 1;
	grid_rows_ = (grid_max_y_ - grid_min_y_) / grid_cell_ + 1;
	grid_.assign(size_t(grid_cols_ * grid_rows_), {});
	grid_tick_ = -1;
}

void Battle::fill_grid() {
	for (auto &cell : grid_) {
		cell.clear();
	}
	for (size_t i = 0; i < aliens.size(); i++) {
		const Alien &a = aliens[i];
		if (a.dead) {
			continue;
		}
		const int64_t cx = std::clamp((a.x - grid_min_x_) / grid_cell_, int64_t(0), grid_cols_ - 1);
		const int64_t cy = std::clamp((a.y - grid_min_y_) / grid_cell_, int64_t(0), grid_rows_ - 1);
		grid_[size_t(cy * grid_cols_ + cx)].push_back(int32_t(i));
	}
	grid_tick_ = tick;
}

// Alien indices in every cell that meets the square around (x, y), in no
// particular order: callers check the exact distance.
void Battle::search(int64_t x, int64_t y, int64_t radius) {
	found_.clear();
	if (grid_tick_ != tick) {
		fill_grid();
	}
	const int64_t x0 = std::max(x - radius, grid_min_x_);
	const int64_t x1 = std::min(x + radius, grid_max_x_);
	const int64_t y0 = std::max(y - radius, grid_min_y_);
	const int64_t y1 = std::min(y + radius, grid_max_y_);
	if (x0 > x1 || y0 > y1) {
		return;
	}
	const int64_t cx0 = (x0 - grid_min_x_) / grid_cell_;
	const int64_t cx1 = (x1 - grid_min_x_) / grid_cell_;
	const int64_t cy0 = (y0 - grid_min_y_) / grid_cell_;
	const int64_t cy1 = (y1 - grid_min_y_) / grid_cell_;
	for (int64_t cy = cy0; cy <= cy1; cy++) {
		for (int64_t cx = cx0; cx <= cx1; cx++) {
			const auto &cell = grid_[size_t(cy * grid_cols_ + cx)];
			found_.insert(found_.end(), cell.begin(), cell.end());
		}
	}
}

Alien *Battle::find_alien(int64_t id) {
	auto it = std::lower_bound(aliens.begin(), aliens.end(), id, [](const Alien &a, int64_t v) { return a.id < v; });
	return it != aliens.end() && it->id == id ? &*it : nullptr;
}

// Nothing reveals a cloaked alien in this sim version (D-034).
bool Battle::can_hit(const TowerType &type, const Alien &alien) const {
	return type.rating_bp[size_t(alien.class_index)] > 0 && (alien.class_index != CLOAKED || type.unrevealed_bp > 0);
}

// "First": the hittable alien in range with the least distance left to the
// Core, ties to the lower id. "Strongest": the toughest kind, by full HP plus
// full shield (the wave's HP growth counts), ties to the least distance left,
// then the lower id. Full values, not what's left, so a tower finishes the alien
// it started on instead of spreading its shots across a pack.
Alien *Battle::pick_target(const Tower &tower, const TowerType &type) {
	search(tower.x, tower.y, tower.range_mt);
	Alien *best = nullptr;
	int64_t best_left = 0;
	int64_t best_toughness = 0;
	for (int32_t index : found_) {
		Alien &a = aliens[size_t(index)];
		if (a.dead || !can_hit(type, a) || !within(tower.x, tower.y, a.x, a.y, tower.range_mt)) {
			continue;
		}
		const int64_t left = a.path->length - a.distance_mt;
		const int64_t toughness = a.max_hp_x100 + a.max_shield_x100;
		bool better = best == nullptr;
		if (!better && type.targeting == TARGET_STRONGEST && toughness != best_toughness) {
			better = toughness > best_toughness;
		} else if (!better) {
			better = left < best_left || (left == best_left && a.id < best->id);
		}
		if (better) {
			best = &a;
			best_left = left;
			best_toughness = toughness;
		}
	}
	return best;
}

void Battle::towers_act() {
	for (Tower &t : towers) {
		const TowerType &type = config_.towers[size_t(t.type_index)];
		if (t.charge >= SHOT_CHARGE) {
			Alien *target = nullptr;
			if (t.target_id != 0 && tick < t.next_pick_tick) {
				Alien *a = find_alien(t.target_id);
				if (a != nullptr && !a->dead && can_hit(type, *a) && within(t.x, t.y, a->x, a->y, t.range_mt)) {
					target = a;
				}
			}
			if (target == nullptr) {
				target = pick_target(t, type);
				t.next_pick_tick = tick + config_.retarget_ticks;
				t.target_id = target != nullptr ? target->id : 0;
			}
			if (target != nullptr) {
				t.charge -= SHOT_CHARGE;
				fire(t, type, *target);
			}
		}
		t.charge = std::min(t.charge + type.shots_per_s_x100, SHOT_CHARGE);
	}
}

void Battle::fire(const Tower &tower, const TowerType &type, Alien &target) {
	events.push_back({ SHOT, tower.id, target.id, target.x, target.y });
	if (type.splash_mt == 0) {
		hit(tower, type, target);
		return;
	}
	const int64_t x = target.x;
	const int64_t y = target.y;
	search(x, y, type.splash_mt);
	// Alien indices follow id order, so sorting them puts the hits in id order.
	std::sort(found_.begin(), found_.end());
	for (int32_t index : found_) {
		Alien &a = aliens[size_t(index)];
		if (!a.dead && can_hit(type, a) && within(x, y, a.x, a.y, type.splash_mt)) {
			hit(tower, type, a);
		}
	}
}

// The damage pipeline (build prompt steps 1, 3, 5, 6 and 7; D-034).
void Battle::hit(const Tower &tower, const TowerType &type, Alien &alien) {
	int64_t damage = tower.damage_x100 * type.rating_bp[size_t(alien.class_index)] / 10000;
	if (alien.class_index == CLOAKED) {
		damage = damage * type.unrevealed_bp / 10000;
	}
	alien.last_hit_tick = tick;
	alien.regen_accum = 0;
	const DamageRules &rules = config_.damage;
	if (alien.shield_x100 > 0) {
		const int64_t on_shield = damage * type.shield_mult_bp / 10000;
		if (on_shield < alien.shield_x100) {
			alien.shield_x100 = std::max<int64_t>(0, alien.shield_x100 - std::max(on_shield, rules.min_damage_x100));
			return;
		}
		const int64_t excess = on_shield - alien.shield_x100;
		alien.shield_x100 = 0;
		damage = excess * 10000 / type.shield_mult_bp;
		if (damage <= 0) {
			return;
		}
	}
	const int64_t armor = config_.enemies[size_t(alien.type_index)].armor * (10000 - type.pierce_bp) / 10000;
	const int64_t reduction = std::min(armor * 10000 / (armor + rules.armor_constant), rules.max_reduction_bp);
	const int64_t hull = std::max(damage * (10000 - reduction) / 10000, rules.min_damage_x100);
	alien.hp_x100 -= hull;
	if (alien.hp_x100 <= 0) {
		alien.dead = true;
		credits_x100 += alien.kill_credits_x100;
		kills += 1;
		wave_pending[size_t(alien.wave_index)] -= 1;
		events.push_back({ KILL, alien.id, tower.id, alien.x, alien.y });
		if (config_.enemies[size_t(alien.type_index)].release_index >= 0) {
			releases_.push_back(alien.id);
		}
	}
}

} // namespace aetd::sim
