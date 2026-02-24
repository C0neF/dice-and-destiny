## Enemy that chases the player in top-down view
extends CharacterBody2D

signal died(enemy: CharacterBody2D, pos: Vector2)

var enemy_def: GameData.EnemyDef
var hp: int = 10
var max_hp: int = 10
var move_speed: float = 40.0
var damage: int = 5
var target: Node2D = null  # Player reference
var knockback_vel: Vector2 = Vector2.ZERO
var damage_cooldown: float = 0.0  # Prevent damage spam
var flash_timer: float = 0.0

# Arena bounds (set by SurvivorArena after instantiation)
var arena_min: Vector2 = Vector2(-10, 22)
var arena_max: Vector2 = Vector2(650, 358)

# Status
var burn_stacks: int = 0
var poison_stacks: int = 0
var freeze_timer: float = 0.0
var slow_factor: float = 1.0

var sprite: Sprite2D
var hp_bar_fill: ColorRect

func setup(def: GameData.EnemyDef, player: Node2D, level_scale: float = 1.0):
	enemy_def = def
	hp = int(def.max_hp * level_scale)
	max_hp = hp
	damage = int(def.base_attack * level_scale)
	move_speed = 30.0 + randf() * 20.0  # Slight variation
	target = player
	
	# Sprite
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	var tex = load(def.texture_path)
	if tex:
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	
	# HP bar
	var bg = ColorRect.new()
	bg.size = Vector2(14, 2)
	bg.position = Vector2(-7, -12)
	bg.color = Color(0.3, 0.1, 0.1)
	add_child(bg)
	hp_bar_fill = ColorRect.new()
	hp_bar_fill.size = Vector2(14, 2)
	hp_bar_fill.position = Vector2(-7, -12)
	hp_bar_fill.color = Color(0.9, 0.2, 0.15)
	add_child(hp_bar_fill)
	
	# Collision
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 5.0
	col.shape = shape
	add_child(col)
	
	# Set to layer 2 (enemies)
	collision_layer = 2
	collision_mask = 4  # Only collide with obstacles, NOT player (overlap for contact damage)

func _physics_process(delta):
	if not is_instance_valid(target):
		return
	
	# Damage cooldown
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	# Flash effect
	if flash_timer > 0:
		flash_timer -= delta
		if sprite:
			sprite.modulate = Color(2, 2, 2) if fmod(flash_timer, 0.1) < 0.05 else Color.WHITE
	elif sprite:
		sprite.modulate = Color.WHITE
	
	# Freeze
	if freeze_timer > 0:
		freeze_timer -= delta
		if sprite:
			sprite.modulate = Color(0.5, 0.7, 1.0)
		return
	
	# Status ticks
	_tick_status(delta)
	
	# Chase player
	var dir = (target.global_position - global_position).normalized()
	var speed = move_speed * slow_factor
	velocity = dir * speed + knockback_vel
	knockback_vel = knockback_vel.move_toward(Vector2.ZERO, 200 * delta)
	move_and_slide()
	
	# Safety clamp to arena bounds (walls handle physics, this prevents tunneling)
	position.x = clampf(position.x, arena_min.x, arena_max.x)
	position.y = clampf(position.y, arena_min.y, arena_max.y)
	
	# Flip sprite
	if sprite and dir.x != 0:
		sprite.flip_h = dir.x < 0

var _status_tick_acc: float = 0.0
func _tick_status(delta):
	_status_tick_acc += delta
	if _status_tick_acc < 1.0:
		return
	_status_tick_acc -= 1.0
	
	if burn_stacks > 0:
		take_damage(burn_stacks, Vector2.ZERO)
		burn_stacks = max(0, burn_stacks - 1)
	if poison_stacks > 0:
		take_damage(poison_stacks, Vector2.ZERO)
		poison_stacks = max(0, poison_stacks - 1)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	hp -= amount
	flash_timer = 0.2
	knockback_vel = knockback_dir * 150
	
	if hp_bar_fill:
		hp_bar_fill.size.x = 14.0 * max(0, hp) / max(1, max_hp)
	
	if hp <= 0:
		died.emit(self, global_position)
		queue_free()

func get_contact_damage() -> int:
	if damage_cooldown > 0:
		return 0
	damage_cooldown = 0.5
	return damage
