#include "godot/bindings.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

#include "core/fx.h"

using namespace godot;

namespace aetd {
namespace {

// Copy-initialization: godot-cpp's builtin types have several non-explicit
// constructors a Variant converts to, so a direct cast would be ambiguous.
template <typename T>
T as(const Variant &value) {
	T out = value;
	return out;
}

std::string to_std(const String &text) {
	const CharString utf8 = text.utf8();
	return std::string(utf8.get_data(), size_t(utf8.length()));
}

String to_godot(const std::string &text) {
	return String::utf8(text.c_str(), int64_t(text.size()));
}

std::vector<int64_t> to_vector(const PackedInt64Array &values) {
	std::vector<int64_t> out(size_t(values.size()));
	for (int64_t i = 0; i < values.size(); i++) {
		out[size_t(i)] = values[i];
	}
	return out;
}

PackedInt64Array to_packed(const std::vector<int64_t> &values) {
	PackedInt64Array out;
	out.resize(int64_t(values.size()));
	for (size_t i = 0; i < values.size(); i++) {
		out.set(int64_t(i), values[i]);
	}
	return out;
}

// Reads the plain Dictionaries sim/core/battle.gd builds. A wrong type is a bug
// in that script, so the messages name the field rather than explain it.
struct Reader {
	std::vector<std::string> &errors;

	bool has(const Dictionary &d, const char *key, Variant::Type type, const std::string &where) {
		if (!d.has(key) || d[key].get_type() != type) {
			errors.push_back(where + "." + key + ": missing or of the wrong type");
			return false;
		}
		return true;
	}
	int64_t get_int(const Dictionary &d, const char *key, const std::string &where) {
		return has(d, key, Variant::INT, where) ? as<int64_t>(d[key]) : 0;
	}
	bool get_bool(const Dictionary &d, const char *key, const std::string &where) {
		return has(d, key, Variant::BOOL, where) ? as<bool>(d[key]) : false;
	}
	std::string get_string(const Dictionary &d, const char *key, const std::string &where) {
		return has(d, key, Variant::STRING, where) ? to_std(as<String>(d[key])) : std::string();
	}
	Array get_array(const Dictionary &d, const char *key, const std::string &where) {
		return has(d, key, Variant::ARRAY, where) ? as<Array>(d[key]) : Array();
	}
	PackedInt64Array get_ints(const Dictionary &d, const char *key, const std::string &where) {
		return has(d, key, Variant::PACKED_INT64_ARRAY, where) ? as<PackedInt64Array>(d[key]) : PackedInt64Array();
	}
	Dictionary item(const Array &list, int64_t i, const std::string &where) {
		if (list[i].get_type() != Variant::DICTIONARY) {
			errors.push_back(where + "[" + std::to_string(i) + "]: expected a Dictionary");
			return Dictionary();
		}
		return as<Dictionary>(list[i]);
	}
	void path(sim::LanePath &out, const Dictionary &d, const char *x_key, const char *y_key, const std::string &where) {
		const std::string problem = out.build(to_vector(get_ints(d, x_key, where)), to_vector(get_ints(d, y_key, where)));
		if (!problem.empty()) {
			errors.push_back(where + ": " + problem);
		}
	}
};

const char *OUTCOME_NAMES[] = { "running", "cleared", "timed_out" };

} // namespace

// SimNative ------------------------------------------------------------------

void SimNative::_bind_methods() {
	ClassDB::bind_static_method("SimNative", D_METHOD("isqrt", "n"), &SimNative::isqrt);
	ClassDB::bind_static_method("SimNative", D_METHOD("mul32", "a", "b"), &SimNative::mul32);
	ClassDB::bind_integer_constant(get_class_static(), "", "SIM_VERSION", sim::SIM_VERSION);
	ClassDB::bind_integer_constant(get_class_static(), "", "TICK_RATE", sim::TICK_RATE);
}

int64_t SimNative::isqrt(int64_t n) {
	return sim::isqrt(n);
}

int64_t SimNative::mul32(int64_t a, int64_t b) {
	return sim::mul32(uint32_t(a), uint32_t(b));
}

// SimNativeRng ---------------------------------------------------------------

void SimNativeRng::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_seed", "seed"), &SimNativeRng::set_seed);
	ClassDB::bind_method(D_METHOD("next_u32"), &SimNativeRng::next_u32);
	ClassDB::bind_method(D_METHOD("range_int", "lo", "hi"), &SimNativeRng::range_int);
	ClassDB::bind_method(D_METHOD("chance_bp", "bp"), &SimNativeRng::chance_bp);
	ClassDB::bind_method(D_METHOD("get_state"), &SimNativeRng::get_state);
	ClassDB::bind_method(D_METHOD("set_state", "state"), &SimNativeRng::set_state);
}

void SimNativeRng::set_seed(int64_t seed) {
	rng.set_seed(seed);
}

int64_t SimNativeRng::next_u32() {
	return rng.next_u32();
}

int64_t SimNativeRng::range_int(int64_t lo, int64_t hi) {
	return rng.range_int(lo, hi);
}

