extends SceneTree
## Throwaway capture tool, not part of the game.
## Godot draws through a GL surface that x11grab cannot see, so we have Godot
## read back its own viewport instead. Run with a display present (Xvfb ok):
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s shot.gd
## Walks the real flow and writes one PNG a step. It rewrites user://run.json to
## stage the title screen, so the player's real save is copied out and put back.

const Rules = preload("res://dice.gd")
const RunState = preload("res://run.gd")
const T = preload("res://theme.gd")
var SAVE := RunState.SAVE_PATH  ## `var`, not `const`: SAVE_PATH is a static var, and a
## static var is not a constant expression, so `const SAVE := RunState.SAVE_PATH`
## fails to parse -- and a failed load still hands back a non-null script, so the
## parse check in test.gd has to reload() rather than just load().
const BACKUP := "/tmp/dice-save-backup.json"
## Google Play wants 2-8 phone screenshots; this writes the whole flow at 540x960
## (9:16, and inside Play's 320px floor) so the listing is a copy, not a shoot.
## Under `res://play/`, which carries a .gdignore, so none of this is imported
## into the APK -- it is store art, not game art.
const SHOTS := "res://play/screenshots/%02d-%s.png"
## Play caps screenshots at 8 and there are exactly 8 in that folder. The
## first-launch title is the one that got cut -- it and the pick-your-hand title
## are both title screens at near-identical size, and the slot was worth more to
## the armoured-fight shot. It is still generated, into `spare/`, so the
## decision stays reversible and nobody has to re-shoot it to change its mind.
const SPARE := "res://play/screenshots-spare/%02d-%s.png"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Stage the save. It is a real file the player owns, not scratch -- so copy
	# it out first and put it back before quitting.
	var had_save := FileAccess.file_exists(SAVE)
	if had_save:
		DirAccess.copy_absolute(SAVE, BACKUP)
	elif FileAccess.file_exists(BACKUP):
		DirAccess.remove_absolute(BACKUP)  ## left over from an earlier run
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await _settle()
	_grab(1, "title-first-launch", SPARE)  ## first launch: the three bonus dice are still locked

	# The mute button has to round-trip: press, the bus mutes and the choice is
	# written; press again, it unmutes. The save is staged from scratch here, so
	# this writes to the scratch file and the real one is restored at the end.
	var mb: Button = game._mute_btn
	assert(mb != null, "the game has a mute button")
	assert(not AudioServer.is_bus_mute(0), "the game starts audible")
	mb.pressed.emit()
	await _settle()
	assert(AudioServer.is_bus_mute(0), "pressing the button mutes the bus")
	assert(bool(RunState.load_stats()["muted"]), "and the choice is written to the save")
	mb.pressed.emit()
	await _settle()
	assert(not AudioServer.is_bus_mute(0), "pressing it again unmutes")
	assert(not bool(RunState.load_stats()["muted"]), "and clears the save")

	# One mute has to cover the bed and the effects. They share the master bus,
	# which is what set_bus_mute(0) flips -- so if an effect is ever moved to a
	# bus of its own, the button silently stops silencing it and this is the
	# only thing that says so.
	for p in game._sfx:
		assert(p.bus == "Master", "every effect rides the master bus, so one mute covers all of it")

	# Two runs done, so the picker has every state in it to show.
	RunState.record_run(3, false)
	RunState.record_run(4, false)
	game.show_title()
	await _settle()
	_grab(1, "title-pick-your-hand")

	# Swap a die in and out. The hand starts full, so the first tap frees a slot
	# and the second fills it. Both have to survive the redraw -- the picks used
	# to be wiped by the reseed inside show_title(), leaving the tap a no-op.
	game._on_die_picked("Hex")
	await _settle()
	assert(game.pool.size() == 3, "tapping a held die takes it out of the hand")
	game._on_die_picked("Riposte")  ## owned but benched -- now there is room
	await _settle()
	assert(game.pool.size() == 4, "a benched die swaps into the hand the pick freed")
	assert(game.pool.has("Riposte") and not game.pool.has("Hex"), "and it is the die that moved")
	## No shot here: this is the title screen from #2 with one die swapped, and
	## Play takes at most 8 per device type. #2 already shows the picker open.
	game._on_daily()
	await _settle()
	var panel = game.fight_panel
	# The bed has to follow the screen. This is the only place both are true at
	# once -- title plays menu, fight plays combat -- so it is the only place the
	# swap can be caught if _music_to ever stops being called from _swap.
	assert(game.music.playing, "the fight screen has music playing")
	assert(game.music.stream == game._tracks[game.MUSIC_COMBAT], "and it is the combat bed, not the menu bed")
	# Every effect this run can reach has to actually be on disk, or the name
	# resolves to null and play_sfx returns silently -- a missing sound file
	# would otherwise look exactly like a mute.
	for n in game.SFX.keys():
		assert(game.SFX[n] != null, "the %s effect is present" % n)
	_grab(2, "fight-daily")  ## the daily badge, before anything is rolled

	panel._on_roll()
	assert(_last_stream(game) == game.SFX["roll"], "rolling the dice clatters")
	await _settle()
	var worst := 0
	var worst_val := 999
	for i in panel.enc.dice.size():
		var f = panel.enc.dice[i].face()
		var val: int = f.dmg + f.block
		if val < worst_val:
			worst_val = val
			worst = i
	panel._on_card_pressed(worst)
	assert(_last_stream(game) == game.SFX["tap"], "queueing a die ticks")
	panel._on_reroll()
	assert(_last_stream(game) == game.SFX["roll"], "and the re-roll clatters again")
	assert(_last_vol(game) < 0.0, "quieter than the opening roll, so the two are tellable apart")

	# Focus, end to end through the UI rather than the rules layer. The mode has
	# to disarm itself, and a cancelled arm has to cost nothing -- a mode that
	# leaked into the next tap would turn a re-roll into a focus.
	var target := -1
	for i in panel.enc.dice.size():
		if panel.enc.can_focus(i):
			target = i
			break
	assert(target >= 0, "the roll left at least one die focusable")
	var was: int = panel.enc.dice[target].face().worth()
	var charges: int = panel.enc.focus_left
	panel._on_focus_pressed()
	assert(panel.focus_armed, "the Focus button arms a mode")
	panel._on_focus_pressed()
	assert(not panel.focus_armed, "and pressing it again cancels it")
	assert(panel.enc.focus_left == charges, "a cancelled focus costs nothing")
	panel._on_focus_pressed()
	panel._on_card_pressed(target)
	assert(not panel.focus_armed, "spending the focus disarms the mode")
	assert(panel.enc.focus_left == charges - 1, "and uses exactly one charge")
	assert(panel.enc.dice[target].face().worth() > was, "the focused die is strictly better")
	assert(panel.enc.dice[target].spent, "and is spent, so it cannot be re-rolled as well")
	assert(_last_stream(game) == game.SFX["block"], "focus chimes, the set's other rising sound")

	# Bank, through the same three doors. The rule the UI has to protect is the
	# mutual exclusion: Focus and Bank are both "spend a resource on one die", so
	# a card tap landing in the wrong mode is the failure that would eat a
	# re-roll and nobody would see why.
	var hold := -1
	for i in panel.enc.dice.size():
		if i != target and not panel.enc.dice[i].spent:
			hold = i
			break
	assert(hold >= 0, "the roll left at least one unspent die to hold")
	# A live charge, or the mutual exclusion is half untestable: the focus block
	# above spent the fight's only one, and Focus rightly refuses to arm without.
	panel.enc.focus_left = 1
	panel._on_focus_pressed()
	assert(panel.focus_armed, "with a charge in hand, Focus arms")
	panel._on_bank_pressed()
	assert(panel.bank_armed and not panel.focus_armed,
		"arming Bank closes Focus -- one armed mode at a time")
	panel._on_focus_pressed()
	assert(panel.focus_armed and not panel.bank_armed, "and arming Focus closes Bank back")
	panel._on_bank_pressed()
	panel._on_card_pressed(hold)
	assert(not panel.bank_armed, "holding a die disarms the mode, same as spending does")
	assert(panel.enc.banked == hold, "the die is held")
	assert(panel.effect_labels[hold].text == "HELD", "and the card says so")
	panel._on_bank_pressed()
	panel._on_card_pressed(hold)
	assert(panel.enc.banked == -1, "holding it again releases it, and costs nothing")
	panel._on_bank_pressed()
	panel._on_card_pressed(hold)
	var held_worth: int = panel.enc.dice[hold].face().worth()

	await _settle()
	var foe_hp: int = panel.enc.enemy.hp
	var my_hp: int = panel.enc.hp
	# Pin a damage face on a die that is not the held one, so the turn below
	# certainly strikes. The claim this used to be made under -- that any roll
	# deals something to a Grunt -- is true of a 0-armour enemy and not of a
	# roll: Ward, Riposte and Sunder's rust all deal nothing, and a hand of them
	# is a legal turn. Adding one card to the reward pool moved the RNG by a
	# single value and started handing out that hand.
	#
	# Pin the *strongest* surviving hit, not the first damage face found. That
	# second version pinned Blade's 2, which the daily fight's armour ate whole,
	# so the turn resolved to nothing and "the pinned face struck" went red on
	# an armoured roll. The assert is right and the fixture was wrong -- same
	# shape as the hand-of-nothing case above it.
	var pierce: int = game.run.pierce
	var pin := -1
	var pin_gain := 0
	for i in panel.enc.dice.size():
		if i == hold:
			continue  ## the held one is not in this resolve
		for j in panel.enc.dice[i].faces.size():
			var gain: int = panel.enc.enemy.pierce(panel.enc.dice[i].faces[j].dmg, pierce)
			if gain > pin_gain:
				pin_gain = gain
				pin = i
				panel.enc.dice[i].up = j
	assert(pin >= 0, "the roll left a die that can actually hurt the enemy")
	# Block is spent by the counter-attack, so its high-water mark is gone by
	# the time the turn returns. Read it off the faces the resolve is *about* to
	# see -- after the pin, and without the held die, which pays on the next
	# resolve rather than this one. Reading it earlier made this assert a report
	# on the pre-pin hand while the chime came from the post-pin one, and it went
	# red twice in eight runs whenever the pin moved the only die that had block.
	var had_block := false
	for i in panel.enc.dice.size():
		if i == hold:
			continue
		if panel.enc.dice[i].face().block > 0:
			had_block = true
	panel._on_end_turn()
	await _settle()
	# The hold's whole promise, checked through the UI: the die comes back from
	# the next roll on the same face, still marked HELD, so the block the player
	# gave up this turn is the block they are holding.
	# This assert is what found a curse enemy dragging a held die to its worst
	# face behind the player's back -- twice in six runs, both times the card
	# still reading HELD. The rule now bans the held die; the fixture stays.
	assert(panel.enc.banked == hold, "the hold survived the turn")
	assert(panel.enc.dice[hold].face().worth() == held_worth, "and the die kept its face")
	assert(panel.effect_labels[hold].text == "HELD", "still marked as held")
	_grab(3, "fight-roll-reroll")

	# The turn's own sounds, each tied to the same delta that moved the bar. The
	# damage face above makes the strike unconditional; hurt is not, and a turn
	# that rolled all block must stay silent rather than thud.
	assert(panel.enc.enemy.hp < foe_hp, "the pinned face struck the Grunt")
	assert(_sfx_fired(game, "strike"), "hitting the enemy strikes")
	assert(_sfx_fired(game, "block") == had_block, "block chimes only when the roll gained some")
	if my_hp - panel.enc.hp > 0:
		assert(_sfx_fired(game, "hurt"), "and taking it back hurts")
	# An unresolvable name must not advance the pool: a typo in a sound name
	# would otherwise steal the next effect's player and cut it off.
	var turn_before: int = game._sfx_next
	game.play_sfx("no-such-sound")
	assert(game._sfx_next == turn_before, "an unknown name is a no-op, not a crash")

	# A run deep enough to hold six dice, so the six-card row gets looked at.
	panel.enc.over = false
	panel.enc.won = true
	panel.enc.dice.append(Rules.Encounter.bonus_dice()[2])
	panel.enc.picks.resize(panel.enc.dice.size())
	panel.enc.picks.fill(false)
	panel._ensure_cards()
	panel._refresh()
	await _settle()
	_grab(4, "fight-six-dice")

	# Forced, not rolled. A store screenshot has to be the same file every run
	# and the 1-of-3 offer is random, so this shot used to be a different PNG
	# each time. It also carries PRECISE_STRIKE on purpose: its description is
	# nearly twice the next longest in the pool, and a reward label has no
	# autowrap, so an overlong one runs off the card and off the screen with
	# nothing to say so.
	var offers: Array = []
	for id in ["PRECISE_STRIKE", "ADD_DIE", "BULWARK"]:
		offers.append(RunState.upgrade_by_id(id))
	game.show_reward(offers)
	await _settle()
	var cards: Array = game.screen.find_children("*", "Button", true, false)
	assert(cards.size() == 3, "the reward screen offers exactly three cards")
	for c in cards:
		var box: Rect2 = c.get_global_rect()
		for l in c.find_children("*", "Label", true, false):
			var lr: Rect2 = l.get_global_rect()
			assert(lr.position.x >= box.position.x and lr.end.x <= box.end.x,
				"'%s' fits inside its card horizontally" % l.text)
			assert(lr.position.y >= box.position.y and lr.end.y <= box.end.y,
				"'%s' fits inside its card vertically" % l.text)
	_grab(5, "reward-pick-one")

	for id in ["ADD_DIE", "FOCUS", "VIGOR"]:
		game.run.upgrades.append(id)
	game.run.depth = 5
	game.show_end(false, true)
	await _settle()
	_grab(6, "run-over")

	# The share button's whole job is the confirmation, so catch it lit up.
	# `owned` is off: the button's owner is the row it sits in, not `screen`.
	var share_btn = game.screen.find_child("Share", true, false)
	assert(share_btn != null, "the end screen has a share button to press")
	share_btn.pressed.emit()
	await _settle()
	_grab(7, "share-result")

	# An armoured enemy. The plating ring only draws when armour > 0, and every
	# other grab here is depth 1 against a Grunt, so it was never rendered and
	# never photographed. ARMOR_GROW_CAP armour puts the ring at full density,
	# which is the shot that actually shows what the enemy is.
	game._on_play()
	await _settle()
	var plated = game.fight_panel
	plated.enc.enemy.armor = Rules.Enemy.ARMOR_GROW_CAP
	plated._refresh()
	await _settle()
	# Exposed rides the same tag line, and it has to be a different colour:
	# armour is a permanent fact about the enemy and Exposed is a one-turn window
	# the player has to spend. Sharing the muted grey would make the one thing
	# worth acting on look like the two things that are not. The tag is
	# capitalize()d on the way out, so the words are matched capitalised too.
	assert(plated.enemy_tag.text.find("Exposed") == -1, "no Exposed tag before it is exposed")
	assert(plated.enemy_tag.get_theme_color("font_color") == T.MUTED,
		"armour is stated in the muted colour, like every other permanent fact")
	plated.enc.enemy.exposed = 1
	plated._refresh()
	await _settle()
	assert(plated.enemy_tag.text.find("Exposed") != -1,
		"exposing the enemy puts the tag on screen")
	assert(plated.enemy_tag.text.find("Armour %d" % Rules.Enemy.ARMOR_GROW_CAP) != -1,
		"and it does not replace the armour reading")
	assert(plated.enemy_tag.get_theme_color("font_color") == T.GOLD,
		"in gold, the colour everything else uses for live-and-act-on-it")
	_grab(8, "fight-armoured")

	if had_save:
		DirAccess.copy_absolute(BACKUP, SAVE)
		DirAccess.remove_absolute(BACKUP)
	quit()


