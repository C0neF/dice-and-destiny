## Save Manager - Handles meta progression + run-in-progress saves
extends Node

const SAVE_PATH = "user://save_data.json"
const META_PATH = "user://meta_progress.json"

## ============================================================
##  META PROGRESSION (persists across all runs)
## ============================================================

func save_meta():
	var data = {
		"total_runs": GameState.meta_total_runs,
		"best_floor": GameState.meta_best_floor,
		"unlocked_cards": GameState.meta_unlocked_cards,
		"unlocked_relics": GameState.meta_unlocked_relics,
		"total_gold_earned": GameState.stats.get("total_gold_earned", 0),
		"total_enemies_killed": GameState.stats.get("total_enemies_killed", 0),
		"language": Loc.current_lang,
		"sfx_volume": SFX.sfx_volume,
		"bgm_volume": SFX.bgm_volume,
	}
	_write_json(META_PATH, data)

func load_meta():
	var data = _read_json(META_PATH)
	if data.is_empty():
		return
	GameState.meta_total_runs = int(data.get("total_runs", 0))
	GameState.meta_best_floor = int(data.get("best_floor", 0))
	# JSON arrays are untyped — convert to Array[String]
	var raw_cards = data.get("unlocked_cards", [])
	GameState.meta_unlocked_cards.clear()
	for c in raw_cards:
		GameState.meta_unlocked_cards.append(str(c))
	var raw_relics = data.get("unlocked_relics", [])
	GameState.meta_unlocked_relics.clear()
	for r in raw_relics:
		GameState.meta_unlocked_relics.append(str(r))
	var lang = data.get("language", "zh")
	if lang in ["zh", "en"]:
		Loc.current_lang = lang
	SFX.sfx_volume = float(data.get("sfx_volume", 0.8))
	SFX.bgm_volume = float(data.get("bgm_volume", 0.6))

## ============================================================
##  RUN SAVE (save / resume mid-run)
## ============================================================

func has_run_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_run():
	var data = {
		"run_mode": GameState.run_mode,
		"survivor_difficulty": GameState.survivor_difficulty,
		"player_hp": GameState.player_hp,
		"player_max_hp": GameState.player_max_hp,
		"player_energy": GameState.player_energy,
		"player_max_energy": GameState.player_max_energy,
		"player_armor": GameState.player_armor,
		"player_gold": GameState.player_gold,
		"current_floor": GameState.current_floor,
		"deck": GameState.deck,
		"hand": GameState.hand,
		"discard": GameState.discard,
		"hand_size": GameState.hand_size,
		"dice_pool": GameState.dice_pool,
		"relics": GameState.relics,
		"card_upgrades": GameState.card_upgrades,
		"map_seed": GameState.map_seed,
		"current_room_x": GameState.current_room.x,
		"current_room_y": GameState.current_room.y,
		"stats": GameState.stats,
	}
	_write_json(SAVE_PATH, data)

func load_run() -> bool:
	var data = _read_json(SAVE_PATH)
	if data.is_empty():
		return false
	
	GameState.run_mode = data.get("run_mode", "adventure")
	GameState.survivor_difficulty = data.get("survivor_difficulty", "normal")
	GameState.player_hp = int(data.get("player_hp", 50))
	GameState.player_max_hp = int(data.get("player_max_hp", 50))
	GameState.player_energy = int(data.get("player_energy", 3))
	GameState.player_max_energy = int(data.get("player_max_energy", 3))
	GameState.player_armor = int(data.get("player_armor", 0))
	GameState.player_gold = int(data.get("player_gold", 0))
	GameState.current_floor = int(data.get("current_floor", 1))
	GameState.deck = Array(data.get("deck", []), TYPE_STRING, "", null)
	GameState.hand = Array(data.get("hand", []), TYPE_STRING, "", null)
	GameState.discard = Array(data.get("discard", []), TYPE_STRING, "", null)
	GameState.hand_size = int(data.get("hand_size", 5))
	GameState.dice_pool = Array(data.get("dice_pool", []), TYPE_STRING, "", null)
	GameState.relics = Array(data.get("relics", []), TYPE_STRING, "", null)
	GameState.card_upgrades = data.get("card_upgrades", {})
	GameState.map_seed = int(data.get("map_seed", 0))
	GameState.current_room = Vector2i(
		int(data.get("current_room_x", 0)),
		int(data.get("current_room_y", 0))
	)
	var loaded_stats = data.get("stats", {})
	var default_stats = {
		"enemies_killed": 0, "cards_played": 0, "damage_dealt": 0,
		"damage_taken": 0, "gold_earned": 0, "gold_spent": 0,
		"healed": 0, "dice_rolled": 0, "rooms_cleared": 0,
		"relics_found": 0, "highest_combo": 0, "cards_upgraded": 0,
		"total_gold_earned": 0, "total_enemies_killed": 0, "run_time_sec": 0.0,
	}
	for key in default_stats:
		if not loaded_stats.has(key):
			loaded_stats[key] = default_stats[key]
	GameState.stats = loaded_stats
	
	# Clear status effects (they don't persist between sessions)
	GameState.poison_stacks = 0
	GameState.freeze_turns = 0
	GameState.regen_turns = 0
	GameState.regen_amount = 0
	GameState.player_effects.clear()
	GameState.combo_count = 0
	GameState.cards_played_this_turn.clear()
	GameState.familiar_active = false
	GameState.familiar_damage = 0
	
	return true

func delete_run_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

## ============================================================
##  FILE I/O
## ============================================================

func _write_json(path: String, data: Dictionary):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}
