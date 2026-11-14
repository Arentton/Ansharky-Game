extends CharacterBody2D

enum {
	UP,
	DOWN,
	RIGHT,
	LEFT
}

const SPEED = 300.0
@onready var anim=$AnimatedSprite2D
var idleDir = DOWN

func _physics_process(_delta: float) -> void:
	if not HighLevelNetworkHandler.is_my_character(self):
		# Этим персонажем управляет другой игрок: позиция и анимация приходят по сети.
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
		anim.play("walk_forward_analyst")
	elif Input.is_action_pressed("moveBack"):
		idleDir=DOWN
		velocity=Vector2(0,+SPEED)
		anim.flip_h=false
		anim.play("walk_down_analyst")
	elif Input.is_action_pressed("move_left"):
		idleDir=LEFT
		velocity=Vector2(-SPEED,0)
		anim.flip_h=true
		anim.play("walk_right_analyst")
	elif Input.is_action_pressed("move_right"):
		idleDir=RIGHT
		velocity=Vector2(+SPEED,0)
		anim.flip_h=false
		anim.play("walk_right_analyst")
	else:
		if idleDir==DOWN:
			anim.play("idle_down_analyst")
		elif idleDir==UP:
			anim.play("idle_up_analyst")
		else:
			# для LEFT flip_h уже включён — idle_right смотрит влево
			anim.play("idle_right_analyst")
		velocity=Vector2(0,0)

	move_and_slide()
