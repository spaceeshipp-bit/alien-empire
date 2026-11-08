extends RefCounted
## SHA-256 over a stream of values: each int as 8 bytes little-endian, each
## string as its UTF-8 byte count (an int) followed by its bytes. Computed by the
## sim core (sim/native/src/core/state_hasher.h). Golden tests compare these
## hashes across desktop, Android and the headless worker.

var _native := SimNativeHasher.new()


func add_int(value: int) -> void:
	_native.add_int(value)


func add_ints(values: PackedInt64Array) -> void:
	_native.add_ints(values)


func add_string(text: String) -> void:
	_native.add_string(text)


## Lower-case hex digest of everything added so far.
func finish_hex() -> String:
	return _native.finish_hex()
