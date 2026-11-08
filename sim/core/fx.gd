extends RefCounted
## Integer helpers for the sim. The sim never uses floating point: HP and damage
## are stored x100, distances in thousandths of a tile (mt), percentages in basis
## points (10000 = 100%) and time in 50 ms ticks.
##
## GDScript integer division truncates toward zero, like the C++ sim core's
## (sim/native). The unit tests check it on each platform.

const TICK_RATE: int = 20
const MS_PER_TICK: int = 50


## Milliseconds to ticks. Callers make sure ms is a multiple of MS_PER_TICK.
static func ms_to_ticks(ms: int) -> int:
	return ms / MS_PER_TICK


## Floor of the square root of n, for 0 <= n < 2^62; 0 for negative n.
## Computed by the sim core (sim/native/src/core/fx.h).
static func isqrt(n: int) -> int:
	return SimNative.isqrt(n)
