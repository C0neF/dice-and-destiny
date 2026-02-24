## Survivor-mode arena: top-down real-time combat with cards + dice
extends Node2D

signal wave_complete(wave_num: int)
signal run_over(victory: bool)

const ARENA_SIZE = Vector2(640, 360)
# Wall-interior bounds (matching survivor_arena_bg wall inner edges)
# Top is already aligned; expand left/right/bottom outward to match the painted walls.
const ARENA_MIN = Vector2(-10, 22)
const ARENA_MAX = Vector2(650, 358)
const SPAWN_MARGIN = 40.0
const WALL_THICKNESS = 40.0  # Collision wall thickness (placed outside playable area)

# Drop item script
const DropItemScript = preload("res://scripts/battle/drop_item.gd")

# Nodes
var player: CharacterBody2D
var camera: Camera2D
var enemy_container: Node2D
var projectile_container: Node2D
var drop_container: Node2D
var ui_layer: CanvasLayer
var hud: Control

# Player buffs from drops
var speed_boost_timer: float = 0.0
var damage_boost_timer: float = 0.0
var damage_boost_mult: float = 1.5
var magnet_active: bool = false
var magnet_timer: float = 0.0

# Unlockable attack types
var unlocked_attacks: Array[String] = ["auto_shot"]  # Start with basic
var attack_levels: Dictionary = {}  # attack_id -> level
# Passive attack timers
var _orbit_timer: float = 0.0
var _lightning_timer: float = 0.0
var _flame_tornado_timer: float = 0.0
var _ice_nova_timer: float = 0.0
var _poison_cloud_timer: float = 0.0
var _orbit_visual: Node2D

# Wave state
var current_wave: int = 0
var wave_timer: float = 0.0
var wave_duration: float = 45.0  # Seconds per wave
var enemies_alive: int = 0
var spawn_timer: float = 0.0
var spawn_interval: float = 1.5
var is_wave_active: bool = false
var is_shopping: bool = false

# Dice state
var dice_timer: float = 0.0
var dice_roll_interval: float = 8.0  # Roll dice every 8 seconds
var current_dice_bonus: int = 0

# Card cooldowns: card_id -> remaining cooldown
var card_cooldowns: Dictionary = {}
var card_slots: Array[String] = []  # Equipped card IDs (max 4)
var _card_key_held: Array = [false, false, false, false]

# UI refs
var wave_label: Label
var timer_label: Label
var hp_label: Label
var dice_label: Label
var card_panels: Array = []
var log_label: RichTextLabel

func _ready():
	_setup_arena()
	_setup_player()
	_setup_ui()
	_start_wave(1)
	VFX.fade_in(0.4)

func _setup_arena():
	# Background - use generated dungeon map
	var bg_tex = load("res://assets/sprites/bg/survivor_arena_bg.png")
	if bg_tex:
		var bg_sprite = Sprite2D.new()
		bg_sprite.texture = bg_tex
		bg_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg_sprite.centered = false
		var tex_size = bg_tex.get_size()
		bg_sprite.scale = Vector2(720.0 / tex_size.x, 440.0 / tex_size.y)
		bg_sprite.position = Vector2(-40, -40)
		bg_sprite.z_index = -10
		add_child(bg_sprite)
	else:
		var bg = ColorRect.new()
		bg.size = ARENA_SIZE * 3
		bg.position = -ARENA_SIZE
		bg.color = Color(0.18, 0.15, 0.22)
		bg.z_index = -10
		add_child(bg)
	
	# === Physical wall colliders ===
	_create_wall_colliders()
	
	# Place collision obstacles - corner crystals (inset from new arena bounds)
	var obstacles = [
		[10, 42, 16],     # Top-left crystal
		[630, 42, 16],    # Top-right crystal
		[10, 338, 16],    # Bottom-left crystal
		[630, 338, 16],   # Bottom-right crystal
	]
	
	var obstacle_container = Node2D.new()
	obstacle_container.name = "Obstacles"
	add_child(obstacle_container)
	
	for obs in obstacles:
		var body = StaticBody2D.new()
		body.position = Vector2(obs[0], obs[1])
		body.collision_layer = 4  # Obstacle layer
		body.collision_mask = 0
		
		var col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = obs[2]
		col.shape = shape
		body.add_child(col)
		
		obstacle_container.add_child(body)
	
	enemy_container = Node2D.new()
	enemy_container.name = "Enemies"
	add_child(enemy_container)
	
	projectile_container = Node2D.new()
	projectile_container.name = "Projectiles"
	add_child(projectile_container)
	
	drop_container = Node2D.new()
	drop_container.name = "Drops"
	add_child(drop_container)

## Build four wall StaticBody2Ds that border the playable area.
## Layer 4 (obstacle) so player (mask 2|4) and enemies (mask 4) both collide.
func _create_wall_colliders():
	var center_x = (ARENA_MIN.x + ARENA_MAX.x) / 2.0
	var center_y = (ARENA_MIN.y + ARENA_MAX.y) / 2.0
	var arena_w = ARENA_MAX.x - ARENA_MIN.x
	var arena_h = ARENA_MAX.y - ARENA_MIN.y
	# Make walls wider than the arena so corners are covered
	var extend = WALL_THICKNESS * 2
	
	var walls = [
		# [position, size] — placed so inner edge aligns with ARENA_MIN / ARENA_MAX
		[Vector2(center_x, ARENA_MIN.y - WALL_THICKNESS / 2.0), Vector2(arena_w + extend, WALL_THICKNESS)],  # Top
		[Vector2(center_x, ARENA_MAX.y + WALL_THICKNESS / 2.0), Vector2(arena_w + extend, WALL_THICKNESS)],  # Bottom
		[Vector2(ARENA_MIN.x - WALL_THICKNESS / 2.0, center_y), Vector2(WALL_THICKNESS, arena_h + extend)],  # Left
		[Vector2(ARENA_MAX.x + WALL_THICKNESS / 2.0, center_y), Vector2(WALL_THICKNESS, arena_h + extend)],  # Right
	]
	
	for w in walls:
		var body = StaticBody2D.new()
		body.position = w[0]
		body.collision_layer = 4  # Obstacle layer
		body.collision_mask = 0   # Static — doesn't need to detect anything
		
		var col = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = w[1]
		col.shape = shape
		body.add_child(col)
		
		add_child(body)

