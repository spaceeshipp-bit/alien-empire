extends "res://plugin_lab/lab_check.gd"
## Google sign-in through Play Games Services, using Google Play Games Services
## for Godot v3.4.0 (godot-sdk-integrations). Initializes the plugin, checks
## whether the player is signed in and signs in if not. The server-side access
## step that links the account to the backend comes with M4.
##
## The plugin's autoload must be initialized before its sign-in client node
## enters the tree; a client added earlier never answers.

const SIGN_IN_CLASS := "PlayGamesSignInClient"
## The name of both the plugin's autoload node and its Android singleton.
const PLUGIN_NAME := "GodotPlayGameServices"
## Set by CI from the PLAY_GAMES_PROJECT_ID variable (docs/PLUGINS.md).
const SETTING := "aetd/play_games/project_id"
## The sign-in client lives as long as the app (see shared_client).
const CLIENT_NODE := "PluginLabPlayGamesSignIn"

var _client: Node = null


func title() -> String:
	return "Google sign-in (Play Games)"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if not Engine.has_singleton(PLUGIN_NAME):
		return "Plugin not installed (docs/PLUGINS.md)"
	if get_tree().root.get_node_or_null(PLUGIN_NAME) == null:
		return "The plugin's autoload is missing (docs/PLUGINS.md)"
	if _project_id().is_empty():
		return "Plugin installed; Play Games project ID not set yet (docs/PLUGINS.md)"
	return "Plugin installed"


func run() -> void:
	if not Engine.has_singleton(PLUGIN_NAME):
		finish(false, "Play Games Services isn't in this build. Install the plugin (docs/PLUGINS.md).")
		return
	var services: Node = get_tree().root.get_node_or_null(PLUGIN_NAME)
	if services == null:
		finish(false, "The GodotPlayGameServices autoload is missing from project.godot (docs/PLUGINS.md).")
		return
	if not require_api(services, ["initialize"], []):
		return
	# initialize() returns OK only the first time; later calls report
	# PLUGIN_NOT_FOUND although the plugin is ready, so check android_plugin.
	if services.get("android_plugin") == null:
		services.call("initialize")
	if services.get("android_plugin") == null:
		finish(false, "GodotPlayGameServices.initialize() didn't find the Android plugin.")
		return
	if _client == null:
		var script: GDScript = find_api(SIGN_IN_CLASS) as GDScript
		if script == null or not script.can_instantiate():
			finish(false, "No usable %s class. GodotPlayGameServices offers: %s" % [SIGN_IN_CLASS, describe_api(services)])
			return
		# Its _ready() hooks the plugin's signals, so it must enter the tree
		# after initialize().
		_client = shared_client(CLIENT_NODE, script)
	if not require_api(_client, ["is_authenticated", "sign_in"], ["user_authenticated"]):
		return
	if _project_id().is_empty():
		log_line("This build has a placeholder Play Games project ID, so sign-in is expected to fail until it's set (docs/PLUGINS.md).")
	_listen(_on_checked)
	arm_timeout(60.0, "No sign-in answer within 60 seconds.")
	log_line("Checking whether this phone is signed in to Play Games…")
	_client.call("is_authenticated")


func _on_checked(is_authenticated: bool) -> void:
	if is_authenticated:
		finish(true, "Signed in to Play Games.")
		return
	log_line("Not signed in yet. Opening Google sign-in…")
	_listen(_on_signed_in)
	# Picking an account can take a while; give the sign-in screen its own time.
	arm_timeout(180.0, "Sign-in didn't finish within 3 minutes.")
	_client.call("sign_in")


func _on_signed_in(is_authenticated: bool) -> void:
	if is_authenticated:
		finish(true, "Sign-in works: signed in to Play Games.")
	else:
		finish(false, "Sign-in didn't complete. Check the project ID, the OAuth credential's SHA-1 and that your account is a tester (docs/PLUGINS.md).")


## Answers arrive through one signal, so only the current step listens.
func _listen(handler: Callable) -> void:
	for old: Callable in [_on_checked, _on_signed_in]:
		if _client.is_connected("user_authenticated", old):
			_client.disconnect("user_authenticated", old)
	_client.connect("user_authenticated", handler, CONNECT_ONE_SHOT)


func _project_id() -> String:
	return str(ProjectSettings.get_setting(SETTING, "")).strip_edges()
