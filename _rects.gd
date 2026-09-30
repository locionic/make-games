extends SceneTree
## Throwaway: print the title screen's widget tree with real rects and the
## colour each label actually rendered at, so layout claims come from the
## engine instead of from squinting at a downscaled PNG.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s _rects.gd

const RunState = preload("res://run.gd")
var SAVE := RunState.SAVE_PATH  ## `var`, not `const`: SAVE_PATH is a static var
const BACKUP := "/tmp/dice-save-backup2.json"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var had := FileAccess.file_exists(SAVE)
	if had:
		DirAccess.copy_absolute(SAVE, BACKUP)
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

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

	if had:
		DirAccess.copy_absolute(BACKUP, SAVE)
		DirAccess.remove_absolute(BACKUP)
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
