extends Node
## Base for one Plugin Lab check. Each check tries one Android plugin on a real
## phone and reports what happened through logged and finished.
##
## Checks never name a plugin's classes in code. They look them up at run time,
## so this project still compiles when a plugin isn't installed (on desktop, or
## before tools fetch it), and an API that differs from what a check expects is
## reported instead of crashing.

signal logged(text: String)
signal finished(ok: bool)

var _done: bool = false
var _run_id: int = 0
var _timer_id: int = 0


func title() -> String:
	return "Check"


## One line saying whether this build contains the plugin.
func availability() -> String:
	return ""


## Starts a run. The Lab calls this, never run() directly: it clears the result
## of any earlier run and makes that run's pending timeout harmless.
func start() -> void:
	_done = false
	_run_id += 1
	_timer_id += 1
	run()


## The check itself, implemented by each check.
func run() -> void:
	finish(false, "not implemented")


func log_line(text: String) -> void:
	print("[Plugin Lab] %s: %s" % [title(), text])
	logged.emit(text)


func finish(ok: bool, text: String) -> void:
	if _done:
		return
	_done = true
	log_line(text)
	finished.emit(ok)


## Fails the current run if it hasn't finished within the given time. Arming
## again replaces the earlier deadline, and a new run cancels it too.
func arm_timeout(seconds: float, message: String) -> void:
	_timer_id += 1
	var timer_id: int = _timer_id
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if timer_id == _timer_id:
			finish(false, message)
	)


## Finds an API an addon registers: a global class (class_name), an autoload
## node or an Engine singleton, in that order. Returns null if none exists.
func find_api(api_name: String) -> Object:
	for entry in ProjectSettings.get_global_class_list():
		if entry["class"] == api_name:
			return load(entry["path"])
	var autoload: Node = get_tree().root.get_node_or_null(api_name)
	if autoload != null:
		return autoload
	if Engine.has_singleton(api_name):
		return Engine.get_singleton(api_name)
	return null


## Returns the app-wide instance of a plugin's client node, creating it under
## the tree root on first use. The Lab's checks are freed when you leave the
## screen, but a plugin client must live as long as the app: a new one would
## start the plugin's Android side again.
func shared_client(node_name: String, script: GDScript) -> Node:
	var root: Window = get_tree().root
	var client: Node = root.get_node_or_null(node_name)
	if client == null:
		client = script.new()
		client.name = node_name
		root.add_child(client)
	return client


## Lists what an object offers, so an API mismatch shows the real names.
static func describe_api(obj: Object) -> String:
	var methods := PackedStringArray()
	var signals := PackedStringArray()
	var script: Script = obj as Script
	if script == null and obj.get_script() != null:
		script = obj.get_script()
	if script != null:
		for method in script.get_script_method_list():
			methods.append(str(method["name"]))
		for sig in script.get_script_signal_list():
			signals.append(str(sig["name"]))
	else:
		for method in obj.get_method_list():
			methods.append(str(method["name"]))
		for sig in obj.get_signal_list():
			signals.append(str(sig["name"]))
	var text: String = "methods: %s; signals: %s" % [", ".join(methods), ", ".join(signals)]
	if obj.has_method("has_java_method"):
		text += " (an Android plugin: its Java methods can't be listed, its signals can)"
	return text


## True if obj offers the method. An Android plugin's Engine singleton is a
## JNISingleton: Godot 4.7 keeps its Java methods out of ClassDB, so has_method()
## is false for them and has_java_method() answers instead.
static func has_api_method(obj: Object, method: String) -> bool:
	if obj.has_method(method):
		return true
	if obj.has_method("has_java_method"):
		return bool(obj.call("has_java_method", method))
	return false


## True if obj has every named method and signal; otherwise finishes the check
## with the plugin's real API listed.
func require_api(obj: Object, methods: Array, signals: Array) -> bool:
	for method in methods:
		if not has_api_method(obj, method):
			finish(false, "The plugin has no method %s. %s" % [method, describe_api(obj)])
			return false
	for sig in signals:
		if not obj.has_signal(sig):
			finish(false, "The plugin has no signal %s. %s" % [sig, describe_api(obj)])
			return false
	return true
