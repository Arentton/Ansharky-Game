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
	"analyst": "Аналитик", "astronaut": "Астронавт",
	"dispatcher": "Диспетчер", "engineer": "Инженер",
}

# --- Корабли ------------------------------------------------------------------
# cost — М$, power — мощность, payload — грузоподъёмность (т),
# tank — объём бака (т), dry — масса пустой ракеты (т).
const SHIPS := {
	"iskra": {"name": "Искра", "cost": 45, "power": 70, "payload": 4, "tank": 30, "dry": 8,
		"desc": "Дешёвая и лёгкая. Пролёт или простая орбита с парой приборов.", "perks": {}},
	"zond": {"name": "Зонд-О", "cost": 65, "power": 75, "payload": 5, "tank": 40, "dry": 7,
		"desc": "Орбитальный разведчик: +30% данных орбитальных приборов. Сесть не может.",
		"perks": {"orbital_bonus": 0.3, "no_landing": true}},
	"sokol": {"name": "Сокол-М", "cost": 85, "power": 120, "payload": 8, "tank": 55, "dry": 14,
		"desc": "Сбалансированная рабочая лошадка для орбиты и посадки.", "perks": {}},
	"kolibri": {"name": "Колибри", "cost": 100, "power": 85, "payload": 6, "tank": 40, "dry": 9,
		"desc": "Экономичный двигатель: топлива нужно на 25% меньше.", "perks": {"fuel_eff": 0.75}},
	"phoenix": {"name": "Феникс-R", "cost": 150, "power": 130, "payload": 7, "tank": 65, "dry": 15,
		"desc": "Многоразовая: после пуска возвращает 40% стоимости.", "perks": {"refund": 0.4}},
	"selena": {"name": "Селена-Л", "cost": 135, "power": 125, "payload": 10, "tank": 70, "dry": 18,
		"desc": "Посадочная платформа: посадка на 30% дешевле по топливу, +15% данных с поверхности.",
		"perks": {"landing_eff": 0.7, "surface_bonus": 0.15}},
	"buran": {"name": "Буран-Т", "cost": 125, "power": 145, "payload": 9, "tank": 120, "dry": 22,
		"desc": "Огромный бак, возврат на 15% экономичнее. Создан для миссий с возвратом.",
		"perks": {"return_eff": 0.85}},
	"tyazh": {"name": "Тяжеловоз", "cost": 160, "power": 210, "payload": 18, "tank": 90, "dry": 30,
		"desc": "Много груза и мощности, но тяжёлый и прожорливый.", "perks": {}},
	"titan": {"name": "Титан", "cost": 240, "power": 320, "payload": 28, "tank": 160, "dry": 45,
		"desc": "Флагман. Почти без ограничений — если хватит денег на топливо.", "perks": {}},
}
const SHIP_ORDER := ["iskra", "zond", "sokol", "kolibri", "phoenix", "selena", "buran", "tyazh", "titan"]

# --- Типы миссий --------------------------------------------------------------
# k — сколько тонн топлива нужно на тонну массы ракеты (корпус + груз).
const PROFILES := {
	"flyby": {"name": "Пролёт", "k": 0.8, "orbital": 0.5, "surface": false, "samples": false, "rank": 0,
		"desc": "Дёшево по топливу, работают только орбитальные приборы и вполсилы."},
	"orbit": {"name": "Орбита", "k": 1.2, "orbital": 1.0, "surface": false, "samples": false, "rank": 1,
		"desc": "Орбитальные приборы работают на полную."},
	"landing": {"name": "Посадка", "k": 2.0, "orbital": 0.8, "surface": true, "samples": false, "rank": 2,
		"desc": "Включаются приборы для поверхности."},
	"return": {"name": "Посадка и возврат", "k": 3.0, "orbital": 0.8, "surface": true, "samples": true, "rank": 3,
		"desc": "Очень дорого, зато образцы привозятся на Землю. Нужна для экипажа."},
}
const PROFILE_ORDER := ["flyby", "orbit", "landing", "return"]

# --- Модули (строит инженер из металла) --------------------------------------
# kind: orbital / surface / samples — научные приборы (data — очки данных);
#       antenna / solar — поддержка; booster / tank / composite — улучшения ракеты;
#       crew — капсула экипажа.
const MODULES := {
	"camera": {"name": "Камера HD", "metal": 6, "mass": 1.0, "kind": "orbital", "data": 20,
		"desc": "Съёмка поверхности с орбиты."},
	"magneto": {"name": "Магнитометр", "metal": 8, "mass": 1.5, "kind": "orbital", "data": 25,
		"desc": "Магнитное поле Луны."},
	"spectro": {"name": "Спектрометр", "metal": 10, "mass": 2.0, "kind": "orbital", "data": 35,
		"desc": "Химический состав пород."},
	"radar": {"name": "Подповерхностный радар", "metal": 15, "mass": 3.0, "kind": "orbital", "data": 55,
		"min_rank": 1, "desc": "Нужна орбита или выше — при пролёте не работает."},
	"seismo": {"name": "Сейсмометр", "metal": 8, "mass": 1.5, "kind": "surface", "data": 30,
		"desc": "Лунотрясения. Только при посадке."},
	"drill": {"name": "Буровая установка", "metal": 18, "mass": 4.0, "kind": "surface", "data": 75,
		"desc": "Керн из глубины. Только при посадке."},
	"rover": {"name": "Мини-луноход", "metal": 26, "mass": 5.0, "kind": "surface", "data": 120,
		"desc": "Объезжает район посадки. Только при посадке."},
	"samples": {"name": "Контейнер образцов", "metal": 12, "mass": 2.0, "kind": "samples", "data": 90,
		"desc": "Данные только при миссии с возвратом. Антенна не нужна."},
	"antenna": {"name": "Антенна дальней связи", "metal": 9, "mass": 1.0, "kind": "antenna", "data": 0,
		"desc": "Без неё на Землю дойдёт только 50% данных."},
	"solar": {"name": "Солнечные панели", "metal": 7, "mass": 1.0, "kind": "solar", "data": 0,
		"desc": "+15% к данным всех приборов (одного комплекта достаточно)."},
	"booster": {"name": "Ускоритель", "metal": 16, "mass": 2.0, "kind": "booster", "data": 0,
		"desc": "+45 к мощности ракеты."},
	"tank": {"name": "Дополнительный бак", "metal": 10, "mass": 1.5, "kind": "tank", "data": 0,
		"desc": "+25 т к объёму бака."},
	"composite": {"name": "Композитная обшивка", "metal": 20, "mass": 0.0, "kind": "composite", "data": 0,
		"desc": "-3 т к массе корпуса (не больше чем вдвое)."},
	"crew": {"name": "Капсула экипажа", "metal": 30, "mass": 4.0, "kind": "crew", "data": 0,
		"desc": "Пилотируемая миссия: данные с поверхности ×1.4 (+тренировка). Только с возвратом."},
}
const MODULE_ORDER := ["camera", "magneto", "spectro", "radar", "seismo", "drill", "rover", "samples",
	"antenna", "solar", "booster", "tank", "composite", "crew"]

