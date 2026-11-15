extends CanvasLayer
## Интерфейс подготовки к полёту: нижняя панель ресурсов, сообщения,
## окна рабочих мест (по одному на роль), полёт к Луне и итоги.

const D = preload("res://scripts/mission_data.gd")
const FlightView = preload("res://scripts/flight_view.gd")

const C_TITLE := Color.WHITE
const C_TEXT := Color(0.875, 0.875, 0.875)
const C_DIM := Color(0.6, 0.6, 0.6)
const C_GOOD := Color(0.45, 0.95, 0.55)
const C_BAD := Color(1.0, 0.42, 0.38)

const STATION_TITLES := {
	"analyst": "Finance Office — Analyst",
	"engineer": "Workshop — Engineer",
	"astronaut": "Loading Airlock — Astronaut",
	"dispatcher": "Mission Control — Flight Dispatcher",
}

var _ms: Node
var _hud_label: RichTextLabel
var _countdown_label: Label
var _toasts: VBoxContainer
var _panel: PanelContainer
var _panel_title: Label
var _content: VBoxContainer
var _scroll: ScrollContainer
var _role := ""
var _last_key := ""
var _launch_view: Control # карточка последнего полёта
var _flight: Control      # полноэкранный полёт


func _ready() -> void:
	layer = 5
	_ms = get_node("/root/MissionState")
	_build_hud()
	_build_panel()
	_ms.changed.connect(_on_changed)
	_ms.notified.connect(toast)
	_ms.launch_started.connect(_start_flight)
	_ms.flight_finished.connect(_end_flight)
	_ms.campaign_finished.connect(_show_final)
	_on_changed()


func _unhandled_input(event: InputEvent) -> void:
	if _panel.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		close_station()
		get_viewport().set_input_as_handled()


# --- Окно станции -------------------------------------------------------------

func open_station(role: String) -> void:
	if is_instance_valid(_flight):
		return
	_role = role
	_last_key = ""
	_panel_title.text = STATION_TITLES.get(role, role)
	_panel.visible = true
	HighLevelNetworkHandler.input_locked = true
	_rebuild()


func close_station() -> void:
	_panel.visible = false
	_role = ""
	# снимаем блок на кадр позже, чтобы та же клавиша E не открыла окно снова
	(func(): HighLevelNetworkHandler.input_locked = is_instance_valid(_flight)).call_deferred()


func is_open() -> bool:
	return _panel.visible or is_instance_valid(_flight)


func _on_changed() -> void:
	_update_hud()
	if _panel.visible:
		# Перестраиваем окно только если поменялось что-то кроме таймеров.
		var st: Dictionary = _ms.state.duplicate()
		st.erase("time_left")
		st.erase("countdown")
		st.erase("flight")
		var key := var_to_str(st)
		if key != _last_key:
			_last_key = key
			_rebuild()


func _rebuild() -> void:
	var scroll_pos := _scroll.scroll_vertical
	for c in _content.get_children():
		c.queue_free()
	var st: Dictionary = _ms.state
	if st["over"]:
		_content.add_child(_lbl("Campaign over. Data collected: %d" % st["total_data"], 20, C_TITLE))
	else:
		match _role:
			"analyst": _build_analyst(st)
			"engineer": _build_engineer(st)
			"astronaut": _build_astronaut(st)
			"dispatcher": _build_dispatcher(st)
	(func(): _scroll.scroll_vertical = scroll_pos).call_deferred()


# --- Аналитик ----------------------------------------------------------------

