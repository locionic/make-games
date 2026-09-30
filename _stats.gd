extends SceneTree
## Throwaway analysis tool, not part of the game. There is no reliable way to
## eyeball the store art in this environment, so this measures it instead:
## per horizontal band it reports how flat or busy the screen is, which is the
## thing a visual read of "this looks empty / this looks crowded" would say.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s _stats.gd
##
## Three numbers per band, each answering a different question:
##   mean  - average brightness. A dead band and a content band differ most here.
##   sd    - brightness spread. The backdrop is a smooth gradient, so sd stays
##           near zero across empty space and spikes wherever ink sits.
##   cols  - distinct colours, 5 bits per channel. The one that separates "a
##           gradient with nothing on it" from "a screen full of type".

const DIR := "res://play/screenshots/"
const BANDS := 12


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for n in DirAccess.get_files_at(DIR):
		if n.ends_with(".png"):
			_report(n)
	quit()


func _report(name: String) -> void:
	var img := Image.load_from_file(DIR + name)
	var w := img.get_width()
	var h := img.get_height()
	print("\n== %s  %dx%d" % [name, w, h])
	print("  band     y-range   mean    sd     max  cols")
	var bh := h / BANDS
	for b in BANDS:
		var y0 := b * bh
		var y1 := y0 + bh if b < BANDS - 1 else h
		var n := 0
		var sum := 0.0
		var sum2 := 0.0
		var hi := 0.0
		var seen := {}
		for y in range(y0, y1):
			for x in w:
				var c := img.get_pixel(x, y)
				var lum := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
				sum += lum
				sum2 += lum * lum
				hi = maxf(hi, lum)
				# 5 bits per channel: fine enough to separate the palette,
				# coarse enough that gradient banding does not inflate the count.
				seen[Vector3i(int(c.r * 31.0), int(c.g * 31.0), int(c.b * 31.0))] = true
				n += 1
		var mean := sum / n
		var sd: float = sqrt(maxf(sum2 / n - mean * mean, 0.0))
		print("  %2d  %4d..%-4d  %.3f  %.3f  %.3f  %4d" % [b, y0, y1, mean, sd, hi, seen.size()])
