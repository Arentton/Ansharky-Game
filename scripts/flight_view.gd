extends Control
## Full-screen flight to the Moon: launch, Earth orbit, trans-lunar injection,
## lunar orbit / flyby, powered descent, and the surface EVA where the astronaut
## collects samples. Everything is drawn in pixel art at 480x270 and scaled up.
##
## Timeline and telemetry follow NASA data:
##   ascent & Earth orbit - Artemis I (SLS Block 1, launched 16 Nov 2022)
##   TLI, lunar orbit, powered descent, landing site - Apollo 11 (July 1969)
##   lunar relief - LRO LOLA elevation along 0.67°N (Sea of Tranquility)
## Rocket, pad, plumes, clouds and smoke: assets/sls (see assets/sls/README.md).

const D = preload("res://scripts/mission_data.gd")
const VW := 480.0
const VH := 270.0

# --- SLS pack (all rocket parts share one 48x216 canvas) ---
const P_CORE := preload("res://assets/sls/rocket/aligned_48x216/00_core.png")
const P_ICPS := preload("res://assets/sls/rocket/aligned_48x216/01_icps.png")
const P_LVSA := preload("res://assets/sls/rocket/aligned_48x216/02_lvsa.png")
const P_ORION := preload("res://assets/sls/rocket/aligned_48x216/03_orion.png")
const P_FAIR_L := preload("res://assets/sls/rocket/aligned_48x216/04_fairing_L.png")
const P_FAIR_R := preload("res://assets/sls/rocket/aligned_48x216/05_fairing_R.png")
const P_LAS := preload("res://assets/sls/rocket/aligned_48x216/06_las.png")
const P_SRB_L := preload("res://assets/sls/rocket/aligned_48x216/07_srb_L.png")
const P_SRB_R := preload("res://assets/sls/rocket/aligned_48x216/08_srb_R.png")
const P_ARRAYS := preload("res://assets/sls/rocket/aligned_48x216/09_arrays.png")
# part -> center on the canvas (rotation pivot when it separates)
const PART_CENTER := {
	"core": Vector2(24.5, 142.5), "icps": Vector2(24.5, 57), "lvsa": Vector2(24.5, 64),
	"orion": Vector2(24.5, 33), "fairing_L": Vector2(21.5, 37), "fairing_R": Vector2(28, 37),
	"las": Vector2(24.5, 17), "srb_L": Vector2(11, 156), "srb_R": Vector2(38, 156), "arrays": Vector2(24.5, 36.5),
}
const ROCKET_PIVOT := Vector2(24, 108)
const STACK_PIVOT := Vector2(24, 48)   # ICPS + Orion
const ORION_PIVOT := Vector2(24.5, 34)
const NOZZLE_SRB_L := Vector2(11, 212)
const NOZZLE_SRB_R := Vector2(38, 212)
const NOZZLE_CORE := Vector2(24, 212)
const NOZZLE_RL10 := Vector2(24, 73)

const FX_SRB := preload("res://assets/sls/fx/srb_plume_strip4.png")
const FX_SRB_VAC := preload("res://assets/sls/fx/srb_vac_strip4.png")
const FX_CORE := preload("res://assets/sls/fx/core_plume_strip4.png")
const FX_CORE_VAC := preload("res://assets/sls/fx/core_vac_strip4.png")
const FX_RL10 := preload("res://assets/sls/fx/rl10_strip4.png")
const FX_BSM := preload("res://assets/sls/fx/bsm_strip4.png")
const FX_LAS := preload("res://assets/sls/fx/las_jet_strip4.png")

const PAD_FAR := preload("res://assets/sls/pad/far.png")
const PAD_TOWER := preload("res://assets/sls/pad/tower.png")
const PAD_ARMS_ON := preload("res://assets/sls/pad/arms_attached.png")
const PAD_ARMS_SWING := preload("res://assets/sls/pad/arms_swinging.png")
const PAD_ARMS_OFF := preload("res://assets/sls/pad/arms_retracted.png")
const PAD_PAD := preload("res://assets/sls/pad/pad.png")
const PAD_BASE := preload("res://assets/sls/pad/ml_base.png")
const PAD_Y := -20.0                    # 480x290 pad canvas shifted up into 480x270
const PAD_ROCKET_TL := Vector2(216, 36)

const CLOUDS := [preload("res://assets/sls/clouds/cu_XS.png"), preload("res://assets/sls/clouds/cu_S.png"),
	preload("res://assets/sls/clouds/cu_M.png"), preload("res://assets/sls/clouds/cu_M2.png"),
	preload("res://assets/sls/clouds/cu_L.png")]
const PUFFS := [preload("res://assets/sls/smoke/puff10_0.png"), preload("res://assets/sls/smoke/puff16_0.png"),
	preload("res://assets/sls/smoke/puff16_1.png"), preload("res://assets/sls/smoke/puff24_0.png"),
	preload("res://assets/sls/smoke/puff24_1.png"), preload("res://assets/sls/smoke/puff32_0.png"),
	preload("res://assets/sls/smoke/puff32_1.png"), preload("res://assets/sls/smoke/puff40_0.png")]

const TEX_EARTH := preload("res://assets/earth.png")
const TEX_MOON := preload("res://assets/moon.png")

# --- own assets (assets/space, tools/gen_space_assets.py) ---
const TEX_LANDER := preload("res://assets/space/lander.png")
const TEX_ASTRO := preload("res://assets/space/astronaut_walk.png")
const TEX_SAMPLES := preload("res://assets/space/samples.png")
const PROFILE_JSON := "res://assets/space/moon_profile_tranquility.json"

# Segment start times (local seconds)
const S_ORBIT := D.T_ASCENT
const S_TLI := S_ORBIT + D.T_EARTH_ORBIT
const S_MOON := S_TLI + D.T_TLI
const S_FINAL := S_MOON + D.T_MOON
# Ascent events (local seconds) — matched to Artemis I T+ times via K_ASCENT
const E_LIFTOFF := 3.0      # T+0
const E_SRB_SEP := 14.0     # T+132 s
const E_FAIRINGS := 17.0    # T+193 s
const E_LAS := 17.3         # T+199 s
const E_MECO := 23.0        # T+476 s
const E_CORE_SEP := 24.0    # T+488 s

