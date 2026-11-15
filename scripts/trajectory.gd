extends RefCounted
## Полёт к Луне: плоская ограниченная задача трёх тел (Земля, Луна, корабль).
## Начало координат — центр Земли (учтено и то, что Луна тянет саму Землю).
## Интегрирование — Рунге — Кутта 4-го порядка с переменным шагом, в двойной
## точности. Один и тот же код строит предпросмотр у диспетчера и «настоящий»
## полёт на сервере, поэтому они совпадают.

const F = preload("res://scripts/flight_data.gd")


static func leo_radius() -> float:
	return F.R_EARTH + F.LEO_ALT


static func moon_pos(phi0: float, t: float) -> Vector2:
	var a := phi0 + F.MOON_RATE * t
	return Vector2(cos(a), sin(a)) * F.MOON_DIST


static func hazard_pos(h: Dictionary, t: float) -> Vector2:
	return Vector2(float(h["x"]) + float(h["vx"]) * t, float(h["y"]) + float(h["vy"]) * t)


## Ускорение корабля (км/с²) в точке x, y в момент t.
static func _acc(x: float, y: float, t: float, phi0: float) -> PackedFloat64Array:
	var a := phi0 + F.MOON_RATE * t
	var mx := F.MOON_DIST * cos(a)
	var my := F.MOON_DIST * sin(a)
	var r2 := x * x + y * y
	var r3 := r2 * sqrt(r2)
	var dx := x - mx
	var dy := y - my
	var d2 := dx * dx + dy * dy
	var d3 := d2 * sqrt(d2)
	var m3 := F.MOON_DIST * F.MOON_DIST * F.MOON_DIST
	return PackedFloat64Array([
		-F.MU_EARTH * x / r3 - F.MU_MOON * dx / d3 - F.MU_MOON * mx / m3,
		-F.MU_EARTH * y / r3 - F.MU_MOON * dy / d3 - F.MU_MOON * my / m3,
	])


