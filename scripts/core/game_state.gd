## Global game state singleton (autoload)
extends Node

signal hp_changed(new_hp: int, max_hp: int)
signal energy_changed(new_energy: int, max_energy: int)
signal gold_changed(new_gold: int)
signal armor_changed(new_armor: int)
signal deck_changed()
signal floor_changed(floor_num: int)

var player_hp: int = 50
var player_max_hp: int = 50
var player_energy: int = 3
var player_max_energy: int = 3
var player_armor: int = 0
var player_gold: int = 0
var current_floor: int = 1
var max_floors: int = 10

# Run mode: "adventure" or "survivor"
var run_mode: String = "adventure"
# Survivor difficulty: "normal" | "hard"
var survivor_difficulty: String = "normal"

# Deck management
var deck: Array[String] = []  # Card IDs in draw pile
var hand: Array[String] = []  # Cards in hand
var discard: Array[String] = []  # Discard pile
var hand_size: int = 5

# Dice inventory
var dice_pool: Array[String] = []  # Dice IDs available
var active_dice: Array[Dictionary] = []  # {type: String, value: int}

# Status effects
var poison_stacks: int = 0
var freeze_turns: int = 0
var regen_turns: int = 0
var regen_amount: int = 0
var player_effects: Array = []  # Array of StatusEffect.Effect

# Relics
var relics: Array[String] = []  # Relic IDs

# Combo system
var combo_count: int = 0  # Cards played this turn
var cards_played_this_turn: Array[String] = []

# Familiar
var familiar_active: bool = false
var familiar_damage: int = 0

# Energy regen accumulator (for survivor mode)
var energy_regen_acc: float = 0.0

# Card upgrades (card_id -> upgrade_count)
var card_upgrades: Dictionary = {}

# Meta progression (persists between runs)
var meta_unlocked_cards: Array[String] = []
var meta_unlocked_relics: Array[String] = []
var meta_total_runs: int = 0
var meta_best_floor: int = 0

# Map state
var rooms_visited: Array[Vector2i] = []
var current_room: Vector2i = Vector2i.ZERO
var map_seed: int = 0

# Run statistics (for end-of-run summary)
var stats: Dictionary = {}

static func _default_stats() -> Dictionary:
	return {
		"enemies_killed": 0,
		"cards_played": 0,
		"damage_dealt": 0,
		"damage_taken": 0,
		"gold_earned": 0,
		"gold_spent": 0,
		"healed": 0,
		"dice_rolled": 0,
		"rooms_cleared": 0,
		"relics_found": 0,
		"highest_combo": 0,
		"cards_upgraded": 0,
		"total_gold_earned": 0,
		"total_enemies_killed": 0,
		"run_time_sec": 0.0,
	}

var _run_start_time: float = 0.0

func _ready():
	reset_run()

func _process(delta):
	if stats.has("run_time_sec"):
		stats["run_time_sec"] += delta

func reset_run():
	player_hp = 50
	player_max_hp = 50
	player_energy = 3
	player_max_energy = 3
	player_armor = 0
	player_gold = 0
	current_floor = 1
	survivor_difficulty = "normal"
	poison_stacks = 0
	freeze_turns = 0
	regen_turns = 0
	regen_amount = 0
	player_effects.clear()
	relics.clear()
	combo_count = 0
	cards_played_this_turn.clear()
	familiar_active = false
	familiar_damage = 0
	card_upgrades.clear()
	rooms_visited.clear()
	current_room = Vector2i.ZERO
	map_seed = randi()
	meta_total_runs += 1
	stats = _default_stats()
	_run_start_time = Time.get_unix_time_from_system()
	
	# Starting deck
	deck = ["strike", "strike", "strike", "block", "block", "heal", "lucky_roll"]
	hand.clear()
	discard.clear()
	
	# Starting dice
	dice_pool = ["normal", "normal", "normal"]
	active_dice.clear()
	
	deck_changed.emit()

