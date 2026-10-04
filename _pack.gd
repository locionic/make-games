extends SceneTree
## Does an exported build still contain every file the game loads?
##   godot --headless --path . -s _pack.gd -- "Android"
##
## Nothing checks the export filter. It has to be checked here, because the
## headless suite cannot see it -- it runs against the source tree, which has
## every file -- and a Play download runs against the pack, which may not.
##
## This was a real defect, not a hypothetical one, and it is **fixed**. The
## Android preset's `exclude_filter` was `_*.gd`, which took `_check.gd` with
## it, and `dice.gd:3` and `run.gd:12` both `preload("res://_check.gd")` at the
## top level -- a `const` preload resolves at parse time, so the rules layer
## failed to compile and a device showed a black screen. `3e743e5` replaced the
## glob with an explicit list of the scripts that are genuinely dev-only, and
## the filter today is literal filenames rather than globs: `_balance.gd`,
## `_pack.gd`, `_probe.gd`, `_rects.gd`, `_stats.gd`, `test.gd`, `shot.gd`,
## `icon.gd`, `extension_api.json`. `_check.gd` is absent from that list, and
## being absent from it is the whole thing this file is here to notice.
##
## The named check at the bottom asserts it rather than trusting the list to
## stay written. This header used to say the filter "is a list of globs" and
## that the exclusion "is not hypothetical", both in the present tense and both
## untrue -- the second because the commit that fixed it is in this file's own
## history. A gate's header describing the incident that motivated it, forever,
## reads to the next person as a live bug in their build. If this ever looks
## wrong again, check `3e743e5` before assuming the fix was reverted.
##
## The dependency set is not written out here. A hardcoded list is a second copy
## of the game's shape that goes stale the day a file is added, and a stale list
## passes while the real dependency went missing -- which is the whole failure
## this file exists to catch. So the set is *read* out of the shipped scripts
## instead, by the regex in `_referenced` below.
##
## The obvious alternative, walking out from the main scene with
## `ResourceLoader.get_dependencies`, was measured and does not work: it returns
## `["res://game.gd"]` for `main.tscn` and an **empty list for every `.gd` in
## the project**, including the two that `preload` the rules layer. So the walk
## would stop after a single hop and never reach `_check.gd` -- not the file it
## is least able to miss, the one this whole file exists to watch. It is called
## out at length at the top of `_referenced`, and it is named here because this
## header used to describe that walk, and a header describing a mechanism the
## code does not use is the exact failure mode the gate below is built to catch,
## one level up.
##
## The file list alone is a statement about names, so the pack is also
## *executed* below, which reads the shipped bytes. That second probe needed two
## things worked out, and both were found the hard way.
##
## `--main-pack` does load the main scene and the game's scripts -- it is not
## blind. It exits 0 either way, so the exit code says nothing and the
## `SCRIPT ERROR` lines in its output are the only evidence. A pack missing
## `_check.gd` really does print `Parse Error: Preload file "res://_check.gd"
## does not exist` at dice.gd:3 and run.gd:12, then `Compile Error: Failed to
## compile depended scripts`, which the engine reports against game.gd's line 0
## -- a shipped build whose main scene
## cannot load, which on a phone is a blank screen and nothing else.
##
## It also answers from the source tree when the process happens to be standing
## in the project directory: the missing preload resolves off disk and the probe
## reports a clean run on a build that cannot compile. Measured, not assumed --
## the same broken pack printed two `Parse Error` lines once the child was moved
## to /tmp and nothing at all before it, which is how a control experiment very
## nearly recorded the opposite conclusion. So the child runs from RUN_FROM,
## and that is load-bearing rather than tidiness.
##
## `load_resource_pack(.., true)` is no use here at all: with a project running
## from a directory, res:// lookups still resolve to that directory, so a
## project-only file loads even when the mounted pack does not contain it.

const Check = preload("res://_check.gd")
const PROBE := "/tmp/_pack_probe.pck"
## Where the child below is made to stand. Must not be a directory the source
## tree is reachable from, or the probe grades the source tree instead of the
## pack -- see the header.
const RUN_FROM := "/tmp"
## The exporter prints `  93% savepack | Storing File: res://x` with SGR
## colour around every field, so the line has to be cleaned before it can be
## read or every path comes out wrapped in escape codes.
const ANSI := "\\x1b\\[[0-9;]*m"
const MARK := "Storing File: "


