extends SceneTree
## Replays one battle and prints its result as JSON. From M4 this is the sim
## worker's job: the server sends a config bundle and a battle spec, and the
## result the worker returns is the one that stands.
##
##   godot --headless --path worker --script res://cli/replay.gd -- --bundle /abs/bundle.json --battle /abs/spec.json
##
## Use absolute paths or res:// paths.

const JsonFile := preload("res://sim/core/json_file.gd")
const SimConfig := preload("res://sim/core/sim_config.gd")
const BattleSpec := preload("res://sim/core/battle_spec.gd")
const Battle := preload("res://sim/core/battle.gd")


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var bundle_path: String = _arg(args, "--bundle")
	var battle_path: String = _arg(args, "--battle")
	if bundle_path.is_empty() or battle_path.is_empty():
		printerr("usage: godot --headless --path worker --script res://cli/replay.gd -- --bundle <bundle.json> --battle <spec.json>")
		return 2
	var bundle_file: Dictionary = JsonFile.read_dict(bundle_path)
	if not bundle_file["ok"]:
		printerr(bundle_file["error"])
		return 1
	var spec_file: Dictionary = JsonFile.read_dict(battle_path)
	if not spec_file["ok"]:
		printerr(spec_file["error"])
		return 1
	var config := SimConfig.new()
	if not config.load_bundle(bundle_file["data"]):
		printerr("\n".join(config.errors))
		return 1
	var spec := BattleSpec.new()
	if not spec.parse(spec_file["data"]):
		printerr("\n".join(spec.errors))
		return 1
	var battle := Battle.new()
	if not battle.setup(config, spec):
		printerr("\n".join(battle.errors))
		return 1
	var started: int = Time.get_ticks_usec()
	var result: Dictionary = battle.run()
	result["replay_usec"] = Time.get_ticks_usec() - started
	print(JSON.stringify(result, "  "))
	return 0


func _arg(args: PackedStringArray, flag: String) -> String:
	var i: int = args.find(flag)
	if i < 0 or i + 1 >= args.size():
		return ""
	return args[i + 1]
