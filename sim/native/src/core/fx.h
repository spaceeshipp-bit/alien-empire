// Integer helpers for the sim core. The sim never uses floating point: HP and
// damage are stored x100, distances in thousandths of a tile (mt), percentages
// in basis points and time in 50 ms ticks.
//
// C++ integer division truncates toward zero, like GDScript's. The build adds
// -fwrapv, so even an overflow would wrap the same way on every platform; the
// sim keeps its values far from the limits anyway (see battle_spec.gd).
#pragma once

#include <cstdint>

namespace aetd::sim {

// Raise whenever a change could alter any battle's result, and re-record the
// golden hashes (sim/tests/golden/expected.json).
inline constexpr int64_t SIM_VERSION = 1;
inline constexpr int64_t TICK_RATE = 20;
inline constexpr int64_t MS_PER_TICK = 50;

// Floor of the square root of n by Newton's method, for 0 <= n < 2^62.
// Returns 0 for negative n. The same steps as the original GDScript version.
inline int64_t isqrt(int64_t n) {
	if (n < 2) {
		return n < 0 ? 0 : n;
	}
	int64_t x = n;
	int64_t y = (x + 1) / 2;
	while (y < x) {
		x = y;
		y = (x + n / x) / 2;
	}
	return x;
}

// (a * b) mod 2^32 for a and b in [0, 2^32).
inline uint32_t mul32(uint32_t a, uint32_t b) {
	return a * b;
}

} // namespace aetd::sim
