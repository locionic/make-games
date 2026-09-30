extends Control
## The run controller and every screen that is not combat: title, the pick-1-of-3
## reward, and the run's end. Fight state lives in fight.gd, rules in dice.gd,
## run state in run.gd. This file is the only one that knows the order things
## happen in.

const Rules = preload("res://dice.gd")
const T = preload("res://theme.gd")
const RunState = preload("res://run.gd")
const Fight = preload("res://fight.gd")

## Two 40s seamless loops generated through FlowMusic2API. The OGG importer does
## not loop on its own, so _ready() sets that on a copy of each.
const MUSIC_MENU := preload("res://audio/menu.ogg")
const MUSIC_COMBAT := preload("res://audio/combat.ogg")
const MUSIC_VOL := -9.0  ## dB. Headroom for anything that plays over the top.
const MUSIC_FADE := 1.2  ## seconds, split evenly either side of the swap

## Sound effects, synthesised by `_mksfx.py` rather than generated. FlowMusic is
## a music model and ignores `duration` -- a 5s request comes back at two minutes
## -- so it cannot make a 200ms die-clack. Procedural costs 43KB for all seven,
## has no licence, and lands exactly on the event that asked for it.
const SFX := {
	"roll": preload("res://audio/roll.ogg"),
	"tap": preload("res://audio/tap.ogg"),
	"hurt": preload("res://audio/hurt.ogg"),
	"strike": preload("res://audio/strike.ogg"),
	"block": preload("res://audio/block.ogg"),
	"win": preload("res://audio/win.ogg"),
	"lose": preload("res://audio/lose.ogg"),
}
const SFX_VOL := -7.0  ## dB. Under the bed, not on top of it.
const SFX_POOL := 6  ## a clatter and a hit can overlap; one player would eat the other

var run: RunState
var screen: Control
var fight_panel: Control  ## the live fight.gd, so HP can be read back off it
var rng := RandomNumberGenerator.new()
var pool: Array[String] = []  ## the hand chosen on the title screen
var music: AudioStreamPlayer
var _tracks: Dictionary = {}  ## source stream -> its loop-enabled copy
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _mute_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = T.build()
	rng.randomize()
	add_child(T.backdrop())
	for src in [MUSIC_MENU, MUSIC_COMBAT]:
		var looped: AudioStreamOggVorbis = src.duplicate()
		looped.loop = true
		_tracks[src] = looped
	music = AudioStreamPlayer.new()
	music.stream = _tracks[MUSIC_MENU]
	music.volume_db = MUSIC_VOL
	add_child(music)
	music.play()
	# One-shots need no loop flag and no duplicate() copy -- the imported default
	# is already right, which is the only reason _tracks exists at all.
	for _i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	_mute_btn = _build_mute()
	_apply_mute()
	show_title()


## Fire a one-shot by name. `vol` is an offset in dB, for the same sound played
## at two weights (a full roll against a quieter re-roll). Round-robins the pool
## so an overlapping sting is not cut off by the click that follows it.
func play_sfx(name: String, vol: float = 0.0) -> void:
	var s = SFX.get(name)
	if s == null:
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = s
	p.volume_db = SFX_VOL + vol
	p.play()


## The sound toggle. Built once on the root rather than per screen, so it
## survives every _swap and no screen builder has to know about it. Top-right,
## because the depth strip's pips are centred and leave roughly 150px of margin
## at each end -- see the two prior layout regressions in BALANCE.md's sibling
## notes; this corner is the one place the fight screen does not use.
func _build_mute() -> Button:
	var b := Button.new()
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.custom_minimum_size = Vector2(64, 34)
	b.offset_left = -74
	b.offset_top = 10
	b.offset_right = -10
	b.offset_bottom = 44
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", T.F_TINY)
	b.pressed.connect(_on_mute_pressed)
	add_child(b)
	return b


