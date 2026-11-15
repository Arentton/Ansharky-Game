extends CharacterBody2D

const Blocking = preload("res://scripts/character_blocking.gd")

enum {
	UP,
	DOWN,
	RIGHT,
	LEFT
}

const SPEED = 300.0
@onready var anim=$AnimatedSprite2D
var idleDir = DOWN

func _physics_process(delta: float) -> void:
	if not visible:
		return
	if not HighLevelNetworkHandler.is_my_character(self):
		if not anim.is_playing():
			anim.play()
		return
	if HighLevelNetworkHandler.input_locked:
		velocity=Vector2(0,0)
		return

	if Input.is_action_pressed("moveForward"):
		idleDir=UP
		velocity=Vector2(0,-SPEED)
		anim.flip_h=false
		anim.play("walk_forward_astronaut")
	elif Input.is_action_pressed("moveBack"):
		idleDir=DOWN
		velocity=Vector2(0,+SPEED)
		anim.flip_h=false
		anim.play("walk_down_astronaut")
	elif Input.is_action_pressed("move_left"):
		idleDir=LEFT
		velocity=Vector2(-SPEED,0)
		anim.flip_h=true
		anim.play("walk_right_astronaut")
	elif Input.is_action_pressed("move_right"):
		idleDir=RIGHT
		velocity=Vector2(+SPEED,0)
		anim.flip_h=false
		anim.play("walk_right_astronaut")
	else:
		if idleDir==DOWN:
			anim.play("idle_down_astronaut")
		elif idleDir==UP:
			anim.play("idle_up_astronaut")
		else:
			anim.play("idle_right_astronaut")
		velocity=Vector2(0,0)

	velocity = Blocking.resolve(self, velocity, delta)
	move_and_slide()
