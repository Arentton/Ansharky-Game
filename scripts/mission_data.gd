class_name MissionData
extends RefCounted
## Справочник: корабли, модули, типы миссий, события и формулы расчёта.
## Все числа баланса — здесь. Меняйте их, чтобы подстроить сложность.

# --- Кампания -----------------------------------------------------------------
const DAYS := 15                 # сколько дней до конца кампании
const DAY_SECONDS := 45.0        # длина одного дня в секундах
const START_MONEY := 160
const START_METAL := 35
const START_FUEL := 20
const MONEY_INCOME := 14         # М$ в день
const METAL_INCOME := 4          # т металла в день
const BASE_FUEL_PRICE := 1.0     # М$ за тонну топлива
const BASE_METAL_PRICE := 2.0    # М$ за тонну металла
const TWR := 1.3                 # мощность должна быть >= стартовая масса × TWR
const LAUNCH_COUNTDOWN := 5.0
const SELL_SHIP_REFUND := 0.5
const SCRAP_MODULE_REFUND := 0.5
## Окна запуска: в эти дни пуск разрешён.
const LAUNCH_WINDOWS := [3, 4, 7, 8, 11, 12, 15]

const ROLE_TITLES := {
	"analyst": "Analyst", "astronaut": "Astronaut",
	"dispatcher": "Flight Dispatcher", "engineer": "Engineer",
}

# --- Корабли ------------------------------------------------------------------
# cost — М$, power — мощность, payload — грузоподъёмность (т),
# tank — объём бака (т), dry — масса пустой ракеты (т).
const SHIPS := {
	"iskra": {"name": "Iskra", "cost": 45, "power": 70, "payload": 4, "tank": 30, "dry": 8,
		"desc": "Cheap and light. A flyby or simple orbit with a couple of instruments.", "perks": {}},
	"zond": {"name": "Zond-O", "cost": 65, "power": 75, "payload": 5, "tank": 40, "dry": 7,
		"desc": "Orbital scout: +30% data from orbital instruments. Cannot land.",
		"perks": {"orbital_bonus": 0.3, "no_landing": true}},
	"sokol": {"name": "Sokol-M", "cost": 85, "power": 120, "payload": 8, "tank": 55, "dry": 14,
		"desc": "A balanced workhorse for orbit and landing.", "perks": {}},
	"kolibri": {"name": "Kolibri", "cost": 100, "power": 85, "payload": 6, "tank": 40, "dry": 9,
		"desc": "Efficient engine: needs 25% less fuel.", "perks": {"fuel_eff": 0.75}},
	"phoenix": {"name": "Phoenix-R", "cost": 150, "power": 130, "payload": 7, "tank": 65, "dry": 15,
		"desc": "Reusable: refunds 40% of its price after launch.", "perks": {"refund": 0.4}},
	"selena": {"name": "Selena-L", "cost": 135, "power": 125, "payload": 10, "tank": 70, "dry": 18,
		"desc": "Landing platform: landing costs 30% less fuel, +15% surface data.",
		"perks": {"landing_eff": 0.7, "surface_bonus": 0.15}},
	"buran": {"name": "Buran-T", "cost": 125, "power": 145, "payload": 9, "tank": 120, "dry": 22,
		"desc": "Huge tank, return trip 15% cheaper. Built for sample-return missions.",
		"perks": {"return_eff": 0.85}},
	"tyazh": {"name": "Heavy Hauler", "cost": 160, "power": 210, "payload": 18, "tank": 90, "dry": 30,
		"desc": "Lots of payload and thrust, but heavy and thirsty.", "perks": {}},
	"titan": {"name": "Titan", "cost": 240, "power": 320, "payload": 28, "tank": 160, "dry": 45,
		"desc": "The flagship. Almost no limits — if you can afford the fuel.", "perks": {}},
}
const SHIP_ORDER := ["iskra", "zond", "sokol", "kolibri", "phoenix", "selena", "buran", "tyazh", "titan"]

# --- Типы миссий --------------------------------------------------------------
# k — сколько тонн топлива нужно на тонну массы ракеты (корпус + груз).
const PROFILES := {
	"flyby": {"name": "Flyby", "k": 0.8, "orbital": 0.5, "surface": false, "samples": false, "rank": 0,
		"desc": "Cheap on fuel; only orbital instruments work, at half strength."},
	"orbit": {"name": "Orbit", "k": 1.2, "orbital": 1.0, "surface": false, "samples": false, "rank": 1,
		"desc": "Orbital instruments work at full strength."},
	"landing": {"name": "Landing", "k": 2.0, "orbital": 0.8, "surface": true, "samples": false, "rank": 2,
		"desc": "Surface instruments work, and the astronaut collects samples on the Moon."},
	"return": {"name": "Landing & return", "k": 3.0, "orbital": 0.8, "surface": true, "samples": true, "rank": 3,
		"desc": "Very expensive, but samples come back to Earth (×1.5). Required for a crew."},
}
const PROFILE_ORDER := ["flyby", "orbit", "landing", "return"]

