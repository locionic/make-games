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
	var args := OS.get_cmdline_user_args()
	check_only = "--check" in args
	# `--at 360`, so the gate can be asked about a phone narrower than the one
	# the layout is authored on. Godot's own `--resolution` cannot answer that:
	# it changes the window and leaves the canvas at 540x960.
	var i := args.find("--at")
	if i >= 0 and i + 1 < args.size():
		screen_dp = float(args[i + 1])
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
	_check(mb != null, "the game has a mute button")
	_check(not AudioServer.is_bus_mute(0), "the game starts audible")
	mb.pressed.emit()
	await _settle()
	_check(AudioServer.is_bus_mute(0), "pressing the button mutes the bus")
	_check(bool(RunState.load_stats()["muted"]), "and the choice is written to the save")
	mb.pressed.emit()
	await _settle()
	_check(not AudioServer.is_bus_mute(0), "pressing it again unmutes")
	_check(not bool(RunState.load_stats()["muted"]), "and clears the save")

	# One mute has to cover the bed and the effects. They share the master bus,
	# which is what set_bus_mute(0) flips -- so if an effect is ever moved to a
	# bus of its own, the button silently stops silencing it and this is the
	# only thing that says so.
	for p in game._sfx:
		_check(p.bus == "Master", "every effect rides the master bus, so one mute covers all of it")

	# Two runs done, so the picker has every state in it to show.
	RunState.record_run(3, false)
	RunState.record_run(4, false)
	game.show_title()
	await _settle()
	_ergonomics(game, "title")
	_grab(1, "title-pick-your-hand")

	# Swap a die in and out. The hand starts full, so the first tap frees a slot
	# and the second fills it. Both have to survive the redraw -- the picks used
	# to be wiped by the reseed inside show_title(), leaving the tap a no-op.
	game._on_die_picked("Hex")
	await _settle()
	_check(game.pool.size() == 3, "tapping a held die takes it out of the hand")
	game._on_die_picked("Riposte")  ## owned but benched -- now there is room
	await _settle()
	_check(game.pool.size() == 4, "a benched die swaps into the hand the pick freed")
	_check(game.pool.has("Riposte") and not game.pool.has("Hex"), "and it is the die that moved")
	## No shot here: this is the title screen from #2 with one die swapped, and
	## Play takes at most 8 per device type. #2 already shows the picker open.
	game._on_daily()
	await _settle()
	var panel = game.fight_panel
	# The bed has to follow the screen. This is the only place both are true at
	# once -- title plays menu, fight plays combat -- so it is the only place the
	# swap can be caught if _music_to ever stops being called from _swap.
	_check(game.music.playing, "the fight screen has music playing")
	_check(game.music.stream == game._tracks[game.MUSIC_COMBAT], "and it is the combat bed, not the menu bed")
	# Every effect this run can reach has to actually be on disk, or the name
	# resolves to null and play_sfx returns silently -- a missing sound file
	# would otherwise look exactly like a mute.
	for n in game.SFX.keys():
		_check(game.SFX[n] != null, "the %s effect is present" % n)
	_grab(2, "fight-daily")  ## the daily badge, before anything is rolled

	panel._on_roll()
	_check(_last_stream(game) == game.SFX["roll"], "rolling the dice clatters")
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
	_check(_last_stream(game) == game.SFX["tap"], "queueing a die ticks")
	panel._on_reroll()
	_check(_last_stream(game) == game.SFX["roll"], "and the re-roll clatters again")
	_check(_last_vol(game) < 0.0, "quieter than the opening roll, so the two are tellable apart")
	# PLAN.md 3.1: a nudged die and a re-rolled die must not look alike. Only half
	# of that is observable -- the tumble is a tween no idle screenshot catches --
	# so the half that bites is that the gold tick belongs to Focus alone. A
	# gamble dressed in certainty's colours is the exact failure the split
	# animation exists to prevent.
	_check(panel.find_children("Tick", "Label", false, false).is_empty(),
		"a re-roll raises no tick -- the gold tick is Focus's alone")
	await _settle()

	# Focus, end to end through the UI rather than the rules layer. The mode has
	# to disarm itself, and a cancelled arm has to cost nothing -- a mode that
	# leaked into the next tap would turn a re-roll into a focus.
	#
	# The hand is pinned, not rolled, because "a die has a strictly better
	# face" is a property of a random draw and not of the code: every die that
	# landed on its own maximum has nothing to step up to, and `can_focus`
	# says no. The chance of all three unspent dice being on their best faces
	# is about one in two hundred, so this failed roughly one run in the
	# hundred-and-fifty the harness is run -- and at the time a failure did not
	# even fail, it hung to the timeout. That is the worst shape a gate can
	# have: rare, and silent about being rare. Face 0 is the cheapest face on
	# any die, so a die sitting on it always has something above it, and the
	# thing under test -- Focus, through the UI -- is unaffected by which face
	# was chosen.
	for i in panel.enc.dice.size():
		if not panel.enc.dice[i].spent and i != panel.enc.banked:
			panel.enc.dice[i].up = 0
			break
	var target := -1
	for i in panel.enc.dice.size():
		if panel.enc.can_focus(i):
			target = i
			break
	_check(target >= 0, "a die on face 0 always has a better face above it")
	var was: int = panel.enc.dice[target].face().worth()
	var charges: int = panel.enc.focus_left
	panel._on_focus_pressed()
	_check(panel.focus_armed, "the Focus button arms a mode")
	panel._on_focus_pressed()
	_check(not panel.focus_armed, "and pressing it again cancels it")
	_check(panel.enc.focus_left == charges, "a cancelled focus costs nothing")
	panel._on_focus_pressed()
	panel._on_card_pressed(target)
	_check(not panel.focus_armed, "spending the focus disarms the mode")
	_check(panel.enc.focus_left == charges - 1, "and uses exactly one charge")
	_check(panel.enc.dice[target].face().worth() > was, "the focused die is strictly better")
	_check(panel.enc.dice[target].spent, "and is spent, so it cannot be re-rolled as well")
	_check(_last_stream(game) == game.SFX["block"], "focus chimes, the set's other rising sound")
	# The other half of 3.1. The tick is created synchronously and floats for
	# 0.7s, so it is still findable on the very next line -- and it is named
	# "Tick" rather than "Float" so this cannot be satisfied by a damage number,
	# which is what gives the re-roll assertion above its meaning.
	_check(panel.find_children("Tick", "Label", false, false).size() == 1,
		"and a gold tick rises off the card Focus just spent")

	# Bank, through the same three doors. The rule the UI has to protect is the
	# mutual exclusion: Focus and Bank are both "spend a resource on one die", so
	# a card tap landing in the wrong mode is the failure that would eat a
	# re-roll and nobody would see why.
	var hold := -1
	for i in panel.enc.dice.size():
		if i != target and not panel.enc.dice[i].spent:
			hold = i
			break
	_check(hold >= 0, "the roll left at least one unspent die to hold")
	# A live charge, or the mutual exclusion is half untestable: the focus block
	# above spent the fight's only one, and Focus rightly refuses to arm without.
	panel.enc.focus_left = 1
	panel._on_focus_pressed()
	_check(panel.focus_armed, "with a charge in hand, Focus arms")
	panel._on_bank_pressed()
	_check(panel.bank_armed and not panel.focus_armed,
		"arming Bank closes Focus -- one armed mode at a time")
	panel._on_focus_pressed()
	_check(panel.focus_armed and not panel.bank_armed, "and arming Focus closes Bank back")
	panel._on_bank_pressed()
	panel._on_card_pressed(hold)
	_check(not panel.bank_armed, "holding a die disarms the mode, same as spending does")
	_check(panel.enc.banked == hold, "the die is held")
	_check(panel.effect_labels[hold].text == "HELD", "and the card says so")
	panel._on_bank_pressed()
	panel._on_card_pressed(hold)
	_check(panel.enc.banked == -1, "holding it again releases it, and costs nothing")
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
	_check(pin >= 0, "the roll left a die that can actually hurt the enemy")
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
	_check(panel.enc.banked == hold, "the hold survived the turn")
	_check(panel.enc.dice[hold].face().worth() == held_worth, "and the die kept its face")
	_check(panel.effect_labels[hold].text == "HELD", "still marked as held")
	_grab(3, "fight-roll-reroll")

	# The turn's own sounds, each tied to the same delta that moved the bar. The
	# damage face above makes the strike unconditional; hurt is not, and a turn
	# that rolled all block must stay silent rather than thud.
	_check(panel.enc.enemy.hp < foe_hp, "the pinned face struck the Grunt")
	_check(_sfx_fired(game, "strike"), "hitting the enemy strikes")
	_check(_sfx_fired(game, "block") == had_block, "block chimes only when the roll gained some")
	if my_hp - panel.enc.hp > 0:
		_check(_sfx_fired(game, "hurt"), "and taking it back hurts")
	# An unresolvable name must not advance the pool: a typo in a sound name
	# would otherwise steal the next effect's player and cut it off.
	var turn_before: int = game._sfx_next
	game.play_sfx("no-such-sound")
	_check(game._sfx_next == turn_before, "an unknown name is a no-op, not a crash")

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
	_check(cards.size() == 3, "the reward screen offers exactly three cards")
	for c in cards:
		var box: Rect2 = c.get_global_rect()
		for l in c.find_children("*", "Label", true, false):
			var lr: Rect2 = l.get_global_rect()
			_check(lr.position.x >= box.position.x and lr.end.x <= box.end.x,
				"'%s' fits inside its card horizontally" % l.text)
			_check(lr.position.y >= box.position.y and lr.end.y <= box.end.y,
				"'%s' fits inside its card vertically" % l.text)
	_ergonomics(game, "reward")
	_grab(5, "reward-pick-one")

	for id in ["ADD_DIE", "FOCUS", "VIGOR"]:
		game.run.upgrades.append(id)
	game.run.depth = 5
	game.show_end(false, true)
	await _settle()
	_ergonomics(game, "run over")
	_grab(6, "run-over")

	# The share button's whole job is the confirmation, so catch it lit up.
	# `owned` is off: the button's owner is the row it sits in, not `screen`.
	var share_btn = game.screen.find_child("Share", true, false)
	_check(share_btn != null, "the end screen has a share button to press")
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
	_check(plated.enemy_tag.text.find("Exposed") == -1, "no Exposed tag before it is exposed")
	_check(plated.enemy_tag.get_theme_color("font_color") == T.MUTED,
		"armour is stated in the muted colour, like every other permanent fact")
	plated.enc.enemy.exposed = 1
	plated._refresh()
	await _settle()
	_check(plated.enemy_tag.text.find("Exposed") != -1,
		"exposing the enemy puts the tag on screen")
	_check(plated.enemy_tag.text.find("Armour %d" % Rules.Enemy.ARMOR_GROW_CAP) != -1,
		"and it does not replace the armour reading")
	_check(plated.enemy_tag.get_theme_color("font_color") == T.GOLD,
		"in gold, the colour everything else uses for live-and-act-on-it")
	_grab(8, "fight-armoured")

	# The impact frame. Every grab above photographs the fight at rest, and the
	# Phase 3.2 numbers live and die inside a tween, so nothing in this harness
	# has ever proved one reaches the screen -- a regression that stopped the
	# damage numbers appearing would pass all eight. Into SPARE: Play caps the
	# listing at 8 and spending a real slot on an action frame is not this file's
	# call to make.
	#
	# The roll is loaded rather than rolled. A real roll of Ward and rust faces
	# deals nothing, so the frame would photograph a turn with no number on it
	# and pass every assertion while proving nothing -- which is exactly what the
	# first version of this did. One Blade showing its 9 into a plate of 4: 5
	# lands and the plate eats the other 4, so the damage number and the
	# deflection callout both come off a single face. The Wards the roll left in
	# place bank block, which is the third number on the card.
	#
	# The plate comes down to 4 for this. At the cap of 12 the top Blade face is 9
	# and nothing a single die can show ever gets through, so a full-plated enemy
	# photographs a turn where the plate eats everything and the only number on
	# the card is how much it ate.
	plated.enc.enemy.exposed = 0
	plated.enc.enemy.hp = 40
	plated.enc.enemy.armor = 4
	plated._on_roll()
	await _settle()
	var blade: Array = Rules.Encounter.library()[0].faces
	plated.enc.dice[0].faces = blade
	plated.enc.dice[0].up = 5
	# Every die but the pinned Blade is pinned too, to the first face of its
	# own that deals nothing. The fight panel seeds its rng from the clock
	# (`rng.randomize()` in _build_panel), so an unpinned hand is a different
	# hand on every run -- and this section asserts exact totals off it, 5
	# through the plate and exactly 4 deflected. One stray damage face in
	# the other three dice moved both numbers and failed the gate on a coin
	# flip, which is not what a regression harness is for: the screenshot
	# and the arithmetic it teaches both have to be the same run to run.
	for i in range(1, plated.enc.dice.size()):
		var hand: Rules.Die = plated.enc.dice[i]
		for fi in hand.faces.size():
			if hand.faces[fi].dmg == 0:
				hand.up = fi
				break
	plated._refresh()
	await _settle()
	# The marker the resolve has to leave alone. Quiet, so a regression cuts a
	# sound nobody can hear into rather than making the run unbearable.
	game.play_sfx("roll", -60.0)
	var hp_before: int = plated.enc.enemy.hp
	plated._on_end_turn()
	# SFX_POOL's comment claims the pool is big enough that "a clatter and a hit
	# can overlap; one player would eat the other". That is a claim about how
	# many sounds one resolve asks for, and nothing checked it.
	#
	# Here rather than at the first end turn in the file, because this is the
	# one that provably deals damage -- the other returned early on its guards
	# and fired nothing, so a marker placed there survived no matter what the
	# pool was sized. A check that passes because nothing happened is worse than
	# no check, and it took a pool of 2 to notice: with the pool cut to 2 this
	# section still had to fail, and at the first end turn it passed.
	_check(_busy(game) >= 2,
		"the resolve fired sounds, so the pool check below is not vacuous")
	_check(_sfx_alive(game, "roll"),
		"a full resolve does not eat a sound already playing (%d of %d players in use)"
		% [_busy(game), game._sfx.size()])
	# Exactly one frame, and it is load-bearing. A float fades over 0.7s from a
	# 0.25s delay and frees itself at 0.95s, and this container's software GL
	# renders at about a third of a second a frame -- so waiting three frames
	# lands past the fade but before the free, and the label is still in the
	# tree, still findable, and completely invisible. The first version of this
	# asserted on three such labels and photographed an empty card.
	await process_frame
	var floats: Array = []
	# By group, not by name: add_child() keeps sibling names unique, so only
	# the first float of a turn is called "Float" and the rest arrive as
	# "@Float@2" and "@Float@3". Filtered to this panel because a float from an
	# earlier fight can still be in the air.
	for f in get_nodes_in_group("float"):
		if f.get_parent() == plated:
			floats.append(f)
	# Asserted on the numbers, not just the count: a count alone is satisfied by
	# one lone block float while a whole turn's worth of feedback is missing.
	var seen := ""
	for f in floats:
		var l := f as Label
		seen += l.text + " / "
		# Present in the tree is not the same as on the card. A float that has
		# already faded is found by every query above and photographs as nothing.
		_check(l.modulate.a > 0.5, "the number is still opaque when the frame is taken")
	# The card has to agree with the rules layer, so every expected number is read
	# off the encounter after the resolve rather than written in here. A literal
	# would be a second copy of the rules to keep in step, and the first version
	# of this asserted "4 deflected" against a fixture that in fact produced 5.
	_check(seen.find("-%d" % (hp_before - plated.enc.enemy.hp)) != -1,
		"the damage that got through is on the card (saw: %s)" % seen)
	_check(seen.find("%d deflected" % plated.enc.last_deflected) != -1,
		"and so is the damage the plate ate (saw: %s, last_deflected=%d)"
		% [seen, plated.enc.last_deflected])
	# The block float is deliberately not asserted on. The enemy's turn runs inside
	# _on_end_turn() and spends what was banked, so there is no reading of enc.block
	# after the fact that is the number the float showed -- and the block that got
	# banked came off the three dice this fixture does not control, so it is not
	# even the same number twice. `seen` carries it when it happens; the two
	# numbers above are the ones a test can actually pin down.
	# Every float is anchored to the sigil or the player's bar and the tween only
	# lifts it 34px, so nothing legitimate lands further than 80px from one of
	# them. This is the invariant the placement bug broke: feeding a global point
	# into a local `position` parked every number against the panel's top-left
	# corner, which still *looked* like a number on the card in a still.
	var anchors: Array[Vector2] = [
		plated.enemy_sigil.global_position + plated.enemy_sigil.size * 0.5,
		plated.player_bar.global_position + plated.player_bar.size * 0.5,
	]
	for f in floats:
		var near := false
		for a in anchors:
			if (f as Control).global_position.distance_to(a) < 80.0:
				near = true
		_check(near, "the float lands on the control it describes, not the panel corner")
	_grab(9, "fight-impact", SPARE)

	# PLAN.md 4.1, the part of it that runs without a handset. "Touch
	# ergonomics for the new buttons on small screens" is a claim about
	# geometry, and every grab above photographs the fight at rest -- which
	# shows a button is *present* and says nothing about whether it is big
	# enough to hit, whether its label is cut off, or whether two of them
	# have started to overlap. A screenshot cannot see any of that.
	#
	# This is the check `fight.gd:200` claims already exists ("Five across
	# 508px is 96px each, which the labels below fit; that is checked, not
	# assumed"). It was not. Nothing in the repo asserted a touch target
	# until now -- `_rects.gd` reasons about the six-dice tight case in a
	# comment and then only dumps rects for a human to read.
	_ergonomics(game, "four-dice hand")

	# The tight case, and the last thing this file does. Six dice is where
	# the cards are narrowest, so it is the only hand where a tap target can
	# fall under the minimum. It runs after every grab on purpose: adding dice
	# mutates the run, and anything below this line would inherit that.
	game.run.apply_upgrade("ADD_DIE", game.rng)
	game.run.apply_upgrade("ADD_DIE", game.rng)
	game.show_fight()
	await _settle()
	_ergonomics(game, "six-dice hand")

	if had_save:
		DirAccess.copy_absolute(BACKUP, SAVE)
		DirAccess.remove_absolute(BACKUP)
	# Non-zero on a failed check, so `--check` can be run in a loop instead of
	# being read. Verified both ways: 48 exits 0, 96 exits 1.
	quit(1 if _fails > 0 else 0)


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


