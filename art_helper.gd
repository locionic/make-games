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
		4: path = "res://assets/sprites/icon_reroll.png"
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

static func get_monster_texture(behavior: int, is_boss: bool, ename: String = "") -> Texture2D:
	var key: String = ename.to_lower() if ename != "" else ("boss" if is_boss else str(behavior))
	if _monster_tex.has(key):
		return _monster_tex[key]
	var path := ""
	var lower_name := ename.to_lower()
	if is_boss or "devourer" in lower_name:
		path = "res://assets/sprites/monster_devourer.png"
	elif "sentinel" in lower_name or "rust golem" in lower_name or "golem" in lower_name:
		path = "res://assets/sprites/monster_stone_sentinel.png"
	elif "knight" in lower_name or "ironhide" in lower_name or "warden" in lower_name or "iron" in lower_name:
		path = "res://assets/sprites/monster_bone_knight.png"
	elif "cultist" in lower_name or "bloodletter" in lower_name or "fungal" in lower_name or "leech" in lower_name:
		path = "res://assets/sprites/monster_blood_cultist.png"
	elif "hexweaver" in lower_name or "hexer" in lower_name or "spider" in lower_name:
		path = "res://assets/sprites/monster_hexweaver.png"
	elif "goblin" in lower_name or "thief" in lower_name or "grunt" in lower_name:
		path = "res://assets/sprites/monster_goblin_thief.png"
	else:
		match behavior:
			1, 5: # ARMOR_GROW, BRACE
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

static func draw_monster_sigil(ci: CanvasItem, behavior: int, is_boss: bool, at: Vector2, rr: float, ename: String = "", edge: Color = Color.WHITE, wash: Color = Color.TRANSPARENT) -> bool:
	var m_tex := get_monster_texture(behavior, is_boss, ename)
	if m_tex != null:
		# Ambient occult halo
		ci.draw_circle(at, rr * 0.96, Color(0, 0, 0, 0.45))
		ci.draw_circle(at, rr * 0.90, wash)
		ci.draw_arc(at, rr * 0.92, 0.0, TAU, 36, Color(edge.r, edge.g, edge.b, 0.35), 1.5)
		
		var side: float = rr * 2.0
		var m_rect := Rect2(at.x - side * 0.5, at.y - side * 0.5, side, side)
		ci.draw_texture_rect(m_tex, m_rect, false)
		
		# Rim vignette ring
		ci.draw_arc(at, rr * 0.95, 0.0, TAU, 36, Color(edge.r, edge.g, edge.b, 0.20), 2.0)
		return true
	return false
