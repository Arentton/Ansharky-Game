extends Node
## Общее состояние подготовки к полёту (автозагрузка MissionState).
## Источник истины — сервер (хост). Клиенты присылают запросы через request(),
## сервер проверяет их и рассылает всем новое состояние.
## В тестовом режиме (без сети) всё выполняется локально.

signal changed                       # состояние обновилось
signal notified(text: String)        # всплывающее сообщение
signal launch_started(mission: Dictionary)
signal flight_finished(mission: Dictionary)
signal campaign_finished(summary: Dictionary)
signal moon_pos(pos: Vector2, flip: bool, frame: int)  # позиция астронавта на Луне

const D = preload("res://scripts/mission_data.gd")

var state: Dictionary = {}
var active := false                  # идёт ли кампания
var _day_timer := 0.0
var _countdown := -1.0
var _sync_timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	state = _fresh_state()


func _fresh_state() -> Dictionary:
	return {
		"day": 1, "time_left": D.DAY_SECONDS,
		"money": D.START_MONEY, "metal": D.START_METAL, "fuel": D.START_FUEL,
		"fuel_price": D.BASE_FUEL_PRICE, "metal_price": D.BASE_METAL_PRICE,
		"event": "calm", "event_arg": "",
		"ship": "", "cargo": [], "tank_fuel": 0.0, "profile": "orbit",
		"warehouse": {},                # id модуля -> количество
		"crew_training": 0.0,
		"daily_used": {},               # разовые действия за день: имя -> true
		"launching": false, "countdown": 0.0,
		"launched": [],                 # отправленные миссии
		"total_data": 0, "over": false,
		# Текущий полёт: {} — нет полёта. Иначе phase "flight" | "surface",
		# t — сколько секунд осталось до конца фазы.
		"flight": {},
	}


# --- Запуск кампании ----------------------------------------------------------

## Вызывается на сервере (или в тестовом режиме), когда игровая сцена готова.
func start_campaign() -> void:
	if not multiplayer.is_server():
		return
	state = _fresh_state()
	active = true
	_day_timer = D.DAY_SECONDS
	_countdown = -1.0
	_roll_event()
	_broadcast()
	_notify("Day 1. Launch windows: days %s" % ", ".join(D.LAUNCH_WINDOWS.map(func(d): return str(d))))


func stop_campaign() -> void:
	active = false


# --- Читы тестового режима ----------------------------------------------------

func debug_next_day() -> void:
	if active and not _online():
		_day_timer = 0.0


func debug_resources() -> void:
	if active and not _online():
		state["money"] += 200
		state["metal"] += 100
		_notify("TEST: +200 M$, +100 t of metal")
		_broadcast()


## Хост (или тест) может промотать ролик полёта.
func skip_flight() -> void:
	if multiplayer.is_server():
		_apply("skip_flight", [], "")
	else:
		_rpc_request.rpc_id(1, "skip_flight", [])


func _process(delta: float) -> void:
	if not active or not multiplayer.is_server() or state["over"]:
		return
	if not state["flight"].is_empty():
		_tick_flight(delta)
	else:
		_day_timer -= delta
		state["time_left"] = max(_day_timer, 0.0)
		if _countdown >= 0.0:
			_countdown -= delta
			state["countdown"] = max(_countdown, 0.0)
			if _countdown <= 0.0:
				_countdown = -1.0
				_do_launch()
		if _day_timer <= 0.0 and state["flight"].is_empty():
			_next_day()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.5
		_broadcast()


func _next_day() -> void:
	if state["day"] >= D.DAYS:
		if _countdown >= 0.0:
			return # идёт отсчёт — сначала даём ракете улететь, итоги подведём следующим кадром
		_finish()
		return
	state["day"] += 1
	_day_timer = D.DAY_SECONDS
	state["daily_used"] = {}
	state["money"] += D.MONEY_INCOME
	state["metal"] += D.METAL_INCOME
	_roll_event()
	var window := "launch window OPEN" if D.LAUNCH_WINDOWS.has(state["day"]) else "no launch window"
	_notify("Day %d: +%d M$, +%d t of metal, %s." % [state["day"], D.MONEY_INCOME, D.METAL_INCOME, window])
	_broadcast()