## How many pool players are sounding at once. The pool's size is only
## justified if this stays under it.
func _busy(game) -> int:
	var n := 0
	for p in game._sfx:
		if p.playing:
			n += 1
	return n


## Whether a sound of this name is still sounding on some pool player. A name
## rather than a player index, because round-robin moves: what the pool must not
## do is eat the sound, not use a particular slot.
func _sfx_alive(game, name: String) -> bool:
	for p in game._sfx:
		if p.playing and p.stream == game.SFX[name]:
			return true
	return false


## Did this sound go off at any point in the turn? Scans the whole pool rather
## than just the last player, because one turn can fire up to three sounds and
## the interesting question is "did the block chime", not "was it the last one".
func _sfx_fired(game, name: String) -> bool:
	for p in game._sfx:
		if p.stream == game.SFX[name]:
			return true
	return false


## Material's minimum touch target, in dp. 48dp is the number Android's own
## design guidance gives and the one a fingertip can reliably land on.
const TOUCH_MIN := 48.0

## The narrowest phone this is expected to clear: 360dp, and it does.
##
## 320dp is not a tuning miss, it is geometry. Clearing 48dp at 320dp needs 81
## canvas units, and the six-dice card row is six cards across 508px -- 78 units
## each, fixed by the die count, not by any height anyone picks. No button
## height fixes it; only fewer dice per row does. 320 is Play's *screenshot*
## floor, not a screen width, so the honest reading of `--at 320` failing is
## "the layout does not claim that device", not "ship a bug". Run the sweep
## from PLAN.md's gate: `--check --at 360`, `--at 411`, `--at 540`.

