#include "core/sim_rng.h"

namespace aetd::sim {

void SimRng::set_seed(int64_t seed) {
	const uint32_t lo = static_cast<uint32_t>(static_cast<uint64_t>(seed) & 0xFFFFFFFFu);
	const uint32_t hi = static_cast<uint32_t>((static_cast<uint64_t>(seed) >> 32) & 0xFFFFFFFFu);
	sm = lo ^ (hi * 0x85EBCA6Bu);
	s0 = splitmix32();
	s1 = splitmix32();
	s2 = splitmix32();
	s3 = splitmix32();
	if ((s0 | s1 | s2 | s3) == 0) {
		s0 = 1;
	}
}

uint32_t SimRng::splitmix32() {
	sm += 0x9E3779B9u;
	uint32_t z = sm;
	z = (z ^ (z >> 16)) * 0x85EBCA6Bu;
	z = (z ^ (z >> 13)) * 0xC2B2AE35u;
	return z ^ (z >> 16);
}

uint32_t SimRng::next_u32() {
	const uint32_t result = rotl(s1 * 5u, 7) * 9u;
	const uint32_t t = s1 << 9;
	s2 ^= s0;
	s3 ^= s1;
	s1 ^= s2;
	s0 ^= s3;
	s2 ^= t;
	s3 = rotl(s3, 11);
	return result;
}

int64_t SimRng::range_int(int64_t lo, int64_t hi) {
	constexpr int64_t TWO_32 = int64_t(1) << 32;
	const int64_t span = hi - lo + 1;
	if (span <= 1) {
		return lo;
	}
	if (span >= TWO_32) {
		return lo + next_u32();
	}
	const int64_t limit = TWO_32 - (TWO_32 % span);
	int64_t r = next_u32();
	while (r >= limit) {
		r = next_u32();
	}
	return lo + r % span;
}

void SimRng::set_state(const std::array<uint32_t, 4> &words) {
	s0 = words[0];
	s1 = words[1];
	s2 = words[2];
	s3 = words[3];
}

} // namespace aetd::sim
