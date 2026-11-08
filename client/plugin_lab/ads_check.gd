extends "res://plugin_lab/lab_check.gd"
## Rewarded ads through Poing Studios' AdMob plugin (v5.1.0, which wraps Google's
## GMA Next-Gen SDK 1.4.0). Initializes the SDK, loads Google's demo rewarded
## unit, shows it and waits for the reward. Demo units always serve test ads, so
## this is safe on any phone. The plugin's export plugin writes the AdMob app id
## into the manifest from the project setting admob/general/android/app_id,
## which defaults to Google's sample app id. Setup: docs/PLUGINS.md.

## Google's demo rewarded ad unit for Android:
## https://developers.google.com/admob/android/next-gen/test-ads
const DEMO_REWARDED_UNIT := "ca-app-pub-3940256099942544/5224354917"
## Global script classes (class_name) the plugin's GDScript API registers.
const API_CLASSES := [
	"MobileAds",
	"OnInitializationCompleteListener",
	"RewardedAdLoader",
	"AdRequest",
	"RewardedAdLoadCallback",
	"OnUserEarnedRewardListener",
]
## Engine singletons the plugin's Android AAR registers (its manifest's
## org.godotengine.plugin.v2.* entries).
const NATIVE_SINGLETONS := ["PoingGodotAdMob", "PoingGodotAdMobRewardedAd"]

## Initialize the SDK once per app session; later runs go straight to loading.
static var _sdk_ready: bool = false

var _api: Dictionary = {}
var _ad: Object = null
var _rewarded: bool = false


func title() -> String:
	return "AdMob rewarded ad"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	if find_api("MobileAds") == null:
		return "Plugin not installed (docs/PLUGINS.md)"
	for singleton in NATIVE_SINGLETONS:
		if not Engine.has_singleton(singleton):
			return "Plugin scripts found, but this APK has no %s (needs a Gradle build)" % singleton
	return "Plugin installed"


func run() -> void:
	arm_timeout(60.0, "No ad loaded within 60 seconds.")
	_ad = null
	_rewarded = false
	_api.clear()
	for api_name in API_CLASSES:
		var api: Object = find_api(api_name)
		if api == null:
			finish(false, "AdMob class %s missing. Install the plugin (docs/PLUGINS.md)." % api_name)
			return
		_api[api_name] = api
	for singleton in NATIVE_SINGLETONS:
		if not Engine.has_singleton(singleton):
			finish(false, "The native AdMob plugin %s isn't in this APK. Export with Gradle build on and admob/general/android/enabled true." % singleton)
			return
	if not require_api(_api["MobileAds"], ["initialize", "get_version", "get_platform_version"], []):
		return
	if _sdk_ready:
		_load_ad()
		return
	log_line("Initializing the Mobile Ads SDK…")
	var listener: Object = (_api["OnInitializationCompleteListener"] as GDScript).new()
	if not _hook(listener, "on_initialization_complete", _on_initialized):
		return
	_api["MobileAds"].call("initialize", listener)


func _on_initialized(status: Object) -> void:
	_sdk_ready = true
	if _done:
		return
	var adapters: Dictionary = {}
	if status != null and "adapter_status_map" in status:
		adapters = status.get("adapter_status_map")
	log_line("SDK ready (plugin %s, SDK %s, %d adapters)." % [
		_api["MobileAds"].call("get_version"),
		_api["MobileAds"].call("get_platform_version"),
		adapters.size(),
	])
	_load_ad()


func _load_ad() -> void:
	var callback: Object = (_api["RewardedAdLoadCallback"] as GDScript).new()
	if not _hook(callback, "on_ad_loaded", _on_ad_loaded):
		return
	if not _hook(callback, "on_ad_failed_to_load", _on_ad_failed_to_load):
		return
	log_line("Loading Google's demo rewarded ad…")
	# The loader keeps itself alive until it answers (it calls reference()).
	var loader: Object = (_api["RewardedAdLoader"] as GDScript).new()
	loader.call("load", DEMO_REWARDED_UNIT, (_api["AdRequest"] as GDScript).new(), callback)


func _on_ad_loaded(ad: Object) -> void:
	if _done:
		return
	# RewardedAd is RefCounted and only this script holds it; keep it until dismissed.
	_ad = ad
	arm_timeout(120.0, "The ad loaded but no reward arrived within 2 minutes.")
	if not require_api(ad, ["show", "destroy"], []):
		return
	var content: Object = ad.get("full_screen_content_callback")
	if content == null:
		finish(false, "RewardedAd has no full_screen_content_callback. %s" % describe_api(ad))
		return
	if not _hook(content, "on_ad_showed_full_screen_content", _on_ad_showed):
		return
	if not _hook(content, "on_ad_failed_to_show_full_screen_content", _on_ad_failed_to_show):
		return
	if not _hook(content, "on_ad_dismissed_full_screen_content", _on_ad_dismissed):
		return
	var listener: Object = (_api["OnUserEarnedRewardListener"] as GDScript).new()
	if not _hook(listener, "on_user_earned_reward", _on_user_earned_reward):
		return
	log_line("Demo ad loaded. Showing it…")
	ad.call("show", listener)


func _on_ad_showed() -> void:
	log_line("The ad is on screen. Watch it to the end to get the reward.")


func _on_ad_failed_to_show(error: Object) -> void:
	finish(false, "The ad loaded but failed to show: %s" % _describe_error(error))


func _on_user_earned_reward(item: Object) -> void:
	_rewarded = true
	var amount: Variant = item.get("amount") if item != null else "?"
	var reward_type: Variant = item.get("type") if item != null else "?"
	finish(true, "AdMob works: Google's demo rewarded ad played and granted %s %s." % [amount, reward_type])


func _on_ad_dismissed() -> void:
	log_line("The ad was closed.")
	var run_id: int = _run_id
	var ad: Object = _ad
	# The reward callback can land just after the dismissal, so keep the ad
	# (which holds the reward listener) a moment longer before destroying it.
	await get_tree().create_timer(1.0).timeout
	if ad != null:
		ad.call("destroy")
	if _ad == ad:
		_ad = null
	if not _rewarded and run_id == _run_id:
		finish(false, "The ad closed before the SDK granted the reward. Run again and watch it to the end.")


func _on_ad_failed_to_load(error: Object) -> void:
	finish(false, "The ad failed to load: %s" % _describe_error(error))


## Sets a Callable property on one of the plugin's callback objects, or fails
## the check and lists the object's real properties if it doesn't have it.
func _hook(obj: Object, property: String, callable: Callable) -> bool:
	if property in obj:
		obj.set(property, callable)
		return true
	var names := PackedStringArray()
	for prop in obj.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(str(prop["name"]))
	finish(false, "The plugin's %s has no %s. Its properties: %s" % [
		obj.get_script().resource_path.get_file(), property, ", ".join(names)])
	return false


## AdError and LoadAdError carry code, domain and message; LoadAdError adds
## response_info. The plugin passes null when the SDK sent no details.
static func _describe_error(error: Object) -> String:
	if error == null:
		return "no details from the SDK"
	return "code %s (%s): %s" % [error.get("code"), error.get("domain"), error.get("message")]
