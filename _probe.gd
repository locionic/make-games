extends SceneTree
## Throwaway: report the fight screen's key labels on turn one, so claims about
## how visible the teaching line is come from the engine and not from a render.
##   godot --headless --path . -s _probe.gd
##   godot --headless --path . -s _probe.gd -- --depth=4
##
## `--depth` starts the run at a later fight, which is the only way to read a
## later enemy's tag line and stats off the screen.

func _init() -> void:
	call_deferred("_go")


func _go() -> void:
	var depth := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--depth="):
			depth = maxi(0, int(a.split("=")[1]))
	var g = load("res://main.tscn").instantiate()
	root.add_child(g)
	for _i in 8:
		await process_frame
	await create_timer(0.4).timeout
	g._on_play()
	for _i in 8:
		await process_frame
	await create_timer(0.4).timeout
	# Win the fights in between by ending the turn on a dead enemy, so the real
	# signal and the real reward screen run -- poking `run.depth` would skip the
	# code that decides which enemy you actually get.
	for _d in range(depth):
		var p0 = g.fight_panel
		p0.enc.enemy.hp = 0
		p0._on_end_turn()
		for _i in 8:
			await process_frame
		g._on_reward_chosen(str(g.run.roll_rewards(
			RandomNumberGenerator.new())[0]["id"]))
		for _i in 8:
			await process_frame
		await create_timer(0.2).timeout
	var p = g.fight_panel
	if p != null and p.enc != null:
		for n in ["enemy_name", "enemy_tag", "intent_num", "ticker", "hud_label"]:
			var l = p.get(n)
			var r: Rect2 = l.get_global_rect()
			print(n, "  y=", int(r.position.y), "..", int(r.position.y + r.size.y),
				"  font=", l.get_theme_font_size("font_size"),
				"  #", l.get_theme_color("font_color").to_html(false),
				"  '", l.text, "'")
		var e = p.enc.enemy
		print("foe  '%s'  hp=%d/%d  armor=%d  atk=%d  behavior='%s'" % [
			e.title, e.hp, e.max_hp, e.armor, e.atk, e.behavior_name()])
	else:
		print("no fight panel at depth ", depth, " -- the reward screen is up")
	quit()
