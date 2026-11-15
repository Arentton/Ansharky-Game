extends Control
## Карта мест посадки: видимая сторона Луны (LRO, NASA SVS) и южный полюс.
## Клик по метке выбирает место.

signal site_selected(id: String)

const F = preload("res://scripts/flight_data.gd")

var selected := ""
var marks: Dictionary = {}       # id -> "bad" | "star" (подсветка)
var interactive := true

var _near: Texture2D = preload("res://assets/flight/moon_near.png")
var _south: Texture2D = preload("res://assets/flight/moon_south.png")
var _hover := ""
var _time := 0.0
var _font: Font


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _px() -> float:
	return 4.0 if size.x >= _near.get_width() * 8.0 + 40.0 else 3.0


func _map_rect(which: String) -> Rect2:
	var s := _near.get_width() * _px()
	var gap := maxf(20.0, (size.x - s * 2.0) / 3.0)
	var y := maxf(30.0, (size.y - s) * 0.5)
	return Rect2(Vector2(gap if which == "near" else gap * 2.0 + s, y), Vector2(s, s))


func site_pos(id: String) -> Vector2:
	var rect := _map_rect(F.SITES[id]["map"])
	var uv := F.site_uv(id)
	var core := rect.size - Vector2(2, 2) * _px()
	return rect.position + Vector2(_px(), _px()) + Vector2((uv.x + 1.0) * 0.5, (1.0 - uv.y) * 0.5) * core


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#05060d"))
	var rn := _map_rect("near")
	var rs := _map_rect("south")
	draw_texture_rect(_near, rn, false)
	draw_texture_rect(_south, rs, false)
	_label(rn.position + Vector2(0, -10), "Видимая сторона", Color(0.85, 0.87, 0.95), 14)
	_label(rs.position + Vector2(0, -10), "Южный полюс (до 78° ю. ш.)", Color(0.85, 0.87, 0.95), 14)
	_label(rs.position + Vector2(rs.size.x * 0.5 - 30, rs.size.y + 16), "↑ к Земле — вверху", Color(0.55, 0.58, 0.7), 12)
	for id in F.SITE_ORDER:
		var p := site_pos(id)
		var col := Color(1, 1, 1)
		match marks.get(id, ""):
			"bad":
				col = Color("#ff5a4f")
			"star":
				col = Color("#ffd23f")
		var s := 6.0 if id != selected else 8.0
		draw_rect(Rect2((p - Vector2(s, s) * 0.5).floor(), Vector2(s, s)), Color(0, 0, 0, 0.85))
		draw_rect(Rect2((p - Vector2(s - 2, s - 2) * 0.5).floor(), Vector2(s - 2, s - 2)), col)
		if id == selected:
			var r := 9.0 + 2.0 * sin(_time * 6.0)
			for j in 16:
				var a := TAU * j / 16.0
				draw_rect(Rect2((p + Vector2(cos(a), sin(a)) * r - Vector2(1, 1)).floor(), Vector2(2, 2)), Color(1, 0.85, 0.3))
		if id == selected or id == _hover:
			_label(p + Vector2(10, -8), F.SITES[id]["name"], Color(1, 1, 0.8), 13)


func _label(p: Vector2, text: String, col: Color, fsize: int) -> void:
	draw_string(_font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.85))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _nearest(pos: Vector2) -> String:
	var best := ""
	var bd := 16.0
	for id in F.SITE_ORDER:
		var d := site_pos(id).distance_to(pos)
		if d < bd:
			bd = d
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _nearest(event.position)
	elif interactive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _nearest(event.position)
		if id != "":
			selected = id
			site_selected.emit(id)
			accept_event()
