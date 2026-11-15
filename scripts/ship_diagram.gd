extends Control

const F = preload("res://scripts/flight_data.gd")
const PX := 4.0
const ZONES := {
	"capsule": [Rect2(4, 7, 13, 9)],
	"service": [Rect2(4, 16, 13, 8)],
	"solar": [Rect2(0, 17, 4, 5), Rect2(17, 17, 4, 4)],
	"antenna": [Rect2(16, 21, 5, 3)],
	"lander": [Rect2(0, 24, 21, 7)],
	"engine": [Rect2(4, 51, 13, 13)],
}

var weak: Array = []
var broken: Array = []
var _tex: Texture2D = preload("res://assets/flight/rocket_schematic.png")
var _time := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = _tex.get_size() * PX + Vector2(8, 8)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var o := Vector2(4, 4)
	draw_texture_rect(_tex, Rect2(o, _tex.get_size() * PX), false)
	var blink := 0.5 + 0.5 * sin(_time * 5.0)
	for id in weak + broken:
		var bad: bool = broken.has(id)
		for r in ZONES[F.FAULTS[id]["zone"]]:
			var rr := Rect2(o + r.position * PX, r.size * PX)
			if bad:
				draw_rect(rr, Color(1.0, 0.2, 0.15, 0.25 + 0.3 * blink))
				draw_rect(rr, Color(1.0, 0.3, 0.2), false, 2.0)
			else:
				draw_rect(rr, Color(1.0, 0.85, 0.2, 0.35 + 0.5 * blink), false, 2.0)