## Apply the saved preference to the bus and the button. Called at boot so a
## player who muted last launch is not ambushed by the menu music.
func _apply_mute() -> void:
	var want := bool(RunState.load_stats()["muted"])
	AudioServer.set_bus_mute(0, want)
	_mute_btn.text = "MUTED" if want else "SOUND"
	_mute_btn.add_theme_color_override("font_color", T.FAINT if want else T.GOLD)
	_mute_btn.tooltip_text = "Turn sound on" if want else "Mute sound"


func _on_mute_pressed() -> void:
	RunState.set_muted(not bool(RunState.load_stats()["muted"]))
	_apply_mute()




## Swap the bed, then fade up. There is one player, so there is nothing to
## crossfade against -- ducking first only added a half-second window where the
## state was mid-change and untestable. Swapping at -40 dB and rising covers the
## cut and leaves the change observable the moment the screen does.
func _music_to(src: AudioStreamOggVorbis) -> void:
	if music.stream == _tracks[src]:
		return
	music.stream = _tracks[src]
	music.play()
	music.volume_db = -40.0
	var tw := create_tween()
	tw.tween_property(music, "volume_db", MUSIC_VOL, MUSIC_FADE)



# --- screen plumbing ---

func _swap(next: Control, music_src: AudioStreamOggVorbis = MUSIC_MENU) -> void:
	if screen != null:
		remove_child(screen)
		screen.queue_free()
	screen = next
	add_child(screen)
	# The mute button is a root sibling added before the first screen, so every
	# swap pushes the new screen over it. Lift it back, or it vanishes on the
	# title and comes back on the fight.
	if _mute_btn != null:
		move_child(_mute_btn, get_child_count() - 1)
	fight_panel = null
	_music_to(music_src)


## A full-screen column. The backdrop already lives on the root, so this is just
## margins and a vertical box.
func _column(top: int = 24, bottom: int = 24) -> VBoxContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_bottom", bottom)
	_swap(m)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	m.add_child(col)
	return col


