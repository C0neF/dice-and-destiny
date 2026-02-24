## Battle Manager - Handles turn-based combat with cards and dice
extends Node2D

signal battle_won(rewards: Dictionary)
signal battle_lost()

@onready var enemy_container = $EnemyContainer
@onready var card_hand = $UI/CardHand
@onready var dice_tray = $UI/DiceTray
@onready var hp_bar = $UI/HPBar
@onready var hp_text = $UI/HPText
@onready var hp_label = $UI/HPLabel
@onready var energy_display = $UI/EnergyDisplay
@onready var armor_display = $UI/ArmorDisplay
@onready var end_turn_btn = $UI/EndTurnButton
@onready var battle_log = $UI/BattleLog
@onready var dice_label = $UI/DiceLabel
@onready var card_label = $UI/CardLabel
@onready var floor_label = $UI/FloorLabel

var enemies: Array[Dictionary] = []
var turn: int = 0
var is_player_turn: bool = true
var player_dodge_stacks: int = 0
var player_reflect_ratio: float = 0.0
var boss_phase: int = 1  # Track boss phase for transitions

func _ready():
	var hp_bg_style = StyleBoxFlat.new()
	hp_bg_style.bg_color = Color(0.15, 0.08, 0.08)
	hp_bg_style.set_border_width_all(1)
	hp_bg_style.border_color = Color(0.3, 0.15, 0.15)
	hp_bg_style.set_corner_radius_all(2)
	hp_bg_style.set_content_margin_all(0)
	hp_bar.add_theme_stylebox_override("background", hp_bg_style)
	
	var hp_fill_style = StyleBoxFlat.new()
	hp_fill_style.bg_color = Color(0.75, 0.2, 0.15)
	hp_fill_style.set_corner_radius_all(2)
	hp_fill_style.set_content_margin_all(0)
	hp_bar.add_theme_stylebox_override("fill", hp_fill_style)
	
	end_turn_btn.pressed.connect(_on_end_turn)
	GameState.hp_changed.connect(_update_hp_display)
	GameState.energy_changed.connect(_update_energy_display)
	GameState.armor_changed.connect(_update_armor_display)
	
	_update_ui_texts()
	VFX.fade_in(0.3)
	SFX.play_bgm("battle")

func _update_ui_texts():
	hp_label.text = Loc.t("hp")
	end_turn_btn.text = Loc.t("end_turn")
	dice_label.text = Loc.t("dice_pool")
	card_label.text = Loc.t("hand")
	floor_label.text = Loc.tf("floor", [GameState.current_floor, GameState.max_floors])

func _input(event):
	if event.is_action_pressed("end_turn") and is_player_turn:
		_on_end_turn()

func _card_name(card_def) -> String:
	return Loc.t("card_" + card_def.id)

func _enemy_name(enemy_def) -> String:
	# Convert enemy type to key: find the key in GameData.ENEMIES
	for key in GameData.ENEMIES:
		if GameData.ENEMIES[key] == enemy_def:
			return Loc.t("enemy_" + key)
	return enemy_def.name

func _player_strength() -> int:
	var total = 0
	for effect in GameState.player_effects:
		if effect is Dictionary and effect.get("type", "") == "strength":
			total += int(effect.get("value", 0))
	return total

func _apply_player_attack_modifiers(amount: int) -> int:
	return max(0, amount + _player_strength())