# Telemetry keyframes: [local t, mission elapsed time s, altitude/distance km, speed km/h]
const K_ASCENT := [[0, -4, 0, 0], [3, 0, 0, 0], [6, 12, 0.4, 250], [10, 70, 13.7, 1600],
	[14, 132, 48.0, 6200], [17, 193, 76.0, 7700], [18, 210, 80.0, 7900], [23, 476, 162.0, 28100], [26, 496, 165, 28160]]
const K_ORBIT := [[26, 496, 165, 28160], [30, 1100, 185, 28000], [36, 3060, 185, 27950]]
const K_TLI := [[36, 5280, 185, 27950], [39, 6360, 330, 38900], [43, 90000, 200000, 5500],
	[47, 262000, 370000, 3200], [48, 273000, 382000, 8300]]
const K_LOI := [[48, 273000, 300, 8300], [52, 274000, 110, 5860], [58, 288000, 110, 5860], [66, 300000, 110, 5860]]
const K_FLYBY := [[48, 273000, 8000, 8300], [53, 277000, 130, 8200], [58, 281000, 9000, 7000]]
const K_DESCENT := [[58, 369185, 15.0, 6100], [63, 369500, 7.0, 3000], [68, 369700, 2.1, 540],
	[72, 369900, 0.15, 60], [74, 369940, 0, 0]]

const C_ASCENT := [[0, "Four RS-25 engines start"], [3, "Liftoff! 39.1 MN of thrust (8.8 million lbf)"],
	[6, "Clearing the launch tower"], [9, "Max Q: maximum dynamic pressure"],
	[13.6, "Solid rocket booster separation"], [16.8, "Service module fairings and launch abort system jettison"],
	[21, "Core stage main engine cutoff (MECO)"], [24, "Core stage separation"]]
const C_ORBIT := [[26, "ICPS + Orion in Earth orbit: 185 km, 7.8 km/s, 88 min per lap"],
	[30, "Orion solar arrays deployed (T+18 min)"], [33, "ICPS perigee raise burn (T+51 min)"]]
const C_TLI := [[36, "Trans-lunar injection: +3.1 km/s in an 18-minute burn"],
	[40, "Coasting to the Moon: 384,400 km, about 3 days"],
	[45, "Entering the Moon's sphere of influence"]]
const C_LOI := [[48, "Lunar orbit insertion burn"], [52, "Lunar orbit: 110 km, 1.6 km/s, ~2 hours per lap"]]
const C_FLYBY := [[48, "Lunar flyby: closest approach 130 km above the surface (Artemis I)"],
	[54, "Gravity assist: free-return trajectory back to Earth"]]
const C_SCIENCE := [[58, "Orbital instruments are mapping the surface"]]
const C_DESCENT := [[58, "Powered descent initiation: 15 km above the Moon"], [63, "Braking phase"],
	[67, "High gate: pitch over, landing site in view"], [71, "Low gate: final approach"],
	[73.3, "Contact light! Touchdown: Sea of Tranquility (0.67°N, 23.47°E)"]]

# Surface EVA
const WORLD_W := 1600.0
const LANDER_X := 220.0
const GRAVITY := 32.0       # px/s²: 1.62 m/s² (1/6 g) at 20 px per metre
const WALK := 60.0          # px/s (Apollo "bunny hop" ~3 m/s)
const JUMP := 48.0
const PICK_DIST := 20.0
## Телеметрия (время, высота, скорость) пока скрыта — на экране только ракета и субтитры.
## Поставьте true, чтобы вернуть табличку в левом верхнем углу.
const SHOW_TELEMETRY := false
const FADE := 0.6           # затемнение между сценами, секунды в каждую сторону

var mission: Dictionary = {}
var t := 0.0
var mode := "flight"        # flight | surface
var _dur := 60.0
var _profile := "orbit"
var _surface_mission := false
var _base := Transform2D()
var _rng := RandomNumberGenerator.new()
var _stars: Array[Vector3] = []
var _clouds: Array[Vector3] = []
var _particles: Array = []
var _heights: PackedFloat32Array = []
var _craters: Array[Vector3] = []
var _fx_frame := 0
var _cam := 0.0             # vertical camera scroll during ascent

var _telemetry: Label
var _caption: Label
var _skip: Button
var _end_eva: Button

# astronaut
var _astro := Vector2(LANDER_X + 24, 0)
var _astro_vy := 0.0
var _astro_flip := false
var _astro_frame := 0
var _anim_t := 0.0
var _send_t := 0.0
var _controller := false
var _last_fact := ""


func setup(m: Dictionary) -> void:
	mission = m
	_profile = m.get("profile", "orbit")
	_surface_mission = m.get("surface", false)
	_dur = D.flight_seconds(_profile)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = 2022
	for i in 140:
		_stars.append(Vector3(_rng.randf() * VW, _rng.randf() * VH, _rng.randf()))
	# x, height above the deck (px), size class
	for i in 16:
		var h := _rng.randf_range(150, 950)
		_clouds.append(Vector3(_rng.randf_range(-40, 520), h, clampf(4.0 - h / 260.0, 0.0, 4.0)))
	_load_profile()
	_build_ui()
	var ms := get_node("/root/MissionState")
	ms.changed.connect(_on_state_changed)
	ms.moon_pos.connect(_on_moon_pos)
	ms.notified.connect(_on_notified)
	var net := get_node("/root/HighLevelNetworkHandler")
	_controller = net.test_mode or not net.is_online() or net.my_role() == "astronaut"
	_on_state_changed()


func _load_profile() -> void:
	var f := FileAccess.open(PROFILE_JSON, FileAccess.READ)
	if f != null:
		var data = JSON.parse_string(f.get_as_text())
		if data is Dictionary:
			for h in data["heights"]:
				_heights.append(float(h))
	if _heights.is_empty():
		for i in 160:
			_heights.append(0.5 + 0.2 * sin(i * 0.3))
	for i in 34:
		_craters.append(Vector3(_rng.randf() * WORLD_W, _rng.randf_range(4, 16), _rng.randf()))


