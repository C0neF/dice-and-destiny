## Survivor-mode arena: top-down real-time combat with cards + dice
extends Node2D

signal wave_complete(wave_num: int)
signal run_over(victory: bool)

const ARENA_SIZE = Vector2(640, 360)
# Wall-interior bounds (matching the current survivor_arena_bg wall inner edges)
# Tuned for the 1376x768 replacement map scaled to 720x440 at (-40, -40).
const ARENA_MIN = Vector2(-5, 20)
const ARENA_MAX = Vector2(645, 340)
const SPAWN_MARGIN = 40.0
const WALL_THICKNESS = 40.0  # Collision wall thickness (placed outside playable area)
const MAGE_COLOR_PRIMARY := Color(0.74, 0.44, 1.0, 0.95)
const MAGE_COLOR_SECONDARY := Color(1.0, 0.58, 0.92, 0.92)

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
var _holy_cross_timer: float = 0.0
var _meteor_timer: float = 0.0
var _spirit_sword_timer: float = 0.0
var _earthquake_timer: float = 0.0
var _vampiric_aura_timer: float = 0.0
var _orbit_visual: Node2D
var _temp_slow_effects: Dictionary = {}  # enemy_id -> {"enemy": Node2D, "until": float, "factor": float}

# Survivor permanent point upgrades from shop
var bonus_attack_points: int = 0
var bonus_armor_points: int = 0

# In-run total purchase counters (used for cross-wave price growth)
var shop_heal_buy_count: int = 0
var shop_upgrade_buy_count: int = 0
var shop_attack_point_buy_count: int = 0
var shop_armor_point_buy_count: int = 0

# Per-shop purchase flags (reset each wave shop)
var shop_heal_bought_this_shop: bool = false
var shop_upgrade_bought_this_shop: bool = false
var shop_attack_point_bought_this_shop: bool = false
var shop_armor_point_bought_this_shop: bool = false

# Wave state
var current_wave: int = 0
var wave_timer: float = 0.0
var wave_duration: float = 45.0  # Seconds per wave
var is_hard_mode: bool = false
var enemies_alive: int = 0
var spawn_timer: float = 0.0
var spawn_interval: float = 1.5
var is_wave_active: bool = false
var is_shopping: bool = false
var is_paused: bool = false
var _pause_layer: CanvasLayer = null

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

# Skill test mode
var is_skill_test_mode: bool = false
var skill_test_panel: PanelContainer = null
var skill_test_level: int = 3
const SKILL_TEST_ATTACKS = [
	{"id":"orbit_blades", "name_zh":"旋转刀刃", "name_en":"Orbit Blades"},
	{"id":"chain_lightning_passive", "name_zh":"连锁闪电", "name_en":"Chain Lightning"},
	{"id":"flame_tornado", "name_zh":"火焰旋风", "name_en":"Flame Tornado"},
	{"id":"ice_nova", "name_zh":"冰霜新星", "name_en":"Ice Nova"},
	{"id":"poison_cloud", "name_zh":"毒雾", "name_en":"Poison Cloud"},
	{"id":"holy_cross", "name_zh":"圣光十字", "name_en":"Holy Cross"},
	{"id":"meteor_rain", "name_zh":"陨石雨", "name_en":"Meteor Rain"},
	{"id":"spirit_sword", "name_zh":"灵魂飞剑", "name_en":"Spirit Sword"},
	{"id":"earthquake", "name_zh":"地震", "name_en":"Earthquake"},
	{"id":"vampiric_aura", "name_zh":"吸血光环", "name_en":"Vampiric Aura"},
]

func _ready():
	# Allow this node to process input even when tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_skill_test_mode = (GameState.run_mode == "survivor_test")
	is_hard_mode = (GameState.survivor_difficulty == "hard")
	_setup_arena()
	_setup_player()
	_setup_ui()
	if is_skill_test_mode:
		_start_skill_test_mode()
	else:
		_start_wave(1)
	VFX.fade_in(0.4)
	SFX.play_bgm("battle")

func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if is_paused:
			_resume_game()
		elif not is_shopping:
			_pause_game()

func _start_skill_test_mode():
	current_wave = 1
	wave_timer = 9999.0
	spawn_timer = 9999.0
	is_wave_active = true
	is_shopping = false
	GameState.roll_all_dice()
	current_dice_bonus = _calc_dice_bonus()
	for p in card_panels:
		if is_instance_valid(p):
			p.visible = false
	add_log("[color=cyan]🧪 技能测试模式：点击右侧技能按钮释放效果[/color]")
	_setup_skill_test_panel()
	_spawn_skill_test_targets()

func _setup_skill_test_panel():
	if not hud:
		return
	skill_test_panel = PanelContainer.new()
	skill_test_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skill_test_panel.position = Vector2(-300, 16)
	skill_test_panel.size = Vector2(284, 420)
	skill_test_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(skill_test_panel)
	
	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	skill_test_panel.add_child(m)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)
	
	var title = Label.new()
	title.text = ("技能测试" if Loc.current_lang == "zh" else "Skill Test")
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	
	var hint = Label.new()
	hint.text = (("点击技能立即释放（Lv%d）" % skill_test_level) if Loc.current_lang == "zh" else ("Click a skill to cast instantly (Lv%d)" % skill_test_level))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vb.add_child(hint)
	
	var btn_grid = GridContainer.new()
	btn_grid.columns = 2
	btn_grid.add_theme_constant_override("h_separation", 6)
	btn_grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(btn_grid)
	
	for s in SKILL_TEST_ATTACKS:
		var b = Button.new()
		b.custom_minimum_size = Vector2(126, 34)
		b.text = str(s["name_zh"]) if Loc.current_lang == "zh" else str(s["name_en"])
		var sid = str(s["id"])
		b.pressed.connect(func(): _cast_skill_test(sid))
		btn_grid.add_child(b)
	
	var refresh_btn = Button.new()
	refresh_btn.custom_minimum_size = Vector2(0, 34)
	refresh_btn.text = ("刷新靶子" if Loc.current_lang == "zh" else "Respawn Targets")
	refresh_btn.pressed.connect(_respawn_skill_test_targets)
	vb.add_child(refresh_btn)
	
	var back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(0, 34)
	back_btn.text = ("返回主菜单" if Loc.current_lang == "zh" else "Back to Menu")
	back_btn.pressed.connect(func():
		GameState.run_mode = "survivor"
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")
	)
	vb.add_child(back_btn)

func _respawn_skill_test_targets():
	for e in enemy_container.get_children():
		if is_instance_valid(e):
			e.queue_free()
	_spawn_skill_test_targets()

func _spawn_skill_test_targets():
	var enemy_ids = ["slime", "mushroom", "skeleton", "goblin", "bat", "ghost"]
	var radius = 120.0
	for i in range(enemy_ids.size()):
		var angle = TAU * float(i) / float(enemy_ids.size())
		var pos = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		_spawn_test_enemy(enemy_ids[i], pos)

func _spawn_test_enemy(enemy_id: String, spawn_pos: Vector2):
	var def = GameData.ENEMIES.get(enemy_id)
	if not def:
		return
	var enemy_scene = CharacterBody2D.new()
	var script = load("res://scripts/battle/enemy_unit.gd")
	enemy_scene.set_script(script)
	enemy_scene.position = spawn_pos
	enemy_container.add_child(enemy_scene)
	enemy_scene.add_to_group("enemies")
	enemy_scene.setup(def, player, 0.8)
	enemy_scene.arena_min = ARENA_MIN
	enemy_scene.arena_max = ARENA_MAX
	enemy_scene.died.connect(func(_enemy, _pos):
		if not is_skill_test_mode:
			return
		var respawn_id = enemy_id
		get_tree().create_timer(0.9).timeout.connect(func():
			if is_skill_test_mode and is_instance_valid(self):
				var jitter = Vector2(randf_range(-60, 60), randf_range(-40, 40))
				var base = player.global_position + Vector2(randf_range(-160, 160), randf_range(-120, 120))
				_spawn_test_enemy(respawn_id, base + jitter)
		)
	)

func _cast_skill_test(skill_id: String):
	var lvl = skill_test_level
	match skill_id:
		"orbit_blades":
			_orbit_timer += 0.25
			_update_orbit_blades(lvl)
		"chain_lightning_passive":
			_fire_chain_lightning(lvl)
		"flame_tornado":
			_spawn_flame_tornado(lvl)
		"ice_nova":
			_fire_ice_nova(lvl)
		"poison_cloud":
			_apply_poison_cloud(lvl)
		"holy_cross":
			_fire_holy_cross(lvl)
		"meteor_rain":
			_drop_meteors(lvl)
		"spirit_sword":
			_fire_spirit_swords(lvl)
		"earthquake":
			_trigger_earthquake(lvl)
		"vampiric_aura":
			_apply_vampiric_aura(lvl)
		_:
			return
	add_log("[color=violet]🧪 释放技能：%s[/color]" % skill_id)

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
	
	# No extra static crystal obstacles on the map; keep only arena wall colliders.
	
	enemy_container = Node2D.new()
	enemy_container.name = "Enemies"
	enemy_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(enemy_container)
	
	projectile_container = Node2D.new()
	projectile_container.name = "Projectiles"
	projectile_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(projectile_container)
	
	drop_container = Node2D.new()
	drop_container.name = "Drops"
	drop_container.process_mode = Node.PROCESS_MODE_PAUSABLE
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
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	# Pass arena bounds so the player clamp uses shared constants
	player.arena_min = ARENA_MIN
	player.arena_max = ARENA_MAX
	# Sync HP bar on spawn
	player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
	
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
	log_label.position = Vector2(-250, -230)
	log_label.size = Vector2(190, 96)
	log_label.add_theme_font_size_override("normal_font_size", 10)
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

func _card_desc(card_id: String, card_def = null) -> String:
	if card_def == null:
		card_def = GameData.CARDS.get(card_id)
	if not card_def:
		return card_id
	
	var base_desc = str(card_def.description).replace("{value}", str(card_def.base_value))
	if Loc.current_lang != "zh":
		return base_desc
	
	var zh_desc_map = {
		"strike": "造成 {value} 点伤害",
		"heavy_strike": "造成 {value} 点伤害",
		"block": "向面朝方向闪现一段距离（冷却30秒）",
		"fortress": "获得 {value} 点护甲",
		"fireball": "对全体造成 {value} 点魔法伤害",
		"ice_shard": "造成 {value} 点伤害并冻结 1 回合",
		"heal": "恢复 {value} 点生命",
		"regenerate": "3 回合内每回合恢复 {value} 点生命",
		"lucky_roll": "随机触发：斩击 / 闪现 / 治疗（冷却40秒）",
		"loaded_dice": "将一颗骰子固定为 6",
		"poison_strike": "造成 {value} 点伤害并附加 2 层中毒",
		"mirror_shield": "获得 {value} 点护甲并反弹 50% 下次伤害",
		"flurry": "造成 3 次 {value} 点伤害",
		"chain_lightning": "对全体造成 {value} 点伤害，每层连击额外 +3",
		"battle_cry": "本场战斗获得 {value} 点力量",
		"vampiric_strike": "造成 {value} 点伤害并回复一半",
		"weaken": "施加 {value} 层虚弱与易伤",
		"dodge_roll": "获得闪避并抽 1 张牌",
		"inferno": "对全体施加 {value} 层灼烧",
		"summon_familiar": "召唤使魔，每回合造成 {value} 点伤害",
		"double_or_nothing": "若骰子≥4，效果翻倍；否则无效果",
		"curse_of_pain": "造成 {value} 点伤害并施加 2 回合易伤",
	}
	
	var zh_desc = str(zh_desc_map.get(card_id, base_desc))
	return zh_desc.replace("{value}", str(card_def.base_value))

