class_name MissionData
extends RefCounted

const DAYS := 15
const DAY_SECONDS := 45.0
const START_MONEY := 160
const START_METAL := 35
const START_FUEL := 20
const MONEY_INCOME := 14
const METAL_INCOME := 4
const BASE_FUEL_PRICE := 1.0
const BASE_METAL_PRICE := 2.0
const TWR := 1.3
const LAUNCH_COUNTDOWN := 5.0
const SELL_SHIP_REFUND := 0.5
const SCRAP_MODULE_REFUND := 0.5
const LAUNCH_WINDOWS := [3, 4, 7, 8, 11, 12, 15]

const DATA_GOAL := 800
const DATA_SUCCESS := 450
const DATA_PARTIAL := 150

const ENDINGS := {
	"triumph": {"title": "Lunar Base Approved", "good": true, "color": Color(1.0, 0.85, 0.35),
		"text": "Your team delivered %d data in %d days. NASA approves a permanent crewed base at the lunar south pole, and the first habitat module will carry the names of everyone at this station."},
	"success": {"title": "Mission Accomplished", "good": true, "color": Color(0.45, 0.95, 0.55),
		"text": "The program met its science goals with %d data in %d days. Funding is extended, and the next generation of explorers will build on your maps and samples."},
	"partial": {"title": "Partial Success", "good": false, "color": Color(1.0, 0.75, 0.35),
		"text": "Only %d data reached Earth in %d days. The results are promising but thin: the program survives, with half the budget and a lot of questions."},
	"failure": {"title": "Program Cancelled", "good": false, "color": Color(1.0, 0.42, 0.38),
		"text": "After %d days the Moon kept its secrets: just %d data. The sponsors pull out, the hangar lights go dark, and the launch pad is left to the wind."},
}

const ROLE_TITLES := {
	"analyst": "Analyst", "astronaut": "Astronaut",
	"dispatcher": "Dispatcher", "engineer": "Engineer",
}

const SHIPS := {
	"iskra": {"name": "Spark", "cost": 45, "power": 70, "payload": 4, "tank": 30, "dry": 8,
		"desc": "Cheap and light. A flyby or a simple orbit with a couple of instruments.", "perks": {}},
	"zond": {"name": "Probe-O", "cost": 65, "power": 75, "payload": 5, "tank": 40, "dry": 7,
		"desc": "Orbital scout: +30% data from orbital instruments. Cannot land.",
		"perks": {"orbital_bonus": 0.3, "no_landing": true}},
	"sokol": {"name": "Falcon-M", "cost": 85, "power": 120, "payload": 8, "tank": 55, "dry": 14,
		"desc": "A balanced workhorse for orbit and landing.", "perks": {}},
	"kolibri": {"name": "Hummingbird", "cost": 100, "power": 85, "payload": 6, "tank": 40, "dry": 9,
		"desc": "Efficient engine: needs 25% less fuel.", "perks": {"fuel_eff": 0.75}},
	"phoenix": {"name": "Phoenix-R", "cost": 150, "power": 130, "payload": 7, "tank": 65, "dry": 15,
		"desc": "Reusable: refunds 40% of its cost after launch.", "perks": {"refund": 0.4}},
	"selena": {"name": "Selene-L", "cost": 135, "power": 125, "payload": 10, "tank": 70, "dry": 18,
		"desc": "Landing platform: landing costs 30% less fuel, +15% surface data.",
		"perks": {"landing_eff": 0.7, "surface_bonus": 0.15}},
	"buran": {"name": "Buran-T", "cost": 125, "power": 145, "payload": 9, "tank": 120, "dry": 22,
		"desc": "Huge tank, return trip 15% more efficient. Built for sample-return missions.",
		"perks": {"return_eff": 0.85}},
	"tyazh": {"name": "Heavy Hauler", "cost": 160, "power": 210, "payload": 18, "tank": 90, "dry": 30,
		"desc": "Lots of cargo and power, but heavy and fuel-hungry.", "perks": {}},
	"titan": {"name": "Titan", "cost": 240, "power": 320, "payload": 28, "tank": 160, "dry": 45,
		"desc": "The flagship. Almost no limits, if you can afford the fuel.", "perks": {}},
}
const SHIP_ORDER := ["iskra", "zond", "sokol", "kolibri", "phoenix", "selena", "buran", "tyazh", "titan"]

