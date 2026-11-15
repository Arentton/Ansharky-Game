extends Node

signal changed
signal notified(text: String)
signal launch_started(mission: Dictionary)
signal flight_finished(result: Dictionary)
signal campaign_finished(summary: Dictionary)

const D = preload("res://scripts/mission_data.gd")
const F = preload("res://scripts/flight_data.gd")
const T = preload("res://scripts/trajectory.gd")

var state: Dictionary = {}
var active := false
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
		"warehouse": {},
		"crew_training": 0.0,
		"daily_used": {},
		"launching": false, "countdown": 0.0,
		"launched": [],
		"total_data": 0, "over": false, "ending": "",
		"weak": [],
		"weak_sent": false,
		"priorities": [],
		"prio_sent": false,
		"flight": {},
	}


func start_campaign() -> void:
	if not multiplayer.is_server():
		return
	state = _fresh_state()
	active = true
	_day_timer = D.DAY_SECONDS
	_countdown = -1.0
	_roll_event()
	_roll_priorities()
	_broadcast()
	_notify("Day 1. Launch windows: days %s" % ", ".join(D.LAUNCH_WINDOWS.map(func(d): return str(d))))
	_notify("Goal: deliver %d data to Earth before day %d ends." % [D.DATA_GOAL, D.DAYS])
	_notify_to_role("analyst", "NASA priority data for the first mission has arrived. Open the analysis station.")


func stop_campaign() -> void:
	active = false


func debug_next_day() -> void:
	if active and not _online():
		_day_timer = 0.0


func debug_resources() -> void:
	if active and not _online():
		state["money"] += 200
		state["metal"] += 100
		_notify("TEST: +200 M$, +100 t of metal")
		_broadcast()


func _process(delta: float) -> void:
	if not active or not multiplayer.is_server() or state["over"]:
		return
	var flying: bool = not state["flight"].is_empty()
	if flying:
		_process_flight(delta)
	else:
		_day_timer -= delta
		state["time_left"] = max(_day_timer, 0.0)
	if _countdown >= 0.0:
		_countdown -= delta
		state["countdown"] = max(_countdown, 0.0)
		if _countdown <= 0.0:
			_countdown = -1.0
			_do_launch()
	if not flying and _day_timer <= 0.0:
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
	var window := "launch window OPEN" if D.LAUNCH_WINDOWS.has(int(state["day"])) else "no launch window"
	_notify("Day %d: +%d M$, +%d t of metal, %s." % [state["day"], D.MONEY_INCOME, D.METAL_INCOME, window])
	_broadcast()


func _roll_event() -> void:
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


func _finish(early := false) -> void:
	if state["over"]:
		return
	state["over"] = true
	state["launching"] = false
	_countdown = -1.0
	state["ending"] = D.ending_for(int(state["total_data"]))
	if not early:
		state["time_left"] = 0.0
	_broadcast()
	var summary := {
		"ending": state["ending"], "early": early,
		"day": state["day"], "days": D.DAYS, "goal": D.DATA_GOAL,
		"total_data": state["total_data"], "launched": state["launched"],
	}
	if _online():
		_rpc_finished.rpc(summary)
	else:
		_rpc_finished(summary)


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
		return ""
	return HighLevelNetworkHandler.my_role()


