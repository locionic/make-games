extends Control
## The combat panel: one fight against one enemy. All rules live in dice.gd;
## this file only draws them and turns taps into the calls dice.gd exposes.
##
## It is a plain Control, not a Container, so `shake` can move the whole panel
## without a parent Container re-laying it out. It emits fight_won / fight_lost
## and lets game.gd decide what comes next.

const Rules = preload("res://dice.gd")
const T = preload("res://theme.gd")

signal fight_won
signal fight_lost

var enc: Rules.Encounter
var rng := RandomNumberGenerator.new()
var has_rolled := false
var busy := false  ## true while the roll animation owns the cards
## The game root, which owns the music, the effect pool and the one mute button.
## Untyped because game.gd preloads this -- naming the type would be a cycle.
var audio: Node

var shake_root: MarginContainer
var enemy_sigil: Control
var enemy_name: Label
var enemy_tag: Label
var enemy_bar: ProgressBar
var enemy_num: Label
var best_box: HBoxContainer
var best_cap: Label
var best_num: Label
var intent_num: Label
var dice_row: HBoxContainer
var player_bar: ProgressBar
var player_num: Label
var hud_label: Label
var ticker: Label
var roll_btn: Button
var reroll_btn: Button
var end_btn: Button
var focus_btn: Button
var bank_btn: Button
var focus_armed := false  ## next card press focuses instead of queueing a re-roll
var bank_armed := false   ## next card press holds the die instead -- mutually
## exclusive with focus_armed: both are "spend a resource on one die", and two
## armed modes at once is a menu nobody can hold in their head at arm's length.
var _mode_line := false   ## the ticker is showing a mode prompt, not a log line

## A card that is out of play this turn -- re-rolled already, or held in the
## bank. Both are "does not count", so both fade the same way.
const SPENT_DIM := Color(0.5, 0.5, 0.55)
var banner: Label

var cards: Array[Button] = []
var name_labels: Array[Label] = []
var value_labels: Array[Label] = []
var effect_labels: Array[Label] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	rng.randomize()
	_build_ui()


func start(e: Rules.Encounter) -> void:
	enc = e
	has_rolled = false
	busy = false
	_ensure_cards()
	_refresh()


# --- construction ---

