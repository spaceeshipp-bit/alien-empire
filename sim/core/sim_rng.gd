extends RefCounted
## Seeded random numbers for the sim: xoshiro128** (Blackman and Vigna), seeded
## through splitmix32, computed by the sim core (sim/native/src/core/sim_rng.cpp).
## Never use Godot's random functions inside the sim. tools/gen_vectors.py holds
## a Python reference of this exact algorithm and writes the test vectors.

## The largest seed JSON carries exactly: 2^53 - 1.
const MAX_SEED: int = 9007199254740991

var _native := SimNativeRng.new()


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


## Seeds the generator. seed_value must be in [0, MAX_SEED].
func set_seed(seed_value: int) -> void:
	_native.set_seed(seed_value)


## Next raw value in [0, 2^32).
func next_u32() -> int:
	return _native.next_u32()


## Uniform integer in [lo, hi] without modulo bias. hi - lo must be below 2^32.
func range_int(lo: int, hi: int) -> int:
	return _native.range_int(lo, hi)


## True with probability bp / 10000.
func chance_bp(bp: int) -> bool:
	return _native.chance_bp(bp)


## The four state words, for state hashes and battle snapshots.
func get_state() -> PackedInt64Array:
	return _native.get_state()


func set_state(state: PackedInt64Array) -> void:
	_native.set_state(state)


## (a * b) mod 2^32 for a and b in [0, 2^32).
static func mul32(a: int, b: int) -> int:
	return SimNative.mul32(a, b)
