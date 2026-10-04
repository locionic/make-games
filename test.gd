extends SceneTree
## Headless entry: godot --headless --path . -s test.gd

const Rules = preload("res://dice.gd")
const RunState = preload("res://run.gd")
const Check = preload("res://_check.gd")

## Every script in the project. `preload` only reads the rules layer, so a
## syntax error in the UI used to sail past this suite green and surface as a
## blank screen in the screenshot harness -- which then hung instead of failing.
## Loading each one here is what turns that into a one-line headless failure.
const UI := [
	"res://theme.gd", "res://game.gd", "res://fight.gd",
	"res://main.tscn", "res://shot.gd", "res://icon.gd",
	"res://_rects.gd", "res://_probe.gd", "res://_balance.gd",
	"res://_pack.gd", "res://_stats.gd",
]

func _init() -> void:
	# The suite writes to the save -- self_test calls record_run. Send it to a
	# scratch file so testing the game never rewrites the player's history.
	RunState.SAVE_PATH = "user://self-test.json"
	print("self_test: start")
	Rules.self_test()
	RunState.self_test()
	for path in UI:
		var s = load(path)
		Check.check(s != null, "%s fails to load" % path)
		# `load()` hands back a non-null GDScript even when the parse failed, so
		# a bare null check calls a broken file healthy. reload() re-parses and
		# returns the real error. Scenes have no parse step.
		if s is Script:
			var err: Error = (s as Script).reload()
			Check.check(err == OK, "%s fails to parse (error %d)" % [path, err])
	print("self_test: %d scripts load" % UI.size())
	_haptics_wired()
	_enemy_tag()
	_store_copy()
	_depth_display()
	_best_caption()
	_face_word()
	_pack_walk()
	_contrast()
	_sfx_names()
	_citations()
	print("self_test: reached end")
	# report() prints every failure and returns 0 or 1, so a broken suite exits
	# non-zero instead of aborting _init() and hanging the SceneTree forever.
	#
	# The floor is the other half. A throw inside a helper aborts only that
	# helper, not _init(), so _init() reaches this quit() and the run exits 0
	# having silently skipped every check after the throw -- measured at 360
	# checks, "8167 checks passed", exit 0. Set the floor to the exact count:
	# it is the same number report() prints, so a check that is removed or
	# skipped by control flow shows up as a red gate with the shortfall named,
	# rather than as a floor that quietly stopped meaning anything. It fires on
	# *fewer* checks than this, so adding one moves the printed count up and
	# leaves the gate green -- which is correct, and is also the reason the floor
	# has to be the live count and not a stale larger number.
	#
	# ...and it has to be the live count for the other direction too, which is
	# the one that had quietly gone wrong: this floor sat at 8539 while the suite
	# printed 8565, so 26 checks could have been removed or skipped without the
	# gate noticing -- precisely "a floor that quietly stopped meaning anything",
	# in the paragraph above that says it must not happen. Adding checks only ever
	# widens the gap, and nothing here said to re-stamp when it did. Re-stamp it
	# whenever the printed count moves.
	#
	# The count is a structure, not a statistic, so unlike `_balance.gd`'s (which
	# is deliberately a small fixed number and says why) this one can be the
	# live value: it held at 8565 across six consecutive runs, and every check is
	# either a fixed assertion or one per *iteration* of a fixed-length loop.
	# `_balance.gd`'s live count is the other thing entirely -- fights played
	# across 22000 runs, which is why calibrating on it was backwards. Neither
	# live count is named above on purpose: they are the two numbers that drift.
	#
	# `_citations` is the first thing here that is neither a fixed assertion nor
	# one per iteration of a fixed-length loop: it emits a fixed two checks per
	# citation *site* it finds in the source and the docs, plus one per file it
	# scans, so rewriting a comment that quotes a line moves the number -- and so
	# does dropping a new .md into the repo, which is what took it from 9041. That
	# second one is the more surprising of the two: the file does not have to cite
	# anything to be counted. Both are still safe in the one direction a floor
	# cares about -- deleting a citation drops the count, the gate goes red and
	# names the shortfall -- and it is why this is re-stamped rather than raised.
	quit(Check.report("test.gd", 9042))


