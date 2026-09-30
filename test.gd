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
	print("self_test: reached end")
	# report() prints every failure and returns 0 or 1, so a broken suite exits
	# non-zero instead of aborting _init() and hanging the SceneTree forever.
	quit(Check.report("test.gd"))