const PROFILES := {
	"flyby": {"name": "Flyby", "k": 0.8, "orbital": 0.5, "surface": false, "samples": false, "rank": 0,
		"desc": "Cheap on fuel; only orbital instruments work, at half strength."},
	"orbit": {"name": "Orbit", "k": 1.2, "orbital": 1.0, "surface": false, "samples": false, "rank": 1,
		"desc": "Orbital instruments work at full strength."},
	"landing": {"name": "Landing", "k": 2.0, "orbital": 0.8, "surface": true, "samples": false, "rank": 2,
		"desc": "Surface instruments come online."},
	"return": {"name": "Landing and return", "k": 3.0, "orbital": 0.8, "surface": true, "samples": true, "rank": 3,
		"desc": "Very expensive, but samples come back to Earth. Required for a crew."},
}
const PROFILE_ORDER := ["flyby", "orbit", "landing", "return"]

const MODULES := {
	"camera": {"name": "HD camera", "metal": 6, "mass": 1.0, "kind": "orbital", "data": 20,
		"desc": "Imaging the surface from orbit."},
	"magneto": {"name": "Magnetometer", "metal": 8, "mass": 1.5, "kind": "orbital", "data": 25,
		"desc": "The Moon's magnetic field."},
	"spectro": {"name": "Spectrometer", "metal": 10, "mass": 2.0, "kind": "orbital", "data": 35,
		"desc": "Chemical composition of rocks."},
	"radar": {"name": "Subsurface radar", "metal": 15, "mass": 3.0, "kind": "orbital", "data": 55,
		"min_rank": 1, "desc": "Needs orbit or higher; does not work on a flyby."},
	"seismo": {"name": "Seismometer", "metal": 8, "mass": 1.5, "kind": "surface", "data": 30,
		"desc": "Moonquakes. Landing only."},
	"drill": {"name": "Drill rig", "metal": 18, "mass": 4.0, "kind": "surface", "data": 75,
		"desc": "A core sample from deep below. Landing only."},
	"rover": {"name": "Mini rover", "metal": 26, "mass": 5.0, "kind": "surface", "data": 120,
		"desc": "Drives around the landing area. Landing only."},
	"samples": {"name": "Sample container", "metal": 12, "mass": 2.0, "kind": "samples", "data": 90,
		"desc": "Gives data only on a return mission. No antenna needed."},
	"antenna": {"name": "Deep-space antenna", "metal": 9, "mass": 1.0, "kind": "antenna", "data": 0,
		"desc": "Without it only 50% of the data reaches Earth."},
	"solar": {"name": "Solar panels", "metal": 7, "mass": 1.0, "kind": "solar", "data": 0,
		"desc": "+15% data from all instruments (one set is enough)."},
	"booster": {"name": "Booster", "metal": 16, "mass": 2.0, "kind": "booster", "data": 0,
		"desc": "+45 rocket power."},
	"tank": {"name": "Extra tank", "metal": 10, "mass": 1.5, "kind": "tank", "data": 0,
		"desc": "+25 t tank capacity."},
	"composite": {"name": "Composite hull", "metal": 20, "mass": 0.0, "kind": "composite", "data": 0,
		"desc": "-3 t hull mass (at most halves it)."},
	"crew": {"name": "Crew lunar module", "metal": 30, "mass": 4.0, "kind": "crew", "data": 0,
		"desc": "The astronaut lands on the Moon in person: surface data ×1.4 (+training). Return missions only."},
}
const MODULE_ORDER := ["camera", "magneto", "spectro", "radar", "seismo", "drill", "rover", "samples",
	"antenna", "solar", "booster", "tank", "composite", "crew"]

