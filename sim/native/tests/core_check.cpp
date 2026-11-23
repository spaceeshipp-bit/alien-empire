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

void print_result(const Battle &battle) {
	static const char *names[] = { "running", "cleared", "timed_out", "lost" };
	std::cout << "result " << names[battle.outcome] << " " << battle.tick << " lives=" << battle.lives
			  << " credits=" << battle.credits_x100 << " kills=" << battle.kills << " leaked=" << battle.leaked_count
			  << " refused=" << battle.refused_commands << " spawned=" << battle.spawned_count << " " << battle.state_hash();
	for (const auto &c : battle.checkpoints) {
		std::cout << " " << c;
	}
	std::cout << "\n";
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
			int64_t air, supported;
			in >> e.hp_x100 >> e.armor >> e.shield_x100 >> e.speed_mtps >> air >> e.leak_lives >> e.class_index >>
					e.kill_credits_x100 >> e.release_index >> e.release_count >> supported;
			e.air = air != 0;
			e.supported = supported != 0;
			config.enemies.push_back(e);
		} else if (cmd == "tower") {
			TowerType t;
			int64_t supported;
			in >> t.cost_credits >> t.damage_x100 >> t.shots_per_s_x100 >> t.range_mt >> t.splash_mt >> t.shield_mult_bp >>
					t.pierce_bp;
			for (auto &rating : t.rating_bp) {
				in >> rating;
			}
			in >> t.unrevealed_bp >> t.targeting >> supported;
			t.supported = supported != 0;
			config.towers.push_back(t);
		} else if (cmd == "upgrades") {
			FieldUpgrades &u = config.upgrades;
			in >> u.max_level >> u.first_upgrade_cost_bp >> u.cost_growth_bp >> u.damage_growth_bp >> u.range_step_bp >>
					u.sell_refund_bp;
		} else if (cmd == "damage") {
			in >> config.damage.armor_constant >> config.damage.max_reduction_bp >> config.damage.min_damage_x100;
		} else if (cmd == "timing") {
			in >> config.regen_per_second_x100 >> config.regen_delay_ticks >> config.retarget_ticks;
		} else if (cmd == "spec") {
			in >> spec.battle_id >> spec.seed >> spec.max_ticks >> spec.lives >> spec.credits >> spec.call_credits_per_s >>
					spec.call_credits_max >> spec.clean_wave_credits;
		} else if (cmd == "wave") {
			int64_t start;
			in >> start;
			spec.wave_starts.push_back(start);
		} else if (cmd == "towerset") {
			int64_t n;
			in >> n;
			spec.tower_set = read_ints(in, n);
		} else if (cmd == "tile") {
			BuildTile tile;
			in >> tile.col >> tile.row;
			spec.build_tiles.push_back(tile);
		} else if (cmd == "command") {
			Command c;
			in >> c.tick >> c.kind >> c.tower_index >> c.col >> c.row;
			spec.commands.push_back(c);
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
			in >> g.enemy_index >> g.lane_index >> g.count >> g.first_tick >> g.interval_ticks >> g.jitter_ticks >> g.hp_bp >>
					g.credits_bp >> g.wave_index;
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
			print_result(battle);
		} else if (cmd == "battle_live") {
			// The same battle with its commands queued live, each on the tick it
			// applies, the way the phone sends them: it must match battle_run.
			BattleSpec opening = spec;
			opening.commands.clear();
			Battle battle;
			if (!battle.setup(config, opening)) {
				std::cout << "error\n";
				continue;
			}
			size_t next = 0;
			bool refused = false;
			while (battle.outcome == RUNNING) {
				while (next < spec.commands.size() && spec.commands[next].tick == battle.tick) {
					refused = refused || !battle.queue_command(spec.commands[next]).empty();
					next += 1;
				}
				battle.advance();
			}
			if (refused) {
				std::cout << "error queue_command refused a command setup accepted\n";
				continue;
			}
			print_result(battle);
		} else if (cmd == "battle_reuse") {
			// One Battle set up three times: the valid battle run partway, a spec
			// the core rejects, then the valid battle again. The rejected setup
			// must leave nothing behind (aliens point into the replaced lanes),
			// and the rerun must match a fresh battle.
			Battle battle;
			if (!battle.setup(config, spec)) {
				std::cout << "error\n" << "error\n";
				continue;
			}
			while (battle.outcome == RUNNING && (battle.tick < 50 || battle.aliens.empty())) {
				battle.advance();
			}
			const bool had_aliens = !battle.aliens.empty();
			BattleSpec rejected = spec;
			rejected.max_ticks = 0;
			const bool accepted = battle.setup(config, rejected);
			std::cout << (had_aliens ? "" : "no aliens to test with ") << "rejected " << (accepted ? "no" : "yes")
					  << " aliens " << battle.aliens.size() << " tick " << battle.tick << "\n";
			battle.setup(config, spec);
			battle.run();
			print_result(battle);
		} else if (!cmd.empty()) {
			std::cerr << "unknown command: " << cmd << "\n";
			return 2;
		}
	}
	return 0;
}