func _build_ui() -> void:
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Courier New", "monospace"])
	_telemetry = Label.new()
	_telemetry.position = Vector2(14, 10)
	_telemetry.add_theme_font_override("font", mono)
	_telemetry.add_theme_font_size_override("font_size", 16)
	_telemetry.add_theme_stylebox_override("normal", _box())
	_telemetry.visible = SHOW_TELEMETRY
	add_child(_telemetry)

	_caption = Label.new()
	_caption.anchor_left = 0.5
	_caption.anchor_right = 0.5
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_left = -360
	_caption.offset_right = 360
	_caption.offset_top = -78
	_caption.offset_bottom = -30
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", mono)
	_caption.add_theme_font_size_override("font_size", 16)
	_caption.add_theme_stylebox_override("normal", _box())
	add_child(_caption)

	_skip = Button.new()
	_skip.text = "Skip ▶▶"
	_skip.anchor_left = 1.0
	_skip.anchor_right = 1.0
	_skip.offset_left = -120
	_skip.offset_right = -14
	_skip.offset_top = 10
	_skip.offset_bottom = 42
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.visible = false # промотка без кнопки: хост жмёт Esc
	_skip.pressed.connect(func(): get_node("/root/MissionState").skip_flight())
	add_child(_skip)

	_end_eva = Button.new()
	_end_eva.text = "Return to lander"
	_end_eva.anchor_left = 1.0
	_end_eva.anchor_right = 1.0
	_end_eva.offset_left = -180
	_end_eva.offset_right = -14
	_end_eva.offset_top = 10
	_end_eva.offset_bottom = 42
	_end_eva.focus_mode = Control.FOCUS_NONE
	_end_eva.visible = false
	_end_eva.pressed.connect(func(): get_node("/root/MissionState").request("end_surface"))
	add_child(_end_eva)


func _box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.04, 0.1, 0.72)
	sb.border_color = Color(0.35, 0.5, 0.8, 0.6)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(6)
	return sb


# --- State --------------------------------------------------------------------

func _on_state_changed() -> void:
	var f: Dictionary = get_node("/root/MissionState").state.get("flight", {})
	if f.is_empty():
		return
	if f["phase"] == "flight":
		var server_t: float = _dur - float(f["t"])
		if abs(server_t - t) > 1.5:
			t = clampf(server_t, 0.0, _dur) # подстраиваемся под хост (промотка/лаг)
	elif f["phase"] == "surface" and mode != "surface":
		_start_surface()


func _start_surface() -> void:
	mode = "surface"
	t = _dur
	_astro = Vector2(LANDER_X + 26, _ground_y(LANDER_X + 26))
	_skip.visible = false
	_end_eva.visible = false # закончить выход: подойти к модулю и нажать E
	_particles.clear()
	get_node("/root/Music").play("moon")


func _on_moon_pos(pos: Vector2, flip: bool, frame: int) -> void:
	if not _controller:
		_astro = pos
		_astro_flip = flip
		_astro_frame = frame


func _on_notified(text: String) -> void:
	if text.begins_with("Collected:"):
		_last_fact = text


# --- Loop ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode == "flight" and multiplayer.is_server() and event.is_action_pressed("ui_cancel"):
		get_node("/root/MissionState").skip_flight()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_fx_frame = int(Time.get_ticks_msec() / 66.6) % 4 # 15 fps plume animation
	if mode == "flight":
		t = min(t + delta, _dur)
		if _surface_mission and t > S_FINAL - 2.0:
			get_node("/root/Music").play("moon")
	else:
		_process_surface(delta)
	_update_particles(delta)
	_update_text()
	queue_redraw()


func _process_surface(delta: float) -> void:
	if not _controller:
		return
	var dir := 0.0
	if Input.is_action_pressed("move_left"):
		dir -= 1.0
	if Input.is_action_pressed("move_right"):
		dir += 1.0
	_astro.x = clampf(_astro.x + dir * WALK * delta, 10.0, WORLD_W - 10.0)
	if dir != 0.0:
		_astro_flip = dir < 0.0
	var gy := _ground_y(_astro.x)
	var on_ground := _astro.y >= gy - 0.5
	if on_ground and (Input.is_action_just_pressed("moveForward") or Input.is_action_just_pressed("ui_accept")):
		_astro_vy = -JUMP
		on_ground = false
	if not on_ground:
		_astro_vy += GRAVITY * delta
		_astro.y += _astro_vy * delta
		if _astro.y >= gy:
			_astro.y = gy
			_astro_vy = 0.0
			_dust(_astro, 4)
	else:
		_astro.y = gy
		_astro_vy = 0.0
	_anim_t += delta * (8.0 if dir != 0.0 and on_ground else 0.0)
	_astro_frame = int(_anim_t) % 4 if dir != 0.0 else 0
	if Input.is_action_just_pressed("interact"):
		var i := _nearest_sample()
		if i >= 0:
			get_node("/root/MissionState").request("collect", [i])
		elif _near_lander():
			get_node("/root/MissionState").request("end_surface")
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.05
		get_node("/root/MissionState").send_moon_pos(_astro, _astro_flip, _astro_frame)


func _near_lander() -> bool:
	return abs(_astro.x - LANDER_X) < 24.0


func _nearest_sample() -> int:
	var f: Dictionary = get_node("/root/MissionState").state.get("flight", {})
	var xs: Array = f.get("sample_x", [])
	var best := -1
	var best_d := PICK_DIST
	for i in xs.size():
		if f["collected"].has(i):
			continue
		var d: float = abs(float(xs[i]) - _astro.x)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Telemetry & captions -------------------------------------------------------

func _keys() -> Array:
	if t < S_ORBIT: return K_ASCENT
	if t < S_TLI: return K_ORBIT
	if t < S_MOON: return K_TLI
	if _profile == "flyby": return K_FLYBY
	if t < S_FINAL or _profile == "orbit": return K_LOI
	return K_DESCENT


