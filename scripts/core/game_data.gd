## Game Data - Card and dice definitions
class_name GameData

# Card types
enum CardType { ATTACK, DEFEND, MAGIC, HEAL, DICE_BOOST }
# Dice types  
enum DiceType { NORMAL, FIRE, ICE, POISON }
# Enemy types
enum EnemyType { SLIME, SKELETON, BAT, GOBLIN, GHOST, DEMON }

# Card definition
class CardDef:
	var id: String
	var name: String
	var type: int  # CardType
	var description: String
	var base_value: int
	var energy_cost: int
	var dice_slots: int  # How many dice this card can hold
	var dice_multiplier: float  # How dice affect the card
	var texture_path: String
	
	func _init(p_id: String, p_name: String, p_type: int, p_desc: String, 
			   p_base: int, p_cost: int, p_slots: int, p_mult: float, p_tex: String):
		id = p_id; name = p_name; type = p_type; description = p_desc
		base_value = p_base; energy_cost = p_cost; dice_slots = p_slots
		dice_multiplier = p_mult; texture_path = p_tex

# Dice definition
class DiceDef:
	var type: int  # DiceType
	var faces: Array[int]
	var name: String
	var texture_path: String
	
	func _init(p_type: int, p_faces: Array[int], p_name: String, p_tex: String):
		type = p_type; faces = p_faces; name = p_name; texture_path = p_tex

# Enemy definition
class EnemyDef:
	var type: int
	var name: String
	var max_hp: int
	var base_attack: int
	var base_defense: int
	var texture_path: String
	var is_boss: bool
	var loot_cards: Array[String]
	
	func _init(p_type: int, p_name: String, p_hp: int, p_atk: int, p_def: int, 
			   p_tex: String, p_boss: bool, p_loot: Array[String]):
		type = p_type; name = p_name; max_hp = p_hp; base_attack = p_atk
		base_defense = p_def; texture_path = p_tex; is_boss = p_boss; loot_cards = p_loot

static var CARDS: Dictionary = {}
static var DICE: Dictionary = {}
static var ENEMIES: Dictionary = {}