func _setup_player():
	player = CharacterBody2D.new()
	var script = load("res://scripts/battle/player_controller.gd")
	player.set_script(script)
	player.position = Vector2(320, 180)  # Center of playable area
	add_child(player)
	# Pass arena bounds so the player clamp uses shared constants
	player.arena_min = ARENA_MIN
	player.arena_max = ARENA_MAX
	
	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	camera.make_current()
	
	# Orbit blade visuals (updated each frame)
	_orbit_visual = Node2D.new()
	_orbit_visual.name = "OrbitBlades"
	_orbit_visual.z_index = 5
	add_child(_orbit_visual)
	
	# Init cards - equip first 4 from deck
	card_slots.clear()
	var count = 0
	for card_id in GameState.deck:
		if count >= 4:
			break
		if not card_slots.has(card_id):
			card_slots.append(card_id)
			count += 1
	# Ensure at least strike
	if card_slots.is_empty():
		card_slots.append("strike")

func _setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(hud)
	
	# Top-left info block
	var top_left = VBoxContainer.new()
	top_left.position = Vector2(16, 8)
	top_left.add_theme_constant_override("separation", 2)
	hud.add_child(top_left)
	
	wave_label = Label.new()
	wave_label.add_theme_font_size_override("font_size", 20)
	wave_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	top_left.add_child(wave_label)
	
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 16)
	hp_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	top_left.add_child(hp_label)
	
	dice_label = Label.new()
	dice_label.add_theme_font_size_override("font_size", 14)
	dice_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	top_left.add_child(dice_label)
	
	# Top-center timer
	timer_label = Label.new()
	timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_label.position = Vector2(-30, 8)
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(timer_label)
	
	# Bottom-center card slots
	var card_bar = HBoxContainer.new()
	card_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	card_bar.position = Vector2(-240, -70)
	card_bar.add_theme_constant_override("separation", 12)
	hud.add_child(card_bar)
	
	for i in range(4):
		var panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(110, 50)
		card_bar.add_child(panel)
		
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 1)
		panel.add_child(vbox)
		
		var header = HBoxContainer.new()
		vbox.add_child(header)
		
		var lbl = Label.new()
		lbl.name = "CardLabel"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(lbl)
		
		var key_lbl = Label.new()
		key_lbl.text = "[%d]" % (i + 1)
		key_lbl.add_theme_font_size_override("font_size", 11)
		key_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
		header.add_child(key_lbl)
		
		var cd_lbl = Label.new()
		cd_lbl.name = "CooldownLabel"
		cd_lbl.add_theme_font_size_override("font_size", 12)
		cd_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
		vbox.add_child(cd_lbl)
		
		card_panels.append(panel)
	
	# Bottom-right log
	log_label = RichTextLabel.new()
	log_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	log_label.position = Vector2(-280, -160)
	log_label.size = Vector2(260, 140)
	log_label.add_theme_font_size_override("normal_font_size", 12)
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(log_label)

func _card_name(card_id: String, card_def = null) -> String:
	var key = "card_" + card_id
	if Loc.has_key(key):
		return Loc.t(key)
	if card_def and card_def.name != "":
		return card_def.name
	return card_id

func _process(delta):
	if is_shopping:
		return
	
	if is_wave_active:
		_update_wave(delta)
		_update_dice(delta)
		_update_auto_attack(delta)
		_update_passive_attacks(delta)
		_update_buffs(delta)
		_handle_card_input()
		_update_card_cooldowns(delta)
		_check_contact_damage()
		# Magnet pulls new drops
		if magnet_active:
			_activate_all_magnets()
	
	_update_hud()

# === WAVE MANAGEMENT ===

func _start_wave(wave_num: int):
	current_wave = wave_num
	wave_timer = wave_duration + min(wave_num * 5, 30)  # Longer waves as you progress
	spawn_interval = max(0.3, 1.5 - wave_num * 0.1)
	spawn_timer = 0
	is_wave_active = true
	is_shopping = false
	
	# Roll initial dice
	GameState.roll_all_dice()
	current_dice_bonus = _calc_dice_bonus()
	
	add_log("[color=yellow]Wave %d![/color]" % wave_num)

func _update_wave(delta):
	wave_timer -= delta
	spawn_timer -= delta
	
	if spawn_timer <= 0:
		_spawn_enemy()
		spawn_timer = spawn_interval
	
	if wave_timer <= 0:
		is_wave_active = false
		# Kill remaining enemies
		for e in enemy_container.get_children():
			if e.has_method("take_damage"):
				e.take_damage(9999)
		_on_wave_end()

