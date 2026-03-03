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

var sprite
var anim_sprite: AnimatedSprite2D = null
var static_sprite: Sprite2D = null
var hp_bar_fill: ColorRect
var _status_fx_timer: float = 0.0
var _anim_time: float = 0.0
var _anim_seed: float = 0.0
var _hit_squash_timer: float = 0.0
var _base_scale: Vector2 = Vector2.ONE

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
	
	# Sprite (animated if frames exist, static fallback otherwise)
	_anim_seed = randf() * TAU
	_setup_visual(def.texture_path)
	
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

func _setup_visual(texture_path: String):
	# 1) Preferred: high-quality external animated sheets (Duelyst)
	anim_sprite = _build_duelyst_animated_sprite()
	if not anim_sprite:
		# 2) Fallback: local frame convention <enemy>/idle_1.png ...
		anim_sprite = _build_animated_sprite(texture_path)
	if anim_sprite:
		sprite = anim_sprite
		sprite.name = "Sprite"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if anim_sprite.has_meta("duelyst"):
			# Duelyst 帧资源留白较大，整体基础缩放提高
			_base_scale = Vector2(0.62, 0.62)
			if enemy_def:
				if enemy_def.is_boss:
					_base_scale = Vector2(0.78, 0.78)
				elif enemy_def.type == GameData.EnemyType.SLIME:
					# critter_1（史莱姆映射）单独放大
					_base_scale = Vector2(1.0, 1.0)
				elif enemy_def.type == GameData.EnemyType.FIRE_ELEMENTAL:
					# 红色小怪（火元素）进一步放大
					_base_scale = Vector2(0.92, 0.92)
				elif enemy_def.type == GameData.EnemyType.GOBLIN:
					# 常见红色系小怪（哥布林映射）同样放大
					_base_scale = Vector2(0.92, 0.92)
		sprite.scale = _base_scale
		add_child(sprite)
		return

	# 3) Last fallback: static sprite + procedural bob/squash
	static_sprite = Sprite2D.new()
	static_sprite.name = "Sprite"
	var tex = load(texture_path)
	if tex:
		static_sprite.texture = tex
		static_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite = static_sprite
	add_child(sprite)

func _build_duelyst_animated_sprite() -> AnimatedSprite2D:
	var path = _get_duelyst_spriteframes_path()
	if path == "" or not ResourceLoader.exists(path):
		return null
	var frames = load(path)
	if not (frames is SpriteFrames):
		return null
	var s = AnimatedSprite2D.new()
	s.sprite_frames = frames
	s.set_meta("duelyst", true)
	var start_anim = _pick_available_anim(frames, ["idle", "run", "walk", "move", "action"])
	if start_anim != "":
		s.play(start_anim)
	return s

func _get_duelyst_spriteframes_path() -> String:
	if not enemy_def:
		return ""
	match enemy_def.type:
		GameData.EnemyType.SLIME:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/critter_1.tres"
		GameData.EnemyType.SKELETON:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/boss_wraith.tres"
		GameData.EnemyType.BAT:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_monsterdragonhawk.tres"
		GameData.EnemyType.GOBLIN:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_gnasher.tres"
		GameData.EnemyType.GHOST:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_ghostlynx.tres"
		GameData.EnemyType.DEMON:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/boss_treatdemon.tres"
		GameData.EnemyType.MUSHROOM:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_blisteringscorn.tres"
		GameData.EnemyType.MIMIC:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_deceptib0t.tres"
		GameData.EnemyType.FIRE_ELEMENTAL:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_firestarter.tres"
		GameData.EnemyType.DARK_KNIGHT:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/boss_chaosknight.tres"
		GameData.EnemyType.ICE_GOLEM:
			return "res://addons/duelyst_animated_sprites/assets/spriteframes/units/neutral_golemice.tres"
		_:
			return ""

func _build_animated_sprite(texture_path: String) -> AnimatedSprite2D:
	var frames = _build_enemy_sprite_frames(texture_path)
	if not frames:
		return null
	var s = AnimatedSprite2D.new()
	s.sprite_frames = frames
	var start_anim = _pick_available_anim(frames, ["idle", "walk", "run"])
	if start_anim != "":
		s.play(start_anim)
	return s

## Optional animated assets convention (any one that exists):
## - res://assets/sprites/enemies/<enemy_id>/idle_1.png ... idle_N.png
## - res://assets/sprites/enemies/<enemy_id>/walk_1.png ... walk_N.png
## - res://assets/sprites/enemies/<enemy_id>/hit_1.png ... hit_N.png
func _build_enemy_sprite_frames(texture_path: String) -> SpriteFrames:
	var base_dir = texture_path.get_base_dir()
	var base_name = texture_path.get_file().get_basename()
	var anim_dir = base_dir.path_join(base_name)

	var idle_patterns = [
		"%s/idle_%%d.png" % anim_dir,
		"%s/%s_idle_%%d.png" % [base_dir, base_name],
		"%s/%s_%%d.png" % [base_dir, base_name],
	]
	var walk_patterns = [
		"%s/walk_%%d.png" % anim_dir,
		"%s/run_%%d.png" % anim_dir,
		"%s/%s_walk_%%d.png" % [base_dir, base_name],
	]
	var hit_patterns = [
		"%s/hit_%%d.png" % anim_dir,
		"%s/hurt_%%d.png" % anim_dir,
		"%s/%s_hit_%%d.png" % [base_dir, base_name],
	]

	var idle_frames = _collect_animation_frames(idle_patterns)
	if idle_frames.is_empty():
		return null

	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 7.0)
	frames.set_animation_loop("idle", true)
	for tex in idle_frames:
		frames.add_frame("idle", tex)

	var walk_frames = _collect_animation_frames(walk_patterns)
	if not walk_frames.is_empty():
		frames.add_animation("walk")
		frames.set_animation_speed("walk", 10.0)
		frames.set_animation_loop("walk", true)
		for tex in walk_frames:
			frames.add_frame("walk", tex)

	var hit_frames = _collect_animation_frames(hit_patterns)
	if not hit_frames.is_empty():
		frames.add_animation("hit")
		frames.set_animation_speed("hit", 16.0)
		frames.set_animation_loop("hit", false)
		for tex in hit_frames:
			frames.add_frame("hit", tex)

	return frames