## PLAN.md 3.2b's haptics, which no gate in this repo can execute. `_haptic` is
## gated on `OS.has_feature("mobile")`, so it never fires headless and never
## fires under xvfb either -- `shot.gd`'s shake check covers the other half of
## that same bullet because a shake *can* be sampled, but there is nothing to
## sample here.
##
## Measured, not assumed: deleting all three `_haptic` call sites left this
## suite at 8527 and `shot.gd --check` at zero failures. The feature could be
## removed from the shipped game and every gate would still be green, which is
## why the paragraph in `shot.gd` that opens "shipped with five call sites"
## lists them between the two systems and
## then covers two of them.
##
## Checked against the source. That is a weaker guarantee than running it and
## is the only one available -- no amount of headless work changes what a
## mobile-gated call does. The two triggers are named as strings rather than
## counted, because a count alone would still pass with the calls rewritten to
## fire on nothing, and `ponytail:` a source check cannot see a call that was
## moved into a helper this file does not read. Upgrade path if that ever
## matters: assert on a value `_haptic` returns, so the gate can observe it.
func _haptics_wired() -> void:
	var src := FileAccess.get_file_as_string("res://fight.gd")
	var sites := src.count("_haptic(") - 1  ## less the `func _haptic(` definition
	Check.check(sites >= 3,
		"fight.gd still wires haptics at three call sites, PLAN.md 3.2b (found %d)" % sites)
	Check.check("dealt >= 10" in src,
		"and still buzzes harder for a heavy hit than for a light one")
	# Anchored on `_haptic(HAPTIC_BOSS`, not on `HAPTIC_BOSS` alone: written the
	# looser way it passes on the `const HAPTIC_BOSS := 70` declaration, which
	# survives the call site being deleted -- found by deleting all three calls
	# and watching this one stay green while the other two went red.
	Check.check("_haptic(HAPTIC_BOSS" in src,
		"and still buzzes differently for a boss than for an ordinary enemy")


## PLAN.md's enemy tag: the behaviour line under the enemy's name.
##
## The first version of this asserted that `String.capitalize()` is sentence
## case, written to pass so the gate could settle what Godot 4.3 actually does.
## It does settle it -- capitalize() is *title* case here, uppercasing the first
## letter of every word -- and that made the check useless as a permanent gate:
## it pinned the engine's semantics rather than the game's render, so it stayed
## red against correct code and would have gone green again if `fight.gd` were
## reverted to `capitalize()`. Measuring is worth doing once; a gate that cannot
## go green is not a gate.
##
## So this watches the two halves the player actually sees instead. The names
## must arrive lowercase, which is a real runtime property of `dice.gd` and is
## the only reason the fix can be a one-liner in `fight.gd`. And `fight.gd` must
## not route any tag through `capitalize()`, which is source-anchored on the
## *absence* rather than on the line that was changed -- a weaker guarantee than
## running it, and the same one `_haptics_wired` above makes, but it covers a
## future tag path that an anchored-on-line check would miss.
##
## Iterates the shipping table rather than the five constants, so a behaviour
## added to `enemy_for` is covered the day it lands.
func _enemy_tag() -> void:
	var run := RunState.new()  ## `enemy_for` is an instance method, not a static one
	for d in range(RunState.FINAL_DEPTH + 1):
		var authored := run.enemy_for(d).behavior_name()
		if authored.is_empty():
			continue
		Check.check(authored == authored.to_lower(),
			"depth %d: behaviour name \"%s\" is not lowercase -- the tag renders it "
				% [d, authored] + "as sentence case, so a capital here is a double capital")
	var src := FileAccess.get_file_as_string("res://fight.gd")
	# Comment lines are stripped first, or the check matches the very comment
	# explaining why it exists. `ponytail:` a trailing `#` comment can still
	# trip it; grep for the token and move it up a line if that ever bites.
	var code := ""
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	Check.check(".capitalize()" not in code,
		"fight.gd must not title-case the enemy tag -- Godot 4 capitalize() is title "
			+ "case, which is how \"curses a die\" reached the screen as \"Curses A Die\"")


