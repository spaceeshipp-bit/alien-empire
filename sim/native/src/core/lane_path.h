// A lane: waypoints in mt with precomputed integer segment lengths. Aliens
// store only how far along the path they are; positions are derived from that
// distance when needed (targeting, drawing, state hashes).
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace aetd::sim {

struct Point {
	int64_t x = 0;
	int64_t y = 0;
};

class LanePath {
public:
	// Builds the path from waypoint coordinates; repeated consecutive points are
	// skipped. Returns "" on success, or what's wrong.
	std::string build(const std::vector<int64_t> &px, const std::vector<int64_t> &py);
	// Position after travelling distance mt from the start, clamped to the ends.
	Point position_at(int64_t distance) const;

	// Total length in mt. Segment lengths are floored square roots, so this can
	// be a few mt shorter than the true length; it's the same on every device.
	int64_t length = 0;
	std::vector<int64_t> xs, ys;
	// Distance from the start of the path to each waypoint, in mt.
	std::vector<int64_t> starts;
};

} // namespace aetd::sim
