extends SceneTree
## Throwaway: print the title screen's widget tree with real rects and the
## colour each label actually rendered at, so layout claims come from the
## engine instead of from squinting at a downscaled PNG.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s _rects.gd

const RunState = preload("res://run.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# This tool wants the title screen's *fresh* state -- "Begin the run" rather
	# than "Play", and an empty stats line -- because a saved profile renders
	# different text, and this file exists to measure text. It used to get that
	# by copying the real save to a fixed /tmp path, deleting the save, and
	# restoring it on the way out.
	#
	# That was eight lines wrapped around a data-loss window. A crash anywhere
	# between the delete and the restore took the player's history with it, and
	# nothing swept up afterwards. The fixed path made it worse than a lone run:
	# two copies at once backed up to the same file, so the second overwrote the
	# first and one of the two restores could put back the wrong history.
	#
	# Redirecting the path is what `test.gd:22` already does, it is one line
	# instead of eight, and it closes the window rather than narrowing it: no
	# copy, no delete, nothing written outside the project. It shares
	# `test.gd`'s scratch filename deliberately, so at most one stray file
	# exists rather than one per tool.
	#
	# If the redirect ever failed to take, the failure is that this dumps a title
	# screen carrying the player's real stats -- a wrong measurement. The old
	# code's version of that same failure destroys their save. Strictly milder,
	# which is the whole reason this is safe to change in a file that cannot be
	# run from here.
	RunState.SAVE_PATH = "user://self-test.json"
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for _i in 8:
		await process_frame
	await create_timer(0.4).timeout

	var args := OS.get_cmdline_user_args()
	if "--fight" in args or "--six" in args:
		game._on_play()
		for _i in 8:
			await process_frame
		await create_timer(0.4).timeout
		if "--six" in args:
			# A full pool is the tight case for touch targets: the cards share
			# the same width, so six of them is the narrowest they ever get.
			game.run.apply_upgrade("ADD_DIE", game.rng)
			game.run.apply_upgrade("ADD_DIE", game.rng)
			game.show_fight()
			for _i in 8:
				await process_frame
			await create_timer(0.4).timeout
		_dump(game.fight_panel, 0)
	elif "--reward" in args:
		game._on_play()  ## the title screen nulls `run`; there is none until a run starts
		for _i in 8:
			await process_frame
		await create_timer(0.4).timeout
		game.show_reward(game.run.roll_rewards(game.rng))
		for _i in 8:
			await process_frame
		await create_timer(0.4).timeout
		_dump(game.screen, 0)
	elif "--end" in args:
		game._on_play()
		for _i in 8:
			await process_frame
		await create_timer(0.4).timeout
		for id in ["ADD_DIE", "FOCUS", "VIGOR"]:
			game.run.upgrades.append(id)
		game.run.depth = 5
		game.show_end(false, true)
		for _i in 8:
			await process_frame
		await create_timer(0.4).timeout
		_dump(game.screen, 0)
	else:
		_dump(game.screen, 0)

	quit()


func _dump(n: Node, depth: int) -> void:
	for c in n.get_children():
		if c is Control:
			var r := (c as Control).get_global_rect()
			var txt := ""
			var col := ""
			if c is Label:
				txt = (c as Label).text
				col = "#" + (c as Label).get_theme_color("font_color").to_html(false)
			elif c is Button:
				txt = (c as Button).text
			print("  ".repeat(depth), c.get_class(), "  y=", int(r.position.y),
				"..", int(r.position.y + r.size.y), "  x=", int(r.position.x),
				"..", int(r.position.x + r.size.x), "  ", col, " '", txt, "'")
		_dump(c, depth + 1)
