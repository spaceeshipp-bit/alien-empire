// SHA-256 (FIPS 180-4) for battle state hashes. Self-contained so the sim core
// needs no engine services; tests check it against Python's hashlib vectors.
#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace aetd::sim {

std::array<uint8_t, 32> sha256(const uint8_t *data, size_t size);
std::string to_hex(const std::array<uint8_t, 32> &digest);

} // namespace aetd::sim
