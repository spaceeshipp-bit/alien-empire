#include "core/lane_path.h"

#include "core/fx.h"

namespace aetd::sim {

std::string LanePath::build(const std::vector<int64_t> &px, const std::vector<int64_t> &py) {
	xs.clear();
	ys.clear();
	starts.clear();
	length = 0;
	if (px.size() != py.size()) {
		return "x and y lists differ in length";
	}
	for (size_t i = 0; i < px.size(); i++) {
		if (!xs.empty()) {
			const int64_t dx = px[i] - xs.back();
			const int64_t dy = py[i] - ys.back();
			if (dx == 0 && dy == 0) {
				continue;
			}
			length += isqrt(dx * dx + dy * dy);
		}
		xs.push_back(px[i]);
		ys.push_back(py[i]);
		starts.push_back(length);
	}
	if (xs.size() < 2) {
		return "needs at least two different points";
	}
	return "";
}

Point LanePath::position_at(int64_t distance) const {
	const size_t last = xs.size() - 1;
	if (distance <= 0) {
		return { xs[0], ys[0] };
	}
	if (distance >= length) {
		return { xs[last], ys[last] };
	}
	size_t i = 0;
	while (i < last - 1 && starts[i + 1] <= distance) {
		i++;
	}
	const int64_t seg = starts[i + 1] - starts[i];
	const int64_t into = distance - starts[i];
	return { xs[i] + (xs[i + 1] - xs[i]) * into / seg, ys[i] + (ys[i + 1] - ys[i]) * into / seg };
}

} // namespace aetd::sim
