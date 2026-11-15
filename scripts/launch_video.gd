extends CanvasLayer
## Ролик пуска (assets/flight/launch.ogv — пиксельный пуск SLS и Orion)
## на весь экран. Пробел, Esc, E или кнопка — пропустить.

signal closed

const VIDEO := "res://assets/flight/launch.ogv"

var _done := false


func _ready() -> void:
	layer = 30
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var box := AspectRatioContainer.new()
	box.ratio = 16.0 / 9.0
	box.stretch_mode = AspectRatioContainer.STRETCH_FIT
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var player := VideoStreamPlayer.new()
	player.expand = true
	player.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stream = load(VIDEO)
	if stream == null:
		_close.call_deferred()
		return
	player.stream = stream
	box.add_child(player)
	player.finished.connect(_close)
	player.play()
	var skip := Button.new()
	skip.text = "Пропустить ▶  [Пробел]"
	skip.anchor_left = 1.0
	skip.anchor_right = 1.0
	skip.anchor_top = 1.0
	skip.anchor_bottom = 1.0
	skip.offset_left = -230
	skip.offset_right = -16
	skip.offset_top = -52
	skip.offset_bottom = -16
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_close)
	add_child(skip)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if _done:
		return
	_done = true
	closed.emit()
	queue_free()
