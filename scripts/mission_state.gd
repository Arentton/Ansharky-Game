extends Node
## Общее состояние подготовки к полёту (автозагрузка MissionState).
## Источник истины — сервер (хост). Клиенты присылают запросы через request(),
## сервер проверяет их и рассылает всем новое состояние.
## В тестовом режиме (без сети) всё выполняется локально.

signal changed                       # состояние обновилось
signal notified(text: String)        # всплывающее сообщение
signal launch_started(mission: Dictionary)
signal campaign_finished(summary: Dictionary)

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
	_notify("День 1. Окна запуска: дни %s" % ", ".join(D.LAUNCH_WINDOWS.map(func(d): return str(d))))


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
		_notify("ТЕСТ: +200 М$, +100 т металла")
		_broadcast()


func _process(delta: float) -> void:
	if not active or not multiplayer.is_server() or state["over"]:
		return
	_day_timer -= delta
	state["time_left"] = max(_day_timer, 0.0)
	if _countdown >= 0.0:
		_countdown -= delta
		state["countdown"] = max(_countdown, 0.0)
		if _countdown <= 0.0:
			_countdown = -1.0
			_do_launch()
	if _day_timer <= 0.0:
		_next_day()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.5
		_broadcast()


func _next_day() -> void:
	if state["day"] >= D.DAYS:
		_finish()
		return
	state["day"] += 1
	_day_timer = D.DAY_SECONDS
	state["daily_used"] = {}
	state["money"] += D.MONEY_INCOME
	state["metal"] += D.METAL_INCOME
	_roll_event()
	var window := "окно запуска ОТКРЫТО" if D.LAUNCH_WINDOWS.has(state["day"]) else "окна запуска нет"
	_notify("День %d: +%d М$, +%d т металла, %s." % [state["day"], D.MONEY_INCOME, D.METAL_INCOME, window])
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
	_notify("Событие: " + event_text())


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
	_apply(action, args, HighLevelNetworkHandler.players.get(sender, ""))


func _my_role() -> String:
	if HighLevelNetworkHandler.test_mode:
		return "" # тестовый режим: можно всё
	return HighLevelNetworkHandler.my_role()


## Какая роль имеет право на действие.
const ACTION_ROLES := {
	"buy_ship": "analyst", "sell_ship": "analyst", "buy_metal": "analyst", "report": "analyst",
	"build": "engineer", "scrap": "engineer", "salvage": "engineer",
	"load": "astronaut", "unload": "astronaut", "train": "astronaut",
	"profile": "dispatcher", "buy_fuel": "dispatcher", "refuel": "dispatcher",
	"drain": "dispatcher", "launch": "dispatcher", "abort": "dispatcher",
}


func _apply(action: String, args: Array, role: String) -> void:
	if not active or state["over"]:
		return
	if role != "" and ACTION_ROLES.get(action, "") != role:
		return
	var err := _do(action, args)
	if err != "":
		_notify_role(err)
	_broadcast()