func _label(parent: Node, text: String, size: int, colour: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


# --- screens ---

## Rebuild the title screen. `reseed` re-reads the saved hand, so it is off when
## this is just redrawing after a tap -- otherwise the pick is wiped before it
## is ever drawn.
func show_title(reseed: bool = true) -> void:
	run = null
	if reseed:
		_seed_pool()
	var stats := RunState.load_stats()
	var col := _column(20, 20)

	col.add_child(_spacer(16))
	_label(col, "DICE FATE", T.F_DISPLAY + 8, T.GOLD)
	_label(col, "Nine fights. One pool of dice. Take what you can.", T.F_SMALL, T.MUTED)

	# --- the hand picker ---
	var head := HBoxContainer.new()
	col.add_child(_spacer(10))
	col.add_child(head)
	var hand_l := _label(head, "YOUR HAND", T.F_TINY, T.FAINT, HORIZONTAL_ALIGNMENT_LEFT)
	hand_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(head, "%d / %d" % [pool.size(), RunState.POOL_SIZE], T.F_TINY,
		T.PICK if pool.size() == RunState.POOL_SIZE else T.GOLD,
		HORIZONTAL_ALIGNMENT_RIGHT)

	# Rows of four, each centred, not a GridContainer. Seven does not divide by
	# four, and a grid left-aligns its short last row -- which left an empty cell
	# in the bottom-right corner that read as a rendering hole rather than a gap.
	# The chips are a fixed width to make that centring possible: ALIGNMENT_CENTER
	# only centres a row whose children stop short of it, and SIZE_EXPAND_FILL
	# hands all the width to a 3-die row and leaves it flush left again.
	var chip := maxi((int(get_viewport_rect().size.x) - 64) / 4, 60)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	col.add_child(grid)
	var owned: Array = RunState.owned_titles()
	var cat := _catalogue()
	for i in range(0, cat.size(), 4):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		for d in cat.slice(i, i + 4):
			row.add_child(_die_chip(d, pool.has(d.title), owned.has(d.title), chip))
		grid.add_child(row)

	# --- the record, then the two ways in ---
	col.add_child(_spacer(14))
	_label(col, "BEST RUN", T.F_TINY, T.FAINT)
	_label(col, _best_line(stats), T.F_TITLE, T.TEXT if int(stats["best_depth"]) > 0 else T.MUTED)
	_label(col, "%d runs   ·   %d victories" % [int(stats["runs"]), int(stats["wins"])],
		T.F_SMALL, T.MUTED)

	col.add_child(_spacer(18))
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	var daily := T.secondary_button("DAILY RUN   ·   #%d" % RunState.today())
	daily.pressed.connect(_on_daily)
	btns.add_child(daily)
	var play := T.primary_button("Play" if int(stats["runs"]) > 0 else "Begin the run")
	play.pressed.connect(_on_play)
	btns.add_child(play)


## Every die that could ever be in hand -- the four starters plus the three a
## finished run unlocks. Locked ones are shown so the next run has a visible
## goal; `Run.owned_titles()` decides which are actually takeable.
func _catalogue() -> Array:
	var out: Array = Rules.Encounter.library()
	out.append_array(Rules.Encounter.bonus_dice())
	return out


## The hand to start from. A throwaway Run applies `set_loadout`'s own rules
## (skip what you do not own, trim and top up to a full hand), so the picker
## can never offer something the next run would silently refuse.
func _seed_pool() -> void:
	pool.clear()
	for d in RunState.new().dice:
		pool.append(d.title)


## One die in the picker: its best face, and whether it is in hand, benched, or
## still locked. Shaped like the fight card so the two read as the same object.
func _die_chip(d: Rules.Die, held: bool, owned: bool, width: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 88)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.pressed.connect(_on_die_picked.bind(d.title))

	var best: Rules.Face = d.faces[0]
	for f in d.faces:
		if f.worth() > best.worth():
			best = f
	var value := maxi(maxi(best.dmg, best.block), best.rerolls)
	var tint := T.face_colour(best.dmg, best.block, best.rerolls)

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_top = 8
	stack.offset_bottom = -8
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 1)
	b.add_child(stack)

	# MUTED, not FAINT, for the same reason as the die card: this is the die's
	# name, the one thing the row has to communicate. 4.70:1 on the card, against
	# FAINT's 2.44:1. The LOCKED caption and border below it keep FAINT -- those
	# are meant to recede.
	var name_l := _label(stack, d.title.to_upper(), T.F_TINY, T.MUTED)
	var value_l := _label(stack, str(value) if value > 0 else "--", T.F_TITLE, tint)
	value_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	value_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Owned-but-benched is the state worth inviting: tap to swap it in.
	var state := "LOCKED" if not owned else ("IN HAND" if held else "BENCHED")
	_label(stack, state, T.F_TINY, T.PICK if held else (T.MUTED if owned else T.FAINT))

	# The border carries the same three states, so the row reads at a glance.
	# A locked die still has to read as a goal, not a gap: FAINT keeps the edge
	# off the backdrop, and it is disabled so the tap does not silently no-op.
	var edge := T.PICK if held else (T.BORDER if owned else T.FAINT)
	var style := T.flat(T.CARD_HI if held else T.CARD, edge, 2 if held else 1, T.RADIUS)
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("pressed", style)
	b.add_theme_stylebox_override("hover",
		T.flat(T.CARD_HI, T.GOLD if owned else T.FAINT, 2, T.RADIUS))
	if not owned:
		b.disabled = true
		b.add_theme_stylebox_override("disabled", style)  ## keep the goal, drop the press
		name_l.modulate = Color(1, 1, 1, 0.6)
		value_l.modulate = Color(1, 1, 1, 0.6)
	return b


