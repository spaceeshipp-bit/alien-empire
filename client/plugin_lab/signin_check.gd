extends "res://plugin_lab/lab_check.gd"
## Google sign-in through Play Games Services, using the Google Play Games
## Services for Godot plugin (godot-sdk-integrations). Checks whether the player
## is signed in and signs in if not. The server-side access step that links the
## account to the backend comes with M4.
##
## The plugin's GDScript names below are unconfirmed (its README wasn't
## reachable when this was written). If they differ, the check fails and lists
## the names the plugin really offers; adjust this file to match.

const SIGN_IN_CLASS := "PlayGamesSignInClient"

var _client: Object = null


func title() -> String:
	return "Google sign-in (Play Games)"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if find_api(SIGN_IN_CLASS) != null or find_api("GodotPlayGameServices") != null:
		return "Plugin installed"
	return "Plugin not installed (docs/PLUGINS.md)"


func run() -> void:
	var script: GDScript = find_api(SIGN_IN_CLASS) as GDScript
	if script == null:
		var other: Object = find_api("GodotPlayGameServices")
		if other == null:
			finish(false, "Play Games Services isn't in this build. Install the plugin (docs/PLUGINS.md).")
		else:
			finish(false, "Found GodotPlayGameServices but no %s class. It offers: %s" % [SIGN_IN_CLASS, describe_api(other)])
		return
	_client = script.new()
	if _client is Node:
		add_child(_client)
	if not require_api(_client, ["is_authenticated", "sign_in"], ["user_authenticated"]):
		return
	_client.connect("user_authenticated", _on_checked, CONNECT_ONE_SHOT)
	arm_timeout(60.0, "No sign-in answer within 60 seconds.")
	log_line("Checking whether this phone is signed in to Play Games…")
	_client.call("is_authenticated")


func _on_checked(is_authenticated: bool) -> void:
	if is_authenticated:
		finish(true, "Signed in to Play Games.")
		return
	log_line("Not signed in yet. Opening Google sign-in…")
	_client.connect("user_authenticated", _on_signed_in, CONNECT_ONE_SHOT)
	_client.call("sign_in")


func _on_signed_in(is_authenticated: bool) -> void:
	if is_authenticated:
		finish(true, "Sign-in works: signed in to Play Games.")
	else:
		finish(false, "Sign-in didn't complete. Check the Play Games setup in Play Console (docs/PLUGINS.md).")