func _build_analyst(st: Dictionary) -> void:
	_content.add_child(_lbl("Money: %d M$   (income +%d M$ per day)" % [st["money"], D.MONEY_INCOME], 18, C_TITLE))
	_section("Buy metal for the engineer — %.2f M$/t" % st["metal_price"])
	var row := _hbox()
	for amount in [5, 10, 20]:
		var cost := ceili(amount * st["metal_price"])
		row.add_child(_btn("+%d t  (%d M$)" % [amount, cost], _req.bind("buy_metal", [amount]), st["money"] < cost))
	var gain := 5 + int(st["total_data"] / 20)
	row.add_child(_btn("Sponsor report (+%d M$)" % gain, _req.bind("report", []), st["daily_used"].has("report"),
		"Once per day. The more data already sent, the more money."))
	_content.add_child(row)

	_section("Hangar")
	if st["ship"] == "":
		_content.add_child(_lbl("Empty. Buy a ship — without it the astronaut can't load and the dispatcher can't fuel.", 14, C_DIM))
	else:
		var s: Dictionary = D.SHIPS[st["ship"]]
		_content.add_child(_lbl("%s — %s" % [s["name"], _ship_line(st["ship"])], 15, C_TEXT))
		var refund := roundi(st.get("ship_paid", s["cost"]) * D.SELL_SHIP_REFUND)
		_content.add_child(_btn("Sell for %d M$ (cargo and fuel go back to storage)" % refund,
			_req.bind("sell_ship", []), st["launching"]))

	_section("Ship catalog")
	for id in D.SHIP_ORDER:
		var s: Dictionary = D.SHIPS[id]
		var cost := D.ship_cost(id, st)
		var card := _card()
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title: String = s["name"]
		var title_color := C_TEXT
		if cost < s["cost"]:
			title += "   SALE! %d → %d M$" % [s["cost"], cost]
			title_color = C_GOOD
		v.add_child(_lbl(title, 16, title_color))
		v.add_child(_lbl(_ship_line(id), 13, C_TITLE))
		v.add_child(_lbl(s["desc"], 13, C_DIM))
		card.get_child(0).add_child(v)
		var b := _btn("Buy\n%d M$" % cost, _req.bind("buy_ship", [id]), st["ship"] != "" or st["money"] < cost)
		b.custom_minimum_size = Vector2(110, 0)
		card.get_child(0).add_child(b)
		_content.add_child(card)


func _ship_line(id: String) -> String:
	var s: Dictionary = D.SHIPS[id]
	return "Thrust %d · Payload %d t · Tank %d t · Dry mass %d t" % [s["power"], s["payload"], s["tank"], s["dry"]]


# --- Инженер -----------------------------------------------------------------

func _build_engineer(st: Dictionary) -> void:
	_content.add_child(_lbl("Metal: %d t   (deliveries +%d t per day)" % [st["metal"], D.METAL_INCOME], 18, C_TITLE))
	if st["event"] in ["strike", "breakthrough"]:
		_content.add_child(_lbl(_ms.event_text(), 14, C_BAD if st["event"] == "strike" else C_GOOD))
	_content.add_child(_btn("Collect scrap metal (+4…10 t, once per day)", _req.bind("salvage", []), st["daily_used"].has("salvage")))
	_section("Rocket modules")
	var groups := [
		["Science instruments — orbit", ["orbital"]],
		["Science instruments — surface", ["surface", "samples"]],
		["Support", ["antenna", "solar"]],
		["Rocket upgrades", ["booster", "tank", "composite"]],
		["Crew", ["crew"]],
	]
	for g in groups:
		_content.add_child(_lbl(g[0], 15, C_DIM))
		for id in D.MODULE_ORDER:
			var m: Dictionary = D.MODULES[id]
			if not g[1].has(m["kind"]):
				continue
			var cost := D.module_cost(id, st["event"])
			var have: int = st["warehouse"].get(id, 0)
			var card := _card()
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var stats := "%.1f t" % m["mass"]
			if m["data"] > 0:
				stats += " · data %d" % m["data"]
			v.add_child(_lbl("%s   [%s]%s" % [m["name"], stats, ("   in storage: %d" % have) if have > 0 else ""], 15, C_TEXT))
			v.add_child(_lbl(m["desc"], 13, C_DIM))
			card.get_child(0).add_child(v)
			if have > 0:
				card.get_child(0).add_child(_btn("Scrap\n+%d t" % floori(m["metal"] * D.SCRAP_MODULE_REFUND), _req.bind("scrap", [id])))
			var b := _btn("Build\n%d t" % cost, _req.bind("build", [id]), st["metal"] < cost)
			b.custom_minimum_size = Vector2(100, 0)
			card.get_child(0).add_child(b)
			_content.add_child(card)


# --- Астронавт ---------------------------------------------------------------

