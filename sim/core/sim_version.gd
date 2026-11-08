extends RefCounted
## Version of the battle rules, defined in the sim core
## (sim/native/src/core/fx.h). Raise it there whenever a change could alter any
## battle's result. Battle records store it, the server keeps every version
## still in use, and golden hashes must be re-recorded when it changes.

const SIM_VERSION: int = SimNative.SIM_VERSION