func _process(delta):
	if is_paused or is_shopping:
		return
	
	if is_wave_active:
		if not is_skill_test_mode:
			_update_wave(delta)
		_update_dice(delta)
		if not is_skill_test_mode:
			_update_auto_attack(delta)
			_update_passive_attacks(delta)
			_handle_card_input()
			_update_card_cooldowns(delta)
			_check_contact_damage()
			# Magnet pulls new drops
			if magnet_active:
				_activate_all_magnets()
		_update_buffs(delta)
		_update_temp_slow_effects()
	
	_update_hud()

# === WAVE MANAGEMENT ===

func _start_wave(wave_num: int):
	current_wave = wave_num
	if is_hard_mode:
		wave_timer = 120.0  # Hard mode: 2-minute wave duration
	else:
		wave_timer = wave_duration + min(wave_num * 5, 30)  # Longer waves as you progress
	spawn_interval = max(0.3, (1.25 if is_hard_mode else 1.5) - wave_num * (0.12 if is_hard_mode else 0.1))
	spawn_timer = 0
	is_wave_active = true
	is_shopping = false
	
	# Roll initial dice
	GameState.roll_all_dice()
	current_dice_bonus = _calc_dice_bonus()
	
	# Apply permanent armor points at start of each wave
	if bonus_armor_points > 0:
		GameState.add_armor(bonus_armor_points)
	
	SFX.play("wave_start")
	if wave_num == 1 and is_hard_mode:
		add_log("[color=red]⚠ 困难模式：怪物更强、掉落更少、数量更多[/color]")
	add_log("[color=yellow]第 %d 波开始！[/color]" % wave_num)

func _update_wave(delta):
	wave_timer -= delta
	spawn_timer -= delta
	
	if spawn_timer <= 0:
		_spawn_enemy()
		if is_hard_mode and randf() < 0.6:
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
	if is_hard_mode:
		level_scale *= 1.75
	enemy_scene.setup(def, player, level_scale)
	if is_hard_mode:
		enemy_scene.move_speed *= 1.22
	enemy_scene.arena_min = ARENA_MIN
	enemy_scene.arena_max = ARENA_MAX
	enemy_scene.died.connect(_on_enemy_died)
	enemies_alive += 1
	
	# Boss wave every 5 waves: also spawn boss
	var active_wave_duration = 120.0 if is_hard_mode else wave_duration
	if current_wave % 5 == 0 and wave_timer > active_wave_duration * 0.8:
		var boss_spawn_roll = 10 if not is_hard_mode else 6
		if randi() % boss_spawn_roll == 0:
			var boss_def = GameData.ENEMIES.get("demon")
			if boss_def:
				var boss = CharacterBody2D.new()
				boss.set_script(script)
				boss.position = spawn_pos + Vector2(30, 0)
				enemy_container.add_child(boss)
				boss.add_to_group("enemies")
				var boss_scale = level_scale * (1.0 if is_hard_mode else 0.7)
				boss.setup(boss_def, player, boss_scale)
				if is_hard_mode:
					boss.move_speed *= 1.18
				boss.arena_min = ARENA_MIN
				boss.arena_max = ARENA_MAX
				boss.died.connect(_on_enemy_died)

func _get_enemy_pool() -> Array:
	var pool = ["slime", "bat"]
	if current_wave >= 2: pool.append("mushroom")
	if current_wave >= 3: pool.append_array(["skeleton", "goblin"])
	if current_wave >= 4: pool.append("fire_elemental")
	if current_wave >= 5: pool.append_array(["ghost", "mimic"])
	if current_wave >= 7: pool.append_array(["dark_knight", "ice_golem"])
	if current_wave >= 9: pool.append_array(["skeleton", "goblin", "fire_elemental"])  # More spawns
	return pool

func _on_enemy_died(_enemy, _pos: Vector2):
	enemies_alive -= 1
	SFX.play_varied("enemy_die")
	# Spawn drops
	_spawn_drops(_pos)
	# Mimic: bonus gold + guaranteed health potion (hard mode gets reduced rewards)
	if _enemy is CharacterBody2D and _enemy.enemy_def \
			and _enemy.enemy_def.type == GameData.EnemyType.MIMIC:
		if is_hard_mode:
			_create_drop(0, randi_range(2, 6), _pos)  # Further reduced extra gold
			if randf() < 0.25:
				_create_drop(1, 8, _pos)
		else:
			_create_drop(0, randi_range(8, 15), _pos)  # Extra gold
			_create_drop(1, 15, _pos)  # Health potion
	if GameState.relics.has("blood_vial"):
		GameState.heal(1)

# === DROP SYSTEM ===

func _spawn_drops(pos: Vector2):
	# Always drop some gold (hard mode reduced)
	if is_hard_mode:
		_create_drop(0, 1, pos)  # DropType.GOLD = 0
	else:
		_create_drop(0, randi_range(1, 3), pos)
	
	# Random additional drops (hard mode: lower rates)
	var roll = randf()
	if is_hard_mode:
		if roll < 0.04:
			_create_drop(1, 6 + current_wave, pos)  # Health potion
		elif roll < 0.055:
			_create_drop(4, 1, pos)  # Energy orb
		elif roll < 0.07:
			_create_drop(2, 4, pos)  # Speed boost
		elif roll < 0.085:
			_create_drop(3, 4, pos)  # Damage boost
		elif roll < 0.095:
			_create_drop(5, 5, pos)  # Magnet
		elif roll < 0.10:
			_create_drop(6, 0, pos)  # Bomb
	else:
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
	
	# Boss drops guaranteed extra (hard mode reduced)
	if current_wave % 5 == 0:
		if is_hard_mode:
			if randf() < 0.5:
				_create_drop(1, 10, pos)
			if randf() < 0.3:
				_create_drop(3, 5, pos)
		else:
			_create_drop(1, 20, pos)
			_create_drop(3, 8, pos)

func _create_drop(type: int, val: int, pos: Vector2):
	# Clamp spawn position to arena interior
	pos.x = clampf(pos.x, ARENA_MIN.x + 8, ARENA_MAX.x - 8)
	pos.y = clampf(pos.y, ARENA_MIN.y + 8, ARENA_MAX.y - 8)
	var drop = Area2D.new()
	drop.set_script(DropItemScript)
	# setup BEFORE add_child so _ready() sees the correct drop_type
	drop.setup(type, val, player, pos)
	drop.arena_min = ARENA_MIN
	drop.arena_max = ARENA_MAX
	drop_container.add_child(drop)
	drop.collected.connect(_on_drop_collected)

func _on_drop_collected(drop_type: int, value: int):
	match drop_type:
		0:  # GOLD
			GameState.add_gold(value)
			SFX.play_varied("coin")
			add_log("[color=yellow]+%dG[/color]" % value)
		1:  # HEALTH_POTION
			GameState.heal(value)
			SFX.play("heal")
			add_log("[color=green]+%d 生命[/color]" % value)
			VFX.flash_screen(Color(0.1, 0.9, 0.2, 0.15), 0.15)
		2:  # SPEED_BOOST
			speed_boost_timer = float(value)
			player.move_speed = 180.0
			SFX.play("powerup")
			add_log("[color=cyan]⚡ 速度提升！[/color]")
		3:  # DAMAGE_BOOST
			damage_boost_timer = float(value)
			SFX.play("powerup")
			add_log("[color=orange]🔥 伤害提升！[/color]")
		4:  # ENERGY_ORB
			GameState.player_energy = min(GameState.player_max_energy, GameState.player_energy + value)
			SFX.play("powerup")
			add_log("[color=blue]+%d 能量[/color]" % value)
		5:  # MAGNET
			magnet_active = true
			magnet_timer = float(value)
			_activate_all_magnets()
			SFX.play("powerup")
			add_log("[color=white]🧲 磁铁生效！[/color]")
		6:  # BOMB
			_detonate_bomb(player.global_position)
			add_log("[color=red]💥 炸弹爆发！[/color]")

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
	SFX.play("explosion")
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
	add_log("[color=green]第 %d 波完成！[/color]" % current_wave)
	wave_complete.emit(current_wave)
	
	# Heal between waves
	GameState.heal(GameState.player_max_hp / 5)
	
	# Instantly collect ALL remaining drops (no animation delay)
	_force_collect_all_drops()
	
	# Brief pause then open shop
	await get_tree().create_timer(0.5).timeout
	_open_shop()

## Force-collect every drop on the field immediately (no magnet flight).
## This guarantees gold is accurate before the shop opens.
func _force_collect_all_drops():
	var drops = drop_container.get_children().duplicate()
	for drop in drops:
		if not is_instance_valid(drop):
			continue
		
		var drop_type = drop.get("drop_type")
		var drop_value = drop.get("value")
		
		# Emit only for actual drop items
		if drop.has_signal("collected") and drop_type != null and drop_value != null:
			drop.collected.emit(int(drop_type), int(drop_value))
		
		# Spawn a quick fly-to-player visual (safe for non-drop nodes too)
		if is_instance_valid(player):
			_spawn_collect_fly(drop.global_position, player.global_position, int(drop_type) if drop_type != null else -1)
		drop.queue_free()

## Small particle that flies from drop position to player (cosmetic only)
func _spawn_collect_fly(from: Vector2, to: Vector2, drop_type: int = -1):
	var color: Color = Color(1, 0.85, 0.1)
	if drop_type >= 0 and DropItemScript:
		var config = DropItemScript.DROP_CONFIG.get(drop_type)
		if config != null and config.size() > 0:
			color = config[0]
	
	var p = ColorRect.new()
	p.size = Vector2(3, 3)
	p.position = from - Vector2(1.5, 1.5)
	p.color = color
	p.z_index = 20
	add_child(p)
	var tw = p.create_tween()
	tw.tween_property(p, "position", to - Vector2(1.5, 1.5), 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)

# === DICE SYSTEM ===

func _update_dice(delta):
	dice_timer += delta
	if dice_timer >= dice_roll_interval:
		dice_timer = 0
		GameState.roll_all_dice()
		current_dice_bonus = _calc_dice_bonus()
		SFX.play("dice_roll")
		add_log("[color=cyan]🎲 掷骰完成！加成：+%d[/color]" % current_dice_bonus)

func _calc_dice_bonus() -> int:
	var total = 0
	for d in GameState.active_dice:
		total += d.value
	return total

# === AUTO ATTACK ===

var auto_attack_timer: float = 0.0
var auto_attack_interval: float = 0.8
var auto_attack_targets: int = 1  # Lv1=1 target, max Lv5=5 targets

