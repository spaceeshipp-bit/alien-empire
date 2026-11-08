extends "res://plugin_lab/lab_check.gd"
## Push notifications through Firebase Cloud Messaging with Godotx Firebase 3.1.0
## (Core + Messaging, Godot 4.7+). Starts Firebase, asks for notification
## permission and fetches this phone's FCM token. Sending a test message to that
## token from the Firebase console completes the check (docs/PLUGINS.md).

const CORE := "GodotxFirebaseCore"
const MESSAGING := "GodotxFirebaseMessaging"

var _core: Object = null
var _messaging: Object = null
## Firebase can hand over a token before Android answers the permission
## request, so the check only passes once permission is granted.
var _permission_ok: bool = false


func title() -> String:
	return "Push notifications (FCM)"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if Engine.has_singleton(CORE) and Engine.has_singleton(MESSAGING):
		return "Plugin installed"
	return "Plugin not installed (docs/PLUGINS.md)"


func run() -> void:
	if not (Engine.has_singleton(CORE) and Engine.has_singleton(MESSAGING)):
		finish(false, "Firebase Core or Messaging isn't in this build. Install the plugin (docs/PLUGINS.md).")
		return
	if _core == null and not _connect_plugin():
		return
	_permission_ok = false
	arm_timeout(60.0, "No FCM token within 60 seconds.")
	log_line("Starting Firebase…")
	_core.call("initialize")


## Connects to both singletons once; the plugin's signals outlive each run.
func _connect_plugin() -> bool:
	var core: Object = Engine.get_singleton(CORE)
	var messaging: Object = Engine.get_singleton(MESSAGING)
	if not require_api(core, ["initialize"], ["core_initialized", "core_error"]):
		return false
	var methods := ["initialize", "request_permission", "get_token"]
	var signals := ["messaging_token_received", "messaging_permission_granted", "messaging_permission_denied", "messaging_error", "messaging_message_received"]
	if not require_api(messaging, methods, signals):
		return false
	_core = core
	_messaging = messaging
	_core.connect("core_initialized", _on_core_initialized)
	_core.connect("core_error", func(message: String) -> void: log_line("Firebase Core error: %s" % message))
	_messaging.connect("messaging_permission_granted", _on_permission_granted)
	_messaging.connect("messaging_permission_denied", _on_permission_denied)
	_messaging.connect("messaging_token_received", _on_token)
	_messaging.connect("messaging_error", _on_error)
	_messaging.connect("messaging_message_received", _on_message)
	return true


func _on_core_initialized(success: bool) -> void:
	if not success:
		finish(false, "Firebase failed to start (see the Core error above).")
		return
	# Success here doesn't prove Firebase is configured: Messaging reports
	# firebase_not_initialized next if google-services.json was missing.
	log_line("Firebase started. Asking for notification permission…")
	_messaging.call("initialize")
	_messaging.call("request_permission")


func _on_permission_granted() -> void:
	_permission_ok = true
	log_line("Permission granted. Fetching this phone's FCM token…")
	_messaging.call("get_token")


func _on_permission_denied() -> void:
	finish(false, "Notification permission is off. Allow it in Android settings and run again.")


func _on_token(token: String) -> void:
	if _done:
		return
	if not _permission_ok:
		log_line("Got a token; waiting for the notification permission answer…")
		return
	log_line("FCM token (copy it with the button below):\n%s" % token)
	finish(true, "Push is set up. Send a test message to this token from the Firebase console. With this screen open it appears here; with the app in the background it shows as a notification.")


func _on_error(message: String) -> void:
	if message == "firebase_not_initialized":
		finish(false, "Firebase isn't configured in this build: it was built without google-services.json (docs/PLUGINS.md).")
		return
	finish(false, "Firebase Messaging error: %s" % message)


func _on_message(message_title: String, body: String) -> void:
	if message_title.is_empty() and body.is_empty():
		# Android doesn't pass on a tapped notification's title and text.
		log_line("Message received (opened from its notification).")
		return
	log_line("Message received: %s: %s" % [message_title, body])