## How many checks this run has failed.
var _fails := 0

## Width of the phone being reasoned about, in dp. `--at 360` for a narrow one.
## Defaults to 540 because that is the canvas the layout is authored on, and
## one canvas unit is one dp there and only there -- which is what the first
## version of this gate quietly assumed everywhere. See _dp().
var screen_dp := 540.0


## A size in canvas units as the finger meets it, in dp.
##
## `canvas_items` + `expand` never shrinks the canvas: the viewport stays
## 540x960 in canvas units on any window, and the whole thing is scaled to fit.
## So a 360dp phone draws a 54-unit button as 36dp, and no amount of widening
## the canvas fixes it. Measured rather than reasoned: run this gate at
## `--resolution 360x640` and it prints the *identical* 540x960 and 96x54 as the
## 540-wide run, which is the gate being blind, not the layout being fine.
## PLAN.md 4.1 asks about "small screens (540x960 baseline)" and the baseline
## was the only screen the gate ever looked at.
##
## Now measured, and recorded here because 4.1's hardware pass is the half of it
## that cannot be run from this machine and it is arguing with exactly this
## number. The smallest target in the layout is 74x74 canvas units, and it has
## no floor of its own -- the effective size is linear in screen width, so the
## whole safety margin lives in the width of the phone:
##
##     360dp -> 49.3dp   (+1.3 over the 48 minimum, 2.7% headroom)
##     375dp -> 51.4dp   (+3.4)      411dp -> 56.3dp   (+8.3)
##     540dp -> 74.0dp   (+26.0)     the authored baseline
##
## Crossover is 350dp: below that the smallest target drops under 48dp and the
## gate turns red on its own. 360dp is the narrowest Android ships in practice,
## so the floor holds everywhere real, but 2.7% is the entire margin at that
## width -- a single row of padding, or a card font step, decides it. If a
## layout change ever shows up in the hardware pass as "hard to hit", this is
## the number to read first.
func _dp(canvas_px: float) -> float:
	return canvas_px * screen_dp / 540.0


