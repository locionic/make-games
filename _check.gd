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
##
## That fixes `assert()` but not the general case, and the general case is the
## one `report`'s floor closes. A plain runtime error -- an index into a
## Dictionary with no such key -- aborts whichever function it happens in, and
## the caller carries straight on to report() and exits 0. Two measured here,
## both green:
##
## - `_axis_report`, one unmapped card: the whole PLAN.md 1.2 report vanished.
## - `dice.gd::_focus_tests`, one throw on its first line: `test.gd` printed
##   "8167 checks passed" and exited 0, 360 checks short of the 8527 it prints
##   when intact.
##
## Neither is visible except by diffing the printed count against a known one,
## and check() cannot see it: a check that never runs cannot fail.
##
## The fix is a floor, and specifically a floor with *zero margin* -- set equal
## to the count the caller expects, not comfortably below it. A floor set low
## enough to survive ordinary edits catches only a big loss and misses a small
## one exactly when it is cheapest to miss.
##
## The obvious better design is a per-suite `done()` sentinel, and it does not
## work. Written and measured: a throw aborts only the *innermost* function, so
## `self_test()` resumed and reached its own `done()` after `_focus_tests()`
## had already died, and the run stayed green. Moving the sentinel into every
## helper would work and is brittle in the other direction -- a helper added
## without one is uncovered, silently. GDScript has no try/catch, so the floor
## is the only signal available: not what ran, just what is missing.

static var failures: Array[String] = []
static var checks: int = 0

static func check(cond: bool, msg: String = "") -> bool:
	checks += 1
	if not cond:
		failures.append(msg if not msg.is_empty() else "(no message)")
	return cond

## Prints every failure and returns the process exit code: 0 clean, 1 dirty.
## `floor` is how many checks the caller expects to have run; pass the exact
## count, so a shortfall of one is already a failure.
##
## `test.gd` and `_balance.gd` both pass one. `_pack.gd` does not, and that is
## a known gap rather than an oversight: its two report() calls sit at
## different points with different counts, and the number can only be measured
## by running the Android export, which is blocked here. A guessed floor would
## be permanently red, which is worse than none -- the default of 0 means
## "unguarded", not "broken".
static func report(label: String, floor: int = 0) -> int:
	if checks < floor:
		failures.append("%d checks ran, %d expected -- %d never executed. Either a test threw partway (which this gate cannot otherwise see, and which is what this is here for) or the floor is stale and a check was added or removed; the count above is the live one either way"
			% [checks, floor, floor - checks])
	if failures.is_empty():
		print("  %s: %d checks passed" % [label, checks])
		return 0
	# Printed collapsed by message. A check sitting inside a loop over simulated
	# runs appends one entry per iteration: `_balance.gd`'s depth bound, forced
	# red on purpose, emitted one identical line per simulated run and passed
	# 10 MiB of stderr, which the console truncated at 200 lines -- so the copies
	# buried every *other* failure, which is the case this function exists for.
	# The summary count is still the exact total; a repeat is reported as a count
	# rather than dropped, because "failed once" and "failed on every run" are
	# different facts, and `Check.failures` is left undeduplicated because
	# `dice.gd` and `run.gd` both read its size.
	var shown := {}
	for f in failures:
		shown[f] = int(shown.get(f, 0)) + 1
	for f in shown:
		var n: int = shown[f]
		if n == 1:
			push_error("CHECK FAILED [%s]: %s" % [label, f])
		else:
			push_error("CHECK FAILED [%s]: %s  (x%d)" % [label, f, n])
	print("=== %s: %d of %d CHECKS FAILED ===" % [label, failures.size(), checks])
	return 1
