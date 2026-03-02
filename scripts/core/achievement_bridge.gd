## Achievement bridge for Milestone plugin.
extends Node

var _poll_acc: float = 0.0
var _notifier: Node = null
var _ui_layer: CanvasLayer = null
var _ui_root: Control = null

func _ready() -> void:
	call_deferred("_setup_notifier")

func _process(delta: float) -> void:
	_poll_acc += delta
	if _poll_acc < 1.0:
		return
	_poll_acc = 0.0
	_sync_achievements()

func _setup_notifier() -> void:
	var notifier_script = load("res://addons/milestone/scripts/achievements/achievement_notifier.gd")
	if not notifier_script:
		return

	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 90
	get_tree().root.add_child(_ui_layer)

	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)

	_notifier = notifier_script.new()
	_notifier.user_interface = _ui_root
	_notifier.screen_corner = "TopRight"
	_notifier.margin = 10
	_notifier.notification_spacing = 6
	_notifier.on_screen_duration = 3.5
	add_child(_notifier)

func _sync_achievements() -> void:
	if AchievementManager == null or GameState == null:
		return

	# Instant unlocks
	if int(GameState.stats.get("enemies_killed", 0)) >= 1:
		AchievementManager.unlock_achievement("first_blood")

	if int(GameState.stats.get("highest_combo", 0)) >= 5:
		AchievementManager.unlock_achievement("combo_apprentice")

	if GameState.current_floor > GameState.max_floors:
		AchievementManager.unlock_achievement("demon_slayer")

	# Progressive achievements (sync by delta)
	_progress_to("card_machine", int(GameState.stats.get("cards_played", 0)))
	_progress_to("relic_collector", int(GameState.stats.get("relics_found", 0)))
	_progress_to("gold_hoarder", int(GameState.stats.get("gold_earned", 0)))
	_progress_to("endurance_runner", int(GameState.stats.get("run_time_sec", 0)))

func _progress_to(achievement_id: String, target: int) -> void:
	if target <= 0:
		return
	var current = AchievementManager.get_progress(achievement_id)
	if target > current:
		AchievementManager.progress_achievement(achievement_id, target - current)
