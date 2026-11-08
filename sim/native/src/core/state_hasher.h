// SHA-256 over a stream of values: each integer as 8 bytes little-endian, each
// string as its UTF-8 byte count (an integer) followed by its bytes. Golden
// tests compare these hashes across desktop, Android and the headless worker.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "core/sha256.h"

namespace aetd::sim {

class StateHasher {
public:
	void add_int(int64_t value) {
		const uint64_t bits = static_cast<uint64_t>(value);
		for (int i = 0; i < 8; i++) {
			bytes.push_back(static_cast<uint8_t>(bits >> (8 * i)));
		}
	}
	// text must already be UTF-8.
	void add_string(const std::string &text) {
		add_int(static_cast<int64_t>(text.size()));
		bytes.insert(bytes.end(), text.begin(), text.end());
	}
	// Lower-case hex digest of everything added so far.
	std::string finish_hex() const { return to_hex(sha256(bytes.data(), bytes.size())); }

private:
	std::vector<uint8_t> bytes;
};

} // namespace aetd::sim