static func _static_init():
	# === STARTER CARDS ===
	CARDS["strike"] = CardDef.new("strike", "Strike", CardType.ATTACK, 
		"Deal {value} damage", 6, 1, 1, 1.0, "res://assets/sprites/cards/card_attack.png")
	CARDS["heavy_strike"] = CardDef.new("heavy_strike", "Heavy Strike", CardType.ATTACK,
		"Deal {value} damage", 10, 2, 2, 1.5, "res://assets/sprites/cards/card_attack.png")
	CARDS["block"] = CardDef.new("block", "Block", CardType.DEFEND,
		"Gain {value} armor", 5, 1, 1, 1.0, "res://assets/sprites/cards/card_defend.png")
	CARDS["fortress"] = CardDef.new("fortress", "Fortress", CardType.DEFEND,
		"Gain {value} armor", 8, 2, 2, 1.2, "res://assets/sprites/cards/card_defend.png")
	CARDS["fireball"] = CardDef.new("fireball", "Fireball", CardType.MAGIC,
		"Deal {value} magic damage to all", 4, 2, 1, 2.0, "res://assets/sprites/cards/card_magic.png")
	CARDS["ice_shard"] = CardDef.new("ice_shard", "Ice Shard", CardType.MAGIC,
		"Deal {value} damage, freeze 1 turn", 3, 1, 1, 1.5, "res://assets/sprites/cards/card_magic.png")
	CARDS["heal"] = CardDef.new("heal", "Heal", CardType.HEAL,
		"Restore {value} HP", 5, 1, 1, 1.0, "res://assets/sprites/cards/card_heal.png")
	CARDS["regenerate"] = CardDef.new("regenerate", "Regenerate", CardType.HEAL,
		"Restore {value} HP over 3 turns", 3, 2, 2, 1.5, "res://assets/sprites/cards/card_heal.png")
	CARDS["lucky_roll"] = CardDef.new("lucky_roll", "Lucky Roll", CardType.DICE_BOOST,
		"Re-roll all dice, +{value} to each", 1, 0, 3, 1.0, "res://assets/sprites/cards/card_dice.png")
	CARDS["loaded_dice"] = CardDef.new("loaded_dice", "Loaded Dice", CardType.DICE_BOOST,
		"Set one die to 6", 6, 1, 0, 0.0, "res://assets/sprites/cards/card_dice.png")
	CARDS["poison_strike"] = CardDef.new("poison_strike", "Poison Strike", CardType.ATTACK,
		"Deal {value} + 2 poison/turn", 4, 1, 1, 1.0, "res://assets/sprites/cards/card_attack.png")
	CARDS["mirror_shield"] = CardDef.new("mirror_shield", "Mirror Shield", CardType.DEFEND,
		"Gain {value} armor, reflect 50%", 3, 2, 1, 1.5, "res://assets/sprites/cards/card_defend.png")
	
	# === COMBO CARDS ===
	CARDS["flurry"] = CardDef.new("flurry", "Flurry", CardType.ATTACK,
		"Deal {value} damage 3 times", 2, 2, 0, 0.0, "res://assets/sprites/cards/card_combo.png")
	CARDS["chain_lightning"] = CardDef.new("chain_lightning", "Chain Lightning", CardType.MAGIC,
		"Deal {value} to all, +3 per combo", 3, 2, 1, 1.0, "res://assets/sprites/cards/card_magic.png")
	CARDS["battle_cry"] = CardDef.new("battle_cry", "Battle Cry", CardType.DICE_BOOST,
		"Gain {value} Strength for this fight", 2, 1, 1, 1.0, "res://assets/sprites/cards/card_combo.png")
	CARDS["vampiric_strike"] = CardDef.new("vampiric_strike", "Vampiric Strike", CardType.ATTACK,
		"Deal {value} damage, heal half", 5, 2, 1, 1.0, "res://assets/sprites/cards/card_attack.png")
	CARDS["weaken"] = CardDef.new("weaken", "Weaken", CardType.MAGIC,
		"Apply {value} Weak + Vulnerable", 2, 1, 1, 0.5, "res://assets/sprites/cards/card_curse.png")
	CARDS["dodge_roll"] = CardDef.new("dodge_roll", "Dodge Roll", CardType.DEFEND,
		"Gain Dodge, draw 1 card", 0, 1, 0, 0.0, "res://assets/sprites/cards/card_defend.png")
	CARDS["inferno"] = CardDef.new("inferno", "Inferno", CardType.MAGIC,
		"Apply {value} Burn to all enemies", 3, 2, 2, 1.5, "res://assets/sprites/cards/card_magic.png")
	CARDS["summon_familiar"] = CardDef.new("summon_familiar", "Summon Familiar", CardType.MAGIC,
		"Summon deals {value} damage each turn", 3, 3, 2, 1.0, "res://assets/sprites/cards/card_summon.png")
	CARDS["double_or_nothing"] = CardDef.new("double_or_nothing", "Double or Nothing", CardType.DICE_BOOST,
		"If dice >= 4: double effect. Else: nothing", 0, 1, 1, 2.0, "res://assets/sprites/cards/card_dice.png")
	CARDS["curse_of_pain"] = CardDef.new("curse_of_pain", "Curse of Pain", CardType.MAGIC,
		"Deal {value} + apply Vulnerable 2 turns", 4, 2, 1, 1.0, "res://assets/sprites/cards/card_curse.png")

	# === DICE ===
	DICE["normal"] = DiceDef.new(DiceType.NORMAL, [1,2,3,4,5,6], "Normal Die", 
		"res://assets/sprites/dice/dice_1.png")
	DICE["fire"] = DiceDef.new(DiceType.FIRE, [2,2,4,4,6,6], "Fire Die",
		"res://assets/sprites/dice/dice_fire.png")
	DICE["ice"] = DiceDef.new(DiceType.ICE, [1,1,3,3,5,5], "Ice Die",
		"res://assets/sprites/dice/dice_ice.png")
	DICE["poison"] = DiceDef.new(DiceType.POISON, [1,2,2,3,3,6], "Poison Die",
		"res://assets/sprites/dice/dice_poison.png")

	# === ENEMIES ===
	ENEMIES["slime"] = EnemyDef.new(EnemyType.SLIME, "Slime", 15, 4, 0,
		"res://assets/sprites/enemies/slime.png", false, ["heal"])
	ENEMIES["skeleton"] = EnemyDef.new(EnemyType.SKELETON, "Skeleton", 20, 7, 2,
		"res://assets/sprites/enemies/skeleton.png", false, ["strike", "heavy_strike"])
	ENEMIES["bat"] = EnemyDef.new(EnemyType.BAT, "Bat", 10, 5, 0,
		"res://assets/sprites/enemies/bat.png", false, ["ice_shard"])
	ENEMIES["goblin"] = EnemyDef.new(EnemyType.GOBLIN, "Goblin", 18, 6, 1,
		"res://assets/sprites/enemies/goblin.png", false, ["poison_strike", "loaded_dice"])
	ENEMIES["ghost"] = EnemyDef.new(EnemyType.GHOST, "Ghost", 12, 8, 3,
		"res://assets/sprites/enemies/ghost.png", false, ["fireball", "mirror_shield"])
	ENEMIES["demon"] = EnemyDef.new(EnemyType.DEMON, "Demon Lord", 60, 12, 5,
		"res://assets/sprites/enemies/demon.png", true, ["lucky_roll"])