## Tap to swap a die in or out of the hand. Tapping the last held die leaves the
## hand short -- `set_loadout` tops it back up when the run actually starts, so
## this stays a pure preview of the choice.
func _on_die_picked(title: String) -> void:
	if pool.has(title):
		pool.erase(title)
	elif pool.size() < RunState.POOL_SIZE:
		pool.append(title)
	show_title(false)



func _best_line(stats: Dictionary) -> String:
	var best := int(stats["best_depth"])
	if best <= 0:
		return "no run yet"
	if int(stats["wins"]) > 0:
		return "the Devourer has fallen"
	return "depth %d of %d" % [best, RunState.FINAL_DEPTH + 1]


func show_fight() -> void:
	# The only screen not built by _column(), so it sets its own insets. Without
	# the top margin the depth strip renders against row 0, under the notch on a
	# phone that draws edge to edge. Top only -- the panel brings its own 16.
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_top", 20)
	_swap(m, MUSIC_COMBAT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)

	col.add_child(_depth_strip(run.depth))
	var panel = Fight.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Handed the sound owner rather than reaching for it: the panel is nested two
	# containers down (root > MarginContainer > VBoxContainer > panel), and a
	# get_parent() walk would break the day either screen is re-laid-out.
	panel.audio = self
	col.add_child(panel)
	fight_panel = panel
	panel.fight_won.connect(_on_fight_won)
	panel.fight_lost.connect(_on_fight_lost)
	panel.start(run.start_fight())


## One pip per fight: how much of the run is behind you, and where the boss
## sits. A daily also says so, because the number it shares is the point.
func _depth_strip(depth: int) -> Control:
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 7)

	if run.is_daily():
		var tag := PanelContainer.new()
		tag.add_theme_stylebox_override("panel", T.padded(T.PANEL, T.GOLD_DARK, 1, 6, 8))
		tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := Label.new()
		l.text = "DAILY RUN  #%d" % run.seed
		l.add_theme_font_size_override("font_size", T.F_TINY)
		l.add_theme_color_override("font_color", T.GOLD)
		tag.add_child(l)
		stack.add_child(tag)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	for i in RunState.FINAL_DEPTH + 1:
		var boss := i == RunState.FINAL_DEPTH
		var pip := ColorRect.new()
		pip.color = T.GOLD if i <= depth else (T.DMG if boss else T.CARD)
		pip.custom_minimum_size = Vector2(30 if boss else 16, 6)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pip)
	stack.add_child(row)
	return stack


func show_reward(offers: Array) -> void:
	var col := _column(40, 40)
	_label(col, "VICTORY", T.F_TINY, T.FAINT)
	_label(col, "Take one", T.F_DISPLAY, T.GOLD)
	_label(col, "depth %d of %d" % [run.depth + 1, RunState.FINAL_DEPTH + 1],
		T.F_SMALL, T.MUTED)
	col.add_child(_spacer(16))

	for o in offers:
		col.add_child(_reward_card(o))