# --- События дня --------------------------------------------------------------
const EVENTS := {
	"calm": {"w": 4, "text": "Спокойный день."},
	"ship_sale": {"w": 3, "text": "Скидка 35%% на корабль «%s»!"},
	"funding": {"w": 2, "text": "Дополнительное финансирование: +40 М$."},
	"grant": {"w": 2, "text": "Научный грант: +25 М$."},
	"scrap": {"w": 2, "text": "Поставка металлолома: +15 т металла."},
	"fuel_shortage": {"w": 2, "text": "Дефицит топлива: цена ×1.6."},
	"fuel_sale": {"w": 2, "text": "Распродажа топлива: цена ×0.6."},
	"metal_sale": {"w": 2, "text": "Металл на бирже подешевел: цена ×0.6."},
	"weather": {"w": 2, "text": "Шторм над космодромом — пуск сегодня запрещён."},
	"audit": {"w": 1, "text": "Аудит: штраф 20 М$."},
	"strike": {"w": 1, "text": "Забастовка в цеху: модули дороже на 50%."},
	"breakthrough": {"w": 1, "text": "Инженерный прорыв: модули дешевле на 30%."},
	"solar_flare": {"w": 1, "text": "Солнечная вспышка: пуск сегодня даст на 20% меньше данных."},
	"sponsor": {"w": 1, "text": "Спонсор заплатит 30 М$ за пуск сегодня."},
}


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
		out.append("Нет корабля — его покупает аналитик")
		return out
	var cargo: Array = st["cargo"]
	var stats := ship_stats(ship_id, cargo)
	var profile_id: String = st["profile"]
	var need := fuel_needed(ship_id, cargo, profile_id)
	var mass: float = stats["dry"] + stats["cargo"] + st["tank_fuel"]
	if stats["cargo"] > stats["payload"] + 0.001:
		out.append("Перегруз: %.1f / %.0f т" % [stats["cargo"], stats["payload"]])
	if st["tank_fuel"] + 0.001 < need:
		out.append("Мало топлива: %.1f / %.1f т" % [st["tank_fuel"], need])
	if stats["power"] < mass * TWR:
		out.append("Не хватает мощности: %d < %.0f (масса %.1f т × %.1f)" % [stats["power"], mass * TWR, mass, TWR])
	if SHIPS[ship_id]["perks"].get("no_landing", false) and PROFILES[profile_id]["surface"]:
		out.append("«%s» не умеет садиться" % SHIPS[ship_id]["name"])
	if count(cargo, "crew") > 0 and profile_id != "return":
		out.append("С экипажем можно лететь только «Посадка и возврат»")
	if not LAUNCH_WINDOWS.has(st["day"]):
		out.append("Сегодня нет окна запуска")
	if st["event"] == "weather":
		out.append("Шторм — пуск запрещён")
	if st["launching"]:
		out.append("Идёт пуск")
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
		lines.append("Экипаж: поверхность ×%.2f" % (1.4 + st["crew_training"]))
	var science := orbital + surface
	lines.append("Орбитальные приборы: %.0f" % orbital)
	lines.append("Приборы на поверхности: %.0f" % surface)
	if count(cargo, "solar") > 0:
		science *= 1.15
		lines.append("Солнечные панели: ×1.15")
	if count(cargo, "antenna") == 0 and science > 0:
		science *= 0.5
		lines.append("Нет антенны: на Землю дойдёт ×0.5")
	var need := fuel_needed(ship_id, cargo, profile_id)
	var margin := 0.0
	if need > 0:
		margin = clampf((st["tank_fuel"] - need) / need, 0.0, 0.5)
	if margin > 0:
		science *= 1.0 + margin
		lines.append("Запас топлива: +%d%% времени работы" % roundi(margin * 100))
	if st["event"] == "solar_flare":
		science *= 0.8
		lines.append("Солнечная вспышка: ×0.8")
	if samples > 0:
		lines.append("Образцы на Землю: %.0f" % samples)
	if idle > 0:
		lines.append("Не работают в этой миссии: %d приборов" % idle)
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