func _spawn_enemy():
	var enemy_pool = _get_enemy_pool()
	var enemy_id = enemy_pool[randi() % enemy_pool.size()]
	var def = GameData.ENEMIES.get(enemy_id)
	if not def:
		return
	
	var enemy_scene = CharacterBody2D.new()
	var script = load("res://scripts/battle/enemy_unit.gd")
	enemy_scene.set_script(script)
	
	# Spawn at wall edges (just inside the playable boundary)
	var side = randi() % 4
	var spawn_pos: Vector2
	var margin_in = 12.0  # pixels inside from wall edge
	match side:
		0: spawn_pos = Vector2(randf_range(ARENA_MIN.x + margin_in, ARENA_MAX.x - margin_in), ARENA_MIN.y + margin_in)
		1: spawn_pos = Vector2(randf_range(ARENA_MIN.x + margin_in, ARENA_MAX.x - margin_in), ARENA_MAX.y - margin_in)
		2: spawn_pos = Vector2(ARENA_MIN.x + margin_in, randf_range(ARENA_MIN.y + margin_in, ARENA_MAX.y - margin_in))
		3: spawn_pos = Vector2(ARENA_MAX.x - margin_in, randf_range(ARENA_MIN.y + margin_in, ARENA_MAX.y - margin_in))
	
	enemy_scene.position = spawn_pos
	enemy_container.add_child(enemy_scene)
	enemy_scene.add_to_group("enemies")
	
	var level_scale = 1.0 + current_wave * 0.15
	enemy_scene.setup(def, player, level_scale)
	enemy_scene.arena_min = ARENA_MIN
	enemy_scene.arena_max = ARENA_MAX
	enemy_scene.died.connect(_on_enemy_died)
	enemies_alive += 1
	
	# Boss wave every 5 waves: also spawn boss
	if current_wave % 5 == 0 and wave_timer > wave_duration * 0.8:
		if randi() % 10 == 0:
			var boss_def = GameData.ENEMIES.get("demon")
			if boss_def:
				var boss = CharacterBody2D.new()
				boss.set_script(script)
				boss.position = spawn_pos + Vector2(30, 0)
				enemy_container.add_child(boss)
				boss.add_to_group("enemies")
				boss.setup(boss_def, player, level_scale * 0.7)
				boss.arena_min = ARENA_MIN
				boss.arena_max = ARENA_MAX
				boss.died.connect(_on_enemy_died)

func _get_enemy_pool() -> Array:
	var pool = ["slime", "bat"]
	if current_wave >= 3: pool.append_array(["skeleton", "goblin"])
	if current_wave >= 5: pool.append("ghost")
	if current_wave >= 7: pool.append_array(["slime", "skeleton", "goblin"])  # More variety
	return pool

func _on_enemy_died(_enemy, _pos: Vector2):
	enemies_alive -= 1
	# Spawn drops
	_spawn_drops(_pos)
	if GameState.relics.has("blood_vial"):
		GameState.heal(1)

# === DROP SYSTEM ===

func _spawn_drops(pos: Vector2):
	# Always drop some gold
	_create_drop(0, randi_range(1, 3), pos)  # DropType.GOLD = 0
	
	# Random additional drops
	var roll = randf()
	if roll < 0.12:
		_create_drop(1, 10 + current_wave * 2, pos)  # Health potion
	elif roll < 0.18:
		_create_drop(4, 1, pos)  # Energy orb
	elif roll < 0.23:
		_create_drop(2, 5, pos)  # Speed boost (5s)
	elif roll < 0.28:
		_create_drop(3, 5, pos)  # Damage boost (5s)
	elif roll < 0.31:
		_create_drop(5, 8, pos)  # Magnet (8s)
	elif roll < 0.33:
		_create_drop(6, 0, pos)  # Bomb
	
	# Boss drops guaranteed extra
	if current_wave % 5 == 0:
		_create_drop(1, 20, pos)
		_create_drop(3, 8, pos)

func _create_drop(type: int, val: int, pos: Vector2):
	# Clamp spawn position to arena interior
	pos.x = clampf(pos.x, ARENA_MIN.x + 8, ARENA_MAX.x - 8)
	pos.y = clampf(pos.y, ARENA_MIN.y + 8, ARENA_MAX.y - 8)
	var drop = Area2D.new()
	drop.set_script(DropItemScript)
	drop_container.add_child(drop)
	drop.arena_min = ARENA_MIN
	drop.arena_max = ARENA_MAX
	drop.setup(type, val, player, pos)
	drop.collected.connect(_on_drop_collected)

func _on_drop_collected(drop_type: int, value: int):
	match drop_type:
		0:  # GOLD
			GameState.add_gold(value)
			add_log("[color=yellow]+%dG[/color]" % value)
		1:  # HEALTH_POTION
			GameState.heal(value)
			add_log("[color=green]+%d HP[/color]" % value)
			VFX.flash_screen(Color(0.1, 0.9, 0.2, 0.15), 0.15)
		2:  # SPEED_BOOST
			speed_boost_timer = float(value)
			player.move_speed = 180.0
			add_log("[color=cyan]⚡ Speed Boost![/color]")
		3:  # DAMAGE_BOOST
			damage_boost_timer = float(value)
			add_log("[color=orange]🔥 Damage Boost![/color]")
		4:  # ENERGY_ORB
			GameState.player_energy = min(GameState.player_max_energy, GameState.player_energy + value)
			add_log("[color=blue]+%d Energy[/color]" % value)
		5:  # MAGNET
			magnet_active = true
			magnet_timer = float(value)
			_activate_all_magnets()
			add_log("[color=white]🧲 Magnet![/color]")
		6:  # BOMB
			_detonate_bomb(player.global_position)
			add_log("[color=red]💥 BOMB![/color]")

func _activate_all_magnets():
	for drop in drop_container.get_children():
		if drop.has_method("activate_magnet"):
			drop.activate_magnet()

func _detonate_bomb(center: Vector2):
	# Damage all enemies in large radius
	var bomb_damage = 15 + current_wave * 3
	if damage_boost_timer > 0:
		bomb_damage = int(bomb_damage * damage_boost_mult)
	for e in enemy_container.get_children():
		if e.has_method("take_damage"):
			var dist = e.global_position.distance_to(center)
			if dist < 150:
				var kb = (e.global_position - center).normalized()
				e.take_damage(bomb_damage, kb)
	VFX.flash_screen(Color(1, 0.5, 0.0, 0.4), 0.25)
	VFX.screen_shake(6.0, 4.0)
	# Visual explosion ring
	_spawn_explosion_ring(center, 150.0, Color(1, 0.4, 0.0))

