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
var arena_min: Vector2 = Vector2(-22, 22)
var arena_max: Vector2 = Vector2(662, 368)

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
	
	# Per-type speed tuning
	match def.type:
		GameData.EnemyType.BAT:
			move_speed = 55.0 + randf() * 15.0  # Fast
		GameData.EnemyType.FIRE_ELEMENTAL:
			move_speed = 60.0 + randf() * 20.0  # Very fast
		GameData.EnemyType.MUSHROOM:
			move_speed = 20.0 + randf() * 10.0  # Slow
		GameData.EnemyType.ICE_GOLEM:
			move_speed = 18.0 + randf() * 8.0   # Very slow
		GameData.EnemyType.DARK_KNIGHT:
			move_speed = 35.0 + randf() * 10.0  # Moderate
		GameData.EnemyType.MIMIC:
			move_speed = 25.0 + randf() * 15.0  # Slow-moderate
	
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
	
	# Dark Knight: periodic charge burst
	if enemy_def and enemy_def.type == GameData.EnemyType.DARK_KNIGHT:
		var dist = global_position.distance_to(target.global_position)
		if dist < 120 and dist > 30 and damage_cooldown <= 0:
			speed *= 2.5  # Charge!
	
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
		_on_death()
		died.emit(self, global_position)
		queue_free()

func get_contact_damage() -> int:
	if damage_cooldown > 0:
		return 0
	damage_cooldown = 0.5
	return damage

## Special death effects based on enemy type
func _on_death():
	if not enemy_def:
		return
	match enemy_def.type:
		GameData.EnemyType.MUSHROOM:
			_death_poison_cloud()
		GameData.EnemyType.FIRE_ELEMENTAL:
			_death_explode()
		GameData.EnemyType.ICE_GOLEM:
			_death_freeze_burst()

## Mushroom: leaves a poison cloud at death position
func _death_poison_cloud():
	var cloud = Node2D.new()
	cloud.position = global_position
	cloud.z_index = -1  # Below player so character walks over the cloud
	get_parent().add_child(cloud)
	
	# Visual: scattered circular particles that drift and pulse
	var particles: Array = []
	for i in range(12):
		var p = ColorRect.new()
		var sz = randf_range(3, 7)
		p.size = Vector2(sz, sz)
		var angle = randf() * TAU
		var dist = randf_range(2, 18)
		p.position = Vector2(cos(angle), sin(angle)) * dist - p.size / 2
		p.color = Color(0.2, randf_range(0.6, 0.85), 0.1, randf_range(0.15, 0.35))
		# Round corners to look like blobs
		cloud.add_child(p)
		particles.append(p)
	
	var duration = 3.0
	var elapsed = 0.0
	var tick_acc = 0.0
	
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	cloud.add_child(timer)
	timer.timeout.connect(func():
		elapsed += 0.1
		tick_acc += 0.1
		if elapsed >= duration:
			cloud.queue_free()
			return
		# Fade out in last second
		var alpha_mult = 1.0 if elapsed < duration - 1.0 else (duration - elapsed)
		# Animate particles: drift + pulse
		for j in range(particles.size()):
			if not is_instance_valid(particles[j]):
				continue
			var p = particles[j]
			var drift = Vector2(randf_range(-0.5, 0.5), randf_range(-0.3, -0.8))
			p.position += drift
			p.modulate.a = (0.2 + sin(elapsed * 3.0 + j) * 0.1) * alpha_mult
		# Damage player if nearby
		if tick_acc >= 0.5 and is_instance_valid(target):
			tick_acc = 0.0
			if target.global_position.distance_to(cloud.position) < 30:
				GameState.poison_stacks += 1
	)

## Fire Elemental: explodes on death dealing AoE damage
func _death_explode():
	var explode_dmg = damage * 2
	var radius = 45.0
	# Damage all enemies AND player in range
	if is_instance_valid(target):
		if target.global_position.distance_to(global_position) < radius:
			GameState.take_damage_with_relics(explode_dmg)
			VFX.flash_screen(Color(1, 0.2, 0.0, 0.35), 0.2)
	# Also damage other enemies (chain reaction potential)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and is_instance_valid(e) and e.has_method("take_damage"):
			if e.global_position.distance_to(global_position) < radius:
				e.take_damage(explode_dmg / 2, (e.global_position - global_position).normalized())
	# Visual explosion
	VFX.screen_shake(3.0, 6.0)
	_spawn_death_ring(Color(1, 0.4, 0.0), radius)

## Ice Golem: freezes nearby enemies briefly on death (helps player!)
func _death_freeze_burst():
	var radius = 40.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and is_instance_valid(e):
			if e.global_position.distance_to(global_position) < radius:
				e.freeze_timer = max(e.freeze_timer, 1.5)
	_spawn_death_ring(Color(0.3, 0.6, 1.0), radius)

func _spawn_death_ring(color: Color, radius: float):
	var ring = Node2D.new()
	ring.position = global_position
	ring.z_index = 15
	get_parent().add_child(ring)
	for i in range(12):
		var angle = (i / 12.0) * TAU
		var p = ColorRect.new()
		p.size = Vector2(4, 4)
		p.position = Vector2(-2, -2)
		p.color = color
		ring.add_child(p)
		var tw = p.create_tween()
		var dest = Vector2(cos(angle), sin(angle)) * radius
		tw.tween_property(p, "position", dest, 0.3).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.35)
	get_tree().create_timer(0.5).timeout.connect(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)