## assert(), except it is a gate and not a debugger breakpoint.
##
## `assert()` is the wrong primitive twice over here, and both halves were found
## by running the thing rather than reading it. It aborts `_run()` where it
## stands, so the `quit()` below never runs and a failure hung to the timeout
## instead of reporting. And on this engine an assert that does abort still
## exits 0 -- measured, not assumed: with the minimum raised to 96 the run
## printed "Assertion failed: 'Roll' is a 96x54 target, over the 96 minimum"
## for both hands and `$?` was 0. A gate whose result nothing can read is a
## gate nobody runs, which is the whole reason `--check` exists.
func _check(cond: bool, msg: String) -> void:
	if cond:
		return
	_fails += 1
	push_error("FAILED: " + msg)



## Every tappable thing on a screen, read off the laid-out rects.
##
## Three claims, and none of them is "the button exists" -- a screenshot has
## that already covered eight times over. A target is *big enough*, a label
## *fits inside* it, and two targets do not *overlap*. The middle one is the
## one that bites, because the buttons carry counts ("Focus (1)",
## "Re-roll (1)") that grow with the run, and the row is fixed at five
## across 508px: more text does not make the button wider, it makes the label
## overflow. `get_combined_minimum_size` is the engine's own answer to "how
## wide does this control want to be", so comparing it against what the
## container actually granted catches a squeeze the moment it happens rather
## than when someone squints at a PNG.
##
## This walks the tree rather than taking a panel, and that is not tidiness.
## Given a panel it could only ever see the fight screen's five buttons and
## its dice, so it called itself a check on touch ergonomics while the mute
## button sat at 34 units tall -- under the 48dp floor at *every* width,
## including the one the canvas is authored at -- and the title and reward
## screens were never looked at. Cards are Buttons already, so walking covers
## them too and the separate card loop went away with the panel.
func _ergonomics(root: Node, label: String) -> void:
	var vp: Vector2 = root.get_viewport_rect().size
	var targets: Array[Button] = []
	_collect(root, targets)
	# The narrowest and shortest thing a finger has to land on, measured rather
	# than assumed. Printed at the end, because this is the number a hardware
	# pass is arguing with and it is not otherwise recorded anywhere.
	var smallest := Vector2(INF, INF)
	for b in targets:
		var c := b as Control
		smallest = smallest.min(c.size)
		_check(_dp(c.size.x) >= TOUCH_MIN and _dp(c.size.y) >= TOUCH_MIN,
			"%s: '%s' is a %.0fx%.0f target, %.0fx%.0f dp on a %ddp screen, over the %.0f minimum"
			% [label, b.text, c.size.x, c.size.y, _dp(c.size.x), _dp(c.size.y),
				screen_dp, TOUCH_MIN])
		var r := c.get_global_rect()
		_check(r.position.x >= 0.0 and r.position.y >= 0.0
			and r.end.x <= vp.x and r.end.y <= vp.y,
			"%s: '%s' fits the %.0fx%.0f screen (at %s)"
			% [label, b.text, vp.x, vp.y, r])
		_check(c.get_combined_minimum_size().x <= c.size.x,
			"%s: '%s' label fits its %.0fpx button (wants %.0f)"
			% [label, b.text, c.size.x, c.get_combined_minimum_size().x])

	# Overlap, across every row at once. A Container will happily hand two
	# growing labels less width than their combined minimum and let them
	# collide, which looks fine in a still and is unusable under a thumb.
	for i in range(targets.size()):
		for j in range(i + 1, targets.size()):
			var a: Rect2 = (targets[i] as Control).get_global_rect()
			var b2: Rect2 = (targets[j] as Control).get_global_rect()
			_check(not a.intersects(b2),
				"%s: target %d ('%s') does not overlap %d ('%s')"
				% [label, i, targets[i].text, j, targets[j].text])

	# A target must not sit on top of a solid fill. ColorRects are the game's
	# opaque blocks -- depth pips, the enemy sigil, bar fills -- so an overlap
	# here is a button drawn on top of something the player is meant to read.
	# Found by running it rather than by assuming: the sound toggle is the one
	# control that shares its corner with the depth strip on every screen, and
	# the strip's comment claimed that corner was free without ever measuring
	# it. It is: the pips end at x=369 and the toggle starts at 456, 87px clear,
	# and that is the worst case, because the strip draws all nine pips including
	# the wide boss one whatever the depth, and the daily tag adds height rather
	# than width.
	var fills: Array[Control] = []
	for c in root.find_children("*", "ColorRect", true, false):
		if c is Control and c.is_visible_in_tree():
			fills.append(c)
	for t in targets:
		var tr2 := (t as Control).get_global_rect()
		for f in fills:
			var fr := (f as Control).get_global_rect()
			_check(not tr2.intersects(fr),
				"%s: '%s' sits on top of a solid fill at %s"
				% [label, t.text, fr])

	# Said out loud on the way past, so a green run records what it measured
	# rather than only that it did not object. The numbers are the ones a
	# hardware pass is then arguing with.
	_check(not targets.is_empty(), "%s: found no targets to measure" % label)
	print("_ergonomics: %s -- %d targets, smallest %.0fx%.0f (%.0fx%.0f dp at %ddp), canvas %.0fx%.0f"
		% [label, targets.size(), smallest.x, smallest.y,
			_dp(smallest.x), _dp(smallest.y), screen_dp, vp.x, vp.y])