func start_battle(enemy_ids: Array[String]):
	enemies.clear()
	for child in enemy_container.get_children():
		child.queue_free()
	player_dodge_stacks = 0
	player_reflect_ratio = 0.0
	GameState.player_effects.clear()
	
	for i in range(enemy_ids.size()):
		var enemy_def = GameData.ENEMIES.get(enemy_ids[i])
		if not enemy_def:
			continue
		
		var sprite = Sprite2D.new()
		sprite.texture = load(enemy_def.texture_path)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(200 + i * 120, 100)
		if enemy_def.is_boss:
			sprite.scale = Vector2(4, 4)
		else:
			sprite.scale = Vector2(3, 3)
		enemy_container.add_child(sprite)
		
		var ehp_bg = ColorRect.new()
		ehp_bg.size = Vector2(40, 4)
		ehp_bg.position = Vector2(-20, -30)
		ehp_bg.color = Color(0.2, 0.1, 0.1)
		sprite.add_child(ehp_bg)
		var ehp_fill = ColorRect.new()
		ehp_fill.size = Vector2(40, 4)
		ehp_fill.position = Vector2(-20, -30)
		ehp_fill.color = Color(0.8, 0.2, 0.2)
		ehp_fill.name = "HPFill"
		sprite.add_child(ehp_fill)
		
		var name_lbl = Label.new()
		name_lbl.text = _enemy_name(enemy_def)
		name_lbl.position = Vector2(-20, -42)
		name_lbl.add_theme_font_size_override("font_size", 8)
		sprite.add_child(name_lbl)
		
		enemies.append({
			"def": enemy_def,
			"hp": enemy_def.max_hp,
			"max_hp": enemy_def.max_hp,
			"armor": 0,
			"frozen": 0,
			"poisoned": 0,
			"sprite": sprite
		})
	
	turn = 0
	start_player_turn()

func start_player_turn():
	is_player_turn = true
	turn += 1
	GameState.start_turn()
	update_hand_display()
	update_dice_display()
	_update_hp_display(GameState.player_hp, GameState.player_max_hp)
	_update_energy_display(GameState.player_energy, GameState.player_max_energy)
	_update_intent_display()
	end_turn_btn.disabled = false
	add_log(Loc.tf("battle_log_turn", [turn]))

func update_hand_display():
	for child in card_hand.get_children():
		child.queue_free()
	
	for i in range(GameState.hand.size()):
		var card_id = GameState.hand[i]
		var card_def = GameData.CARDS.get(card_id)
		if not card_def:
			continue
		var card_node = _create_card_ui(card_def, i)
		card_hand.add_child(card_node)

func _create_card_ui(card_def, index: int) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(80, 120)
	panel.add_theme_stylebox_override("panel", ThemeGen.get_card_style(card_def.type))
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	
	var cost_row = HBoxContainer.new()
	vbox.add_child(cost_row)
	var cost_lbl = Label.new()
	cost_lbl.text = "%d" % card_def.energy_cost
	cost_lbl.add_theme_font_size_override("font_size", 11)
	cost_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	cost_row.add_child(cost_lbl)
	if card_def.dice_slots > 0:
		var dice_lbl = Label.new()
		dice_lbl.text = "  x%d" % card_def.dice_slots
		dice_lbl.add_theme_font_size_override("font_size", 9)
		dice_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
		cost_row.add_child(dice_lbl)
	
	var tex_rect = TextureRect.new()
	tex_rect.texture = load(card_def.texture_path)
	tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.custom_minimum_size = Vector2(48, 64)
	vbox.add_child(tex_rect)
	
	var name_lbl = Label.new()
	name_lbl.text = Loc.t("card_" + card_def.id)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	panel.mouse_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(panel, "scale", Vector2(1.08, 1.08), 0.1)
		panel.z_index = 10
	)
	panel.mouse_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1)
		panel.z_index = 0
	)
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_card_clicked(index)
	)
	return panel

func update_dice_display():
	for child in dice_tray.get_children():
		child.queue_free()
	for i in range(GameState.active_dice.size()):
		var dice = GameState.active_dice[i]
		dice_tray.add_child(_create_dice_ui(dice, i))

