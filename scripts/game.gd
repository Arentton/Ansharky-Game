extends Node2D
## Игровая сцена: раздаёт персонажей игрокам согласно выбранным ролям.
## Мой персонаж записывается в HighLevelNetworkHandler.my_character —
## управлять клавишами можно только им.
## Тестовый режим (ansharky в поле IP или запуск сцены через F6):
## один игрок, старт за роль из меню, клавиши 1–4 переключают персонажа.

@onready var status_label: Label = %StatusLabel

const TEST_KEYS := {KEY_1: "analyst", KEY_2: "astronaut", KEY_3: "dispatcher", KEY_4: "engineer"}

var ui: CanvasLayer


func _ready() -> void:
	var net := HighLevelNetworkHandler
	ui = preload("res://scripts/mission_ui.gd").new()
	add_child(ui)
	Music.play("game")
	for ws in find_children("*", "Node2D"):
		if ws is Workstation:
			ws.used.connect(_on_station_used)

	if not net.is_online():
		_set_sync_visible(false)
		_select_test_character(net.test_role)
		MissionState.start_campaign()
		return
	# Каждым персонажем «владеет» игрок с этой ролью: только он двигает его,
	# а MultiplayerSynchronizer рассылает позицию и анимацию остальным.
	for role in net.ROLES:
		var character := get_node_or_null(role)
		if character == null:
			continue
		var pid := net.peer_for_role(role)
		character.set_multiplayer_authority(pid if pid != 0 else 1, true)
	status_label.text = "Waiting for all players to load..."
	net.match_started.connect(_on_match_started)
	net.notify_scene_loaded()


func _on_match_started() -> void:
	var net := HighLevelNetworkHandler
	_set_sync_visible(true)
	net.my_character = get_node_or_null(net.my_role())
	print("[game] my character: ", net.my_character.name if net.my_character else "none")
	status_label.text = "You are the %s" % net.ROLE_TITLES.get(net.my_role(), "?")
	MissionState.start_campaign() # сработает только у хоста


func _on_station_used(role: String) -> void:
	ui.open_station(role)


func _unhandled_input(event: InputEvent) -> void:
	if HighLevelNetworkHandler.is_online() or ui.is_open():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if TEST_KEYS.has(event.physical_keycode):
		_select_test_character(TEST_KEYS[event.physical_keycode])
	elif event.physical_keycode == KEY_F9:
		MissionState.debug_next_day()
	elif event.physical_keycode == KEY_F10:
		MissionState.debug_resources()


func _select_test_character(role: String) -> void:
	var net := HighLevelNetworkHandler
	net.my_character = get_node_or_null(role)
	status_label.text = "TEST: you are the %s   (1–4 switch character · E station · F9 next day · F10 resources)" % net.ROLE_TITLES[role]


func _exit_tree() -> void:
	HighLevelNetworkHandler.my_character = null
	HighLevelNetworkHandler.input_locked = false
	MissionState.stop_campaign()


func _set_sync_visible(v: bool) -> void:
	for s in find_children("*", "MultiplayerSynchronizer"):
		s.public_visibility = v