## Возвращает текст ошибки или "".
func _do(action: String, args: Array) -> String:
	var st := state
	var locked: bool = st["launching"]
	match action:
		# --- Аналитик ---
		"buy_ship":
			var id: String = args[0]
			if st["ship"] != "":
				return "В ангаре уже стоит корабль — сначала запустите или продайте его"
			var cost := D.ship_cost(id, st)
			if st["money"] < cost:
				return "Не хватает денег: нужно %d М$" % cost
			st["money"] -= cost
			st["ship"] = id
			st["ship_paid"] = cost
			st["cargo"] = []
			st["tank_fuel"] = 0.0
			if D.SHIPS[id]["perks"].get("no_landing", false) and D.PROFILES[st["profile"]]["surface"]:
				st["profile"] = "orbit"
			_notify("Куплен корабль «%s» за %d М$" % [D.SHIPS[id]["name"], cost])
		"sell_ship":
			if st["ship"] == "" or locked:
				return "Нечего продавать"
			var refund := roundi(st.get("ship_paid", D.SHIPS[st["ship"]]["cost"]) * D.SELL_SHIP_REFUND)
			for id in st["cargo"]:
				_add_wh(id, 1)
			st["fuel"] += st["tank_fuel"]
			st["money"] += refund
			_notify("Корабль «%s» продан за %d М$, груз и топливо вернулись на склад" % [D.SHIPS[st["ship"]]["name"], refund])
			st["ship"] = ""
			st["cargo"] = []
			st["tank_fuel"] = 0.0
		"buy_metal":
			var amount: int = args[0]
			var cost := ceili(amount * st["metal_price"])
			if st["money"] < cost:
				return "Не хватает денег: нужно %d М$" % cost
			st["money"] -= cost
			st["metal"] += amount
		"report":
			if st["daily_used"].has("report"):
				return "Отчёт спонсорам уже был сегодня"
			st["daily_used"]["report"] = true
			var gain := 5 + int(st["total_data"] / 20)
			st["money"] += gain
			_notify("Отчёт спонсорам: +%d М$ (чем больше данных собрано, тем щедрее)" % gain)
		# --- Инженер ---
		"build":
			var id: String = args[0]
			var cost := D.module_cost(id, st["event"])
			if st["metal"] < cost:
				return "Не хватает металла: нужно %d т" % cost
			st["metal"] -= cost
			_add_wh(id, 1)
		"scrap":
			var id: String = args[0]
			if st["warehouse"].get(id, 0) <= 0:
				return "Такого модуля нет на складе"
			_add_wh(id, -1)
			st["metal"] += floori(D.MODULES[id]["metal"] * D.SCRAP_MODULE_REFUND)
		"salvage":
			if st["daily_used"].has("salvage"):
				return "Металлолом сегодня уже собран"
			st["daily_used"]["salvage"] = true
			var gain := _rng.randi_range(4, 10)
			st["metal"] += gain
			_notify("Инженер собрал металлолом: +%d т" % gain)
		# --- Астронавт ---
		"load":
			var id: String = args[0]
			if st["ship"] == "" or locked:
				return "Нет корабля для погрузки"
			if st["warehouse"].get(id, 0) <= 0:
				return "Такого модуля нет на складе"
			var stats := D.ship_stats(st["ship"], st["cargo"])
			if stats["cargo"] + D.MODULES[id]["mass"] > stats["payload"] + 0.001:
				return "Не влезет: грузоподъёмность %.0f т" % stats["payload"]
			_add_wh(id, -1)
			st["cargo"].append(id)
		"unload":
			var id: String = args[0]
			if locked or not st["cargo"].has(id):
				return "Такого модуля нет на борту"
			st["cargo"].erase(id)
			_add_wh(id, 1)
			_clamp_tank()
		"train":
			if st["daily_used"].has("train"):
				return "Экипаж сегодня уже тренировался"
			if st["crew_training"] >= 0.3:
				return "Экипаж натренирован на максимум"
			st["daily_used"]["train"] = true
			st["crew_training"] = snappedf(st["crew_training"] + 0.05, 0.01)
			_notify("Тренировка экипажа: бонус экипажа ×%.2f" % (1.4 + st["crew_training"]))
		# --- Диспетчер ---
		"profile":
			var id: String = args[0]
			if locked:
				return "Идёт пуск"
			if st["ship"] != "" and D.SHIPS[st["ship"]]["perks"].get("no_landing", false) and D.PROFILES[id]["surface"]:
				return "«%s» не умеет садиться" % D.SHIPS[st["ship"]]["name"]
			st["profile"] = id
		"buy_fuel":
			var amount: int = args[0]
			var cost := ceili(amount * st["fuel_price"])
			if st["money"] < cost:
				return "Не хватает денег: нужно %d М$" % cost
			st["money"] -= cost
			st["fuel"] += amount
		"refuel":
			var amount: float = args[0]
			if st["ship"] == "" or locked:
				return "Нет корабля"
			var stats := D.ship_stats(st["ship"], st["cargo"])
			var room: float = stats["tank"] - st["tank_fuel"]
			var take: float = min(amount, room, float(st["fuel"]))
			if take <= 0.0:
				return "Бак полон" if room <= 0.0 else "На складе нет топлива"
			st["tank_fuel"] = snappedf(st["tank_fuel"] + take, 0.1)
			st["fuel"] = snappedf(st["fuel"] - take, 0.1)
		"drain":
			if st["ship"] == "" or locked or st["tank_fuel"] <= 0.0:
				return "Сливать нечего"
			var amount: float = min(float(args[0]), float(st["tank_fuel"]))
			st["tank_fuel"] = snappedf(st["tank_fuel"] - amount, 0.1)
			st["fuel"] = snappedf(st["fuel"] + amount, 0.1)
		"launch":
			var problems := D.launch_problems(st)
			if not problems.is_empty():
				return "Пуск невозможен: " + problems[0]
			st["launching"] = true
			_countdown = D.LAUNCH_COUNTDOWN
			st["countdown"] = _countdown
			_notify("ПУСК! Обратный отсчёт %d секунд..." % D.LAUNCH_COUNTDOWN)
		"abort":
			if not locked:
				return ""
			st["launching"] = false
			_countdown = -1.0
			_notify("Пуск отменён диспетчером")
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
		_notify("Пуск сорван: " + problems[0])
		return
	var fc := D.forecast(st)
	var ship: Dictionary = D.SHIPS[st["ship"]]
	var mission := {
		"n": st["launched"].size() + 1, "day": st["day"],
		"ship": st["ship"], "ship_name": ship["name"],
		"profile": st["profile"], "profile_name": D.PROFILES[st["profile"]]["name"],
		"cargo": st["cargo"].duplicate(), "tank_fuel": st["tank_fuel"],
		"data": fc["total"], "lines": fc["lines"],
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
	_broadcast()
	if _online():
		_rpc_launch.rpc(mission)
	else:
		_rpc_launch(mission)


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
func _rpc_finished(summary: Dictionary) -> void:
	campaign_finished.emit(summary)
