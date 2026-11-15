@tool
extends Control

const W := 519.0
const H := 522.0
const U := 4.0
const YELLOW := Color("#fbf236")
const LIGHT := Color("#fffb9f")
const BIG: Array[String] = ["...Y...", "...Y...", "..YWY..", "YYWYWYY", "..YWY..", "...Y...", "...Y..."]
const SMALL: Array[String] = ["..Y..", ".YWY.", "YWWWY", ".YWY.", "..Y.."]
const STAR_POSITIONS := [
	[89.5, 18.5, 1], [189.5, 30.5, 0], [293.5, 62.5, 0], [53.5, 66.5, 0], [393.5, 74.5, 0],
	[505.5, 102.5, 0], [237.5, 110.5, 0], [157.5, 158.5, 1], [357.5, 178.5, 1], [25.5, 190.5, 0],
	[233.5, 198.5, 0], [421.5, 238.5, 0], [133.5, 246.5, 0], [301.5, 282.5, 0], [89.5, 286.5, 0],
	[205.5, 310.5, 0], [469.5, 326.5, 1], [365.5, 362.5, 0], [93.5, 386.5, 0], [249.5, 398.5, 0],
	[441.5, 410.5, 0], [197.5, 466.5, 1], [101.5, 486.5, 0], [385.5, 494.5, 1],
]

var _stars: Array[Dictionary] = []
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in STAR_POSITIONS:
		_stars.append({
			"pos": Vector2(p[0], p[1]),
			"shape": BIG if p[2] == 1 else SMALL,
			"period": randf_range(1.5, 4.0),
			"phase": randf() * TAU,
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	var k: float = max(size.x / W, size.y / H)
	var offset := (size - Vector2(W, H) * k) / 2.0
	draw_set_transform(offset, 0.0, Vector2(k, k))
	for s in _stars:
		var v := (sin(_time * TAU / s.period + s.phase) + 1.0) / 2.0
		var stepped := roundf(v * 4.0) / 4.0
		_draw_star(s, 0.15 + 0.85 * stepped)
	draw_set_transform(Vector2.ZERO)


func _draw_star(s: Dictionary, alpha: float) -> void:
	var shape: Array[String] = s.shape
	var n := shape.size()
	var x0 := roundf(s.pos.x - n * U / 2.0 + 0.5)
	var y0 := roundf(s.pos.y - n * U / 2.0 + 0.5)
	for j in n:
		for i in n:
			var c := shape[j][i]
			if c == ".":
				continue
			var col := LIGHT if c == "W" else YELLOW
			col.a = alpha
			draw_rect(Rect2(x0 + i * U, y0 + j * U, U, U), col)
