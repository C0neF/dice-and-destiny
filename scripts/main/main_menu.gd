## Main Menu with settings panel
extends Control

@onready var start_btn = $VBox/StartButton
@onready var survivor_btn = $VBox/SurvivorButton
@onready var settings_btn = $VBox/SettingsButton
@onready var quit_btn = $VBox/QuitButton
@onready var title_label = $VBox/Title
@onready var subtitle_label = $VBox/Subtitle
@onready var desc_label = $VBox/Desc
@onready var version_label = $Version
@onready var settings_panel = $SettingsPanel
@onready var settings_title = $SettingsPanel/VBox/SettingsTitle
@onready var fullscreen_btn = $SettingsPanel/VBox/DisplayRow/FullscreenBtn
@onready var windowed_btn = $SettingsPanel/VBox/DisplayRow/WindowedBtn
@onready var display_label = $SettingsPanel/VBox/DisplayRow/DisplayLabel
@onready var lang_label = $SettingsPanel/VBox/LangRow/LangLabel
@onready var zh_btn = $SettingsPanel/VBox/LangRow/ZhBtn
@onready var en_btn = $SettingsPanel/VBox/LangRow/EnBtn
@onready var back_btn = $SettingsPanel/VBox/BackBtn

var title_time: float = 0.0

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	start_btn.pressed.connect(_on_start)
	survivor_btn.pressed.connect(_on_survivor)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)
	fullscreen_btn.pressed.connect(_on_fullscreen)
	windowed_btn.pressed.connect(_on_windowed)
	zh_btn.pressed.connect(func(): _set_lang("zh"))
	en_btn.pressed.connect(func(): _set_lang("en"))
	back_btn.pressed.connect(_on_back)
	
	settings_panel.visible = false
	_update_texts()
	_update_display_buttons()
	
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.8)

func _process(delta):
	title_time += delta
	if title_label:
		title_label.position.y = -2.0 * sin(title_time * 1.5)
	if subtitle_label:
		var pulse = 0.7 + 0.3 * sin(title_time * 2.0)
		subtitle_label.modulate = Color(pulse, pulse * 0.9, pulse * 0.7)

func _update_texts():
	title_label.text = Loc.t("title")
	subtitle_label.text = Loc.t("subtitle")
	desc_label.text = Loc.t("desc")
	start_btn.text = Loc.t("begin")
	survivor_btn.text = Loc.t("survivor_mode") if Loc.has_key("survivor_mode") else "Survivor Mode"
	settings_btn.text = Loc.t("settings")
	quit_btn.text = Loc.t("quit")
	version_label.text = Loc.t("version")
	settings_title.text = Loc.t("settings_title")
	display_label.text = Loc.t("display_mode")
	lang_label.text = Loc.t("language")
	fullscreen_btn.text = Loc.t("fullscreen")
	windowed_btn.text = Loc.t("windowed")
	back_btn.text = Loc.t("back")

func _update_display_buttons():
	var is_fs = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_btn.disabled = is_fs
	windowed_btn.disabled = not is_fs

func _on_start():
	await VFX.fade_out(0.4)
	GameState.reset_run()
	GameState.run_mode = "adventure"
	get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")

func _on_survivor():
	await VFX.fade_out(0.4)
	GameState.reset_run()
	GameState.run_mode = "survivor"
	get_tree().change_scene_to_file("res://scenes/battle/survivor_arena.tscn")

func _on_settings():
	settings_panel.visible = true
	$VBox.visible = false

func _on_back():
	settings_panel.visible = false
	$VBox.visible = true

func _on_fullscreen():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_display_buttons()

func _on_windowed():
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_update_display_buttons()

func _set_lang(lang: String):
	Loc.current_lang = lang
	_update_texts()
	zh_btn.disabled = (lang == "zh")
	en_btn.disabled = (lang == "en")

func _on_quit():
	await VFX.fade_out(0.3)
	get_tree().quit()