func _update_auto_attack(delta):
	auto_attack_timer -= delta
	if auto_attack_timer > 0:
		return
	auto_attack_timer = auto_attack_interval
	
	# Find nearest enemies up to auto_attack_targets count
	var targets = _find_nearest_enemies(auto_attack_targets)
	if targets.is_empty():
		return
	
	var base_dmg = 3 + bonus_attack_points + current_dice_bonus / 4
	var dmg = int(base_dmg * _get_damage_multiplier())
	for target in targets:
		var dir = (target.global_position - player.global_position).normalized()
		var proj = _create_projectile(player.global_position, dir, dmg, 180.0)
		proj.setup_visual(MAGE_COLOR_SECONDARY, 3.2)

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

func _find_nearest_enemies(count: int) -> Array:
	var candidates: Array = []
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist < 300.0:
			candidates.append({"enemy": e, "dist": dist})
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var result: Array = []
	for i in range(min(count, candidates.size())):
		result.append(candidates[i]["enemy"])
	return result

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

func _shop_heal_cost() -> int:
	if shop_heal_buy_count == 0:
		return 1
	if shop_heal_buy_count == 1:
		return 5
	if shop_heal_buy_count == 2:
		return 10
	return 10 + (shop_heal_buy_count - 2) * 5

func _shop_upgrade_attack_cost() -> int:
	return 20 + shop_upgrade_buy_count * 20

func _shop_attack_point_cost() -> int:
	return 10 + shop_attack_point_buy_count * 10

func _shop_armor_point_cost() -> int:
	return 10 + shop_armor_point_buy_count * 10

func _apply_temporary_slow(enemy: Node2D, factor: float, duration: float):
	if not is_instance_valid(enemy):
		return
	var key = int(enemy.get_instance_id())
	var now = Time.get_ticks_msec() / 1000.0
	var until = now + duration
	var restore_factor = enemy.slow_factor
	if _temp_slow_effects.has(key):
		var old = _temp_slow_effects[key]
		var old_until = float(old.get("until", 0.0))
		until = max(until, old_until)
		restore_factor = float(old.get("restore", restore_factor))
	_temp_slow_effects[key] = {
		"enemy": enemy,
		"until": until,
		"factor": factor,
		"restore": restore_factor,
	}
	enemy.slow_factor = min(enemy.slow_factor, factor)

func _update_temp_slow_effects():
	if _temp_slow_effects.is_empty():
		return
	var now = Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []
	for key in _temp_slow_effects.keys():
		var entry = _temp_slow_effects[key]
		var enemy = entry.get("enemy") as Node2D
		if not is_instance_valid(enemy):
			to_remove.append(key)
			continue
		var factor = float(entry.get("factor", 1.0))
		enemy.slow_factor = min(enemy.slow_factor, factor)
		if now >= float(entry.get("until", 0.0)):
			if is_equal_approx(enemy.slow_factor, factor):
				enemy.slow_factor = float(entry.get("restore", 1.0))
			to_remove.append(key)
	for key in to_remove:
		_temp_slow_effects.erase(key)

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
	
	# Holy cross - fires projectiles in 4 cardinal directions
	if unlocked_attacks.has("holy_cross"):
		lvl = attack_levels.get("holy_cross", 1)
		_holy_cross_timer += delta
		var interval = max(1.0, 2.5 - lvl * 0.3)
		if _holy_cross_timer >= interval:
			_holy_cross_timer = 0.0
			_fire_holy_cross(lvl)
	
	# Meteor rain - drops meteors on random enemies
	if unlocked_attacks.has("meteor_rain"):
		lvl = attack_levels.get("meteor_rain", 1)
		_meteor_timer += delta
		var interval = max(2.0, 4.5 - lvl * 0.5)
		if _meteor_timer >= interval:
			_meteor_timer = 0.0
			_drop_meteors(lvl)
	
	# Spirit swords - homing projectiles seeking enemies
	if unlocked_attacks.has("spirit_sword"):
		lvl = attack_levels.get("spirit_sword", 1)
		_spirit_sword_timer += delta
		var interval = max(1.5, 3.5 - lvl * 0.4)
		if _spirit_sword_timer >= interval:
			_spirit_sword_timer = 0.0
			_fire_spirit_swords(lvl)
	
	# Earthquake - periodic shockwave expanding from player
	if unlocked_attacks.has("earthquake"):
		lvl = attack_levels.get("earthquake", 1)
		_earthquake_timer += delta
		var interval = max(3.0, 6.0 - lvl * 0.6)
		if _earthquake_timer >= interval:
			_earthquake_timer = 0.0
			_trigger_earthquake(lvl)
	
	# Vampiric aura - drains HP from nearby enemies, heals player
	if unlocked_attacks.has("vampiric_aura"):
		lvl = attack_levels.get("vampiric_aura", 1)
		_vampiric_aura_timer += delta
		if _vampiric_aura_timer >= 2.0:
			_vampiric_aura_timer = 0.0
			_apply_vampiric_aura(lvl)

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
	SFX.play("lightning")
	add_log("[color=cyan]⚡ 连锁闪电命中 %d[/color]" % hit.size())

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

## Flame tornado - nova-shaped pulse that applies sustained burn damage
func _spawn_flame_tornado(lvl: int):
	var radius = 80.0 + lvl * 14.0
	var burn_add = 3 + lvl * 2
	var hit_count = 0
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		if e.global_position.distance_to(player.global_position) <= radius:
			e.burn_stacks += burn_add
			hit_count += 1
	
	_spawn_explosion_ring(player.global_position, radius, Color(1.0, 0.48, 0.12))
	VFX.flash_screen(Color(1.0, 0.35, 0.1, 0.16), 0.1)
	SFX.play("fire")
	add_log("[color=orange]🔥 火焰旋风：持续灼烧 %d[/color]" % hit_count)

## Ice nova - control-only: Lv1 slow, Lv2 freeze 1s, Lv3+ freeze 3s (no damage)
func _fire_ice_nova(lvl: int):
	var radius = 80.0 + lvl * 15.0
	var enemies = _find_enemies_in_range(player.global_position, radius)
	if enemies.is_empty():
		return
	
	if lvl <= 1:
		for e in enemies:
			_apply_temporary_slow(e, 0.45, 1.6)
		add_log("[color=aqua]❄️ 冰霜新星 Lv1：减速 %d[/color]" % enemies.size())
	elif lvl == 2:
		for e in enemies:
			e.freeze_timer = max(e.freeze_timer, 1.0)
		add_log("[color=aqua]❄️ 冰霜新星 Lv2：定身 1s（%d）[/color]" % enemies.size())
	else:
		for e in enemies:
			e.freeze_timer = max(e.freeze_timer, 3.0)
		add_log("[color=aqua]❄️ 冰霜新星 Lv3：定身 3s（%d）[/color]" % enemies.size())
	
	_spawn_explosion_ring(player.global_position, radius, Color(0.3, 0.6, 1.0))
	VFX.flash_screen(Color(0.3, 0.5, 1.0, 0.2), 0.12)
	SFX.play("freeze")

## Poison cloud - nova-shaped pulse that applies sustained poison damage
func _apply_poison_cloud(lvl: int):
	var radius = 80.0 + lvl * 14.0
	var poison_add = 3 + lvl * 2
	var hit_count = 0
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		if e.global_position.distance_to(player.global_position) <= radius:
			e.poison_stacks += poison_add
			hit_count += 1
	
	_spawn_explosion_ring(player.global_position, radius, Color(0.35, 0.95, 0.55))
	VFX.flash_screen(Color(0.25, 0.85, 0.45, 0.12), 0.08)
	SFX.play("powerup")
	add_log("[color=green]☣ 毒雾：持续中毒 %d[/color]" % hit_count)

## Holy cross - fires projectiles in 4 (+ diagonals at higher levels) directions
func _fire_holy_cross(lvl: int):
	var dmg = int((4 + lvl * 3) * _get_damage_multiplier())
	var speed = 160.0 + lvl * 15
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	# Lvl 3+: add diagonals
	if lvl >= 3:
		directions.append_array([
			Vector2(1, 1).normalized(), Vector2(1, -1).normalized(),
			Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()
		])
	var pierce_count = 1 + lvl
	for dir in directions:
		var p = _create_projectile(player.global_position, dir, dmg, speed)
		p.pierce = pierce_count
		p.setup_visual(MAGE_COLOR_PRIMARY, 5)
	# Visual flash
	VFX.flash_screen(Color(0.62, 0.48, 1.0, 0.14), 0.06)

## Meteor rain - drops AoE meteors on random enemy positions
func _drop_meteors(lvl: int):
	var count = 1 + lvl
	var dmg = int((10 + lvl * 5) * _get_damage_multiplier())
	var radius = 35.0 + lvl * 8
	var targets = _find_enemies_in_range(player.global_position, 250.0 + lvl * 30)
	if targets.is_empty():
		return
	
	for i in range(count):
		var target_enemy = targets[randi() % targets.size()]
		if not is_instance_valid(target_enemy):
			continue
		var impact_pos = target_enemy.global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
		# Delayed impact via timer
		var delay = i * 0.2
		_spawn_meteor(impact_pos, dmg, radius, delay)
	
	add_log("[color=red]☄️ 陨石降临 %d 发！[/color]" % count)
	SFX.play("explosion", 0.7)

func _spawn_meteor(pos: Vector2, dmg: int, radius: float, delay: float):
	# Warning indicator
	var warning = ColorRect.new()
	warning.size = Vector2(radius * 2, radius * 2)
	warning.position = pos - Vector2(radius, radius)
	warning.color = Color(1, 0.3, 0.0, 0.15)
	warning.z_index = 8
	add_child(warning)
	
	# Grow the warning
	var tw = warning.create_tween()
	tw.tween_property(warning, "modulate:a", 0.6, 0.3 + delay)
	tw.tween_callback(func():
		# Impact!
		for e in enemy_container.get_children():
			if e.has_method("take_damage"):
				if e.global_position.distance_to(pos) < radius:
					var kb = (e.global_position - pos).normalized()
					e.take_damage(dmg, kb)
					e.burn_stacks += 2
		# Visual explosion
		_spawn_explosion_ring(pos, radius, Color(1, 0.4, 0.0))
		VFX.screen_shake(4.0, 5.0)
		warning.queue_free()
	)