func _spawn_explosion_ring(center: Vector2, radius: float, color: Color):
	var ring = Node2D.new()
	ring.position = center
	ring.z_index = 15
	add_child(ring)
	# Draw expanding ring with particles
	for i in range(16):
		var angle = (i / 16.0) * TAU
		var p = ColorRect.new()
		p.size = Vector2(4, 4)
		p.position = Vector2(-2, -2)
		p.color = color
		ring.add_child(p)
		var tween = p.create_tween()
		var dest = Vector2(cos(angle), sin(angle)) * radius
		tween.tween_property(p, "position", dest, 0.35).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(p, "modulate:a", 0.0, 0.4)
	# Cleanup
	var ct = get_tree().create_timer(0.5)
	ct.timeout.connect(ring.queue_free)

func _on_wave_end():
	add_log("[color=green]Wave %d complete![/color]" % current_wave)
	wave_complete.emit(current_wave)
	
	# Heal between waves
	GameState.heal(GameState.player_max_hp / 5)
	
	# Enter shop phase
	await get_tree().create_timer(1.0).timeout
	_open_shop()

# === DICE SYSTEM ===

func _update_dice(delta):
	dice_timer += delta
	if dice_timer >= dice_roll_interval:
		dice_timer = 0
		GameState.roll_all_dice()
		current_dice_bonus = _calc_dice_bonus()
		add_log("[color=cyan]🎲 Dice rolled! Bonus: +%d[/color]" % current_dice_bonus)

func _calc_dice_bonus() -> int:
	var total = 0
	for d in GameState.active_dice:
		total += d.value
	return total

# === AUTO ATTACK ===

var auto_attack_timer: float = 0.0
var auto_attack_interval: float = 0.8

func _update_auto_attack(delta):
	auto_attack_timer -= delta
	if auto_attack_timer > 0:
		return
	auto_attack_timer = auto_attack_interval
	
	# Find nearest enemy
	var nearest = _find_nearest_enemy()
	if not nearest:
		return
	
	# Fire basic projectile toward nearest enemy
	var dir = (nearest.global_position - player.global_position).normalized()
	var base_dmg = 3 + current_dice_bonus / 4
	var proj = _create_projectile(player.global_position, dir, int(base_dmg * _get_damage_multiplier()), 180.0)
	proj.setup_visual(Color(1, 0.9, 0.4), 3)

func _find_nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist = 300.0  # Max range
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = e
	return best

func _find_enemies_in_range(center: Vector2, radius: float) -> Array:
	var result = []
	for e in enemy_container.get_children():
		if e.has_method("take_damage"):
			if e.global_position.distance_to(center) < radius:
				result.append(e)
	return result

# === BUFF MANAGEMENT ===

func _update_buffs(delta):
	if speed_boost_timer > 0:
		speed_boost_timer -= delta
		if speed_boost_timer <= 0:
			player.move_speed = 120.0  # Reset
	if damage_boost_timer > 0:
		damage_boost_timer -= delta
	if magnet_timer > 0:
		magnet_timer -= delta
		if magnet_timer <= 0:
			magnet_active = false

func _get_damage_multiplier() -> float:
	return damage_boost_mult if damage_boost_timer > 0 else 1.0

# === PASSIVE ATTACKS (unlockable) ===

func _update_passive_attacks(delta):
	var lvl: int
	
	# Orbiting blades
	if unlocked_attacks.has("orbit_blades"):
		lvl = attack_levels.get("orbit_blades", 1)
		_orbit_timer += delta
		_update_orbit_blades(lvl)
	
	# Chain lightning (periodic)
	if unlocked_attacks.has("chain_lightning_passive"):
		lvl = attack_levels.get("chain_lightning_passive", 1)
		_lightning_timer += delta
		var interval = max(2.0, 4.0 - lvl * 0.5)
		if _lightning_timer >= interval:
			_lightning_timer = 0.0
			_fire_chain_lightning(lvl)
	
	# Flame tornado (periodic)
	if unlocked_attacks.has("flame_tornado"):
		lvl = attack_levels.get("flame_tornado", 1)
		_flame_tornado_timer += delta
		var interval = max(3.0, 6.0 - lvl * 0.7)
		if _flame_tornado_timer >= interval:
			_flame_tornado_timer = 0.0
			_spawn_flame_tornado(lvl)
	
	# Ice nova (periodic AoE)
	if unlocked_attacks.has("ice_nova"):
		lvl = attack_levels.get("ice_nova", 1)
		_ice_nova_timer += delta
		var interval = max(3.5, 7.0 - lvl * 0.8)
		if _ice_nova_timer >= interval:
			_ice_nova_timer = 0.0
			_fire_ice_nova(lvl)
	
	# Poison cloud (aura)
	if unlocked_attacks.has("poison_cloud"):
		lvl = attack_levels.get("poison_cloud", 1)
		_poison_cloud_timer += delta
		if _poison_cloud_timer >= 1.5:
			_poison_cloud_timer = 0.0
			_apply_poison_cloud(lvl)