## PLAN.md's store copy: the clause that survived a repair and came back wrong.
##
## "Hexweaver curses one of your dice to nothing" sat in the Play description and
## was false for three of the four library dice. A repair swapped it for "which is
## exactly what Hexweaver reaches for", which was false in a second way: the curse
## picks a die at random and drops it on *that die's* lowest-`worth()` face, and
## only Sunder's is a nothing. Both were caught the same way -- by writing the
## claim as a check and letting the gate decide, which is also what caught it the
## first time round.
##
## Two halves, deliberately in two files. The mechanic halves -- how many of the
## library dice have a nothing for a worst face, and which cards move hit points
## -- are `run.gd`'s, beside the other store-copy claims it pins. This is the copy
## half, and it lives here rather than
## in `shot.gd`'s `_check_copy_claims` because `shot.gd` cannot be executed from
## this session's gates: a check in a file nobody can run is a check that quietly
## stops meaning anything, which is the failure mode every other floor comment in
## this repo is about.
##
## Both clauses here are *negatives* -- "not a stat bar", "to nothing" -- and both
## were absolutes the game does not keep. That is the shape worth watching for in
## a description: a sentence with "not" in it is a claim about every case, and the
## cases nobody was holding in mind are the ones it is about.
func _store_copy() -> void:
	var fence := RegEx.new()
	fence.compile("(?s)```\\n(.*?)```")
	var blocks: Array = []
	for m in fence.search_all(FileAccess.get_file_as_string("res://play/LISTING.md")):
		blocks.append(str(m.get_string(1)).strip_edges())
	# Indexing before the count is asserted is how the fence silently stops
	# matching, so the count comes first and the rest is skipped loudly.
	Check.check(blocks.size() == 2,
		"LISTING.md holds the two text blocks Play takes (found %d)" % blocks.size())
	if blocks.size() != 2:
		return
	# Newlines folded because the block is hard-wrapped, so "down to its\nworst
	# face" is one clause in the file and two unrelated strings to a match.
	var text: String = str(blocks[1]).replace("\n", " ").to_lower()
	Check.check("drags one of your dice down to its worst face" in text,
		"the description says what the curse actually does")
	Check.check("to nothing" not in text,
		"and promises no nothing -- the curse lands on whichever die it picks, and "
			+ "only Sunder's worst face is one")
	# Anchored on the *noun*, not on the phrase "not a stat bar" this first
	# version tested. That version went green over a second sentence saying "You
	# are not managing a timer or a stat bar" -- the same false absolute, one
	# sentence from the one it was written for, and the substring simply was not
	# present. Found by reading the whole block for every quantitative claim
	# rather than for the one already complained about, which is the same mistake
	# in a different key: fixing the instance, not the claim.
	Check.check("stat bar" not in text,
		"the description must not claim it avoids a stat bar at all -- MEND heals "
			+ "14 and VIGOR grants +8 max health, so two of the twelve do not, and "
			+ "the fight screen carries two health bars")
	Check.check("only two of the twelve buy hit points back" in text,
		"and says what is true instead: two of the twelve are about hit points, and "
			+ "the other ten change the dice or the rules they roll under")


## PLAN.md's depth off-by-one, which `run.gd`'s own checks could not see.
##
## The death screen said "You reached depth 9 of 9" and, two lines below it,
## "The Devourer waits at depth 8" -- one fight, two numbers, on one screen,
## because five of the six sites printing a depth added one and the sixth did
## not. `RunState.depth_no` now owns the mapping and `run.gd` pins it: the first
## fight reads as 1, the boss as `FINAL_DEPTH + 1`, every depth as itself plus
## one, and a run past the end still reads as the last fight.
##
## **Those twelve checks do not cover the bug they were written for, and this
## file is the correction.** Measured, not assumed: with `"% RunState.FINAL_DEPTH"`
## put back at `game.gd:539` -- the original defect, verbatim -- the tree stayed
## at 8618 and exit 0. A helper is correct by construction, so a call site that
## never calls it is invisible to every assertion about it. Same shape as the
## `br` check that named `ARMOR_GROW_CAP` while running on a `BEH_BRACE` enemy,
## one layer up: the check pins a value while the defect is in the wiring.
##
## So these two are source-anchored, because `game.gd` builds its Controls and
## cannot be executed from a headless session -- the same weaker guarantee
## `_haptics_wired` and `_enemy_tag` make, and the only one available. Each names
## the exact shape that shipped: a `%` format printing the bare index, and a
## hand-rolled `+ 1` beside it. Both are falsified by the mutation above.
##
## The ceiling that leaves: a future site can still dodge both by formatting a
## depth some third way. Closing that means extracting the sentences into
## statics this suite could call and compare -- not worth it until a site
## actually dodges, since it doubles the surface for a hypothetical.
func _depth_display() -> void:
	var src := FileAccess.get_file_as_string("res://game.gd")
	Check.check("% RunState.FINAL_DEPTH" not in src,
		"game.gd must not print a depth as the bare index -- the death screen said "
			+ "\"The Devourer waits at depth 8\" two lines under \"You reached depth 9 of 9\"")
	Check.check("run.depth + 1" not in src,
		"and must not hand-roll the +1 beside it; every displayed depth goes "
			+ "through RunState.depth_no")