## Spirit swords - homing projectiles with level-based ricochet
func _fire_spirit_swords(lvl: int):
	var count = 1 + (lvl / 2)  # 1 at lv1-2, 2 at lv3-4, 3 at lv5+
	var dmg = int((6 + lvl * 2) * _get_damage_multiplier())
	var bounce_max = 0
	if lvl == 2:
		bounce_max = 1
	elif lvl >= 3:
		bounce_max = 3
	
	for i in range(count):
		var angle = randf() * TAU
		var spawn_offset = Vector2(cos(angle), sin(angle)) * 20
		var sword = Area2D.new()
		sword.position = player.global_position + spawn_offset
		sword.z_index = 12
		add_child(sword)
		sword.add_to_group("spirit_swords")
		
		# Visual
		var sprite = ColorRect.new()
		sprite.size = Vector2(8, 3)
		sprite.position = Vector2(-4, -1.5)
		sprite.color = Color(0.5, 0.8, 1.0, 0.9)
		sword.add_child(sprite)
		
		# Collision
		var col = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 5.0
		col.shape = shape
		sword.add_child(col)
		sword.collision_layer = 0
		sword.collision_mask = 2
		sword.monitoring = true
		sword.monitorable = false
		
		# Homing logic via metadata
		var meta = {
			"dmg": dmg,
			"speed": 130.0 + lvl * 20,
			"lifetime": 3.2,
			"hit": [],
			"bounce_left": bounce_max,
			"hit_cd": 0.0,
		}
		sword.set_meta("sword_data", meta)
		
		sword.body_entered.connect(func(body):
			if not body.has_method("take_damage"):
				return
			if meta.hit_cd > 0.0:
				return
			if meta.hit.has(body):
				return
			meta.hit.append(body)
			var kb = (body.global_position - sword.global_position).normalized()
			if kb == Vector2.ZERO:
				kb = Vector2.RIGHT.rotated(randf() * TAU)
			body.take_damage(meta.dmg, kb)
			_spawn_damage_hit_flash(sword.global_position, Color(0.5, 0.8, 1.0))
			
			# Ricochet logic
			if meta.bounce_left > 0:
				meta.bounce_left -= 1
				meta.hit_cd = 0.08
				sword.position = body.global_position + kb * 10.0
			else:
				sword.queue_free()
		)
		
		# Drive homing via process
		var _process_cb: Callable
		_process_cb = func(delta_inner: float):
			if not is_instance_valid(sword):
				return
			meta.lifetime -= delta_inner
			if meta.lifetime <= 0:
				sword.queue_free()
				return
			if meta.hit_cd > 0.0:
				meta.hit_cd = max(0.0, float(meta.hit_cd) - delta_inner)
			
			# Find nearest unhitted enemy
			var best: Node2D = null
			var best_dist = 260.0
			for e in enemy_container.get_children():
				if e.has_method("take_damage") and not meta.hit.has(e):
					var d = e.global_position.distance_to(sword.global_position)
					if d < best_dist:
						best_dist = d
						best = e
			if best:
				var dir = (best.global_position - sword.global_position).normalized()
				sword.position += dir * meta.speed * delta_inner
				sprite.rotation = dir.angle()
			else:
				# If no next target after at least one hit, end early
				if meta.hit.size() > 0:
					sword.queue_free()
					return
				sword.position += Vector2.RIGHT.rotated(sprite.rotation) * meta.speed * delta_inner * 0.45
		
		var timer = Timer.new()
		timer.wait_time = 0.016
		timer.autostart = true
		sword.add_child(timer)
		timer.timeout.connect(func(): _process_cb.call(0.016))

func _spawn_damage_hit_flash(pos: Vector2, color: Color):
	for j in range(3):
		var p = ColorRect.new()
		p.size = Vector2(3, 3)
		p.position = pos + Vector2(randf_range(-6, 6), randf_range(-6, 6))
		p.color = color
		p.z_index = 20
		add_child(p)
		var tw = p.create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.25)
		tw.tween_callback(p.queue_free)

func _quake_knockup(enemy: Node2D, _unused: float, delay_before_stun: float, stun_time: float = 0.0):
	if not is_instance_valid(enemy):
		return
	# No launch anymore: enemy is knocked back by take_damage(), then stunned after a short delay.
	if stun_time <= 0.0:
		return
	get_tree().create_timer(delay_before_stun).timeout.connect(func():
		if not is_instance_valid(enemy):
			return
		if enemy.has_method("get") and enemy.has_method("set"):
			var cur_after = float(enemy.get("freeze_timer"))
			enemy.set("freeze_timer", max(cur_after, stun_time))
	)

## Earthquake - lower damage, knockback, level-based range; Lv3 adds delayed stun
func _trigger_earthquake(lvl: int):
	var max_radius: float
	var base_damage: int
	var kb_base: float
	var knockup_lift: float
	var stun_sec: float = 0.0
	match lvl:
		1:
			max_radius = 92.0
			base_damage = 5
			kb_base = 220.0
			knockup_lift = 10.0
		2:
			max_radius = 124.0
			base_damage = 7
			kb_base = 270.0
			knockup_lift = 13.0
		_:
			max_radius = 156.0 + float(max(0, lvl - 3)) * 8.0
			base_damage = 9 + max(0, lvl - 3)
			kb_base = 320.0 + float(max(0, lvl - 3)) * 22.0
			knockup_lift = 16.0 + float(max(0, lvl - 3)) * 2.0
			stun_sec = 1.0
	
	var dmg_center = int(base_damage * _get_damage_multiplier())
	var dmg_edge = max(1, int(round(float(dmg_center) * 0.55)))
	
	VFX.screen_shake(6.0 + lvl * 0.45, 4.5)
	VFX.flash_screen(Color(0.65, 0.46, 0.18, 0.22), 0.10)
	SFX.play("explosion")
	
	# Ring visual
	var ring = Node2D.new()
	ring.position = player.global_position
	ring.z_index = 9
	add_child(ring)
	for i in range(34):
		var angle = TAU * float(i) / 34.0
		var p = ColorRect.new()
		p.size = Vector2(4, 4)
		p.position = Vector2(cos(angle), sin(angle)) * max_radius - Vector2(2, 2)
		p.color = Color(0.82, 0.62, 0.28, 0.9)
		p.z_index = 9
		ring.add_child(p)
		var tw = p.create_tween()
		tw.tween_property(p, "modulate:a", 0.0, 0.20)
		tw.tween_callback(p.queue_free)
	get_tree().create_timer(0.24).timeout.connect(func():
		if is_instance_valid(ring):
			ring.queue_free()
	)
	
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist > max_radius:
			continue
		var dir = (e.global_position - player.global_position).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var t = clampf(dist / max(1.0, max_radius), 0.0, 1.0)
		var dmg = int(round(lerpf(float(dmg_center), float(dmg_edge), t)))
		var kb_force = lerpf(kb_base, kb_base * 0.65, t)
		e.take_damage(dmg, dir * (kb_force / 150.0))
		_quake_knockup(e, knockup_lift, 0.22 + float(lvl) * 0.05, stun_sec)
	
	if lvl >= 3:
		add_log("[color=yellow]🌍 地震Lv3：先击退，再眩晕[/color]")
	else:
		add_log("[color=yellow]🌍 地震：强力击退[/color]")

## Vampiric aura - drains HP from nearby enemies, heals player
func _apply_vampiric_aura(lvl: int):
	var radius = 50.0 + lvl * 12
	var dmg = int((2 + lvl) * _get_damage_multiplier())
	var heal_total = 0
	var hit_count = 0
	
	for e in enemy_container.get_children():
		if e.has_method("take_damage"):
			if e.global_position.distance_to(player.global_position) < radius:
				e.take_damage(dmg, Vector2.ZERO)
				hit_count += 1
				# Visual drain line
				_spawn_drain_line(e.global_position, player.global_position)
	
	if hit_count > 0:
		heal_total = 1 + (hit_count * lvl) / 2
		GameState.heal(heal_total)
		player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)

func _spawn_drain_line(from: Vector2, to: Vector2):
	var line = Line2D.new()
	line.width = 1.5
	line.default_color = Color(0.8, 0.15, 0.2, 0.7)
	line.z_index = 12
	line.add_point(from)
	var mid = (from + to) / 2 + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	line.add_point(mid)
	line.add_point(to)
	add_child(line)
	var tw = line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.3)
	tw.tween_callback(line.queue_free)

func _spawn_mage_cast_fx(pos: Vector2, color: Color = MAGE_COLOR_PRIMARY):
	# Removed the circular cast ring; keep only subtle spark rays.
	for i in range(5):
		var ray = Line2D.new()
		ray.width = 1.4
		ray.default_color = Color(color.lightened(0.18).r, color.lightened(0.18).g, color.lightened(0.18).b, 0.9)
		ray.z_index = 19
		var dir = Vector2.RIGHT.rotated(randf() * TAU)
		ray.add_point(pos)
		ray.add_point(pos + dir * randf_range(6.0, 12.0))
		add_child(ray)
		var ray_tw = ray.create_tween()
		ray_tw.tween_property(ray, "modulate:a", 0.0, 0.12)
		ray_tw.tween_callback(ray.queue_free)

func _player_blink(distance: float = 110.0):
	if not is_instance_valid(player):
		return
	
	var dir = Vector2.RIGHT
	if player.has_method("get_facing_direction"):
		dir = player.get_facing_direction()
	elif player.velocity.length() > 0.01:
		dir = player.velocity.normalized()
	if dir.length() <= 0.01:
		dir = Vector2.RIGHT
	
	var from_pos = player.position
	var target = from_pos + dir.normalized() * distance
	target.x = clampf(target.x, ARENA_MIN.x + 6.0, ARENA_MAX.x - 6.0)
	target.y = clampf(target.y, ARENA_MIN.y + 6.0, ARENA_MAX.y - 6.0)
	player.position = target
	
	# Blink trail
	var trail = Line2D.new()
	trail.width = 2.2
	trail.default_color = Color(0.72, 0.5, 1.0, 0.75)
	trail.z_index = 16
	trail.add_point(from_pos)
	trail.add_point((from_pos + target) * 0.5 + Vector2(randf_range(-4, 4), randf_range(-4, 4)))
	trail.add_point(target)
	add_child(trail)
	var tw = trail.create_tween()
	tw.tween_property(trail, "modulate:a", 0.0, 0.16)
	tw.tween_callback(trail.queue_free)
	
	VFX.flash_screen(Color(0.68, 0.55, 1.0, 0.14), 0.06)
	SFX.play("powerup")

func _player_circle_slash(damage: int, radius: float = 90.0, color: Color = MAGE_COLOR_PRIMARY):
	# Damage enemies around player center
	for e in enemy_container.get_children():
		if not e.has_method("take_damage"):
			continue
		var dist = e.global_position.distance_to(player.global_position)
		if dist <= radius:
			var kb = (e.global_position - player.global_position).normalized()
			e.take_damage(damage, kb)
	
	# Circular slash visual (expand from player center, not projectile-like)
	var ring = Line2D.new()
	ring.width = 2.6
	ring.default_color = Color(color.r, color.g, color.b, 0.92)
	ring.z_index = 18
	ring.position = player.global_position
	var seg = 28
	var final_r = radius * 0.95  # keep overall visual size close to current
	for i in range(seg + 1):
		var a = TAU * float(i) / float(seg)
		ring.add_point(Vector2(cos(a), sin(a)) * final_r)
	ring.scale = Vector2(0.12, 0.12)
	add_child(ring)
	
	var tw = ring.create_tween()
	tw.tween_property(ring, "scale", Vector2.ONE, 0.14)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.15)
	tw.tween_callback(ring.queue_free)
	
	VFX.flash_screen(Color(color.r, color.g, color.b, 0.15), 0.08)
	SFX.play("hit")

func _create_projectile(from: Vector2, dir: Vector2, dmg: int, spd: float = 200.0) -> Node2D:
	_spawn_mage_cast_fx(from + dir * 8.0, MAGE_COLOR_PRIMARY)
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
	
	# Set cooldown
	if card_id == "block" or card_id == "strike" or card_id == "heal":
		card_cooldowns[card_id] = 30.0
	elif card_id == "lucky_roll":
		card_cooldowns[card_id] = 40.0
	else:
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
	SFX.play("card_play")
	_execute_card(card_id, card_def, value)
	
	add_log("%s → %d" % [_card_name(card_id, card_def), value])

