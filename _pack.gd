extends SceneTree
## Does an exported build still contain every file the game loads?
##   godot --headless --path . -s _pack.gd -- "Android"
##
## The export filter is a list of globs in `export_presets.cfg` and nothing
## checks it. That is not hypothetical: the Android preset excludes `_*.gd`,
## and `dice.gd:3` and `run.gd:12` both `preload("res://_check.gd")`, so a
## filter that drops that file ships a rules layer that cannot parse. The
## headless suite cannot see it -- it runs against the source tree, which has
## the file. A blank screen on a Play download, found after upload.
##
## The dependency set is walked out from the main scene with
## `ResourceLoader.get_dependencies`, not written out here. A hardcoded list is
## a second copy of the game's shape that goes stale the day a file is added,
## and a stale list passes while the real dependency went missing -- which is
## the whole failure this file exists to catch.
##
## Why not load the pack instead: `--main-pack` looks like it works, and exits
## 0 on a healthy pack -- but it also exits 0 on a pack with the entire rules
## layer deleted, because it never loads the game's scripts. And
## `load_resource_pack(.., true)` does not help either: with a project running
## from a directory, res:// lookups still resolve to that directory, so a
## project-only file loads even when the mounted pack does not contain it. Both
## are green on a broken build. The exporter's own file list is the only
## statement about the pack here that is not a guess.

const Check = preload("res://_check.gd")
const PROBE := "/tmp/_pack_probe.pck"
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
	quit(Check.report("_pack.gd"))


## Every file the exporter put in the pack, keyed by the *source* path. It
## stores compiled and remapped names -- `dice.gd.remap` and `dice.gdc` both
## stand for `dice.gd` -- so both are folded back onto the name a dependency
## walk produces, otherwise every single script reads as missing.
func _stored(log: String) -> Dictionary:
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
## `ResourceLoader.get_dependencies` is not reliable here: running from a
## directory rather than from a pack it answers for two of this game's eight
## files and calls the rest dependency-free, which is a gate that passes
## because it cannot see. A preload is a literal string in the file, so
## reading the file cannot come back half-answered.
func _referenced(shipped: Dictionary) -> Dictionary:
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