## Every `file.gd:N` citation in the repo, resolved against the line it names.
##
## Citations are how a comment reaches its evidence, and they rot silently: the
## sentence keeps asserting something true about code that has moved on. One
## line of `run.gd` has now been wrong three times -- 268, then 284 written as
## the correction to 268, then 312 -- and the last was moved nineteen lines by a
## helper added higher up in the same file while this audit was running, so the
## comment recording the first two failures was itself stale before the third
## was written. `_balance.gd` carries the history and drew the conclusion
## itself: the wrong number was ratified twice by fixing it once. So the fourth
## response is not a number.
##
## Two tests, and the gap between them is permanent and deliberate. A citation
## that quotes its target is checked against that exact line, and that is the
## family that has now failed three times. A citation that only names a file
## and a line is checked for being in range and non-blank -- which catches a
## shift that ran off the end of a file or landed on a gap, and not a shift
## that landed on plausible code. `run.gd` pointed at its own line 49, a real
## `base_focus` declaration, to mean `saved_loadout()`'s call seventeen lines
## below; nothing mechanical sees that one, and it was found by reading all
## twenty-two by hand.
##
## `ponytail:` the loose half is only checkable once a claim quotes its own
## target, so closing it means rewriting every citation in the repo as a quote.
## That is a diff across five files to cover a gap that has opened once, and a
## mechanically-checked claim about a line is still a claim somebody has to
## read -- which is what the twenty-two are for.
## The BEST HIT caption names its cause, and for one reachable hand it names
## the wrong one.
##
## `_refresh` computes `best` as the most any one die can land after armour, and
## at zero it says "ARMOUR n -- NOTHING LANDS". That is only the cause when the
## hand actually rolled damage and the enemy's armour ate it. Ward is six
## block faces and Riposte is five plus a junk, both reachable from the die
## picker, so a hand can hold nothing but zero-damage faces -- and then `best`
## is 0 because the roll was empty, not because anything blocked it. Against a
## Grunt the armour is 0, so the caption reads "ARMOUR 0 -- NOTHING LANDS":
## true that nothing lands, and blaming armour for the one enemy that cannot.
##
## The reachability is asserted here rather than in `fight.gd`, because the
## caption is set inside `_refresh` and building that headless means standing up
## the whole fight scene to read one Label. What is checkable without the scene
## is the premise the caption depends on -- that the hand exists and that the
## dice can all show a face dealing no damage on the same roll -- and
## `best_caption` below is the pure part the caption now goes through.
func _best_caption() -> void:
	var zero: Dictionary = {}
	for d in Rules.Encounter.library():
		for f in d.faces:
			zero[d.title] = (zero.get(d.title, true) and f.dmg == 0)
	for d in Rules.Encounter.bonus_dice():
		for f in d.faces:
			zero[d.title] = (zero.get(d.title, true) and f.dmg == 0)
	Check.check(zero.get("Ward", false) and zero.get("Riposte", false),
		"Ward and Riposte deal no damage on any face")
	Check.check(not zero.get("Blade", true) and not zero.get("Fang", true),
		"and Blade and Fang deal damage, so the starting hand is not this case")

	# Sunder and Spark each carry two faces that deal nothing, which is what
	# lets the other two dice join them on the same roll.
	var spare := 0
	for title in ["Sunder", "Spark"]:
		for d in Rules.Encounter.library() + Rules.Encounter.bonus_dice():
			if d.title == title:
				spare += d.faces.filter(func(f: Rules.Face) -> bool: return f.dmg == 0).size()
	Check.check(spare == 4, "Sunder and Spark hold two zero-damage faces each")

	# The picker passes whatever four titles the player chose straight to
	# `set_loadout`, and that has no filter on damage -- so this hand is legal.
	var r := RunState.new()
	r.set_loadout(["Ward", "Riposte", "Sunder", "Spark"])
	Check.check(r.dice.size() == 4 and r.dice[0].title == "Ward",
		"a hand of four zero-damage-capable dice is accepted verbatim")

	# And every die in it can show such a face at once, which is the roll the
	# caption gets wrong: nothing dealt, nothing blocked.
	var can_show := 0
	for d in r.dice:
		var pick := -1
		for i in d.faces.size():
			if d.faces[i].dmg == 0:
				pick = i
				break
		d.up = pick
		if pick >= 0:
			can_show += 1
	Check.check(can_show == r.dice.size(),
		"every die in that hand has a face that deals nothing")
	var grunt := r.enemy_for(0)
	var best := 0
	for d in r.dice:
		best = maxi(best, grunt.pierce(d.face().dmg, 0))
	Check.check(best == 0 and grunt.armor == 0,
		"against a Grunt that reads best 0 on armour 0, which is not armour's doing")

	var cap: String = (load("res://fight.gd") as Script).best_caption(best, 0, grunt.armor)
	Check.check(cap == "NO DAMAGE THIS ROLL",
		"and the caption names the roll instead of armour 0")
	Check.check((load("res://fight.gd") as Script).best_caption(0, 9, 3) ==
			"ARMOUR 3 — NOTHING LANDS",
		"a rolled 9 eaten by armour 3 still names the armour")
	Check.check((load("res://fight.gd") as Script).best_caption(7, 9, 3) == "BEST HIT",
		"and a landed hit says so")
	# The two zero branches must never both be live, or the roll is unnamed.
	Check.check(not (cap.contains("ARMOUR") and cap.contains("NO DAMAGE")),
		"the zero caption names one cause, never both")


