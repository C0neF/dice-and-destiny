## Relic System - Passive artifacts that modify gameplay
class_name RelicData

enum RelicRarity { COMMON, UNCOMMON, RARE, BOSS }

class RelicDef:
	var id: String
	var name_key: String  # Loc key for name
	var desc_key: String  # Loc key for description
	var rarity: int
	var texture_path: String
	var cost: int  # Shop price in gold
	
	func _init(p_id: String, p_name_key: String, p_desc_key: String, p_rarity: int, p_tex: String, p_cost: int = 0):
		id = p_id; name_key = p_name_key; desc_key = p_desc_key
		rarity = p_rarity; texture_path = p_tex; cost = p_cost

static var RELICS: Dictionary = {}

static func _static_init():
	# Common relics (shop cost: 50G)
	RELICS["lucky_coin"] = RelicDef.new("lucky_coin", "relic_lucky_coin_name", "relic_lucky_coin_desc",
		RelicRarity.COMMON, "res://assets/sprites/relics/relic_lucky_coin.png", 50)
	RELICS["blood_vial"] = RelicDef.new("blood_vial", "relic_blood_vial_name", "relic_blood_vial_desc",
		RelicRarity.COMMON, "res://assets/sprites/relics/relic_blood_vial.png", 50)
	# Uncommon relics (shop cost: 80G)
	RELICS["iron_crown"] = RelicDef.new("iron_crown", "relic_iron_crown_name", "relic_iron_crown_desc",
		RelicRarity.UNCOMMON, "res://assets/sprites/relics/relic_iron_crown.png", 80)
	RELICS["flame_ring"] = RelicDef.new("flame_ring", "relic_flame_ring_name", "relic_flame_ring_desc",
		RelicRarity.UNCOMMON, "res://assets/sprites/relics/relic_flame_ring.png", 80)
	RELICS["frost_amulet"] = RelicDef.new("frost_amulet", "relic_frost_amulet_name", "relic_frost_amulet_desc",
		RelicRarity.UNCOMMON, "res://assets/sprites/relics/relic_frost_amulet.png", 80)
	# Rare relics (shop cost: 120G)
	RELICS["poison_fang"] = RelicDef.new("poison_fang", "relic_poison_fang_name", "relic_poison_fang_desc",
		RelicRarity.RARE, "res://assets/sprites/relics/relic_poison_fang.png", 120)
	RELICS["war_drum"] = RelicDef.new("war_drum", "relic_war_drum_name", "relic_war_drum_desc",
		RelicRarity.RARE, "res://assets/sprites/relics/relic_war_drum.png", 120)
	RELICS["crystal_ball"] = RelicDef.new("crystal_ball", "relic_crystal_ball_name", "relic_crystal_ball_desc",
		RelicRarity.RARE, "res://assets/sprites/relics/relic_crystal_ball.png", 120)
	# Boss relics (not sold in shop, only from boss/elite drops)
	RELICS["broken_mirror"] = RelicDef.new("broken_mirror", "relic_broken_mirror_name", "relic_broken_mirror_desc",
		RelicRarity.BOSS, "res://assets/sprites/relics/relic_broken_mirror.png", 200)
	RELICS["golden_dice"] = RelicDef.new("golden_dice", "relic_golden_dice_name", "relic_golden_dice_desc",
		RelicRarity.BOSS, "res://assets/sprites/relics/relic_golden_dice.png", 200)

## Get relic IDs not already owned by the player, optionally filtered by max rarity
static func get_available(exclude: Array, max_rarity: int = RelicRarity.BOSS) -> Array[String]:
	var result: Array[String] = []
	for key in RELICS:
		if not exclude.has(key) and RELICS[key].rarity <= max_rarity:
			result.append(key)
	return result

## Pick N random relics from available pool
static func pick_random(count: int, exclude: Array, max_rarity: int = RelicRarity.BOSS) -> Array[String]:
	var pool = get_available(exclude, max_rarity)
	pool.shuffle()
	return pool.slice(0, mini(count, pool.size()))

## Pick N random relics suitable for shop (excludes BOSS rarity)
static func pick_for_shop(count: int, exclude: Array) -> Array[String]:
	return pick_random(count, exclude, RelicRarity.RARE)

## Get rarity color for display
static func rarity_color(rarity: int) -> Color:
	match rarity:
		RelicRarity.COMMON: return Color(0.8, 0.8, 0.75)
		RelicRarity.UNCOMMON: return Color(0.3, 0.55, 0.9)
		RelicRarity.RARE: return Color(0.7, 0.3, 0.85)
		RelicRarity.BOSS: return Color(1, 0.75, 0.2)
		_: return Color.WHITE

## Get rarity tag string
static func rarity_tag(rarity: int) -> String:
	match rarity:
		RelicRarity.COMMON: return "⚪"
		RelicRarity.UNCOMMON: return "🔵"
		RelicRarity.RARE: return "🟣"
		RelicRarity.BOSS: return "🟡"
		_: return ""