bool SimNativeRng::chance_bp(int64_t bp) {
	return rng.chance_bp(bp);
}

PackedInt64Array SimNativeRng::get_state() const {
	const auto words = rng.state();
	return to_packed({ words[0], words[1], words[2], words[3] });
}

void SimNativeRng::set_state(const PackedInt64Array &state) {
	ERR_FAIL_COND_MSG(state.size() != 4, "SimNativeRng.set_state needs 4 words");
	rng.set_state({ uint32_t(state[0]), uint32_t(state[1]), uint32_t(state[2]), uint32_t(state[3]) });
}

// SimNativeHasher ------------------------------------------------------------

void SimNativeHasher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("add_int", "value"), &SimNativeHasher::add_int);
	ClassDB::bind_method(D_METHOD("add_ints", "values"), &SimNativeHasher::add_ints);
	ClassDB::bind_method(D_METHOD("add_string", "text"), &SimNativeHasher::add_string);
	ClassDB::bind_method(D_METHOD("finish_hex"), &SimNativeHasher::finish_hex);
}

void SimNativeHasher::add_int(int64_t value) {
	hasher.add_int(value);
}

void SimNativeHasher::add_ints(const PackedInt64Array &values) {
	for (int64_t i = 0; i < values.size(); i++) {
		hasher.add_int(values[i]);
	}
}

void SimNativeHasher::add_string(const String &text) {
	hasher.add_string(to_std(text));
}

String SimNativeHasher::finish_hex() const {
	return to_godot(hasher.finish_hex());
}

// SimNativeLanePath ----------------------------------------------------------

void SimNativeLanePath::_bind_methods() {
	ClassDB::bind_method(D_METHOD("build", "px", "py"), &SimNativeLanePath::build);
	ClassDB::bind_method(D_METHOD("position_at", "distance"), &SimNativeLanePath::position_at);
	ClassDB::bind_method(D_METHOD("get_length"), &SimNativeLanePath::get_length);
	ClassDB::bind_method(D_METHOD("get_xs"), &SimNativeLanePath::get_xs);
	ClassDB::bind_method(D_METHOD("get_ys"), &SimNativeLanePath::get_ys);
	ClassDB::bind_method(D_METHOD("get_starts"), &SimNativeLanePath::get_starts);
}

String SimNativeLanePath::build(const PackedInt64Array &px, const PackedInt64Array &py) {
	const std::string problem = path.build(to_vector(px), to_vector(py));
	built = problem.empty();
	return to_godot(problem);
}

Vector2i SimNativeLanePath::position_at(int64_t distance) const {
	ERR_FAIL_COND_V_MSG(!built, Vector2i(), "SimNativeLanePath.position_at before a successful build");
	const sim::Point p = path.position_at(distance);
	return Vector2i(int32_t(p.x), int32_t(p.y));
}

int64_t SimNativeLanePath::get_length() const {
	return path.length;
}

PackedInt64Array SimNativeLanePath::get_xs() const {
	return to_packed(path.xs);
}

PackedInt64Array SimNativeLanePath::get_ys() const {
	return to_packed(path.ys);
}

PackedInt64Array SimNativeLanePath::get_starts() const {
	return to_packed(path.starts);
}

// SimNativeBattle ------------------------------------------------------------

void SimNativeBattle::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "config", "spec"), &SimNativeBattle::setup);
	ClassDB::bind_method(D_METHOD("advance"), &SimNativeBattle::advance);
	ClassDB::bind_method(D_METHOD("run"), &SimNativeBattle::run);
	ClassDB::bind_method(D_METHOD("result"), &SimNativeBattle::result);
	ClassDB::bind_method(D_METHOD("state_hash"), &SimNativeBattle::state_hash);
	ClassDB::bind_method(D_METHOD("get_tick"), &SimNativeBattle::get_tick);
	ClassDB::bind_method(D_METHOD("get_outcome"), &SimNativeBattle::get_outcome);
	ClassDB::bind_method(D_METHOD("get_spawned_count"), &SimNativeBattle::get_spawned_count);
	ClassDB::bind_method(D_METHOD("get_leaked_count"), &SimNativeBattle::get_leaked_count);
	ClassDB::bind_method(D_METHOD("get_leaked_lives"), &SimNativeBattle::get_leaked_lives);
	ClassDB::bind_method(D_METHOD("get_entity_updates"), &SimNativeBattle::get_entity_updates);
	ClassDB::bind_method(D_METHOD("get_checkpoints"), &SimNativeBattle::get_checkpoints);
	ClassDB::bind_method(D_METHOD("get_errors"), &SimNativeBattle::get_errors);
	ClassDB::bind_method(D_METHOD("get_aliens"), &SimNativeBattle::get_aliens);
}

