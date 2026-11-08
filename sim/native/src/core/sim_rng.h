// Seeded random numbers for the sim: xoshiro128** (Blackman and Vigna), seeded
// through splitmix32. Never use any engine or library random function inside
// the sim. tools/gen_vectors.py and tools/reference/xoshiro128ss.c hold
// references of this exact algorithm; their vectors run on every platform.
#pragma once

#include <array>
#include <cstdint>

namespace aetd::sim {

class SimRng {
public:
	// The largest seed JSON carries exactly: 2^53 - 1.
	static constexpr int64_t MAX_SEED = 9007199254740991LL;

	explicit SimRng(int64_t seed = 0) { set_seed(seed); }

	// Seeds the generator. seed must be in [0, MAX_SEED].
	void set_seed(int64_t seed);
	// Next raw value in [0, 2^32).
	uint32_t next_u32();
	// Uniform integer in [lo, hi] without modulo bias; hi - lo must be below 2^32.
	int64_t range_int(int64_t lo, int64_t hi);
	// True with probability bp / 10000.
	bool chance_bp(int64_t bp) { return range_int(0, 9999) < bp; }

	std::array<uint32_t, 4> state() const { return {s0, s1, s2, s3}; }
	void set_state(const std::array<uint32_t, 4> &words);

private:
	uint32_t s0 = 0, s1 = 0, s2 = 0, s3 = 0;
	uint32_t sm = 0; // splitmix32 state, used only while seeding

	uint32_t splitmix32();
	static uint32_t rotl(uint32_t x, int k) { return (x << k) | (x >> (32 - k)); }
};

} // namespace aetd::sim