## Orbiting blades that damage enemies on contact
func _update_orbit_blades(lvl: int):
	var blade_count = 2 + lvl
	var orbit_radius = 30.0 + lvl * 5.0
	var dmg = int((3 + lvl * 2) * _get_damage_multiplier())
	var rot_speed = 3.0
	
	# Update visual
	if _orbit_visual:
		_orbit_visual.position = player.global_position
		# Ensure correct number of blade sprites
		while _orbit_visual.get_child_count() < blade_count:
			var b = ColorRect.new()
			b.size = Vector2(6, 3)
			b.position = Vector2(-3, -1.5)
			b.color = Color(0.9, 0.9, 1.0, 0.9)
			_orbit_visual.add_child(b)
		while _orbit_visual.get_child_count() > blade_count:
			_orbit_visual.get_child(_orbit_visual.get_child_count() - 1).queue_free()
		for i in range(blade_count):
			var angle = _orbit_timer * rot_speed + (i * TAU / blade_count)
			var child = _orbit_visual.get_child(i)
			child.position = Vector2(cos(angle), sin(angle)) * orbit_radius - Vector2(3, 1.5)
	
	# Check enemies in orbit range
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist < orbit_radius + 10:
			for i in range(blade_count):
				var angle = _orbit_timer * rot_speed + (i * TAU / blade_count)
				var blade_pos = player.global_position + Vector2(cos(angle), sin(angle)) * orbit_radius
				if blade_pos.distance_to(e.global_position) < 12:
					var kb = (e.global_position - player.global_position).normalized()
					e.take_damage(dmg, kb)
					break

## Chain lightning that bounces between enemies
func _fire_chain_lightning(lvl: int):
	var targets = _find_enemies_in_range(player.global_position, 150.0 + lvl * 20)
	if targets.is_empty():
		return
	
	var dmg = int((5 + lvl * 3) * _get_damage_multiplier())
	var bounces = 3 + lvl
	var hit: Array = []
	var current = targets[randi() % targets.size()]
	
	for i in range(bounces):
		if not is_instance_valid(current):
			break
		if not hit.has(current):
			current.take_damage(dmg, Vector2.ZERO)
			hit.append(current)
			# Visual: lightning line
			_spawn_lightning_line(
				current.global_position if i == 0 else hit[i-1].global_position if i-1 < hit.size() else player.global_position,
				current.global_position
			)
		# Find next closest unhit
		var next: Node2D = null
		var best_dist = 100.0
		for e in enemy_container.get_children():
			if e.has_method("take_damage") and not hit.has(e):
				var d = e.global_position.distance_to(current.global_position)
				if d < best_dist:
					best_dist = d
					next = e
		if next == null:
			break
		current = next
	
	VFX.flash_screen(Color(0.4, 0.6, 1.0, 0.15), 0.08)
	add_log("[color=cyan]⚡ Chain Lightning x%d[/color]" % hit.size())

func _spawn_lightning_line(from: Vector2, to: Vector2):
	var line = Line2D.new()
	line.width = 2.0
	line.default_color = Color(0.5, 0.7, 1.0, 0.9)
	line.z_index = 15
	# Jagged lightning
	var dir = to - from
	var length = dir.length()
	var segments = max(3, int(length / 10))
	var perp = dir.normalized().rotated(PI / 2)
	line.add_point(from)
	for i in range(1, segments):
		var t = float(i) / segments
		var jitter = perp * randf_range(-4, 4)
		line.add_point(from + dir * t + jitter)
	line.add_point(to)
	add_child(line)
	# Fade out
	var tween = line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.25)
	tween.tween_callback(line.queue_free)

## Flame tornado that circles outward from player
func _spawn_flame_tornado(lvl: int):
	var dmg = int((8 + lvl * 4) * _get_damage_multiplier())
	var radius = 60.0 + lvl * 15
	var tornado = Node2D.new()
	tornado.position = player.global_position
	tornado.z_index = 12
	add_child(tornado)
	
	# Fire particles in expanding spiral
	var duration = 1.5
	var hit_enemies: Array = []
	
	# Animate via process
	var elapsed = 0.0
	var _step_func: Callable
	_step_func = func(delta_inner: float):
		elapsed += delta_inner
		if elapsed >= duration or not is_instance_valid(tornado):
			if is_instance_valid(tornado):
				tornado.queue_free()
			return
		
		var progress = elapsed / duration
		var angle = progress * TAU * 3  # 3 full rotations
		var r = progress * radius
		var fire_pos = tornado.position + Vector2(cos(angle), sin(angle)) * r
		
		# Spawn fire particle
		var p = ColorRect.new()
		p.size = Vector2(5, 5)
		p.position = fire_pos - Vector2(2.5, 2.5)
		p.color = Color(1, randf_range(0.2, 0.6), 0.0, 0.9)
		p.z_index = 12
		add_child(p)
		var tw = p.create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.4)
		tw.tween_callback(p.queue_free)
		
		# Damage enemies near fire
		for e in enemy_container.get_children():
			if e.has_method("take_damage") and not hit_enemies.has(e):
				if e.global_position.distance_to(fire_pos) < 15:
					e.take_damage(dmg, (e.global_position - fire_pos).normalized())
					e.burn_stacks += 2
					hit_enemies.append(e)
	
	# Use a timer loop to drive the animation
	var timer_node = Timer.new()
	timer_node.wait_time = 0.05
	timer_node.autostart = true
	tornado.add_child(timer_node)
	timer_node.timeout.connect(func(): _step_func.call(0.05))
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(tornado):
			tornado.queue_free()
	)
	
	VFX.flash_screen(Color(1, 0.3, 0.0, 0.12), 0.1)
	add_log("[color=orange]🌪️ Flame Tornado![/color]")

## Ice nova - freezes and damages nearby enemies
func _fire_ice_nova(lvl: int):
	var radius = 80.0 + lvl * 15
	var dmg = int((6 + lvl * 3) * _get_damage_multiplier())
	var freeze_time = 1.0 + lvl * 0.5
	var enemies = _find_enemies_in_range(player.global_position, radius)
	
	if enemies.is_empty():
		return
	
	for e in enemies:
		e.take_damage(dmg, (e.global_position - player.global_position).normalized())
		e.freeze_timer = max(e.freeze_timer, freeze_time)
	
	# Visual: expanding ring
	_spawn_explosion_ring(player.global_position, radius, Color(0.3, 0.6, 1.0))
	VFX.flash_screen(Color(0.3, 0.5, 1.0, 0.2), 0.12)
	add_log("[color=aqua]❄️ Ice Nova! Froze %d[/color]" % enemies.size())