func _reward_card(o: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 100)
	b.add_theme_stylebox_override("normal", T.flat(T.CARD, T.BORDER, 1, T.RADIUS))
	b.add_theme_stylebox_override("hover", T.flat(T.CARD_HI, T.GOLD, 2, T.RADIUS))
	b.add_theme_stylebox_override("pressed", T.flat(T.CARD_HI, T.GOLD_DARK, 2, T.RADIUS))
	b.pressed.connect(_on_reward_chosen.bind(str(o["id"])))

	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 18
	stack.offset_right = -18
	stack.offset_top = 14
	stack.offset_bottom = -14
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 4)
	b.add_child(stack)

	_label(stack, str(o["name"]), T.F_TITLE, T.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_label(stack, str(o["desc"]), T.F_SMALL, T.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	return b


## Both endings share a shape: headline, a run summary, one button out.
func show_end(victory: bool, is_best: bool) -> void:
	var reached := mini(run.depth + 1, RunState.FINAL_DEPTH + 1)
	var col := _column(48, 40)

	col.add_child(_spacer(50))
	_label(col, "THE DEVOURER FALLS" if victory else "YOU FALL",
		T.F_DISPLAY, T.GOLD if victory else T.DMG)
	col.add_child(_spacer(8))

	if victory:
		_label(col, "The run is complete. %d upgrades carried you through." % run.upgrades.size(),
			T.F_BODY, T.MUTED)
	elif is_best:
		_label(col, "A NEW BEST RUN", T.F_BODY, T.GOLD)
		_label(col, "You died deeper than ever before. That counts.", T.F_SMALL, T.MUTED)
	else:
		_label(col, "You reached depth %d of %d." % [reached, RunState.FINAL_DEPTH + 1],
			T.F_BODY, T.MUTED)
		_label(col, "The Devourer waits at depth %d." % RunState.FINAL_DEPTH,
			T.F_SMALL, T.MUTED)

	col.add_child(_spacer(20))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", T.padded(T.PANEL, T.BORDER))
	col.add_child(card)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	card.add_child(inner)
	_label(inner, "%d upgrades   ·   %d dice   ·   %d/%d hp" % [
		run.upgrades.size(), run.dice.size(), run.hp, run.max_hp],
		T.F_SMALL, T.TEXT)
	_label(inner, "   ·   ".join(_upgrade_names()) if not run.upgrades.is_empty()
		else "No upgrades taken.", T.F_TINY, T.FAINT)

	col.add_child(_spacer(24))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	col.add_child(btns)
	var share := T.secondary_button("Copy result")
	share.name = "Share"
	share.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share.pressed.connect(_on_share.bind(reached, victory, share))
	btns.add_child(share)
	var again := T.primary_button("Run again")
	again.size_flags_stretch_ratio = 1.4
	again.pressed.connect(show_title)
	btns.add_child(again)


# --- flow ---

func _on_play() -> void:
	_start(0)


func _on_daily() -> void:
	_start(RunState.today())


## Both entry points. A daily re-seeds `rng` off the day so the upgrade offers
## are the same for everyone too -- the run has to be the same run, not just
## the same enemies.
func _start(seed_value: int) -> void:
	run = RunState.new(seed_value)
	run.set_loadout(pool)
	if seed_value != 0:
		rng.seed = seed_value
	show_fight()



## The fight owns its encounter, so the surviving HP is read back off it.
func _absorb_fight() -> void:
	if fight_panel != null and fight_panel.enc != null:
		run.absorb(fight_panel.enc)


func _on_reward_chosen(id: String) -> void:
	run.apply_upgrade(id, rng)
	run.depth += 1
	show_fight()


func _on_fight_won() -> void:
	_absorb_fight()
	if run.at_boss():
		run.won = true
		play_sfx("win")
		show_end(true, RunState.record_run(RunState.FINAL_DEPTH + 1, true, pool))
		return
	show_reward(run.roll_rewards(rng))


func _on_fight_lost() -> void:
	_absorb_fight()
	var reached := mini(run.depth + 1, RunState.FINAL_DEPTH + 1)
	play_sfx("lose")
	show_end(false, RunState.record_run(reached, false, pool))


## Puts the three-line result on the clipboard. The clipboard is the whole share
## story -- no plugin, no account, and it works on Android -- so the button says
## "copy" rather than pretending something left the device.
func _on_share(reached: int, victory: bool, btn: Button) -> void:
	DisplayServer.clipboard_set(run.share_text(reached, victory))
	btn.text = "COPIED"
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, T.PICK)
	await get_tree().create_timer(1.5).timeout
	if not is_instance_valid(btn):  ## the run may have ended again by now
		return
	btn.text = "Copy result"
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, T.GOLD)


# --- small helpers over run data ---

func _upgrade_names() -> Array:
	var out: Array = []
	for id in run.upgrades:
		out.append(str(RunState.upgrade_by_id(id)["name"]))
	return out
