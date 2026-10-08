extends RefCounted

## Helper for loading and rendering illustrated dark-fantasy sprites and textures in Dice Fate.

static var _icon_tex := {}
static var _monster_tex := {}

static func get_icon_texture(k: int) -> Texture2D:
	if _icon_tex.has(k):
		return _icon_tex[k]
	var path := ""
	match k:
		1: path = "res://assets/sprites/icon_blade.png"
		2: path = "res://assets/sprites/icon_ward.png"
		3: path = "res://assets/sprites/icon_hex.png"
		4: path = "res://assets/sprites/icon_focus.png"
	if path != "" and ResourceLoader.exists(path):
		var t = ResourceLoader.load(path)
		if t is Texture2D:
			_icon_tex[k] = t
			return t
	return null

static func draw_die_icon(ci: CanvasItem, kind: int, o: Vector2, s: float) -> bool:
	var tex := get_icon_texture(kind)
	if tex != null:
		ci.draw_texture_rect(tex, Rect2(o, Vector2(s, s)), false)
		return true
	return false

static func get_monster_texture(behavior: int, is_boss: bool) -> Texture2D:
	var key: String = ("boss" if is_boss else str(behavior))
	if _monster_tex.has(key):
		return _monster_tex[key]
	var path := ""
	if is_boss:
		path = "res://assets/sprites/monster_devourer.png"
	else:
		match behavior:
			1: # ARMOR_GROW / BRACE
				path = "res://assets/sprites/monster_stone_sentinel.png"
			2: # LIFESTEAL
				path = "res://assets/sprites/monster_blood_cultist.png"
			3: # CURSE
				path = "res://assets/sprites/monster_hexweaver.png"
			4: # ENRAGE
				path = "res://assets/sprites/monster_devourer.png"
			_:
				path = "res://assets/sprites/monster_goblin_thief.png"
	if path != "" and ResourceLoader.exists(path):
		var t = ResourceLoader.load(path)
		if t is Texture2D:
			_monster_tex[key] = t
			return t
	return null

static func draw_monster_sigil(ci: CanvasItem, behavior: int, is_boss: bool, at: Vector2, rr: float) -> bool:
	var m_tex := get_monster_texture(behavior, is_boss)
	if m_tex != null:
		var side: float = rr * 2.2
		var m_rect := Rect2(at.x - side * 0.5, at.y - side * 0.5, side, side)
		ci.draw_texture_rect(m_tex, m_rect, false)
		return true
	return false