## Poison cloud - damages and poisons enemies near player
func _apply_poison_cloud(lvl: int):
	var radius = 40.0 + lvl * 10
	var dmg = int((1 + lvl) * _get_damage_multiplier())
	for e in enemy_container.get_children():
		if e.has_method("take_damage"):
			if e.global_position.distance_to(player.global_position) < radius:
				e.take_damage(dmg, Vector2.ZERO)
				e.poison_stacks = max(e.poison_stacks, lvl)

func _create_projectile(from: Vector2, dir: Vector2, dmg: int, spd: float = 200.0) -> Node2D:
	var proj = Area2D.new()
	var script = load("res://scripts/battle/projectile.gd")
	proj.set_script(script)
	proj.position = from + dir * 10
	proj.direction = dir
	proj.speed = spd
	proj.damage = dmg
	proj.arena_min = ARENA_MIN
	proj.arena_max = ARENA_MAX
	projectile_container.add_child(proj)
	return proj

# === CARD ABILITIES ===

func _handle_card_input():
	for i in range(min(4, card_slots.size())):
		if Input.is_action_just_pressed("ui_" + ["left", "right", "up", "down"][i] if i < 4 else ""):
			pass  # Using number keys instead
	
	# Number keys 1-4
	if Input.is_key_pressed(KEY_1) and not _card_key_held[0]: _use_card(0); _card_key_held[0] = true
	if Input.is_key_pressed(KEY_2) and not _card_key_held[1]: _use_card(1); _card_key_held[1] = true
	if Input.is_key_pressed(KEY_3) and not _card_key_held[2]: _use_card(2); _card_key_held[2] = true
	if Input.is_key_pressed(KEY_4) and not _card_key_held[3]: _use_card(3); _card_key_held[3] = true
	if not Input.is_key_pressed(KEY_1): _card_key_held[0] = false
	if not Input.is_key_pressed(KEY_2): _card_key_held[1] = false
	if not Input.is_key_pressed(KEY_3): _card_key_held[2] = false
	if not Input.is_key_pressed(KEY_4): _card_key_held[3] = false

func _use_card(slot: int):
	if slot >= card_slots.size():
		return
	var card_id = card_slots[slot]
	
	# Check cooldown
	if card_cooldowns.get(card_id, 0.0) > 0:
		return
	
	# Check energy
	var card_def = GameData.CARDS.get(card_id)
	if not card_def:
		return
	if not GameState.spend_energy(card_def.energy_cost):
		return
	
	# Set cooldown (based on energy cost)
	card_cooldowns[card_id] = 2.0 + card_def.energy_cost * 1.5
	
	# Calculate value
	var value = card_def.base_value + int(current_dice_bonus * card_def.dice_multiplier * 0.5)
	
	# Card upgrade bonus
	var upgrades = GameState.get_card_upgrade_level(card_id)
	value += upgrades * 2
	
	# Combo bonus
	GameState.combo_count += 1
	var combo_bonus = GameState.combo_count - 1
	if GameState.relics.has("war_drum"):
		combo_bonus *= 2
	value += combo_bonus
	
	# Execute card effect
	_execute_card(card_id, card_def, value)
	
	add_log("%s → %d" % [_card_name(card_id, card_def), value])

func _execute_card(card_id: String, card_def, value: int):
	var nearest = _find_nearest_enemy()
	
	match card_def.type:
		GameData.CardType.ATTACK:
			if nearest:
				var attack_value = GameState.apply_damage_with_relics(value)
				var dir = (nearest.global_position - player.global_position).normalized()
				match card_id:
					"flurry":
						for i in range(3):
							var spread = dir.rotated(deg_to_rad(-10 + i * 10))
							var p = _create_projectile(player.global_position, spread, attack_value / 3, 220)
							p.setup_visual(Color(1, 0.7, 0.3), 3)
					"vampiric_strike":
						var p = _create_projectile(player.global_position, dir, attack_value, 200)
						p.setup_visual(Color(0.8, 0.1, 0.2), 5)
						GameState.heal(attack_value / 3)
					"poison_strike":
						var p = _create_projectile(player.global_position, dir, attack_value, 180)
						p.status_effect = "poison"
						p.status_stacks = 3
						p.setup_visual(Color(0.3, 0.9, 0.3), 4)
					_:
						var p = _create_projectile(player.global_position, dir, attack_value, 200)
						p.setup_visual(Color(1, 1, 0.5), 4)
		
		GameData.CardType.DEFEND:
			GameState.add_armor(value)
			VFX.flash_screen(Color(0.3, 0.5, 1, 0.15), 0.1)
		
		GameData.CardType.MAGIC:
			match card_id:
				"fireball", "inferno":
					var aoe_damage = GameState.apply_damage_with_relics(value)
					# AoE around player
					for e in enemy_container.get_children():
						if e.has_method("take_damage"):
							var dist = e.global_position.distance_to(player.global_position)
							if dist < 120:
								var kb = (e.global_position - player.global_position).normalized()
								e.take_damage(aoe_damage, kb)
								if card_id == "inferno":
									e.burn_stacks += 3
					VFX.flash_screen(Color(1, 0.3, 0.1, 0.2), 0.15)
				"ice_shard":
					if nearest:
						var ice_damage = GameState.apply_damage_with_relics(value)
						var dir = (nearest.global_position - player.global_position).normalized()
						var p = _create_projectile(player.global_position, dir, ice_damage, 160)
						p.status_effect = "freeze"
						p.status_stacks = 2
						p.setup_visual(Color(0.4, 0.7, 1.0), 5)
				"chain_lightning":
					var bonus = GameState.combo_count * 3
					var chain_damage = GameState.apply_damage_with_relics(value + bonus)
					var hit_count = 0
					for e in enemy_container.get_children():
						if e.has_method("take_damage") and hit_count < 5:
							var dist = e.global_position.distance_to(player.global_position)
							if dist < 150:
								e.take_damage(chain_damage, Vector2.ZERO)
								hit_count += 1
					VFX.flash_screen(Color(0.5, 0.7, 1, 0.2), 0.1)
				"weaken":
					for e in enemy_container.get_children():
						if e.has_method("take_damage"):
							var dist = e.global_position.distance_to(player.global_position)
							if dist < 100:
								e.slow_factor = 0.5
				_:
					if nearest:
						var magic_damage = GameState.apply_damage_with_relics(value)
						var dir = (nearest.global_position - player.global_position).normalized()
						_create_projectile(player.global_position, dir, magic_damage, 180)
		
		GameData.CardType.HEAL:
			GameState.heal(value)
			VFX.flash_screen(Color(0.2, 1, 0.3, 0.15), 0.1)
		
		GameData.CardType.DICE_BOOST:
			GameState.roll_all_dice()
			current_dice_bonus = _calc_dice_bonus()
			add_log("[color=cyan]🎲 Rerolled! +%d[/color]" % current_dice_bonus)