bool SimNativeBattle::setup(const Dictionary &config, const Dictionary &spec) {
	std::vector<std::string> errors;
	Reader r{ errors };
	sim::BattleConfig c;
	c.config_hash = r.get_string(config, "config_hash", "config");
	c.config_version = r.get_int(config, "config_version", "config");
	const Array enemies = r.get_array(config, "enemies", "config");
	for (int64_t i = 0; i < enemies.size(); i++) {
		const std::string where = "config.enemies[" + std::to_string(i) + "]";
		const Dictionary d = r.item(enemies, i, "config.enemies");
		sim::EnemyType e;
		e.hp_x100 = r.get_int(d, "hp_x100", where);
		e.armor = r.get_int(d, "armor", where);
		e.shield_x100 = r.get_int(d, "shield_x100", where);
		e.speed_mtps = r.get_int(d, "speed_mtps", where);
		e.air = r.get_bool(d, "air", where);
		e.leak_lives = r.get_int(d, "leak_lives", where);
		c.enemies.push_back(e);
	}
	sim::BattleSpec s;
	s.battle_id = r.get_string(spec, "battle_id", "spec");
	s.seed = r.get_int(spec, "seed", "spec");
	s.max_ticks = r.get_int(spec, "max_ticks", "spec");
	const Array lanes = r.get_array(spec, "lanes", "spec");
	for (int64_t i = 0; i < lanes.size(); i++) {
		const std::string where = "spec.lanes[" + std::to_string(i) + "]";
		const Dictionary d = r.item(lanes, i, "spec.lanes");
		sim::LaneSpec lane;
		r.path(lane.ground, d, "ground_x", "ground_y", where + ".ground");
		if (r.has(d, "air_x", Variant::PACKED_INT64_ARRAY, where) && as<PackedInt64Array>(d["air_x"]).size() > 0) {
			sim::LanePath air;
			r.path(air, d, "air_x", "air_y", where + ".air");
			lane.air = air;
		}
		s.lanes.push_back(lane);
	}
	const Array groups = r.get_array(spec, "groups", "spec");
	for (int64_t i = 0; i < groups.size(); i++) {
		const std::string where = "spec.groups[" + std::to_string(i) + "]";
		const Dictionary d = r.item(groups, i, "spec.groups");
		sim::SpawnGroup g;
		g.enemy_index = r.get_int(d, "enemy_index", where);
		g.lane_index = r.get_int(d, "lane_index", where);
		g.count = r.get_int(d, "count", where);
		g.first_tick = r.get_int(d, "first_tick", where);
		g.interval_ticks = r.get_int(d, "interval_ticks", where);
		g.jitter_ticks = r.get_int(d, "jitter_ticks", where);
		s.groups.push_back(g);
	}
	if (!errors.empty()) {
		battle.errors = errors;
		ready = false;
		return false;
	}
	ready = battle.setup(std::move(c), std::move(s));
	return ready;
}

void SimNativeBattle::advance() {
	battle.advance();
}

Dictionary SimNativeBattle::run() {
	battle.run();
	return result();
}

Dictionary SimNativeBattle::result() const {
	Dictionary d;
	ERR_FAIL_COND_V_MSG(!ready, d, "SimNativeBattle.result before a successful setup");
	d["battle_id"] = to_godot(battle.spec().battle_id);
	d["sim_version"] = sim::SIM_VERSION;
	d["config_version"] = battle.config().config_version;
	d["config_hash"] = to_godot(battle.config().config_hash);
	d["outcome"] = String(OUTCOME_NAMES[battle.outcome]);
	d["ticks"] = battle.tick;
	d["spawned"] = battle.spawned_count;
	d["leaked"] = battle.leaked_count;
	d["leaked_lives"] = battle.leaked_lives;
	d["final_hash"] = state_hash();
	Array checkpoints;
	for (const std::string &c : battle.checkpoints) {
		checkpoints.push_back(to_godot(c));
	}
	d["checkpoints"] = checkpoints;
	d["entity_updates"] = battle.entity_updates;
	return d;
}

String SimNativeBattle::state_hash() const {
	ERR_FAIL_COND_V_MSG(!ready, String(), "SimNativeBattle.state_hash before a successful setup");
	return to_godot(battle.state_hash());
}

PackedStringArray SimNativeBattle::get_checkpoints() const {
	PackedStringArray out;
	for (const std::string &c : battle.checkpoints) {
		out.push_back(to_godot(c));
	}
	return out;
}

PackedStringArray SimNativeBattle::get_errors() const {
	PackedStringArray out;
	for (const std::string &e : battle.errors) {
		out.push_back(to_godot(e));
	}
	return out;
}

Array SimNativeBattle::get_aliens() const {
	Array out;
	for (const sim::Alien &a : battle.aliens) {
		const sim::Point pos = a.path->position_at(a.distance_mt);
		Dictionary d;
		d["id"] = a.id;
		d["type_index"] = a.type_index;
		d["lane_index"] = a.lane_index;
		d["air"] = a.air;
		d["distance_mt"] = a.distance_mt;
		d["move_accum"] = a.move_accum;
		d["hp_x100"] = a.hp_x100;
		d["shield_x100"] = a.shield_x100;
		d["x"] = pos.x;
		d["y"] = pos.y;
		out.push_back(d);
	}
	return out;
}

} // namespace aetd