func _captions() -> Array:
	if t < S_ORBIT: return C_ASCENT
	if t < S_TLI: return C_ORBIT
	if t < S_MOON: return C_TLI
	if _profile == "flyby": return C_FLYBY
	if t < S_FINAL: return C_LOI
	return C_SCIENCE if _profile == "orbit" else C_DESCENT


static func _interp(keys: Array, x: float, col: int) -> float:
	if x <= keys[0][0]:
		return keys[0][col]
	for i in range(1, keys.size()):
		if x <= keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			var u: float = (x - a[0]) / float(b[0] - a[0])
			return lerpf(a[col], b[col], u)
	return keys[-1][col]


static func _fmt_met(s: float) -> String:
	var sign := "T- " if s < 0 else "T+ "
	var v := int(abs(s))
	var days := v / 86400
	v %= 86400
	var hms := "%02d:%02d:%02d" % [v / 3600, (v % 3600) / 60, v % 60]
	return sign + ("%dd %s" % [days, hms] if days > 0 else hms)


static func _thousands(n: float) -> String:
	var s := str(int(round(n)))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _update_text() -> void:
	if mode == "surface":
		var f: Dictionary = get_node("/root/MissionState").state.get("flight", {})
		var got: int = f.get("collected", []).size()
		var left := int(f.get("t", 0.0))
		_telemetry.text = ("Sea of Tranquility  0.67°N 23.47°E\nGravity  1.62 m/s² (1/6 g)\nSurface  -173 to +127 °C, no air\n"
			+ "Samples  %d / %d    EVA time %d:%02d") % [got, D.MOON_SAMPLES.size(), left / 60, left % 60]
		var status := "Samples %d / %d · %d:%02d left" % [got, D.MOON_SAMPLES.size(), left / 60, left % 60]
		if _last_fact != "":
			_caption.text = _last_fact
		elif _controller:
			_caption.text = "A/D walk · W jump (1/6 g!) · E pick up a sample"
		else:
			_caption.text = "The astronaut is collecting samples on the Moon..."
		var i := _nearest_sample() if _controller else -1
		if i >= 0:
			_caption.text = "[E] Pick up: " + D.MOON_SAMPLES[i]["name"]
		elif _controller and _near_lander():
			_caption.text = "[E] Climb back into the lander and finish the moonwalk"
		_caption.text = status + "\n" + _caption.text
		return
	var keys := _keys()
	var met := _interp(keys, t, 1)
	var alt := _interp(keys, t, 2)
	var spd := _interp(keys, t, 3)
	var alt_name := "Altitude"
	if t >= S_TLI + 3.0 and t < S_MOON:
		alt_name = "From Earth"
	elif t >= S_MOON:
		alt_name = "Above Moon"
	var alt_txt := ("%.1f km" % alt) if alt < 1000.0 else (_thousands(alt) + " km")
	_telemetry.text = "%s\n%-10s %s\nSpeed      %s km/h\n%s" % [_fmt_met(met), alt_name, alt_txt, _thousands(spd),
		"Mission #%d · %s" % [mission.get("n", 1), mission.get("ship_name", "")]]
	var cap := ""
	for c in _captions():
		if t >= c[0]:
			cap = c[1]
	_caption.text = cap
	_caption.visible = cap != ""


# --- Drawing helpers ----------------------------------------------------------

func _draw() -> void:
	var k := minf(size.x / VW, size.y / VH)
	var off := (size - Vector2(VW, VH) * k) / 2.0
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	_base = Transform2D(0.0, Vector2(k, k), 0.0, off)
	draw_set_transform_matrix(_base)
	if mode == "surface":
		_draw_surface()
	elif t < S_ORBIT:
		_draw_ascent(t)
	elif t < S_TLI:
		_draw_earth_orbit(t - S_ORBIT)
	elif t < S_MOON:
		_draw_tli(t - S_TLI)
	elif t < S_FINAL or _profile != "landing" and _profile != "return":
		_draw_moon(t - S_MOON)
	else:
		_draw_descent(t - S_FINAL)
	_draw_particles()
	var fade := _fade_alpha()
	if fade > 0.0:
		draw_rect(Rect2(0, 0, VW, VH), Color(0, 0, 0, fade))
	draw_set_transform_matrix(Transform2D())


## Плавное затемнение на стыке сцен (подъём → орбита → перелёт → Луна → посадка).
func _fade_alpha() -> float:
	if mode != "flight":
		return 0.0
	var cuts := [S_ORBIT, S_TLI, S_MOON]
	if _profile == "landing" or _profile == "return":
		cuts.append(S_FINAL)
	var a := 0.0
	for c in cuts:
		a = maxf(a, 1.0 - clampf(abs(t - c) / FADE, 0.0, 1.0))
	return a


func _spr(tex: Texture2D, pos: Vector2, ang := 0.0, sc := 1.0, flip := false, mod := Color.WHITE) -> void:
	draw_set_transform_matrix(_base * Transform2D(ang, Vector2(-sc if flip else sc, sc), 0.0, pos))
	draw_texture(tex, -tex.get_size() / 2.0, mod)
	draw_set_transform_matrix(_base)


## Transform of the 48x216 rocket canvas: canvas point `pivot` lands on screen `pos`.
func _canvas_xf(pos: Vector2, ang: float, sc: float, pivot: Vector2) -> Transform2D:
	return Transform2D(ang, Vector2(sc, sc), 0.0, pos) * Transform2D(0.0, -pivot)


## Draw rocket parts on a shared canvas transform. `sep` maps part -> [offset, rotation]
## applied around that part's own centre (for parts drifting away after separation).
func _draw_parts(xf: Transform2D, parts: Array, sep := {}, mod := Color.WHITE) -> void:
	for name in parts:
		var tex: Texture2D = _part_tex(name)
		var pxf := xf
		if sep.has(name):
			var c: Vector2 = PART_CENTER[name]
			pxf = xf * Transform2D(sep[name][1], c + sep[name][0]) * Transform2D(0.0, -c)
		draw_set_transform_matrix(_base * pxf)
		draw_texture(tex, Vector2.ZERO, mod)
	draw_set_transform_matrix(_base)


