extends Node
## Сетевое лобби: хост создаёт комнату, клиенты подключаются по IP.
## Каждому игроку соответствует одна из 4 ролей. Игра стартует автоматически,
## когда в комнате 4 игрока и у всех выбраны разные роли.

signal lobby_updated
signal connection_succeeded
signal connection_failed
signal server_closed
signal match_started

const DEFAULT_PORT: int = 42069
const MAX_PLAYERS: int = 4
const ROLES: Array[String] = ["analyst", "astronaut", "dispatcher", "engineer"]
const ROLE_TITLES: Dictionary = {
	"analyst": "Аналитик",
	"astronaut": "Астронавт",
	"dispatcher": "Диспетчер",
	"engineer": "Инженер",
}
const GAME_SCENE: String = "res://scenes/node_2d.tscn"
const MENU_SCENE: String = "res://scenes/control.tscn"

## peer_id -> роль ("" — роль ещё не выбрана). Источник истины — сервер.
var players: Dictionary = {}
var game_started: bool = false
var _loaded_peers: Dictionary = {}

## Персонаж, которым управляет ЭТОТ игрок (назначается в game.gd).
## Остальными персонажами управляют другие игроки по сети.
var my_character: CharacterBody2D = null
## Порт текущей комнаты (для отображения в лобби).
var port: int = DEFAULT_PORT
## Тестовый режим в одиночку (вводится словом ansharky в поле IP).
var test_mode := false
## Роль, с которой стартует тестовый режим (выбирается в меню).
var test_role := "dispatcher"
## true, пока открыто окно станции — персонаж не ходит.
var input_locked := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Публичное API для UI -----------------------------------------------------

## Создать комнату. Хост сразу занимает выбранную роль.
func start_server(role: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	self.port = port
	players = {1: role}
	lobby_updated.emit()
	return OK


## Подключиться к хосту по IP.
func start_client(ip: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	self.port = port
	return OK


## Выйти из комнаты / закрыть сервер.
func leave() -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_loaded_peers.clear()
	game_started = false
	my_character = null
	test_mode = false
	input_locked = false


## Одиночный тест: без сети, можно переключаться между всеми персонажами.
func start_test_mode(role: String = "dispatcher") -> void:
	leave()
	test_mode = true
	test_role = role if ROLES.has(role) else "dispatcher"
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


## true, если этим персонажем управляю я.
func is_my_character(node: Node) -> bool:
	return node != null and node == my_character


## Локальные IPv4-адреса этого компьютера (их хост сообщает друзьям в одной сети).
func get_local_ips() -> PackedStringArray:
	var result: PackedStringArray = []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue # IPv6, loopback, автоадреса
		result.append(ip)
	# Адреса домашних сетей (192.168.*, 10.*, 172.16-31.*) и Radmin/Hamachi (26.*, 25.*) — первыми.
	var score := func(ip: String) -> int:
		if ip.begins_with("192.168.") or ip.begins_with("10."): return 0
		if ip.begins_with("26.") or ip.begins_with("25."): return 1
		return 2
	var sorted := Array(result)
	sorted.sort_custom(func(a, b): return score.call(a) < score.call(b))
	return PackedStringArray(sorted)


func is_online() -> bool:
	return not players.is_empty()


## Запросить роль (вызывается клиентом из лобби).
func request_role(role: String) -> void:
	if multiplayer.is_server():
		_set_role(1, role)
	else:
		_rpc_request_role.rpc_id(1, role)


func my_role() -> String:
	return players.get(multiplayer.get_unique_id(), "")


func is_role_taken(role: String) -> bool:
	return players.values().has(role)


## peer_id игрока с этой ролью, 0 — если никто её не занял.
func peer_for_role(role: String) -> int:
	for pid in players:
		if players[pid] == role:
			return pid
	return 0


## Игровая сцена загрузилась у этого пира.
func notify_scene_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(1)
	else:
		_rpc_scene_loaded.rpc_id(1)


# --- Сервер -------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	if game_started or players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = ""
	_broadcast_players()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	players.erase(id)
	_loaded_peers.erase(id)
	_broadcast_players()


func _set_role(id: int, role: String) -> void:
	if game_started or not players.has(id) or not ROLES.has(role):
		return
	var owner := peer_for_role(role)
	if owner != 0 and owner != id:
		_broadcast_players() # роль уже занята — просто обновим UI клиента
		return
	players[id] = role
	_broadcast_players()
	_try_start_game()


func _try_start_game() -> void:
	if players.size() < MAX_PLAYERS:
		return
	for role in players.values():
		if role == "":
			return
	game_started = true
	_rpc_start_game.rpc()


func _mark_loaded(id: int) -> void:
	_loaded_peers[id] = true
	if _loaded_peers.size() >= players.size():
		_rpc_begin_match.rpc()


func _broadcast_players() -> void:
	_rpc_sync_players.rpc(players)


@rpc("any_peer", "reliable")
func _rpc_request_role(role: String) -> void:
	_set_role(multiplayer.get_remote_sender_id(), role)


@rpc("any_peer", "reliable")
func _rpc_scene_loaded() -> void:
	_mark_loaded(multiplayer.get_remote_sender_id())


# --- Все пиры -----------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_sync_players(data: Dictionary) -> void:
	players = data
	lobby_updated.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_start_game() -> void:
	game_started = true
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


@rpc("authority", "call_local", "reliable")
func _rpc_begin_match() -> void:
	print("[net] Матч начался, моя роль: ", my_role())
	match_started.emit()


# --- Клиент -------------------------------------------------------------------

func _on_connected_ok() -> void:
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	var was_in_game := game_started
	leave()
	server_closed.emit()
	if was_in_game:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
