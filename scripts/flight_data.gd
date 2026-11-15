extends RefCounted

const MU_EARTH := 398600.4418
const MU_MOON := 4902.800
const R_EARTH := 6371.0
const R_MOON := 1737.4
const MOON_DIST := 384400.0
const MOON_RATE := 2.66531e-6
const LEO_ALT := 185.0
const DAY := 86400.0

const DV_MIN := 3.00
const DV_MAX := 3.30
const DV_START := 3.10
const PERI_SAFE_MIN := 50.0
const PERI_GOOD_MAX := 500.0
const PERI_REACH := 20000.0
const FREE_RETURN_ALT := 1000.0
const SIM_DAY_REAL := 5.0
const TLI_BUDGET := 3.20
const LOI_BUDGET := 0.95
const MARGIN_DV := 1.2
const NOMINAL_DV := 3.17
const NOMINAL_OFFSET_DEG := 226.6
const SLOPE_LIMIT := 8.0
const SLOPE_LIMIT_RADAR := 4.0
const BREAK_CHANCE := 0.55
const METEOR_HIT_CHANCE := 0.45
const PRIORITY_BONUS := 0.25
const PRIORITY_GRANT := 15
const PRIORITY_DISCOUNT := 0.75

const SITES := {
	"apollo11": {"name": "Sea of Tranquility", "note": "Apollo 11, 1969", "map": "near",
		"lat": 0.67, "lon": 23.47, "slope": 2, "light": 50, "earth": 100, "tags": ["mare"],
		"desc": "A flat basalt plain where the lunar module 'Eagle' touched down."},
	"apollo12": {"name": "Ocean of Storms", "note": "Apollo 12, 1969", "map": "near",
		"lat": -3.01, "lon": -23.42, "slope": 3, "light": 50, "earth": 100, "tags": ["mare"],
		"desc": "A mare plain; the Apollo 12 crew landed about 160 m from the Surveyor 3 probe."},
	"apollo15": {"name": "Hadley–Apennine", "note": "Apollo 15, 1971", "map": "near",
		"lat": 26.13, "lon": 3.63, "slope": 9, "light": 50, "earth": 100, "tags": ["mare", "highland"],
		"desc": "Hadley Rille at the foot of the Apennines: lava and ancient mountains, but steeper slopes."},
	"apollo16": {"name": "Descartes Highlands", "note": "Apollo 16, 1972", "map": "near",
		"lat": -8.97, "lon": 15.50, "slope": 7, "light": 50, "earth": 100, "tags": ["highland"],
		"desc": "The only Apollo landing in the lunar mountains: ancient bright crust."},
	"apollo17": {"name": "Taurus–Littrow Valley", "note": "Apollo 17, 1972", "map": "near",
		"lat": 20.19, "lon": 30.77, "slope": 6, "light": 50, "earth": 100, "tags": ["mare", "highland"],
		"desc": "A valley between massifs where 'orange soil' (volcanic glass) was found."},
	"reiner": {"name": "Reiner Gamma Swirl", "note": "target of NASA's Lunar Vertex mission", "map": "near",
		"lat": 7.5, "lon": -59.0, "slope": 2, "light": 50, "earth": 100, "tags": ["swirl", "mare"],
		"desc": "A bright 'swirl' above a magnetic anomaly, a puzzle for magnetometers."},
	"shackleton": {"name": "Peak near Shackleton crater", "note": "Artemis III region (2022)", "map": "south",
		"lat": -89.45, "lon": 160.0, "slope": 6, "light": 85, "earth": 55, "tags": ["ice"],
		"desc": "Almost constant sunlight next to a permanently dark crater that may hold ice."},
	"ridge": {"name": "Shackleton–de Gerlache Ridge", "note": "Connecting Ridge, Artemis III (2022)", "map": "south",
		"lat": -89.0, "lon": -100.0, "slope": 5, "light": 88, "earth": 50, "tags": ["ice"],
		"desc": "One of the best-lit ridges at the pole, but Earth is visible only half the time."},
	"haworth": {"name": "Haworth crater rim", "note": "Artemis III region (2024)", "map": "south",
		"lat": -86.9, "lon": -25.0, "slope": 7, "light": 65, "earth": 75, "tags": ["ice"],
		"desc": "Next to a huge cold trap: the permanently shadowed floor of Haworth."},
	"malapert": {"name": "Malapert Massif", "note": "Artemis III region (2024)", "map": "south",
		"lat": -85.9, "lon": 3.0, "slope": 9, "light": 70, "earth": 95, "tags": ["highland"],
		"desc": "A mountain from which Earth is almost always visible: great comms, but steeper slopes."},
	"mouton": {"name": "Mons Mouton Plateau", "note": "Artemis III region (2024), VIPER area", "map": "south",
		"lat": -85.4, "lon": 31.0, "slope": 3, "light": 75, "earth": 70, "tags": ["ice"],
		"desc": "A flat mountaintop: gentle slopes and plenty of sun next to cold traps."},
	"cabeus": {"name": "Peak near Cabeus B crater", "note": "Artemis III region (2024)", "map": "south",
		"lat": -83.6, "lon": -45.0, "slope": 8, "light": 70, "earth": 85, "tags": ["ice"],
		"desc": "In nearby Cabeus crater, the LCROSS probe found water ice in 2009."},
}
const SITE_ORDER := ["apollo11", "apollo12", "apollo15", "apollo16", "apollo17", "reiner",
	"shackleton", "ridge", "haworth", "malapert", "mouton", "cabeus"]
