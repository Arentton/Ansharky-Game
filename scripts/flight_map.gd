extends Control

signal theta_picked(theta: float)

const F = preload("res://scripts/flight_data.gd")
const T = preload("res://scripts/trajectory.gd")
const PX := 4.0
const METEOR_PATH := "res://assets/image_2026-11-15_10-11-26.png"

const C_BG := Color("#05060d")
const C_ORBIT := Color(0.55, 0.6, 0.78, 0.5)
const C_OUT := Color("#7ee0ff")
const C_BACK_OK := Color("#7ef08c")
const C_BACK_BAD := Color("#ffb347")
const C_HAZARD := Color("#ff5a4f")
const C_TEXT := Color(0.85, 0.87, 0.95)
const C_DIM := Color(0.55, 0.58, 0.7)

var mode := "plan"
var phase := "tli"
var phi0 := 0.0
var theta := 0.0
var traj: Dictionary = {}
var hazards: Array = []
var t_now := 0.0
var auto_preview := true
var orbit_alt := 0.0

var _earth: Texture2D = preload("res://assets/flight/earth.png")
var _moon: Texture2D = preload("res://assets/flight/moon_small.png")
var _ship: Texture2D = preload("res://assets/flight/ship.png")
var _meteor: Texture2D = load(METEOR_PATH)
var _rocks: Array[Texture2D] = [
	_meteor,
	preload("res://assets/flight/asteroid_0.png"), preload("res://assets/flight/asteroid_1.png"),
	preload("res://assets/flight/asteroid_2.png"), preload("res://assets/flight/asteroid_3.png"),
	preload("res://assets/flight/asteroid_4.png"),
]
var _hz_layout := {}
var _stars: Array = []
var _time := 0.0
var _font: Font


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_font = ThemeDB.fallback_font
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 140:
		_stars.append([rng.randf(), rng.randf(), 2.0 if rng.randf() < 0.8 else 4.0, rng.randf_range(0.25, 0.9)])


func _process(delta: float) -> void:
	_time += delta
	if mode == "plan" and auto_preview and not traj.is_empty():
		var end_t: float = minf(float(traj["peri_t"]) + 1.5 * F.DAY, float(traj["t_end"]))
		t_now += delta * F.DAY / 1.6
		if t_now > end_t + 0.6 * F.DAY:
			t_now = 0.0
	queue_redraw()


func _center() -> Vector2:
	var inset_w := _inset_rect().size.x + 20.0
	var cx := minf(size.x * 0.5, size.x - inset_w - _radius_px() * 0.55)
	return Vector2(maxf(cx, _radius_px() + 20.0), size.y * 0.5)


func _radius_px() -> float:
	return minf(size.y * 0.5 - 26.0, (size.x - 230.0) * 0.5)


func _k() -> float:
	return _radius_px() / (F.MOON_DIST + 25000.0)


func to_screen(p: Vector2) -> Vector2:
	return _center() + Vector2(p.x, -p.y) * _k()


func _earth_r() -> float:
	return _earth.get_width() * PX * 0.5


