extends Node2D

const Blocking = preload("res://scripts/character_blocking.gd")
const ASTRONAUT_RETURN := Vector2(445, 280)

var ui: CanvasLayer


func _ready() -> void:
	var net := HighLevelNetworkHandler
	ui = preload("res://scripts/mission_ui.gd").new()
	add_child(ui)
	Blocking.setup(_characters())
	Music.play("base")
	MissionState.changed.connect(_sync_astronaut)
	MissionState.changed.connect(_sync_music)
	for ws in find_children("*", "Node2D"):
		if ws is Workstation:
			ws.used.connect(_on_station_used)

	if not net.is_online():
		_set_sync_visible(false)
		net.my_character = get_node_or_null(net.test_role)
		MissionState.start_campaign()
		return

	for role in net.ROLES:
		var character := get_node_or_null(role)
		if character == null:
			continue
		var pid := net.peer_for_role(role)
		character.set_multiplayer_authority(pid if pid != 0 else 1, true)
	net.match_started.connect(_on_match_started)
	net.notify_scene_loaded()


func _on_match_started() -> void:
	var net := HighLevelNetworkHandler
	_set_sync_visible(true)
	net.my_character = get_node_or_null(net.my_role())
	print("[game] my character: ", net.my_character.name if net.my_character else "none")
	MissionState.start_campaign()


func _on_station_used(role: String) -> void:
	ui.open_station(role)


func _sync_astronaut() -> void:
	var astro := get_node_or_null("astronaut") as CharacterBody2D
	if astro == null:
		return
	var flying: bool = not MissionState.state.get("flight", {}).is_empty()
	if astro.visible != flying:
		return
	astro.visible = not flying
	astro.get_node("CollisionShape2D").set_deferred("disabled", flying)
	if not flying and astro.is_multiplayer_authority():
		astro.position = ASTRONAUT_RETURN


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and ui.handle_interact():
		get_viewport().set_input_as_handled()
		return
	if HighLevelNetworkHandler.is_online() or ui.is_open():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_F9:
		MissionState.debug_next_day()
	elif event.physical_keycode == KEY_F10:
		MissionState.debug_resources()


func _exit_tree() -> void:
	HighLevelNetworkHandler.my_character = null
	HighLevelNetworkHandler.input_locked = false
	MissionState.stop_campaign()


func _characters() -> Array:
	var out := []
	for role in HighLevelNetworkHandler.ROLES:
		var c := get_node_or_null(role)
		if c is CharacterBody2D:
			out.append(c)
	return out


func _sync_music() -> void:
	Music.play_for_state(MissionState.state)


func _set_sync_visible(v: bool) -> void:
	for s in find_children("*", "MultiplayerSynchronizer"):
		s.public_visibility = v