## Полёт после разгона с опорной орбиты в точке theta (рад) импульсом dv (км/с).
## phi0 — положение Луны в момент разгона. hazards — метеорные потоки.
static func simulate(phi0: float, theta: float, dv: float, hazards: Array = [], t_max: float = 691200.0) -> Dictionary:
	var r0 := leo_radius()
	var vc := sqrt(F.MU_EARTH / r0)
	var x := r0 * cos(theta)
	var y := r0 * sin(theta)
	var vx := -(vc + dv) * sin(theta)
	var vy := (vc + dv) * cos(theta)
	var t := 0.0
	var pts := PackedVector2Array()
	var rel := PackedVector2Array()
	var ts := PackedFloat64Array()
	var status := "fly"
	var dmin := INF
	var peri_t := 0.0
	var peri_i := 0
	var vrel := 0.0
	var side := 0.0
	var passed := false
	var ret_min := INF
	var ret_t := 0.0
	var apogee := 0.0
	var cross_t := -1.0
	var cross_ang := 0.0
	var hz_hits := {}
	while t < t_max:
		var ma := phi0 + F.MOON_RATE * t
		var mx := F.MOON_DIST * cos(ma)
		var my := F.MOON_DIST * sin(ma)
		var r := sqrt(x * x + y * y)
		var dx := x - mx
		var dy := y - my
		var d := sqrt(dx * dx + dy * dy)
		pts.append(Vector2(x, y))
		rel.append(Vector2(dx, dy))
		ts.append(t)
		apogee = maxf(apogee, r)
		if cross_t < 0.0 and r >= F.MOON_DIST:
			cross_t = t
			cross_ang = wrapf(atan2(y, x) - ma, -PI, PI)
		for i in hazards.size():
			if hz_hits.has(i):
				continue
			var hp := hazard_pos(hazards[i], t)
			if Vector2(x, y).distance_to(hp) < float(hazards[i]["r"]):
				hz_hits[i] = t
		if d < F.R_MOON:
			status = "impact"
			dmin = d
			peri_t = t
			peri_i = pts.size() - 1
			break
		if not passed:
			if d < dmin:
				dmin = d
				peri_t = t
				peri_i = pts.size() - 1
				var mvx := -F.MOON_DIST * F.MOON_RATE * sin(ma)
				var mvy := F.MOON_DIST * F.MOON_RATE * cos(ma)
				vrel = sqrt((vx - mvx) * (vx - mvx) + (vy - mvy) * (vy - mvy))
				side = (dx * mvx + dy * mvy) / maxf(d * sqrt(mvx * mvx + mvy * mvy), 1e-9)
			elif dmin < 200000.0 and d > dmin + 500.0 and d > dmin * 1.05:
				passed = true
		else:
			if r < ret_min:
				ret_min = r
				ret_t = t
		if t > 3600.0 and r < F.R_EARTH + 120.0:
			status = "returned" if passed else "reentry"
			break
		if r > 1.2e6:
			status = "escape"
			break
		var dt := clampf(0.02 * minf(sqrt(r * r * r / F.MU_EARTH), sqrt(d * d * d / F.MU_MOON)), 5.0, 3600.0)
		var k1 := _acc(x, y, t, phi0)
		var x2 := x + 0.5 * dt * vx
		var y2 := y + 0.5 * dt * vy
		var vx2 := vx + 0.5 * dt * k1[0]
		var vy2 := vy + 0.5 * dt * k1[1]
		var k2 := _acc(x2, y2, t + 0.5 * dt, phi0)
		var x3 := x + 0.5 * dt * vx2
		var y3 := y + 0.5 * dt * vy2
		var vx3 := vx + 0.5 * dt * k2[0]
		var vy3 := vy + 0.5 * dt * k2[1]
		var k3 := _acc(x3, y3, t + 0.5 * dt, phi0)
		var x4 := x + dt * vx3
		var y4 := y + dt * vy3
		var vx4 := vx + dt * k3[0]
		var vy4 := vy + dt * k3[1]
		var k4 := _acc(x4, y4, t + dt, phi0)
		x += dt / 6.0 * (vx + 2.0 * vx2 + 2.0 * vx3 + vx4)
		y += dt / 6.0 * (vy + 2.0 * vy2 + 2.0 * vy3 + vy4)
		vx += dt / 6.0 * (k1[0] + 2.0 * k2[0] + 2.0 * k3[0] + k4[0])
		vy += dt / 6.0 * (k1[1] + 2.0 * k2[1] + 2.0 * k3[1] + k4[1])
		t += dt
	var hits := []
	for i in hz_hits:
		hits.append([i, hz_hits[i]])
	var loi := 0.0
	if status != "impact" and dmin < INF:
		loi = vrel - sqrt(F.MU_MOON / dmin)
	var ret_alt := ret_min - F.R_EARTH
	return {
		"pts": pts, "rel": rel, "ts": ts, "status": status,
		"peri_alt": dmin - F.R_MOON, "peri_t": peri_t, "peri_i": peri_i, "side": side,
		"loi_dv": loi, "passed": passed,
		"free_return": passed and ret_alt < F.FREE_RETURN_ALT,
		"return_alt": ret_alt, "return_t": ret_t,
		"apogee": apogee, "cross_t": cross_t, "cross_ang": cross_ang,
		"hazards": hits, "t_end": t,
	}


## Точка траектории в момент t (key: "pts" — от Земли, "rel" — от Луны).
static func sample(traj: Dictionary, key: String, t: float) -> Vector2:
	var ts: PackedFloat64Array = traj["ts"]
	var arr: PackedVector2Array = traj[key]
	var n := ts.size()
	if n == 0:
		return Vector2.ZERO
	if t <= ts[0]:
		return arr[0]
	if t >= ts[n - 1]:
		return arr[n - 1]
	var i := ts.bsearch(t)
	var k := (t - ts[i - 1]) / maxf(ts[i] - ts[i - 1], 1e-9)
	return arr[i - 1].lerp(arr[i], k)


## Скорость (км/с) относительно Земли в момент t.
static func speed_at(traj: Dictionary, t: float) -> float:
	var ts: PackedFloat64Array = traj["ts"]
	var arr: PackedVector2Array = traj["pts"]
	var n := ts.size()
	if n < 2:
		return 0.0
	var i := clampi(ts.bsearch(t), 1, n - 1)
	return arr[i].distance_to(arr[i - 1]) / maxf(ts[i] - ts[i - 1], 1e-9)


