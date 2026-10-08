extends RefCounted
## The whole look of the game, in code. No .tres, no font file, no sprites --
## so there is nothing to go missing on a fresh checkout, and one edit here
## restyles every screen at once. Set the Theme on the root Control; it cascades.
##
## Consumers preload() this file for the same reason dice.gd says so: a headless
## run on a fresh checkout has not built the global class cache. Note there is
## deliberately no `class_name` -- it would shadow the engine's own Theme.

# --- palette ---
# Named rather than inlined because fight.gd and game.gd both tint by meaning:
# a number is red because it is damage, not because red looks nice.

const BG := Color("#0e1015")
const PANEL := Color("#1a1e28")
const CARD := Color("#232838")
const CARD_HI := Color("#2b3145")
const BORDER := Color("#333a4d")

const TEXT := Color("#f0f3f8")
const MUTED := Color("#949eb2")   ## secondary text, and it has to clear 4.5:1 on
                                   ## CARD_HI, not just on CARD -- that is the fill a
                                   ## die card takes when it is armed, picked or hovered.
                                   ## See `test.gd`'s `_contrast`.
const FAINT := Color("#5a6379")

const GOLD := Color("#ffc24b")      ## primary action
const GOLD_DARK := Color("#c9922a")
const DMG := Color("#ff6b6b")       ## damage faces, the enemy's health
const BLOCK := Color("#5bc0eb")     ## block faces
const REROLL := Color("#b08cff")    ## re-roll faces
const PICK := Color("#7fd18f")      ## a die queued for a re-roll
const HP := Color("#e5484d")        ## damage to the player
const ALLY := Color("#6ee7a0")      ## the player's own health -- green, because the two
                                   ## bars sit one above the other and two reds read as one
const GOLD_LIGHT := Color("#ffd98a")

# --- type scale (the engine's default font; no font file to ship) ---
const F_DISPLAY := 40
const F_TITLE := 24
const F_BODY := 17
const F_SMALL := 14
const F_TINY := 12

const RADIUS := 10


## A flat card: solid fill, hairline border, rounded corners.
static func flat(fill: Color, border: Color = BORDER, width: int = 1, radius: int = RADIUS) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(0)
	return sb