func _settle() -> void:
	for _i in 8:
		await process_frame
	await create_timer(0.35).timeout


# --- sound ---
#
# This machine's only audio driver is the dummy one, so there is no way to listen
# and the effects have to be checked by the only observable they leave: which
# stream landed on which pool player. That is enough to catch the failure that
# matters -- a sound wired to the wrong event, or to none.

## The player the pool handed out most recently. Read it as a stream rather than
## as `playing`, because strike is 0.22s and _settle() alone outlasts it: a
## player keeps its last stream after the clip ends, so this cannot race the
## frame the harness happens to sample on.
func _last_player(game) -> AudioStreamPlayer:
	return game._sfx[(game._sfx_next - 1 + game._sfx.size()) % game._sfx.size()]


func _last_stream(game) -> AudioStream:
	return _last_player(game).stream


func _last_vol(game) -> float:
	return _last_player(game).volume_db


## Did this sound go off at any point in the turn? Scans the whole pool rather
## than just the last player, because one turn can fire up to three sounds and
## the interesting question is "did the block chime", not "was it the last one".
func _sfx_fired(game, name: String) -> bool:
	for p in game._sfx:
		if p.stream == game.SFX[name]:
			return true
	return false


func _grab(n: int, name: String, dir: String = SHOTS) -> void:
	var path := dir % [n, name]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := root.get_texture().get_image()
	# The viewport read-back is RGBA; Play takes screenshots as JPEG or 24-bit
	# PNG with no alpha, and rejects the alpha channel. Flatten to RGB here so a
	# re-run cannot put a non-compliant file back in the listing.
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("wrote ", path, " ", img.get_size())