func _part_tex(name: String) -> Texture2D:
	match name:
		"core": return P_CORE
		"icps": return P_ICPS
		"lvsa": return P_LVSA
		"orion": return P_ORION
		"fairing_L": return P_FAIR_L
		"fairing_R": return P_FAIR_R
		"las": return P_LAS
		"srb_L": return P_SRB_L
		"srb_R": return P_SRB_R
	return P_ARRAYS


## Animated plume strip (4 frames). The anchor (top centre) sits on `nozzle`
## in canvas coordinates; `rot` turns the plume around the nozzle.
func _plume(xf: Transform2D, strip: Texture2D, nozzle: Vector2, alpha := 1.0, rot := 0.0) -> void:
	if alpha <= 0.01:
		return
	var fw := strip.get_width() / 4.0
	var fh := strip.get_height()
	draw_set_transform_matrix(_base * xf * Transform2D(rot, nozzle))
	draw_texture_rect_region(strip, Rect2(-fw / 2.0, 0, fw, fh), Rect2(_fx_frame * fw, 0, fw, fh), Color(1, 1, 1, alpha))
	draw_set_transform_matrix(_base)


func _draw_stars(alpha: float, drift := 0.0) -> void:
	if alpha <= 0.0:
		return
	for s in _stars:
		var a := alpha * (0.4 + 0.6 * s.z)
		var x := fposmod(s.x - drift * (0.3 + s.z), VW)
		draw_rect(Rect2(floorf(x), floorf(s.y), 1, 1), Color(1, 1, 1, a))


func _draw_earth_limb(horizon: float, scroll: float) -> void:
	var r := 1400.0
	var c := Vector2(VW / 2.0, horizon + r)
	draw_circle(c, r + 5.0, Color(0.35, 0.6, 1.0, 0.35))
	draw_circle(c, r + 2.0, Color(0.55, 0.78, 1.0, 0.8))
	draw_circle(c, r, Color(0.16, 0.4, 0.78))
	for i in 9:
		var x := fposmod(i * 71.0 - scroll, VW + 120.0) - 60.0
		var y := horizon + 6.0 + (i % 3) * 9.0
		draw_rect(Rect2(floorf(x), floorf(y), 34 + (i % 4) * 9, 3), Color(0.9, 0.94, 1.0, 0.75))
		draw_rect(Rect2(floorf(x + 20), floorf(y + 14), 26, 4), Color(0.3, 0.6, 0.3, 0.85))


func _smoke(p: Vector2, v: Vector2, life: float, world: bool, size_idx := -1) -> void:
	var idx := size_idx if size_idx >= 0 else _rng.randi_range(0, PUFFS.size() - 1)
	_particles.append({"p": p, "v": v, "life": life, "max": life, "tex": idx, "world": world})


# --- Ascent (SLS pack) ----------------------------------------------------------

func _ascent_alt_px(lt: float) -> float:
	return 0.0 if lt < E_LIFTOFF else pow(lt - E_LIFTOFF, 2.0) * 6.0


func _draw_ascent(lt: float) -> void:
	var alt_km := _interp(K_ASCENT, lt, 2)
	var sky := Color(0.31, 0.55, 0.88).lerp(Color(0.01, 0.02, 0.07), clampf(alt_km / 60.0, 0.0, 1.0))
	draw_rect(Rect2(0, 0, VW, VH), sky)
	_draw_stars(clampf((alt_km - 25.0) / 30.0, 0.0, 1.0))
	var alt_px := _ascent_alt_px(lt)
	_cam = maxf(0.0, alt_px - 30.0)
	var pad_y := PAD_Y + _cam
	if lt > 11.0:
		_draw_earth_limb(lerpf(300.0, 205.0, smoothstep(11.0, 21.0, lt)), lt * 18.0)
	# cumulus clouds (smaller = farther)
	for c in _clouds:
		var y := pad_y + 243.0 - c.y
		if y > -30 and y < VH + 30:
			_spr(CLOUDS[int(c.z)], Vector2(c.x, y))
	# pad: far layers, tower, swing arms
	var pad_visible := pad_y < VH
	if pad_visible:
		_draw_ground(pad_y)
		draw_texture(PAD_FAR, Vector2(0, pad_y))
		draw_texture(PAD_TOWER, Vector2(0, pad_y))
		var arms := PAD_ARMS_ON if lt < E_LIFTOFF else (PAD_ARMS_SWING if lt < E_LIFTOFF + 0.4 else PAD_ARMS_OFF)
		draw_texture(arms, Vector2(0, pad_y))

	# rocket: pitch program and camera zoom-out like the Artemis I broadcast
	var ang := deg_to_rad(lerpf(0.0, 58.0, smoothstep(6.0, 18.0, lt)) + lerpf(0.0, 14.0, smoothstep(18.0, 25.0, lt)))
	var sc := lerpf(1.0, 0.5, smoothstep(7.0, 13.0, lt))
	var pivot_on_pad := PAD_ROCKET_TL + ROCKET_PIVOT + Vector2(0, pad_y - alt_px)
	var pos := pivot_on_pad.lerp(Vector2(250.0, 140.0), smoothstep(7.0, 13.0, lt))
	var xf := _canvas_xf(pos, ang, sc, ROCKET_PIVOT)
	var vac := smoothstep(10.0, 35.0, alt_km)   # low-altitude plume -> vacuum plume

	# plumes behind the rocket
	if lt >= 0.6 and lt < E_MECO:
		_plume(xf, FX_CORE, NOZZLE_CORE, 1.0 - vac)
		_plume(xf, FX_CORE_VAC, NOZZLE_CORE, vac)
	if lt >= E_LIFTOFF and lt < E_SRB_SEP:
		for n in [NOZZLE_SRB_L, NOZZLE_SRB_R]:
			_plume(xf, FX_SRB, n, 1.0 - vac)
			_plume(xf, FX_SRB_VAC, n, vac)

	var parts := ["core", "icps", "lvsa", "orion"]
	var sep := {}
	if lt < E_FAIRINGS + 4.0:
		parts.append_array(["fairing_L", "fairing_R"])
	if lt < E_LAS + 4.0:
		parts.append("las")
	if lt < E_SRB_SEP + 6.0:
		parts.append_array(["srb_L", "srb_R"])
	if lt >= E_SRB_SEP:
		var u := lt - E_SRB_SEP
		sep["srb_L"] = [Vector2(-u * 10.0, u * u * 9.0), -u * 0.35]
		sep["srb_R"] = [Vector2(u * 10.0, u * u * 9.0), u * 0.35]
		if u < 1.0: # booster separation motors at nose and skirt
			for side in [-1.0, 1.0]:
				var nx := 11.0 if side < 0.0 else 38.0
				for ny in [110.0, 204.0]:
					_plume(xf, FX_BSM, Vector2(nx + side * 6.0, ny), 1.0, side * PI / 2.0)
	if lt >= E_FAIRINGS:
		var u := lt - E_FAIRINGS
		sep["fairing_L"] = [Vector2(-u * 16.0, u * 8.0), -u * 2.0]
		sep["fairing_R"] = [Vector2(u * 16.0, u * 8.0), u * 2.0]
	if lt >= E_LAS:
		var u := lt - E_LAS
		sep["las"] = [Vector2(u * 6.0, -u * 45.0), u * 0.5]
		if u < 1.2:
			for s in [-1.0, 1.0]:
				_plume(xf, FX_LAS, Vector2(24.0 + u * 6.0, 26.0 - u * 45.0), 1.0, s * deg_to_rad(145.0))
	if lt >= E_CORE_SEP:
		var u := lt - E_CORE_SEP
		sep["core"] = [Vector2(0, u * 26.0), -u * 0.12]
		sep["lvsa"] = [Vector2(0, u * 26.0), -u * 0.12]
	_draw_parts(xf, parts, sep)

	# pad deck and mobile launcher base cover the nozzles and flame trench
	if pad_visible:
		draw_texture(PAD_PAD, Vector2(0, pad_y))
		draw_texture(PAD_BASE, Vector2(0, pad_y))

	# smoke: steam at the deck, exhaust out of the trench to the right, then a trail
	if lt > 0.6 and lt < 10.0:
		_smoke(Vector2(_rng.randf_range(200, 280), 243.0 + PAD_Y + _rng.randf_range(-6, 4)),
			Vector2(_rng.randf_range(-50, 50), _rng.randf_range(-14, -2)), 2.6, true)
		_smoke(Vector2(345.0 + _rng.randf_range(-6, 6), 262.0 + PAD_Y), Vector2(_rng.randf_range(40, 110), _rng.randf_range(-16, -4)), 2.8, true)
	elif lt >= 10.0 and lt < E_SRB_SEP:
		for n in [NOZZLE_SRB_L, NOZZLE_SRB_R]:
			var p: Vector2 = xf * (n + Vector2(0, 40))
			_smoke(p, xf.basis_xform(Vector2(_rng.randf_range(-10, 10), 70)), 1.2, false, _rng.randi_range(1, 4))