func _init() -> void:
	var argv := OS.get_cmdline_user_args()
	Check.check(argv.size() == 1, "pass one preset name after -- (%s)" % argv)
	if argv.size() != 1:
		quit(Check.report("_pack.gd"))
		return
	var preset: String = argv[0]

	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(),
		["--headless", "--path", ".", "--export-pack", preset, PROBE], out, true)
	Check.check(code == 0, "%s exports (exit %d)" % [preset, code])
	var log := "".join(out)

	var shipped := _stored(log)
	Check.check(shipped.size() > 0, "the exporter reported %d files" % shipped.size())

	var main_scene: String = ProjectSettings.get_setting(
		"application/run/main_scene", "")
	Check.check(main_scene != "", "a main scene is configured")
	var need := _referenced(shipped)

	var missing: Array = []
	for p in need:
		# An imported asset is not stored under its own name. The pack holds
		# `x.png.import` and the converted blob under `.godot/imported/`, and
		# the original `x.png` is not in there at all -- so a reference to an
		# import counts as present when the import is. Without this, every
		# sound in the game reads as missing and the real finding drowns in it.
		if not shipped.has(p) and not shipped.has(p + ".import"):
			missing.append(p)
	# Sorted so the failure is the same run to run -- the exporter's order is
	# directory order and a gate that reshuffles its own failures is a gate
	# nobody can read.
	missing.sort()
	for m in missing:
		Check.check(false, "required but not exported: %s" % m)
	if missing.is_empty():
		print("_pack.gd: %d scripts and everything they preload, all exported (%d stored)"
			% [need.size(), shipped.size()])

	# The one that started this, asserted by name so the failure says what to
	# do about it rather than only that something is absent.
	Check.check(shipped.has("res://_check.gd"),
		"res://_check.gd ships -- dice.gd and run.gd preload it, and a filter "
		+ "matching `_*.gd` takes the whole rules layer with it")
	_runs(PROBE, preset)
	quit(Check.report("_pack.gd"))


## Boot the pack and read what the engine says. The file list above can only see
## that a name was shipped; this sees whether the shipped bytes still compile,
## which is the question that actually reaches a player.
func _runs(pack: String, preset: String) -> void:
	var out: Array = []
	# Through a shell purely to set the child's directory -- `OS.execute` has no
	# cwd argument, and the cwd is what makes this probe meaningful (header).
	var cmd := "cd %s && exec %s --headless --main-pack %s --quit-after 120" % [
		RUN_FROM, OS.get_executable_path(), pack]
	var code: int = OS.execute("/bin/sh", ["-c", cmd], out, true)
	Check.check(code == 0, "%s pack boots (exit %d)" % [preset, code])
	var trace := "".join(out)
	# Exactly `SCRIPT ERROR`, not "ERROR": a `--quit-after` teardown always
	# complains about leaked ObjectDB instances and resources still in use, and
	# matching those would make this check permanently red and therefore useless.
	# A GDScript line is the one thing that means a shipped script did not parse.
	var bad: Array = []
	for line in trace.split("\n"):
		if line.begins_with("SCRIPT ERROR"):
			bad.append(line.strip_edges())
	bad.sort()
	for b in bad:
		Check.check(false, "%s pack does not run: %s" % [preset, b])
	if bad.is_empty():
		print("_pack.gd: %s pack boots -- main scene and every script it loads compile"
			% preset)


## Every file the exporter put in the pack, keyed by the *source* path. It
## stores compiled and remapped names -- `dice.gd.remap` and `dice.gdc` both
## stand for `dice.gd` -- so both are folded back onto the name a dependency
## walk produces, otherwise every single script reads as missing.
static func _stored(log: String) -> Dictionary:
	var strip := RegEx.new()
	strip.compile(ANSI)
	var out := {}
	for line in strip.sub(log, "", true).split("\n"):
		var i := line.find(MARK)
		if i == -1:
			continue
		var p: String = line.substr(i + MARK.length()).strip_edges()
		if p.ends_with(".remap"):
			p = p.trim_suffix(".remap")
		if p.ends_with(".gdc"):
			p = p.trim_suffix(".gdc") + ".gd"
		out[p] = true
	return out


## Every file the shipped scripts reach for by a literal path.
##
## Read out of the source text rather than asked of the loader, because
## `ResourceLoader.get_dependencies` is not merely unreliable here -- it is
## unreliable in the one direction that matters. Measured: it answers for one of
## this game's eight files and calls the rest dependency-free, and the one it
## answers for is the main scene, whose single answer is `game.gd`. Every
## script, including both that preload the rules layer, answers empty. A walk
## built on it terminates after one hop and never reaches `_check.gd`, which is
## a gate that passes because it cannot see the file it was written for. A
## preload is a literal string in the file, so reading the file cannot come back
## half-answered.
##
## Static, as is `_stored`, and that is not tidiness: neither touches instance
## state, both take everything they read as an argument, and making them static
## is the only reason `test.gd` can reach them at all. Instantiating this script
## to call them would run `_init`, which exports a pack and then calls `quit()`.
## So without `static` the entire logic of the one gate that can see an export
## filter dropping a file is unreachable from the headless suite, and the only
## gate that could test it is the one that cannot run.
static func _referenced(shipped: Dictionary) -> Dictionary:
	var re := RegEx.new()
	re.compile("(?:pre)?load\\(\"(res://[^\"]+)\"\\)")
	var into := {}
	# Keys are seeded from the shipped set, so a preloaded script that is
	# itself excluded gets its own references walked too and the exclusion is
	# reported at the top rather than one level down.
	for p in shipped:
		if p.ends_with(".gd"):
			into[p] = true
	for p in into.keys():
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		for m in re.search_all(f.get_as_text()):
			into[m.get_string(1)] = true
	return into
