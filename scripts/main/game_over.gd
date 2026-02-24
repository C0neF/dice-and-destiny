extends Control

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	$VBox/Title.text = Loc.t("game_over")
	$VBox/RetryButton.text = Loc.t("retry")
	$VBox/MenuButton.text = Loc.t("main_menu")
	
	var title = $VBox/Title
	title.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 1.0).set_delay(0.3)
	
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