# --- Модули (строит инженер из металла) --------------------------------------
# kind: orbital / surface / samples — научные приборы (data — очки данных);
#       antenna / solar — поддержка; booster / tank / composite — улучшения ракеты;
#       crew — капсула экипажа.
const MODULES := {
	"camera": {"name": "HD camera", "metal": 6, "mass": 1.0, "kind": "orbital", "data": 20,
		"desc": "Images the surface from orbit."},
	"magneto": {"name": "Magnetometer", "metal": 8, "mass": 1.5, "kind": "orbital", "data": 25,
		"desc": "Measures the Moon's magnetic field."},
	"spectro": {"name": "Spectrometer", "metal": 10, "mass": 2.0, "kind": "orbital", "data": 35,
		"desc": "Chemical composition of the rocks."},
	"radar": {"name": "Subsurface radar", "metal": 15, "mass": 3.0, "kind": "orbital", "data": 55,
		"min_rank": 1, "desc": "Needs orbit or better — useless on a flyby."},
	"seismo": {"name": "Seismometer", "metal": 8, "mass": 1.5, "kind": "surface", "data": 30,
		"desc": "Moonquakes. Landing only."},
	"drill": {"name": "Drill rig", "metal": 18, "mass": 4.0, "kind": "surface", "data": 75,
		"desc": "Deep core samples. Landing only."},
	"rover": {"name": "Mini rover", "metal": 26, "mass": 5.0, "kind": "surface", "data": 120,
		"desc": "Drives around the landing site. Landing only."},
	"samples": {"name": "Sample container", "metal": 12, "mass": 2.0, "kind": "samples", "data": 90,
		"desc": "Data only on a return mission. No antenna needed."},
	"antenna": {"name": "Deep-space antenna", "metal": 9, "mass": 1.0, "kind": "antenna", "data": 0,
		"desc": "Without it only 50% of the data reaches Earth."},
	"solar": {"name": "Solar panels", "metal": 7, "mass": 1.0, "kind": "solar", "data": 0,
		"desc": "+15% data from all instruments (one set is enough)."},
	"booster": {"name": "Booster", "metal": 16, "mass": 2.0, "kind": "booster", "data": 0,
		"desc": "+45 rocket thrust."},
	"tank": {"name": "Extra tank", "metal": 10, "mass": 1.5, "kind": "tank", "data": 0,
		"desc": "+25 t tank capacity."},
	"composite": {"name": "Composite hull", "metal": 20, "mass": 0.0, "kind": "composite", "data": 0,
		"desc": "-3 t dry mass (at most halves it)."},
	"crew": {"name": "Crew capsule", "metal": 30, "mass": 4.0, "kind": "crew", "data": 0,
		"desc": "Crewed mission: surface data ×1.4 (+training). Return missions only."},
}
const MODULE_ORDER := ["camera", "magneto", "spectro", "radar", "seismo", "drill", "rover", "samples",
	"antenna", "solar", "booster", "tank", "composite", "crew"]

# --- События дня --------------------------------------------------------------
const EVENTS := {
	"calm": {"w": 4, "text": "A calm day."},
	"ship_sale": {"w": 3, "text": "35%% off the %s!"},
	"funding": {"w": 2, "text": "Extra funding: +40 M$."},
	"grant": {"w": 2, "text": "Science grant: +25 M$."},
	"scrap": {"w": 2, "text": "Scrap delivery: +15 t of metal."},
	"fuel_shortage": {"w": 2, "text": "Fuel shortage: price ×1.6."},
	"fuel_sale": {"w": 2, "text": "Fuel sale: price ×0.6."},
	"metal_sale": {"w": 2, "text": "Metal prices dropped: price ×0.6."},
	"weather": {"w": 2, "text": "Storm over the launch site — no launches today."},
	"audit": {"w": 1, "text": "Audit: 20 M$ fine."},
	"strike": {"w": 1, "text": "Workshop strike: modules cost 50% more."},
	"breakthrough": {"w": 1, "text": "Engineering breakthrough: modules cost 30% less."},
	"solar_flare": {"w": 1, "text": "Solar flare: a launch today yields 20% less data."},
	"sponsor": {"w": 1, "text": "A sponsor pays 30 M$ for a launch today."},
}


# --- Полёт к Луне (длительность ролика, секунды реального времени) ----------
# Фазы и телеметрия — по данным NASA (Artemis I, Apollo 11), см. flight_view.gd.
const T_ASCENT := 26.0
const T_EARTH_ORBIT := 10.0
const T_TLI := 12.0
const T_MOON := 10.0
const T_DESCENT := 16.0
const T_ORBIT_SCIENCE := 8.0
const SURFACE_SECONDS := 120.0
const SAMPLE_RETURN_BONUS := 1.5   # образцы, привезённые на Землю, ценнее


static func flight_seconds(profile_id: String) -> float:
	var base := T_ASCENT + T_EARTH_ORBIT + T_TLI + T_MOON
	match profile_id:
		"flyby": return base
		"orbit": return base + T_ORBIT_SCIENCE
		_: return base + T_DESCENT


