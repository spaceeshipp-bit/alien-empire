extends RefCounted
## Version of the battle rules. Raise it whenever a change under sim/ could
## change any battle's result. Battle records store it, the server keeps every
## version still in use, and golden hashes must be re-recorded when it changes.

const SIM_VERSION: int = 1
