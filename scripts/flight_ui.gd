extends CanvasLayer

signal closed
signal prep_requested

const F = preload("res://scripts/flight_data.gd")
const T = preload("res://scripts/trajectory.gd")
const D = preload("res://scripts/mission_data.gd")
const FlightMap = preload("res://scripts/flight_map.gd")
const MoonSites = preload("res://scripts/moon_sites.gd")

const C_TITLE := Color.WHITE
const C_TEXT := Color(0.875, 0.875, 0.875)
const C_DIM := Color(0.6, 0.6, 0.6)
const PHASE_NAMES := {
	"tli": "in parking orbit, waiting for the burn", "coast": "en route to the Moon", "return": "returning to Earth",
	"orbit": "in lunar orbit", "site": "in lunar orbit, choosing a landing site", "landing": "landing",
}

var role := "dispatcher"

var _ms: Node
var _title: Label
var _map: Control
var _sites: Control
var _side: VBoxContainer
var _info: RichTextLabel
var _exec: Button
var _angle_lbl: Label
var _dv_lbl: Label
var _astro: TextureRect
var _sources: PanelContainer
var _phase := ""
var _theta := 0.0
var _dv := F.DV_START
var _traj: Dictionary = {}
var _plan_key := ""
var _site := ""
var _t := 0.0
var _info_timer := 0.0
var _time := 0.0


func _ready() -> void:
	layer = 8
	_ms = get_node("/root/MissionState")
	_build()
	var fl: Dictionary = _ms.state["flight"]
	if not fl.is_empty():
		_theta = float(fl["phi0"]) + PI
		_t = float(fl["t"])
	_ms.changed.connect(_on_changed)
	_on_changed()


func is_open() -> bool:
	return get_child(0).visible


func set_open(v: bool) -> void:
	for c in get_children():
		c.visible = v
	if v:
		_on_changed()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.06, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_right = -10
	root.offset_top = 8
	root.offset_bottom = -48
	root.add_theme_constant_override("separation", 6)
	bg.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	root.add_child(head)
	_title = _lbl("", 18, C_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	head.add_child(_btn("NASA sources", func(): _sources.visible = not _sources.visible))
	if role == "dispatcher":
		head.add_child(_btn("Launch prep", func(): prep_requested.emit()))
	head.add_child(_btn("Close [E]", func(): closed.emit()))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	root.add_child(body)
	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_map = FlightMap.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.theta_picked.connect(func(a: float):
		_theta = a
		_recompute())
	left.add_child(_map)
	_sites = MoonSites.new()
	_sites.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sites.visible = false
	_sites.site_selected.connect(_select_site)
	left.add_child(_sites)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 6)
	scroll.add_child(_side)
	_sources = PanelContainer.new()
	_sources.set_anchors_preset(Control.PRESET_CENTER)
	_sources.offset_left = -330
	_sources.offset_right = 330
	_sources.offset_top = -200
	_sources.offset_bottom = 200
	_sources.visible = false
	bg.add_child(_sources)
	var sv := VBoxContainer.new()
	_sources.add_child(sv)
	sv.add_child(_lbl("Where the mini-game data comes from", 18, C_TITLE))
	for s in F.SOURCES:
		sv.add_child(_lbl("· " + s, 13, C_TEXT))
	sv.add_child(_btn("Close", func(): _sources.visible = false))


func _on_changed() -> void:
	var fl: Dictionary = _ms.state["flight"]
	if fl.is_empty():
		return
	_title.text = "%s: mission #%d '%s' · %s · %s" % [
		"Mission Control" if role == "dispatcher" else "On board", fl["n"], fl["ship_name"], fl["profile_name"], PHASE_NAMES.get(fl["phase"], "")]
	_map.phi0 = fl["phi0"]
	_map.hazards = fl["hazards"]
	_map.phase = fl["phase"]
	_map.orbit_alt = float(fl["sum"].get("peri_alt", 0.0))
	if not fl["plan"].is_empty():
		var key := "%f|%f" % [fl["plan"]["theta"], fl["plan"]["dv"]]
		if key != _plan_key:
			_plan_key = key
			_traj = T.simulate(fl["phi0"], fl["plan"]["theta"], fl["plan"]["dv"], fl["hazards"])
	if fl["phase"] != _phase:
		_phase = fl["phase"]
		_rebuild_side(fl)
	_sites.visible = role == "dispatcher" and _phase in ["site", "landing"]
	_map.visible = not _sites.visible
	_update_marks(fl)
	_update_info()