func _roll_event() -> void:
	# Цены каждый день немного плавают.
	state["fuel_price"] = snappedf(D.BASE_FUEL_PRICE * _rng.randf_range(0.85, 1.15), 0.01)
	state["metal_price"] = snappedf(D.BASE_METAL_PRICE * _rng.randf_range(0.85, 1.15), 0.01)
	var total := 0
	for e in D.EVENTS.values():
		total += e["w"]
	var r := _rng.randi_range(1, total)
	var ev := "calm"
	for id in D.EVENTS:
		r -= D.EVENTS[id]["w"]
		if r <= 0:
			ev = id
			break
	state["event"] = ev
	state["event_arg"] = ""
	match ev:
		"ship_sale":
			state["event_arg"] = D.SHIP_ORDER[_rng.randi() % D.SHIP_ORDER.size()]
		"funding":
			state["money"] += 40
		"grant":
			state["money"] += 25
		"scrap":
			state["metal"] += 15
		"audit":
			state["money"] = max(0, state["money"] - 20)
		"fuel_shortage":
			state["fuel_price"] = snappedf(state["fuel_price"] * 1.6, 0.01)
		"fuel_sale":
			state["fuel_price"] = snappedf(state["fuel_price"] * 0.6, 0.01)
		"metal_sale":
			state["metal_price"] = snappedf(state["metal_price"] * 0.6, 0.01)
	_notify("Event: " + event_text())


func event_text() -> String:
	var t: String = D.EVENTS[state["event"]]["text"]
	if state["event"] == "ship_sale":
		t = t % D.SHIPS[state["event_arg"]]["name"]
	return t


func _finish() -> void:
	state["over"] = true
	state["time_left"] = 0.0
	_broadcast()
	var summary := {"total_data": state["total_data"], "launched": state["launched"]}
	if _online():
		_rpc_finished.rpc(summary)
	else:
		_rpc_finished(summary)


# --- Запросы от игроков -------------------------------------------------------

## Выполнить действие. role — роль, от имени которой оно делается.
func request(action: String, args: Array = []) -> void:
	if multiplayer.is_server():
		_apply(action, args, _my_role())
	else:
		_rpc_request.rpc_id(1, action, args)