## Земля вокруг стартового стола (в паке её нет): полоса океана на горизонте,
## трава с полосами и дорога. Едет вниз вместе со столом, когда камера поднимается.
func _draw_ground(pad_y: float) -> void:
	var horizon := pad_y + 236.0
	draw_rect(Rect2(0, horizon - 3, VW, 3), Color(0.55, 0.72, 0.9))          # дымка
	draw_rect(Rect2(0, horizon, VW, 6), Color(0.2, 0.42, 0.66))               # Атлантика
	draw_rect(Rect2(0, horizon + 6, VW, 2), Color(0.85, 0.82, 0.7))           # пляж
	draw_rect(Rect2(0, horizon + 8, VW, VH + 400), Color(0.33, 0.55, 0.27))   # трава
	draw_rect(Rect2(0, horizon + 14, VW, 4), Color(0.29, 0.49, 0.24))
	draw_rect(Rect2(0, horizon + 26, VW, 5), Color(0.38, 0.6, 0.3))
	draw_rect(Rect2(0, pad_y + 280, VW, 3), Color(0.55, 0.53, 0.5))           # дорога у стола
	draw_rect(Rect2(0, pad_y + 283, VW, VH + 400), Color(0.3, 0.5, 0.24))


# --- Earth orbit ----------------------------------------------------------------

func _draw_earth_orbit(lt: float) -> void:
	_draw_stars(1.0, lt * 4.0)
	_draw_earth_limb(196.0, 300.0 + lt * 26.0)
	var pos := Vector2(240, 112)
	var xf := _canvas_xf(pos, PI / 2.0, 1.5, STACK_PIVOT)
	var parts := ["icps", "orion"]
	if lt >= 4.0:
		parts.append("arrays")
	if lt > 7.0 and lt < 9.0:
		_plume(xf, FX_RL10, NOZZLE_RL10)
	_draw_parts(xf, parts)


func _bezier(a: Vector2, b: Vector2, c: Vector2, u: float) -> Vector2:
	return a.lerp(b, u).lerp(b.lerp(c, u), u)


## Orion (with arrays), nose pointing along `dir`.
func _draw_orion(pos: Vector2, dir: Vector2, sc: float, with_icps := false, burn := false, mod := Color.WHITE) -> void:
	var xf := _canvas_xf(pos, dir.angle() + PI / 2.0, sc, STACK_PIVOT if with_icps else ORION_PIVOT)
	if burn:
		_plume(xf, FX_RL10, NOZZLE_RL10)
	_draw_parts(xf, ["icps", "orion", "arrays"] if with_icps else ["orion", "arrays"], {}, mod)


# Перелёт: один непрерывный путь без скачков.
#   0–3 с   виток по околоземной орбите, с 1.5 с — разгон RL10 (TLI)
#   3–11 с  перелётная дуга (кубическая Безье, касательные совпадают с орбитами);
#           быстро у Земли, медленно посередине, снова быстрее у Луны
#   11–12 с захват на окололунную орбиту
const TLI_EARTH := Vector2(90, 172)
const TLI_MOON := Vector2(392, 92)
const TLI_R_EARTH := 46.0
const TLI_R_MOON := 32.0
const TLI_W_EARTH := -1.2          # рад/с, против часовой стрелки
const TLI_EXIT_ANG := 0.93         # где корабль сходит с орбиты Земли
const TLI_ENTRY_ANG := PI + 0.64   # где выходит на орбиту Луны
const TLI_ORBIT_END := 3.0
const TLI_ARC_END := 11.0


