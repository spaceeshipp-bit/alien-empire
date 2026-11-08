extends "res://plugin_lab/lab_check.gd"
## Google Play Billing through GodotGooglePlayBilling 3.3.0 (godot-sdk-integrations,
## Play Billing Library 9.1.0). Connects to Play, asks for one test product and
## lists existing subscriptions. A pass means the plugin talks to Google Play on
## this phone; real purchases come with the store in M9.
## Setup (Play Console app, test product, license tester): docs/PLUGINS.md.

## In-app product created in Play Console for this test.
const TEST_PRODUCT := "m0_test_gems"
## The plugin's Android library registers this Engine singleton.
const SINGLETON := "GodotGooglePlayBilling"

## One client for the app's lifetime (see shared_client): every
## BillingClient.new() re-initializes the plugin's Android side.
const CLIENT_NODE := "PluginLabBillingClient"

var _client: Node = null
var _consts: Dictionary = {}
var _found_product: bool = false


func title() -> String:
	return "Play Billing"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if find_api("BillingClient") == null:
		return "Plugin not installed (docs/PLUGINS.md)"
	if not Engine.has_singleton(SINGLETON):
		return "Addon present, but its Android library isn't in this build"
	return "Plugin installed"


func run() -> void:
	var script: GDScript = find_api("BillingClient") as GDScript
	if script == null:
		finish(false, "BillingClient isn't in this build. Install the plugin (docs/PLUGINS.md).")
		return
	if not Engine.has_singleton(SINGLETON):
		finish(false, "The %s Android library isn't in this build. Enable the plugin and export again." % SINGLETON)
		return
	if _client == null and not _attach_client(script):
		return
	arm_timeout(30.0, "No answer from Google Play within 30 seconds.")
	_found_product = false
	var connecting: int = int(_consts.get("ConnectionState", {}).get("CONNECTING", 1))
	if bool(_client.call("is_ready")):
		_on_connected()
	elif int(_client.call("get_connection_state")) == connecting:
		# Asking again while connecting makes Play answer DEVELOPER_ERROR.
		log_line("Still connecting to Google Play Billing…")
	else:
		log_line("Connecting to Google Play Billing…")
		_client.call("start_connection")


## Connects this check to the app-wide client. The connections end by
## themselves when this check is freed with the Lab screen.
func _attach_client(script: GDScript) -> bool:
	var client: Node = shared_client(CLIENT_NODE, script)
	var methods := ["start_connection", "is_ready", "get_connection_state", "query_product_details", "query_purchases"]
	var signals := ["connected", "disconnected", "connect_error", "query_product_details_response", "query_purchases_response"]
	if not require_api(client, methods, signals):
		return false
	_client = client
	_consts = script.get_script_constant_map()
	_client.connect("connected", _on_connected)
	_client.connect("disconnected", _on_disconnected)
	_client.connect("connect_error", _on_connect_error)
	_client.connect("query_product_details_response", _on_product_details)
	_client.connect("query_purchases_response", _on_purchases)
	return true


func _on_disconnected() -> void:
	log_line("Disconnected from Google Play Billing.")


func _on_connected() -> void:
	log_line("Connected. Asking Play for product %s…" % TEST_PRODUCT)
	_client.call("query_product_details", PackedStringArray([TEST_PRODUCT]), _product_type("INAPP"))


func _on_connect_error(code: int, message: String) -> void:
	finish(false, "Couldn't connect to Play Billing: %s %s" % [_code_name(code), message])


func _on_product_details(response: Dictionary) -> void:
	var code: int = int(response.get("response_code", -999))
	if code != 0:
		finish(false, "Product query failed: %s %s" % [_code_name(code), response.get("debug_message", "")])
		return
	for details in response.get("product_details", []):
		if str(details.get("product_id", "")) != TEST_PRODUCT:
			continue
		_found_product = true
		var offers: Variant = details.get("one_time_purchase_offer_details_list")
		var price: String = "?"
		if offers is Array and not offers.is_empty():
			price = str(offers[0].get("formatted_price", "?"))
		log_line("Play knows %s: %s, %s." % [TEST_PRODUCT, details.get("title", ""), price])
	for missing in response.get("unfetched_products", []):
		log_line("Play didn't return %s (status %d: 3 means not found yet, 4 no eligible offer, 2 bad id)." % [
			missing.get("product_id", ""), int(missing.get("status_code", 0)),
		])
	log_line("Asking Play for this account's subscriptions…")
	_client.call("query_purchases", _product_type("SUBS"))


func _on_purchases(response: Dictionary) -> void:
	var code: int = int(response.get("response_code", -999))
	if code != 0:
		finish(false, "Subscription query failed: %s %s" % [_code_name(code), response.get("debug_message", "")])
		return
	# Purchases carry tokens and signatures, so only the count is shown.
	var count: int = response.get("purchases", []).size()
	if _found_product:
		finish(true, "Billing works: Play returned %s and answered the subscription query (%d active)." % [TEST_PRODUCT, count])
	else:
		finish(false, "Play answered, but didn't return %s. Check the product is Active in Play Console and this phone's account is a license tester (docs/PLUGINS.md)." % TEST_PRODUCT)


func _product_type(type_name: String) -> int:
	return int(_consts.get("ProductType", {}).get(type_name, 0 if type_name == "INAPP" else 1))


func _code_name(code: int) -> String:
	var names: Dictionary = _consts.get("BillingResponseCode", {})
	for key in names:
		if int(names[key]) == code:
			return "%s (%d)" % [key, code]
	return str(code)
