extends Control

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	$VBox/Title.text = Loc.t("victory_title")
	$VBox/Sub.text = Loc.t("victory_sub")
	$VBox/MenuButton.text = Loc.t("main_menu")
	
	var title = $VBox/Title
	var tw = create_tween().set_loops(30)
	tw.tween_property(title, "modulate", Color(1.2, 1.1, 0.8), 1.0)
	tw.tween_property(title, "modulate", Color(1, 0.9, 0.7), 1.0)
	
	$VBox/MenuButton.pressed.connect(func():
		await VFX.fade_out(0.4)
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn"))