func _tli_arc_points() -> Array:
	var p0 := TLI_EARTH + Vector2(cos(TLI_EXIT_ANG), sin(TLI_EXIT_ANG)) * TLI_R_EARTH
	var t0 := Vector2(sin(TLI_EXIT_ANG), -cos(TLI_EXIT_ANG))
	var p3 := TLI_MOON + Vector2(cos(TLI_ENTRY_ANG), sin(TLI_ENTRY_ANG)) * TLI_R_MOON
	var t3 := Vector2(-sin(TLI_ENTRY_ANG), cos(TLI_ENTRY_ANG))
	return [p0, p0 + t0 * 120.0, p3 - t3 * 70.0, p3]


static func _cubic(p: Array, u: float) -> Vector2:
	var v := 1.0 - u
	return p[0] * v * v * v + p[1] * 3.0 * v * v * u + p[2] * 3.0 * v * u * u + p[3] * u * u * u


## Положение и направление корабля в момент x (0..12 с сегмента перелёта).
func _tli_state(x: float) -> Array:
	if x < TLI_ORBIT_END:
		var a := TLI_EXIT_ANG + (x - TLI_ORBIT_END) * TLI_W_EARTH
		return [TLI_EARTH + Vector2(cos(a), sin(a)) * TLI_R_EARTH, Vector2(sin(a), -cos(a))]
	var pts := _tli_arc_points()
	if x < TLI_ARC_END:
		var u := (x - TLI_ORBIT_END) / (TLI_ARC_END - TLI_ORBIT_END)
		var s := u + 0.1 * sin(TAU * u)  # скорость: высокая у Земли и Луны, низкая посередине
		var p := _cubic(pts, s)
		return [p, _cubic(pts, minf(s + 0.005, 1.0)) - _cubic(pts, maxf(s - 0.005, 0.0))]
	var b := TLI_ENTRY_ANG + (x - TLI_ARC_END) * 1.15
	return [TLI_MOON + Vector2(cos(b), sin(b)) * TLI_R_MOON, Vector2(-sin(b), cos(b))]


func _draw_tli(lt: float) -> void:
	_draw_stars(1.0)
	_spr(TEX_EARTH, TLI_EARTH)
	_spr(TEX_MOON, TLI_MOON, 0.0, 0.8)
	# пройденный путь — ярко, впереди — едва заметно
	var x := 0.0
	while x <= D.T_TLI:
		var p: Vector2 = _tli_state(x)[0]
		var done := x <= lt
		if done or int(x / 0.12) % 3 == 0:
			draw_rect(Rect2(floorf(p.x), floorf(p.y), 1, 1), Color(0.6, 0.85, 1.0, 0.85) if done else Color(1, 1, 1, 0.18))
		x += 0.12
	var st := _tli_state(lt)
	# ICPS делает разгон (1.5–3 с) и отделяется от Orion после него
	_draw_orion(st[0], st[1], 0.45, lt < 4.0, lt > 1.5 and lt < TLI_ORBIT_END)


func _draw_moon(lt: float) -> void:
	_draw_stars(1.0)
	var c := Vector2(240, 140)
	_spr(TEX_EARTH, Vector2(430, 44), 0.0, 0.5)
	var ship: Vector2
	var dir: Vector2
	var behind := false
	if _profile == "flyby":
		var u := clampf(lt / D.T_MOON, 0.0, 1.0)
		var a := Vector2(20, 10)
		var b := Vector2(720, 140)
		var e := Vector2(20, 270)
		ship = _bezier(a, b, e, u)
		dir = _bezier(a, b, e, minf(u + 0.01, 1.0)) - ship
	else:
		var total := D.T_MOON + (D.T_ORBIT_SCIENCE if _profile == "orbit" else 0.0)
		var ang := -PI * 0.9 + lt / total * TAU * 1.3
		ship = c + Vector2(cos(ang) * 122.0, sin(ang) * 40.0)
		dir = Vector2(-sin(ang) * 122.0, cos(ang) * 40.0)
		behind = sin(ang) < 0.0
		for i in 64:
			var oa := i / 64.0 * TAU
			var p := c + Vector2(cos(oa) * 122.0, sin(oa) * 40.0)
			if sin(oa) > 0.0 or abs(cos(oa)) > 0.82:
				draw_rect(Rect2(floorf(p.x), floorf(p.y), 1, 1), Color(0.6, 0.85, 1.0, 0.45))
	if behind:
		_draw_orion(ship, dir, 0.5, false, false, Color(0.7, 0.7, 0.8))
	_spr(TEX_MOON, c, 0.0, 3.0)
	if not behind:
		_draw_orion(ship, dir, 0.5, false, lt < 3.0 and _profile != "flyby")
		if _profile == "orbit" and lt > D.T_MOON:
			draw_line(ship, ship.lerp(c, 0.55), Color(0.4, 1.0, 0.6, 0.6), 1.0)


# --- Lunar terrain (NASA LOLA profile) ----------------------------------------

func _ground_y(wx: float) -> float:
	var f := clampf(wx / WORLD_W, 0.0, 1.0) * (_heights.size() - 1)
	var i := int(f)
	var j := mini(i + 1, _heights.size() - 1)
	var h := lerpf(_heights[i], _heights[j], f - i)
	var y := 222.0 - h * 46.0
	for cr in _craters:
		var d: float = abs(wx - cr.x)
		if d < cr.y:
			y += (1.0 - pow(d / cr.y, 2.0)) * cr.y * 0.35 # bowl-shaped crater
	return y