## A card's sub-label, and the two upgrades that make a numeric one wrong.
##
## Blade's faces are *named* "2".."9", and those names are the damage values.
## SHARPEN and REFORGE both raise a face's damage and neither touches its
## name, so after either the die shows 10 under the name "9". The card prints
## the live number large, from `max(hit, block, rerolls)`, and then the label
## underneath -- so the two lines on one card disagree, with the headline right
## and the line beneath it stale. Nothing about the rendering looks broken,
## which is why it is worth naming rather than looking at.
##
## The label is a *word* or it is nothing. "cleave", "rend", "fend" and "rust"
## are words and ride along. A bare number is never a word, so it falls back to
## `kind`, which is built from the live stats -- the same "N DAMAGE" an
## unupgraded Blade already shows, and the same "2 BLOCK" Ward shows. The rule
## is unchanged for every unupgraded die; it only bites once a stat moves.
static func face_word(label: String, kind: String, value: int) -> String:
	return kind if label.is_valid_int() or label == str(value) else label


## The premise above, measured before the display rule was written against it.
func _face_word() -> void:
	var sh := RunState.new()
	sh.apply_upgrade("SHARPEN", RandomNumberGenerator.new())
	var drifted := 0
	for d in sh.dice:
		for f in d.faces:
			if f.label.is_valid_int() and f.label != str(f.dmg):
				drifted += 1
	Check.check(drifted > 0,
		"SHARPEN leaves %d numeric labels naming a damage they no longer deal" % drifted)
	var rf := RunState.new()
	rf.apply_upgrade("REFORGE", RandomNumberGenerator.new())
	var forged := 0
	for d in rf.dice:
		for f in d.faces:
			if f.label.is_valid_int() and f.label != str(f.dmg):
				forged += 1
	Check.check(forged > 0, "and REFORGE does the same to the face it climbs")

	var Fight = load("res://fight.gd")
	Check.check(Fight.face_word("9", "10 DAMAGE", 10) == "10 DAMAGE",
		"a drifted numeric label falls back to the live stat")
	Check.check(Fight.face_word("9", "9 DAMAGE", 9) == "9 DAMAGE",
		"and an undrifted one reads the same as it always did")
	Check.check(Fight.face_word("2", "2 BLOCK", 2) == "2 BLOCK",
		"Ward's block faces are numeric too, and must keep their word")
	Check.check(Fight.face_word("cleave", "12 DAMAGE", 12) == "cleave",
		"a real word still rides along under the number")
	Check.check(Fight.face_word("5", "10 DAMAGE", 10) == "10 DAMAGE",
		"a paired face shows the doubled number, not the half it is named")