const EVENTS := {
	"calm": {"w": 4, "text": "A quiet day."},
	"ship_sale": {"w": 3, "text": "35%% off the '%s' ship!"},
	"funding": {"w": 2, "text": "Extra funding: +40 M$."},
	"grant": {"w": 2, "text": "Science grant: +25 M$."},
	"scrap": {"w": 2, "text": "Scrap metal delivery: +15 t of metal."},
	"fuel_shortage": {"w": 2, "text": "Fuel shortage: price ×1.6."},
	"fuel_sale": {"w": 2, "text": "Fuel sale: price ×0.6."},
	"metal_sale": {"w": 2, "text": "Metal prices dropped: price ×0.6."},
	"weather": {"w": 2, "text": "Storm over the launch site: no launches today."},
	"audit": {"w": 1, "text": "Audit: 20 M$ fine."},
	"strike": {"w": 1, "text": "Workshop strike: modules cost 50% more."},
	"breakthrough": {"w": 1, "text": "Engineering breakthrough: modules cost 30% less."},
	"solar_flare": {"w": 1, "text": "Solar flare: a launch today yields 20% less data."},
	"sponsor": {"w": 1, "text": "A sponsor pays 30 M$ for a launch today."},
}


static func count(cargo: Array, id: String) -> int:
	return cargo.count(id)


static func science_count(cargo: Array) -> int:
	var n := 0
	for id in cargo:
		if MODULES[id]["kind"] in ["orbital", "surface", "samples"]:
			n += 1
	return n


static func cargo_mass(cargo: Array) -> float:
	var m := 0.0
	for id in cargo:
		m += MODULES[id]["mass"]
	return m


static func ship_stats(ship_id: String, cargo: Array) -> Dictionary:
	var s: Dictionary = SHIPS[ship_id]
	var dry: float = s["dry"]
	dry = max(dry * 0.5, dry - 3.0 * count(cargo, "composite"))
	return {
		"power": s["power"] + 45 * count(cargo, "booster"),
		"payload": float(s["payload"]),
		"tank": float(s["tank"] + 25 * count(cargo, "tank")),
		"dry": dry,
		"cargo": cargo_mass(cargo),
	}


static func fuel_needed(ship_id: String, cargo: Array, profile_id: String) -> float:
	var st := ship_stats(ship_id, cargo)
	var perks: Dictionary = SHIPS[ship_id]["perks"]
	var p: Dictionary = PROFILES[profile_id]
	var eff: float = perks.get("fuel_eff", 1.0)
	if p["surface"]:
		eff *= perks.get("landing_eff", 1.0)
	if profile_id == "return":
		eff *= perks.get("return_eff", 1.0)
	return snappedf((st["dry"] + st["cargo"]) * p["k"] * eff, 0.1)


