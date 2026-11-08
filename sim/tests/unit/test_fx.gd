extends "res://sim/tests/test_case.gd"

const Fx := preload("res://sim/core/fx.gd")


func test_isqrt_vectors() -> bool:
	var doc: Dictionary = load_json("res://sim/tests/vectors/isqrt_vectors.json")
	var rows: Array = doc.get("isqrt", [])
	expect_true(rows.size() > 20, "isqrt vectors loaded")
	for row in rows:
		var n: int = int(row[0])
		expect_eq(Fx.isqrt(n), int(row[1]), "isqrt(%d)" % n)
	return true


func test_isqrt_of_negative_is_zero() -> bool:
	expect_eq(Fx.isqrt(-5), 0, "isqrt(-5)")
	return true


func test_ms_to_ticks() -> bool:
	expect_eq(Fx.ms_to_ticks(0), 0, "0 ms")
	expect_eq(Fx.ms_to_ticks(50), 1, "50 ms")
	expect_eq(Fx.ms_to_ticks(3000), 60, "3000 ms")
	return true


## The sim relies on integer division truncating toward zero everywhere.
func test_integer_division_truncates_toward_zero() -> bool:
	var a: int = -7
	var b: int = 2
	var c: int = 7
	expect_eq(a / b, -3, "-7 / 2")
	expect_eq(a % b, -1, "-7 % 2")
	expect_eq(c / -b, -3, "7 / -2")
	var d: int = -9000
	var e: int = 5000
	expect_eq(d / e, -1, "-9000 / 5000")
	return true


## Bit operations on values below 2^32 must behave as unsigned 32-bit math.
func test_shifts_on_32_bit_values() -> bool:
	var x: int = 0xFFFFFFFF
	expect_eq(x >> 16, 0xFFFF, "logical shift of a 32-bit value")
	expect_eq((x << 9) & 0xFFFFFFFF, 0xFFFFFE00, "masked left shift")
	expect_eq(x ^ 0xFFFF0000, 0x0000FFFF, "xor")
	return true