func _pack_walk() -> void:
	var Pack = load("res://_pack.gd")
	# `_pack.gd` is the only gate that can see an export filter dropping a file,
	# and its whole logic is two pure string functions -- neither of which any
	# headless gate has ever called, because the only code path that calls them
	# exports a pack first. Both are `static` now precisely so this can reach
	# them; instantiating the script would run `_init`, which exports and quits.
	#
	# The seed deliberately omits `_check.gd`. `_referenced` returns its own
	# seed, so handing it a set that already contains the file under test makes
	# the first assertion true without the walk having looked for anything. This
	# is the exact situation the gate exists for: a filter matching `_*.gd`
	# taking the whole rules layer with it.
	var shipped := {}
	for path in DirAccess.get_files_at("res://"):
		if path.ends_with(".gd") and path != "_check.gd":
			shipped["res://" + path] = true
	var need: Dictionary = Pack._referenced(shipped)
	Check.check(need.has("res://_check.gd"),
		"the pack walk requires _check.gd even though the seed excludes it")
	Check.check(need.has("res://audio/roll.ogg"),
		"the pack walk reaches game.gd's preloads -- the hop get_dependencies cannot make")
	# A walk that requires a path which is not in the repository would turn the
	# pack gate permanently red on a file that was merely renamed, and the
	# message would be about an export rather than about the rename.
	#
	# The non-empty clause is not decoration. Written as `gone.is_empty()` alone
	# this passes trivially when the walk finds nothing at all, which is exactly
	# the state a broken regex leaves it in -- caught by mutation here, where
	# this check stayed green through a regex that matched nothing. The two
	# assertions above it are positive and cannot pass that way; this one can,
	# and would have been the only check in the helper reporting success on an
	# empty result.
	var gone: Array = []
	for p in need:
		if not FileAccess.file_exists(p) and not FileAccess.file_exists(p + ".import"):
			gone.append(p)
	gone.sort()
	Check.check(need.size() > 0 and gone.is_empty(),
		"the pack walk requires %d path(s) absent from this repository, from %d required: %s"
			% [gone.size(), need.size(), ", ".join(gone)])

	# `_stored` is the other half, and it is the half that decides whether a
	# shipped file is even seen: it parses the exporter's own log. A synthetic
	# line is the only way to test a parser without running an export, and the
	# two folds below are the ones that make it work at all -- without them
	# every script reads as missing, which is the failure its own header names.
	var line := func(n: String) -> String:
		return "[1m  93%% savepack | Storing File: %s[0m" % n
	var got: Dictionary = Pack._stored("\n".join(PackedStringArray([
		line.call("res://dice.gd.remap"),
		line.call("res://run.gdc"),
		"not an export line at all",
	])))
	Check.check(got.has("res://dice.gd"), "a .remap entry folds back onto its source name")
	Check.check(got.has("res://run.gd"), "a .gdc entry folds back onto the script it came from")
	Check.check(got.size() == 2,
		"and the exporter's colour codes and surrounding chatter are not counted as files")


func _contrast() -> void:
	var T = load("res://theme.gd")
	# The palette's only accessibility invariant was written down as a ratio in a
	# comment -- "FAINT measured 2.44:1 on the card, under the 4.5:1 of WCAG 2.2
	# SC 1.4.3" -- and both halves of that were true when written. They stayed
	# true on CARD. They were not true on CARD_HI, which is the fill a die card
	# takes the moment it is armed, picked for a re-roll, or hovered, and which
	# nobody re-measured because the comment named the other surface.
	#
	# So these are the decision-invariants, not the measurements: MUTED is only
	# usable for secondary text while it clears 4.5 against the *lightest*
	# surface it is ever drawn on, and FAINT is only acceptable where the text
	# is meant to disappear because it clears 4.5 nowhere. Asserting the exact
	# ratio instead would fail on a deliberate palette change for the wrong
	# reason, and would say nothing about whether the decision still holds.
	var worst := _ratio(T.MUTED, T.CARD_HI)
	Check.check(worst >= 4.5,
		"MUTED is %.2f:1 on CARD_HI, the fill an armed or picked die card takes (want 4.5)"
			% worst)
	Check.check(_ratio(T.MUTED, T.CARD) >= 4.5,
		"MUTED is %.2f:1 on CARD" % _ratio(T.MUTED, T.CARD))
	# The reason MUTED exists at all. If FAINT ever cleared the bar, the rule
	# written above it in `fight.gd` would be choosing the dimmer of two
	# compliant colours for no reason, and the rule would be dead weight.
	Check.check(_ratio(T.FAINT, T.CARD_HI) < 4.5 and _ratio(T.FAINT, T.CARD) < 4.5,
		"FAINT is %.2f:1 on CARD_HI and %.2f:1 on CARD, so 'MUTED, not FAINT' still means something"
			% [_ratio(T.FAINT, T.CARD_HI), _ratio(T.FAINT, T.CARD)])
	# And MUTED must not become a second TEXT -- the dominance the comment relies
	# on is "the 40px number, not the fading of the text", which needs the two
	# to stay visibly apart.
	#
	# The bar is 2.0, not the 3.0 this check first carried. 3.0 was invented
	# rather than measured, and it failed against a palette that had been in the
	# repo all along: the design point is 2.81. Lightening MUTED to clear
	# CARD_HI cost 0.39 of that, to 2.42 -- a real price for the fix, taken
	# knowingly rather than discovered afterwards, and the reason the floor sits
	# at 2.0 rather than at the old number. A check that only passes for the
	# value it was invented against is a check that blocks the next change
	# without saying anything about whether the change was right.
	Check.check(_ratio(T.TEXT, T.MUTED) >= 2.0,
		"TEXT and MUTED are only %.2f:1 apart, so the name no longer recedes"
			% _ratio(T.TEXT, T.MUTED))
	# TEXT is the one colour that carries the number a player reads at a glance,
	# on every surface including the raised one.
	Check.check(_ratio(T.TEXT, T.CARD_HI) >= 4.5,
		"TEXT is %.2f:1 on CARD_HI" % _ratio(T.TEXT, T.CARD_HI))


