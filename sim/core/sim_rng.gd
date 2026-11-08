extends RefCounted
## Seeded random numbers for the sim: xoshiro128** (Blackman and Vigna), seeded
## through splitmix32. Never use Godot's random functions inside the sim.
##
## Every state word stays in [0, 2^32) and every multiplication is split so no
## intermediate value passes 2^48. Nothing can overflow a 64-bit int, so the
## results are identical on every platform. tools/gen_vectors.py holds a Python
## reference of this exact algorithm and writes the test vectors.

const MASK32: int = 0xFFFFFFFF
const TWO_32: int = 0x100000000
## The largest seed JSON carries exactly: 2^53 - 1.
const MAX_SEED: int = 9007199254740991

var _s0: int = 0
var _s1: int = 0
var _s2: int = 0
var _s3: int = 0
var _sm: int = 0  # splitmix32 state, used only while seeding


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


## Seeds the generator. seed_value must be in [0, MAX_SEED].
func set_seed(seed_value: int) -> void:
	var lo: int = seed_value & MASK32
	var hi: int = (seed_value >> 32) & MASK32
	_sm = lo ^ mul32(hi, 0x85EBCA6B)
	_s0 = _splitmix32()
	_s1 = _splitmix32()
	_s2 = _splitmix32()
	_s3 = _splitmix32()
	if (_s0 | _s1 | _s2 | _s3) == 0:
		_s0 = 1


## Next raw value in [0, 2^32).
func next_u32() -> int:
	var result: int = (_rotl((_s1 * 5) & MASK32, 7) * 9) & MASK32
	var t: int = (_s1 << 9) & MASK32
	_s2 ^= _s0
	_s3 ^= _s1
	_s1 ^= _s2
	_s0 ^= _s3
	_s2 ^= t
	_s3 = _rotl(_s3, 11)
	return result


## Uniform integer in [lo, hi] without modulo bias. hi - lo must be below 2^32.
func range_int(lo: int, hi: int) -> int:
	var span: int = hi - lo + 1
	if span <= 1:
		return lo
	if span >= TWO_32:
		return lo + next_u32()
	var limit: int = TWO_32 - (TWO_32 % span)
	var r: int = next_u32()
	while r >= limit:
		r = next_u32()
	return lo + r % span


## True with probability bp / 10000.
func chance_bp(bp: int) -> bool:
	return range_int(0, 9999) < bp


## The four state words, for state hashes and battle snapshots.
func get_state() -> PackedInt64Array:
	return PackedInt64Array([_s0, _s1, _s2, _s3])


func set_state(state: PackedInt64Array) -> void:
	_s0 = state[0] & MASK32
	_s1 = state[1] & MASK32
	_s2 = state[2] & MASK32
	_s3 = state[3] & MASK32


## (a * b) mod 2^32 for a and b in [0, 2^32), split into 16-bit halves of b.
static func mul32(a: int, b: int) -> int:
	var low: int = (a * (b & 0xFFFF)) & MASK32
	var high: int = ((a * (b >> 16)) & 0xFFFF) << 16
	return (low + high) & MASK32


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & MASK32


func _splitmix32() -> int:
	_sm = (_sm + 0x9E3779B9) & MASK32
	var z: int = _sm
	z = mul32(z ^ (z >> 16), 0x85EBCA6B)
	z = mul32(z ^ (z >> 13), 0xC2B2AE35)
	return z ^ (z >> 16)
