extends RefCounted
## Shared failure registry for the headless self-tests.
##
## Godot's `assert()` cannot gate a headless suite: on failure it prints
## `SCRIPT ERROR:` and aborts the rest of the calling function, so
## `test.gd::_init()` never reaches `quit()` and the SceneTree hangs instead
## of exiting non-zero. A failing suite and a passing suite were therefore
## indistinguishable except by waiting for a timeout -- and only the FIRST
## failure was ever visible.
##
## check() records and keeps going, so the run reports every failure and
## exits 0 or 1 cleanly.

static var failures: Array[String] = []
static var checks: int = 0

static func check(cond: bool, msg: String = "") -> bool:
	checks += 1
	if not cond:
		failures.append(msg if not msg.is_empty() else "(no message)")
	return cond

## Prints every failure and returns the process exit code: 0 clean, 1 dirty.
static func report(label: String) -> int:
	if failures.is_empty():
		print("  %s: %d checks passed" % [label, checks])
		return 0
	for f in failures:
		push_error("CHECK FAILED [%s]: %s" % [label, f])
	print("=== %s: %d of %d CHECKS FAILED ===" % [label, failures.size(), checks])
	return 1
