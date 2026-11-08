extends "res://plugin_lab/lab_check.gd"
## Play Integrity through this project's own PlayIntegrity plugin
## (client/android_plugins/play_integrity), since no maintained Godot plugin
## exists. Prepares a standard token provider and requests one token bound to a
## request hash. The server decodes tokens from M4; here, getting one is a pass.

const SETTING := "aetd/play_integrity/cloud_project_number"

var _plugin: Object = null


func title() -> String:
	return "Play Integrity"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	return "Plugin installed" if Engine.has_singleton("PlayIntegrity") else "Plugin not in this build (docs/PLUGINS.md)"


func run() -> void:
	if not Engine.has_singleton("PlayIntegrity"):
		finish(false, "The PlayIntegrity plugin isn't in this build. Build it with tools/build_android_plugins.sh.")
		return
	var project_number: String = str(ProjectSettings.get_setting(SETTING, "")).strip_edges()
	if project_number.is_empty():
		finish(false, "This build has no Google Cloud project number. Set the PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER variable and build again (docs/PLUGINS.md).")
		return
	if _plugin == null:
		# Connect once; the plugin's signals outlive each run.
		var plugin: Object = Engine.get_singleton("PlayIntegrity")
		if not require_api(plugin, ["prepare", "request_token"], ["prepared", "prepare_failed", "token_ready", "token_failed"]):
			return
		_plugin = plugin
		_plugin.connect("prepared", _on_prepared)
		_plugin.connect("prepare_failed", _on_failed.bind("Preparing the token provider failed"))
		_plugin.connect("token_ready", _on_token)
		_plugin.connect("token_failed", _on_failed.bind("The token request failed"))
	arm_timeout(90.0, "No integrity token within 90 seconds.")
	log_line("Preparing the integrity token provider…")
	_plugin.call("prepare", project_number)


func _on_prepared() -> void:
	# Binds the token to this request, as the server will for real requests.
	var request: String = "aetd-m0-plugin-lab:%d" % int(Time.get_unix_time_from_system())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(request.to_utf8_buffer())
	var request_hash: String = ctx.finish().hex_encode()
	log_line("Requesting a token for request hash %s…" % request_hash.substr(0, 12))
	_plugin.call("request_token", request_hash)


func _on_token(token: String) -> void:
	finish(true, "Play Integrity works: got a %d-character token. The server will decode it from M4." % token.length())


func _on_failed(error: String, what: String) -> void:
	finish(false, "%s: %s" % [what, error])