func _create_dice_ui(dice: Dictionary, _index: int) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(40, 40)
	panel.add_theme_stylebox_override("panel", ThemeGen.get_dice_style(dice.type))
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	var tex = TextureRect.new()
	var tex_path = "res://assets/sprites/dice/dice_%d.png" % dice.value
	if dice.type != "normal":
		tex_path = "res://assets/sprites/dice/dice_%s.png" % dice.type
	tex.texture = load(tex_path)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(24, 24)
	vbox.add_child(tex)
	var val_lbl = Label.new()
	val_lbl.text = str(dice.value)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.7))
	vbox.add_child(val_lbl)
	return panel

func _on_card_clicked(index: int):
	if not is_player_turn:
		return
	var result = GameState.play_card(index)
	if not result.success:
		if result.get("reason") == "not_enough_energy":
			add_log(Loc.t("not_enough_energy"))
		return
	
	SFX.play("card_play")
	
	# Show combo if > 1
	if result.combo_bonus > 0:
		add_log(Loc.tf("combo_bonus", [GameState.combo_count, result.combo_bonus]))
	
	_apply_card_effect(result.card_def, result.value, result.dice_bonus, result.get("card_id", ""))
	update_hand_display()
	update_dice_display()
	update_enemy_display()
	_update_intent_display()
	_check_battle_end()

func _apply_card_effect(card_def, value: int, dice_bonus: int, card_id: String = ""):
	var actual_value = GameState.apply_damage_with_relics(value) if card_def.type == GameData.CardType.ATTACK else value
	
	match card_def.type:
		GameData.CardType.ATTACK:
			actual_value = _apply_player_attack_modifiers(actual_value)
			if enemies.size() > 0:
				var target = _get_first_alive_enemy()
				if target >= 0:
					if card_id == "flurry":
						# Hit 3 times for value/3 each
						var per_hit = max(1, actual_value / 3)
						for _hit in range(3):
							_deal_damage_to_enemy(target, per_hit)
							target = _get_first_alive_enemy()
							if target < 0:
								break
						add_log(Loc.tf("deals_damage", [_card_name(card_def), actual_value, dice_bonus]))
					elif card_id == "vampiric_strike":
						var dmg = _deal_damage_to_enemy(target, actual_value)
						GameState.heal(dmg / 2)
						add_log(Loc.tf("deals_damage", [_card_name(card_def), dmg, dice_bonus]))
					else:
						var dmg = _deal_damage_to_enemy(target, actual_value)
						add_log(Loc.tf("deals_damage", [_card_name(card_def), dmg, dice_bonus]))
					if card_id == "poison_strike":
						enemies[target].poisoned += 2 if target >= 0 else 0
						add_log(Loc.t("poison_applied"))
		
		GameData.CardType.DEFEND:
			if card_id == "dodge_roll":
				player_dodge_stacks += 1
				GameState.draw_single_card()
				update_hand_display()
				add_log(Loc.t("dodge_ready"))
			else:
				GameState.add_armor(value)
				SFX.play("shield")
				add_log(Loc.tf("gains_armor", [_card_name(card_def), value, dice_bonus]))
			if card_id == "mirror_shield":
				player_reflect_ratio = 0.5
				add_log(Loc.t("reflect"))
		
		GameData.CardType.MAGIC:
			if card_id == "fireball":
				for i in range(enemies.size()):
					if enemies[i].hp > 0:
						_deal_damage_to_enemy(i, actual_value)
				add_log(Loc.tf("fireball_hits", [actual_value, dice_bonus]))
			elif card_id == "ice_shard":
				var target = _get_first_alive_enemy()
				if target >= 0:
					_deal_damage_to_enemy(target, actual_value)
					enemies[target].frozen += 1
					add_log(Loc.tf("ice_shard_hits", [actual_value, dice_bonus]))
			elif card_id == "chain_lightning":
				var bonus = GameState.combo_count * 3
				for i in range(enemies.size()):
					if enemies[i].hp > 0:
						_deal_damage_to_enemy(i, actual_value + bonus)
				add_log(Loc.tf("fireball_hits", [actual_value + bonus, dice_bonus]))
			elif card_id == "weaken":
				var target = _get_first_alive_enemy()
				if target >= 0:
					enemies[target]["weak"] = enemies[target].get("weak", 0) + value
					enemies[target]["vulnerable"] = enemies[target].get("vulnerable", 0) + 2
				add_log(Loc.tf("deals_damage", [_card_name(card_def), 0, 0]))
			elif card_id == "inferno":
				for i in range(enemies.size()):
					if enemies[i].hp > 0:
						enemies[i]["burn"] = enemies[i].get("burn", 0) + value
				add_log(Loc.tf("fireball_hits", [value, dice_bonus]))
			elif card_id == "summon_familiar":
				GameState.familiar_active = true
				GameState.familiar_damage = actual_value
				add_log(Loc.tf("deals_damage", [_card_name(card_def), 0, 0]))
			elif card_id == "curse_of_pain":
				var target = _get_first_alive_enemy()
				if target >= 0:
					_deal_damage_to_enemy(target, actual_value)
					enemies[target]["vulnerable"] = enemies[target].get("vulnerable", 0) + 2
				add_log(Loc.tf("deals_damage", [_card_name(card_def), actual_value, dice_bonus]))
			else:
				var target = _get_first_alive_enemy()
				if target >= 0:
					_deal_damage_to_enemy(target, actual_value)
				add_log(Loc.tf("deals_damage", [_card_name(card_def), actual_value, dice_bonus]))
		
		GameData.CardType.HEAL:
			if card_def.id == "regenerate":
				GameState.regen_turns = 3
				GameState.regen_amount = value
				add_log(Loc.tf("regen", [value]))
			else:
				GameState.heal(value)
				SFX.play("heal")
				add_log(Loc.tf("healed", [value, dice_bonus]))
		
		GameData.CardType.DICE_BOOST:
			if card_id == "lucky_roll":
				GameState.reroll_dice()
				for d in GameState.active_dice:
					d.value = min(6, d.value + value)
				SFX.play("dice_roll")
				add_log(Loc.tf("reroll", [value]))
				update_dice_display()
			elif card_id == "loaded_dice":
				if GameState.active_dice.size() > 0:
					GameState.active_dice[0].value = 6
					add_log(Loc.t("loaded"))
					update_dice_display()
			elif card_id == "battle_cry":
				GameState.player_effects.append({"type": "strength", "value": value})
				add_log(Loc.tf("strength_gain", [value]))
			elif card_id == "double_or_nothing":
				if GameState.active_dice.size() > 0 and GameState.active_dice[0].value >= 4:
					# Double next card effect - simplified as +5 armor + draw
					GameState.add_armor(value * 2)
					GameState.draw_single_card()
					update_hand_display()
				add_log(Loc.tf("deals_damage", [_card_name(card_def), value, 0]))

