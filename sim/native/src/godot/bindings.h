// The sim core as Godot classes. GDScript reaches the core only through these;
// sim/core/*.gd wraps them with the APIs the rest of the game uses.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include "core/battle.h"
#include "core/lane_path.h"
#include "core/sim_rng.h"
#include "core/state_hasher.h"

namespace aetd {

// Constants and integer helpers.
class SimNative : public godot::RefCounted {
	GDCLASS(SimNative, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	static int64_t isqrt(int64_t n);
	static int64_t mul32(int64_t a, int64_t b);
};

class SimNativeRng : public godot::RefCounted {
	GDCLASS(SimNativeRng, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void set_seed(int64_t seed);
	int64_t next_u32();
	int64_t range_int(int64_t lo, int64_t hi);
	bool chance_bp(int64_t bp);
	godot::PackedInt64Array get_state() const;
	void set_state(const godot::PackedInt64Array &state);

private:
	sim::SimRng rng;
};

class SimNativeHasher : public godot::RefCounted {
	GDCLASS(SimNativeHasher, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	void add_int(int64_t value);
	void add_ints(const godot::PackedInt64Array &values);
	void add_string(const godot::String &text);
	godot::String finish_hex() const;

private:
	sim::StateHasher hasher;
};

class SimNativeLanePath : public godot::RefCounted {
	GDCLASS(SimNativeLanePath, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	godot::String build(const godot::PackedInt64Array &px, const godot::PackedInt64Array &py);
	godot::Vector2i position_at(int64_t distance) const;
	int64_t get_length() const;
	godot::PackedInt64Array get_xs() const;
	godot::PackedInt64Array get_ys() const;
	godot::PackedInt64Array get_starts() const;

private:
	sim::LanePath path;
	bool built = false;
};

class SimNativeBattle : public godot::RefCounted {
	GDCLASS(SimNativeBattle, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	bool setup(const godot::Dictionary &config, const godot::Dictionary &spec);
	// Queues a player command ({tick, kind, tower_index, col, row}) for this tick
	// or later. Returns "" or why it was refused.
	godot::String queue_command(const godot::Dictionary &command);
	void advance();
	godot::Dictionary run();
	godot::Dictionary result() const;
	godot::String state_hash() const;

	int64_t get_tick() const { return battle.tick; }
	int64_t get_outcome() const { return battle.outcome; }
	int64_t get_spawned_count() const { return battle.spawned_count; }
	int64_t get_leaked_count() const { return battle.leaked_count; }
	int64_t get_leaked_lives() const { return battle.leaked_lives; }
	int64_t get_entity_updates() const { return battle.entity_updates; }
	int64_t get_lives() const { return battle.lives; }
	int64_t get_credits_x100() const { return battle.credits_x100; }
	int64_t get_kills() const { return battle.kills; }
	int64_t get_refused_commands() const { return battle.refused_commands; }
	godot::PackedInt64Array get_wave_starts() const;
	godot::PackedStringArray get_checkpoints() const;
	godot::PackedStringArray get_errors() const;
	// One Dictionary per live alien, in id order (tests and debugging).
	godot::Array get_aliens() const;
	// One Dictionary per tower, in id order, with its upgrade cost (-1 at the top
	// level) and what selling it returns.
	godot::Array get_towers() const;
	// Live aliens for drawing, ALIEN_VIEW_STRIDE values each in id order: id,
	// type_index, class_index, air, x, y, hp_x100, max_hp_x100, shield_x100,
	// max_shield_x100.
	godot::PackedInt64Array get_alien_view() const;
	// The last tick's events, 5 values each: kind, a, b, x, y (core/battle.h).
	godot::PackedInt64Array get_events() const;
	// What upgrading a tower of this type from this level costs, x100.
	int64_t upgrade_cost_x100(int64_t type_index, int64_t level) const;
	// The commands so far, as {tick, kind, tower_index, col, row}: the log a
	// replay needs.
	godot::Array get_commands() const;

private:
	sim::Battle battle;
	bool ready = false;
};

} // namespace aetd
