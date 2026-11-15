extends RefCounted
## Справочник полёта к Луне: физические константы, места посадки, неисправности
## корабля и научные приоритеты. Физика — реальные значения NASA, игровые
## параметры (склоны, освещённость, шансы) упрощены. Источники — в SOURCES.

# --- Физика (NASA Earth/Moon Fact Sheets, JPL) --------------------------------
const MU_EARTH := 398600.4418      # км³/с² — гравитационный параметр Земли
const MU_MOON := 4902.800          # км³/с² — гравитационный параметр Луны
const R_EARTH := 6371.0            # км — средний радиус Земли
const R_MOON := 1737.4             # км — средний радиус Луны
const MOON_DIST := 384400.0        # км — средний радиус орбиты Луны
const MOON_RATE := 2.66531e-6      # рад/с — Луна делает оборот за 27,3 суток
const LEO_ALT := 185.0             # км — опорная орбита Apollo и Artemis I
const DAY := 86400.0

# --- Мини-игра диспетчера ----------------------------------------------------
const DV_MIN := 3.00               # км/с — допустимый импульс разгона (TLI)
const DV_MAX := 3.30
const DV_START := 3.10
const PERI_SAFE_MIN := 50.0        # км — ниже опасно: рельеф и ошибки навигации
const PERI_GOOD_MAX := 500.0       # км — удобная высота для торможения у Луны
const PERI_REACH := 20000.0        # км — дальше траектория до Луны не доходит
const FREE_RETURN_ALT := 1000.0    # км — перигей возврата, который добивается коррекцией
const SIM_DAY_REAL := 5.0          # реальных секунд на сутки полёта
const TLI_BUDGET := 3.20           # км/с — разгон при топливе «по норме»
const LOI_BUDGET := 0.95           # км/с — торможение у Луны (не нужно при пролёте)
const MARGIN_DV := 1.2             # км/с за каждые 100% топлива сверх нормы
const NOMINAL_DV := 3.17           # автопилот тестового режима
const NOMINAL_OFFSET_DEG := 226.6  # угол точки разгона относительно Луны для NOMINAL_DV
const SLOPE_LIMIT := 8.0           # ° — круче опасно садиться
const SLOPE_LIMIT_RADAR := 4.0     # ° — если сломан посадочный радар
const BREAK_CHANCE := 0.55         # шанс, что слабое место откажет в полёте
const METEOR_HIT_CHANCE := 0.45    # шанс пробоя при проходе через метеорный поток
const PRIORITY_BONUS := 0.25       # +25% данных за каждый выполненный приоритет
const PRIORITY_GRANT := 15         # М$ от NASA за каждый выполненный приоритет
const PRIORITY_DISCOUNT := 0.75    # приоритетные приборы дешевле для инженера

# --- Места посадки -----------------------------------------------------------
# slope — типичный склон (°), light — % времени на Солнце, earth — % времени,
# когда видна Земля (связь напрямую). Оценки упрощены по данным LRO (LOLA, LROC)
# и материалам NASA о выборе регионов Artemis III.
const SITES := {
	"apollo11": {"name": "Море Спокойствия", "note": "Apollo 11, 1969", "map": "near",
		"lat": 0.67, "lon": 23.47, "slope": 2, "light": 50, "earth": 100, "tags": ["mare"],
		"desc": "Ровная базальтовая равнина — здесь сел лунный модуль «Орёл»."},
	"apollo12": {"name": "Океан Бурь", "note": "Apollo 12, 1969", "map": "near",
		"lat": -3.01, "lon": -23.42, "slope": 3, "light": 50, "earth": 100, "tags": ["mare"],
		"desc": "Морская равнина; экипаж Apollo 12 сел примерно в 160 м от зонда Surveyor 3."},
	"apollo15": {"name": "Хэдли — Апеннины", "note": "Apollo 15, 1971", "map": "near",
		"lat": 26.13, "lon": 3.63, "slope": 9, "light": 50, "earth": 100, "tags": ["mare", "highland"],
		"desc": "Борозда Хэдли у подножия Апеннин: и лава, и древние горы, но склоны круче."},
	"apollo16": {"name": "Нагорье Декарт", "note": "Apollo 16, 1972", "map": "near",
		"lat": -8.97, "lon": 15.50, "slope": 7, "light": 50, "earth": 100, "tags": ["highland"],
		"desc": "Единственная посадка Apollo в лунных горах — древняя светлая кора."},
	"apollo17": {"name": "Долина Таурус-Литтров", "note": "Apollo 17, 1972", "map": "near",
		"lat": 20.19, "lon": 30.77, "slope": 6, "light": 50, "earth": 100, "tags": ["mare", "highland"],
		"desc": "Долина между массивами; здесь нашли «оранжевый грунт» — вулканическое стекло."},
	"reiner": {"name": "Завиток Гамма Райнера", "note": "цель миссии NASA Lunar Vertex", "map": "near",
		"lat": 7.5, "lon": -59.0, "slope": 2, "light": 50, "earth": 100, "tags": ["swirl", "mare"],
		"desc": "Светлый «завиток» над магнитной аномалией — загадка для магнитометров."},
	"shackleton": {"name": "Пик у кратера Шеклтон", "note": "регион Artemis III (2022)", "map": "south",
		"lat": -89.45, "lon": 160.0, "slope": 6, "light": 85, "earth": 55, "tags": ["ice"],
		"desc": "Почти постоянное Солнце рядом с вечно тёмным кратером, где может быть лёд."},
	"ridge": {"name": "Хребет Шеклтон — де Жерлаш", "note": "Connecting Ridge, Artemis III (2022)", "map": "south",
		"lat": -89.0, "lon": -100.0, "slope": 5, "light": 88, "earth": 50, "tags": ["ice"],
		"desc": "Один из самых освещённых гребней полюса, но Земля видна лишь половину времени."},
	"haworth": {"name": "Кромка кратера Хауорт", "note": "регион Artemis III (2024)", "map": "south",
		"lat": -86.9, "lon": -25.0, "slope": 7, "light": 65, "earth": 75, "tags": ["ice"],
		"desc": "Рядом огромная холодная ловушка — вечно затенённое дно Хауорта."},
	"malapert": {"name": "Массив Малаперт", "note": "регион Artemis III (2024)", "map": "south",
		"lat": -85.9, "lon": 3.0, "slope": 9, "light": 70, "earth": 95, "tags": ["highland"],
		"desc": "Гора, с которой Земля видна почти всегда: отличная связь, но склоны круче."},
	"mouton": {"name": "Плато Монс-Мутон", "note": "регион Artemis III (2024), район VIPER", "map": "south",
		"lat": -85.4, "lon": 31.0, "slope": 3, "light": 75, "earth": 70, "tags": ["ice"],
		"desc": "Плоская вершина горы: пологие склоны и много солнца рядом с холодными ловушками."},
	"cabeus": {"name": "Пик у кратера Кабеус B", "note": "регион Artemis III (2024)", "map": "south",
		"lat": -83.6, "lon": -45.0, "slope": 8, "light": 70, "earth": 85, "tags": ["ice"],
		"desc": "В соседнем кратере Кабеус зонд LCROSS в 2009 году нашёл водяной лёд."},
}
const SITE_ORDER := ["apollo11", "apollo12", "apollo15", "apollo16", "apollo17", "reiner",
	"shackleton", "ridge", "haworth", "malapert", "mouton", "cabeus"]