func _build_astronaut(st: Dictionary) -> void:
	var p: Dictionary = D.PROFILES[st["profile"]]
	if st["ship"] == "":
		_content.add_child(_lbl("No ship in the hangar. Ask the analyst to buy one.", 17, C_BAD))
	else:
		var stats := D.ship_stats(st["ship"], st["cargo"])
		_content.add_child(_lbl("%s: cargo %.1f / %.0f t" % [D.SHIPS[st["ship"]]["name"], stats["cargo"], stats["payload"]], 18, C_TITLE))
		_content.add_child(_bar(stats["cargo"] / stats["payload"]))
	_content.add_child(_lbl("Mission (chosen by the dispatcher): %s — %s" % [p["name"], p["desc"]], 14, C_DIM))
	if p["surface"]:
		_content.add_child(_lbl("After landing YOU walk on the Moon and collect samples (A/D, W, E).", 14, C_GOOD))
	var training_txt := "Crew training (bonus now ×%.2f, once per day)" % (1.4 + st["crew_training"])
	_content.add_child(_btn(training_txt, _req.bind("train", []), st["daily_used"].has("train") or st["crew_training"] >= 0.3))

	_section("On board")
	if st["cargo"].is_empty():
		_content.add_child(_lbl("Empty", 14, C_DIM))
	var counted := {}
	for id in st["cargo"]:
		counted[id] = counted.get(id, 0) + 1
	for id in counted:
		var m: Dictionary = D.MODULES[id]
		var row := _hbox()
		var l := _lbl("%s ×%d   %.1f t   %s" % [m["name"], counted[id], m["mass"], _works_hint(id, st)], 15, C_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_btn("Unload", _req.bind("unload", [id]), st["launching"]))
		_content.add_child(row)

	_section("Storage (modules are built by the engineer)")
	if st["warehouse"].is_empty():
		_content.add_child(_lbl("Empty", 14, C_DIM))
	for id in D.MODULE_ORDER:
		var n: int = st["warehouse"].get(id, 0)
		if n <= 0:
			continue
		var m: Dictionary = D.MODULES[id]
		var fits := true
		if st["ship"] != "":
			var stats := D.ship_stats(st["ship"], st["cargo"])
			fits = stats["cargo"] + m["mass"] <= stats["payload"] + 0.001
		var row := _hbox()
		var l := _lbl("%s ×%d   %.1f t   %s" % [m["name"], n, m["mass"], _works_hint(id, st)], 15, C_TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_btn("Load" if fits else "Won't fit", _req.bind("load", [id]),
			st["ship"] == "" or not fits or st["launching"]))
		_content.add_child(row)


## Подсказка: будет ли модуль работать в выбранной миссии.
func _works_hint(id: String, st: Dictionary) -> String:
	var m: Dictionary = D.MODULES[id]
	var p: Dictionary = D.PROFILES[st["profile"]]
	match m["kind"]:
		"orbital":
			return "✓ works" if p["rank"] >= m.get("min_rank", 0) else "✗ useless on a flyby"
		"surface":
			return "✓ works" if p["surface"] else "✗ needs a landing"
		"samples":
			return "✓ works" if p["samples"] else "✗ needs a return"
		"crew":
			return "✓" if st["profile"] == "return" else "✗ needs a return"
	return ""


# --- Диспетчер ---------------------------------------------------------------