func _execute_card(card_id: String, card_def, value: int):
	var nearest = _find_nearest_enemy()
	
	match card_def.type:
		GameData.CardType.ATTACK:
			var attack_value = GameState.apply_damage_with_relics(value)
			match card_id:
				"strike":
					_player_circle_slash(attack_value, 88.0, Color(1.0, 0.82, 0.55, 0.95))
				"heavy_strike":
					_player_circle_slash(attack_value, 104.0, Color(1.0, 0.68, 0.35, 0.95))
				_:
					if nearest:
						var dir = (nearest.global_position - player.global_position).normalized()
						match card_id:
							"flurry":
								for i in range(3):
									var spread = dir.rotated(deg_to_rad(-10 + i * 10))
									var p = _create_projectile(player.global_position, spread, attack_value / 3, 220)
									p.setup_visual(MAGE_COLOR_SECONDARY, 3)
							"vampiric_strike":
								var p = _create_projectile(player.global_position, dir, attack_value, 200)
								p.setup_visual(Color(0.86, 0.28, 0.78), 5)
								GameState.heal(attack_value / 3)
							"poison_strike":
								var p = _create_projectile(player.global_position, dir, attack_value, 180)
								p.status_effect = "poison"
								p.status_stacks = 3
								p.setup_visual(Color(0.45, 1.0, 0.65), 4)
							_:
								var p = _create_projectile(player.global_position, dir, attack_value, 200)
								p.setup_visual(MAGE_COLOR_PRIMARY, 4)
		
		GameData.CardType.DEFEND:
			if card_id == "block":
				_player_blink(110.0)
			else:
				GameState.add_armor(value)
				VFX.flash_screen(Color(0.45, 0.55, 1.0, 0.16), 0.1)
		
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
					VFX.flash_screen(Color(0.9, 0.35, 0.95, 0.22), 0.15)
				"ice_shard":
					if nearest:
						var ice_damage = GameState.apply_damage_with_relics(value)
						var dir = (nearest.global_position - player.global_position).normalized()
						var p = _create_projectile(player.global_position, dir, ice_damage, 160)
						p.status_effect = "freeze"
						p.status_stacks = 2
						p.setup_visual(MAGE_COLOR_SECONDARY, 5)
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
					VFX.flash_screen(Color(0.62, 0.5, 1.0, 0.22), 0.1)
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
						var p = _create_projectile(player.global_position, dir, magic_damage, 180)
						p.setup_visual(MAGE_COLOR_SECONDARY, 4.5)
		
		GameData.CardType.HEAL:
			GameState.heal(value)
			VFX.flash_screen(Color(0.2, 1, 0.3, 0.15), 0.1)
		
		GameData.CardType.DICE_BOOST:
			match card_id:
				"lucky_roll":
					var lucky_mode = randi() % 3
					match lucky_mode:
						0:
							var slash_damage = GameState.apply_damage_with_relics(max(4, value))
							_player_circle_slash(slash_damage, 92.0, Color(1.0, 0.82, 0.55, 0.95))
							add_log("[color=yellow]🎲 幸运骰：斩击[/color]")
						1:
							_player_blink(120.0)
							add_log("[color=violet]🎲 幸运骰：闪现[/color]")
						_:
							var heal_amount = max(4, value)
							GameState.heal(heal_amount)
							if is_instance_valid(player):
								player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
							VFX.flash_screen(Color(0.2, 1.0, 0.35, 0.18), 0.1)
							add_log("[color=green]🎲 幸运骰：治疗 +%d[/color]" % heal_amount)
				"loaded_dice":
					if GameState.active_dice.size() > 0:
						var pick = randi() % GameState.active_dice.size()
						GameState.active_dice[pick].value = 6
						current_dice_bonus = _calc_dice_bonus()
						add_log("[color=cyan]🎲 灌铅骰：一颗骰子固定为6[/color]")
				_:
					GameState.roll_all_dice()
					current_dice_bonus = _calc_dice_bonus()
					add_log("[color=cyan]🎲 重新掷骰！加成 +%d[/color]" % current_dice_bonus)

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
					SFX.play("player_hurt")
					player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
				
				if GameState.is_dead():
					_on_player_died()
					return

func _on_player_died():
	is_wave_active = false
	add_log("[color=red]你倒下了……[/color]")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main/game_over.tscn")

# === SHOP (between waves) ===