func _update_card_cooldowns(delta):
	for card_id in card_cooldowns:
		card_cooldowns[card_id] = max(0, card_cooldowns[card_id] - delta)
	# Energy regen
	if GameState.player_energy < GameState.player_max_energy:
		GameState.energy_regen_acc += delta
		if GameState.energy_regen_acc >= 3.0:
			GameState.energy_regen_acc -= 3.0
			GameState.player_energy = min(GameState.player_max_energy, GameState.player_energy + 1)

# === CONTACT DAMAGE ===

func _check_contact_damage():
	for e in enemy_container.get_children():
		if not e.has_method("get_contact_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist < 18:  # Contact range (player radius 6 + enemy radius 5 + margin)
			var dmg = e.get_contact_damage()
			if dmg > 0:
				var actual = GameState.take_damage_with_relics(dmg)
				if actual > 0:
					VFX.flash_screen(Color(1, 0.1, 0.05, 0.3), 0.1)
					VFX.screen_shake(3.0, 6.0)
					player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
				
				if GameState.is_dead():
					_on_player_died()
					return

func _on_player_died():
	is_wave_active = false
	add_log("[color=red]You fell...[/color]")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main/game_over.tscn")

# === SHOP (between waves) ===

func _open_shop():
	is_shopping = true
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.name = "ShopOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(overlay)
	
	# Shop panel - centered
	var shop_panel = PanelContainer.new()
	shop_panel.name = "ShopPanel"
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.custom_minimum_size = Vector2(500, 360)
	shop_panel.position = Vector2(-250, -180)
	overlay.add_child(shop_panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	shop_panel.add_child(margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)
	
	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)
	
	var title = Label.new()
	title.text = Loc.t("shop") + " - Wave %d" % current_wave
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	
	var gold_lbl = Label.new()
	gold_lbl.text = "Gold: %d" % GameState.player_gold
	gold_lbl.add_theme_font_size_override("font_size", 18)
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	header.add_child(gold_lbl)
	
	# Two columns
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	main_vbox.add_child(columns)
	
	# Left: card offers
	var left_col = VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 6)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left_col)
	
	var cards_title = Label.new()
	cards_title.text = Loc.t("survivor_mode") if Loc.current_lang == "zh" else "Buy Cards"
	cards_title.text = "购买卡牌" if Loc.current_lang == "zh" else "Buy Cards"
	cards_title.add_theme_font_size_override("font_size", 16)
	cards_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	left_col.add_child(cards_title)
	
	var all_cards = GameData.CARDS.keys()
	var offered: Array[String] = []
	for i in range(3):
		offered.append(all_cards[randi() % all_cards.size()])
	
	for i in range(3):
		var card_def = GameData.CARDS.get(offered[i])
		if not card_def: continue
		var card_id = offered[i]
		var cost = 10 + card_def.energy_cost * 5
		var btn = Button.new()
		btn.text = "%s (%d⚡) - %dG" % [_card_name(card_id, card_def), card_def.energy_cost, cost]
		btn.custom_minimum_size = Vector2(220, 36)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func():
			if GameState.player_gold >= cost:
				GameState.player_gold -= cost
				GameState.add_card_to_deck(card_id)
				gold_lbl.text = "Gold: %d" % GameState.player_gold
				btn.disabled = true
				btn.text += " ✓"
		)
		left_col.add_child(btn)
	
	# Right: actions
	var right_col = VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 6)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right_col)
	
	var actions_title = Label.new()
	actions_title.text = "操作" if Loc.current_lang == "zh" else "Actions"
	actions_title.add_theme_font_size_override("font_size", 16)
	actions_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	right_col.add_child(actions_title)
	
	var upgrade_btn = Button.new()
	upgrade_btn.text = ("升级卡牌 (15G)" if Loc.current_lang == "zh" else "Upgrade Card (15G)")
	upgrade_btn.custom_minimum_size = Vector2(200, 36)
	upgrade_btn.add_theme_font_size_override("font_size", 14)
	upgrade_btn.pressed.connect(func():
		if GameState.player_gold >= 15 and card_slots.size() > 0:
			GameState.player_gold -= 15
			var to_upgrade = card_slots[randi() % card_slots.size()]
			GameState.upgrade_card(to_upgrade)
			gold_lbl.text = "Gold: %d" % GameState.player_gold
			upgrade_btn.text += " ✓"
	)
	right_col.add_child(upgrade_btn)
	
	var heal_btn = Button.new()
	heal_btn.text = ("恢复30%生命 (10G)" if Loc.current_lang == "zh" else "Heal 30% HP (10G)")
	heal_btn.custom_minimum_size = Vector2(200, 36)
	heal_btn.add_theme_font_size_override("font_size", 14)
	heal_btn.pressed.connect(func():
		if GameState.player_gold >= 10:
			GameState.player_gold -= 10
			GameState.heal(GameState.player_max_hp * 3 / 10)
			gold_lbl.text = "Gold: %d" % GameState.player_gold
	)
	right_col.add_child(heal_btn)
	
	# Attack upgrades section
	var atk_title = Label.new()
	atk_title.text = "攻击能力" if Loc.current_lang == "zh" else "Attacks"
	atk_title.add_theme_font_size_override("font_size", 16)
	atk_title.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
	right_col.add_child(atk_title)
	
	# Offer 2 random attack upgrades
	var all_attacks = [
		["orbit_blades", "旋转刀刃" if Loc.current_lang == "zh" else "Orbit Blades", 20],
		["chain_lightning_passive", "连锁闪电" if Loc.current_lang == "zh" else "Chain Lightning", 25],
		["flame_tornado", "火焰旋风" if Loc.current_lang == "zh" else "Flame Tornado", 30],
		["ice_nova", "冰霜新星" if Loc.current_lang == "zh" else "Ice Nova", 25],
		["poison_cloud", "毒雾" if Loc.current_lang == "zh" else "Poison Cloud", 20],
	]
	all_attacks.shuffle()
	
	for i in range(min(2, all_attacks.size())):
		var atk = all_attacks[i]
		var atk_id: String = atk[0]
		var atk_name: String = atk[1]
		var atk_cost: int = atk[2]
		var current_lvl = attack_levels.get(atk_id, 0)
		var is_new = not unlocked_attacks.has(atk_id)
		var label_text: String
		if is_new:
			label_text = "%s (%dG)" % [atk_name, atk_cost]
		else:
			label_text = "%s Lv%d→%d (%dG)" % [atk_name, current_lvl, current_lvl + 1, atk_cost]
		
		var atk_btn = Button.new()
		atk_btn.text = label_text
		atk_btn.custom_minimum_size = Vector2(200, 36)
		atk_btn.add_theme_font_size_override("font_size", 13)
		atk_btn.pressed.connect(func():
			if GameState.player_gold >= atk_cost:
				GameState.player_gold -= atk_cost
				if not unlocked_attacks.has(atk_id):
					unlocked_attacks.append(atk_id)
					attack_levels[atk_id] = 1
				else:
					attack_levels[atk_id] = attack_levels.get(atk_id, 1) + 1
				gold_lbl.text = "Gold: %d" % GameState.player_gold
				atk_btn.disabled = true
				atk_btn.text += " ✓"
		)
		right_col.add_child(atk_btn)
	
	# Continue button at bottom
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(spacer)
	
	var continue_btn = Button.new()
	continue_btn.text = (">> 下一波 >>" if Loc.current_lang == "zh" else ">> Next Wave >>")
	continue_btn.custom_minimum_size = Vector2(200, 44)
	continue_btn.add_theme_font_size_override("font_size", 18)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_btn.pressed.connect(func():
		overlay.queue_free()
		GameState.combo_count = 0
		GameState.player_energy = GameState.player_max_energy
		_start_wave(current_wave + 1)
	)
	main_vbox.add_child(continue_btn)

