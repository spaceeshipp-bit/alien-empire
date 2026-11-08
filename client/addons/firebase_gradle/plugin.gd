@tool
extends EditorPlugin
## Godotx Firebase needs the google-services Gradle plugin in the Android build
## template (its README, "Configure Android Gradle"). CI reinstalls the template
## on every export, which would undo a one-time edit, so this export plugin
## makes the edit at the start of each Android export instead.
##
## It only does so when res://google-services.json exists: without that file
## the Gradle plugin fails the build, while an unpatched build still works and
## the Plugin Lab reports Firebase as not configured.

var _export_plugin: EditorExportPlugin = null


func _enter_tree() -> void:
	_export_plugin = FirebaseGradleExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class FirebaseGradleExport extends EditorExportPlugin:
	const BUILD_GRADLE := "res://android/build/build.gradle"
	const CONFIG := "res://google-services.json"
	## The version Godotx Firebase 3.1.0's README asks for.
	const CLASSPATH := "com.google.gms:google-services:4.4.4"
	## Must come before the template's plugins block.
	const HEAD := """buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath '%s'
    }
}

"""
	const TAIL := "\n// Added by addons/firebase_gradle for Godotx Firebase.\napply plugin: 'com.google.gms.google-services'\n"

	func _get_name() -> String:
		return "FirebaseGradle"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android") or not FileAccess.file_exists(CONFIG):
			return
		if not FileAccess.file_exists(BUILD_GRADLE):
			push_error("[FirebaseGradle] %s is missing. Install the Android build template first." % BUILD_GRADLE)
			return
		var text: String = FileAccess.get_file_as_string(BUILD_GRADLE)
		if text.contains("com.google.gms:google-services"):
			return
		var file := FileAccess.open(BUILD_GRADLE, FileAccess.WRITE)
		if file == null:
			push_error("[FirebaseGradle] Can't write %s." % BUILD_GRADLE)
			return
		file.store_string(HEAD % CLASSPATH + text + TAIL)
		file.close()
		print("[FirebaseGradle] Applied the google-services Gradle plugin to %s" % BUILD_GRADLE)
