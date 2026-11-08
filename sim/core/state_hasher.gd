extends RefCounted
## SHA-256 over a stream of values: each int as 8 bytes little-endian, each
## string as its UTF-8 byte count (an int) followed by its bytes. Golden tests
## compare these hashes across desktop, Android and the headless worker.

var _bytes: PackedByteArray = PackedByteArray()
var _size: int = 0


func add_int(value: int) -> void:
	_bytes.resize(_size + 8)
	_bytes.encode_s64(_size, value)
	_size += 8


func add_ints(values: PackedInt64Array) -> void:
	for value in values:
		add_int(value)


func add_string(text: String) -> void:
	var utf8: PackedByteArray = text.to_utf8_buffer()
	add_int(utf8.size())
	_bytes.append_array(utf8)
	_size += utf8.size()


## Lower-case hex digest of everything added so far.
func finish_hex() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if _size > 0:
		ctx.update(_bytes)
	return ctx.finish().hex_encode()
