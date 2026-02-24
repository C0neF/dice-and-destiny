## Pickup drop item - spawns from dead enemies, player walks over to collect
extends Area2D

signal collected(drop_type: String, value: int)

enum DropType { GOLD, HEALTH_POTION, SPEED_BOOST, DAMAGE_BOOST, ENERGY_ORB, MAGNET, BOMB }

var drop_type: int = DropType.GOLD
var value: int = 1
var lifetime: float = 15.0
var magnet_speed: float = 0.0  # When attracted to player
var target: Node2D = null  # Player ref
var _blink_timer: float = 0.0
var _spawn_anim: float = 0.0
var _spawn_dir: Vector2 = Vector2.ZERO
var sprite: ColorRect
var glow: ColorRect

# Arena bounds (set by SurvivorArena)
var arena_min: Vector2 = Vector2(-22, 22)
var arena_max: Vector2 = Vector2(662, 368)

# Drop type configs: [color, size, label]
const DROP_CONFIG = {
	DropType.GOLD: [Color(1, 0.85, 0.1), 4.0, "G"],
	DropType.HEALTH_POTION: [Color(0.9, 0.15, 0.2), 5.0, "+"],
	DropType.SPEED_BOOST: [Color(0.2, 0.9, 1.0), 5.0, "S"],
	DropType.DAMAGE_BOOST: [Color(1, 0.4, 0.1), 5.0, "D"],
	DropType.ENERGY_ORB: [Color(0.4, 0.5, 1.0), 4.0, "E"],
	DropType.MAGNET: [Color(0.8, 0.8, 0.8), 5.0, "M"],
	DropType.BOMB: [Color(1, 0.3, 0.0), 6.0, "B"],
}

func setup(type: int, val: int, player: Node2D, spawn_pos: Vector2):
	drop_type = type
	value = val
	target = player
	position = spawn_pos
	# Random scatter on spawn
	_spawn_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(15, 35)
	_spawn_anim = 0.3

func _ready():
	var config = DROP_CONFIG.get(drop_type, [Color.WHITE, 4.0, "?"])
	var color: Color = config[0]
	var sz: float = config[1]
	
	# Glow effect (larger, semi-transparent)
	glow = ColorRect.new()
	glow.size = Vector2(sz * 2.5, sz * 2.5)
	glow.position = -glow.size / 2
	glow.color = Color(color.r, color.g, color.b, 0.25)
	add_child(glow)
	
	# Main sprite
	sprite = ColorRect.new()
	sprite.size = Vector2(sz, sz)
	sprite.position = -sprite.size / 2
	sprite.color = color
	add_child(sprite)
	
	# Collision for pickup
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 10.0  # Generous pickup radius
	col.shape = shape
	add_child(col)
	
	collision_layer = 0
	collision_mask = 1  # Detect player on layer 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	# Spawn scatter animation
	if _spawn_anim > 0:
		_spawn_anim -= delta
		position += _spawn_dir * delta * (_spawn_anim / 0.3) * 3.0
		# Clamp to arena bounds during scatter
		position.x = clampf(position.x, arena_min.x + 4, arena_max.x - 4)
		position.y = clampf(position.y, arena_min.y + 4, arena_max.y - 4)
		return
	
	lifetime -= delta
	
	# Blink when about to expire
	if lifetime < 3.0:
		_blink_timer += delta * 8.0
		visible = int(_blink_timer) % 2 == 0
	
	if lifetime <= 0:
		queue_free()
		return
	
	# Float/bob animation
	if sprite:
		sprite.position.y = -sprite.size.y / 2 + sin(lifetime * 4.0) * 1.5
	if glow:
		glow.position.y = -glow.size.y / 2 + sin(lifetime * 4.0) * 1.5
		glow.modulate.a = 0.4 + sin(lifetime * 6.0) * 0.2
	
	# Magnet: attract toward player
	if magnet_speed > 0 and is_instance_valid(target):
		var dir = (target.global_position - global_position).normalized()
		position += dir * magnet_speed * delta
		magnet_speed += 200 * delta  # Accelerate
	elif is_instance_valid(target):
		# Gentle pull when very close
		var dist = global_position.distance_to(target.global_position)
		if dist < 25:
			var dir = (target.global_position - global_position).normalized()
			position += dir * 60 * delta
	
	# Keep drops inside arena at all times
	position.x = clampf(position.x, arena_min.x + 4, arena_max.x - 4)
	position.y = clampf(position.y, arena_min.y + 4, arena_max.y - 4)

func _on_body_entered(body):
	if body.collision_layer & 1:  # Player layer
		collected.emit(drop_type, value)
		# Small pop effect
		_spawn_collect_particles()
		queue_free()

func _spawn_collect_particles():
	# Quick particle burst at collect position
	var config = DROP_CONFIG.get(drop_type, [Color.WHITE, 4.0, "?"])
	var color: Color = config[0]
	for i in range(4):
		var p = ColorRect.new()
		p.size = Vector2(2, 2)
		p.position = global_position - Vector2(1, 1)
		p.color = color
		p.z_index = 20
		get_parent().add_child(p)
		var tween = p.create_tween()
		var dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * 15
		tween.tween_property(p, "position", p.position + dir, 0.3)
		tween.parallel().tween_property(p, "modulate:a", 0.0, 0.3)
		tween.tween_callback(p.queue_free)

func activate_magnet():
	magnet_speed = 100.0
