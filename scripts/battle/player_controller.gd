## Top-down player controller for survivor mode
extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal died

@export var move_speed: float = 120.0

# Arena bounds (set by SurvivorArena after instantiation)
var arena_min: Vector2 = Vector2(-22, 22)
var arena_max: Vector2 = Vector2(662, 368)

var sprite: AnimatedSprite2D
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect

const PLAYER_VISUAL_SCALE := Vector2(1.35, 1.35)
const DUELYST_PLAYER_SCALE := Vector2(0.72, 0.72)
const DUELYST_PLAYER_FRAMES_PATH := "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_moonlitsorcerer.tres"
const HP_BAR_WIDTH = 28.0

# Animation frames
var anim_frames: SpriteFrames
var using_duelyst_player: bool = false
var _last_hp: int = -1
var _facing_dir: Vector2 = Vector2.RIGHT

func _ready():
	anim_frames = _build_player_spriteframes()
	
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = anim_frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = DUELYST_PLAYER_SCALE if using_duelyst_player else PLAYER_VISUAL_SCALE
	sprite.play(_pick_anim(["idle", "run", "walk_down", "walk_side", "walk_up"]))
	sprite.animation_finished.connect(_on_animation_finished)
	add_child(sprite)
	
	# HP bar above player
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.size = Vector2(HP_BAR_WIDTH, 3)
	hp_bar_bg.position = Vector2(-HP_BAR_WIDTH * 0.5, -24)
	hp_bar_bg.color = Color(0.2, 0.1, 0.1)
	add_child(hp_bar_bg)
	
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(HP_BAR_WIDTH, 3)
	hp_bar_fill.position = Vector2(-HP_BAR_WIDTH * 0.5, -24)
	hp_bar_fill.color = Color(0.1, 0.8, 0.2)
	add_child(hp_bar_fill)
	
	# Collision shape
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 7.5 if using_duelyst_player else 6.0
	col.shape = shape
	add_child(col)
	
	# Player on layer 1
	collision_layer = 1
	collision_mask = 2 | 4  # Detect enemies (2) + obstacles (4)

func _build_player_spriteframes() -> SpriteFrames:
	if ResourceLoader.exists(DUELYST_PLAYER_FRAMES_PATH):
		var duelyst_frames = load(DUELYST_PLAYER_FRAMES_PATH)
		if duelyst_frames is SpriteFrames:
			using_duelyst_player = true
			return duelyst_frames
	
	using_duelyst_player = false
	return _build_survivor_spriteframes()

func _build_survivor_spriteframes() -> SpriteFrames:
	var frames = SpriteFrames.new()
	
	# Define animations: idle, walk_down, walk_side, walk_up
	var anims = {
		"idle": "res://assets/sprites/player/survivor/idle_%d.png",
		"walk_down": "res://assets/sprites/player/survivor/walk_down_%d.png",
		"walk_side": "res://assets/sprites/player/survivor/walk_side_%d.png",
		"walk_up": "res://assets/sprites/player/survivor/walk_up_%d.png",
	}
	
	for anim_name in anims:
		if anim_name != "idle":
			frames.add_animation(anim_name)
		else:
			frames.rename_animation("default", "idle")
		frames.set_animation_speed(anim_name, 6)
		frames.set_animation_loop(anim_name, true)
		for i in range(1, 5):
			var tex = load(anims[anim_name] % i)
			if tex:
				frames.add_frame(anim_name, tex)
	
	return frames

func _has_anim(name: String) -> bool:
	return sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(name)

func _pick_anim(preferred: Array[String]) -> String:
	if not anim_frames:
		return "idle"
	for anim_name in preferred:
		if anim_frames.has_animation(anim_name):
			return anim_name
	var names = anim_frames.get_animation_names()
	return names[0] if names.size() > 0 else "idle"

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
		_facing_dir = input
		if using_duelyst_player:
			sprite.play(_pick_anim(["run", "walk", "move", "walk_side", "walk_down", "walk_up", "idle"]))
			sprite.flip_h = input.x < -0.05
		else:
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
		sprite.play(_pick_anim(["idle", "run", "walk_down", "walk_side", "walk_up"]))
	
	velocity = input * move_speed
	move_and_slide()
	
	# Safety clamp — the physical wall colliders handle normal cases,
	# but this prevents tunneling at extreme speeds or edge cases.
	position.x = clampf(position.x, arena_min.x, arena_max.x)
	position.y = clampf(position.y, arena_min.y, arena_max.y)

func get_facing_direction() -> Vector2:
	if _facing_dir.length() <= 0.01:
		return Vector2.RIGHT
	return _facing_dir.normalized()

func _on_animation_finished() -> void:
	if not sprite:
		return
	if sprite.animation in ["hit", "hurt", "attack", "action"]:
		sprite.play(_pick_anim(["idle", "run", "walk_down", "walk_side", "walk_up"]))

func update_hp_bar(current: int, maximum: int):
	if hp_bar_fill:
		var ratio = float(current) / float(max(1, maximum))
		hp_bar_fill.size.x = HP_BAR_WIDTH * ratio
		# Color shift: green → yellow → red
		if ratio > 0.5:
			hp_bar_fill.color = Color(0.1, 0.8, 0.2)
		elif ratio > 0.25:
			hp_bar_fill.color = Color(0.9, 0.75, 0.1)
		else:
			hp_bar_fill.color = Color(0.9, 0.15, 0.1)
		
	if _last_hp >= 0 and current < _last_hp and _has_anim("hit"):
		sprite.play("hit")
	_last_hp = current
