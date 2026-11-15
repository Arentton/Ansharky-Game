extends Control
## Главное меню: Server -> выбор роли -> лобби; Client -> выбор роли + ввод IP -> лобби.
## В тестовом режиме (ansharky в поле IP) выбранная роль — стартовый персонаж.
##
## Для быстрого теста можно запускать с аргументами (после `--`):
##   --host=<роль> [--port=N]      создать комнату с этой ролью
##   --join=<ip[:порт]> [--role=<роль>]   подключиться и сразу занять роль

const NET_ROLES := ["analyst", "astronaut", "dispatcher", "engineer"]

@onready var main_panel: Control = %MainPanel
@onready var role_panel: Control = %RolePanel
@onready var join_panel: Control = %JoinPanel
@onready var lobby_panel: Control = %LobbyPanel
@onready var ip_edit: LineEdit = %IpEdit
@onready var join_status: Label = %JoinStatus
@onready var connect_button: Button = %ConnectButton
@onready var players_label: Label = %PlayersLabel
@onready var lobby_status: Label = %LobbyStatus
@onready var lobby_roles: Container = %LobbyRoles
@onready var role_buttons: Container = %RoleButtons
@onready var join_roles: Container = %JoinRoles

## Роль, выбранная клиентом до подключения; запрашивается сразу после входа.
var _auto_role := ""
var _host_info: Label
var _copy_button: Button