const SOUTH_MAP_COLAT := 12.0      # полярная карта показывает широты от -90° до -78°

# --- Неисправности корабля ---------------------------------------------------
# kind: trajectory — учитывается при расчёте траектории, site — при выборе места.
# zone — участок на схеме ракеты у инженера.
const FAULTS := {
	"engine": {"name": "Маршевый двигатель", "weak": "нестабильная тяга",
		"broken": "двигатель отказал — затормозить у Луны нечем",
		"need": "траектория свободного возврата", "kind": "trajectory", "zone": "engine",
		"history": "Свободный возврат страховал Apollo 8 и Apollo 11: даже без двигателя корабль облетает Луну и идёт домой."},
	"oxygen": {"name": "Кислородный бак", "weak": "трещина в изоляции",
		"broken": "утечка кислорода — экипажу срочно нужно домой",
		"need": "свободный возврат и перелёт не дольше 3 суток", "kind": "trajectory", "zone": "service",
		"history": "Apollo 13 (1970): после взрыва кислородного бака экипаж вернулся, облетев Луну."},
	"shield": {"name": "Радиационная защита", "weak": "тонкая обшивка капсулы",
		"broken": "дозиметры показывают рост радиации",
		"need": "быстрый перелёт — не дольше 2,5 суток", "kind": "trajectory", "zone": "capsule",
		"history": "Радиацию на пути к Луне измеряли манекены Хельга и Зоар в полёте Artemis I (2022)."},
	"radar": {"name": "Посадочный радар", "weak": "плавающие показания",
		"broken": "радар не видит рельеф",
		"need": "ровная площадка: склон не круче 4°", "kind": "site", "zone": "lander",
		"history": "На Apollo 14 посадочный радар заработал только после перезагрузки уже на спуске."},
	"power": {"name": "Солнечные батареи", "weak": "износ панелей",
		"broken": "батареи дают половину мощности",
		"need": "место, где Солнце светит от 70% времени", "kind": "site", "zone": "solar",
		"history": "В полёте Artemis I на Orion несколько раз срабатывали ограничители тока в системе питания."},
	"comms": {"name": "Антенна дальней связи", "weak": "слабый сигнал",
		"broken": "связь с Землёй прерывается",
		"need": "место, откуда Земля видна от 90% времени", "kind": "site", "zone": "antenna",
		"history": "Во время Artemis I связь с сетью дальней связи NASA однажды пропала почти на час."},
}
const FAULT_ORDER := ["engine", "oxygen", "shield", "radar", "power", "comms"]
## Сколько слабых мест у корабля каждой модели.
const SHIP_WEAK := {
	"iskra": 2, "zond": 1, "sokol": 1, "kolibri": 2, "phoenix": 1,
	"selena": 1, "buran": 1, "tyazh": 2, "titan": 1,
}