# --- Образцы на поверхности (факты — NASA Apollo / LRO) ---------------------
# icon — индекс в assets/space/samples.png
const MOON_SAMPLES := [
	{"id": "basalt", "name": "Mare basalt", "icon": 0, "data": 30,
		"fact": "Dark lunar 'seas' are basalt lava plains 3.1-3.9 billion years old (Apollo 11 & 12 samples)."},
	{"id": "anorthosite", "name": "Highland anorthosite", "icon": 1, "data": 40,
		"fact": "Bright highland rock formed ~4.4 billion years ago when a global magma ocean cooled."},
	{"id": "regolith", "name": "Regolith scoop", "icon": 2, "data": 25,
		"fact": "Lunar soil (regolith) is 4-5 m deep in the maria, ground up by billions of years of micrometeorite impacts."},
	{"id": "core_tube", "name": "Drive core tube", "icon": 3, "data": 35,
		"fact": "Core tubes keep soil layers intact; they hold solar-wind gases such as helium-3."},
	{"id": "glass", "name": "Orange glass beads", "icon": 4, "data": 45,
		"fact": "Volcanic glass beads ~3.6 billion years old, like the 'orange soil' found on Apollo 17."},
	{"id": "seismometer", "name": "Seismometer readout", "icon": 5, "data": 50,
		"fact": "Apollo seismometers (1969-1977) recorded thousands of moonquakes, some shallow ones up to magnitude ~5."},
]


# --- Формулы ------------------------------------------------------------------

static func count(cargo: Array, id: String) -> int:
	return cargo.count(id)


static func cargo_mass(cargo: Array) -> float:
	var m := 0.0
	for id in cargo:
		m += MODULES[id]["mass"]
	return m


## Полные характеристики снаряжённой ракеты.
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


## Сколько топлива нужно для миссии.
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


## Проверка готовности. Возвращает список проблем (пустой = можно лететь).
static func launch_problems(st: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var ship_id: String = st["ship"]
	if ship_id == "":
		out.append("No ship — the analyst buys one")
		return out
	var cargo: Array = st["cargo"]
	var stats := ship_stats(ship_id, cargo)
	var profile_id: String = st["profile"]
	var need := fuel_needed(ship_id, cargo, profile_id)
	var mass: float = stats["dry"] + stats["cargo"] + st["tank_fuel"]
	if stats["cargo"] > stats["payload"] + 0.001:
		out.append("Overloaded: %.1f / %.0f t" % [stats["cargo"], stats["payload"]])
	if st["tank_fuel"] + 0.001 < need:
		out.append("Not enough fuel: %.1f / %.1f t" % [st["tank_fuel"], need])
	if stats["power"] < mass * TWR:
		out.append("Not enough thrust: %d < %.0f (mass %.1f t × %.1f)" % [stats["power"], mass * TWR, mass, TWR])
	if SHIPS[ship_id]["perks"].get("no_landing", false) and PROFILES[profile_id]["surface"]:
		out.append("The %s cannot land" % SHIPS[ship_id]["name"])
	if count(cargo, "crew") > 0 and profile_id != "return":
		out.append("A crew can only fly 'Landing & return'")
	if not LAUNCH_WINDOWS.has(st["day"]):
		out.append("No launch window today")
	if st["event"] == "weather":
		out.append("Storm — launch forbidden")
	if st["launching"]:
		out.append("Launch in progress")
	return out


## Прогноз собранных данных. Возвращает {total, lines: [...]} с разбором.
static func forecast(st: Dictionary) -> Dictionary:
	var ship_id: String = st["ship"]
	if ship_id == "":
		return {"total": 0, "lines": PackedStringArray()}
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
	var science := orbital + surface
	lines.append("Orbital instruments: %.0f" % orbital)
	lines.append("Surface instruments: %.0f" % surface)
	if count(cargo, "solar") > 0:
		science *= 1.15
		lines.append("Solar panels: ×1.15")
	if count(cargo, "antenna") == 0 and science > 0:
		science *= 0.5
		lines.append("No antenna: only ×0.5 reaches Earth")
	var need := fuel_needed(ship_id, cargo, profile_id)
	var margin := 0.0
	if need > 0:
		margin = clampf((st["tank_fuel"] - need) / need, 0.0, 0.5)
	if margin > 0:
		science *= 1.0 + margin
		lines.append("Fuel margin: +%d%% operating time" % roundi(margin * 100))
	if st["event"] == "solar_flare":
		science *= 0.8
		lines.append("Solar flare: ×0.8")
	if samples > 0:
		lines.append("Samples to Earth: %.0f" % samples)
	if idle > 0:
		lines.append("Idle on this mission: %d instruments" % idle)
	return {"total": roundi(science + samples), "lines": lines}


static func module_cost(id: String, event: String) -> int:
	var c: float = MODULES[id]["metal"]
	if event == "strike":
		c *= 1.5
	elif event == "breakthrough":
		c *= 0.7
	return ceili(c)


static func ship_cost(id: String, st: Dictionary) -> int:
	var c: float = SHIPS[id]["cost"]
	if st["event"] == "ship_sale" and st["event_arg"] == id:
		c *= 0.65
	return roundi(c)