const SOUTH_MAP_COLAT := 12.0

const FAULTS := {
	"engine": {"name": "Main engine", "weak": "unstable thrust",
		"broken": "engine failed, nothing left to brake at the Moon",
		"need": "a free-return trajectory", "kind": "trajectory", "zone": "engine",
		"history": "Free return protected Apollo 8 and Apollo 11: even without an engine the ship swings around the Moon and heads home."},
	"oxygen": {"name": "Oxygen tank", "weak": "cracked insulation",
		"broken": "oxygen leak, the crew must get home fast",
		"need": "free return and a transit of no more than 3 days", "kind": "trajectory", "zone": "service",
		"history": "Apollo 13 (1970): after an oxygen tank exploded, the crew made it home by looping around the Moon."},
	"shield": {"name": "Radiation shielding", "weak": "thin capsule hull",
		"broken": "dosimeters show rising radiation",
		"need": "a fast transit of no more than 2.5 days", "kind": "trajectory", "zone": "capsule",
		"history": "Radiation on the way to the Moon was measured by the mannequins Helga and Zohar on Artemis I (2022)."},
	"radar": {"name": "Landing radar", "weak": "erratic readings",
		"broken": "the radar cannot see the terrain",
		"need": "a flat site: slope no steeper than 4°", "kind": "site", "zone": "lander",
		"history": "On Apollo 14 the landing radar only started working after a reset during descent."},
	"power": {"name": "Solar arrays", "weak": "worn panels",
		"broken": "the arrays give only half power",
		"need": "a site with sunlight at least 70% of the time", "kind": "site", "zone": "solar",
		"history": "During Artemis I, current limiters in Orion's power system tripped several times."},
	"comms": {"name": "Deep-space antenna", "weak": "weak signal",
		"broken": "contact with Earth keeps dropping",
		"need": "a site with Earth visible at least 90% of the time", "kind": "site", "zone": "antenna",
		"history": "During Artemis I, contact with NASA's Deep Space Network was lost for almost an hour."},
}
const FAULT_ORDER := ["engine", "oxygen", "shield", "radar", "power", "comms"]
const SHIP_WEAK := {
	"iskra": 2, "zond": 1, "sokol": 1, "kolibri": 2, "phoenix": 1,
	"selena": 1, "buran": 1, "tyazh": 2, "titan": 1,
}