# Enemy intent types
enum IntentType { ATTACK, DEFEND, BUFF, DEBUFF, SPECIAL }

class EnemyIntent:
	var type: int  # IntentType
	var value: int
	var description: String
	
	func _init(p_type: int, p_value: int, p_desc: String = ""):
		type = p_type; value = p_value; description = p_desc

## Generate an intent for a given enemy based on its type and current state
static func get_enemy_intent(enemy_type: int, turn: int, enemy_hp_pct: float) -> EnemyIntent:
	match enemy_type:
		EnemyType.SLIME:
			if turn % 3 == 0:
				return EnemyIntent.new(IntentType.BUFF, 2, "Growing...")
			return EnemyIntent.new(IntentType.ATTACK, 4)
		EnemyType.SKELETON:
			if turn % 2 == 0:
				return EnemyIntent.new(IntentType.DEFEND, 5)
			return EnemyIntent.new(IntentType.ATTACK, 7)
		EnemyType.BAT:
			return EnemyIntent.new(IntentType.ATTACK, 5)  # Always attacks
		EnemyType.GOBLIN:
			if enemy_hp_pct < 0.4:
				return EnemyIntent.new(IntentType.DEBUFF, 2, "Poisoning...")
			return EnemyIntent.new(IntentType.ATTACK, 6)
		EnemyType.GHOST:
			if turn % 3 == 0:
				return EnemyIntent.new(IntentType.DEBUFF, 3, "Cursing...")
			return EnemyIntent.new(IntentType.ATTACK, 8)
		EnemyType.DEMON:
			if turn % 4 == 0:
				return EnemyIntent.new(IntentType.SPECIAL, 15, "Charging...")
			elif turn % 4 == 1:
				return EnemyIntent.new(IntentType.BUFF, 5, "Enraging...")
			elif turn % 4 == 2:
				return EnemyIntent.new(IntentType.DEBUFF, 3, "Cursing...")
			return EnemyIntent.new(IntentType.ATTACK, 12)
		_:
			return EnemyIntent.new(IntentType.ATTACK, 5)