# === HUD UPDATE ===

func _update_hud():
	if wave_label:
		wave_label.text = Loc.tf("wave", [current_wave]) if Loc.has_key("wave") else "Wave %d" % current_wave
	if timer_label:
		var secs = max(0, int(wave_timer))
		timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	if hp_label:
		var hp_text = "HP: %d/%d" % [GameState.player_hp, GameState.player_max_hp]
		var armor_text = ("护甲" if Loc.current_lang == "zh" else "Armor") + ": %d" % GameState.player_armor
		var gold_text = ("金币" if Loc.current_lang == "zh" else "Gold") + ": %d" % GameState.player_gold
		hp_label.text = "%s  %s  %s" % [hp_text, armor_text, gold_text]
	if dice_label:
		var dice_str = "🎲 "
		for d in GameState.active_dice:
			dice_str += "[%d] " % d.value
		dice_str += "= +%d" % current_dice_bonus
		# Show active buffs
		var buffs = ""
		if speed_boost_timer > 0:
			buffs += " ⚡%.0f" % speed_boost_timer
		if damage_boost_timer > 0:
			buffs += " 🔥%.0f" % damage_boost_timer
		if magnet_active:
			buffs += " 🧲%.0f" % magnet_timer
		if buffs != "":
			dice_str += "  |" + buffs
		dice_label.text = dice_str
	
	# Card panels
	for i in range(min(4, card_panels.size())):
		var panel = card_panels[i]
		var vbox = panel.get_child(0)  # VBoxContainer
		var header = vbox.get_child(0)  # HBoxContainer
		var card_lbl = header.get_child(0)  # CardLabel
		var cd_lbl = vbox.get_child(1)  # CooldownLabel
		if i < card_slots.size():
			var card_def = GameData.CARDS.get(card_slots[i])
			if card_def:
				card_lbl.text = _card_name(card_slots[i], card_def)
			var cd = card_cooldowns.get(card_slots[i], 0.0)
			if cd > 0:
				cd_lbl.text = "%.1fs" % cd
				panel.modulate = Color(0.5, 0.5, 0.5)
			else:
				cd_lbl.text = ("就绪" if Loc.current_lang == "zh" else "Ready")
				panel.modulate = Color.WHITE
		else:
			card_lbl.text = "-"
			cd_lbl.text = ""

func add_log(text: String):
	if log_label:
		log_label.append_text(text + "\n")