func _collect_animation_frames(patterns: Array) -> Array[Texture2D]:
	for pattern in patterns:
		var out: Array[Texture2D] = []
		for i in range(1, 13):
			var path = pattern % i
			if ResourceLoader.exists(path):
				var tex = load(path)
				if tex:
					out.append(tex)
			else:
				if i == 1:
					break
				break
		if not out.is_empty():
			return out
	return []

func _pick_available_anim(frames: SpriteFrames, preferred: Array[String]) -> String:
	for name in preferred:
		if frames.has_animation(name):
			return name
	var names = frames.get_animation_names()
	return names[0] if names.size() > 0 else ""

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
		_update_status_visuals(delta)
		_animate_visual(delta, Vector2.ZERO, false)
		return
	
	# Status ticks
	_tick_status(delta)
	_update_status_visuals(delta)
	
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
	
	_animate_visual(delta, dir, true)

func _animate_visual(delta: float, _dir: Vector2, can_move: bool):
	if not sprite:
		return

	_anim_time += delta
	if _hit_squash_timer > 0:
		_hit_squash_timer = max(0.0, _hit_squash_timer - delta)

	var moving = can_move and velocity.length() > 8.0
	if anim_sprite and anim_sprite.sprite_frames:
		var frames = anim_sprite.sprite_frames
		var target_anim = ""
		if _hit_squash_timer > 0:
			target_anim = _pick_available_anim(frames, ["hit", "attack", "action", "idle", "run", "walk"])
		elif moving:
			target_anim = _pick_available_anim(frames, ["walk", "run", "move", "idle"])
		else:
			target_anim = _pick_available_anim(frames, ["idle", "run", "walk", "move"])
		if target_anim != "" and anim_sprite.animation != target_anim:
			anim_sprite.play(target_anim)

	var bob_speed = 10.0 if moving else 5.0
	var bob_amp = 1.1 if moving else 0.45
	var squash_amp = 0.045 if moving else 0.02

	if _hit_squash_timer > 0:
		bob_amp += 0.6
		squash_amp += 0.08

	var wave = sin(_anim_time * bob_speed + _anim_seed)
	sprite.position.y = wave * bob_amp
	sprite.scale = Vector2(_base_scale.x * (1.0 + squash_amp * wave), _base_scale.y * (1.0 - squash_amp * wave))

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

func _update_status_visuals(delta: float):
	_status_fx_timer = max(0.0, _status_fx_timer - delta)
	
	# Body tint feedback (no head icons)
	if sprite and flash_timer <= 0 and freeze_timer <= 0:
		var tint = Color.WHITE
		if burn_stacks > 0:
			tint = tint.lerp(Color(1.25, 0.78, 0.55, 1.0), 0.35)
		if poison_stacks > 0:
			tint = tint.lerp(Color(0.72, 1.18, 0.78, 1.0), 0.35)
		if burn_stacks > 0 or poison_stacks > 0:
			var pulse = 0.9 + 0.1 * sin(_anim_time * 11.0 + _anim_seed)
			sprite.modulate = Color(tint.r * pulse, tint.g * pulse, tint.b * pulse, 1.0)
	
	if _status_fx_timer <= 0.0 and (burn_stacks > 0 or poison_stacks > 0):
		if burn_stacks > 0:
			for i in range(min(2, 1 + int(burn_stacks / 4))):
				_spawn_status_particle("burn")
		if poison_stacks > 0:
			for i in range(min(2, 1 + int(poison_stacks / 4))):
				_spawn_status_particle("poison")
		_status_fx_timer = 0.12

func _spawn_status_particle(kind: String):
	var p = ColorRect.new()
	p.z_index = 6
	add_child(p)
	var tw = p.create_tween()
	
	if kind == "burn":
		p.size = Vector2(2.6, 3.4)
		p.position = Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
		p.color = Color(1.0, randf_range(0.35, 0.7), 0.12, 0.85)
		tw.tween_property(p, "position", p.position + Vector2(randf_range(-2.0, 2.0), randf_range(-9.0, -5.0)), 0.24)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.24)
	else:
		p.size = Vector2(3.0, 3.0)
		p.position = Vector2(randf_range(-6.0, 6.0), randf_range(-2.0, 6.0))
		p.color = Color(0.45, 1.0, 0.55, 0.78)
		tw.tween_property(p, "position", p.position + Vector2(randf_range(-3.0, 3.0), randf_range(-5.0, -2.0)), 0.28)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.28)
	
	tw.tween_callback(p.queue_free)

func take_damage(amount: int, knockback_dir: Vector2 = Vector2.ZERO):
	hp -= amount
	flash_timer = 0.2
	_hit_squash_timer = 0.16
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