# --- Научные приоритеты NASA (для аналитика) ---------------------------------
# modules — какими приборами получить эти данные; site_tag — какое место посадки
# подходит (для приборов на поверхности).
const PRIORITIES := {
	"ice": {"name": "Водяной лёд у южного полюса", "modules": ["radar", "spectro", "drill", "samples"],
		"site_tag": "ice", "why": "Лёд — это вода, кислород и топливо для будущей лунной базы.",
		"source": "LCROSS (2009), LRO, научная группа Artemis III (2020)"},
	"quakes": {"name": "Лунотрясения и недра Луны", "modules": ["seismo"], "site_tag": "",
		"why": "Сейсмометры Apollo записали тысячи лунотрясений в 1969–1977 годах.",
		"source": "Apollo PSE; NASA Space Apps 2022–2023 «Make a Moonquake Map»"},
	"magnet": {"name": "Магнитные аномалии", "modules": ["magneto"], "site_tag": "swirl",
		"why": "У Луны нет общего магнитного поля, но есть «магнитные пятна» и светлые завитки.",
		"source": "Lunar Prospector, миссия NASA Lunar Vertex"},
	"volcano": {"name": "Вулканизм лунных морей", "modules": ["spectro", "camera", "rover"], "site_tag": "mare",
		"why": "Моря — застывшая лава; её состав рассказывает о недрах Луны.",
		"source": "образцы Apollo 11–17, камеры LRO (LROC)"},
	"impacts": {"name": "Древняя кора и история ударов", "modules": ["samples", "drill", "rover"],
		"site_tag": "highland", "why": "Горные породы хранят летопись бомбардировки Земли и Луны.",
		"source": "Apollo 16, приоритеты Planetary Decadal Survey 2023–2032"},
	"mapping": {"name": "Карта мест посадки Artemis", "modules": ["camera", "radar"], "site_tag": "",
		"why": "Подробные снимки и рельеф нужны, чтобы выбирать безопасные площадки.",
		"source": "LRO: LOLA и LROC; Space Apps 2021 «Planetary Lander Video Game»"},
}
const PRIORITY_ORDER := ["ice", "quakes", "magnet", "volcano", "impacts", "mapping"]
const SITE_TAG_NAMES := {"ice": "лёд", "mare": "лунное море", "highland": "древние горы", "swirl": "магнитный завиток"}

# --- Метеорные потоки ---------------------------------------------------------
const METEOR_STREAMS := ["Персеиды", "Леониды", "Геминиды", "Квадрантиды", "Ориониды",
	"Тауриды", "Лириды", "Драконниды"]

const SOURCES := [
	"NASA Earth и Moon Fact Sheets — массы, радиусы и орбита Луны.",
	"Apollo Flight Journal (NASA) — опорная орбита 185 км, разгон к Луне ≈ 3,1 км/с, перелёт ≈ 3 суток, траектория свободного возврата.",
	"Artemis I (NASA, 2022) — разгон к Луне ступенью ICPS; ролик пуска SLS и Orion.",
	"NASA, регионы посадки Artemis III: 13 регионов (2022) и 9 регионов (2024) у южного полюса; критерии — склон, освещённость, связь с Землёй, близость к вечной тени.",
	"LRO: высотомер LOLA и камеры LROC; карта Луны в игре — NASA SVS «CGI Moon Kit».",
	"LCROSS (NASA, 2009) — водяной лёд в кратере Кабеус.",
	"NASA Space Apps Challenge: 2018 — выбор мест посадки лунной миссии по данным Moon Trek и LRO; 2021 — «Planetary Lander Video Game»; 2022–2023 — «Make a Moonquake Map» (сейсмометры Apollo).",
	"NASA Meteoroid Environment Office — метеорные потоки в окрестностях Земли и Луны.",
]


# --- Помощники -----------------------------------------------------------------

## Положение места на своей карте: u, v в [-1, 1], v — вверх.
static func site_uv(id: String) -> Vector2:
	var s: Dictionary = SITES[id]
	var lat := deg_to_rad(float(s["lat"]))
	var lon := deg_to_rad(float(s["lon"]))
	if s["map"] == "near":
		return Vector2(cos(lat) * sin(lon), sin(lat))
	var r := (90.0 + float(s["lat"])) / SOUTH_MAP_COLAT
	return Vector2(r * sin(lon), r * cos(lon))


static func site_tags_text(id: String) -> String:
	var names: PackedStringArray = []
	for t in SITES[id]["tags"]:
		names.append(SITE_TAG_NAMES.get(t, t))
	return ", ".join(names)


## Подходит ли место для приоритета (для приборов на поверхности).
static func site_fits_priority(site_id: String, prio_id: String) -> bool:
	var tag: String = PRIORITIES[prio_id]["site_tag"]
	return tag == "" or SITES[site_id]["tags"].has(tag)


## Входит ли модуль в список приборов для приоритетов.
static func module_is_priority(module_id: String, priorities: Array) -> bool:
	for p in priorities:
		if PRIORITIES[p]["modules"].has(module_id):
			return true
	return false