## As flat(), with padding -- for panels that hold text.
static func padded(fill: Color, border: Color = BORDER, width: int = 1,
		radius: int = RADIUS, pad: int = 16) -> StyleBoxFlat:
	var sb := flat(fill, border, width, radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


## The theme applied to the root Control. Everything cascades from here.
static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = F_BODY

	# Button: gold for the one thing you should press, flat for everything else.
	_style_button(t, "normal", CARD, BORDER, TEXT)
	_style_button(t, "hover", CARD_HI, GOLD_DARK, TEXT)
	_style_button(t, "pressed", PANEL, GOLD, TEXT)
	_style_button(t, "focus", CARD, GOLD, TEXT)
	_style_button(t, "disabled", PANEL, PANEL, FAINT)

	t.set_stylebox("panel", "PanelContainer", padded(PANEL, BORDER))
	t.set_stylebox("panel", "Panel", padded(PANEL, BORDER))

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("default_color", "RichTextLabel", MUTED)
	t.set_font_size("normal_font_size", "RichTextLabel", F_SMALL)
	t.set_stylebox("normal", "RichTextLabel", flat(BG, BORDER, 0, 0))

	# ProgressBar: a recessed track with a fill that sits flush inside it.
	t.set_stylebox("background", "ProgressBar", flat(PANEL, BORDER, 1, 6))
	t.set_stylebox("fill", "ProgressBar", flat(HP, HP, 0, 6))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", F_TINY)

	t.set_color("font_color", "TabBar", GOLD)
	return t


static func _style_button(t: Theme, state: String, fill: Color, border: Color, font: Color) -> void:
	t.set_stylebox(state, "Button", flat(fill, border))
	t.set_color("font_color" if state != "disabled" else "font_disabled_color", "Button", font)


## Height of every tappable in the game, in canvas units.
##
## One number, because it was four: the fight row was 74, the title's primary
## 62, its secondary 54, and the sound toggle 34, and nothing kept them in step
## because nothing measured them. `shot.gd --check --at N` does now, and the
## numbers it produced are the reason this exists: on a 411dp phone those were
## 56, 47, 41 and 26 dp against Material's 48dp floor, so three of the four
## failed on a mainstream handset and the sound toggle failed at every width
## including the 540 the canvas is authored at.
##
## The canvas is 540 wide and never shrinks -- `canvas_items` + `expand` scales
## the whole thing to the window -- so a unit is one dp only on a 540dp phone.
## 74 is sized off a number that means something rather than off the floor: it
## is 56dp on a 411dp phone, the *comfortable* target Material asks for, and
## that clears 48dp at 360dp too. `shot.gd --check` is what checks it.
const TOUCH_H := 74


## Gold fill with dark text -- the "start run" / "confirm" button.
static func primary_button(text: String = "Tap to play") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, TOUCH_H)
	b.add_theme_font_size_override("font_size", F_TITLE)
	b.add_theme_color_override("font_color", BG)
	b.add_theme_color_override("font_hover_color", BG)
	b.add_theme_color_override("font_pressed_color", BG)
	b.add_theme_stylebox_override("normal", flat(GOLD, GOLD, 1, RADIUS))
	b.add_theme_stylebox_override("hover", flat(GOLD_LIGHT, GOLD_LIGHT, 1, RADIUS))
	b.add_theme_stylebox_override("pressed", flat(GOLD_DARK, GOLD_DARK, 1, RADIUS))
	b.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT, GOLD, 2, RADIUS))
	return b


## Gold outline over a dark fill -- the second thing you might press, so it
## never competes with the filled primary beside it.
static func secondary_button(text: String, accent: Color = GOLD) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, TOUCH_H)
	b.add_theme_font_size_override("font_size", F_BODY)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", accent)
	b.add_theme_stylebox_override("normal", flat(PANEL, accent, 1, RADIUS))
	b.add_theme_stylebox_override("hover", flat(CARD_HI, accent, 2, RADIUS))
	b.add_theme_stylebox_override("pressed", flat(PANEL, accent, 2, RADIUS))
	b.add_theme_stylebox_override("focus", flat(Color.TRANSPARENT, accent, 2, RADIUS))
	return b


## The full-screen backdrop: a near-black gradient, darker at the bottom, so the
## screen is not one flat slab of grey.
static func backdrop() -> TextureRect:
	var tr := TextureRect.new()
	var path := "res://assets/textures/bg_altar_table.png"
	if ResourceLoader.exists(path):
		var tex = ResourceLoader.load(path)
		if tex is Texture2D:
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_preset(Control.PRESET_FULL_RECT)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.modulate = Color(0.75, 0.75, 0.85, 0.60)
			tr.tree_entered.connect(func():
				var tw := tr.create_tween().set_loops()
				tw.tween_property(tr, "modulate", Color(0.88, 0.82, 0.92, 0.72), 1.6).set_trans(Tween.TRANS_SINE)
				tw.tween_property(tr, "modulate", Color(0.68, 0.70, 0.80, 0.52), 2.1).set_trans(Tween.TRANS_SINE)
			)
			return tr

	var g := Gradient.new()
	g.set_color(0, Color("#171b26"))
	g.set_color(1, BG)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)

	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


## A thin coloured rule used to separate HUD rows.
static func rule(col: Color = BORDER) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## The colour a die face is "about" -- damage, block, or a re-roll.
static func face_colour(dmg: int, block: int, rerolls: int) -> Color:
	if dmg > 0 and dmg >= block:
		return DMG
	if block > 0:
		return BLOCK
	if rerolls > 0:
		return REROLL
	return MUTED
