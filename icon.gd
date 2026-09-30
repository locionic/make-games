extends SceneTree
## Throwaway image generator, not part of the game. Writes every image the
## project ships, all drawn in code so a fresh checkout can produce them:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s icon.gd
## res://icon.png is the launcher icon -- the only image inside the APK. The
## one under res://play/ is Google Play's feature graphic, which is store art
## and sits behind a .gdignore so it never reaches the player. Re-run this
## after editing theme.gd to restyle the launcher too.

const T = preload("res://theme.gd")
const ICON := 512  ## Play's documented icon size. 1024 is the Android launcher
## master; Play wants 512x512, 32-bit PNG, so draw at 512 and let the launcher
## scale rather than uploading an oversized file and hoping.
const FEATURE := Vector2i(1024, 500)  ## Play's exact feature-graphic size
const SIDE := 0.56  ## die width as a fraction of the canvas's short edge


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# The one image the game ships. The launcher scales it to 48px, so it is
	# drawn large and centred. Alpha is required here -- 32-bit PNG.
	var icon := await _render(Vector2i(ICON, ICON), false)
	icon.save_png("res://icon.png")
	print("wrote res://icon.png ", icon.get_size())

	# The store banner: die on the left third, the name on the right, because
	# Play shows this edge-to-edge behind the install button. Play takes this as
	# JPEG or 24-bit PNG *without* alpha, and the read-back comes back RGBA --
	# so flatten it onto the backdrop here or the upload is rejected.
	var feature := await _render(FEATURE, true)
	DirAccess.make_dir_recursive_absolute("res://play")
	feature.convert(Image.FORMAT_RGB8)
	feature.save_png("res://play/feature.png")
	print("wrote res://play/feature.png ", feature.get_size())
	quit()


## A canvas of any shape with the game's backdrop and die on it. `wordmark` adds
## the title lockup. A SubViewport sizes independently of the window, so the
## output is a clean square (or banner) at full resolution rather than the
## project's 540x960 portrait.
func _render(size: Vector2i, wordmark: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(T.backdrop())
	var die := Control.new()
	die.set_anchors_preset(Control.PRESET_FULL_RECT)
	die.draw.connect(_draw_die.bind(die, size, wordmark))
	vp.add_child(die)

	for _i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


## The die at 0.56 of the short edge sits inside Android's 0.66 adaptive-icon
## safe zone, so this one PNG survives a circular mask and still reads at the
## 48px the Play listing shows it at.
func _draw_die(die: Control, size: Vector2i, wordmark: bool) -> void:
	var side := minf(size.x, size.y) * SIDE
	var cx := size.x * (0.28 if wordmark else 0.5)
	var at := Vector2(cx - side * 0.5, (size.y - side) * 0.5)
	var rect := Rect2(at, Vector2(side, side))

	# A soft drop shadow, so the die lifts off the backdrop instead of sitting
	# flat on it once the launcher has scaled it down to a thumbnail.
	die.draw_style_box(_box(Color(0, 0, 0, 0.5), 0.16, 0.0, side),
		Rect2(at + Vector2(0, side * 0.04), Vector2(side, side)))
	die.draw_style_box(_box(T.GOLD, 0.16, 0.02, side), rect)

	# Two columns of three. Six is the one pips layout that still reads as a
	# number once the whole thing is a thumbnail.
	for row in 3:
		for col in 2:
			die.draw_circle(Vector2(
				at.x + side * (0.31 + col * 0.38),
				at.y + side * (0.24 + row * 0.26)), side * 0.082, T.BG)

	if not wordmark:
		return
	# The engine's built-in font, so the banner needs no font file either. This
	# is the same default the whole game renders its text with.
	var font := ThemeDB.fallback_font
	var tx := size.x * 0.50
	die.draw_string(font, Vector2(tx, size.y * 0.47), "DICE FATE",
		HORIZONTAL_ALIGNMENT_LEFT, size.x - tx, 62, T.GOLD)
	die.draw_string(font, Vector2(tx, size.y * 0.66), "Nine fights. One pool of dice.",
		HORIZONTAL_ALIGNMENT_LEFT, size.x - tx, 26, T.MUTED)


## A flat rounded card -- the same shape `theme.gd` gives every die in a fight.
func _box(fill: Color, radius: float, border: float, side: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(side * radius))
	sb.set_border_width_all(maxi(int(side * border), 1))
	sb.border_color = T.GOLD_DARK
	return sb