func _draw_terrain(cam_x: float, sky_earth: bool) -> void:
	_draw_stars(1.0)
	if sky_earth:
		_spr(TEX_EARTH, Vector2(380 - cam_x * 0.05, 46), 0.0, 0.5)
	var x := 0
	while x < int(VW):
		var wx := cam_x + x
		var y := floorf(_ground_y(wx))
		draw_rect(Rect2(x, y, 2, VH - y), Color(0.42, 0.42, 0.43))
		draw_rect(Rect2(x, y + 10, 2, VH - y), Color(0.34, 0.34, 0.35))
		draw_rect(Rect2(x, y, 2, 1), Color(0.72, 0.72, 0.7))
		if int(wx) % 13 == 0:
			draw_rect(Rect2(x, y + 4 + int(wx) % 7, 1, 1), Color(0.55, 0.55, 0.55))
		x += 2


func _flame(pos: Vector2, ang: float, length: float, width: float) -> void:
	draw_set_transform_matrix(_base * Transform2D(ang, pos))
	var l := length * _rng.randf_range(0.8, 1.15)
	draw_colored_polygon(PackedVector2Array([Vector2(-width, 0), Vector2(width, 0), Vector2(0, l)]), Color(1.0, 0.45, 0.1, 0.9))
	draw_colored_polygon(PackedVector2Array([Vector2(-width * 0.6, 0), Vector2(width * 0.6, 0), Vector2(0, l * 0.65)]), Color(1.0, 0.85, 0.3))
	draw_set_transform_matrix(_base)


func _draw_descent(lt: float) -> void:
	var land_x := LANDER_X
	var cam_x := land_x - 240.0
	_draw_terrain(cam_x, true)
	var u := clampf(lt / D.T_DESCENT, 0.0, 1.0)
	var gy := _ground_y(land_x) - 12.0
	var start := Vector2(-30, 20)
	var e := Vector2(240, gy)
	var p := Vector2(lerpf(start.x, e.x, 1.0 - pow(1.0 - u, 2.2)), lerpf(start.y, e.y, smoothstep(0.0, 1.0, u)))
	var ang := lerpf(-1.2, 0.0, smoothstep(0.45, 0.8, u))
	if u < 0.99:
		_flame(Transform2D(ang, p) * Vector2(0, 7), ang, 10.0 + _rng.randf() * 4.0, 2.0)
	_spr(TEX_LANDER, p, ang)
	if gy - p.y < 50.0 and u < 0.99:
		for i in 2:
			_particles.append({"p": Vector2(p.x + _rng.randf_range(-10, 10), gy + 12), "v": Vector2(_rng.randf_range(-90, 90), _rng.randf_range(-12, -2)), "life": 0.8, "max": 0.8, "world": false, "gray": true})


func _draw_surface() -> void:
	var cam_x := clampf(_astro.x - 240.0, 0.0, WORLD_W - VW)
	_draw_terrain(cam_x, true)
	_spr(TEX_LANDER, Vector2(LANDER_X - cam_x, _ground_y(LANDER_X) - 12.0))
	var fx := LANDER_X + 40.0 - cam_x
	var fy := _ground_y(LANDER_X + 40.0)
	draw_rect(Rect2(fx, fy - 20, 1, 20), Color(0.8, 0.8, 0.8))
	draw_rect(Rect2(fx + 1, fy - 20, 10, 6), Color(0.85, 0.2, 0.2))
	draw_rect(Rect2(fx + 1, fy - 20, 4, 3), Color(0.2, 0.3, 0.8))
	var f: Dictionary = get_node("/root/MissionState").state.get("flight", {})
	var xs: Array = f.get("sample_x", [])
	var bob := sin(Time.get_ticks_msec() / 250.0)
	for i in xs.size():
		if f["collected"].has(i):
			continue
		var sx: float = float(xs[i]) - cam_x
		if sx < -20 or sx > VW + 20:
			continue
		var sy := _ground_y(float(xs[i])) - 6.0
		draw_circle(Vector2(sx, sy), 7.0 + bob, Color(1, 0.9, 0.3, 0.18))
		var icon: int = D.MOON_SAMPLES[i]["icon"]
		draw_texture_rect_region(TEX_SAMPLES, Rect2(sx - 5, sy - 5, 10, 10), Rect2(icon * 10, 0, 10, 10))
	var ap := Vector2(_astro.x - cam_x, _astro.y - 9.0)
	draw_set_transform_matrix(_base * Transform2D(0.0, Vector2(-1.0 if _astro_flip else 1.0, 1.0), 0.0, ap))
	draw_texture_rect_region(TEX_ASTRO, Rect2(-6, -9, 12, 18), Rect2(_astro_frame * 12, 0, 12, 18))
	draw_set_transform_matrix(_base)


# --- Particles (smoke puffs, lunar dust) ---------------------------------------

func _dust(p: Vector2, n: int) -> void:
	for i in n:
		_particles.append({"p": p, "v": Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-12, -3)), "life": 0.7, "max": 0.7, "world": false, "gray": true, "surface": true})


func _update_particles(delta: float) -> void:
	var keep: Array = []
	for p in _particles:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		p["p"] += p["v"] * delta
		if p.get("gray", false):
			p["v"].y += 25.0 * delta
		else:
			p["v"] *= 0.97
		keep.append(p)
	_particles = keep.slice(maxi(0, keep.size() - 400))


func _draw_particles() -> void:
	var cam := _cam if mode == "flight" and t < S_ORBIT else 0.0
	var cam_x := clampf(_astro.x - 240.0, 0.0, WORLD_W - VW)
	for p in _particles:
		var a: float = p["life"] / p["max"]
		var pos: Vector2 = p["p"]
		if p.get("world", false):
			pos.y += cam
		if p.get("surface", false):
			pos.x -= cam_x
		if p.get("gray", false):
			draw_rect(Rect2(floorf(pos.x), floorf(pos.y), 1, 1), Color(0.7, 0.7, 0.68, a))
		else:
			var tex: Texture2D = PUFFS[p["tex"]]
			# puffs grow as they age
			var grow := 1.0 + (1.0 - a) * 0.8
			var s := tex.get_size() * grow
			draw_texture_rect(tex, Rect2(pos - s / 2.0, s), false, Color(1, 1, 1, 0.9 * a))
