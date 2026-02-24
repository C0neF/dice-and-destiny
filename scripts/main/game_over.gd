extends Control

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	SFX.stop_bgm(1.5)  # Fade out battle BGM
	$VBox/Title.text = Loc.t("game_over")
	$VBox/RetryButton.text = Loc.t("retry")
	$VBox/MenuButton.text = Loc.t("main_menu")
	
	var title = $VBox/Title
	title.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 1.0).set_delay(0.3)
	tw.tween_callback(func(): SFX.play("game_over"))
	
	# Insert run summary before buttons
	var summary = _build_run_summary()
	$VBox.add_child(summary)
	$VBox.move_child(summary, 1)  # After title
	
	# Save meta + delete run save (run ended)
	SaveManager.save_meta()
	SaveManager.delete_run_save()
	
	$VBox/RetryButton.pressed.connect(func(): 
		await VFX.fade_out(0.4)
		var retry_scene = "res://scenes/map/map_screen.tscn"
		if GameState.run_mode == "survivor":
			retry_scene = "res://scenes/battle/survivor_arena.tscn"
		GameState.reset_run()
		get_tree().change_scene_to_file(retry_scene))
	$VBox/MenuButton.pressed.connect(func():
		await VFX.fade_out(0.4)
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))

func _build_run_summary() -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	
	var s = GameState.stats
	var run_time = int(s.get("run_time_sec", 0))
	var minutes = run_time / 60
	var seconds = run_time % 60
	
	var entries = [
		[Loc.t("stat_floor"), "%d / %d" % [GameState.current_floor, GameState.max_floors]],
		[Loc.t("stat_time"), "%d:%02d" % [minutes, seconds]],
		[Loc.t("stat_enemies_killed"), str(s.get("enemies_killed", 0))],
		[Loc.t("stat_damage_dealt"), str(s.get("damage_dealt", 0))],
		[Loc.t("stat_gold_earned"), str(s.get("gold_earned", 0))],
		[Loc.t("stat_highest_combo"), str(s.get("highest_combo", 0))],
		[Loc.t("stat_relics_found"), str(s.get("relics_found", 0))],
	]
	
	for entry in entries:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2(280, 0)
		vbox.add_child(row)
		
		var key_lbl = Label.new()
		key_lbl.text = entry[0]
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_lbl)
		
		var val_lbl = Label.new()
		val_lbl.text = entry[1]
		val_lbl.add_theme_font_size_override("font_size", 13)
		val_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
	
	return vbox