func _process(delta: float) -> void:
	_time += delta
	var fl: Dictionary = _ms.state["flight"]
	if fl.is_empty() or not get_child(0).visible:
		return
	var server_t := float(fl["t"])
	if _phase in ["coast", "return"]:
		_t += delta * F.DAY / F.SIM_DAY_REAL
		if absf(_t - server_t) > 0.25 * F.DAY:
			_t = server_t
		else:
			_t = lerpf(_t, server_t, 0.05)
	else:
		_t = server_t
	if _phase != "tli" or role != "dispatcher":
		_map.mode = "view"
		_map.traj = _traj
		_map.t_now = _t
	if _astro != null:
		_astro.position.y = 6.0 * sin(_time * 1.3)
		_astro.rotation = 0.08 * sin(_time * 0.7)
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 0.2
		_update_info()


func _rebuild_side(fl: Dictionary) -> void:
	for c in _side.get_children():
		c.queue_free()
	_exec = null
	_angle_lbl = null
	_dv_lbl = null
	_astro = null
	if role == "dispatcher" and _phase == "tli":
		_side.add_child(_lbl("Step 1. Translunar injection (TLI)", 17, C_TITLE))
		_side.add_child(_lbl("The ship is in a 185 km parking orbit. Pick the burn point on the orbit and the Δv impulse so the ship meets the Moon: it keeps moving and covers almost 40° in 3 days.", 13, C_DIM))
		_angle_lbl = _lbl("", 15, C_TEXT)
		_side.add_child(_angle_lbl)
		var ar := HBoxContainer.new()
		for step in [-5.0, -0.5, -0.05, 0.05, 0.5, 5.0]:
			ar.add_child(_btn(_signed(step) + "°", _turn.bind(deg_to_rad(step))))
		_side.add_child(ar)
		_dv_lbl = _lbl("", 15, C_TEXT)
		_side.add_child(_dv_lbl)
		var dr := HBoxContainer.new()
		for step in [-0.05, -0.01, -0.001, 0.001, 0.01, 0.05]:
			dr.add_child(_btn(_signed(step), _push.bind(step)))
		_side.add_child(dr)
		_side.add_child(_lbl("Keys: A/D burn point, W/S Δv, Shift finer, Ctrl coarser, Enter execute. Click near Earth to pick a point.", 12, C_DIM))
		_info = _rich()
		_side.add_child(_info)
		_exec = _btn("EXECUTE BURN [Enter]", _execute)
		_exec.custom_minimum_size = Vector2(0, 44)
		_side.add_child(_exec)
		_map.mode = "plan"
		_recompute()
	elif role == "dispatcher" and _phase == "site":
		_side.add_child(_lbl("Step 3. Landing site", 17, C_TITLE))
		_side.add_child(_lbl("The ship is in lunar orbit. Choose a site using NASA criteria: slope, sunlight, Earth visibility, science target. Mind the engineer's damage report!", 13, C_DIM))
		_info = _rich()
		_side.add_child(_info)
		_exec = _btn("LAND [Enter]", _land)
		_exec.custom_minimum_size = Vector2(0, 44)
		_side.add_child(_exec)
		var grid := GridContainer.new()
		grid.columns = 2
		for id in F.SITE_ORDER:
			var b := _btn(F.SITES[id]["name"], _select_site.bind(id))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.clip_text = true
			grid.add_child(b)
		_side.add_child(grid)
	else:
		var head: String = PHASE_NAMES.get(_phase, "")
		_side.add_child(_lbl(head.left(1).to_upper() + head.substr(1), 17, C_TITLE))
		if role == "astronaut":
			var cam := PanelContainer.new()
			cam.custom_minimum_size = Vector2(0, 220)
			var holder := Control.new()
			cam.add_child(holder)
			var at := AtlasTexture.new()
			at.atlas = load("res://assets/astro1.png")
			at.region = Rect2(0, 0, 48, 48)
			_astro = TextureRect.new()
			_astro.texture = at
			_astro.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_astro.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_astro.size = Vector2(192, 192)
			_astro.pivot_offset = Vector2(96, 96)
			holder.add_child(_astro)
			holder.resized.connect(func():
				if is_instance_valid(_astro):
					_astro.position.x = (holder.size.x - 192.0) * 0.5)
			_side.add_child(_lbl("Cabin camera: zero gravity", 12, C_DIM))
			_side.add_child(cam)
		_info = _rich()
		_side.add_child(_info)
		if role == "dispatcher" and _phase == "landing":
			_sites.selected = fl["site"]