## Every visible Button under `n`, depth first. Invisible ones are skipped:
## a screen that `_swap` has replaced is still in the tree, and its buttons
## have a stale or zero rect that would fail every check for no reason.
func _collect(n: Node, out: Array[Button]) -> void:
	if n is Button and n.is_visible_in_tree():
		out.append(n)
	for child in n.get_children():
		_collect(child, out)


## Set by `--check`. The ergonomics gate lives here because this is the only
## thing in the repo that lays the fight out and reads back real rects -- but
## that made the gate unusable on its own: every run of it rewrote
## play/screenshots/, so verifying PLAN.md 4.1's touch targets meant re-shooting
## the whole Play listing, and on a working tree with someone else's uncommitted
## screenshots in it, re-shooting means overwriting them. `--check` walks the
## identical flow, runs every assertion, and writes nothing. A layout gate that
## has to publish store art to be allowed to run is a gate nobody runs.
var check_only := false


func _grab(n: int, name: String, dir: String = SHOTS) -> void:
	# Before the read-back, not after: the only thing below this line that
	# matters is producing a file, and producing files is the part being skipped.
	if check_only:
		return
	var path := dir % [n, name]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := root.get_texture().get_image()
	# The viewport read-back is RGBA; Play takes screenshots as JPEG or 24-bit
	# PNG with no alpha, and rejects the alpha channel. Flatten to RGB here so a
	# re-run cannot put a non-compliant file back in the listing.
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("wrote ", path, " ", img.get_size())