## WCAG 2.2 relative-luminance contrast, per SC 1.4.3 -- the same definition
## the comments above were written against, so a number here and a number there
## mean the same thing.
##
## Not `Color.get_luminance()`, which looks like exactly this function and is
## not: it applies the 0.2126/0.7152/0.0722 weights to the **un-linearised**
## sRGB channel values, so it understates dark-on-dark contrast badly. The
## ratios it gives for this palette are wrong enough to change the answer --
## TEXT on CARD_HI reads 4.13 under it and 11.60 under WCAG, and FAINT on CARD
## reads 2.11 rather than the 2.44 the code has always quoted. So the numbers
## in `fight.gd` and `game.gd` were computed correctly, outside the engine, and
## the one helper a reader would reach for gives a different answer to the same
## question. That gap is worth six lines.
static func _ratio(a: Color, b: Color) -> float:
	var al := _rel_lum(a)
	var bl := _rel_lum(b)
	return (maxf(al, bl) + 0.05) / (minf(al, bl) + 0.05)

static func _rel_lum(c: Color) -> float:
	return 0.2126 * _srgb(c.r) + 0.7152 * _srgb(c.g) + 0.0722 * _srgb(c.b)

static func _srgb(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## Every sound the fight or the run *asks for* resolves to a real player.
##
## `shot.gd` walks `game.SFX` and checks each entry is a file. That is
## one half of a bijection, and the half that cannot fail: a key that stops
## resolving is a file that went missing, and `shot.gd` is right to look. Nobody
## walked the other way. A typo in `_sfx("blok") ` indexes `SFX ` with a key it
## does not have, so `preload` returns null, so `play_sfx ` returns without
## touching the pool -- and the sound stops playing with every gate in the repo
## still green.
##
## That is the same loss the duration gate exists to catch. "The name still
## resolves" is precisely what a truncated or re-encoded file gets right, so a
## whole gate was written to look past it; here it is the resolution itself that
## fails. `shot.gd ` asserts the unknown-name path is *safe* -- nothing is
## stolen, nothing is cut off -- and that is a reason to handle a bad name
## gracefully, not a reason to let one arrive.
##
## The scan is a regex over source text rather than a hook on `play_sfx `,
## because the names are string literals at the call site and there is no way to
## read them off a running fight without writing a test that plays every branch
## of it. It misses a name built at runtime; none is, and one appearing is the
## thing to notice when this next fails to catch it.
##
## `shot.gd ` is not scanned, because it asks for `"no-such-sound"` on purpose.
func _sfx_names() -> void:
	var game = load("res://game.gd")
	var call := RegEx.new()
	call.compile("(?:_sfx|play_sfx)\\(\"([a-z_]+)\"")
	var used := {}   ## sound name -> the file that asked for it
	for path in ["res://fight.gd", "res://game.gd"]:
		for m in call.search_all(FileAccess.get_file_as_string(path)):
			used[m.get_string(1)] = path
	Check.check(used.size() >= 7,
		"the sfx-name scan found %d distinct names across fight.gd and game.gd, "
			% used.size() + "which is too few for the seven effects to be reachable")
	for name in used:
		Check.check(game.SFX.has(name),
			"%s asks for \"%s\", which is not a key in game.SFX, so it plays nothing"
				% [str(used[name]).get_file(), name])


func _citations() -> void:
	var plain := RegEx.new()
	plain.compile("([A-Za-z_]+\\.gd):(\\d+)")
	var quoted := RegEx.new()
	# The filename may itself be in backticks, which is how the docs quote a
	# citation back at itself. Without the optional backtick that reading fell
	# through to the plain pass and got only the in-range test, on the one site
	# in the repo whose whole subject is whether a quoted citation still holds.
	quoted.compile("`([^`\\n]+)` at `?([A-Za-z_]+\\.gd):(\\d+)`?")
	# The docs carry more of these than the code does -- 90 against 21 -- and they
	# drift more, because editing any `.gd` file breaks the documents citing it
	# while breaking nothing in the file being edited. Four were dead when this
	# was extended: a roster range pointing eleven lines above the roster, an
	# armour pair citing a blank line for each enemy, a die-catalogue range off
	# by nine, and one naming a check that asserts hand width as though it
	# asserted enemy behaviour.
	#
	# `.md` is here rather than in a separate pass because the drift is the same
	# drift; two passes would be two chances to fix one of them and not the
	# other, which is exactly what the three hand corrections to `run.gd:312`
	# were. `play/LISTING.md` is named explicitly because
	# `DirAccess.get_files_at` does not recurse, and that file holds 13 more.
	var sources := ["play/LISTING.md"]
	for path in DirAccess.get_files_at("res://"):
		if path.ends_with(".gd") or path.ends_with(".md"):
			sources.append(path)
	# A quote-form citation that wraps is not a quote-form citation. `quoted`
	# reads one line at a time, so a quoted target whose trailing "at" falls at
	# the end of its line, with the file and line number on the next, falls
	# through to the plain pass and gets the structural pair only -- the exact
	# weakening the quoting form exists to avoid, and silent: three were wrapped,
	# and one of those was two lines off while the gate stayed green. Wrapping at
	# the column limit is the normal way to edit prose, so this is a thing
	# authors do while thinking they are doing something else. Matches the
	# wrapped shape rather than every line ending in a backtick, which is most
	# of the repository. (Neither regex below may be written with the citation
	# punctuation spelled out: this file is scanned for its own citations, and a
	# comment illustrating one trips the gate that is checking it. That is the
	# same trap as the note in `PLAN.md`, and the reason both describe the
	# pattern instead of spelling it.)
	var wrapped := RegEx.new()
	wrapped.compile("`[ \\t]*at[ \\t]*$")
	var wrapped_to := RegEx.new()
	wrapped_to.compile("^[ \\t]*`?[A-Za-z_]+\\.gd:\\d+`?")
	for path in sources:
		var lines := FileAccess.get_file_as_string("res://" + path).split("\n")
		# One check per file, not one per wrap. A check that only fires when it
		# is already broken contributes nothing to the floor, so the count gives
		# no way to tell it is running at all.
		var wraps := 0
		for i in lines.size():
			if wrapped.search(lines[i]) != null and i + 1 < lines.size() \
					and wrapped_to.search(lines[i + 1]) != null:
				wraps += 1
		Check.check(wraps == 0,
			"%s wraps %d quote-form citation(s), which are then only checked for being in range"
				% [path, wraps])
		for i in lines.size():
			var here := "%s line %d" % [path, i + 1]
			# The quoting form is taken first and keyed by target, so the plain
			# pass skips the same site instead of counting it a second time --
			# one citation, one pair of checks, however it was written.
			var claims := {}
			for m in quoted.search_all(lines[i]):
				claims["%s:%d" % [m.get_string(2), int(m.get_string(3))]] = m.get_string(1)
			for key in claims:
				var at := str(key).split(":")
				_cite(here, at[0], int(at[1]), str(claims[key]))
			for m in plain.search_all(lines[i]):
				var key2 := "%s:%d" % [m.get_string(1), int(m.get_string(2))]
				if claims.has(key2):
					continue
				var at2 := str(key2).split(":")
				_cite(here, at2[0], int(at2[1]), "")


func _cite(here: String, target_file: String, n: int, quote: String) -> void:
	if not FileAccess.file_exists("res://" + target_file):
		Check.check(false, "%s cites %s, which is not in this repo" % [here, target_file])
		return
	var lines := FileAccess.get_file_as_string("res://" + target_file).split("\n")
	# Every message below names the target in prose -- the file, then the word
	# "line" and the number -- rather than in the colon form this file's own
	# regex reads, so this function never prints a string its own check would
	# then flag. It otherwise cannot be quoted at all: PLAN.md quotes a failure
	# message verbatim as evidence, and a document quoting the gate cannot pass
	# it. Writing the colon form out here to illustrate it is the same mistake,
	# which is why this sentence describes the shape instead.
	Check.check(n >= 1 and n <= lines.size(),
		"%s cites %s line %d, and that file has %d lines" % [here, target_file, n, lines.size()])
	if n < 1 or n > lines.size():
		return
	var line: String = lines[n - 1]
	Check.check(not line.strip_edges().is_empty(),
		"%s cites %s line %d, which is a blank line" % [here, target_file, n])
	if quote != "":
		Check.check(quote in line,
			"%s quotes \"%s\", and that text is not on %s line %d"
				% [here, quote, target_file, n])