func _open_shop():
	is_shopping = true
	
	# Per-shop purchase limits (reset each wave shop)
	shop_heal_bought_this_shop = false
	shop_upgrade_bought_this_shop = false
	shop_attack_point_bought_this_shop = false
	shop_armor_point_bought_this_shop = false
	
	# Full-screen dark overlay
	var overlay = ColorRect.new()
	overlay.name = "ShopOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(overlay)
	
	# Main responsive panel
	var shop_panel = PanelContainer.new()
	shop_panel.name = "ShopPanel"
	shop_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var vp = get_viewport_rect().size
	var edge_gap := 28.0
	var panel_size = Vector2(
		min(980.0, vp.x - edge_gap * 2.0),
		min(680.0, vp.y - edge_gap * 2.0)
	)
	shop_panel.custom_minimum_size = panel_size
	shop_panel.size = panel_size
	var panel_y_offset := -20.0
	shop_panel.position = (vp - panel_size) * 0.5 + Vector2(0, panel_y_offset)
	overlay.add_child(shop_panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	shop_panel.add_child(margin)
	
	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	
	# Header
	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(header)
	
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	
	var title = Label.new()
	title.text = ("🛒 商店" if Loc.current_lang == "zh" else "🛒 Shop")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.45))
	title_box.add_child(title)
	
	var sub = Label.new()
	sub.text = (("第 %d 波结束 · 选择你的强化" if Loc.current_lang == "zh" else "Wave %d cleared · Choose your upgrades") % current_wave)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	title_box.add_child(sub)
	
	var gold_lbl = Label.new()
	gold_lbl.add_theme_font_size_override("font_size", 20)
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	header.add_child(gold_lbl)
	
	var reroll_btn = Button.new()
	reroll_btn.custom_minimum_size = Vector2(150, 36)
	reroll_btn.add_theme_font_size_override("font_size", 13)
	header.add_child(reroll_btn)
	
	root.add_child(HSeparator.new())
	
	# Body: product wall (3 horizontal columns)
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	
	var product_panel = PanelContainer.new()
	product_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	product_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(product_panel)
	
	var product_margin = MarginContainer.new()
	product_margin.add_theme_constant_override("margin_left", 10)
	product_margin.add_theme_constant_override("margin_right", 10)
	product_margin.add_theme_constant_override("margin_top", 10)
	product_margin.add_theme_constant_override("margin_bottom", 10)
	product_panel.add_child(product_margin)
	
	var product_root = VBoxContainer.new()
	product_root.add_theme_constant_override("separation", 8)
	product_margin.add_child(product_root)
	

	var product_row = HBoxContainer.new()
	product_row.add_theme_constant_override("separation", 10)
	product_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	product_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	product_root.add_child(product_row)
	
	var make_island_style = func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb_island = StyleBoxFlat.new()
		sb_island.bg_color = bg
		sb_island.border_color = border
		sb_island.set_border_width_all(2)
		sb_island.corner_radius_top_left = 14
		sb_island.corner_radius_top_right = 14
		sb_island.corner_radius_bottom_left = 14
		sb_island.corner_radius_bottom_right = 14
		return sb_island
	
	# Two-column layout: left = player stats, right = shop items
	var left_col = PanelContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.0
	left_col.custom_minimum_size = Vector2(220, 0)
	left_col.add_theme_stylebox_override("panel", make_island_style.call(Color(0.10, 0.12, 0.16, 0.95), Color(0.30, 0.40, 0.55)))
	product_row.add_child(left_col)
	
	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 10)
	left_margin.add_theme_constant_override("margin_right", 10)
	left_margin.add_theme_constant_override("margin_top", 10)
	left_margin.add_theme_constant_override("margin_bottom", 10)
	left_col.add_child(left_margin)
	
	var stat_root = VBoxContainer.new()
	stat_root.add_theme_constant_override("separation", 8)
	left_margin.add_child(stat_root)
	
	var stat_title = Label.new()
	stat_title.text = ("角色属性" if Loc.current_lang == "zh" else "Character Stats")
	stat_title.add_theme_font_size_override("font_size", 16)
	stat_title.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	stat_root.add_child(stat_title)
	
	var stat_attack_lbl = Label.new()
	var stat_def_lbl = Label.new()
	var stat_hp_lbl = Label.new()
	var stat_lvl_lbl = Label.new()
	var stat_skill_lvl_lbl = Label.new()
	var stat_unlocked_lbl = Label.new()
	var stat_list = [stat_attack_lbl, stat_def_lbl, stat_hp_lbl, stat_lvl_lbl, stat_skill_lvl_lbl, stat_unlocked_lbl]
	for l in stat_list:
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
		stat_root.add_child(l)
	
	var right_col = PanelContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 2.0
	right_col.add_theme_stylebox_override("panel", make_island_style.call(Color(0.11, 0.10, 0.15, 0.95), Color(0.52, 0.40, 0.22)))
	product_row.add_child(right_col)
	
	var right_margin = MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 10)
	right_margin.add_theme_constant_override("margin_right", 10)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_col.add_child(right_margin)
	
	var shop_root = VBoxContainer.new()
	shop_root.add_theme_constant_override("separation", 8)
	shop_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(shop_root)
	
	var shop_title = Label.new()
	shop_title.text = ("商店页面" if Loc.current_lang == "zh" else "Shop")
	shop_title.add_theme_font_size_override("font_size", 16)
	shop_title.add_theme_color_override("font_color", Color(1.0, 0.87, 0.55))
	shop_root.add_child(shop_title)
	
	var offers_grid = HBoxContainer.new()
	offers_grid.add_theme_constant_override("separation", 10)
	offers_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shop_root.add_child(offers_grid)
	
	# Shop cards: 2 columns x 3 rows.
	var shop_columns: Array = []
	for i in range(2):
		var col = VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offers_grid.add_child(col)
		shop_columns.append(col)
	
	var card_height = clampf((panel_size.y - 340.0) / 3.0, 56.0, 104.0)
	var card_desc_height = max(18.0, card_height - 70.0)
	
	# Right-side description panel removed by request.
	# Keep a no-op binder so existing product creation code stays simple.
	var bind_detail = func(_ctrl: Control, _t: String, _d: String):
		pass

	var rarity_color = func(rarity: String) -> Color:
		match rarity:
			"rare": return Color(1.0, 0.72, 0.28)
			"uncommon": return Color(0.35, 0.78, 1.0)
			_:
				return Color(0.72, 0.72, 0.72)
	
	var rarity_label = func(rarity: String) -> String:
		if Loc.current_lang == "zh":
			match rarity:
				"rare": return "稀有"
				"uncommon": return "非凡"
				_:
					return "普通"
		match rarity:
			"rare": return "Rare"
			"uncommon": return "Uncommon"
			_:
				return "Common"
	
	var rarity_mul = func(rarity: String) -> float:
		match rarity:
			"rare": return 1.7
			"uncommon": return 1.3
			_:
				return 1.0
	

	var offer_buttons: Array = []
	var offer_cards: Array = []
	var reroll_cost: int = 50
	var reroll_count: int = 0
	var reroll_max: int = 1
	
	var refresh_shop_state: Callable
	refresh_shop_state = func():
		gold_lbl.text = (("金币: %d" if Loc.current_lang == "zh" else "Gold: %d") % GameState.player_gold)
		reroll_btn.text = (("刷新商品 %d/%d (%dG)" % [reroll_count, reroll_max, reroll_cost]) if Loc.current_lang == "zh" else ("Refresh %d/%d (%dG)" % [reroll_count, reroll_max, reroll_cost]))
		reroll_btn.disabled = GameState.player_gold < reroll_cost or reroll_count >= reroll_max
		
		# Left-column character stats
		var atk_now = int((3.0 + float(bonus_attack_points) + float(current_dice_bonus) / 4.0) * _get_damage_multiplier())
		stat_attack_lbl.text = (("攻击: %d（成长+%d）" % [atk_now, bonus_attack_points]) if Loc.current_lang == "zh" else ("Attack: %d (growth +%d)" % [atk_now, bonus_attack_points]))
		stat_def_lbl.text = (("防御(护甲): %d（成长+%d）" % [GameState.player_armor, bonus_armor_points]) if Loc.current_lang == "zh" else ("Defense (Armor): %d (growth +%d)" % [GameState.player_armor, bonus_armor_points]))
		stat_hp_lbl.text = (("血量: %d/%d" % [GameState.player_hp, GameState.player_max_hp]) if Loc.current_lang == "zh" else ("HP: %d/%d" % [GameState.player_hp, GameState.player_max_hp]))
		stat_lvl_lbl.text = (("当前波次: %d" % current_wave) if Loc.current_lang == "zh" else ("Current Wave: %d" % current_wave))
		stat_skill_lvl_lbl.text = (("普通攻击等级: Lv%d（%d目标）" % [auto_attack_targets, auto_attack_targets]) if Loc.current_lang == "zh" else ("Auto Attack Level: Lv%d (%d targets)" % [auto_attack_targets, auto_attack_targets]))
		stat_unlocked_lbl.text = (("已解锁技能数: %d" % max(0, unlocked_attacks.size() - 1)) if Loc.current_lang == "zh" else ("Unlocked Skills: %d" % max(0, unlocked_attacks.size() - 1)))
		
		for it in offer_buttons:
			var b = it["btn"] as Button
			if not is_instance_valid(b):
				continue
			var cost = int(it["cost"])
			if it.has("cost_fn"):
				var fn = it["cost_fn"] as Callable
				if fn.is_valid():
					cost = int(fn.call())
			if it.has("cost_lbl"):
				var c_lbl = it["cost_lbl"] as Label
				if is_instance_valid(c_lbl):
					c_lbl.text = "%dG" % cost
			if b.disabled:
				continue
			b.modulate = Color(1, 1, 1, 1) if GameState.player_gold >= cost else Color(0.62, 0.56, 0.56, 1)
	
	var clear_cards = func():
		for c in offer_cards:
			if is_instance_valid(c):
				c.queue_free()
		offer_cards.clear()
		offer_buttons.clear()
	
	var clear_rare_cards = func():
		var keep_cards: Array = []
		var keep_card_ids: Dictionary = {}
		for c in offer_cards:
			if not is_instance_valid(c):
				continue
			var is_fixed = bool(c.get_meta("is_fixed_offer")) if c.has_meta("is_fixed_offer") else false
			var row = int(c.get_meta("shop_row")) if c.has_meta("shop_row") else 0
			var keep = is_fixed
			if not keep and row == 3 and c.has_meta("buy_btn"):
				var bb = c.get_meta("buy_btn") as Button
				if is_instance_valid(bb) and bb.disabled:
					keep = true
			if keep:
				keep_cards.append(c)
				keep_card_ids[c.get_instance_id()] = true
			else:
				c.queue_free()
		
		var keep_buttons: Array = []
		for it in offer_buttons:
			var card_ref = it.get("card") as Control
			if is_instance_valid(card_ref) and keep_card_ids.has(card_ref.get_instance_id()):
				keep_buttons.append(it)
		offer_cards = keep_cards
		offer_buttons = keep_buttons
	
	var make_offer_card: Callable
	make_offer_card = func(entry: Dictionary):
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(0, card_height)
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.13, 0.17, 0.96)
		sb.border_color = rarity_color.call(str(entry.get("rarity", "common"))) if entry.has("rarity") else Color(0.55, 0.55, 0.55)
		sb.set_border_width_all(2)
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		card.add_theme_stylebox_override("panel", sb)
		
		var m = MarginContainer.new()
		m.add_theme_constant_override("margin_left", 8)
		m.add_theme_constant_override("margin_right", 8)
		m.add_theme_constant_override("margin_top", 6)
		m.add_theme_constant_override("margin_bottom", 6)
		card.add_child(m)
		
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		m.add_child(vb)
		
		var top = HBoxContainer.new()
		vb.add_child(top)
		
		var name_lbl = Label.new()
		name_lbl.text = str(entry.get("title", "Item"))
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_lbl.clip_text = true
		name_lbl.max_lines_visible = 1
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top.add_child(name_lbl)
		
		if entry.has("rarity"):
			var rarity_lbl = Label.new()
			rarity_lbl.text = "[%s]" % rarity_label.call(str(entry.get("rarity", "common")))
			rarity_lbl.add_theme_font_size_override("font_size", 11)
			rarity_lbl.add_theme_color_override("font_color", rarity_color.call(str(entry.get("rarity", "common"))))
			top.add_child(rarity_lbl)
		
		var desc_lbl = Label.new()
		desc_lbl.text = str(entry.get("desc", ""))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.78, 0.84, 0.94))
		desc_lbl.custom_minimum_size = Vector2(0, card_desc_height)
		desc_lbl.max_lines_visible = 2
		desc_lbl.clip_text = true
		desc_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		vb.add_child(desc_lbl)
		
		var bottom = HBoxContainer.new()
		vb.add_child(bottom)
		
		var static_cost: int = int(entry.get("cost", 0))
		var kind = str(entry.get("kind", ""))
		var get_cost = func() -> int:
			match kind:
				"heal":
					return _shop_heal_cost()
				"upgrade_attack":
					return _shop_upgrade_attack_cost()
				"attack_point":
					return _shop_attack_point_cost()
				"armor_point":
					return _shop_armor_point_cost()
				_:
					return static_cost
		
		var cost_lbl = Label.new()
		cost_lbl.text = "%dG" % get_cost.call()
		cost_lbl.add_theme_font_size_override("font_size", 13)
		cost_lbl.add_theme_color_override("font_color", Color(1, 0.84, 0.2))
		cost_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(cost_lbl)
		
		var buy_btn = Button.new()
		buy_btn.text = ("购买" if Loc.current_lang == "zh" else "Buy")
		buy_btn.custom_minimum_size = Vector2(68, 28)
		buy_btn.add_theme_font_size_override("font_size", 12)
		bottom.add_child(buy_btn)
		if bool(entry.get("disabled", false)):
			buy_btn.disabled = true
			buy_btn.text = str(entry.get("disabled_text", ("已满级" if Loc.current_lang == "zh" else "MAX")))
			card.modulate = Color(0.82, 0.82, 0.82, 0.95)
		
		buy_btn.pressed.connect(func():
			if buy_btn.disabled:
				return
			var pay_cost: int = get_cost.call()
			if GameState.player_gold < pay_cost:
				return
			if kind == "heal" and shop_heal_bought_this_shop:
				add_log("[color=gray]本回合已购买恢复[/color]")
				return
			if kind == "upgrade_attack" and shop_upgrade_bought_this_shop:
				add_log("[color=gray]本回合已购买升级攻击[/color]")
				return
			if kind == "attack_point" and shop_attack_point_bought_this_shop:
				add_log("[color=gray]本回合已购买攻击点[/color]")
				return
			if kind == "armor_point" and shop_armor_point_bought_this_shop:
				add_log("[color=gray]本回合已购买护甲点[/color]")
				return
			if kind == "upgrade_attack" and auto_attack_targets >= 5:
				add_log("[color=gray]攻击已满级 Lv5[/color]")
				return
			if kind == "attack":
				var atk_id_chk = str(entry.get("id", ""))
				if attack_levels.get(atk_id_chk, 0) >= 3:
					add_log("[color=gray]技能已满级 Lv3[/color]")
					return
			
			GameState.player_gold -= pay_cost
			match kind:
				"card":
					GameState.add_card_to_deck(str(entry.get("id", "")))
					SFX.play("coin")
				"attack":
					var atk_id = str(entry.get("id", ""))
					if not unlocked_attacks.has(atk_id):
						unlocked_attacks.append(atk_id)
						attack_levels[atk_id] = 1
					else:
						attack_levels[atk_id] = min(attack_levels.get(atk_id, 1) + 1, 3)
					SFX.play("powerup")
				"upgrade_attack":
					auto_attack_targets = min(auto_attack_targets + 1, 5)
					shop_upgrade_buy_count += 1
					shop_upgrade_bought_this_shop = true
					add_log("[color=cyan]⬆ 攻击升级至 Lv%d，同时攻击 %d 个目标[/color]" % [auto_attack_targets, auto_attack_targets])
					SFX.play("powerup")
				"attack_point":
					bonus_attack_points += 1
					shop_attack_point_buy_count += 1
					shop_attack_point_bought_this_shop = true
					add_log("[color=orange]⚔ 攻击点 +1（当前 +%d）[/color]" % bonus_attack_points)
					SFX.play("powerup")
				"armor_point":
					bonus_armor_points += 2
					shop_armor_point_buy_count += 1
					shop_armor_point_bought_this_shop = true
					GameState.add_armor(2)
					add_log("[color=deepskyblue]🛡 护甲点 +2（当前 +%d）[/color]" % bonus_armor_points)
					SFX.play("powerup")
				"heal":
					shop_heal_buy_count += 1
					shop_heal_bought_this_shop = true
					GameState.heal(GameState.player_max_hp * 3 / 10)
					if is_instance_valid(player):
						player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
					SFX.play("heal")
			
			var fixed_once = kind in ["heal", "upgrade_attack", "attack_point", "armor_point"]
			if fixed_once:
				buy_btn.disabled = true
				buy_btn.text = ("已满级" if kind == "upgrade_attack" and auto_attack_targets >= 5 else "已购✓") if Loc.current_lang == "zh" else ("MAX" if kind == "upgrade_attack" and auto_attack_targets >= 5 else "Bought✓")
				card.modulate = Color(0.82, 0.82, 0.82, 0.95)
			elif kind == "attack":
				buy_btn.disabled = true
				buy_btn.text = ("已购✓" if Loc.current_lang == "zh" else "Bought✓")
				card.modulate = Color(0.82, 0.82, 0.82, 0.95)
			refresh_shop_state.call()
		)
		
		card.set_meta("shop_row", int(entry.get("shop_row", 0)))
		card.set_meta("is_fixed_offer", bool(entry.get("fixed", false)))
		card.set_meta("item_id", str(entry.get("id", "")))
		card.set_meta("item_kind", kind)
		card.set_meta("buy_btn", buy_btn)
		offer_buttons.append({"btn": buy_btn, "cost": static_cost, "cost_fn": get_cost, "cost_lbl": cost_lbl, "card": card})
		bind_detail.call(card, str(entry.get("title", "")), str(entry.get("detail", entry.get("desc", ""))))
		var col_idx: int = int(entry.get("col", 0))
		col_idx = clampi(col_idx, 0, shop_columns.size() - 1)
		var target_col = shop_columns[col_idx] as VBoxContainer
		if target_col:
			target_col.add_child(card)
		else:
			product_row.add_child(card)
		offer_cards.append(card)
	
	var attack_pool = [
		{"id":"orbit_blades", "name_zh":"旋转刀刃", "name_en":"Orbit Blades", "cost":20, "desc_zh":"召唤环绕飞刃持续切割附近敌人。", "desc_en":"Summons orbiting blades that repeatedly cut nearby enemies."},
		{"id":"chain_lightning_passive", "name_zh":"连锁闪电", "name_en":"Chain Lightning", "cost":25, "desc_zh":"周期性释放闪电，自动跳跃打击多个目标。", "desc_en":"Periodically casts lightning that chains across multiple enemies."},
		{"id":"flame_tornado", "name_zh":"火焰旋风", "name_en":"Flame Tornado", "cost":30, "desc_zh":"新星形火焰脉冲，对范围敌人施加持续灼烧。", "desc_en":"Nova-shaped flame pulse that applies sustained burn to enemies."},
		{"id":"ice_nova", "name_zh":"冰霜新星", "name_en":"Ice Nova", "cost":25, "desc_zh":"无伤害控制：Lv1减速，Lv2定身1秒，Lv3定身3秒。", "desc_en":"No-damage control: Lv1 slow, Lv2 root 1s, Lv3 root 3s."},
		{"id":"poison_cloud", "name_zh":"毒雾", "name_en":"Poison Cloud", "cost":20, "desc_zh":"新星形毒雾脉冲，对范围敌人施加持续中毒。", "desc_en":"Nova-shaped toxic pulse that applies sustained poison to enemies."},
		{"id":"holy_cross", "name_zh":"圣光十字", "name_en":"Holy Cross", "cost":25, "desc_zh":"向多个方向发射穿透弹幕。", "desc_en":"Fires piercing projectiles in multiple directions."},
		{"id":"meteor_rain", "name_zh":"陨石雨", "name_en":"Meteor Rain", "cost":35, "desc_zh":"召唤多发陨石，对大范围造成高爆发伤害。", "desc_en":"Calls down multiple meteors for high burst AoE damage."},
		{"id":"spirit_sword", "name_zh":"灵魂飞剑", "name_en":"Spirit Sword", "cost":30, "desc_zh":"释放追踪飞剑；Lv1不弹射，Lv2弹1次，Lv3+弹3次。", "desc_en":"Summons homing spirit swords; Lv1 no ricochet, Lv2 one bounce, Lv3+ three bounces."},
		{"id":"earthquake", "name_zh":"地震", "name_en":"Earthquake", "cost":30, "desc_zh":"低伤害地震波并击退；Lv1/2/3范围递增，Lv3先击退后眩晕。", "desc_en":"Lower-damage quake knockback; range grows at Lv1/2/3, Lv3 knocks back first then stuns."},
		{"id":"vampiric_aura", "name_zh":"吸血光环", "name_en":"Vampiric Aura", "cost":25, "desc_zh":"持续吸取附近敌人生命并为你恢复血量。", "desc_en":"Drains nearby enemies over time and heals you."},
	]
	
	var make_attack_entry = func(atk: Dictionary, target_rarity: String, col: int, shop_row: int = 3):
		var atk_id = str(atk["id"])
		var base_cost = int(atk["cost"])
		var lvl = attack_levels.get(atk_id, 0)
		var target_lvl = min(lvl + 1, 3)
		var price_mul = 1.7
		if target_lvl == 2:
			price_mul = 2.4
		elif target_lvl >= 3:
			price_mul = 3.2
		var final_cost = int(round(base_cost * price_mul))
		
		var name = str(atk["name_zh"]) if Loc.current_lang == "zh" else str(atk["name_en"])
		if lvl <= 0:
			name = "%s Lv1" % name
		elif lvl < 3:
			name = "%s Lv%d→%d" % [name, lvl, lvl + 1]
		else:
			name = "%s Lv3(MAX)" % name
		
		var detail_zh = "%s\n价格：Lv1 %.1fx / Lv2 %.1fx / Lv3 %.1fx" % [str(atk["desc_zh"]), 1.7, 2.4, 3.2]
		var detail_en = "%s\nPrice: Lv1 x%.1f / Lv2 x%.1f / Lv3 x%.1f" % [str(atk["desc_en"]), 1.7, 2.4, 3.2]
		make_offer_card.call({
			"kind": "attack",
			"id": atk_id,
			"title": name,
			"desc": str(atk["desc_zh"]) if Loc.current_lang == "zh" else str(atk["desc_en"]),
			"detail": detail_zh if Loc.current_lang == "zh" else detail_en,
			"cost": final_cost,
			"rarity": target_rarity,
			"col": col,
			"shop_row": shop_row,
			"disabled": lvl >= 3,
		})
	
	var build_rare_offers: Callable
	build_rare_offers = func():
		clear_rare_cards.call()
		var attack_map: Dictionary = {}
		for atk in attack_pool:
			attack_map[str(atk["id"])] = atk
		
		var row3_pool_ids = [
			"orbit_blades", "chain_lightning_passive", "flame_tornado", "ice_nova", "poison_cloud",
			"holy_cross", "meteor_rain", "spirit_sword", "earthquake", "vampiric_aura"
		]
		var selectable_ids: Array = []
		for id in row3_pool_ids:
			if attack_levels.get(id, 0) < 3:
				selectable_ids.append(id)
		if selectable_ids.is_empty():
			selectable_ids = row3_pool_ids.duplicate()
		selectable_ids.shuffle()
		
		var used_ids: Dictionary = {}
		var occupied_cols: Dictionary = {}
		for c in offer_cards:
			if not is_instance_valid(c):
				continue
			var row = int(c.get_meta("shop_row")) if c.has_meta("shop_row") else 0
			if row != 3:
				continue
			var col_idx_exist = c.get_parent().get_index() if is_instance_valid(c.get_parent()) else -1
			if col_idx_exist >= 0:
				occupied_cols[col_idx_exist] = true
			if c.has_meta("item_id"):
				used_ids[str(c.get_meta("item_id"))] = true
		
		for col in range(2):
			if occupied_cols.has(col):
				continue
			var pick_id = ""
			for id in selectable_ids:
				if not used_ids.has(id):
					pick_id = id
					used_ids[id] = true
					break
			# Fallback: if all choices are already used by kept purchased items,
			# allow duplicate display instead of leaving an empty rare slot.
			if pick_id == "" and not selectable_ids.is_empty():
				pick_id = str(selectable_ids[randi() % selectable_ids.size()])
			if pick_id != "" and attack_map.has(pick_id):
				make_attack_entry.call(attack_map[pick_id], "rare", col, 3)
		
		refresh_shop_state.call()
	
	var build_offers: Callable
	build_offers = func():
		clear_cards.call()
		
		# Row1 fixed slots (common)
		make_offer_card.call({
			"kind": "heal",
			"title": ("恢复30%生命" if Loc.current_lang == "zh" else "Heal 30% HP"),
			"desc": ("立即恢复最大生命值的 30%。" if Loc.current_lang == "zh" else "Instantly restore 30% max HP."),
			"detail": ("立即恢复最大生命值的 30%，适合为下一波保命。" if Loc.current_lang == "zh" else "Instantly restores 30% max HP to survive upcoming waves."),
			"cost": _shop_heal_cost(),
			"col": 0,
			"shop_row": 1,
			"fixed": true,
			"disabled": shop_heal_bought_this_shop,
			"disabled_text": ("已购✓" if Loc.current_lang == "zh" else "Bought✓"),
		})
		if auto_attack_targets < 5:
			make_offer_card.call({
				"kind": "upgrade_attack",
				"title": (("升级攻击 (Lv%d→%d)" % [auto_attack_targets, auto_attack_targets + 1]) if Loc.current_lang == "zh" else ("Upgrade Attack (Lv%d→%d)" % [auto_attack_targets, auto_attack_targets + 1])),
				"desc": (("提升普通攻击目标数 +1（当前 %d 个）。" % auto_attack_targets) if Loc.current_lang == "zh" else ("Increase auto-attack targets by 1 (current: %d)." % auto_attack_targets)),
				"detail": (("每次普通攻击可同时命中更多敌人。当前 Lv%d，升级后 Lv%d。上限 Lv5。" % [auto_attack_targets, auto_attack_targets + 1]) if Loc.current_lang == "zh" else ("Auto-attack hits more enemies simultaneously. Current Lv%d, next Lv%d. Max Lv5." % [auto_attack_targets, auto_attack_targets + 1])),
				"cost": _shop_upgrade_attack_cost(),
				"col": 1,
				"shop_row": 1,
				"fixed": true,
				"disabled": shop_upgrade_bought_this_shop,
				"disabled_text": ("已购✓" if Loc.current_lang == "zh" else "Bought✓"),
			})
		else:
			make_offer_card.call({
				"kind": "upgrade_attack",
				"title": ("升级攻击 (MAX)" if Loc.current_lang == "zh" else "Upgrade Attack (MAX)"),
				"desc": ("已达到上限（Lv5）。" if Loc.current_lang == "zh" else "Reached cap (Lv5)."),
				"detail": ("升级攻击已达到最高等级，无法继续购买。" if Loc.current_lang == "zh" else "Upgrade attack reached max level and cannot be purchased further."),
				"cost": _shop_upgrade_attack_cost(),
				"col": 1,
				"shop_row": 1,
				"fixed": true,
				"disabled": true,
				"disabled_text": (("已购✓" if shop_upgrade_bought_this_shop else "已满级") if Loc.current_lang == "zh" else ("Bought✓" if shop_upgrade_bought_this_shop else "MAX")),
			})
		
		# Row2 fixed slots (uncommon): attack/armor points, not refreshed
		make_offer_card.call({
			"kind": "attack_point",
			"title": ("攻击点" if Loc.current_lang == "zh" else "Attack Point"),
			"desc": ("永久攻击 +1。" if Loc.current_lang == "zh" else "Permanent +1 attack."),
			"detail": ("提升主角基础攻击点。" if Loc.current_lang == "zh" else "Increase hero base attack point."),
			"cost": _shop_attack_point_cost(),
			"col": 0,
			"shop_row": 2,
			"fixed": true,
			"disabled": shop_attack_point_bought_this_shop,
			"disabled_text": ("已购✓" if Loc.current_lang == "zh" else "Bought✓"),
		})
		make_offer_card.call({
			"kind": "armor_point",
			"title": ("护甲点" if Loc.current_lang == "zh" else "Armor Point"),
			"desc": ("永久护甲 +2。" if Loc.current_lang == "zh" else "Permanent +2 armor."),
			"detail": ("每波开始获得额外护甲，并立即获得 +2 护甲。" if Loc.current_lang == "zh" else "Gain extra armor each wave and instantly +2 armor now."),
			"cost": _shop_armor_point_cost(),
			"col": 1,
			"shop_row": 2,
			"fixed": true,
			"disabled": shop_armor_point_bought_this_shop,
			"disabled_text": ("已购✓" if Loc.current_lang == "zh" else "Bought✓"),
		})
		
		# Row3 rare only (reroll affects this row only)
		build_rare_offers.call()
	
	reroll_btn.pressed.connect(func():
		if GameState.player_gold < reroll_cost or reroll_count >= reroll_max:
			return
		GameState.player_gold -= reroll_cost
		reroll_count += 1
		SFX.play("dice_roll")
		build_rare_offers.call()
	)
	
	# Footer
	var footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	
	var leave_btn = Button.new()
	leave_btn.text = ("跳过购物" if Loc.current_lang == "zh" else "Skip Shop")
	leave_btn.custom_minimum_size = Vector2(110, 36)
	leave_btn.pressed.connect(func():
		overlay.queue_free()
		GameState.combo_count = 0
		GameState.player_energy = GameState.player_max_energy
		_start_wave(current_wave + 1)
	)
	bind_detail.call(leave_btn,
		"跳过购物" if Loc.current_lang == "zh" else "Skip Shop",
		"不花钱，立即进入下一波。" if Loc.current_lang == "zh" else "Enter the next wave immediately without buying anything.")
	footer.add_child(leave_btn)
	
	var continue_btn = Button.new()
	continue_btn.text = ("完成购买，进入下一波" if Loc.current_lang == "zh" else "Start Next Wave")
	continue_btn.custom_minimum_size = Vector2(180, 38)
	continue_btn.add_theme_font_size_override("font_size", 16)
	continue_btn.pressed.connect(func():
		overlay.queue_free()
		GameState.combo_count = 0
		GameState.player_energy = GameState.player_max_energy
		_start_wave(current_wave + 1)
	)
	bind_detail.call(continue_btn,
		"开始下一波" if Loc.current_lang == "zh" else "Start Next Wave",
		"结束当前商店阶段并进入战斗。" if Loc.current_lang == "zh" else "Finish shopping and return to combat.")
	footer.add_child(continue_btn)
	
	build_offers.call()

