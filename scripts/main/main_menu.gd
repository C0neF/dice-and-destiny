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
@onready var volume_slider = $SettingsPanel/VBox/VolumeRow/VolumeSlider
@onready var volume_label = $SettingsPanel/VBox/VolumeRow/VolumeLabel
@onready var volume_value = $SettingsPanel/VBox/VolumeRow/VolumeValue
@onready var bgm_slider = $SettingsPanel/VBox/BgmRow/BgmSlider
@onready var bgm_label = $SettingsPanel/VBox/BgmRow/BgmLabel
@onready var bgm_value = $SettingsPanel/VBox/BgmRow/BgmValue

var title_time: float = 0.0
var continue_btn: Button = null
var _settings_fader: Node = null

func _ready():
	theme = ThemeGen.create_game_theme()
	VFX.fade_in(0.5)
	
	# Load meta progression + language preference
	SaveManager.load_meta()
	
	start_btn.pressed.connect(_on_start)
	survivor_btn.pressed.connect(_on_survivor)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)
	fullscreen_btn.pressed.connect(_on_fullscreen)
	windowed_btn.pressed.connect(_on_windowed)
	zh_btn.pressed.connect(func(): _set_lang("zh"))
	en_btn.pressed.connect(func(): _set_lang("en"))
	back_btn.pressed.connect(_on_back)
	
	# Volume slider
	volume_slider.value = SFX.sfx_volume * 100.0
	volume_value.text = "%d%%" % int(volume_slider.value)
	volume_slider.value_changed.connect(func(val):
		SFX.set_volume(val / 100.0)
		volume_value.text = "%d%%" % int(val)
		SFX.play("ui_click")
	)
	
	# BGM volume slider
	bgm_slider.value = SFX.bgm_volume * 100.0
	bgm_value.text = "%d%%" % int(bgm_slider.value)
	bgm_slider.value_changed.connect(func(val):
		SFX.set_bgm_volume(val / 100.0)
		bgm_value.text = "%d%%" % int(val)
	)
	
	settings_panel.visible = false
	_settings_fader = _setup_panel_fader(settings_panel)
	
	# Add Continue button if a run save exists
	if SaveManager.has_run_save():
		continue_btn = Button.new()
		continue_btn.custom_minimum_size = Vector2(220, 44)
		continue_btn.add_theme_font_size_override("font_size", 18)
		continue_btn.pressed.connect(_on_continue)
		$VBox.add_child(continue_btn)
		$VBox.move_child(continue_btn, $VBox.get_children().find(start_btn))
	
	# Add meta stats display
	if GameState.meta_total_runs > 0:
		var meta_lbl = Label.new()
		meta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta_lbl.add_theme_font_size_override("font_size", 12)
		meta_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.6))
		$VBox.add_child(meta_lbl)
		meta_lbl.name = "MetaLabel"
	
	_update_texts()
	_update_display_buttons()
	
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	
	# Play lobby BGM
	SFX.play_bgm("lobby")

func _process(delta):
	title_time += delta
	if title_label:
		title_label.position.y = -2.0 * sin(title_time * 1.5)
	if subtitle_label:
		var pulse = 0.7 + 0.3 * sin(title_time * 2.0)
		subtitle_label.modulate = Color(pulse, pulse * 0.9, pulse * 0.7)

func _setup_panel_fader(panel: Control) -> Node:
	if not panel:
		return null
	var fader_script = load("res://addons/uiJuicer/Fader.gd")
	if not fader_script:
		return null
	for child in panel.get_children():
		if child.get_script() == fader_script:
			return child
	var fader = fader_script.new()
	fader.AutoFadeIn = false
	fader.StartVisible = false
	fader.FadeInTime = 0.2
	fader.FadeOutTime = 0.15
	fader.ChangeVisibility = false
	panel.add_child(fader)
	return fader

