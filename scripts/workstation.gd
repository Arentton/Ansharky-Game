class_name Workstation
extends Node2D

signal used(role: String)

const ROLE_TITLES := {
	"analyst": "Analyst",
	"astronaut": "Astronaut",
	"dispatcher": "Dispatcher",
	"engineer": "Engineer",
}

@export_enum("analyst", "astronaut", "dispatcher", "engineer") var role: String = "analyst"
@export var station_name: String = "Workstation"
@export var action_text: String = "Work"

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $InteractArea
@onready var hint: Label = $Hint

var _owner_body: Node2D = null
var _others: Array[Node2D] = []
var _busy := false


func _ready() -> void:
	sprite.material = sprite.material.duplicate()
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	_refresh()


func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D or not _is_local(body):
		return
	if String(body.name) == role:
		_owner_body = body
	elif not _others.has(body):
		_others.append(body)
	_refresh()


func _on_body_exited(body: Node2D) -> void:
	if body == _owner_body:
		_owner_body = null
	_others.erase(body)
	_refresh()


func _is_local(body: Node) -> bool:
	return HighLevelNetworkHandler.is_my_character(body)


func _refresh() -> void:
	var near := _owner_body != null
	sprite.material.set_shader_parameter("enabled", near)
	if _busy:
		return
	if near:
		hint.text = "[E] %s — %s" % [station_name, action_text]
		hint.modulate = Color(1.0, 0.9, 0.3)
		hint.visible = true
	elif not _others.is_empty():
		hint.text = "%s: %s only" % [station_name, ROLE_TITLES.get(role, role)]
		hint.modulate = Color(0.75, 0.78, 0.9, 0.85)
		hint.visible = true
	else:
		hint.visible = false


func _process(_delta: float) -> void:
	if _owner_body == null or HighLevelNetworkHandler.input_locked:
		return
	if Input.is_action_just_pressed("interact"):
		interact()


func interact() -> void:
	used.emit(role)
	if _is_online():
		_rpc_used.rpc()
	else:
		_rpc_used()


func _is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


@rpc("any_peer", "call_local", "reliable")
func _rpc_used() -> void:
	_busy = true
	hint.text = "%s: %s..." % [ROLE_TITLES.get(role, role), action_text.to_lower()]
	hint.modulate = Color(0.5, 1.0, 0.6)
	hint.visible = true
	var t := create_tween()
	t.tween_property(sprite, "modulate", Color(1.6, 1.6, 1.3), 0.12)
	t.tween_property(sprite, "modulate", Color.WHITE, 0.35)
	t.tween_interval(0.9)
	t.tween_callback(func():
		_busy = false
		_refresh())
