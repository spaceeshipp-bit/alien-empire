extends "res://plugin_lab/lab_check.gd"
## Rewarded ads through the AdMob plugin by Poing Studios (Godot 4.5+).
## Initializes the SDK, loads Google's demo rewarded ad unit and shows it.
## Demo units always serve test ads, so this is safe on any phone. Setup
## (AdMob app id in the export): docs/PLUGINS.md.

## Google's demo rewarded ad unit for Android:
## https://developers.google.com/admob/android/test-ads
const DEMO_REWARDED_UNIT := "ca-app-pub-3940256099942544/5224354917"

var _ad: Object = null


func title() -> String:
	return "AdMob rewarded ad"


func availability() -> String:
	if OS.get_name() != "Android":
		return "Needs an Android phone"
	return "Plugin installed" if find_api("MobileAds") != null else "Plugin not installed (docs/PLUGINS.md)"


func run() -> void:
	var mobile_ads: Object = find_api("MobileAds")
	var loader_script: GDScript = find_api("RewardedAdLoader") as GDScript
	var request_script: GDScript = find_api("AdRequest") as GDScript
	var callback_script: GDScript = find_api("RewardedAdLoadCallback") as GDScript
	if mobile_ads == null or loader_script == null or request_script == null or callback_script == null:
		finish(false, "AdMob classes missing (MobileAds, RewardedAdLoader, AdRequest, RewardedAdLoadCallback). Install the plugin (docs/PLUGINS.md).")
		return
	log_line("Initializing the Mobile Ads SDK…")
	mobile_ads.call("initialize")
	var callback: Object = callback_script.new()
	for property in ["on_ad_loaded", "on_ad_failed_to_load"]:
		if not (property in callback):
			finish(false, "RewardedAdLoadCallback has no %s. %s" % [property, describe_api(callback)])
			return
	callback.set("on_ad_loaded", _on_ad_loaded)
	callback.set("on_ad_failed_to_load", _on_ad_failed)
	arm_timeout(45.0, "No ad loaded within 45 seconds.")
	log_line("Loading Google's demo rewarded ad…")
	loader_script.new().call("load", DEMO_REWARDED_UNIT, request_script.new(), callback)


func _on_ad_loaded(ad: Object) -> void:
	_ad = ad
	log_line("Demo ad loaded. Showing it…")
	var listener_script: GDScript = find_api("OnUserEarnedRewardListener") as GDScript
	if listener_script != null:
		var listener: Object = listener_script.new()
		if "on_user_earned_reward" in listener:
			listener.set("on_user_earned_reward", func(reward: Object) -> void:
				log_line("Reward granted by the SDK: %s" % str(reward))
			)
		ad.call("show", listener)
	else:
		ad.call("show")
	finish(true, "AdMob works: Google's demo rewarded ad loaded and opened.")


func _on_ad_failed(error: Object) -> void:
	var detail: String = str(error)
	if error != null and "message" in error:
		detail = str(error.get("message"))
	finish(false, "The ad failed to load: %s" % detail)
