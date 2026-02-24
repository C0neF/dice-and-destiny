extends Control

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	SFX.stop_bgm(1.0)  # Fade out battle BGM
	$VBox/Title.text = Loc.t("victory_title")
	$VBox/Sub.text = Loc.t("victory_sub")
	$VBox/MenuButton.text = Loc.t("main_menu")
	
	var title = $VBox/Title
	var tw = create_tween().set_loops(30)
	tw.tween_property(title, "modulate", Color(1.2, 1.1, 0.8), 1.0)
	tw.tween_property(title, "modulate", Color(1, 0.9, 0.7), 1.0)
	SFX.play("victory")
	
	# Insert run summary before menu button
	var summary = _build_victory_summary()
	$VBox.add_child(summary)
	$VBox.move_child(summary, 2)  # After title + sub
	
	# Save meta + delete run save (run complete)
	GameState.meta_best_floor = max(GameState.meta_best_floor, GameState.max_floors + 1)
	SaveManager.save_meta()
	SaveManager.delete_run_save()
	
	$VBox/MenuButton.pressed.connect(func():
		await VFX.fade_out(0.4)
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))

func _build_victory_summary() -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	
	var s = GameState.stats
	var run_time = int(s.get("run_time_sec", 0))
	var minutes = run_time / 60
	var seconds = run_time % 60
	
	# Header
	var header = Label.new()
	header.text = Loc.t("victory_summary")
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var entries = [
		[Loc.t("stat_time"), "%d:%02d" % [minutes, seconds]],
		[Loc.t("stat_enemies_killed"), str(s.get("enemies_killed", 0))],
		[Loc.t("stat_damage_dealt"), str(s.get("damage_dealt", 0))],
		[Loc.t("stat_damage_taken"), str(s.get("damage_taken", 0))],
		[Loc.t("stat_cards_played"), str(s.get("cards_played", 0))],
		[Loc.t("stat_gold_earned"), str(s.get("gold_earned", 0))],
		[Loc.t("stat_relics_found"), str(s.get("relics_found", 0))],
		[Loc.t("stat_highest_combo"), str(s.get("highest_combo", 0))],
		[Loc.t("stat_cards_upgraded"), str(s.get("cards_upgraded", 0))],
	]
	
	for entry in entries:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.custom_minimum_size = Vector2(300, 0)
		vbox.add_child(row)
		
		var key_lbl = Label.new()
		key_lbl.text = entry[0]
		key_lbl.add_theme_font_size_override("font_size", 14)
		key_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_lbl)
		
		var val_lbl = Label.new()
		val_lbl.text = entry[1]
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
	
	# Meta record
	var meta_lbl = Label.new()
	meta_lbl.text = Loc.tf("meta_stats", [GameState.meta_total_runs, GameState.meta_best_floor])
	meta_lbl.add_theme_font_size_override("font_size", 12)
	meta_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.6))
	meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(meta_lbl)
	
	return vbox