func _update_texts():
	title_label.text = Loc.t("title")
	subtitle_label.text = Loc.t("subtitle")
	desc_label.text = Loc.t("desc")
	start_btn.text = Loc.t("begin")
	survivor_btn.text = ("冒险模式" if Loc.current_lang == "zh" else "Adventure Mode")
	settings_btn.text = Loc.t("settings")
	quit_btn.text = Loc.t("quit")
	version_label.text = Loc.t("version")
	settings_title.text = Loc.t("settings_title")
	display_label.text = Loc.t("display_mode")
	lang_label.text = Loc.t("language")
	fullscreen_btn.text = Loc.t("fullscreen")
	windowed_btn.text = Loc.t("windowed")
	back_btn.text = Loc.t("back")
	if continue_btn:
		continue_btn.text = Loc.t("continue_run")
	if volume_label:
		volume_label.text = Loc.t("sfx_volume")
	if bgm_label:
		bgm_label.text = Loc.t("bgm_volume")
	var meta_lbl = get_node_or_null("VBox/MetaLabel")
	if meta_lbl:
		meta_lbl.text = Loc.tf("meta_stats", [GameState.meta_total_runs, GameState.meta_best_floor])

func _update_display_buttons():
	var is_fs = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_btn.disabled = is_fs
	windowed_btn.disabled = not is_fs

func _on_start():
	_show_survivor_difficulty_picker()

func _start_survivor_with_difficulty(diff: String):
	await VFX.fade_out(0.4)
	SaveManager.delete_run_save()  # New run discards old save
	GameState.reset_run()
	GameState.run_mode = "survivor"
	GameState.survivor_difficulty = diff
	get_tree().change_scene_to_file("res://scenes/battle/survivor_arena.tscn")

func _show_survivor_difficulty_picker():
	if has_node("DifficultyOverlay"):
		return
	var overlay = ColorRect.new()
	overlay.name = "DifficultyOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 220)
	panel.position = Vector2(-180, -110)
	overlay.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	
	var title = Label.new()
	title.text = ("选择模式难度" if Loc.current_lang == "zh" else "Choose Difficulty")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)
	
	var hint = Label.new()
	hint.text = ("默认：普通模式" if Loc.current_lang == "zh" else "Default: Normal")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	vb.add_child(hint)
	
	var normal_btn = Button.new()
	normal_btn.custom_minimum_size = Vector2(0, 42)
	normal_btn.text = ("普通模式（默认）" if Loc.current_lang == "zh" else "Normal (Default)")
	normal_btn.pressed.connect(func():
		overlay.queue_free()
		_start_survivor_with_difficulty("normal")
	)
	vb.add_child(normal_btn)
	
	var hard_btn = Button.new()
	hard_btn.custom_minimum_size = Vector2(0, 42)
	hard_btn.text = ("困难模式" if Loc.current_lang == "zh" else "Hard Mode")
	hard_btn.pressed.connect(func():
		overlay.queue_free()
		_start_survivor_with_difficulty("hard")
	)
	vb.add_child(hard_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.custom_minimum_size = Vector2(0, 34)
	cancel_btn.text = ("取消" if Loc.current_lang == "zh" else "Cancel")
	cancel_btn.pressed.connect(func(): overlay.queue_free())
	vb.add_child(cancel_btn)

func _on_survivor():
	await VFX.fade_out(0.4)
	SaveManager.delete_run_save()
	GameState.reset_run()
	GameState.run_mode = "adventure"
	get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")

func _on_continue():
	await VFX.fade_out(0.4)
	if SaveManager.load_run():
		if GameState.run_mode == "survivor":
			get_tree().change_scene_to_file("res://scenes/battle/survivor_arena.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	else:
		# Save corrupted - start new
		GameState.reset_run()
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")

func _on_settings():
	settings_panel.visible = true
	$VBox.visible = false
	if _settings_fader and _settings_fader.has_method("FadeIn"):
		_settings_fader.FadeIn(0.2)

func _on_back():
	if _settings_fader and _settings_fader.has_method("FadeOut"):
		await _settings_fader.FadeOut(0.15)
	settings_panel.visible = false
	$VBox.visible = true
	SaveManager.save_meta()  # Persist volume + language

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
