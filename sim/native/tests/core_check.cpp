// Drives the sim core without Godot, for tools/check_sim_native.py: it reads
// simple text commands on stdin and prints one result line per query. Built
// with sanitizers, so undefined behaviour in the core fails the check.
#include <array>
#include <cstdint>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "core/battle.h"
#include "core/fx.h"
#include "core/sim_rng.h"
#include "core/state_hasher.h"

using namespace aetd::sim;

namespace {

std::string from_hex(const std::string &hex) {
	std::string out;
	for (size_t i = 0; i + 1 < hex.size(); i += 2) {
		out.push_back(char(std::stoi(hex.substr(i, 2), nullptr, 16)));
	}
	return out;
}

std::vector<int64_t> read_ints(std::istringstream &in, int64_t count) {
	std::vector<int64_t> out(static_cast<size_t>(count));
	for (auto &v : out) {
		in >> v;
	}
	return out;
}

} // namespace

int main() {
	SimRng rng;
	StateHasher hasher;
	BattleConfig config;
	BattleSpec spec;
	std::string line;
	while (std::getline(std::cin, line)) {
		std::istringstream in(line);
		std::string cmd;
		in >> cmd;
		if (cmd == "rng") {
			int64_t seed;
			in >> seed;
			rng.set_seed(seed);
		} else if (cmd == "u32") {
			std::cout << rng.next_u32() << "\n";
		} else if (cmd == "range") {
			int64_t lo, hi;
			in >> lo >> hi;
			std::cout << rng.range_int(lo, hi) << "\n";
		} else if (cmd == "chance") {
			int64_t bp;
			in >> bp;
			std::cout << (rng.chance_bp(bp) ? "true" : "false") << "\n";
		} else if (cmd == "state") {
			const auto s = rng.state();
			std::cout << s[0] << " " << s[1] << " " << s[2] << " " << s[3] << "\n";
		} else if (cmd == "mul32") {
			int64_t a, b;
			in >> a >> b;
			std::cout << mul32(uint32_t(a), uint32_t(b)) << "\n";
		} else if (cmd == "isqrt") {
			int64_t n;
			in >> n;
			std::cout << isqrt(n) << "\n";
		} else if (cmd == "hash_begin") {
			hasher = StateHasher();
		} else if (cmd == "int") {
			int64_t v;
			in >> v;
			hasher.add_int(v);
		} else if (cmd == "str") {
			std::string hex;
			in >> hex;
			hasher.add_string(from_hex(hex));
		} else if (cmd == "hash_end") {
			std::cout << hasher.finish_hex() << "\n";
		} else if (cmd == "battle_begin") {
			config = BattleConfig();
			spec = BattleSpec();
		} else if (cmd == "config") {
			in >> config.config_hash >> config.config_version;
		} else if (cmd == "enemy") {
			EnemyType e;
			int64_t air;
			in >> e.hp_x100 >> e.armor >> e.shield_x100 >> e.speed_mtps >> air >> e.leak_lives;
			e.air = air != 0;
			config.enemies.push_back(e);
		} else if (cmd == "spec") {
			in >> spec.battle_id >> spec.seed >> spec.max_ticks;
		} else if (cmd == "lane") {
			LaneSpec lane;
			int64_t n;
			in >> n;
			const auto gx = read_ints(in, n);
			const auto gy = read_ints(in, n);
			lane.ground.build(gx, gy);
			in >> n;
			if (n > 0) {
				const auto ax = read_ints(in, n);
				const auto ay = read_ints(in, n);
				LanePath air;
				air.build(ax, ay);
				lane.air = air;
			}
			spec.lanes.push_back(lane);
		} else if (cmd == "group") {
			SpawnGroup g;
			in >> g.enemy_index >> g.lane_index >> g.count >> g.first_tick >> g.interval_ticks >> g.jitter_ticks;
			spec.groups.push_back(g);
		} else if (cmd == "battle_run") {
			Battle battle;
			if (!battle.setup(config, spec)) {
				std::cout << "error";
				for (const auto &e : battle.errors) {
					std::cout << " [" << e << "]";
				}
				std::cout << "\n";
				continue;
			}
			battle.run();
			static const char *names[] = { "running", "cleared", "timed_out" };
			std::cout << "result " << names[battle.outcome] << " " << battle.tick << " " << battle.state_hash();
			for (const auto &c : battle.checkpoints) {
				std::cout << " " << c;
			}
			std::cout << "\n";
		} else if (!cmd.empty()) {
			std::cerr << "unknown command: " << cmd << "\n";
			return 2;
		}
	}
	return 0;
}