func _deal_damage_to_enemy(index: int, amount: int) -> int:
	var enemy = enemies[index]
	var adjusted_amount = max(0, amount)
	var vulnerable = int(enemy.get("vulnerable", 0))
	if vulnerable > 0:
		adjusted_amount = int(round(adjusted_amount * 1.5))
	var actual = max(0, adjusted_amount - enemy.armor)
	enemy.armor = max(0, enemy.armor - adjusted_amount)
	var was_alive = enemy.hp > 0
	enemy.hp = max(0, enemy.hp - actual)
	var sprite = enemy.sprite
	sprite.modulate = Color(3, 0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	_spawn_damage_number(sprite.global_position + Vector2(0, -40), actual, Color(1, 0.3, 0.2))
	if actual >= 8:
		VFX.screen_shake(actual * 0.5, 6.0)
		SFX.play("hit_crit")
	elif actual > 0:
		SFX.play_varied("hit")
	# Stat tracking
	GameState.stats["damage_dealt"] = GameState.stats.get("damage_dealt", 0) + actual
	if was_alive and enemy.hp <= 0:
		GameState.stats["enemies_killed"] = GameState.stats.get("enemies_killed", 0) + 1
		GameState.stats["total_enemies_killed"] = GameState.stats.get("total_enemies_killed", 0) + 1
	# Boss phase transitions
	if enemy.def.is_boss and enemy.hp > 0:
		_check_boss_phase(enemy)
	return actual

func _apply_reflect(enemy_index: int, damage_taken: int):
	if player_reflect_ratio <= 0.0:
		return
	var ratio = player_reflect_ratio
	player_reflect_ratio = 0.0
	var reflect_damage = int(round(max(0, damage_taken) * ratio))
	if reflect_damage <= 0:
		return
	var reflected = _deal_damage_to_enemy(enemy_index, reflect_damage)
	if reflected > 0:
		add_log(Loc.tf("reflect_hits", [reflected]))

func _check_boss_phase(enemy: Dictionary):
	var hp_pct = float(enemy.hp) / enemy.max_hp
	var new_phase = 1
	if hp_pct <= 0.25:
		new_phase = 3
	elif hp_pct <= 0.6:
		new_phase = 2
	
	if new_phase > boss_phase:
		boss_phase = new_phase
		match new_phase:
			2:
				add_log(Loc.t("boss_phase2"))
				VFX.screen_shake(8.0, 3.0)
				VFX.flash_screen(Color(1, 0.2, 0.0, 0.4), 0.3)
				SFX.play("boss_phase")
				# Boss gains strength + armor in phase 2
				enemy["strength"] = enemy.get("strength", 0) + 5
				enemy.armor += 10
				# Visual: tint red
				enemy.sprite.modulate = Color(1.2, 0.6, 0.6)
				var tw = create_tween()
				tw.tween_property(enemy.sprite, "modulate", Color(1.1, 0.8, 0.8), 1.0)
			3:
				add_log(Loc.t("boss_phase3"))
				VFX.screen_shake(12.0, 2.0)
				VFX.flash_screen(Color(0.8, 0.0, 0.0, 0.6), 0.5)
				SFX.play("boss_phase")
				# Boss massive buff in phase 3
				enemy["strength"] = enemy.get("strength", 0) + 8
				# Poison player
				GameState.poison_stacks += 3
				# Visual: dark aura
				enemy.sprite.modulate = Color(1.5, 0.3, 0.3)
				var tw2 = create_tween().set_loops(20)
				tw2.tween_property(enemy.sprite, "modulate", Color(1.5, 0.3, 0.3), 0.5)
				tw2.tween_property(enemy.sprite, "modulate", Color(1.0, 0.5, 0.5), 0.5)

func _spawn_damage_number(pos: Vector2, value: int, color: Color):
	var label = Label.new()
	label.text = str(value)
	label.position = pos + Vector2(randf_range(-10, 10), 0)
	label.add_theme_font_size_override("font_size", 18 if value >= 10 else 14)
	label.add_theme_color_override("font_color", color)
	label.z_index = 100
	add_child(label)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 40, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tween.chain().tween_callback(label.queue_free)

func _get_first_alive_enemy() -> int:
	for i in range(enemies.size()):
		if enemies[i].hp > 0:
			return i
	return -1

func update_enemy_display():
	for enemy in enemies:
		if enemy.hp <= 0:
			enemy.sprite.modulate = Color(0.3, 0.3, 0.3, 0.5)
		var ehp_fill = enemy.sprite.get_node_or_null("HPFill")
		if ehp_fill:
			ehp_fill.size.x = 40.0 * enemy.hp / enemy.max_hp

func _update_intent_display():
	for enemy in enemies:
		if enemy.hp <= 0:
			continue
		var hp_pct = float(enemy.hp) / enemy.max_hp
		var intent = GameData.get_enemy_intent(enemy.def.type, turn, hp_pct)
		# Update or create intent label
		var intent_lbl = enemy.sprite.get_node_or_null("IntentLabel")
		if not intent_lbl:
			intent_lbl = Label.new()
			intent_lbl.name = "IntentLabel"
			intent_lbl.position = Vector2(-20, 20)
			intent_lbl.add_theme_font_size_override("font_size", 7)
			enemy.sprite.add_child(intent_lbl)
		
		match intent.type:
			GameData.IntentType.ATTACK:
				intent_lbl.text = "⚔ %d" % intent.value
				intent_lbl.add_theme_color_override("font_color", Color(1, 0.3, 0.2))
			GameData.IntentType.DEFEND:
				intent_lbl.text = "🛡"
				intent_lbl.add_theme_color_override("font_color", Color(0.3, 0.5, 0.9))
			GameData.IntentType.BUFF:
				intent_lbl.text = "↑"
				intent_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
			GameData.IntentType.DEBUFF:
				intent_lbl.text = "↓"
				intent_lbl.add_theme_color_override("font_color", Color(0.6, 0.2, 0.8))
			GameData.IntentType.SPECIAL:
				intent_lbl.text = "⚡!"
				intent_lbl.add_theme_color_override("font_color", Color(1, 0.5, 0))

func _on_end_turn():
	if not is_player_turn:
		return
	is_player_turn = false
	end_turn_btn.disabled = true
	GameState.discard_hand()
	update_hand_display()
	await get_tree().create_timer(0.5).timeout
	_enemy_turn()

func _enemy_turn():
	# Familiar attacks first
	if GameState.familiar_active:
		var ftarget = _get_first_alive_enemy()
		if ftarget >= 0:
			_deal_damage_to_enemy(ftarget, GameState.familiar_damage)
			add_log(Loc.tf("familiar_attacks", [GameState.familiar_damage]))
	
	for i in range(enemies.size()):
		var enemy = enemies[i]
		if enemy.hp <= 0:
			continue
		# Burn tick
		var burn = enemy.get("burn", 0)
		if burn > 0:
			enemy.hp = max(0, enemy.hp - burn)
			enemy["burn"] = max(0, burn - 1)
		if enemy.frozen > 0:
			enemy.frozen -= 1
			add_log(Loc.tf("enemy_frozen", [_enemy_name(enemy.def)]))
			continue
		if enemy.poisoned > 0:
			enemy.hp = max(0, enemy.hp - enemy.poisoned)
			enemy.poisoned -= 1
			add_log(Loc.tf("enemy_poison", [_enemy_name(enemy.def), enemy.poisoned + 1]))
		# Intent-based action
		var hp_pct = float(enemy.hp) / enemy.max_hp
		var intent = GameData.get_enemy_intent(enemy.def.type, turn, hp_pct)
		match intent.type:
			GameData.IntentType.ATTACK:
				var atk = intent.value + int(enemy.get("strength", 0)) + randi() % 3
				var weak = enemy.get("weak", 0)
				if weak > 0:
					atk = int(atk * 0.75)
					enemy["weak"] = weak - 1
				var dodged = false
				if player_dodge_stacks > 0:
					player_dodge_stacks -= 1
					add_log(Loc.t("you_dodged"))
					dodged = true
				if not dodged:
					var actual = GameState.take_damage_with_relics(atk)
					add_log(Loc.tf("enemy_attacks", [_enemy_name(enemy.def), actual, max(0, atk - actual)]))
					_apply_reflect(i, actual)
					if actual > 0:
						VFX.flash_screen(Color(1, 0.15, 0.1, 0.25), 0.15)
						VFX.screen_shake(2.0, 8.0)
						SFX.play("player_hurt")
			GameData.IntentType.DEFEND:
				enemy.armor += intent.value
			GameData.IntentType.BUFF:
				enemy["strength"] = enemy.get("strength", 0) + intent.value
				add_log(Loc.tf("enemy_gains_strength", [_enemy_name(enemy.def), intent.value]))
			GameData.IntentType.DEBUFF:
				GameState.poison_stacks += intent.value
			GameData.IntentType.SPECIAL:
				var special_damage = intent.value + int(enemy.get("strength", 0))
				var dodged = false
				if player_dodge_stacks > 0:
					player_dodge_stacks -= 1
					add_log(Loc.t("you_dodged"))
					dodged = true
				if not dodged:
					var actual = GameState.take_damage_with_relics(special_damage)
					add_log(Loc.tf("enemy_attacks", [_enemy_name(enemy.def), actual, 0]))
					_apply_reflect(i, actual)
					if actual > 0:
						VFX.flash_screen(Color(1, 0.1, 0.05, 0.4), 0.2)
						VFX.screen_shake(5.0, 4.0)
		var vulnerable = int(enemy.get("vulnerable", 0))
		if vulnerable > 0:
			enemy["vulnerable"] = vulnerable - 1
		await get_tree().create_timer(0.3).timeout
	
	update_enemy_display()
	
	if GameState.is_dead():
		add_log(Loc.t("you_fell"))
		await get_tree().create_timer(1.0).timeout
		battle_lost.emit()
		return
	
	_check_battle_end()
	if not _all_enemies_dead():
		start_player_turn()

func _all_enemies_dead() -> bool:
	for enemy in enemies:
		if enemy.hp > 0:
			return false
	return true

func _check_battle_end():
	if _all_enemies_dead():
		add_log(Loc.t("victory"))
		var rewards = _generate_rewards()
		await get_tree().create_timer(1.0).timeout
		battle_won.emit(rewards)

func _generate_rewards() -> Dictionary:
	var gold = 0
	var cards: Array[String] = []
	var dice_reward: String = ""
	var relic_choices: Array[String] = []
	var has_boss = false
	var has_elite = false
	for enemy in enemies:
		gold += randi_range(5, 15)
		if enemy.def.is_boss:
			gold += 50
			has_boss = true
		else:
			# Multi-enemy non-boss fights count as elite
			if enemies.size() >= 2:
				has_elite = true
		if randf() < 0.4 and enemy.def.loot_cards.size() > 0:
			cards.append(enemy.def.loot_cards[randi() % enemy.def.loot_cards.size()])
	if randf() < 0.15:
		var dice_types = ["fire", "ice", "poison"]
		dice_reward = dice_types[randi() % dice_types.size()]
	# Boss: guaranteed relic choice (pick 1 of 3)
	if has_boss:
		relic_choices = RelicData.pick_random(3, GameState.relics)
	# Elite: 40% chance for relic choice (pick 1 of 2)
	elif has_elite:
		if randf() < 0.4:
			relic_choices = RelicData.pick_random(2, GameState.relics)
	return {"gold": gold, "cards": cards, "dice": dice_reward, "relic_choices": relic_choices}

func _update_hp_display(hp: int, max_hp: int):
	if hp_bar:
		hp_bar.value = float(hp) / max_hp * 100
	if hp_text:
		hp_text.text = "%d/%d" % [hp, max_hp]
		var pct = float(hp) / max_hp
		if pct > 0.6:
			hp_text.add_theme_color_override("font_color", Color(0.3, 0.8, 0.35))
		elif pct > 0.3:
			hp_text.add_theme_color_override("font_color", Color(1, 0.75, 0.2))
		else:
			hp_text.add_theme_color_override("font_color", Color(0.9, 0.25, 0.2))

func _update_energy_display(energy: int, max_energy: int):
	if energy_display:
		energy_display.text = Loc.tf("energy", [energy, max_energy])

func _update_armor_display(armor: int):
	if armor_display:
		armor_display.text = Loc.tf("armor", [armor])

func add_log(text: String):
	if battle_log:
		battle_log.text += text + "\n"
		await get_tree().process_frame
		var scrollbar = battle_log.get_v_scroll_bar()
		if scrollbar:
			scrollbar.value = scrollbar.max_value
