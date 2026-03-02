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

var _visual_root: Node2D
var _core: ColorRect
var _tip: ColorRect
var _rune_l: ColorRect
var _rune_r: ColorRect
var _trail: Line2D
var _trail_points: Array[Vector2] = []

var _visual_color: Color = Color(1, 0.9, 0.3, 1.0)
var _visual_size: float = 4.0

func _ready():
	_build_visual()
	
	# Collision
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 3.0
	col.shape = shape
	add_child(col)
	
	# Projectile monitors layer 2 (enemies)
	collision_layer = 0  # Projectile has no layer itself
	collision_mask = 2   # Detect enemies on layer 2
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	
	body_entered.connect(_on_body_entered)

func _build_visual():
	_trail = Line2D.new()
	_trail.width = 2.0
	_trail.default_color = Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.45)
	_trail.z_index = -1
	add_child(_trail)
	
	_visual_root = Node2D.new()
	_visual_root.z_index = 1
	add_child(_visual_root)
	
	_core = ColorRect.new()
	_core.color = _visual_color
	_visual_root.add_child(_core)
	
	_tip = ColorRect.new()
	_tip.color = _visual_color.lightened(0.28)
	_visual_root.add_child(_tip)
	
	_rune_l = ColorRect.new()
	_rune_l.color = _visual_color.lightened(0.15)
	_visual_root.add_child(_rune_l)
	
	_rune_r = ColorRect.new()
	_rune_r.color = _visual_color.lightened(0.15)
	_visual_root.add_child(_rune_r)
	
	_refresh_visual_style()

func _refresh_visual_style():
	if not _core:
		return
	
	var shaft_len = max(6.0, _visual_size * 2.2)
	var shaft_h = max(2.0, _visual_size * 0.72)
	var tip_size = max(2.0, _visual_size * 0.95)
	var rune_size = max(1.5, _visual_size * 0.45)
	
	_core.size = Vector2(shaft_len, shaft_h)
	_core.position = Vector2(-shaft_len * 0.5, -shaft_h * 0.5)
	
	_tip.size = Vector2(tip_size, tip_size)
	_tip.position = Vector2(shaft_len * 0.5 - tip_size * 0.2, -tip_size * 0.5)
	
	_rune_l.size = Vector2(rune_size, rune_size)
	_rune_l.position = Vector2(-shaft_len * 0.15, -shaft_h * 0.5 - rune_size * 0.9)
	
	_rune_r.size = Vector2(rune_size, rune_size)
	_rune_r.position = Vector2(-shaft_len * 0.15, shaft_h * 0.5 - rune_size * 0.1)
	
	_core.color = _visual_color
	_tip.color = _visual_color.lightened(0.28)
	_rune_l.color = _visual_color.lightened(0.15)
	_rune_r.color = _visual_color.lightened(0.15)
	if _trail:
		_trail.width = max(1.2, _visual_size * 0.7)
		_trail.default_color = Color(_visual_color.r, _visual_color.g, _visual_color.b, 0.45)

func _physics_process(delta):
	position += direction * speed * delta
	if _visual_root:
		_visual_root.rotation = direction.angle()
	_update_trail()
	
	lifetime -= delta
	# Despawn if out of arena bounds or lifetime expired
	if lifetime <= 0 or position.x < arena_min.x or position.x > arena_max.x \
			or position.y < arena_min.y or position.y > arena_max.y:
		if aoe_radius > 0:
			_explode()
		queue_free()

func _update_trail():
	if not _trail:
		return
	_trail_points.push_front(global_position)
	while _trail_points.size() > 9:
		_trail_points.pop_back()
	_trail.clear_points()
	for gp in _trail_points:
		_trail.add_point(gp - global_position)

func _on_body_entered(body):
	if body.has_method("take_damage") and not hits.has(body):
		hits.append(body)
		var kb_dir = (body.global_position - global_position).normalized()
		body.take_damage(damage, kb_dir)
		_spawn_hit_sparks(kb_dir)
		
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

func _spawn_hit_sparks(kb_dir: Vector2):
	if not get_parent():
		return
	for i in range(4):
		var line = Line2D.new()
		line.width = max(1.2, _visual_size * 0.45)
		line.default_color = _visual_color.lightened(0.2)
		line.z_index = 14
		line.add_point(global_position)
		var dir = kb_dir
		if dir.length() < 0.01:
			dir = Vector2.RIGHT.rotated(randf() * TAU)
		dir = dir.rotated(randf_range(-0.8, 0.8))
		line.add_point(global_position + dir * randf_range(8.0, 16.0))
		get_parent().add_child(line)
		var tw = line.create_tween()
		tw.tween_property(line, "modulate:a", 0.0, 0.14)
		tw.tween_callback(line.queue_free)

func _explode():
	# AoE damage on expiry/impact
	var bodies = get_tree().get_nodes_in_group("enemies")
	for b in bodies:
		if b.has_method("take_damage"):
			var dist = b.global_position.distance_to(global_position)
			if dist <= aoe_radius and not hits.has(b):
				var kb = (b.global_position - global_position).normalized()
				b.take_damage(damage / 2, kb)
	_spawn_hit_sparks(Vector2.ZERO)

func setup_visual(color: Color, size_px: float = 4.0):
	_visual_color = color
	_visual_size = size_px
	_refresh_visual_style()
