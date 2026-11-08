extends "res://plugin_lab/lab_check.gd"
## Google Play Billing through the GodotGooglePlayBilling plugin
## (godot-sdk-integrations, Godot 4.2+). Connects to Play, asks for one test
## product and lists existing subscriptions. A pass means the plugin talks to
## Google Play on this phone; real purchases come with the store in M9.
## Setup (Play Console app, test product, license testers): docs/PLUGINS.md.

## In-app product created in Play Console for this test.
const TEST_PRODUCT := "m0_test_gems"

var _client: Object = null
var _product_types: Dictionary = {}


func title() -> String:
	return "Play Billing"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	return "Plugin installed" if find_api("BillingClient") != null else "Plugin not installed (docs/PLUGINS.md)"


func run() -> void:
	var script: GDScript = find_api("BillingClient") as GDScript
	if script == null:
		finish(false, "BillingClient isn't in this build. Install the plugin (docs/PLUGINS.md).")
		return
	_client = script.new()
	if _client is Node:
		add_child(_client)
	_product_types = script.get_script_constant_map().get("ProductType", {})
	var methods := ["start_connection", "query_product_details", "query_purchases"]
	var signals := ["connected", "connect_error", "query_product_details_response", "query_purchases_response"]
	if not require_api(_client, methods, signals):
		return
	_client.connect("connected", _on_connected)
	_client.connect("connect_error", _on_connect_error)
	_client.connect("query_product_details_response", _on_product_details)
	_client.connect("query_purchases_response", _on_purchases)
	arm_timeout(30.0, "No answer from Google Play within 30 seconds.")
	log_line("Connecting to Google Play Billing…")
	_client.call("start_connection")


func _on_connected() -> void:
	log_line("Connected. Asking Play for product %s…" % TEST_PRODUCT)
	_client.call("query_product_details", [TEST_PRODUCT], _product_types.get("INAPP", 0))


func _on_connect_error(code: int, message: String) -> void:
	finish(false, "Couldn't connect to Play Billing: %d %s" % [code, message])


func _on_product_details(response: Dictionary) -> void:
	log_line("Product answer: %s" % str(response))
	_client.call("query_purchases", _product_types.get("SUBS", 1))


func _on_purchases(response: Dictionary) -> void:
	log_line("Subscriptions answer: %s" % str(response))
	var code: int = int(response.get("response_code", 0))
	if code == 0:
		finish(true, "Billing works: Google Play answered both queries.")
	else:
		finish(false, "Google Play answered with response code %d." % code)
