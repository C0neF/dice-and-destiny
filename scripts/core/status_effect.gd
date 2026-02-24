## Status Effect System
class_name StatusEffect

enum Type {
	BURN,       # Damage over time (fire)
	FREEZE,     # Skip next turn
	POISON,     # Stacking damage per turn
	WEAK,       # Deal 25% less damage
	STRENGTH,   # Deal +N more damage per attack
	VULNERABLE, # Take 50% more damage
	REGEN,      # Heal N per turn
	COMBO,      # Bonus damage per card played this turn
	DODGE,      # Chance to avoid next attack
	SHIELD,     # Flat damage reduction
}

class Effect:
	var type: int
	var stacks: int
	var duration: int  # -1 = permanent until stacks run out
	
	func _init(p_type: int, p_stacks: int, p_duration: int = -1):
		type = p_type; stacks = p_stacks; duration = p_duration
	
	func tick() -> Dictionary:
		## Returns {damage: int, heal: int, expired: bool, message: String}
		var result = {"damage": 0, "heal": 0, "expired": false, "message": ""}
		
		match type:
			Type.BURN:
				result.damage = stacks
				stacks = max(0, stacks - 1)
				if stacks <= 0:
					result.expired = true
			Type.POISON:
				result.damage = stacks
				stacks = max(0, stacks - 1)
				if stacks <= 0:
					result.expired = true
			Type.REGEN:
				result.heal = stacks
				if duration > 0:
					duration -= 1
					if duration <= 0:
						result.expired = true
			Type.FREEZE:
				stacks -= 1
				if stacks <= 0:
					result.expired = true
			Type.WEAK:
				if duration > 0:
					duration -= 1
					if duration <= 0:
						result.expired = true
			Type.STRENGTH:
				pass  # Permanent unless removed
			Type.VULNERABLE:
				if duration > 0:
					duration -= 1
					if duration <= 0:
						result.expired = true
			Type.COMBO:
				stacks = 0  # Reset each turn
				result.expired = true
			Type.DODGE:
				pass  # Consumed on hit
			Type.SHIELD:
				if duration > 0:
					duration -= 1
					if duration <= 0:
						result.expired = true
		
		return result

static func get_icon_path(type: int) -> String:
	var icons = {
		Type.BURN: "res://assets/sprites/status/status_burn.png",
		Type.FREEZE: "res://assets/sprites/status/status_freeze.png",
		Type.POISON: "res://assets/sprites/status/status_poison.png",
		Type.WEAK: "res://assets/sprites/status/status_weak.png",
		Type.STRENGTH: "res://assets/sprites/status/status_strength.png",
		Type.VULNERABLE: "res://assets/sprites/status/status_vulnerable.png",
		Type.REGEN: "res://assets/sprites/status/status_regen.png",
		Type.COMBO: "res://assets/sprites/status/status_combo.png",
		Type.DODGE: "res://assets/sprites/status/status_dodge.png",
		Type.SHIELD: "res://assets/sprites/status/status_shield.png",
	}
	return icons.get(type, "")

static func get_name_key(type: int) -> String:
	var names = {
		Type.BURN: "status_burn",
		Type.FREEZE: "status_freeze",
		Type.POISON: "status_poison",
		Type.WEAK: "status_weak",
		Type.STRENGTH: "status_strength",
		Type.VULNERABLE: "status_vulnerable",
		Type.REGEN: "status_regen",
		Type.COMBO: "status_combo",
		Type.DODGE: "status_dodge",
		Type.SHIELD: "status_shield",
	}
	return names.get(type, "unknown")
