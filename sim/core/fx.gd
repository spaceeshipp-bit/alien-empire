extends RefCounted
## Integer helpers for the sim. The sim never uses floating point: HP and damage
## are stored x100, distances in thousandths of a tile (mt), percentages in basis
## points (10000 = 100%) and time in 50 ms ticks.
##
## GDScript integer division truncates toward zero (it runs as C++ int64
## division on every platform). The sim relies on that, and the unit tests
## check it on each platform.

const TICK_RATE: int = 20
const MS_PER_TICK: int = 50


## Milliseconds to ticks. Callers make sure ms is a multiple of MS_PER_TICK.
static func ms_to_ticks(ms: int) -> int:
	return ms / MS_PER_TICK


## Floor of the square root of n, by Newton's method on integers.
## Valid for 0 <= n < 2^62; returns 0 for negative n.
static func isqrt(n: int) -> int:
	if n < 2:
		return maxi(n, 0)
	var x: int = n
	var y: int = (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x
