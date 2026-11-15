class_name PlayerCharacter
extends CharacterBody2D

enum Dir { UP, DOWN, RIGHT, LEFT }

const SPEED := 300.0

var active := false
var idle_dir := Dir.DOWN

@onready var anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")


func _physics_process(_delta: float) -> void:
	if not active or not is_multiplayer_authority():
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("moveForward"):
		dir = Vector2.UP
		idle_dir = Dir.UP
	elif Input.is_action_pressed("moveBack"):
		dir = Vector2.DOWN
		idle_dir = Dir.DOWN
	elif Input.is_action_pressed("move_left"):
		dir = Vector2.LEFT
		idle_dir = Dir.LEFT
	elif Input.is_action_pressed("move_right"):
		dir = Vector2.RIGHT
		idle_dir = Dir.RIGHT
	velocity = dir * SPEED
	move_and_slide()
	_update_animation(dir != Vector2.ZERO)


func _process(_delta: float) -> void:
	if anim != null and not is_multiplayer_authority() and not anim.is_playing():
		anim.play()


func _update_animation(moving: bool) -> void:
	if anim == null or anim.sprite_frames == null:
		return
	var anim_name := ""
	match idle_dir:
		Dir.UP:
			anim_name = "walk_forward" if moving else "idle_up"
		Dir.DOWN:
			anim_name = "walk_down" if moving else "idle_down"
		_:
			anim_name = "walk_right" if moving else "idle_right"
	anim.flip_h = idle_dir == Dir.LEFT
	if anim.sprite_frames.has_animation(anim_name) and anim.animation != anim_name:
		anim.play(anim_name)