const PRIORITIES := {
	"ice": {"name": "Water ice at the south pole", "modules": ["radar", "spectro", "drill", "samples"],
		"site_tag": "ice", "why": "Ice means water, oxygen and fuel for a future lunar base.",
		"source": "LCROSS (2009), LRO, Artemis III Science Definition Team (2020)"},
	"quakes": {"name": "Moonquakes and the lunar interior", "modules": ["seismo"], "site_tag": "",
		"why": "Apollo seismometers recorded thousands of moonquakes between 1969 and 1977.",
		"source": "Apollo PSE; NASA Space Apps 2022–2023 'Make a Moonquake Map'"},
	"magnet": {"name": "Magnetic anomalies", "modules": ["magneto"], "site_tag": "swirl",
		"why": "The Moon has no global magnetic field, but it has 'magnetic patches' and bright swirls.",
		"source": "Lunar Prospector, NASA's Lunar Vertex mission"},
	"volcano": {"name": "Volcanism of the lunar maria", "modules": ["spectro", "camera", "rover"], "site_tag": "mare",
		"why": "The maria are frozen lava; their composition tells us about the Moon's interior.",
		"source": "Apollo 11–17 samples, LRO cameras (LROC)"},
	"impacts": {"name": "Ancient crust and impact history", "modules": ["samples", "drill", "rover"],
		"site_tag": "highland", "why": "Highland rocks preserve a record of the bombardment of the Earth and the Moon.",
		"source": "Apollo 16, Planetary Decadal Survey 2023–2032 priorities"},
	"mapping": {"name": "Artemis landing site map", "modules": ["camera", "radar"], "site_tag": "",
		"why": "Detailed images and terrain are needed to pick safe landing sites.",
		"source": "LRO: LOLA and LROC; Space Apps 2021 'Planetary Lander Video Game'"},
}
const PRIORITY_ORDER := ["ice", "quakes", "magnet", "volcano", "impacts", "mapping"]
const SITE_TAG_NAMES := {"ice": "ice", "mare": "lunar mare", "highland": "ancient highlands", "swirl": "magnetic swirl"}

const METEOR_STREAMS := ["Perseids", "Leonids", "Geminids", "Quadrantids", "Orionids",
	"Taurids", "Lyrids", "Draconids"]

const SOURCES := [
	"NASA Earth and Moon Fact Sheets: masses, radii and the Moon's orbit.",
	"Apollo Flight Journal (NASA): 185 km parking orbit, translunar injection ≈ 3.1 km/s, transit ≈ 3 days, free-return trajectory.",
	"Artemis I (NASA, 2022): translunar injection by the ICPS stage; SLS and Orion launch footage.",
	"NASA, Artemis III landing regions: 13 regions (2022) and 9 regions (2024) near the south pole; criteria are slope, lighting, Earth visibility and proximity to permanent shadow.",
	"LRO: LOLA altimeter and LROC cameras; the in-game Moon map is NASA SVS 'CGI Moon Kit'.",
	"LCROSS (NASA, 2009): water ice in Cabeus crater.",
	"NASA Space Apps Challenge: 2018, choosing lunar landing sites using Moon Trek and LRO data; 2021, 'Planetary Lander Video Game'; 2022–2023, 'Make a Moonquake Map' (Apollo seismometers).",
	"NASA Meteoroid Environment Office: meteor showers near the Earth and the Moon.",
]


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


static func site_fits_priority(site_id: String, prio_id: String) -> bool:
	var tag: String = PRIORITIES[prio_id]["site_tag"]
	return tag == "" or SITES[site_id]["tags"].has(tag)


static func module_is_priority(module_id: String, priorities: Array) -> bool:
	for p in priorities:
		if PRIORITIES[p]["modules"].has(module_id):
			return true
	return false
