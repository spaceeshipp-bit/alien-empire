extends RefCounted
## PvE stages from a config bundle (config/balance/stages.json): the battle spec
## one play of a stage makes, given the seed the server issues. Wave HP and kill
## credits grow per wave by the stage's factors, truncated at each step, as
## tools/stages.py computes them; the GDScript tests check both agree.


## The bundle's stage with this id, or {} if there's none.
static func find(bundle: Dictionary, id: String) -> Dictionary:
	var data: Dictionary = bundle.get("data", {})
	var part: Dictionary = data.get("stages", {})
	for stage: Variant in part.get("stages", []):
		if typeof(stage) == TYPE_DICTIONARY and stage.get("id", "") == id:
			return stage
	return {}


## The x growth^wave_index factor in basis points: wave 1 (index 0) is 10000.
static func wave_scale_bp(growth_bp: int, wave_index: int) -> int:
	var scale: int = 10000
	for _w in wave_index:
		scale = scale * growth_bp / 10000
	return scale


## The battle spec for one play of a stage: no spawn jitter (D-033) and no
## commands yet; the player's commands join as the battle runs. Values pass
## through as read, and BattleSpec.parse checks every one.
static func build_spec(stage: Dictionary, battle_seed: int, battle_id: String = "") -> Dictionary:
	var waves: Array = []
	var hp_growth: int = int(stage.get("hp_growth_bp", 10000))
	var credit_growth: int = int(stage.get("credit_growth_bp", 10000))
	var stage_waves: Array = stage.get("waves", [])
	for i in stage_waves.size():
		var wave: Dictionary = stage_waves[i]
		var groups: Array = []
		for group: Dictionary in wave.get("groups", []):
			var copy: Dictionary = group.duplicate(true)
			copy["jitter_ms"] = 0
			groups.append(copy)
		waves.append({
			"start_ms": wave.get("start_ms", 0),
			"hp_bp": wave_scale_bp(hp_growth, i),
			"credits_bp": wave_scale_bp(credit_growth, i),
			"groups": groups,
		})
	return {
		"battle_id": battle_id if not battle_id.is_empty() else String(stage.get("id", "")),
		"mode": "pve",
		"seed": battle_seed,
		"max_ms": stage.get("max_ms", 0),
		"lives": stage.get("lives", 0),
		"credits": stage.get("credits", 0),
		"towers": (stage.get("towers", []) as Array).duplicate(),
		"map": {
			"lanes": (stage.get("lanes", []) as Array).duplicate(true),
			"build_tiles": (stage.get("build_tiles", []) as Array).duplicate(true),
		},
		"waves": waves,
		"commands": [],
	}
