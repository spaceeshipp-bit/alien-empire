extends "res://plugin_lab/lab_check.gd"
## Push notifications through Firebase Cloud Messaging with the Godotx Firebase
## plugin (Godot 4.7+). Initializes Firebase, asks for notification permission
## and fetches this phone's FCM token. Sending a test message to that token from
## the Firebase console completes the check (docs/PLUGINS.md).

var _core: Object = null
var _messaging: Object = null


func title() -> String:
	return "Push notifications (FCM)"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if Engine.has_singleton("GodotxFirebaseCore") and Engine.has_singleton("GodotxFirebaseMessaging"):
		return "Plugin installed"
	return "Plugin not installed (docs/PLUGINS.md)"


func run() -> void:
	if not (Engine.has_singleton("GodotxFirebaseCore") and Engine.has_singleton("GodotxFirebaseMessaging")):
		finish(false, "Firebase Core or Messaging isn't in this build. Install the plugin and google-services.json (docs/PLUGINS.md).")
		return
	_core = Engine.get_singleton("GodotxFirebaseCore")
	_messaging = Engine.get_singleton("GodotxFirebaseMessaging")
	if not require_api(_core, ["initialize"], ["core_initialized"]):
		return
	var methods := ["initialize", "request_permission", "get_token"]
	var signals := ["messaging_token_received", "messaging_permission_granted", "messaging_permission_denied", "messaging_error", "messaging_message_received"]
	if not require_api(_messaging, methods, signals):
		return
	_core.connect("core_initialized", _on_core_initialized)
	_messaging.connect("messaging_permission_granted", _on_permission_granted)
	_messaging.connect("messaging_permission_denied", _on_permission_denied)
	_messaging.connect("messaging_token_received", _on_token)
	_messaging.connect("messaging_error", _on_error)
	_messaging.connect("messaging_message_received", _on_message)
	arm_timeout(60.0, "No FCM token within 60 seconds.")
	log_line("Starting Firebase…")
	_core.call("initialize")


func _on_core_initialized(success: bool) -> void:
	if not success:
		finish(false, "Firebase didn't start. Check google-services.json matches this package name.")
		return
	log_line("Firebase started. Asking for notification permission…")
	_messaging.call("initialize")
	_messaging.call("request_permission")


func _on_permission_granted() -> void:
	log_line("Permission granted. Fetching this phone's FCM token…")
	_messaging.call("get_token")


func _on_permission_denied() -> void:
	finish(false, "Notification permission is off. Allow it in Android settings and run again.")


func _on_token(token: String) -> void:
	print("[Plugin Lab] FCM token: %s" % token)
	finish(true, "Push is set up: got an FCM token (%s…). Send a test message to it from the Firebase console; it should appear below." % token.substr(0, 12))


func _on_error(message: String) -> void:
	finish(false, "Firebase Messaging error: %s" % message)


func _on_message(message_title: String, body: String) -> void:
	log_line("Message received: %s — %s" % [message_title, body])
