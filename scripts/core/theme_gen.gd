## Custom pixel-art theme generator
## Creates a cohesive dark fantasy UI theme at runtime
class_name ThemeGen

static func create_game_theme() -> Theme:
	var theme = Theme.new()
	
	# Colors
	var bg_dark = Color(0.08, 0.06, 0.12)
	var bg_medium = Color(0.14, 0.11, 0.22)
	var _bg_light = Color(0.2, 0.16, 0.3)
	var border_color = Color(0.4, 0.35, 0.55)
	var border_highlight = Color(0.6, 0.5, 0.8)
	var text_color = Color(0.9, 0.88, 0.82)
	var text_dim = Color(0.6, 0.55, 0.5)
	var accent_gold = Color(1.0, 0.85, 0.3)
	var accent_red = Color(0.85, 0.25, 0.2)
	var _accent_green = Color(0.3, 0.8, 0.35)
	var _accent_blue = Color(0.3, 0.55, 0.9)
	var hover_color = Color(0.25, 0.2, 0.38)
	var pressed_color = Color(0.12, 0.09, 0.18)
	
	# === Default Font Size ===
	theme.set_default_font_size(14)
	
	# === Label ===
	theme.set_color("font_color", "Label", text_color)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	
	# === Button ===
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = bg_medium
	btn_normal.border_color = border_color
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(2)
	btn_normal.set_content_margin_all(8)
	theme.set_stylebox("normal", "Button", btn_normal)
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = hover_color
	btn_hover.border_color = border_highlight
	theme.set_stylebox("hover", "Button", btn_hover)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = pressed_color
	btn_pressed.border_color = accent_gold
	theme.set_stylebox("pressed", "Button", btn_pressed)
	
	var btn_disabled = btn_normal.duplicate()
	btn_disabled.bg_color = Color(0.1, 0.08, 0.14)
	btn_disabled.border_color = Color(0.25, 0.2, 0.3)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	
	theme.set_color("font_color", "Button", text_color)
	theme.set_color("font_hover_color", "Button", accent_gold)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", text_dim)
	theme.set_font_size("font_size", "Button", 14)
	
	# === Panel ===
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = bg_dark
	panel_style.border_color = border_color
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(2)
	panel_style.set_content_margin_all(6)
	theme.set_stylebox("panel", "Panel", panel_style)
	
	var panel_card = StyleBoxFlat.new()
	panel_card.bg_color = Color(0.12, 0.1, 0.18)
	panel_card.border_color = Color(0.35, 0.3, 0.5)
	panel_card.set_border_width_all(1)
	panel_card.set_corner_radius_all(3)
	panel_card.set_content_margin_all(4)
	theme.set_stylebox("panel", "PanelContainer", panel_card)
	
	# === ProgressBar (HP bar) ===
	var pb_bg = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.15, 0.08, 0.08)
	pb_bg.border_color = Color(0.4, 0.15, 0.15)
	pb_bg.set_border_width_all(1)
	pb_bg.set_corner_radius_all(1)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	
	var pb_fill = StyleBoxFlat.new()
	pb_fill.bg_color = accent_red
	pb_fill.set_corner_radius_all(1)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)
	
	# === RichTextLabel (battle log) ===
	var rtl_bg = StyleBoxFlat.new()
	rtl_bg.bg_color = Color(0.05, 0.04, 0.08, 0.9)
	rtl_bg.border_color = Color(0.3, 0.25, 0.4)
	rtl_bg.set_border_width_all(1)
	rtl_bg.set_corner_radius_all(2)
	rtl_bg.set_content_margin_all(6)
	theme.set_stylebox("normal", "RichTextLabel", rtl_bg)
	theme.set_color("default_color", "RichTextLabel", Color(0.75, 0.72, 0.65))
	theme.set_font_size("normal_font_size", "RichTextLabel", 11)
	
	# === HBoxContainer / VBoxContainer separations ===
	theme.set_constant("separation", "HBoxContainer", 6)
	theme.set_constant("separation", "VBoxContainer", 4)
	
	return theme

## Returns specialized card panel style based on card type
static func get_card_style(card_type: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	style.set_content_margin_all(4)
	
	match card_type:
		GameData.CardType.ATTACK:
			style.bg_color = Color(0.2, 0.08, 0.08)
			style.border_color = Color(0.7, 0.25, 0.2)
		GameData.CardType.DEFEND:
			style.bg_color = Color(0.08, 0.1, 0.2)
			style.border_color = Color(0.2, 0.35, 0.7)
		GameData.CardType.MAGIC:
			style.bg_color = Color(0.15, 0.06, 0.2)
			style.border_color = Color(0.55, 0.2, 0.7)
		GameData.CardType.HEAL:
			style.bg_color = Color(0.06, 0.15, 0.08)
			style.border_color = Color(0.2, 0.6, 0.3)
		GameData.CardType.DICE_BOOST:
			style.bg_color = Color(0.18, 0.15, 0.06)
			style.border_color = Color(0.7, 0.6, 0.2)
		_:
			style.bg_color = Color(0.12, 0.1, 0.18)
			style.border_color = Color(0.4, 0.35, 0.55)
	
	return style

static func get_dice_style(dice_type: String) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.set_border_width_all(2)
	style.set_content_margin_all(3)
	
	match dice_type:
		"fire":
			style.bg_color = Color(0.2, 0.06, 0.04)
			style.border_color = Color(0.8, 0.3, 0.15)
		"ice":
			style.bg_color = Color(0.04, 0.1, 0.2)
			style.border_color = Color(0.2, 0.5, 0.85)
		"poison":
			style.bg_color = Color(0.05, 0.15, 0.05)
			style.border_color = Color(0.2, 0.7, 0.2)
		_:
			style.bg_color = Color(0.18, 0.17, 0.15)
			style.border_color = Color(0.6, 0.58, 0.5)
	
	return style
