## Projectile for card-based abilities
extends Area2D

var direction: Vector2 = Vector2.RIGHT
var speed: float = 200.0
var damage: int = 5
var lifetime: float = 3.0
var pierce: int = 1  # How many enemies it can hit
var status_effect: String = ""  # "burn", "poison", "freeze"
var status_stacks: int = 0
var aoe_radius: float = 0.0  # 0 = single target
var hits: Array = []

# Arena bounds — projectiles despawn when leaving the playable area
var arena_min: Vector2 = Vector2(-20, -20)
var arena_max: Vector2 = Vector2(660, 380)

func _ready():
	# Visual
	var sprite = ColorRect.new()
	sprite.size = Vector2(4, 4)
	sprite.position = Vector2(-2, -2)
	sprite.color = Color(1, 0.9, 0.3)
	add_child(sprite)
	
	# Collision
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 3.0
	col.shape = shape
	add_child(col)
	
	# Projectile monitors layer 2 (enemies)
	collision_layer = 0  # Projectile has no layer itself
	collision_mask = 2   # Detect enemies on layer 2
	monitoring = true
	monitorable = false
	
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	position += direction * speed * delta
	lifetime -= delta
	# Despawn if out of arena bounds or lifetime expired
	if lifetime <= 0 or position.x < arena_min.x or position.x > arena_max.x \
			or position.y < arena_min.y or position.y > arena_max.y:
		if aoe_radius > 0:
			_explode()
		queue_free()

func _on_body_entered(body):
	if body.has_method("take_damage") and not hits.has(body):
		hits.append(body)
		var kb_dir = (body.global_position - global_position).normalized()
		body.take_damage(damage, kb_dir)
		
		# Apply status
		if status_effect != "" and status_stacks > 0:
			match status_effect:
				"burn": body.burn_stacks += status_stacks
				"poison": body.poison_stacks += status_stacks
				"freeze": body.freeze_timer += float(status_stacks)
		
		pierce -= 1
		if pierce <= 0:
			if aoe_radius > 0:
				_explode()
			queue_free()

func _explode():
	# AoE damage on expiry/impact
	var bodies = get_tree().get_nodes_in_group("enemies")
	for b in bodies:
		if b.has_method("take_damage"):
			var dist = b.global_position.distance_to(global_position)
			if dist <= aoe_radius and not hits.has(b):
				var kb = (b.global_position - global_position).normalized()
				b.take_damage(damage / 2, kb)

func setup_visual(color: Color, size_px: float = 4.0):
	var sprite = get_child(0)
	if sprite is ColorRect:
		sprite.color = color
		sprite.size = Vector2(size_px, size_px)
		sprite.position = -sprite.size / 2