func _update_marks(fl: Dictionary) -> void:
	if role != "dispatcher":
		return
	var marks := {}
	for id in F.SITE_ORDER:
		var bad: bool = T.crash_risk(id, fl["reported"]) > 0.0
		for b in fl["reported"]:
			if not T.site_req_ok(b, id):
				bad = true
		if bad:
			marks[id] = "bad"
		elif _fits_priority(fl, id) != "":
			marks[id] = "star"
	_sites.marks = marks
	var landed := []
	for m in MissionState.state.get("launched", []):
		if m.get("site_id", "") != "" and not landed.has(m["site_id"]):
			landed.append(m["site_id"])
	_sites.flags = landed


func _fits_priority(fl: Dictionary, site_id: String) -> String:
	for p in fl["prio"]:
		var tag: String = F.PRIORITIES[p]["site_tag"]
		if tag == "" or not F.SITES[site_id]["tags"].has(tag):
			continue
		for m in F.PRIORITIES[p]["modules"]:
			if fl["cargo"].has(m) and D.MODULES[m]["kind"] in ["surface", "samples"]:
				return F.PRIORITIES[p]["name"]
	return ""


func _turn(step: float) -> void:
	_theta = wrapf(_theta + step, 0.0, TAU)
	_recompute()


func _push(step: float) -> void:
	_dv = clampf(snappedf(_dv + step, 0.001), F.DV_MIN, F.DV_MAX)
	_recompute()


func _recompute() -> void:
	var fl: Dictionary = _ms.state["flight"]
	if fl.is_empty() or _phase != "tli" or role != "dispatcher":
		return
	_traj = T.simulate(fl["phi0"], _theta, _dv, fl["hazards"])
	_map.mode = "plan"
	_map.theta = _theta
	_map.traj = _traj
	_map.t_now = 0.0
	_update_info()


func _execute() -> void:
	if _exec != null and not _exec.disabled:
		_ms.request("flight_tli", [_theta, _dv])


func _select_site(id: String) -> void:
	_site = id
	_sites.selected = id
	_update_info()


func _land() -> void:
	if _site != "" and _exec != null and not _exec.disabled:
		_ms.request("flight_site", [_site])


func _unhandled_input(event: InputEvent) -> void:
	if not get_child(0).visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if role != "dispatcher" or not (event is InputEventKey and event.pressed):
		return
	var k: InputEventKey = event
	var fine := k.shift_pressed
	var coarse := k.ctrl_pressed
	var handled := true
	match k.physical_keycode:
		KEY_A, KEY_LEFT:
			_turn(-deg_to_rad(0.05 if fine else (5.0 if coarse else 0.5)))
		KEY_D, KEY_RIGHT:
			_turn(deg_to_rad(0.05 if fine else (5.0 if coarse else 0.5)))
		KEY_W, KEY_UP:
			_push(0.001 if fine else (0.05 if coarse else 0.01))
		KEY_S, KEY_DOWN:
			_push(-(0.001 if fine else (0.05 if coarse else 0.01)))
		KEY_ENTER, KEY_KP_ENTER:
			if _phase == "tli":
				_execute()
			elif _phase == "site":
				_land()
		_:
			handled = false
	if handled and _phase in ["tli", "site"]:
		get_viewport().set_input_as_handled()


