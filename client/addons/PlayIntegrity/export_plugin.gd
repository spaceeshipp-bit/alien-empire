@tool
extends EditorPlugin
## Adds the PlayIntegrity Android plugin to Android exports (Godot's v2 plugin
## format: an AAR plus this export plugin). Build the AARs first with
## tools/build_android_plugins.sh; they land in addons/PlayIntegrity/bin/.

var _export_plugin: AndroidExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const PLUGIN_NAME := "PlayIntegrity"
	## Keep in step with client/android_plugins/play_integrity/plugin/build.gradle.
	const DEPENDENCIES := ["com.google.android.play:integrity:1.6.0"]

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if debug:
			return PackedStringArray(["PlayIntegrity/bin/PlayIntegrity-debug.aar"])
		return PackedStringArray(["PlayIntegrity/bin/PlayIntegrity-release.aar"])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(DEPENDENCIES)

	func _get_name() -> String:
		return PLUGIN_NAME