func _build_ui() -> void:
	add_child(T.backdrop())

	shake_root = MarginContainer.new()
	shake_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		shake_root.add_theme_constant_override("margin_" + side, 16)
	add_child(shake_root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	shake_root.add_child(col)

	# The enemy is a shape before it is a stat line. Five behaviours get five
	# silhouettes, sized by health -- so the Devourer is the largest thing on
	# the board and a Grunt is a dot, without reading a single number. It is the
	# only control here that stretches, so it takes all the leftover height --
	# which is the whole enemy, not a share of it.
	enemy_sigil = Control.new()
	enemy_sigil.custom_minimum_size = Vector2(0, 132)
	enemy_sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_sigil.size_flags_vertical = Control.SIZE_EXPAND_FILL
	enemy_sigil.draw.connect(_draw_sigil)
	col.add_child(enemy_sigil)

	enemy_name = Label.new()
	enemy_name.add_theme_font_size_override("font_size", T.F_TITLE)
	col.add_child(enemy_name)

	# The tag recedes to the smallest size on screen: the name and the shape
	# carry the enemy, the tag only explains it.
	enemy_tag = Label.new()
	enemy_tag.add_theme_font_size_override("font_size", T.F_TINY)
	enemy_tag.add_theme_color_override("font_color", T.MUTED)
	col.add_child(enemy_tag)

	# No spacer between the tag and the bar on purpose. Sharing the leftover
	# height with a blank control put 123px of nothing in the middle of the
	# screen and left the enemy a small shape adrift in the top third. Letting
	# the sigil take all of it grows the enemy and closes the gap at once, and
	# the buttons still land at the bottom because the sigil eats the slack.
	enemy_bar = _make_bar(T.DMG)
	enemy_num = _bar_number(enemy_bar)
	col.add_child(enemy_bar)

	# The enemy's damage is the number every decision hangs on -- push it or
	# block it -- and nothing else on screen says it. It goes in the gap under
	# the bar, big enough to read at a glance, rather than as another 12px tag
	# on the name row. Read live, not once: ENRAGE raises it every turn.
	var intent_box := VBoxContainer.new()
	intent_box.add_theme_constant_override("separation", 0)
	intent_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(intent_box)
	var cap := Label.new()
	cap.text = "INCOMING"
	cap.add_theme_font_size_override("font_size", T.F_TINY)
	cap.add_theme_color_override("font_color", T.FAINT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_box.add_child(cap)
	intent_num = Label.new()
	intent_num.add_theme_font_size_override("font_size", T.F_DISPLAY)
	intent_num.add_theme_color_override("font_color", T.DMG)
	intent_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent_box.add_child(intent_num)

	# The answer to the enemy's armour, and the mirror of the telegraph above.
	# Nobody is told that a 2 into 4 armour deals nothing, so a new player's
	# first fight reads as a broken game rather than a small hit that was
	# absorbed. This says it before they commit, and it says it again every
	# turn because the dice move. Sits with the dice, not the enemy: it is the
	# roll's output, not the enemy's stats.
	best_box = HBoxContainer.new()
	best_box.alignment = BoxContainer.ALIGNMENT_CENTER
	best_box.add_theme_constant_override("separation", 8)
	best_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(best_box)
	best_cap = Label.new()
	best_cap.add_theme_font_size_override("font_size", T.F_TINY)
	best_cap.add_theme_color_override("font_color", T.FAINT)
	best_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_box.add_child(best_cap)
	best_num = Label.new()
	best_num.add_theme_font_size_override("font_size", T.F_TITLE)
	best_box.add_child(best_num)

	# The dice get a fixed, card-shaped height. Letting them eat the whole column
	# made 125x230 posters with the number marooned in the middle; the slack goes
	# to the enemy instead, which is the thing worth looking at.
	dice_row = HBoxContainer.new()
	dice_row.add_theme_constant_override("separation", 7)
	dice_row.custom_minimum_size = Vector2(0, 186)
	dice_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_child(dice_row)

	# Green, not red: T.HP and T.DMG are within a hair of each other, so a red
	# player bar under a red enemy bar read as one bar split in two.
	player_bar = _make_bar(T.ALLY)
	player_num = _bar_number(player_bar)
	col.add_child(player_bar)

	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", T.F_SMALL)
	hud_label.add_theme_color_override("font_color", T.MUTED)
	col.add_child(hud_label)

	# One line, not a console. The rules layer narrates every exchange; the
	# screen only needs the most recent beat. The 80px this gives back go to
	# the dice, which are the point of the screen.
	ticker = Label.new()
	ticker.add_theme_font_size_override("font_size", T.F_TINY)
	ticker.add_theme_color_override("font_color", T.FAINT)
	ticker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticker.clip_text = true
	col.add_child(ticker)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	col.add_child(btns)
	roll_btn = _mk_button(btns, "Roll", T.GOLD)
	roll_btn.pressed.connect(_on_roll)
	# Focus and Bank are modes, not targets: press one, then tap the die. Reusing
	# the card press keeps the turn at one tap per action. They do not need a
	# second row -- they are mutually exclusive, and neither button grows when
	# armed, so the "tap a die" half of the label goes to the ticker line where
	# the other teaching line already lives. Five across 508px is 96px each,
	# which the labels below fit; that is checked, not assumed.
	focus_btn = _mk_button(btns, "Focus", T.PICK)
	focus_btn.pressed.connect(_on_focus_pressed)
	bank_btn = _mk_button(btns, "Bank", T.BLOCK)
	bank_btn.pressed.connect(_on_bank_pressed)
	reroll_btn = _mk_button(btns, "Re-roll", T.REROLL)
	reroll_btn.pressed.connect(_on_reroll)
	end_btn = _mk_button(btns, "End turn", T.DMG)
	end_btn.pressed.connect(_on_end_turn)


## The enemy, drawn. Nothing here is decoration: the silhouette is how you tell
## a Bloodletter from a Hexweaver without reading the tag, and the radius is
## health, so the boss is unmistakable in a screenshot.
func _draw_sigil() -> void:
	if enc == null:  ## the first layout pass happens before start()
		return
	var e := enc.enemy
	var r: float = enemy_sigil.size.y * 0.5 * clampf(0.5 + e.max_hp / 150.0, 0.6, 0.78)
	var at := enemy_sigil.size / 2.0

	var sides := 6
	var rot := 0.0
	match e.behavior:
		Rules.Enemy.BEH_ARMOR_GROW: rot = PI / 6.0  ## flat-topped: it is plating up
		Rules.Enemy.BEH_LIFESTEAL:
			sides = 3
			rot = PI  ## a downward point
		Rules.Enemy.BEH_CURSE:
			sides = 5
			rot = -PI / 2.0  ## the warding star
		Rules.Enemy.BEH_ENRAGE:
			sides = 8
			rot = PI / 8.0  ## all spikes, no flat side

	var pts := PackedVector2Array()
	for i in sides:
		var a := rot + TAU * float(i) / float(sides)
		pts.append(at + Vector2(cos(a), sin(a)) * r)

	var boss: bool = e.max_hp > 60
	var edge: Color = T.GOLD if boss else T.DMG

	# The panel is the largest thing on the fight screen and it was showing
	# nothing about the fight -- the enemy read as one flat outline. Armour is
	# the stat a player most needs to see and least often does: it only ever
	# appeared in a log line, and ARMOR_GROW raises it every turn. One tick per
	# point, so the ring visibly thickens as a golem plates up.
	var reach: float = minf(enemy_sigil.size.x, enemy_sigil.size.y) * 0.5 - 8.0
	if boss:
		enemy_sigil.draw_arc(at, minf(r * 1.5, reach), 0.0, TAU, 48, T.GOLD, 1.5)
	if e.armor > 0:
		var tr: float = minf(r * 1.3, reach)
		var step: float = TAU / float(Rules.Enemy.ARMOR_GROW_CAP)
		for i in mini(e.armor, Rules.Enemy.ARMOR_GROW_CAP):
			var a := rot + step * (float(i) + 0.5)
			var d := Vector2(cos(a), sin(a))
			enemy_sigil.draw_line(at + d * (tr - 9.0), at + d * tr, T.BLOCK, 3.0)

	# A translucent wash of the edge colour, so the shape reads as a mass and not
	# a smudge: PANEL on the backdrop is invisible at this size.
	enemy_sigil.draw_colored_polygon(pts, Color(edge.r, edge.g, edge.b, 0.22))

	# A second body turned half a step and scaled in, so the mass has a depth
	# instead of reading as one outline. Behaviour already rotates the outer
	# shape, so the two never line up for every enemy.
	var inner := PackedVector2Array()
	for i in sides:
		var a := rot + TAU * (float(i) + 0.5) / float(sides)
		inner.append(at + Vector2(cos(a), sin(a)) * r * 0.62)
	enemy_sigil.draw_colored_polygon(inner, Color(edge.r, edge.g, edge.b, 0.14))

	var loop := pts
	loop.append(pts[0])  ## polyline does not close itself
	enemy_sigil.draw_polyline(loop, edge, 3.0)
	enemy_sigil.draw_circle(at, r * 0.3, edge)
	enemy_sigil.draw_arc(at, r * 0.34, 0.0, TAU, 40, Color(edge.r, edge.g, edge.b, 0.7), 2.0)


## A bar that carries its own numbers. The two bars sit one above the other with
## the enemy in between, so the count has to live on the bar it describes --
## buried in the HUD line at the bottom of the screen, it is unreadable.
func _make_bar(fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 22)
	b.show_percentage = false
	b.add_theme_stylebox_override("background", T.flat(T.PANEL, T.BORDER, 1, 6))
	b.add_theme_stylebox_override("fill", T.flat(fill, fill, 0, 6))
	return b


func _bar_number(bar: ProgressBar) -> Label:
	var n := Label.new()
	n.add_theme_font_size_override("font_size", T.F_TINY)
	n.add_theme_color_override("font_color", T.TEXT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(n)
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	return n


func _mk_button(parent: Node, text: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 74 canvas units tall, not 54. The canvas is 540 wide and never shrinks --
	# `canvas_items` + `expand` scales the whole thing to the window -- so a unit
	# is one dp only on a 540dp phone. Measured with `shot.gd --check --at N`,
	# which is the gate that found it: at 54 the button row was 36dp tall on a
	# 360dp phone, 12dp under the 48dp floor, and the same at every width.
	# Sized the other way round, off a number that means something: 74 units is
	# 56dp on a 411dp phone, which is the comfortable target Material asks for
	# and not just the minimum, and that clears 48dp on a 360dp one too.
	b.custom_minimum_size = Vector2(0, 74)
	b.add_theme_font_size_override("font_size", T.F_BODY)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", T.TEXT)
	b.add_theme_color_override("font_pressed_color", T.TEXT)
	b.add_theme_color_override("font_disabled_color", T.FAINT)
	parent.add_child(b)
	return b


## One card per die. Cards are Buttons so touch, hover and focus all come free.
func _ensure_cards() -> void:
	while cards.size() < enc.dice.size():
		var i := cards.size()
		cards.append(_make_card())
		name_labels.append(null)
		value_labels.append(null)
		effect_labels.append(null)
		_build_card_face(i)
		cards[i].pressed.connect(_on_card_pressed.bind(i))
	while cards.size() > enc.dice.size():
		var i := cards.size() - 1
		dice_row.remove_child(cards[i])
		cards[i].queue_free()
		cards.pop_back()
		name_labels.pop_back()
		value_labels.pop_back()
		effect_labels.pop_back()


func _make_card() -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	dice_row.add_child(b)
	return b


func _build_card_face(i: int) -> void:
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 4
	stack.offset_right = -4
	stack.offset_top = 10
	stack.offset_bottom = -10
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 2)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	cards[i].add_child(stack)

	# MUTED, not FAINT: the die's name is its identity across a run, not a
	# de-emphasised tag. FAINT measured 2.44:1 on the card -- under the 4.5:1 of
	# WCAG 2.2 SC 1.4.3 -- and left "BLADE" dimmer than the "2 DAMAGE" beneath
	# it. The name still recedes: dominance is carried by the 40px number, not
	# by fading the text. FAINT stays for what is meant to disappear (a locked
	# die, a cursed face reading "--", a disabled button).
	name_labels[i] = _card_label(stack, T.F_TINY, T.MUTED)
	value_labels[i] = _card_label(stack, T.F_DISPLAY, T.TEXT)
	value_labels[i].size_flags_vertical = Control.SIZE_EXPAND_FILL
	value_labels[i].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	effect_labels[i] = _card_label(stack, T.F_TINY, T.MUTED)


func _card_label(parent: Node, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	parent.add_child(l)
	return l


# --- input ---

## Sound is owned by the root -- one pool, one mute path -- so the fight only
## names what happened. Every call is guarded by the same delta that drives the
## shake and the bar, so a sound can never fire for a roll that did nothing.
func _sfx(name: String, vol: float = 0.0) -> void:
	audio.play_sfx(name, vol)


func _on_roll() -> void:
	if busy or has_rolled or enc.over:
		return
	_sfx("roll")
	enc.roll_all(rng)
	has_rolled = true
	_drain_log()
	_refresh()
	_spin()


func _on_card_pressed(i: int) -> void:
	if busy or not has_rolled:
		return
	if focus_armed:
		# Spend the charge here and only here, so a mis-tap costs a die's action
		# rather than the whole turn's budget.
		if not enc.focus_die(i):
			return
		focus_armed = false
		_sfx("block", 2.0)
		_drain_log()
		_refresh()
		_nudge_flash(i)
		return
	if bank_armed:
		# Bank is reversible, so a mis-tap here costs nothing -- the mode stays
		# armed and a second tap on the same card puts the die back.
		enc.toggle_bank(i)
		bank_armed = false
		_sfx("tap", 3.0)
		_drain_log()
		_refresh()
		return
	enc.toggle_pick(i)
	_sfx("tap")
	_refresh()


## Focus arms the next card press. Tapping the button twice cancels, so a player
## who changed their mind does not have to reach for a disabled control.
func _on_focus_pressed() -> void:
	if busy or not has_rolled or enc.focus_left <= 0:
		return
	focus_armed = not focus_armed
	bank_armed = false
	_sfx("tap", 3.0)
	_refresh()


## Bank arms the next card press, on the same terms as Focus. Arming one closes
## the other: they spend different resources on the same card, and a screen that
## can show both as armed is a screen asking the player to remember a state
## machine.
func _on_bank_pressed() -> void:
	if busy or not has_rolled:
		return
	bank_armed = not bank_armed
	focus_armed = false
	_sfx("tap", 3.0)
	_refresh()


func _on_reroll() -> void:
	if busy or not has_rolled or not enc.can_reroll():
		return
	# The same clatter, quieter: it is the same dice moving, on a smaller budget.
	_sfx("roll", -6.0)
	enc.resolve_rerolls(rng)
	_drain_log()
	_refresh()
	_reroll_spin()


func _on_end_turn() -> void:
	if busy or not has_rolled or enc.over:
		return
	var struck: int = enc.enemy.hp
	var before_block: int = enc.block
	var was_exposed: int = enc.enemy.exposed
	enc.resolve_faces()
	var dealt: int = struck - enc.enemy.hp
	if dealt > 0:
		_sfx("strike")
		shake(1.0)  ## the punch lands on the panel, not just the bar
		_flash_sigil()
		_float_text("-%d" % dealt, T.DMG, _anchor(enemy_sigil))
		_haptic(40 if dealt >= 10 else 20)
	if enc.last_deflected > 0:
		_float_text("%d deflected" % enc.last_deflected, T.MUTED,
			_anchor(enemy_sigil) + Vector2(0, 24), T.F_SMALL)
	if enc.block > before_block:
		_sfx("block")
		_float_text("+%d" % (enc.block - before_block), T.BLOCK, _anchor(player_bar))
	if enc.enemy.exposed > was_exposed:
		_float_text("EXPOSED", T.REROLL, _anchor(enemy_sigil) - Vector2(0, 28), T.F_SMALL)
	_drain_log()
	_refresh()

	if not enc.over:
		var before_hp: int = enc.hp
		enc.take_turn(rng)
		# Only the damage that got through the block you had banked. A full
		# block would otherwise thud exactly like a killing blow.
		if enc.hp < before_hp:
			_sfx("hurt")
			_float_text("-%d" % (before_hp - enc.hp), T.HP, _anchor(player_bar))
			_haptic(45)
		_drain_log()
		_refresh()

	if enc.over:
		busy = true
		_show_banner()
		await get_tree().create_timer(0.8).timeout
		if enc.won:
			fight_won.emit()
		else:
			fight_lost.emit()
		return

	has_rolled = false
	_refresh()


# --- presentation ---

func _log(s: String) -> void:
	if not s.is_empty():
		_say(s, T.FAINT, T.F_TINY)


## The ticker does double duty: the running log, and the one instruction an
## untouched fight gets. They are not the same thing -- an instruction nobody
## reads is the same as no instruction -- so the caller picks how loud it is.
## It cannot afford to be bigger, though: the button row is already flush to
## the bottom of the column, so a taller line would push it off the screen.
func _say(s: String, colour: Color, size: int) -> void:
	ticker.text = s
	ticker.add_theme_font_size_override("font_size", size)
	ticker.add_theme_color_override("font_color", colour)


## Gold while a mode is armed, its own accent otherwise. One place, because the
## two mode buttons are the only controls whose colour means a state rather than
## a kind of action, and they have to agree on what "armed" looks like.
func _mode_colour(b: Button, armed: bool, accent: Color) -> void:
	var c := T.GOLD if armed else accent
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c)


func _drain_log() -> void:
	for line in enc.log_lines:
		_log(line)
	enc.log_lines.clear()


## Flicker `idxs` through random faces, then settle them on the real roll.
## One function for the dealer's shuffle and the re-roll's clatter: the
## vocabulary is the same -- dice moving, faces changing -- so it is one piece
## of code with a different list and a shorter run, not two animations that
## drift apart the first time one of them is tuned.
func _flicker(idxs: Array[int], steps: int) -> void:
	busy = true
	_refresh()
	for _step in steps:
		for i in idxs:
			_paint_card(i, enc.dice[i].faces[rng.randi_range(0, 5)], false)
		await get_tree().create_timer(0.035).timeout
	for i in idxs:
		_paint_card(i, enc.dice[i].face(), true)
		var c := cards[i]
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(0.84, 0.84)
		var tw := create_tween()
		tw.tween_property(c, "scale", Vector2.ONE, 0.2)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	busy = false
	_refresh()


## The deal: every card, long enough to read as a throw onto the table.
func _spin() -> void:
	var all: Array[int] = []
	for i in cards.size():
		all.append(i)
	_flicker(all, 5)


## The re-roll's clatter. Only the dice that actually moved flicker -- `spent`
## is the rules layer's record of exactly those, and shaking the whole hand
## would tell the player four dice changed when one did.
func _reroll_spin() -> void:
	var moved: Array[int] = []
	for i in cards.size():
		if enc.dice[i].spent:
			moved.append(i)
	if moved.is_empty():
		return
	_flicker(moved, 3)


## The Focus spend's signature: gold, and it rises. A re-roll is a gamble and
## looks like one -- faces tumbling, a clatter, a card you could not predict. A
## nudge is the opposite trade, a charge spent for a *guaranteed* step, so it
## gets the opposite treatment: nothing tumbles, the card goes gold and lifts,
## and the player is told "this was certain" on the same channel that says "this
## was luck". PLAN.md 3.1, and the reason these are two functions and not one:
## a spend the player cannot predict must not be dressed as a spend they can.
func _nudge_flash(i: int) -> void:
	var c := cards[i]
	# Read the dim the refresh just set rather than assuming white. A focus
	# always spends the die, so the card is SPENT_DIM by now, and tweening back
	# to white would leave a spent die looking unspent until the next repaint.
	var rest: Color = c.modulate
	# Pivot on the bottom edge so the pop reads as lifting *out* of the row. A
	# centre pivot inflates in place, which is the re-roll's bounce -- the one
	# thing these two must not look alike.
	c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.1)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate", T.GOLD_LIGHT, 0.1)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(c, "modulate", rest, 0.18)
	# The rising tick, named "Tick" and not "Float" so the harness can tell a
	# certainty from a hit. A re-roll must never raise one of these, and that
	# is the only part of this claim a screenshot could catch.
	_float_text("FOCUS", T.GOLD, _anchor(c) - Vector2(0, c.size.y * 0.5),
		T.F_SMALL, "Tick")
	_haptic(12)


## Draw one card. `final` is false mid-spin, so a card shows a bare number rather
## than the state colouring of a locked-in result.
func _paint_card(i: int, f: Rules.Face, final: bool) -> void:
	var d: Rules.Die = enc.dice[i]
	# While Focus is armed the card previews the face you would get, not the one
	# you rolled. The charge is once a fight and never refunded, and the jumps are
	# enormous and uneven -- Sunder's "1" becomes a cleave 12, Blade's "7" only a
	# 9 -- so spending it without seeing the result is not a decision, it is a
	# guess dressed up as one.
	var target: Rules.Face = enc.focus_face(i) if final and focus_armed else null
	# A held die is dimmed and outlined green: green for "you chose this", dim for
	# "it is not counting", which is the whole of what banking does to a card.
	var held: bool = final and i == enc.banked
	var picked: bool = final and target == null and not held and enc.picks[i]
	var spent: bool = final and d.spent
	if target != null:
		f = target

	name_labels[i].text = d.title.to_upper()
	# Six cards across 540 leave about 55px of text room, which is not enough
	# for the longest titles -- the card clips them mid-word ("THOR", "RIPOST").
	# Step the name down when the row is at its widest so it still reads.
	name_labels[i].add_theme_font_size_override("font_size",
		T.F_TINY if cards.size() < 6 else T.F_TINY - 2)

	var has_value := f.dmg > 0 or f.block > 0 or f.rerolls > 0
	# A paired face deals `face_hit`, not `f.dmg`, and the card has to say so.
	# Only on a settled card: mid-spin the face is a random one, and a focus
	# preview is a face the die could be moved to, and neither has a partner to
	# read. The doubling is visible as a number the die does not have a face for,
	# which teaches the rule by showing it rather than by a "5x2" the player has
	# to decode.
	var hit: int = f.dmg
	if final and target == null:
		hit = enc.face_hit(i)
	var value := maxi(maxi(hit, f.block), f.rerolls)
	value_labels[i].text = str(value) if has_value else "--"

	var colour := T.face_colour(f.dmg, f.block, f.rerolls)
	if target != null:
		colour = T.GOLD
	elif picked:
		colour = T.PICK
	elif not has_value:
		colour = T.FAINT
	value_labels[i].add_theme_color_override("font_color", colour)

	# The face's own word -- "cleave", "rend", "fend" -- is the interesting half
	# of a face, so it rides along whenever it is not just the number again.
	var kind := "--"
	if hit > 0:
		kind = "%d DAMAGE" % hit
	elif f.block > 0:
		kind = "%d BLOCK" % f.block
	elif f.rerolls > 0:
		kind = "+%d RE-ROLL" % f.rerolls
	# The face's own word, unless it is now the same number the card already
	# shows big -- a paired face's label is its *un*doubled number, so printing
	# it would put "10" over "5" and the smaller one would be the lie.
	var shown: String = f.label
	if hit != f.dmg:
		shown = str(hit)
	effect_labels[i].text = shown if shown != str(value) else kind
	if held:
		effect_labels[i].text = "HELD"
	effect_labels[i].add_theme_color_override("font_color",
		T.GOLD if target != null else (T.PICK if held else (T.TEXT if picked else T.MUTED)))

	var style := T.card_style(f.dmg, f.block, f.rerolls, picked, spent)
	# A focusable card is outlined gold while the mode is armed, and one that is
	# already on its best face is not outlined at all -- otherwise the player
	# taps, nothing happens, and the button just flashes. A maxed die cannot be
	# focused, so the UI has to say so before the tap, not after.
	if target != null or held:
		style = T.flat(T.CARD_HI, T.GOLD if target != null else T.PICK, 2, T.RADIUS)
		style.border_width_left = 3
		style.border_width_right = 3
	cards[i].add_theme_stylebox_override("normal", style)
	cards[i].add_theme_stylebox_override("pressed", style)
	cards[i].add_theme_stylebox_override("hover",
		T.flat(T.CARD_HI, T.PICK if final else colour, 2, T.RADIUS))
	cards[i].modulate = SPENT_DIM if (spent or held) else Color.WHITE


## A short punch, so a big hit registers before the screen changes.
func shake(power: float = 1.0) -> void:
	var tw := create_tween()
	for _i in 4:
		tw.tween_property(shake_root, "position",
			Vector2(rng.randf_range(-7, 7), rng.randf_range(-4, 4)) * power, 0.04)
	tw.tween_property(shake_root, "position", Vector2.ZERO, 0.06)


## Phase 3.2: the number where it lands, instead of a log line asking the player
## to read it. The label owns itself -- nothing holds a reference and nothing
## has to free it, so a fight that ends mid-float takes the label with it and
## leaves no orphan on the card.
func _float_text(txt: String, col: Color, at: Vector2, size: int = T.F_TITLE,
		tag: String = "Float") -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# An outline, because these land over the panel and the sigil alike and a
	# red number on a dark card is otherwise unreadable at a glance.
	l.add_theme_color_override("font_outline_color", T.BG)
	l.add_theme_constant_override("outline_size", 4)
	l.z_index = 50
	# Named so the screenshot harness can count them. The floats live under a
	# second of tween and a screenshot of the idle fight screen never catches one,
	# so "the juice renders" is otherwise unobservable -- and a regression that
	# stopped the numbers appearing would pass every gate. `tag` exists so a
	# certainty (a Focus tick) is not counted as a hit: they are the one pair of
	# effects that must never be confused for each other.
	l.name = tag
	# In a group as well, because the name alone cannot be counted with. A turn
	# throws up to four of these as siblings and add_child() keeps sibling names
	# unique, so only the first is ever called "Float" -- the rest come back as
	# "@Float@2", "@Float@3", and a find_children("Float") reports a turn of
	# perfectly good feedback as missing. The group is the tag that survives all
	# of them; the name stays because it is what a reader sees in the tree.
	l.add_to_group("float")
	add_child(l)
	# reset_size() is synchronous, so the half-width offset below is real and the
	# number is centred on its anchor rather than hanging off its top-left.
	l.reset_size()
	# The panel's inverse global transform, not the raw point. The panel sits
	# inside a MarginContainer and a VBoxContainer, so its local origin is nowhere
	# near (0,0) and a global point dropped straight into `position` lands in the
	# wrong place by however far down the screen the fight card happens to sit.
	#
	# Parented to the panel rather than to shake_root, which the sigil lives in,
	# so the float does not ride the punch. shake_root is a MarginContainer, and a
	# Container force-sets the rect of every direct child each layout pass -- which
	# is what parked the numbers against the panel corner. The punch is 7px for a
	# fifth of a second, so a number holding its ground while the card jitters
	# reads as the number landing on a target, not as a mismatch.
	l.position = get_global_transform().affine_inverse() * at \
		- Vector2(l.size.x * 0.5, 0.0)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 34.0, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.tween_callback(l.queue_free)


## Mid-point of a control, in the same space the float is placed in.
func _anchor(c: Control) -> Vector2:
	return c.global_position + c.size * 0.5


## A handset buzz for the hits worth feeling. Gated on the mobile feature so the
## desktop and web builds never call into it -- vibrate_handheld is a no-op off
## Android, but the intent is clearer than relying on that.
func _haptic(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


## The enemy flinches when a face lands. Same beat as `shake`, aimed at the
## thing that actually took the hit.
func _flash_sigil() -> void:
	enemy_sigil.modulate = Color(1, 1, 1, 0.45)
	create_tween().tween_property(enemy_sigil, "modulate", Color.WHITE, 0.25)


func _show_banner() -> void:
	banner = Label.new()
	banner.text = ("%s falls." % enc.enemy.title) if enc.won else "You fall."
	banner.add_theme_font_size_override("font_size", T.F_DISPLAY)
	banner.add_theme_color_override("font_color", T.GOLD if enc.won else T.DMG)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner.set_anchors_preset(Control.PRESET_FULL_RECT)

	banner.pivot_offset = size / 2.0
	banner.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	shake()


## A bar slides to its new value instead of snapping, and any drop pops the
## number that came off it -- so a big hit lands before the log scrolls.
func _set_bar(bar: ProgressBar, v: int) -> void:
	if int(bar.value) == v:
		return
	var lost: int = int(bar.value) - v
	create_tween().tween_property(bar, "value", v, 0.18)
	if lost > 0:
		_pop(bar, lost)


## A number that rises off a bar and fades. Anchored rather than positioned, so
## the tween moves it by its offsets and nothing can knock it sideways.
func _pop(bar: ProgressBar, amount: int) -> void:
	var l := Label.new()
	l.text = "-%d" % amount
	l.add_theme_font_size_override("font_size", T.F_TITLE)
	l.add_theme_color_override("font_color", T.DMG)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = -18
	l.offset_bottom = 6
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "offset_top", -46, 0.5)
	tw.tween_property(l, "offset_bottom", -22, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(l.queue_free)


func _refresh() -> void:
	if enc == null:
		return

	enemy_name.text = enc.enemy.title
	enemy_sigil.queue_redraw()
	var tag := enc.enemy.behavior_name()
	if enc.enemy.armor > 0:
		tag = ("%s   " % tag) if not tag.is_empty() else ""
		tag += "armour %d" % enc.enemy.armor
	# Exposed is the one tag that is not a fact about the enemy but a window the
	# player has to spend, so it goes in gold -- the colour everything else uses
	# for "this is live, act on it" -- instead of sharing the muted grey that a
	# permanent stat like armour wears. One turn is short enough that missing it
	# costs the whole card.
	if enc.enemy.exposed > 0:
		tag = ("%s   " % tag) if not tag.is_empty() else ""
		tag += "exposed"
	enemy_tag.text = tag.capitalize()
	enemy_tag.add_theme_color_override("font_color", T.GOLD if enc.enemy.exposed > 0 else T.MUTED)
	enemy_tag.visible = not tag.is_empty()

	enemy_bar.max_value = enc.enemy.max_hp
	_set_bar(enemy_bar, enc.enemy.hp)
	enemy_num.text = "%d / %d" % [enc.enemy.hp, enc.enemy.max_hp]
	intent_num.text = str(enc.enemy.atk)
	player_bar.max_value = enc.max_hp
	_set_bar(player_bar, enc.hp)
	player_num.text = "%d / %d" % [enc.hp, enc.max_hp]

	# The counts live on the bars now, so this line is only what they do not say.
	hud_label.text = "block %d     re-rolls %d     focus %d     turn %d" % [
		enc.block, enc.rerolls_left, enc.focus_left, enc.turn,
	]

	# The best any one die can land this turn, after armour. Armour applies per
	# die, so this is the whole strategy in one number: a pool of 2s reads 0
	# here, and re-rolling one of them into a 9 is the fight.
	var best := 0
	for d in enc.dice:
		best = maxi(best, enc.enemy.pierce(d.face().dmg, enc.pierce))
	best_num.text = str(best)
	best_num.add_theme_color_override("font_color", T.DMG if best > 0 else T.FAINT)
	# At zero the number alone is ambiguous -- it reads as "you did nothing this
	# turn", which is the opposite of what is true. Name the cause.
	best_cap.text = "BEST HIT" if best > 0 else "ARMOUR %d — NOTHING LANDS" % enc.enemy.armor
	best_cap.add_theme_color_override("font_color", T.FAINT if best > 0 else T.BLOCK)
	# The log only ever carries what just happened, so an untouched fight has
	# nothing in it -- and the first turn is exactly that. See the bottom of this
	# function, which is the one place that decides the ticker.

	for i in cards.size():
		_paint_card(i, enc.dice[i].face(), true)

	var free: bool = not enc.over and not busy
	roll_btn.disabled = not free or has_rolled
	reroll_btn.disabled = not free or not enc.can_reroll()
	end_btn.disabled = not free or not has_rolled
	reroll_btn.text = "Re-roll (%d)" % enc.rerolls_left

	# Disarm on anything that ends the turn. A mode that survived into the next
	# roll would silently turn a re-roll tap into a focus.
	if not free or not has_rolled:
		focus_armed = false
		bank_armed = false
	# Focus only, and only on the charge: an armed Focus with nothing to spend is
	# a mode that eats the next tap. Bank spends nothing, so it outlives an empty
	# charge -- dropping it here too would disarm a mode the player can still use.
	elif enc.focus_left <= 0:
		focus_armed = false
	focus_btn.disabled = not free or not has_rolled or enc.focus_left <= 0
	bank_btn.disabled = not free or not has_rolled
	# The labels never change width. An armed button that grew to "Focus 1 — tap
	# a die" is what made five buttons unaffordable, and a row of buttons that
	# re-flows under the thumb is a row that mis-taps; the instruction moves to
	# the ticker instead, next to the other teaching line.
	focus_btn.text = "Focus (%d)" % enc.focus_left
	bank_btn.text = "Bank"
	# Gold while armed. Every other button carries a fixed accent, so these are
	# the only controls on the screen whose colour means a mode rather than a
	# kind of action.
	_mode_colour(focus_btn, focus_armed, T.PICK)
	_mode_colour(bank_btn, bank_armed, T.BLOCK)

	# An armed mode is invisible without a prompt -- a gold button says "armed",
	# not "now tap a die" -- and that prompt has to lose to a fresh log line,
	# because what just happened is more use than what you are about to do. It
	# also has to leave when the mode does, or it hangs around describing a mode
	# that is no longer on. `_mode_line` is what tells those two apart.
	if _mode_line or ticker.text.is_empty():
		if focus_armed:
			_say("Focus armed — tap a die to step it up.", T.GOLD, T.F_TINY)
		elif bank_armed:
			_say("Bank armed — tap a die to hold it, tap it again to let it go.",
				T.GOLD, T.F_TINY)
		elif _mode_line:
			ticker.text = ""
	_mode_line = focus_armed or bank_armed
	# And the fallback the other half of the time: the first turn of a fight has
	# an empty log, and this is the one line that teaches the core verb. Gold, the
	# theme's action colour: FAINT measured 3.2:1 on the backdrop, under the 4.5:1
	# WCAG AA asks of body text, and this was the only label on screen failing it.
	if ticker.text.is_empty() and not enc.over:
		_say("Roll, then tap dice to queue a re-roll.", T.GOLD, T.F_TINY)