func _update_info() -> void:
	var fl: Dictionary = _ms.state["flight"]
	if fl.is_empty() or _info == null or not is_instance_valid(_info):
		return
	if role == "dispatcher" and _phase == "tli":
		_info.text = _tli_text(fl)
	elif role == "dispatcher" and _phase == "site":
		_info.text = _site_text(fl)
	else:
		_info.text = _telemetry_text(fl)


func _tli_text(fl: Dictionary) -> String:
	if _traj.is_empty():
		return ""
	_angle_lbl.text = "Burn point: %.2f°  (Moon: %.1f°)" % [rad_to_deg(wrapf(_theta, 0.0, TAU)), rad_to_deg(wrapf(fl["phi0"], 0.0, TAU))]
	_dv_lbl.text = "Δv impulse: %.3f km/s" % _dv
	var ev := T.evaluate(_traj, fl["profile"], _dv, fl["budget"], fl["hazards"])
	_exec.disabled = not ev["ok"]
	var s := ""
	var peri: float = _traj["peri_alt"]
	if _traj["status"] == "impact":
		s += "Closest approach: [color=#ff6b61]COLLISION with the Moon[/color]\n"
	elif peri > F.PERI_REACH:
		s += "Closest approach: [color=#ff6b61]miss, %s km[/color]\n" % _num(peri)
	else:
		var col := "#7ef08c" if peri >= F.PERI_SAFE_MIN and peri <= F.PERI_GOOD_MAX else "#ffd23f"
		s += "Closest approach: [color=%s]%s km above the Moon[/color]\n" % [col, _num(peri)]
		s += "Transit: %.2f days\n" % T.transit_days(_traj)
		s += "Free return: %s\n" % ("[color=#7ef08c]yes, the Moon will swing the ship back to Earth[/color]" if _traj["free_return"] else "[color=#ffb347]no[/color]")
		if fl["profile"] != "flyby":
			s += "Lunar orbit insertion (LOI): %.2f km/s\n" % maxf(float(_traj["loi_dv"]), 0.0)
	var ok_dv: bool = ev["dv_total"] <= float(fl["budget"]) + 0.0005
	s += "Total Δv: [color=%s]%.2f of %.2f km/s[/color] (spare fuel gives more)\n" % ["#7ef08c" if ok_dv else "#ff6b61", ev["dv_total"], fl["budget"]]
	for e in ev["errors"]:
		s += "[color=#ff6b61]✗ %s[/color]\n" % e
	for w in ev["warns"]:
		s += "[color=#ffd23f]⚠ %s[/color]\n" % w
	s += "\n[b]Engineer's report[/b]\n"
	if not fl["weak_sent"]:
		s += "[color=#999999]The engineer hasn't sent a report, the ship's weak points are unknown.[/color]\n"
	elif fl["weak"].is_empty():
		s += "No weak points.\n"
	else:
		for id in fl["weak"]:
			var f: Dictionary = F.FAULTS[id]
			if f["kind"] == "trajectory":
				var ok := T.traj_req_ok(id, _traj)
				s += "[color=%s]%s %s (%s): needs %s[/color]\n" % ["#7ef08c" if ok else "#ff6b61", "✓" if ok else "✗", f["name"], f["weak"], f["need"]]
			else:
				s += "· %s (%s): keep it in mind when choosing a landing site\n" % [f["name"], f["weak"]]
	s += "\n[color=#9fb4ff]Hint: %s[/color]" % T.hint(_traj)
	return s