func take_damage(amount: int) -> int:
	var actual = max(0, amount - player_armor)
	player_armor = max(0, player_armor - amount)
	player_hp = max(0, player_hp - actual)
	hp_changed.emit(player_hp, player_max_hp)
	armor_changed.emit(player_armor)
	stats["damage_taken"] = stats.get("damage_taken", 0) + actual
	return actual

func heal(amount: int):
	var before = player_hp
	player_hp = min(player_max_hp, player_hp + amount)
	hp_changed.emit(player_hp, player_max_hp)
	stats["healed"] = stats.get("healed", 0) + (player_hp - before)

func add_armor(amount: int):
	player_armor += amount
	armor_changed.emit(player_armor)

func spend_energy(amount: int) -> bool:
	if player_energy < amount:
		return false
	player_energy -= amount
	energy_changed.emit(player_energy, player_max_energy)
	return true

func start_turn():
	player_energy = player_max_energy
	player_armor = 0
	combo_count = 0
	cards_played_this_turn.clear()
	energy_changed.emit(player_energy, player_max_energy)
	armor_changed.emit(player_armor)
	
	# Relic: Iron Crown - +1 armor at start of each turn
	if relics.has("iron_crown"):
		player_armor += 3
		armor_changed.emit(player_armor)
	
	# Relic: Blood Vial - heal 2 at start of turn
	if relics.has("blood_vial"):
		heal(2)
	
	# Apply status effects
	if poison_stacks > 0:
		player_hp = max(0, player_hp - poison_stacks)
		poison_stacks -= 1
		hp_changed.emit(player_hp, player_max_hp)
	if regen_turns > 0:
		heal(regen_amount)
		regen_turns -= 1
	
	# Draw hand
	var draw_count = hand_size
	# Relic: Crystal Ball - draw 1 extra card
	if relics.has("crystal_ball"):
		draw_count += 1
	draw_hand(draw_count)
	# Roll dice
	roll_all_dice()

func draw_hand(count: int = -1):
	hand.clear()
	var draw_count = count if count > 0 else hand_size
	for i in range(draw_count):
		if deck.is_empty():
			deck = discard.duplicate()
			discard.clear()
			deck.shuffle()
		if not deck.is_empty():
			hand.append(deck.pop_back())
	deck_changed.emit()

func discard_hand():
	for card_id in hand:
		discard.append(card_id)
	hand.clear()
	deck_changed.emit()

func play_card(hand_index: int) -> Dictionary:
	if hand_index < 0 or hand_index >= hand.size():
		return {"success": false}
	
	var card_id = hand[hand_index]
	var card_def = GameData.CARDS.get(card_id)
	if not card_def:
		return {"success": false}
	
	if not spend_energy(card_def.energy_cost):
		return {"success": false, "reason": "not_enough_energy"}
	
	# Calculate card value with dice
	var value = card_def.base_value
	
	# Card upgrades add +2 base value per upgrade
	var upgrades = card_upgrades.get(card_id, 0)
	value += upgrades * 2
	
	var dice_bonus = 0
	var dice_used = min(card_def.dice_slots, active_dice.size())
	for i in range(dice_used):
		dice_bonus += int(active_dice[i].value * card_def.dice_multiplier)
	value += dice_bonus
	
	# Combo bonus: +1 per card already played this turn
	var combo_bonus = combo_count
	# Relic: War Drum - combo bonus doubled
	if relics.has("war_drum"):
		combo_bonus *= 2
	value += combo_bonus
	
	# Relic: Lucky Coin - 20% chance to not consume energy
	if relics.has("lucky_coin") and randf() < 0.2:
		player_energy += card_def.energy_cost
		energy_changed.emit(player_energy, player_max_energy)
	
	# Remove used dice
	for i in range(dice_used):
		if not active_dice.is_empty():
			active_dice.pop_front()
	
	# Track combo
	combo_count += 1
	cards_played_this_turn.append(card_id)
	stats["cards_played"] = stats.get("cards_played", 0) + 1
	if combo_count > stats.get("highest_combo", 0):
		stats["highest_combo"] = combo_count
	
	# Remove card from hand to discard
	hand.remove_at(hand_index)
	discard.append(card_id)
	deck_changed.emit()
	
	return {
		"success": true,
		"card_id": card_id,
		"card_def": card_def,
		"value": value,
		"dice_used": dice_used,
		"dice_bonus": dice_bonus,
		"combo_bonus": combo_bonus,
		"upgraded": upgrades > 0
	}