func _inset_rect() -> Rect2:
	return Rect2(size.x - 216.0, 12.0, 204.0, 204.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for s in _stars:
		var a: float = s[3] * (0.75 + 0.25 * sin(_time * 1.3 + s[0] * 40.0))
		draw_rect(Rect2(Vector2(s[0] * size.x, s[1] * size.y).floor(), Vector2(s[2], s[2])), Color(1, 1, 0.85, a))
	var c := _center()
	_dotted_circle(c, F.MOON_DIST * _k(), C_ORBIT, 2.0, 2.0)
	_label(c + Vector2(-F.MOON_DIST * _k() + 6, -6), "Moon's orbit (384,400 km)", C_DIM, 12)
	for i in hazards.size():
		_draw_hazard(i)
	if not traj.is_empty():
		_draw_trajectory()
	var er := _earth_r()
	_dotted_circle(c, er + 6.0, Color(0.5, 0.8, 1.0, 0.6), 2.0, 6.0)
	draw_texture_rect(_earth, Rect2(c - Vector2(er, er), Vector2(er, er) * 2.0), false)
	_label(c + Vector2(-22, er + 22), "EARTH", C_TEXT, 13)
	if phase == "tli":
		_draw_burn_marker(c, er + 6.0)
	var mp := to_screen(T.moon_pos(phi0, t_now))
	if mode == "plan" and not traj.is_empty() and float(traj["peri_alt"]) < F.PERI_REACH * 3.0:
		var tp: float = traj["peri_t"]
		_moon_arc(t_now, tp)
		_draw_moon(to_screen(T.moon_pos(phi0, tp)), 0.35)
		_label(to_screen(T.moon_pos(phi0, tp)) + Vector2(-40, -34), "Moon in %.1f days" % (tp / F.DAY), C_DIM, 12)
	_draw_moon(mp, 1.0)
	_label(mp + Vector2(-16, 40), "MOON", C_TEXT, 13)
	if not traj.is_empty() and phase not in ["tli", "orbit", "site", "landing"]:
		_draw_ship(to_screen(T.sample(traj, "pts", t_now)), _ship_dir())
	elif phase in ["orbit", "site", "landing"]:
		_draw_ship(mp + Vector2(cos(_time * 2.0), sin(_time * 2.0)) * 30.0, Vector2(-sin(_time * 2.0), cos(_time * 2.0)))
	_draw_inset()


func _draw_trajectory() -> void:
	var pts: PackedVector2Array = traj["pts"]
	var ts: PackedFloat64Array = traj["ts"]
	var peri_t: float = traj["peri_t"]
	var back_col := C_BACK_OK if traj["free_return"] else C_BACK_BAD
	var c := _center()
	var er := _earth_r() + 8.0
	var last := Vector2(INF, INF)
	for i in pts.size():
		var p := to_screen(pts[i])
		if p.distance_to(c) < er:
			continue
		if p.distance_to(last) < 7.0:
			continue
		last = p
		var t := ts[i]
		var col := C_OUT if t <= peri_t else back_col
		if mode == "view":
			col.a = 1.0 if t <= t_now else 0.35
		for h in hazards:
			if pts[i].distance_to(T.hazard_pos(h, t)) < float(h["r"]):
				col = C_HAZARD
				break
		draw_rect(Rect2((p - Vector2(1.5, 1.5)).floor(), Vector2(3, 3)), col)


func _draw_burn_marker(c: Vector2, r: float) -> void:
	var dir := Vector2(cos(theta), -sin(theta))
	var p := c + dir * r
	var blink := 0.6 + 0.4 * sin(_time * 6.0)
	draw_rect(Rect2((p - Vector2(4, 4)).floor(), Vector2(8, 8)), Color(1.0, 0.6, 0.15, blink))
	var pro := Vector2(-dir.y, dir.x) * -1.0
	for j in range(1, 5):
		draw_rect(Rect2((p + pro * (6.0 + j * 5.0) - Vector2(1, 1)).floor(), Vector2(3, 3)), Color(1.0, 0.75, 0.3, 0.9))
	_label(p + dir * 12.0 + Vector2(-30, 0), "burn", Color(1.0, 0.75, 0.3), 12)


func _moon_arc(t0: float, t1: float) -> void:
	var steps := 24
	for j in steps + 1:
		var t := lerpf(t0, t1, float(j) / steps)
		var p := to_screen(T.moon_pos(phi0, t))
		draw_rect(Rect2((p - Vector2(1, 1)).floor(), Vector2(3, 3)), Color(0.9, 0.9, 0.8, 0.55))


func _draw_moon(p: Vector2, alpha: float) -> void:
	var s := _moon.get_size() * PX
	draw_texture_rect(_moon, Rect2((p - s * 0.5).floor(), s), false, Color(1, 1, 1, alpha))


func _ship_dir() -> Vector2:
	var a := to_screen(T.sample(traj, "pts", t_now))
	var b := to_screen(T.sample(traj, "pts", t_now + 1800.0))
	return (b - a).normalized() if a.distance_to(b) > 0.01 else Vector2.RIGHT


func _draw_ship(p: Vector2, dir: Vector2) -> void:
	var s := _ship.get_size() * 2.0
	draw_set_transform(p, dir.angle(), Vector2.ONE)
	draw_texture_rect(_ship, Rect2(-s * 0.5, s), false)
	draw_set_transform(Vector2.ZERO)
	if fmod(_time, 0.6) < 0.3:
		draw_rect(Rect2((p - Vector2(2, 2)).floor(), Vector2(4, 4)), Color(1, 1, 0.6))


func _draw_hazard(i: int) -> void:
	var h: Dictionary = hazards[i]
	var p := to_screen(T.hazard_pos(h, t_now))
	var r: float = float(h["r"]) * _k()
	_dotted_circle(p, r, Color(C_HAZARD, 0.55), 2.0, 5.0)
	for j in range(1, 7):
		var q := to_screen(T.hazard_pos(h, t_now + j * F.DAY / 6.0))
		draw_rect(Rect2((q - Vector2(1, 1)).floor(), Vector2(2, 2)), Color(C_HAZARD, 0.35))
	var lay := _layout(h)
	for rock in lay["rocks"]:
		var a: float = rock["phase"] + _time * rock["speed"]
		_draw_rock(p + Vector2(cos(a), sin(a)) * r * rock["dist"], rock)
	_draw_rock(p, lay["main"])
	_label(p + Vector2(-r * 0.6, -r - 6.0), "'%s' stream" % h["name"], Color(1.0, 0.6, 0.55), 12)


func _layout(h: Dictionary) -> Dictionary:
	var seed_v: int = int(h.get("seed", hash(h["name"])))
	if _hz_layout.has(seed_v):
		return _hz_layout[seed_v]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var main := _rock_spec(rng, int(h.get("art", rng.randi_range(0, 3))))
	var rocks := []
	for j in rng.randi_range(3, 5):
		var spec := _rock_spec(rng, rng.randi_range(maxi(int(main["tex"]) + 1, 2), 5))
		spec["dist"] = rng.randf_range(0.45, 0.95)
		spec["phase"] = rng.randf() * TAU
		spec["speed"] = rng.randf_range(0.15, 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		rocks.append(spec)
	_hz_layout[seed_v] = {"main": main, "rocks": rocks}
	return _hz_layout[seed_v]


func _rock_spec(rng: RandomNumberGenerator, idx: int) -> Dictionary:
	return {"tex": idx, "rot": PI * 0.5 * rng.randi_range(0, 3),
		"flip": Vector2(-1.0 if rng.randf() < 0.5 else 1.0, 1.0)}


func _draw_rock(p: Vector2, rock: Dictionary) -> void:
	var tex: Texture2D = _rocks[rock["tex"]]
	if tex == null:
		return
	var s := tex.get_size()
	draw_set_transform(p.floor(), rock["rot"], rock["flip"])
	draw_texture(tex, -(s * 0.5).floor())
	draw_set_transform(Vector2.ZERO)


func _draw_inset() -> void:
	var rect := _inset_rect()
	draw_rect(rect, Color(0.02, 0.03, 0.07, 0.92))
	draw_rect(rect, Color(0.45, 0.5, 0.7, 0.8), false, 2.0)
	_label(rect.position + Vector2(8, 16), "Near the Moon (±9,000 km)", C_DIM, 12)
	var mc := rect.get_center() + Vector2(0, 8)
	var ki := 88.0 / 9000.0
	var mr := F.R_MOON * ki
	var ms := Vector2(mr, mr) * 2.0
	draw_texture_rect(_moon, Rect2((mc - ms * 0.5).floor(), ms), false)
	var to_earth := -T.moon_pos(phi0, t_now).normalized()
	var ep := mc + Vector2(to_earth.x, -to_earth.y) * 80.0
	draw_rect(Rect2((ep - Vector2(3, 3)).floor(), Vector2(6, 6)), Color(0.4, 0.7, 1.0))
	_label(ep + Vector2(-18, -8), "Earth", Color(0.5, 0.75, 1.0), 11)
	if phase in ["orbit", "site", "landing"]:
		var orr := (F.R_MOON + orbit_alt) * ki
		_dotted_circle(mc, maxf(orr, mr + 3.0), Color(0.6, 1.0, 0.7, 0.8), 2.0, 8.0)
		var a := _time * 1.5
		var sp := mc + Vector2(cos(a), sin(a)) * maxf(orr, mr + 3.0)
		draw_rect(Rect2((sp - Vector2(2, 2)).floor(), Vector2(5, 5)), Color(1, 1, 0.6))
		_label(rect.position + Vector2(8, rect.size.y - 8), "orbit %d km" % roundi(orbit_alt), C_TEXT, 12)
		return
	if traj.is_empty():
		return
	var rel: PackedVector2Array = traj["rel"]
	var ts: PackedFloat64Array = traj["ts"]
	var lim := 9000.0
	var last := Vector2(INF, INF)
	for i in rel.size():
		var q: Vector2 = rel[i]
		if absf(q.x) > lim or absf(q.y) > lim:
			continue
		var p := mc + Vector2(q.x, -q.y) * ki
		if p.distance_to(last) < 4.0:
			continue
		last = p
		var col := C_OUT if ts[i] <= float(traj["peri_t"]) else (C_BACK_OK if traj["free_return"] else C_BACK_BAD)
		if mode == "view" and ts[i] > t_now:
			col.a = 0.35
		draw_rect(Rect2((p - Vector2(1, 1)).floor(), Vector2(2, 2)), col)
	var pi_: int = traj["peri_i"]
	if pi_ < rel.size() and float(traj["peri_alt"]) < lim:
		var pp := mc + Vector2(rel[pi_].x, -rel[pi_].y) * ki
		draw_rect(Rect2((pp - Vector2(3, 3)).floor(), Vector2(6, 6)), Color(1, 0.85, 0.3))
		var txt := "impact!" if traj["status"] == "impact" else "%d km" % roundi(float(traj["peri_alt"]))
		_label(pp + Vector2(6, -6), txt, Color(1, 0.85, 0.3), 12)
	var sq := T.sample(traj, "rel", t_now)
	if absf(sq.x) < lim and absf(sq.y) < lim and phase != "tli":
		var sp := mc + Vector2(sq.x, -sq.y) * ki
		draw_rect(Rect2((sp - Vector2(2, 2)).floor(), Vector2(5, 5)), Color(1, 1, 0.6))


func _dotted_circle(c: Vector2, r: float, col: Color, dot: float, step_px: float) -> void:
	if r <= 1.0:
		return
	var n := maxi(12, int(TAU * r / step_px))
	for j in n:
		var a := TAU * j / n
		draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * r - Vector2(dot, dot) * 0.5).floor(), Vector2(dot, dot)), col)


func _label(p: Vector2, text: String, col: Color, fsize: int) -> void:
	draw_string(_font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _gui_input(event: InputEvent) -> void:
	if mode != "plan" or phase != "tli":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var d: Vector2 = event.position - _center()
		if d.length() < _earth_r() + 70.0 and d.length() > 4.0:
			theta_picked.emit(atan2(-d.y, d.x))
			accept_event()