func _site_text(fl: Dictionary) -> String:
	_exec.disabled = _site == ""
	var known: Array = fl["reported"]
	var s := ""
	if known.is_empty():
		s += "[color=#999999]No damage in the engineer's report%s.[/color]\n" % ("" if fl["weak_sent"] else " (the engineer hasn't sent anything yet)")
	else:
		s += "[b]Damage per the engineer's report:[/b]\n"
		for id in known:
			s += "[color=#ff6b61]✗ %s: %s → needs %s[/color]\n" % [F.FAULTS[id]["name"], F.FAULTS[id]["broken"], F.FAULTS[id]["need"]]
	if _site == "":
		return s + "\nPick a site on the map or in the list. Yellow markers fit NASA priorities, red ones are dangerous."
	var st: Dictionary = F.SITES[_site]
	s += "\n[b]%s[/b] [color=#999999](%s)[/color]\n%s\n" % [st["name"], st["note"], st["desc"]]
	var slope_lim := F.SLOPE_LIMIT_RADAR if known.has("radar") else F.SLOPE_LIMIT
	s += "[color=%s]Slope %d° (limit ≤ %d°)[/color]\n" % ["#7ef08c" if float(st["slope"]) <= slope_lim else "#ff6b61", st["slope"], roundi(slope_lim)]
	s += "[color=%s]Sunlight %d%% of the time[/color]\n" % ["#ff6b61" if known.has("power") and not T.site_req_ok("power", _site) else "#dddddd", st["light"]]
	s += "[color=%s]Earth visible %d%% of the time (comms)[/color]\n" % ["#ff6b61" if known.has("comms") and not T.site_req_ok("comms", _site) else "#dddddd", st["earth"]]
	s += "Science: %s\n" % F.site_tags_text(_site)
	var prio := _fits_priority(fl, _site)
	if prio != "":
		s += "[color=#ffd23f]★ Fits NASA priority '%s'[/color]\n" % prio
	var risk := T.crash_risk(_site, known)
	s += "Landing crash risk: [color=%s]%d%%[/color]\n" % ["#7ef08c" if risk == 0.0 else "#ff6b61", roundi(risk * 100)]
	return s


func _telemetry_text(fl: Dictionary) -> String:
	var s := ""
	var t := _t
	s += "Flight time: %d d %02d h\n" % [int(t / F.DAY), int(fmod(t, F.DAY) / 3600.0)]
	if not _traj.is_empty() and _phase in ["coast", "return"]:
		var p := T.sample(_traj, "pts", t)
		s += "To Earth: %s km\n" % _num(maxf(p.length() - F.R_EARTH, 0.0))
		s += "To the Moon: %s km\n" % _num(maxf(p.distance_to(T.moon_pos(fl["phi0"], t)) - F.R_MOON, 0.0))
		s += "Speed: %.2f km/s\n" % T.speed_at(_traj, t)
		if _phase == "coast":
			s += "Time to the Moon: %.1f days\n" % maxf((float(fl["sum"]["peri_t"]) - t) / F.DAY, 0.0)
	match _phase:
		"tli":
			s += "\nMission Control is calculating the burn to the Moon. Hold on!"
		"orbit":
			s += "\nThe ship is in lunar orbit, instruments are collecting data."
		"site":
			s += "\nMission Control is choosing a landing site."
		"landing":
			s += "\nThe lander is descending: %s." % F.SITES.get(fl["site"], {"name": "?"})["name"]
	var faults: Array = fl["faults"] if role == "astronaut" else []
	if role == "dispatcher":
		for id in fl["reported"]:
			faults.append({"id": id, "cause": "per the engineer's report"})
	if not faults.is_empty():
		s += "\n\n[b]Alarms on board:[/b]\n"
		for f in faults:
			s += "[color=#ff6b61]⚠ %s — %s[/color]\n" % [F.FAULTS[f["id"]]["name"], F.FAULTS[f["id"]]["broken"]]
	elif role == "dispatcher" and fl["faults"].size() > 0:
		s += "\n\n[color=#ffd23f]⚠ Something happened on board, waiting for the engineer's report.[/color]"
	if role == "astronaut" and _in_hazard(fl):
		s += "\n\n[color=#ff6b61]Meteor shower outside! Hold on tight.[/color]"
	return s


func _in_hazard(fl: Dictionary) -> bool:
	if _traj.is_empty() or _phase not in ["coast", "return"]:
		return false
	var p := T.sample(_traj, "pts", _t)
	for h in fl["hazards"]:
		if p.distance_to(T.hazard_pos(h, _t)) < float(h["r"]):
			return true
	return false


func _signed(v: float) -> String:
	return ("+" if v > 0.0 else "−") + str(absf(v))


func _num(v: float) -> String:
	var s := str(roundi(v))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _lbl(text: String, fsize: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", 14)
	r.add_theme_font_size_override("bold_font_size", 15)
	return r


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b