static func launch_problems(st: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var ship_id: String = st["ship"]
	if ship_id == "":
		out.append("No ship: the analyst buys one")
		return out
	var cargo: Array = st["cargo"]
	var stats := ship_stats(ship_id, cargo)
	var profile_id: String = st["profile"]
	var need := fuel_needed(ship_id, cargo, profile_id)
	var mass: float = stats["dry"] + stats["cargo"] + st["tank_fuel"]
	if not st.get("flight", {}).is_empty():
		out.append("The previous mission is still in flight")
	if science_count(cargo) == 0:
		out.append("No science equipment on board: the engineer builds instruments, the astronaut loads them")
	if stats["cargo"] > stats["payload"] + 0.001:
		out.append("Overloaded: %.1f / %.0f t" % [stats["cargo"], stats["payload"]])
	if st["tank_fuel"] + 0.001 < need:
		out.append("Not enough fuel: %.1f / %.1f t" % [st["tank_fuel"], need])
	if stats["power"] < mass * TWR:
		out.append("Not enough power: %d < %.0f (mass %.1f t × %.1f)" % [stats["power"], mass * TWR, mass, TWR])
	if SHIPS[ship_id]["perks"].get("no_landing", false) and PROFILES[profile_id]["surface"]:
		out.append("'%s' cannot land" % SHIPS[ship_id]["name"])
	if count(cargo, "crew") > 0 and profile_id != "return":
		out.append("With the crew lunar module you can only fly 'Landing and return'")
	if not LAUNCH_WINDOWS.has(int(st["day"])):
		out.append("No launch window today")
	if st["event"] == "weather":
		out.append("Storm: launch forbidden")
	if st["launching"]:
		out.append("Launch in progress")
	return out


static func forecast(st: Dictionary) -> Dictionary:
	var ship_id: String = st["ship"]
	if ship_id == "":
		return {"total": 0, "lines": PackedStringArray(), "orbital": 0.0, "surface": 0.0, "samples": 0.0, "mult": 1.0}
	var cargo: Array = st["cargo"]
	var perks: Dictionary = SHIPS[ship_id]["perks"]
	var profile_id: String = st["profile"]
	var p: Dictionary = PROFILES[profile_id]
	var lines: PackedStringArray = []
	var orbital := 0.0
	var surface := 0.0
	var samples := 0.0
	var idle := 0
	for id in cargo:
		var m: Dictionary = MODULES[id]
		match m["kind"]:
			"orbital":
				if p["rank"] >= m.get("min_rank", 0):
					orbital += m["data"]
				else:
					idle += 1
			"surface":
				if p["surface"]:
					surface += m["data"]
				else:
					idle += 1
			"samples":
				if p["samples"]:
					samples += m["data"]
				else:
					idle += 1
	orbital *= p["orbital"] * (1.0 + perks.get("orbital_bonus", 0.0))
	surface *= 1.0 + perks.get("surface_bonus", 0.0)
	if count(cargo, "crew") > 0:
		surface *= 1.4 + st["crew_training"]
		lines.append("Crew: surface ×%.2f" % (1.4 + st["crew_training"]))
	lines.append("Orbital instruments: %.0f" % orbital)
	lines.append("Surface instruments: %.0f" % surface)
	var mult := 1.0
	if count(cargo, "solar") > 0:
		mult *= 1.15
		lines.append("Solar panels: ×1.15")
	if count(cargo, "antenna") == 0 and orbital + surface > 0:
		mult *= 0.5
		lines.append("No antenna: only ×0.5 reaches Earth")
	var need := fuel_needed(ship_id, cargo, profile_id)
	var margin := 0.0
	if need > 0:
		margin = clampf((st["tank_fuel"] - need) / need, 0.0, 0.5)
	if margin > 0:
		mult *= 1.0 + margin
		lines.append("Fuel reserve: +%d%% operating time" % roundi(margin * 100))
	if st["event"] == "solar_flare":
		mult *= 0.8
		lines.append("Solar flare: ×0.8")
	if samples > 0:
		lines.append("Samples to Earth: %.0f" % samples)
	if idle > 0:
		lines.append("Idle on this mission: %d instruments" % idle)
	var science := (orbital + surface) * mult
	return {"total": roundi(science + samples), "lines": lines,
		"orbital": orbital, "surface": surface, "samples": samples, "mult": mult}


static func module_cost(id: String, event: String, prio := false) -> int:
	var c: float = MODULES[id]["metal"]
	if event == "strike":
		c *= 1.5
	elif event == "breakthrough":
		c *= 0.7
	if prio:
		c *= 0.75
	return ceili(c)


static func ending_for(total_data: int) -> String:
	if total_data >= DATA_GOAL:
		return "triumph"
	if total_data >= DATA_SUCCESS:
		return "success"
	if total_data >= DATA_PARTIAL:
		return "partial"
	return "failure"


static func ending_text(id: String, total_data: int, days: int) -> String:
	var t: String = ENDINGS[id]["text"]
	if id == "failure":
		return t % [days, total_data]
	return t % [total_data, days]


static func ship_cost(id: String, st: Dictionary) -> int:
	var c: float = SHIPS[id]["cost"]
	if st["event"] == "ship_sale" and st["event_arg"] == id:
		c *= 0.65
	return roundi(c)