const ACTION_ROLES := {
	"buy_ship": "analyst", "sell_ship": "analyst", "buy_metal": "analyst", "report": "analyst",
	"send_prio": "analyst",
	"build": "engineer", "scrap": "engineer", "salvage": "engineer", "send_report": "engineer",
	"load": "astronaut", "unload": "astronaut", "train": "astronaut",
	"profile": "dispatcher", "buy_fuel": "dispatcher", "refuel": "dispatcher",
	"drain": "dispatcher", "launch": "dispatcher", "abort": "dispatcher",
	"flight_tli": "dispatcher", "flight_site": "dispatcher",
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


func prio_discount(module_id: String) -> bool:
	return state.get("prio_sent", false) and F.module_is_priority(module_id, state.get("priorities", []))


func _do(action: String, args: Array) -> String:
	var st := state
	var locked: bool = st["launching"]
	match action:
		"buy_ship":
			var id: String = args[0]
			if st["ship"] != "":
				return "There is already a ship in the hangar: launch or sell it first"
			var cost := D.ship_cost(id, st)
			if st["money"] < cost:
				return "Not enough money: need %d M$" % cost
			st["money"] -= cost
			st["ship"] = id
			st["ship_paid"] = cost
			st["cargo"] = []
			st["tank_fuel"] = 0.0
			st["weak"] = _roll_weak(id)
			st["weak_sent"] = false
			if D.SHIPS[id]["perks"].get("no_landing", false) and D.PROFILES[st["profile"]]["surface"]:
				st["profile"] = "orbit"
			_notify("Bought the '%s' ship for %d M$" % [D.SHIPS[id]["name"], cost])
			_notify_to_role("engineer", "New ship in the hangar: run diagnostics at the server rack.")
		"sell_ship":
			if st["ship"] == "" or locked:
				return "Nothing to sell"
			var refund := roundi(st.get("ship_paid", D.SHIPS[st["ship"]]["cost"]) * D.SELL_SHIP_REFUND)
			for id in st["cargo"]:
				_add_wh(id, 1)
			st["fuel"] += st["tank_fuel"]
			st["money"] += refund
			_notify("Sold the '%s' ship for %d M$, cargo and fuel went back to storage" % [D.SHIPS[st["ship"]]["name"], refund])
			st["ship"] = ""
			st["cargo"] = []
			st["tank_fuel"] = 0.0
			st["weak"] = []
			st["weak_sent"] = false
		"buy_metal":
			var amount: int = args[0]
			var cost := ceili(amount * st["metal_price"])
			if st["money"] < cost:
				return "Not enough money: need %d M$" % cost
			st["money"] -= cost
			st["metal"] += amount
		"report":
			if st["daily_used"].has("report"):
				return "The sponsor report was already filed today"
			st["daily_used"]["report"] = true
			var gain := 5 + int(st["total_data"] / 20)
			st["money"] += gain
			_notify("Sponsor report: +%d M$ (the more data collected, the more generous)" % gain)
		"send_prio":
			if st["priorities"].is_empty():
				return "No priorities yet"
			if st["prio_sent"]:
				return ""
			st["prio_sent"] = true
			_notify("The analyst sent NASA priorities to the engineer: %s. Instruments for them are %d%% cheaper." % [
				_prio_names(st["priorities"]), roundi((1.0 - F.PRIORITY_DISCOUNT) * 100)])
		"build":
			var id: String = args[0]
			var cost := D.module_cost(id, st["event"], prio_discount(id))
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
				return "Scrap metal was already collected today"
			st["daily_used"]["salvage"] = true
			var gain := _rng.randi_range(4, 10)
			st["metal"] += gain
			_notify("The engineer collected scrap metal: +%d t" % gain)
		"send_report":
			var fl: Dictionary = st["flight"]
			if not fl.is_empty():
				var known: Array = []
				for f in fl["faults"]:
					known.append(f["id"])
				fl["reported"] = known
				fl["weak_sent"] = true
				var txt := "no damage" if known.is_empty() else _fault_names(known)
				_notify("The engineer sent mission #%d telemetry to the dispatcher: %s." % [fl["n"], txt])
			elif st["ship"] != "":
				st["weak_sent"] = true
				var txt := "no weak points" if st["weak"].is_empty() else "weak points: " + _fault_names(st["weak"])
				_notify("The engineer sent the dispatcher a report on '%s': %s." % [D.SHIPS[st["ship"]]["name"], txt])
			else:
				return "Nothing to send: no ship in the hangar"
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
				return "The crew has already trained today"
			if st["crew_training"] >= 0.3:
				return "The crew is fully trained"
			st["daily_used"]["train"] = true
			st["crew_training"] = snappedf(st["crew_training"] + 0.05, 0.01)
			_notify("Crew training: crew bonus ×%.2f" % (1.4 + st["crew_training"]))
		"profile":
			var id: String = args[0]
			if locked:
				return "Launch in progress"
			if st["ship"] != "" and D.SHIPS[st["ship"]]["perks"].get("no_landing", false) and D.PROFILES[id]["surface"]:
				return "'%s' cannot land" % D.SHIPS[st["ship"]]["name"]
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
				return "Launch impossible: " + problems[0]
			st["launching"] = true
			_countdown = D.LAUNCH_COUNTDOWN
			st["countdown"] = _countdown
			_notify("LAUNCH! Countdown %d seconds..." % D.LAUNCH_COUNTDOWN)
		"abort":
			if not locked:
				return ""
			st["launching"] = false
			_countdown = -1.0
			_notify("Launch aborted by the dispatcher")
		"flight_tli":
			return _flight_tli(float(args[0]), float(args[1]))
		"flight_site":
			return _flight_site(str(args[0]))
	return ""


func _add_wh(id: String, n: int) -> void:
	var wh: Dictionary = state["warehouse"]
	wh[id] = wh.get(id, 0) + n
	if wh[id] <= 0:
		wh.erase(id)


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
		_notify("Launch scrubbed: " + problems[0])
		return
	var fc := D.forecast(st)
	var ship: Dictionary = D.SHIPS[st["ship"]]
	var mission := {
		"n": st["launched"].size() + 1, "day": st["day"],
		"ship": st["ship"], "ship_name": ship["name"],
		"profile": st["profile"], "profile_name": D.PROFILES[st["profile"]]["name"],
		"cargo": st["cargo"].duplicate(), "tank_fuel": st["tank_fuel"],
		"expected": fc["total"], "data": 0, "status": "flight", "site": "", "lines": fc["lines"],
	}
	st["launched"].append(mission)
	if ship["perks"].has("refund"):
		st["money"] += roundi(st.get("ship_paid", ship["cost"]) * ship["perks"]["refund"])
	if st["event"] == "sponsor":
		st["money"] += 30
	st["flight"] = _new_flight(mission, fc)
	st["ship"] = ""
	st["cargo"] = []
	st["tank_fuel"] = 0.0
	st["weak"] = []
	st["weak_sent"] = false
	_roll_priorities()
	_broadcast()
	if _online():
		_rpc_launch.rpc(mission)
	else:
		_rpc_launch(mission)
	_notify_to_role("analyst", "NASA sent priorities for the next mission: %s." % _prio_names(st["priorities"]))


func _new_flight(mission: Dictionary, fc: Dictionary) -> Dictionary:
	var st := state
	var need := D.fuel_needed(st["ship"], st["cargo"], st["profile"])
	var margin := 0.0
	if need > 0.0:
		margin = clampf((st["tank_fuel"] - need) / need, 0.0, 0.5)
	var phi0 := _rng.randf() * TAU
	return {
		"n": mission["n"], "ship": st["ship"], "ship_name": mission["ship_name"],
		"profile": st["profile"], "profile_name": mission["profile_name"],
		"cargo": st["cargo"].duplicate(), "crew": D.count(st["cargo"], "crew") > 0,
		"phase": "tli", "t": 0.0, "t_phase": 0.0, "phi0": phi0,
		"plan": {}, "sum": {},
		"weak": st["weak"].duplicate(), "weak_sent": st["weak_sent"],
		"faults": [], "reported": [], "pending": [],
		"hazards": _make_hazards(phi0),
		"budget": T.dv_budget(st["profile"], margin),
		"prio": st["priorities"].duplicate(),
		"parts": {"orbital": fc["orbital"], "surface": fc["surface"], "samples": fc["samples"], "mult": fc["mult"]},
		"site": "", "crash": false, "outcome": "",
	}


func _make_hazards(phi0: float) -> Array:
	var nominal := T.simulate(phi0, phi0 + deg_to_rad(F.NOMINAL_OFFSET_DEG), F.NOMINAL_DV)
	var names: Array = F.METEOR_STREAMS.duplicate()
	_shuffle(names)
	var arts := [0, 1, 2, 3]
	_shuffle(arts)
	var out := []
	for i in _rng.randi_range(2, 3):
		var tc := _rng.randf_range(0.5, 2.2) * F.DAY
		var p := T.sample(nominal, "pts", tc)
		var along := (T.sample(nominal, "pts", tc + 900.0) - p).normalized()
		var normal := Vector2(-along.y, along.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var art: int = arts[i]
		var radius := _rng.randf_range(42000.0, 46000.0) - art * 4000.0
		var center := p + along * _rng.randf_range(-1.6, 1.6) * radius
		var v := normal * _rng.randf_range(0.25, 0.6)
		var start := center - v * tc
		out.append({"name": names[i], "x": start.x, "y": start.y, "vx": v.x, "vy": v.y, "r": radius,
			"seed": _rng.randi(), "art": art})
	return out


func _flight_tli(theta: float, dv: float) -> String:
	var fl: Dictionary = state["flight"]
	if fl.is_empty() or fl["phase"] != "tli":
		return "A burn is not possible right now"
	dv = clampf(dv, F.DV_MIN, F.DV_MAX)
	var traj := T.simulate(fl["phi0"], theta, dv, fl["hazards"])
	var ev := T.evaluate(traj, fl["profile"], dv, fl["budget"], fl["hazards"])
	if not ev["ok"]:
		return ev["errors"][0]
	_start_coast(theta, dv, traj, ev)
	return ""


func _start_coast(theta: float, dv: float, traj: Dictionary, ev: Dictionary) -> void:
	var fl: Dictionary = state["flight"]
	fl["plan"] = {"theta": theta, "dv": dv}
	fl["sum"] = {
		"peri_alt": traj["peri_alt"], "peri_t": traj["peri_t"], "loi": ev["loi"],
		"free_return": traj["free_return"], "return_t": traj["return_t"], "t_end": traj["t_end"],
		"dv_total": ev["dv_total"],
	}
	var pending := []
	for id in fl["weak"]:
		if _rng.randf() < F.BREAK_CHANCE:
			pending.append({"id": id, "t": float(traj["peri_t"]) * _rng.randf_range(0.2, 0.85), "cause": "weak point"})
	for hit in traj["hazards"]:
		if _rng.randf() < F.METEOR_HIT_CHANCE:
			var h: Dictionary = fl["hazards"][hit[0]]
			var id: String = F.FAULT_ORDER[_rng.randi() % F.FAULT_ORDER.size()]
			pending.append({"id": id, "t": float(hit[1]), "cause": "meteoroid puncture, '%s' stream" % h["name"]})
	pending.sort_custom(func(a, b): return a["t"] < b["t"])
	fl["pending"] = pending
	fl["t"] = 0.0
	_set_phase(fl, "coast")
	_notify("Translunar injection complete: Δv %.3f km/s, transit %.1f days%s." % [
		dv, T.transit_days(traj), ", free-return trajectory" if traj["free_return"] else ""])


func _process_flight(delta: float) -> void:
	var fl: Dictionary = state["flight"]
	fl["t_phase"] = float(fl["t_phase"]) + delta
	match fl["phase"]:
		"tli", "site":
			_autopilot(fl)
		"coast", "return":
			fl["t"] = float(fl["t"]) + delta * F.DAY / F.SIM_DAY_REAL
			_apply_pending(fl)
			if fl["phase"] == "coast" and fl["t"] >= fl["sum"]["peri_t"]:
				fl["t"] = fl["sum"]["peri_t"]
				_arrive(fl)
			elif fl["phase"] == "return" and fl["t"] >= _return_end(fl):
				_finish_flight()
		"orbit":
			if fl["t_phase"] > 3.0:
				_finish_flight()
		"landing":
			if fl["t_phase"] > 3.5:
				_finish_flight()


func _return_end(fl: Dictionary) -> float:
	var t_end: float = fl["sum"]["return_t"]
	return t_end if t_end > fl["sum"]["peri_t"] else float(fl["sum"]["t_end"])


func _set_phase(fl: Dictionary, phase: String) -> void:
	fl["phase"] = phase
	fl["t_phase"] = 0.0
	_broadcast()


func _apply_pending(fl: Dictionary) -> void:
	var pending: Array = fl["pending"]
	while not pending.is_empty() and float(pending[0]["t"]) <= float(fl["t"]):
		var p: Dictionary = pending.pop_front()
		if _broken(fl).has(p["id"]):
			continue
		fl["faults"].append(p)
		var f: Dictionary = F.FAULTS[p["id"]]
		_notify("⚠ Emergency on board mission #%d! Engineer, check the telemetry." % fl["n"])
		_notify_to_role("engineer", "⚠ Telemetry: %s: %s (%s). Send the report to the dispatcher!" % [f["name"], f["broken"], p["cause"]])
		_broadcast()


func _broken(fl: Dictionary) -> Array:
	var out := []
	for f in fl["faults"]:
		out.append(f["id"])
	return out


func _arrive(fl: Dictionary) -> void:
	var broken := _broken(fl)
	var fr: bool = fl["sum"]["free_return"]
	var peri := roundi(float(fl["sum"]["peri_alt"]))
	if fl["profile"] == "flyby":
		_notify("Lunar flyby at %d km! The Moon swings the ship back toward Earth." % peri)
		_set_phase(fl, "return")
		return
	fl["pending"] = []
	if broken.has("engine") or broken.has("oxygen"):
		var why: String = F.FAULTS["engine" if broken.has("engine") else "oxygen"]["broken"]
		if fr:
			fl["outcome"] = "aborted"
			_notify("Landing cancelled: %s. The ship loops around the Moon and returns on a free-return trajectory." % why)
			_set_phase(fl, "return")
		else:
			fl["outcome"] = "lost"
			_notify("Accident: %s, and the trajectory does not lead back to Earth. The crew was evacuated; the ship and instruments are lost." % why)
			_finish_flight()
		return
	_notify("Lunar orbit insertion complete: orbit %d km above the surface." % peri)
	if fl["profile"] == "orbit":
		_set_phase(fl, "orbit")
	else:
		_set_phase(fl, "site")
		_notify_to_role("dispatcher", "The ship is in lunar orbit: choose a landing site at Mission Control!")


func _flight_site(site_id: String) -> String:
	var fl: Dictionary = state["flight"]
	if fl.is_empty() or fl["phase"] != "site":
		return "You can't choose a landing site right now"
	if not F.SITES.has(site_id):
		return "Unknown landing site"
	fl["site"] = site_id
	fl["crash"] = _rng.randf() < T.crash_risk(site_id, _broken(fl))
	_set_phase(fl, "landing")
	_notify("The lander is descending: %s..." % F.SITES[site_id]["name"])
	return ""


func _finish_flight() -> void:
	var st := state
	var fl: Dictionary = st["flight"]
	var res := _flight_result(fl)
	for m in st["launched"]:
		if m["n"] == fl["n"]:
			m["data"] = res["data"]
			m["status"] = res["outcome"]
			m["site"] = res["site_name"]
	st["total_data"] += res["data"]
	st["money"] += res["money"]
	st["flight"] = {}
	_broadcast()
	if _online():
		_rpc_flight_done.rpc(res)
	else:
		_rpc_flight_done(res)
	if st["total_data"] >= D.DATA_GOAL:
		_finish(true)


func _flight_result(fl: Dictionary) -> Dictionary:
	var parts: Dictionary = fl["parts"]
	var broken := _broken(fl)
	var profile: String = fl["profile"]
	var outcome: String = fl["outcome"]
	var site: String = fl["site"]
	var peri := float(fl["sum"].get("peri_alt", 0.0))
	var days := float(fl["sum"].get("peri_t", 0.0)) / F.DAY
	var lines: PackedStringArray = []
	var f_orb := 1.0
	var f_surf := 0.0
	var f_samp := 0.0
	var f_link := 1.0
	var f_all := 1.0
	if outcome == "lost":
		f_orb = 0.0
		lines.append("Ship lost: no data")
	elif outcome == "aborted":
		f_orb = 0.5
		lines.append("Mission aborted: instruments only worked during the flyby (×0.5)")
	else:
		if profile == "flyby":
			f_orb = 1.0 if peri <= 500.0 else (0.8 if peri <= 3000.0 else 0.6)
			lines.append("Flyby %d km from the Moon: orbital instruments ×%.1f" % [roundi(peri), f_orb])
		else:
			f_orb = 1.0 if peri <= 300.0 else (0.85 if peri <= 1000.0 else 0.7)
			lines.append("Orbit %d km: orbital instruments ×%.2f" % [roundi(peri), f_orb])
		if D.PROFILES[profile]["surface"] and site != "":
			var s: Dictionary = F.SITES[site]
			if fl["crash"]:
				outcome = "crash"
				lines.append("The lander crashed on a slope: no surface data")
			else:
				f_surf = 0.8 + 0.4 * float(s["light"]) / 100.0
				lines.append("%s: sunlight %d%% of the time, surface ×%.2f" % [s["name"], s["light"], f_surf])
				if broken.has("power") and not T.site_req_ok("power", site):
					f_surf *= 0.5
					lines.append("Worn batteries died in the shadow: surface ×0.5")
				f_link = 0.7 + 0.3 * float(s["earth"]) / 100.0
				lines.append("Earth visible %d%% of the time, comms ×%.2f" % [s["earth"], f_link])
				if broken.has("comms") and not T.site_req_ok("comms", site):
					f_link *= 0.6
					lines.append("The weak antenna kept losing Earth: comms ×0.6")
				if profile == "return":
					f_samp = 1.0
					lines.append("Samples delivered to Earth")
		if broken.has("shield") and days > 2.5:
			f_all *= 0.8
			lines.append("Long transit with damaged shielding: radiation dose, ×0.8")
		if broken.has("oxygen") and days > 3.0:
			f_all *= 0.7
			lines.append("The crew breathed emergency oxygen for too long: ×0.7")
		if outcome == "":
			outcome = "success"
	var science: float = (float(parts["orbital"]) * f_orb + float(parts["surface"]) * f_surf) * float(parts["mult"]) * f_link
	var data: float = (science + float(parts["samples"]) * f_samp) * f_all
	var met: PackedStringArray = []
	for p in fl["prio"]:
		if _priority_met(p, fl, f_orb > 0.0, f_surf > 0.0, f_samp > 0.0):
			met.append(F.PRIORITIES[p]["name"])
	if not met.is_empty():
		data *= 1.0 + F.PRIORITY_BONUS * met.size()
		lines.append("NASA priorities: %s (+%d%% data, grant +%d M$)" % [
			", ".join(met), roundi(F.PRIORITY_BONUS * 100 * met.size()), F.PRIORITY_GRANT * met.size()])
	var fault_names: PackedStringArray = []
	for f in fl["faults"]:
		fault_names.append("%s (%s)" % [F.FAULTS[f["id"]]["name"], f["cause"]])
	return {
		"n": fl["n"], "ship_name": fl["ship_name"], "profile_name": fl["profile_name"],
		"outcome": outcome, "data": roundi(data), "lines": lines,
		"money": F.PRIORITY_GRANT * met.size(), "met": met, "faults": fault_names,
		"site_name": F.SITES[site]["name"] if site != "" else "",
	}


func _priority_met(prio_id: String, fl: Dictionary, orb_ok: bool, surf_ok: bool, samp_ok: bool) -> bool:
	var prof: Dictionary = D.PROFILES[fl["profile"]]
	for m in F.PRIORITIES[prio_id]["modules"]:
		if not fl["cargo"].has(m):
			continue
		match D.MODULES[m]["kind"]:
			"orbital":
				if orb_ok and prof["rank"] >= D.MODULES[m].get("min_rank", 0):
					return true
			"surface":
				if surf_ok and F.site_fits_priority(fl["site"], prio_id):
					return true
			"samples":
				if samp_ok and F.site_fits_priority(fl["site"], prio_id):
					return true
	return false


func _autopilot(fl: Dictionary) -> void:
	if _online() or HighLevelNetworkHandler.test_role == "dispatcher" or fl["t_phase"] < 4.0:
		return
	if fl["phase"] == "tli":
		var theta: float = fl["phi0"] + deg_to_rad(F.NOMINAL_OFFSET_DEG)
		var traj := T.simulate(fl["phi0"], theta, F.NOMINAL_DV, fl["hazards"])
		var ev := T.evaluate(traj, fl["profile"], F.NOMINAL_DV, fl["budget"], fl["hazards"])
		_notify("TEST: the autopilot performed the burn for the dispatcher.")
		_start_coast(theta, F.NOMINAL_DV, traj, ev)
	elif fl["phase"] == "site":
		var best := ""
		var best_score := -INF
		for id in F.SITE_ORDER:
			var score := -T.crash_risk(id, _broken(fl)) * 10.0
			for b in _broken(fl):
				if not T.site_req_ok(b, id):
					score -= 2.0
			if score > best_score:
				best_score = score
				best = id
		_notify("TEST: the autopilot chose a landing site for the dispatcher.")
		_flight_site(best)


func _roll_weak(ship_id: String) -> Array:
	var ids: Array = F.FAULT_ORDER.duplicate()
	_shuffle(ids)
	return ids.slice(0, F.SHIP_WEAK.get(ship_id, 1))


func _roll_priorities() -> void:
	var ids: Array = F.PRIORITY_ORDER.duplicate()
	_shuffle(ids)
	state["priorities"] = ids.slice(0, 2)
	state["prio_sent"] = false


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _prio_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id in ids:
		names.append("'%s'" % F.PRIORITIES[id]["name"])
	return ", ".join(names)


func _fault_names(ids: Array) -> String:
	var names: PackedStringArray = []
	for id in ids:
		names.append(F.FAULTS[id]["name"].to_lower())
	return ", ".join(names)


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


func _notify_role(text: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _online() and sender != 0 and sender != multiplayer.get_unique_id():
		_rpc_notify.rpc_id(sender, "⚠ " + text)
	else:
		notified.emit("⚠ " + text)


func _notify_to_role(role: String, text: String) -> void:
	if _online():
		var pid := HighLevelNetworkHandler.peer_for_role(role)
		if pid == 0:
			return
		if pid == multiplayer.get_unique_id():
			notified.emit(text)
		else:
			_rpc_notify.rpc_id(pid, text)
	elif HighLevelNetworkHandler.test_role == role:
		notified.emit(text)


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
func _rpc_flight_done(result: Dictionary) -> void:
	flight_finished.emit(result)


@rpc("authority", "call_local", "reliable")
func _rpc_finished(summary: Dictionary) -> void:
	campaign_finished.emit(summary)