## Длительность перелёта до Луны в сутках.
static func transit_days(traj: Dictionary) -> float:
	return float(traj["peri_t"]) / F.DAY


## Бюджет Δv (км/с) по запасу топлива.
static func dv_budget(profile: String, margin: float) -> float:
	var b := F.TLI_BUDGET + (0.0 if profile == "flyby" else F.LOI_BUDGET)
	return b + clampf(margin, 0.0, 0.5) * F.MARGIN_DV


## Выполнено ли требование неисправности «траекторного» типа.
static func traj_req_ok(fault_id: String, traj: Dictionary) -> bool:
	var days := transit_days(traj)
	match fault_id:
		"engine":
			return traj["free_return"]
		"oxygen":
			return traj["free_return"] and days <= 3.0
		"shield":
			return days <= 2.5
	return true


## Выполнено ли требование неисправности для места посадки.
static func site_req_ok(fault_id: String, site_id: String) -> bool:
	var s: Dictionary = F.SITES[site_id]
	match fault_id:
		"radar":
			return float(s["slope"]) <= F.SLOPE_LIMIT_RADAR
		"power":
			return int(s["light"]) >= 70
		"comms":
			return int(s["earth"]) >= 90
	return true


## Риск аварии при посадке (0..1) с учётом сломанных систем.
static func crash_risk(site_id: String, broken: Array) -> float:
	var slope := float(F.SITES[site_id]["slope"])
	if broken.has("radar"):
		return 0.0 if slope <= F.SLOPE_LIMIT_RADAR else 0.7
	return 0.0 if slope <= F.SLOPE_LIMIT else 0.25


## Проверка плана: ошибки блокируют манёвр, предупреждения — нет.
static func evaluate(traj: Dictionary, profile: String, dv: float, budget: float, hazards: Array) -> Dictionary:
	var errors: PackedStringArray = []
	var warns: PackedStringArray = []
	var peri: float = traj["peri_alt"]
	var flyby := profile == "flyby"
	var loi: float = 0.0 if flyby else maxf(float(traj["loi_dv"]), 0.0)
	var dv_total := dv + loi
	if traj["status"] == "impact":
		errors.append("Траектория врезается в Луну")
	elif peri > F.PERI_REACH:
		errors.append("Корабль проходит мимо Луны")
	else:
		if peri < F.PERI_SAFE_MIN:
			warns.append("Очень низко над Луной (%d км): опасно" % roundi(peri))
		if flyby and not traj["free_return"]:
			errors.append("Для пролёта нужна траектория свободного возврата — иначе экипаж не вернётся")
	if dv_total > budget + 0.0005:
		errors.append("Не хватит топлива: нужно %.2f км/с, есть %.2f" % [dv_total, budget])
	for hit in traj["hazards"]:
		var h: Dictionary = hazards[hit[0]]
		warns.append("Пересекает метеорный поток «%s» через %.1f сут — риск пробоя %d%%" % [
			h["name"], float(hit[1]) / F.DAY, roundi(F.METEOR_HIT_CHANCE * 100)])
	return {"ok": errors.is_empty(), "errors": errors, "warns": warns, "dv_total": dv_total, "loi": loi}


## Подсказка, куда крутить, если корабль не встречается с Луной.
static func hint(traj: Dictionary) -> String:
	if traj["status"] == "impact":
		return "Корабль врезается в Луну: немного измените точку разгона, чтобы пройти рядом."
	if float(traj["peri_alt"]) <= F.PERI_REACH:
		if not traj["free_return"]:
			return "Для свободного возврата корабль должен обогнуть Луну с обратной стороны — попробуйте сдвинуть точку разгона на десятые доли градуса."
		return "Отлично: Луна развернёт корабль обратно к Земле, даже если двигатель откажет."
	if float(traj["apogee"]) < F.MOON_DIST - 20000.0:
		return "Не хватает скорости, чтобы долететь до орбиты Луны — увеличьте Δv (W)."
	if float(traj["cross_t"]) >= 0.0:
		if float(traj["cross_ang"]) > 0.0:
			return "Корабль приходит раньше Луны — поверните точку разгона назад (A)."
		return "Луна уже ушла вперёд — поверните точку разгона вперёд (D)."
	return "Измените точку разгона или Δv."