func _ready() -> void:
	var net := HighLevelNetworkHandler
	net.lobby_updated.connect(_refresh_lobby)
	net.connection_succeeded.connect(_on_connection_succeeded)
	net.connection_failed.connect(_on_connection_failed)
	net.server_closed.connect(_on_server_closed)

	%server.pressed.connect(_show.bind(role_panel))
	%client.pressed.connect(_on_client_pressed)
	%RoleBack.pressed.connect(_show.bind(main_panel))
	%JoinBack.pressed.connect(_show.bind(main_panel))
	%LeaveButton.pressed.connect(_on_leave_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	ip_edit.text_submitted.connect(func(_t: String) -> void: _on_connect_pressed())

	for role in NET_ROLES:
		var title: String = net.ROLE_TITLES[role]
		role_buttons.get_node(role).text = title
		role_buttons.get_node(role).pressed.connect(_on_host_role_chosen.bind(role))
		lobby_roles.get_node(role).text = title
		lobby_roles.get_node(role).pressed.connect(net.request_role.bind(role))
		join_roles.get_node(role).text = title
		join_roles.get_node(role).pressed.connect(_on_join_role_chosen.bind(role))

	_build_host_info()
	Music.play("menu")

	if net.is_online():
		_show(lobby_panel) # вернулись в меню, оставаясь в комнате
		_refresh_lobby()
	else:
		_show(main_panel)
	_show_disconnect_reason()
	_handle_cmdline.call_deferred()


## Если матч прервался (кто-то отключился), объясняем почему.
func _show_disconnect_reason() -> void:
	var net := HighLevelNetworkHandler
	if net.disconnect_reason == "":
		return
	var l := Label.new()
	l.text = net.disconnect_reason
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 320
	l.add_theme_color_override("font_color", Color(1.0, 0.42, 0.38))
	main_panel.add_child(l)
	main_panel.move_child(l, 0)
	net.disconnect_reason = ""


func _show(panel: Control) -> void:
	for p in [main_panel, role_panel, join_panel, lobby_panel]:
		p.visible = p == panel


# --- Server -------------------------------------------------------------------

func _on_host_role_chosen(role: String, port: int = HighLevelNetworkHandler.DEFAULT_PORT) -> void:
	var err := HighLevelNetworkHandler.start_server(role, port)
	if err != OK:
		_show(main_panel)
		push_error("Could not create the server (port %d busy?): %s" % [port, error_string(err)])
		return
	print("[menu] Server created, host role: ", role)
	_show(lobby_panel)
	_refresh_lobby()


# --- Client -------------------------------------------------------------------

func _on_client_pressed() -> void:
	join_status.text = ""
	connect_button.disabled = false
	_update_join_roles()
	_show(join_panel)
	ip_edit.grab_focus()


func _on_join_role_chosen(role: String) -> void:
	_auto_role = role
	_update_join_roles()
	if join_status.text == "Choose a role first":
		join_status.text = ""


func _update_join_roles() -> void:
	for role in NET_ROLES:
		join_roles.get_node(role).button_pressed = role == _auto_role


func _on_connect_pressed() -> void:
	if not NET_ROLES.has(_auto_role):
		join_status.text = "Choose a role first"
		return
	var ip := ip_edit.text.strip_edges()
	if ip.to_lower() == "ansharky":
		HighLevelNetworkHandler.start_test_mode(_auto_role)
		return
	var port := HighLevelNetworkHandler.DEFAULT_PORT
	# Можно ввести «IP:порт», например 192.168.1.5:42069
	if ip.count(":") == 1:
		var parts := ip.split(":")
		ip = parts[0]
		if not parts[1].is_valid_int():
			join_status.text = "Invalid port"
			return
		port = parts[1].to_int()
	if ip.is_empty():
		ip = "127.0.0.1"
	if not ip.is_valid_ip_address() and ip != "localhost":
		join_status.text = "Invalid IP address"
		return
	var err := HighLevelNetworkHandler.start_client(ip, port)
	if err != OK:
		join_status.text = "Error: %s" % error_string(err)
		return
	join_status.text = "Connecting to %s..." % ip
	connect_button.disabled = true


func _on_connection_succeeded() -> void:
	print("[menu] Connected to host")
	_show(lobby_panel)
	_refresh_lobby()
	if _auto_role != "":
		HighLevelNetworkHandler.request_role(_auto_role)


func _on_connection_failed() -> void:
	connect_button.disabled = false
	join_status.text = "Could not connect"
	_show(join_panel)


func _on_server_closed() -> void:
	connect_button.disabled = false
	join_status.text = "The host closed the room or it is full"
	_show(join_panel)


# --- Лобби --------------------------------------------------------------------

func _on_leave_pressed() -> void:
	HighLevelNetworkHandler.leave()
	_show(main_panel)


func _refresh_lobby() -> void:
	var net := HighLevelNetworkHandler
	var lines: PackedStringArray = []
	var my_id := multiplayer.get_unique_id()
	var ids := net.players.keys()
	ids.sort()
	for pid in ids:
		var role: String = net.players[pid]
		var who := "Host" if pid == 1 else "Player %d" % pid
		if pid == my_id:
			who += " (you)"
		var role_text: String = net.ROLE_TITLES.get(role, "choosing a role...")
		lines.append("%s — %s" % [who, role_text])
	players_label.text = "\n".join(lines)

	var mine := net.my_role()
	for role in NET_ROLES:
		var b: Button = lobby_roles.get_node(role)
		b.disabled = net.is_role_taken(role) and role != mine
		b.button_pressed = role == mine
	lobby_roles.visible = not multiplayer.is_server()
	_update_host_info()

	if mine == "":
		if _auto_role != "" and net.is_role_taken(_auto_role):
			lobby_status.text = "The %s role is taken — choose another" % net.ROLE_TITLES[_auto_role]
		else:
			lobby_status.text = "Choose a free role"
	else:
		lobby_status.text = "Waiting for players: %d / %d" % [net.players.size(), net.MAX_PLAYERS]


# --- IP и порт хоста ----------------------------------------------------------

func _build_host_info() -> void:
	_host_info = Label.new()
	_host_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_host_info.custom_minimum_size.x = 320
	lobby_panel.add_child(_host_info)
	lobby_panel.move_child(_host_info, 1)
	_copy_button = Button.new()
	_copy_button.text = "Copy IP:port"
	_copy_button.pressed.connect(_on_copy_pressed)
	lobby_panel.add_child(_copy_button)
	lobby_panel.move_child(_copy_button, 2)


func _host_address() -> String:
	var net := HighLevelNetworkHandler
	var ips: PackedStringArray = net.get_local_ips()
	return "%s:%d" % [ips[0] if not ips.is_empty() else "127.0.0.1", net.port]


func _update_host_info() -> void:
	var is_host := multiplayer.is_server() and HighLevelNetworkHandler.is_online()
	_host_info.visible = is_host
	_copy_button.visible = is_host
	if not is_host:
		return
	var net := HighLevelNetworkHandler
	var ips: PackedStringArray = net.get_local_ips()
	var text := "You are the host. Port: %d\n" % net.port
	if ips.is_empty():
		text += "No IP found — check your network connection"
	else:
		text += "IP for friends: %s" % ips[0]
		if ips.size() > 1:
			text += "\n(other addresses: %s)" % ", ".join(ips.slice(1))
	_host_info.text = text


func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(_host_address())
	_copy_button.text = "Copied: " + _host_address()


# --- Аргументы командной строки (для тестов) ----------------------------------

func _handle_cmdline() -> void:
	if HighLevelNetworkHandler.is_online():
		return
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("host"):
		_on_host_role_chosen(args["host"], int(args.get("port", HighLevelNetworkHandler.DEFAULT_PORT)))
	elif args.has("join"):
		_on_client_pressed()
		_auto_role = args.get("role", "")
		_update_join_roles()
		ip_edit.text = args["join"]
		if _auto_role != "":
			_on_connect_pressed()
