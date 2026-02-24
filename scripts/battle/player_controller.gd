## Top-down player controller for survivor mode
extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal died

@export var move_speed: float = 120.0

# Arena bounds (set by SurvivorArena after instantiation)
var arena_min: Vector2 = Vector2(-10, 22)
var arena_max: Vector2 = Vector2(650, 358)

var sprite: AnimatedSprite2D
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect

# Animation frames
var anim_frames: SpriteFrames

func _ready():
	# Build animated sprite from survivor spritesheet frames
	anim_frames = SpriteFrames.new()
	
	# Define animations: idle, walk_down, walk_side, walk_up
	var anims = {
		"idle": "res://assets/sprites/player/survivor/idle_%d.png",
		"walk_down": "res://assets/sprites/player/survivor/walk_down_%d.png",
		"walk_side": "res://assets/sprites/player/survivor/walk_side_%d.png",
		"walk_up": "res://assets/sprites/player/survivor/walk_up_%d.png",
	}
	
	for anim_name in anims:
		if anim_name != "idle":  # "default" already exists, we'll rename
			anim_frames.add_animation(anim_name)
		else:
			anim_frames.rename_animation("default", "idle")
		anim_frames.set_animation_speed(anim_name, 6)
		anim_frames.set_animation_loop(anim_name, true)
		for i in range(1, 5):
			var tex = load(anims[anim_name] % i)
			if tex:
				anim_frames.add_frame(anim_name, tex)
	
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = anim_frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play("idle")
	add_child(sprite)
	
	# HP bar above player
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(20, 3)
	hp_bar_bg.position = Vector2(-10, -20)
	hp_bar_bg.color = Color(0.2, 0.1, 0.1)
	add_child(hp_bar_bg)
	
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(20, 3)
	hp_bar_fill.position = Vector2(-10, -20)
	hp_bar_fill.color = Color(0.1, 0.8, 0.2)
	add_child(hp_bar_fill)
	
	# Collision shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 6.0
	col.shape = shape
	add_child(col)
	
	# Player on layer 1
	collision_layer = 1
	collision_mask = 2 | 4  # Detect enemies (2) + obstacles (4)

func _physics_process(_delta):
	var input = Vector2.ZERO
	input.x = Input.get_axis("ui_left", "ui_right")
	input.y = Input.get_axis("ui_up", "ui_down")
	
	# Also support WASD
	if Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_key_pressed(KEY_D): input.x += 1
	if Input.is_key_pressed(KEY_W): input.y -= 1
	if Input.is_key_pressed(KEY_S): input.y += 1
	
	if input.length() > 0:
		input = input.normalized()
		# Choose animation based on dominant direction
		if abs(input.x) > abs(input.y):
			sprite.play("walk_side")
			sprite.flip_h = input.x < 0
		elif input.y > 0:
			sprite.play("walk_down")
			sprite.flip_h = false
		else:
			sprite.play("walk_up")
			sprite.flip_h = false
	else:
		sprite.play("idle")
	
	velocity = input * move_speed
	move_and_slide()
	
	# Safety clamp — the physical wall colliders handle normal cases,
	# but this prevents tunneling at extreme speeds or edge cases.
	position.x = clampf(position.x, arena_min.x, arena_max.x)
	position.y = clampf(position.y, arena_min.y, arena_max.y)

func update_hp_bar(current: int, maximum: int):
	if hp_bar_fill:
		hp_bar_fill.size.x = 20.0 * current / max(1, maximum)