@rpc("any_peer", "reliable")
func _rpc_request(action: String, args: Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var role: String = HighLevelNetworkHandler.players.get(sender, "")
	if action == "skip_flight":
		return # промотка — только у хоста
	_apply(action, args, role)


func _my_role() -> String:
	if HighLevelNetworkHandler.test_mode:
		return "" # тестовый режим: можно всё
	return HighLevelNetworkHandler.my_role()


## Какая роль имеет право на действие.
const ACTION_ROLES := {
	"buy_ship": "analyst", "sell_ship": "analyst", "buy_metal": "analyst", "report": "analyst",
	"build": "engineer", "scrap": "engineer", "salvage": "engineer",
	"load": "astronaut", "unload": "astronaut", "train": "astronaut",
	"collect": "astronaut", "end_surface": "astronaut",
	"profile": "dispatcher", "buy_fuel": "dispatcher", "refuel": "dispatcher",
	"drain": "dispatcher", "launch": "dispatcher", "abort": "dispatcher",
}
## Действия, доступные во время полёта (остальные ждут возвращения).
const FLIGHT_ACTIONS := ["collect", "end_surface", "skip_flight"]


func _apply(action: String, args: Array, role: String) -> void:
	if not active or state["over"]:
		return
	if role != "" and ACTION_ROLES.get(action, "") != role:
		return
	if not _valid_args(action, args):
		push_warning("[mission] rejected request %s %s" % [action, args])
		return
	if state["flight"].is_empty() == FLIGHT_ACTIONS.has(action):
		return # во время полёта — только действия полёта, и наоборот
	var err := _do(action, args)
	if err != "":
		_notify_role(err)
	_broadcast()


## Аргументы приходят от клиентов — проверяем тип и диапазон до выполнения,
## иначе неверный id уронит хост, а отрицательное количество даст бесплатные ресурсы.
func _valid_args(action: String, args: Array) -> bool:
	match action:
		"buy_ship":
			return _is_id(args, D.SHIPS)
		"build", "scrap", "load", "unload":
			return _is_id(args, D.MODULES)
		"profile":
			return _is_id(args, D.PROFILES)
		"buy_metal", "buy_fuel":
			return args.size() == 1 and typeof(args[0]) == TYPE_INT and args[0] > 0 and args[0] <= 1000
		"refuel", "drain":
			return args.size() == 1 and typeof(args[0]) in [TYPE_INT, TYPE_FLOAT] and args[0] > 0.0 and args[0] <= 1000.0
		"collect":
			return args.size() == 1 and typeof(args[0]) == TYPE_INT and args[0] >= 0 and args[0] < D.MOON_SAMPLES.size()
		"skip_flight":
			return true
		_:
			return ACTION_ROLES.has(action)


func _is_id(args: Array, table: Dictionary) -> bool:
	return args.size() == 1 and typeof(args[0]) in [TYPE_STRING, TYPE_STRING_NAME] and table.has(String(args[0]))


## Возвращает текст ошибки или "".
func _do(action: String, args: Array) -> String:
	var st := state
	var locked: bool = st["launching"]
	match action:
		# --- Аналитик ---
		"buy_ship":
			var id: String = args[0]
			if st["ship"] != "":
				return "A ship is already in the hangar — launch or sell it first"
			var cost := D.ship_cost(id, st)
			if st["money"] < cost:
				return "Not enough money: need %d M$" % cost
			st["money"] -= cost
			st["ship"] = id
			st["ship_paid"] = cost
			st["cargo"] = []
			st["tank_fuel"] = 0.0
			if D.SHIPS[id]["perks"].get("no_landing", false) and D.PROFILES[st["profile"]]["surface"]:
				st["profile"] = "orbit"
			_notify("Bought the %s for %d M$" % [D.SHIPS[id]["name"], cost])
		"sell_ship":
			if st["ship"] == "" or locked:
				return "Nothing to sell"
			var refund := roundi(st.get("ship_paid", D.SHIPS[st["ship"]]["cost"]) * D.SELL_SHIP_REFUND)
			for id in st["cargo"]:
				_add_wh(id, 1)
			st["fuel"] += st["tank_fuel"]
			st["money"] += refund
			_notify("Sold the %s for %d M$, cargo and fuel returned to storage" % [D.SHIPS[st["ship"]]["name"], refund])
			st["ship"] = ""
			st["cargo"] = []
			st["tank_fuel"] = 0.0
		"buy_metal":
			var amount: int = args[0]
			var cost := ceili(amount * st["metal_price"])
			if st["money"] < cost:
				return "Not enough money: need %d M$" % cost
			st["money"] -= cost
			st["metal"] += amount
		"report":
			if st["daily_used"].has("report"):
				return "Sponsors already got a report today"
			st["daily_used"]["report"] = true
			var gain := 5 + int(st["total_data"] / 20)
			st["money"] += gain
			_notify("Sponsor report: +%d M$ (more data collected = more generous sponsors)" % gain)
		# --- Инженер ---
		"build":
			var id: String = args[0]
			var cost := D.module_cost(id, st["event"])
			if st["metal"] < cost:
				return "Not enough metal: need %d t" % cost
			st["metal"] -= cost
			_add_wh(id, 1)
		"scrap":
			var id: String = args[0]
			if st["warehouse"].get(id, 0) <= 0:
				return "No such module in storage"
			_add_wh(id, -1)
			st["metal"] += floori(D.MODULES[id]["metal"] * D.SCRAP_MODULE_REFUND)
		"salvage":
			if st["daily_used"].has("salvage"):
				return "Scrap was already collected today"
			st["daily_used"]["salvage"] = true
			var gain := _rng.randi_range(4, 10)
			st["metal"] += gain
			_notify("Engineer collected scrap metal: +%d t" % gain)
		# --- Астронавт ---
		"load":
			var id: String = args[0]
			if st["ship"] == "" or locked:
				return "No ship to load"
			if st["warehouse"].get(id, 0) <= 0:
				return "No such module in storage"
			var stats := D.ship_stats(st["ship"], st["cargo"])
			if stats["cargo"] + D.MODULES[id]["mass"] > stats["payload"] + 0.001:
				return "Won't fit: payload capacity %.0f t" % stats["payload"]
			_add_wh(id, -1)
			st["cargo"].append(id)
		"unload":
			var id: String = args[0]
			if locked or not st["cargo"].has(id):
				return "No such module on board"
			st["cargo"].erase(id)
			_add_wh(id, 1)
			_clamp_tank()
		"train":
			if st["daily_used"].has("train"):
				return "The crew already trained today"
			if st["crew_training"] >= 0.3:
				return "The crew is fully trained"
			st["daily_used"]["train"] = true
			st["crew_training"] = snappedf(st["crew_training"] + 0.05, 0.01)
			_notify("Crew training: crew bonus ×%.2f" % (1.4 + st["crew_training"]))
		"collect":
			var f: Dictionary = st["flight"]
			var i: int = args[0]
			if f.get("phase", "") != "surface" or f["collected"].has(i):
				return ""
			f["collected"].append(i)
			var s: Dictionary = D.MOON_SAMPLES[i]
			_notify("Collected: %s (+%d data). %s" % [s["name"], s["data"], s["fact"]])
			if f["collected"].size() >= D.MOON_SAMPLES.size():
				f["t"] = min(f["t"], 4.0)
				_notify("All samples collected! Returning to the lander...")
		"end_surface":
			var f: Dictionary = st["flight"]
			if f.get("phase", "") == "surface":
				f["t"] = min(f["t"], 2.0)
		"skip_flight":
			var f: Dictionary = st["flight"]
			if f.get("phase", "") == "flight":
				f["t"] = 0.0
		# --- Диспетчер ---
		"profile":
			var id: String = args[0]
			if locked:
				return "Launch in progress"
			if st["ship"] != "" and D.SHIPS[st["ship"]]["perks"].get("no_landing", false) and D.PROFILES[id]["surface"]:
				return "The %s cannot land" % D.SHIPS[st["ship"]]["name"]
			st["profile"] = id
		"buy_fuel":
			var amount: int = args[0]
			var cost := ceili(amount * st["fuel_price"])
			if st["money"] < cost:
				return "Not enough money: need %d M$" % cost
			st["money"] -= cost
			st["fuel"] += amount
		"refuel":
			var amount: float = args[0]
			if st["ship"] == "" or locked:
				return "No ship"
			var stats := D.ship_stats(st["ship"], st["cargo"])
			var room: float = stats["tank"] - st["tank_fuel"]
			var take: float = min(amount, room, float(st["fuel"]))
			if take <= 0.0:
				return "Tank is full" if room <= 0.0 else "No fuel in storage"
			st["tank_fuel"] = snappedf(st["tank_fuel"] + take, 0.1)
			st["fuel"] = snappedf(st["fuel"] - take, 0.1)
		"drain":
			if st["ship"] == "" or locked or st["tank_fuel"] <= 0.0:
				return "Nothing to drain"
			var amount: float = min(float(args[0]), float(st["tank_fuel"]))
			st["tank_fuel"] = snappedf(st["tank_fuel"] - amount, 0.1)
			st["fuel"] = snappedf(st["fuel"] + amount, 0.1)
		"launch":
			var problems := D.launch_problems(st)
			if not problems.is_empty():
				return "Cannot launch: " + problems[0]
			st["launching"] = true
			_countdown = D.LAUNCH_COUNTDOWN
			st["countdown"] = _countdown
			_notify("LAUNCH! Countdown %d seconds..." % D.LAUNCH_COUNTDOWN)
		"abort":
			if not locked:
				return ""
			st["launching"] = false
			_countdown = -1.0
			_notify("Launch aborted by the flight dispatcher")
	return ""


func _add_wh(id: String, n: int) -> void:
	var wh: Dictionary = state["warehouse"]
	wh[id] = wh.get(id, 0) + n
	if wh[id] <= 0:
		wh.erase(id)


## Если сняли бак — лишнее топливо возвращается на склад.
func _clamp_tank() -> void:
	if state["ship"] == "":
		return
	var cap: float = D.ship_stats(state["ship"], state["cargo"])["tank"]
	if state["tank_fuel"] > cap:
		state["fuel"] = snappedf(state["fuel"] + state["tank_fuel"] - cap, 0.1)
		state["tank_fuel"] = cap


func _do_launch() -> void:
	var st := state
	st["launching"] = false
	var problems := D.launch_problems(st)
	if not problems.is_empty():
		_notify("Launch failed: " + problems[0])
		return
	var fc := D.forecast(st)
	var ship: Dictionary = D.SHIPS[st["ship"]]
	var profile: Dictionary = D.PROFILES[st["profile"]]
	var mission := {
		"n": st["launched"].size() + 1, "day": st["day"],
		"ship": st["ship"], "ship_name": ship["name"],
		"profile": st["profile"], "profile_name": profile["name"],
		"surface": profile["surface"], "samples": profile["samples"],
		"cargo": st["cargo"].duplicate(), "tank_fuel": st["tank_fuel"],
		"data": fc["total"], "lines": fc["lines"], "surface_data": 0,
	}
	st["launched"].append(mission)
	st["total_data"] += fc["total"]
	var refund := 0
	if ship["perks"].has("refund"):
		refund = roundi(st.get("ship_paid", ship["cost"]) * ship["perks"]["refund"])
		st["money"] += refund
	if st["event"] == "sponsor":
		st["money"] += 30
	st["ship"] = ""
	st["cargo"] = []
	st["tank_fuel"] = 0.0
	st["flight"] = {
		"phase": "flight", "t": D.flight_seconds(mission["profile"]),
		"n": mission["n"], "profile": mission["profile"], "surface": mission["surface"],
	}
	_broadcast()
	if _online():
		_rpc_launch.rpc(mission)
	else:
		_rpc_launch(mission)


# --- Полёт --------------------------------------------------------------------

func _tick_flight(delta: float) -> void:
	var f: Dictionary = state["flight"]
	f["t"] = f["t"] - delta
	if f["t"] > 0.0:
		return
	if f["phase"] == "flight" and f["surface"]:
		f["phase"] = "surface"
		f["t"] = D.SURFACE_SECONDS
		f["collected"] = []
		# Образцы раскиданы по району посадки (x в пикселях мира поверхности).
		var xs: Array = []
		for i in D.MOON_SAMPLES.size():
			xs.append(380 + i * 190 + _rng.randi_range(-50, 50))
		xs.shuffle()
		f["sample_x"] = xs
		_notify("Touchdown! Astronaut: collect the samples (A/D walk, W jump, E pick up).")
		_broadcast()
	else:
		_end_flight()


func _end_flight() -> void:
	var f: Dictionary = state["flight"]
	var mission: Dictionary = state["launched"].back()
	var bonus := 0
	for i in f.get("collected", []):
		bonus += D.MOON_SAMPLES[i]["data"]
	if mission["samples"]:
		bonus = roundi(bonus * D.SAMPLE_RETURN_BONUS)
	mission["surface_data"] = bonus
	mission["data"] += bonus
	state["total_data"] += bonus
	state["flight"] = {}
	_day_timer = max(_day_timer, 10.0) # чтобы после возвращения успеть оглядеться
	_broadcast()
	if _online():
		_rpc_flight_done.rpc(mission)
	else:
		_rpc_flight_done(mission)


## Позиция астронавта на Луне: шлёт тот, кто им управляет, остальные рисуют.
func send_moon_pos(pos: Vector2, flip: bool, frame: int) -> void:
	if _online():
		_rpc_moon_pos.rpc(pos, flip, frame)


@rpc("any_peer", "unreliable_ordered")
func _rpc_moon_pos(pos: Vector2, flip: bool, frame: int) -> void:
	moon_pos.emit(pos, flip, frame)


# --- Синхронизация ------------------------------------------------------------

func _online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


func _broadcast() -> void:
	if _online():
		_rpc_sync.rpc(state)
	else:
		changed.emit()


func _notify(text: String) -> void:
	if _online():
		_rpc_notify.rpc(text)
	else:
		notified.emit(text)


## Ошибка — только тому, кто нажал.
func _notify_role(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _online() and sender != 0 and sender != multiplayer.get_unique_id():
		_rpc_notify.rpc_id(sender, "⚠ " + text)
	else:
		notified.emit("⚠ " + text)


@rpc("authority", "call_local", "reliable")
func _rpc_sync(data: Dictionary) -> void:
	state = data
	changed.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_notify(text: String) -> void:
	notified.emit(text)


@rpc("authority", "call_local", "reliable")
func _rpc_launch(mission: Dictionary) -> void:
	launch_started.emit(mission)


@rpc("authority", "call_local", "reliable")
func _rpc_flight_done(mission: Dictionary) -> void:
	flight_finished.emit(mission)


@rpc("authority", "call_local", "reliable")
func _rpc_finished(summary: Dictionary) -> void:
	campaign_finished.emit(summary)