func _build_dispatcher(st: Dictionary) -> void:
	_section("Mission type")
	var prow := _hbox()
	for id in D.PROFILE_ORDER:
		var p: Dictionary = D.PROFILES[id]
		var b := _btn(("▶ " if st["profile"] == id else "") + p["name"], _req.bind("profile", [id]),
			st["launching"], "%s\nFuel: %.1f t per tonne of mass" % [p["desc"], p["k"]])
		prow.add_child(b)
	_content.add_child(prow)
	_content.add_child(_lbl(D.PROFILES[st["profile"]]["desc"], 13, C_DIM))

	_section("Fuel in storage: %.1f t  (price %.2f M$/t, analyst has %d M$)" % [st["fuel"], st["fuel_price"], st["money"]])
	var frow := _hbox()
	for amount in [10, 25, 50]:
		var cost := ceili(amount * st["fuel_price"])
		frow.add_child(_btn("Buy %d t (%d M$)" % [amount, cost], _req.bind("buy_fuel", [amount]), st["money"] < cost))
	_content.add_child(frow)

	if st["ship"] == "":
		_content.add_child(_lbl("No ship — nothing to fuel.", 16, C_BAD))
		return
	var stats := D.ship_stats(st["ship"], st["cargo"])
	var need := D.fuel_needed(st["ship"], st["cargo"], st["profile"])
	var mass: float = stats["dry"] + stats["cargo"] + st["tank_fuel"]
	_section("%s: tank %.1f / %.0f t, mission needs %.1f t" % [D.SHIPS[st["ship"]]["name"], st["tank_fuel"], stats["tank"], need])
	_content.add_child(_bar(st["tank_fuel"] / stats["tank"], need / stats["tank"]))
	var trow := _hbox()
	trow.add_child(_btn("+5 t", _req.bind("refuel", [5.0]), st["launching"]))
	trow.add_child(_btn("+10 t", _req.bind("refuel", [10.0]), st["launching"]))
	trow.add_child(_btn("To required", _req.bind("refuel", [max(0.0, need - st["tank_fuel"])]), st["launching"] or st["tank_fuel"] >= need))
	trow.add_child(_btn("Fill up", _req.bind("refuel", [999.0]), st["launching"]))
	trow.add_child(_btn("-5 t", _req.bind("drain", [5.0]), st["launching"]))
	trow.add_child(_btn("Drain all", _req.bind("drain", [999.0]), st["launching"]))
	_content.add_child(trow)
	var pw_ok: bool = stats["power"] >= mass * D.TWR
	_content.add_child(_lbl("Liftoff mass %.1f t (dry %.1f + cargo %.1f + fuel %.1f)" % [mass, stats["dry"], stats["cargo"], st["tank_fuel"]], 14, C_TEXT))
	_content.add_child(_lbl("Thrust %d, required ≥ %.0f" % [stats["power"], mass * D.TWR], 14, C_GOOD if pw_ok else C_BAD))

	_section("Data forecast")
	var fc := D.forecast(st)
	_content.add_child(_lbl("≈ %d data units" % fc["total"], 20, C_TITLE))
	for line in fc["lines"]:
		_content.add_child(_lbl("· " + line, 13, C_DIM))

	_section("Pre-launch check")
	var problems := D.launch_problems(st)
	if st["launching"]:
		_content.add_child(_lbl("Countdown: %d" % ceili(st["countdown"]), 18, C_TITLE))
		_content.add_child(_btn("ABORT LAUNCH", _req.bind("abort", [])))
		return
	if problems.is_empty():
		_content.add_child(_lbl("✓ All systems go", 16, C_GOOD))
	for pr in problems:
		_content.add_child(_lbl("✗ " + pr, 15, C_BAD))
	var launch := _btn("LAUNCH TO THE MOON", _req.bind("launch", []), not problems.is_empty())
	launch.custom_minimum_size = Vector2(0, 48)
	launch.add_theme_font_size_override("font_size", 22)
	_content.add_child(launch)


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 0
	bar.anchor_right = 1
	bar.anchor_top = 1
	bar.anchor_bottom = 1
	bar.offset_top = -40
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_hud_label = RichTextLabel.new()
	_hud_label.bbcode_enabled = true
	_hud_label.fit_content = true
	_hud_label.scroll_active = false
	_hud_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_label.add_theme_font_size_override("normal_font_size", 15)
	bar.add_child(_hud_label)

	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 1
	_toasts.anchor_right = 1
	_toasts.offset_left = -430
	_toasts.offset_right = -12
	_toasts.offset_top = 48
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_toasts)

	_countdown_label = Label.new()
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.3
	_countdown_label.offset_left = -300
	_countdown_label.offset_right = 300
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 46)
	_countdown_label.add_theme_color_override("font_color", C_TITLE)
	_countdown_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_countdown_label.add_theme_constant_override("outline_size", 10)
	_countdown_label.visible = false
	add_child(_countdown_label)


func _update_hud() -> void:
	var st: Dictionary = _ms.state
	if st.is_empty():
		return
	var t := ceili(st["time_left"])
	var window := ""
	if D.LAUNCH_WINDOWS.has(st["day"]):
		window = "[color=#7ef08c]WINDOW OPEN[/color]"
	else:
		var next := -1
		for d in D.LAUNCH_WINDOWS:
			if d > st["day"]:
				next = d
				break
		window = "window: day %d" % next if next > 0 else "no more windows"
	var ship: String = "none" if st["ship"] == "" else D.SHIPS[st["ship"]]["name"]
	_hud_label.text = ("Day %d/%d %d:%02d   |   Money [b]%d[/b] M$   Metal [b]%d[/b] t   Fuel [b]%.0f[/b] t"
		+ "   |   Ship: %s   |   %s   |   Data: [b]%d[/b]") % [
		st["day"], D.DAYS, t / 60, t % 60, st["money"], st["metal"], st["fuel"], ship, window, st["total_data"]]
	_countdown_label.visible = st["launching"]
	if st["launching"]:
		_countdown_label.text = "LAUNCH IN %d" % ceili(st["countdown"])