# === PAUSE MENU ===

func _pause_game():
	if is_paused:
		return
	is_paused = true
	get_tree().paused = true
	
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 20
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_layer)
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(overlay)
	
	# Center panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 340)
	panel.position = Vector2(-160, -170)
	overlay.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = Loc.t("pause_title")
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# Resume
	var resume_btn = Button.new()
	resume_btn.text = Loc.t("pause_resume")
	resume_btn.add_theme_font_size_override("font_size", 18)
	resume_btn.custom_minimum_size = Vector2(220, 44)
	resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_btn.pressed.connect(_resume_game)
	vbox.add_child(resume_btn)
	
	# Settings row (fullscreen / language)
	var settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 6)
	vbox.add_child(settings_box)
	
	var settings_title = Label.new()
	settings_title.text = Loc.t("settings")
	settings_title.add_theme_font_size_override("font_size", 14)
	settings_title.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_box.add_child(settings_title)
	
	# Display mode
	var display_row = HBoxContainer.new()
	display_row.alignment = BoxContainer.ALIGNMENT_CENTER
	display_row.add_theme_constant_override("separation", 8)
	settings_box.add_child(display_row)
	
	var display_lbl = Label.new()
	display_lbl.text = Loc.t("display_mode") + ":"
	display_lbl.add_theme_font_size_override("font_size", 13)
	display_row.add_child(display_lbl)
	
	var fs_btn = Button.new()
	fs_btn.text = Loc.t("fullscreen")
	fs_btn.add_theme_font_size_override("font_size", 12)
	fs_btn.custom_minimum_size = Vector2(80, 28)
	fs_btn.disabled = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	display_row.add_child(fs_btn)
	
	var win_btn = Button.new()
	win_btn.text = Loc.t("windowed")
	win_btn.add_theme_font_size_override("font_size", 12)
	win_btn.custom_minimum_size = Vector2(80, 28)
	win_btn.disabled = DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN
	display_row.add_child(win_btn)
	
	fs_btn.pressed.connect(func():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		fs_btn.disabled = true; win_btn.disabled = false)
	win_btn.pressed.connect(func():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		fs_btn.disabled = false; win_btn.disabled = true)
	
	# Language
	var lang_row = HBoxContainer.new()
	lang_row.alignment = BoxContainer.ALIGNMENT_CENTER
	lang_row.add_theme_constant_override("separation", 8)
	settings_box.add_child(lang_row)
	
	var lang_lbl = Label.new()
	lang_lbl.text = Loc.t("language") + ":"
	lang_lbl.add_theme_font_size_override("font_size", 13)
	lang_row.add_child(lang_lbl)
	
	var zh_btn = Button.new()
	zh_btn.text = "中文"
	zh_btn.add_theme_font_size_override("font_size", 12)
	zh_btn.custom_minimum_size = Vector2(60, 28)
	zh_btn.disabled = Loc.current_lang == "zh"
	lang_row.add_child(zh_btn)
	
	var en_btn = Button.new()
	en_btn.text = "EN"
	en_btn.add_theme_font_size_override("font_size", 12)
	en_btn.custom_minimum_size = Vector2(60, 28)
	en_btn.disabled = Loc.current_lang == "en"
	lang_row.add_child(en_btn)
	
	# Volume slider
	var vol_row = HBoxContainer.new()
	vol_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vol_row.add_theme_constant_override("separation", 8)
	settings_box.add_child(vol_row)
	
	var vol_lbl = Label.new()
	vol_lbl.text = Loc.t("sfx_volume") + ":"
	vol_lbl.add_theme_font_size_override("font_size", 13)
	vol_row.add_child(vol_lbl)
	
	var vol_slider = HSlider.new()
	vol_slider.custom_minimum_size = Vector2(120, 20)
	vol_slider.min_value = 0.0
	vol_slider.max_value = 100.0
	vol_slider.step = 5.0
	vol_slider.value = SFX.sfx_volume * 100.0
	vol_row.add_child(vol_slider)
	
	var vol_val = Label.new()
	vol_val.text = "%d%%" % int(vol_slider.value)
	vol_val.add_theme_font_size_override("font_size", 12)
	vol_val.custom_minimum_size = Vector2(36, 0)
	vol_row.add_child(vol_val)
	
	vol_slider.value_changed.connect(func(val):
		SFX.set_volume(val / 100.0)
		vol_val.text = "%d%%" % int(val)
	)
	
	# BGM volume slider
	var bgm_row = HBoxContainer.new()
	bgm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bgm_row.add_theme_constant_override("separation", 8)
	settings_box.add_child(bgm_row)
	
	var bgm_lbl = Label.new()
	bgm_lbl.text = Loc.t("bgm_volume") + ":"
	bgm_lbl.add_theme_font_size_override("font_size", 13)
	bgm_row.add_child(bgm_lbl)
	
	var bgm_slider = HSlider.new()
	bgm_slider.custom_minimum_size = Vector2(120, 20)
	bgm_slider.min_value = 0.0
	bgm_slider.max_value = 100.0
	bgm_slider.step = 5.0
	bgm_slider.value = SFX.bgm_volume * 100.0
	bgm_row.add_child(bgm_slider)
	
	var bgm_val = Label.new()
	bgm_val.text = "%d%%" % int(bgm_slider.value)
	bgm_val.add_theme_font_size_override("font_size", 12)
	bgm_val.custom_minimum_size = Vector2(36, 0)
	bgm_row.add_child(bgm_val)
	
	bgm_slider.value_changed.connect(func(val):
		SFX.set_bgm_volume(val / 100.0)
		bgm_val.text = "%d%%" % int(val)
	)
	
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	# Restart
	var restart_btn = Button.new()
	restart_btn.text = Loc.t("pause_restart")
	restart_btn.add_theme_font_size_override("font_size", 16)
	restart_btn.custom_minimum_size = Vector2(220, 40)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(func():
		get_tree().paused = false
		GameState.reset_run()
		GameState.run_mode = "survivor"
		get_tree().change_scene_to_file("res://scenes/battle/survivor_arena.tscn"))
	vbox.add_child(restart_btn)
	
	# Quit to menu
	var quit_btn = Button.new()
	quit_btn.text = Loc.t("pause_quit")
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.add_theme_color_override("font_color", Color(0.8, 0.4, 0.35))
	quit_btn.custom_minimum_size = Vector2(220, 40)
	quit_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_btn.pressed.connect(func():
		get_tree().paused = false
		SaveManager.save_meta()
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
	vbox.add_child(quit_btn)
	
	# Now connect language buttons (restart_btn / quit_btn are declared)
	zh_btn.pressed.connect(func():
		Loc.current_lang = "zh"; zh_btn.disabled = true; en_btn.disabled = false
		title.text = Loc.t("pause_title")
		resume_btn.text = Loc.t("pause_resume")
		restart_btn.text = Loc.t("pause_restart")
		quit_btn.text = Loc.t("pause_quit"))
	en_btn.pressed.connect(func():
		Loc.current_lang = "en"; zh_btn.disabled = false; en_btn.disabled = true
		title.text = Loc.t("pause_title")
		resume_btn.text = Loc.t("pause_resume")
		restart_btn.text = Loc.t("pause_restart")
		quit_btn.text = Loc.t("pause_quit"))

func _resume_game():
	if not is_paused:
		return
	is_paused = false
	get_tree().paused = false
	SaveManager.save_meta()  # Persist volume setting
	if _pause_layer and is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null

# === HUD UPDATE ===

func _update_hud():
	if wave_label:
		if is_skill_test_mode:
			wave_label.text = ("技能测试场" if Loc.current_lang == "zh" else "Skill Test Arena")
		else:
			wave_label.text = Loc.tf("wave", [current_wave]) if Loc.has_key("wave") else "Wave %d" % current_wave
	if timer_label:
		if is_skill_test_mode:
			timer_label.text = ("TEST" if Loc.current_lang == "zh" else "TEST")
		else:
			var secs = max(0, int(wave_timer))
			timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	if hp_label:
		var hp_text = "HP: %d/%d" % [GameState.player_hp, GameState.player_max_hp]
		var armor_text = ("护甲" if Loc.current_lang == "zh" else "Armor") + ": %d" % GameState.player_armor
		var gold_text = ("金币" if Loc.current_lang == "zh" else "Gold") + ": %d" % GameState.player_gold
		hp_label.text = "%s  %s  %s" % [hp_text, armor_text, gold_text]
	
	# Keep player HP bar always synchronized with top-left HUD values.
	if is_instance_valid(player) and player.has_method("update_hp_bar"):
		player.update_hp_bar(GameState.player_hp, GameState.player_max_hp)
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