func roll_all_dice():
	active_dice.clear()
	for dice_id in dice_pool:
		var dice_def = GameData.DICE.get(dice_id)
		if dice_def:
			var face_idx = randi() % dice_def.faces.size()
			var value = dice_def.faces[face_idx]
			# Relic: Golden Dice - minimum roll is 3
			if relics.has("golden_dice"):
				value = max(3, value)
			active_dice.append({
				"type": dice_id,
				"value": value,
				"def": dice_def
			})
	stats["dice_rolled"] = stats.get("dice_rolled", 0) + 1

func reroll_dice():
	roll_all_dice()

func add_card_to_deck(card_id: String):
	deck.append(card_id)
	deck.shuffle()
	deck_changed.emit()

func remove_card_from_deck(card_id: String) -> bool:
	var idx = deck.find(card_id)
	if idx >= 0:
		deck.remove_at(idx)
		deck_changed.emit()
		return true
	idx = discard.find(card_id)
	if idx >= 0:
		discard.remove_at(idx)
		deck_changed.emit()
		return true
	return false

func get_all_deck_card_ids() -> Array[String]:
	var all: Array[String] = []
	all.append_array(deck)
	all.append_array(discard)
	return all

func add_dice(dice_id: String):
	dice_pool.append(dice_id)

func add_gold(amount: int):
	player_gold += amount
	gold_changed.emit(player_gold)
	stats["gold_earned"] = stats.get("gold_earned", 0) + amount
	stats["total_gold_earned"] = stats.get("total_gold_earned", 0) + amount

func next_floor():
	current_floor += 1
	rooms_visited.clear()
	current_room = Vector2i.ZERO
	map_seed = randi()
	floor_changed.emit(current_floor)
	# Update meta best
	if current_floor > meta_best_floor:
		meta_best_floor = current_floor

func is_dead() -> bool:
	return player_hp <= 0

func is_victory() -> bool:
	return current_floor > max_floors

func add_relic(relic_id: String):
	if not relics.has(relic_id):
		relics.append(relic_id)
		stats["relics_found"] = stats.get("relics_found", 0) + 1
		# Apply immediate relic effects
		match relic_id:
			"blood_vial":
				player_max_hp += 10
				heal(10)
			"flame_ring":
				add_dice("fire")
			"frost_amulet":
				add_dice("ice")
			"poison_fang":
				add_dice("poison")

func upgrade_card(card_id: String):
	if card_upgrades.has(card_id):
		card_upgrades[card_id] += 1
	else:
		card_upgrades[card_id] = 1
	stats["cards_upgraded"] = stats.get("cards_upgraded", 0) + 1

func get_card_upgrade_level(card_id: String) -> int:
	return card_upgrades.get(card_id, 0)

func draw_single_card():
	if deck.is_empty():
		deck = discard.duplicate()
		discard.clear()
		deck.shuffle()
	if not deck.is_empty():
		hand.append(deck.pop_back())
	deck_changed.emit()

func apply_damage_with_relics(base_damage: int) -> int:
	var damage = base_damage
	# Relic: Flame Ring - +2 fire damage
	if relics.has("flame_ring"):
		damage += 2
	# Relic: Broken Mirror - 10% chance to double damage
	if relics.has("broken_mirror") and randf() < 0.1:
		damage *= 2
	return damage

func take_damage_with_relics(amount: int) -> int:
	# Relic: Frost Amulet - reduce incoming damage by 1
	if relics.has("frost_amulet"):
		amount = max(0, amount - 1)
	return take_damage(amount)