func toast(text: String) -> void:
	var l := _lbl(text, 14, C_BAD if text.begins_with("⚠") else C_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 5:
		_toasts.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


# --- Окно (каркас) ------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -430
	_panel.offset_right = 430
	_panel.offset_top = -290
	_panel.offset_bottom = 250
	_panel.visible = false
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_panel.add_child(v)
	var head := _hbox()
	_panel_title = _lbl("", 20, C_TITLE)
	_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_panel_title)
	head.add_child(_btn("Close [E]", close_station))
	v.add_child(head)
	v.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)


# --- Мелкие помощники ---------------------------------------------------------

func _req(action: String, args: Array) -> void:
	_ms.request(action, args)


func _lbl(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _btn(text: String, cb: Callable, disabled := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func _hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	return h


func _section(text: String) -> void:
	var l := _lbl(text, 16, C_TITLE)
	_content.add_child(HSeparator.new())
	_content.add_child(l)


func _card() -> PanelContainer:
	var p := PanelContainer.new()
	var h := _hbox()
	p.add_child(h)
	return p


## Полоса заполнения; marker — отметка (например, нужное топливо).
func _bar(fill: float, marker := -1.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 14)
	c.draw.connect(func():
		var w := c.size.x
		c.draw_rect(Rect2(0, 0, w, 14), Color(0.15, 0.15, 0.15))
		var col := C_GOOD if fill <= 1.0 else C_BAD
		c.draw_rect(Rect2(0, 0, w * clampf(fill, 0, 1), 14), col.darkened(0.2))
		if marker >= 0.0:
			var x := w * clampf(marker, 0, 1)
			c.draw_rect(Rect2(x - 1, -3, 3, 20), C_TITLE))
	return c


func _centered_panel(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -w / 2.0
	p.offset_right = w / 2.0
	p.offset_top = -h / 2.0
	p.offset_bottom = h / 2.0
	add_child(p)
	return p


# --- Полёт и итоги ------------------------------------------------------------

func _start_flight(mission: Dictionary) -> void:
	if _panel.visible:
		close_station()
	if is_instance_valid(_launch_view):
		_launch_view.queue_free()
	if is_instance_valid(_flight):
		_flight.queue_free()
	_flight = FlightView.new()
	_flight.setup(mission)
	add_child(_flight)
	_toasts.visible = false # во время полёта — только ракета и субтитры
	HighLevelNetworkHandler.input_locked = true
	Music.play("launch")


func _end_flight(mission: Dictionary) -> void:
	if is_instance_valid(_flight):
		_flight.queue_free()
	_flight = null
	_toasts.visible = true
	HighLevelNetworkHandler.input_locked = false
	Music.play("game")
	_show_results(mission)


func _show_results(mission: Dictionary) -> void:
	if is_instance_valid(_launch_view):
		_launch_view.queue_free()
	var p := _centered_panel(660, 360)
	_launch_view = p
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_lbl("Mission #%d complete: %s" % [mission["n"], mission["ship_name"]], 22, C_TITLE))
	v.add_child(_lbl("Mission type: %s · fuel in tank %.1f t" % [mission["profile_name"], mission["tank_fuel"]], 15, C_TEXT))
	var names: PackedStringArray = []
	for id in mission["cargo"]:
		names.append(D.MODULES[id]["name"])
	v.add_child(_lbl("On board: " + (", ".join(names) if not names.is_empty() else "nothing"), 14, C_DIM))
	v.add_child(_lbl("Data returned: %d" % mission["data"], 24, C_GOOD))
	for line in mission["lines"]:
		v.add_child(_lbl("· " + line, 13, C_DIM))
	if mission.get("surface", false):
		var extra := " (×%.1f — samples returned to Earth)" % D.SAMPLE_RETURN_BONUS if mission.get("samples", false) else ""
		v.add_child(_lbl("· Astronaut's lunar samples: +%d%s" % [mission.get("surface_data", 0), extra], 14, C_GOOD))
	var close := _btn("Continue preparations", p.queue_free)
	v.add_child(close)


func _show_final(summary: Dictionary) -> void:
	if _panel.visible:
		close_station()
	var p := _centered_panel(660, 420)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_lbl("Preparation complete", 26, C_TITLE))
	v.add_child(_lbl("Missions sent to the Moon: %d" % summary["launched"].size(), 17, C_TEXT))
	v.add_child(_lbl("Total data collected: %d" % summary["total_data"], 22, C_GOOD))
	for m in summary["launched"]:
		v.add_child(_lbl("#%d · day %d · %s · %s · data %d" % [m["n"], m["day"], m["ship_name"], m["profile_name"], m["data"]], 14, C_DIM))
	v.add_child(_btn("Close", p.queue_free))
