## Map screen - shows dungeon floor layout, lets player pick rooms
extends Node2D

const CELL_SIZE = 80
const OFFSET = Vector2(120, 60)

const SHOP_HEAL_COST = 20
const SHOP_REMOVE_COST = 75

var floor_data: Dictionary = {}
var room_buttons: Dictionary = {}  # Vector2i -> Button
var _popup_layer: Control = null

@onready var map_container = $MapContainer
@onready var floor_label = $UI/TopPanel/HBox/FloorLabel
@onready var stats_label = $UI/TopPanel/HBox/StatsLabel
@onready var deck_label = $UI/TopPanel/HBox/DeckLabel
@onready var back_button = $UI/BackButton

func _ready():
	back_button.theme = ThemeGen.create_game_theme()
	back_button.text = Loc.t("menu")
	back_button.pressed.connect(_on_back)
	var legend = get_node_or_null("UI/Legend")
	if legend:
		legend.text = Loc.t("legend")
	generate_map()
	VFX.fade_in(0.3)

func generate_map():
	floor_data = DungeonGenerator.generate_floor(GameState.current_floor, GameState.map_seed)
	GameState.current_room = floor_data.start
	_draw_map()

func _draw_map():
	for child in map_container.get_children():
		child.queue_free()
	room_buttons.clear()
	
	floor_label.text = Loc.tf("floor", [GameState.current_floor, GameState.max_floors])
	stats_label.text = Loc.tf("stats", [GameState.player_hp, GameState.player_max_hp, GameState.player_gold])
	if deck_label:
		deck_label.text = Loc.tf("deck_info", [GameState.deck.size() + GameState.discard.size(), GameState.dice_pool.size()])
	
	# Draw relic icons in top bar area
	_draw_relic_bar()
	
	var rooms = floor_data.rooms
	
	# Draw connections
	for pos in rooms:
		var room = rooms[pos]
		for conn in room.connections:
			var line = Line2D.new()
			line.width = 2
			line.default_color = Color(0.4, 0.35, 0.5)
			line.add_point(OFFSET + Vector2(pos.x * CELL_SIZE + CELL_SIZE / 2.0, pos.y * CELL_SIZE + CELL_SIZE / 2.0))
			line.add_point(OFFSET + Vector2(conn.x * CELL_SIZE + CELL_SIZE / 2.0, conn.y * CELL_SIZE + CELL_SIZE / 2.0))
			map_container.add_child(line)
	
	# Draw rooms
	for pos in rooms:
		var room = rooms[pos]
		var btn = Button.new()
		btn.position = OFFSET + Vector2(pos.x * CELL_SIZE + 10, pos.y * CELL_SIZE + 10)
		btn.size = Vector2(CELL_SIZE - 20, CELL_SIZE - 20)
		btn.add_theme_font_size_override("font_size", 20)
		
		var icons = {
			DungeonGenerator.RoomType.EMPTY: "○",
			DungeonGenerator.RoomType.ENEMY: "👹",
			DungeonGenerator.RoomType.ELITE: "💀",
			DungeonGenerator.RoomType.BOSS: "👑",
			DungeonGenerator.RoomType.TREASURE: "💎",
			DungeonGenerator.RoomType.REST: "🔥",
			DungeonGenerator.RoomType.SHOP: "🛒",
			DungeonGenerator.RoomType.EVENT: "❓",
		}
		btn.text = icons.get(room.type, "?")
		
		if room.visited and room.cleared:
			btn.modulate = Color(0.4, 0.4, 0.4, 0.6)
		elif pos == GameState.current_room:
			btn.modulate = Color(1, 0.9, 0.5)
			var tw = create_tween().set_loops(50)
			tw.tween_property(btn, "modulate:a", 0.7, 0.6).set_trans(Tween.TRANS_SINE)
			tw.tween_property(btn, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		elif _is_adjacent(pos, GameState.current_room):
			btn.modulate = Color(0.9, 0.9, 0.95)
		else:
			btn.modulate = Color(0.45, 0.4, 0.5, 0.7)
			btn.disabled = true
		
		btn.pressed.connect(_on_room_clicked.bind(pos))
		map_container.add_child(btn)
		room_buttons[pos] = btn

func _draw_relic_bar():
	# Remove old relic bar if present
	var old_bar = get_node_or_null("UI/RelicBar")
	if old_bar:
		old_bar.queue_free()
	if GameState.relics.is_empty():
		return
	var relic_bar = HBoxContainer.new()
	relic_bar.name = "RelicBar"
	relic_bar.offset_left = 10.0
	relic_bar.offset_top = 42.0
	relic_bar.offset_right = 500.0
	relic_bar.offset_bottom = 62.0
	relic_bar.add_theme_constant_override("separation", 4)
	$UI.add_child(relic_bar)
	
	var prefix = Label.new()
	prefix.text = "🏺"
	prefix.add_theme_font_size_override("font_size", 12)
	relic_bar.add_child(prefix)
	
	for relic_id in GameState.relics:
		var rdef = RelicData.RELICS.get(relic_id)
		if not rdef:
			continue
		var tex = TextureRect.new()
		tex.texture = load(rdef.texture_path)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(18, 18)
		tex.tooltip_text = Loc.t(rdef.name_key) + ": " + Loc.t(rdef.desc_key)
		relic_bar.add_child(tex)

func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var rooms = floor_data.rooms
	if rooms.has(b):
		return rooms[b].connections.has(a)
	return false

func _on_room_clicked(pos: Vector2i):
	if not _is_adjacent(pos, GameState.current_room) and pos != GameState.current_room:
		return
	
	var room = floor_data.rooms[pos]
	if room.cleared and room.type != DungeonGenerator.RoomType.SHOP:
		return
	
	GameState.current_room = pos
	room.visited = true
	
	match room.type:
		DungeonGenerator.RoomType.ENEMY, DungeonGenerator.RoomType.ELITE, DungeonGenerator.RoomType.BOSS:
			_enter_battle(room)
		DungeonGenerator.RoomType.TREASURE:
			_open_treasure(room)
		DungeonGenerator.RoomType.REST:
			_open_rest(room)
		DungeonGenerator.RoomType.SHOP:
			_open_shop(room)
		DungeonGenerator.RoomType.EVENT:
			_trigger_event(room)
		_:
			room.cleared = true
			_draw_map()

# ============================================================
#  POPUP SYSTEM
# ============================================================

func _clear_popup():
	if _popup_layer and is_instance_valid(_popup_layer):
		_popup_layer.queue_free()
		_popup_layer = null

## Creates a modal popup overlay and returns the VBoxContainer for content.
func _create_popup(title_text: String, width: float = 520.0, height: float = 420.0) -> VBoxContainer:
	_clear_popup()
	
	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UI.add_child(_popup_layer)
	
	var overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_layer.add_child(overlay)
	
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(width, height)
	panel.position = Vector2(-width / 2.0, -height / 2.0)
	_popup_layer.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)
	
	var title = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	return vbox

func _close_popup_and_finish(room):
	_clear_popup()
	room.cleared = true
	_draw_map()

func _card_name(card_id: String) -> String:
	var key = "card_" + card_id
	if Loc.has_key(key):
		return Loc.t(key)
	var cdef = GameData.CARDS.get(card_id)
	if cdef:
		return cdef.name
	return card_id

func _dice_name(dice_id: String) -> String:
	var key = "dice_" + dice_id
	if Loc.has_key(key):
		return Loc.t(key)
	return dice_id

# ============================================================
#  BATTLE
# ============================================================

func _enter_battle(room):
	await VFX.fade_out(0.3)
	visible = false
	$UI.visible = false
	
	var battle_scene = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle_scene)
	battle_scene.start_battle(room.enemies)
	
	battle_scene.battle_won.connect(func(rewards):
		room.cleared = true
		GameState.add_gold(rewards.gold)
		for card_id in rewards.cards:
			GameState.add_card_to_deck(card_id)
		if rewards.dice != "":
			GameState.add_dice(rewards.dice)
		battle_scene.queue_free()
		
		visible = true
		$UI.visible = true
		
		# Show rewards popup
		_show_rewards(room, rewards)
	)
	battle_scene.battle_lost.connect(func():
		battle_scene.queue_free()
		get_tree().change_scene_to_file("res://scenes/main/game_over.tscn")
	)

func _show_rewards(room, rewards: Dictionary):
	var vbox = _create_popup(Loc.t("rewards_title"), 440, 360)
	
	# Gold
	var gold_lbl = Label.new()
	gold_lbl.text = Loc.tf("rewards_gold", [rewards.gold])
	gold_lbl.add_theme_font_size_override("font_size", 16)
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	vbox.add_child(gold_lbl)
	
	# Cards
	for card_id in rewards.cards:
		var card_lbl = Label.new()
		card_lbl.text = Loc.tf("rewards_card", [_card_name(card_id)])
		card_lbl.add_theme_font_size_override("font_size", 14)
		card_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1))
		vbox.add_child(card_lbl)
	
	# Dice
	if rewards.dice != "":
		var dice_lbl = Label.new()
		dice_lbl.text = Loc.tf("rewards_dice", [_dice_name(rewards.dice)])
		dice_lbl.add_theme_font_size_override("font_size", 14)
		dice_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
		vbox.add_child(dice_lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)
	
	var relic_choices: Array = rewards.get("relic_choices", [])
	
	var continue_btn = Button.new()
	continue_btn.text = Loc.t("rewards_continue")
	continue_btn.custom_minimum_size = Vector2(200, 40)
	continue_btn.add_theme_font_size_override("font_size", 16)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(continue_btn)
	
	continue_btn.pressed.connect(func():
		_clear_popup()
		if relic_choices.size() > 0:
			_show_relic_choice(relic_choices, func():
				_after_battle_finish(room)
			)
		else:
			_after_battle_finish(room)
	)

func _after_battle_finish(room):
	# Check if boss killed -> next floor
	if room.type == DungeonGenerator.RoomType.BOSS:
		GameState.next_floor()
		if GameState.is_victory():
			get_tree().change_scene_to_file("res://scenes/main/victory_screen.tscn")
			return
		generate_map()
	_draw_map()
	VFX.fade_in(0.3)

# ============================================================
#  RELIC CHOICE (used after boss/elite battles)
# ============================================================

func _show_relic_choice(relic_ids: Array, on_done: Callable):
	if relic_ids.is_empty():
		on_done.call()
		return
	
	var vbox = _create_popup(Loc.t("relic_choice_title"), 560, 380)
	
	var relics_row = HBoxContainer.new()
	relics_row.add_theme_constant_override("separation", 16)
	relics_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(relics_row)
	
	for relic_id in relic_ids:
		var rdef = RelicData.RELICS.get(relic_id)
		if not rdef:
			continue
		
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(140, 200)
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.12, 0.1, 0.18)
		card_style.border_color = RelicData.rarity_color(rdef.rarity)
		card_style.set_border_width_all(2)
		card_style.set_corner_radius_all(4)
		card_style.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", card_style)
		relics_row.add_child(card)
		
		var cvbox = VBoxContainer.new()
		cvbox.alignment = BoxContainer.ALIGNMENT_CENTER
		cvbox.add_theme_constant_override("separation", 6)
		card.add_child(cvbox)
		
		# Rarity tag
		var rarity_lbl = Label.new()
		rarity_lbl.text = RelicData.rarity_tag(rdef.rarity)
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rarity_lbl.add_theme_font_size_override("font_size", 16)
		cvbox.add_child(rarity_lbl)
		
		# Icon
		var tex = TextureRect.new()
		tex.texture = load(rdef.texture_path)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(48, 48)
		cvbox.add_child(tex)
		
		# Name
		var name_lbl = Label.new()
		name_lbl.text = Loc.t(rdef.name_key)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", RelicData.rarity_color(rdef.rarity))
		cvbox.add_child(name_lbl)
		
		# Description
		var desc_lbl = Label.new()
		desc_lbl.text = Loc.t(rdef.desc_key)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(120, 0)
		cvbox.add_child(desc_lbl)
		
		# Pick button
		var pick_btn = Button.new()
		pick_btn.text = Loc.t("treasure_take")
		pick_btn.add_theme_font_size_override("font_size", 12)
		pick_btn.custom_minimum_size = Vector2(80, 28)
		pick_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cvbox.add_child(pick_btn)
		
		pick_btn.pressed.connect(func():
			GameState.add_relic(relic_id)
			_clear_popup()
			on_done.call()
		)
	
	# Skip button
	var skip_btn = Button.new()
	skip_btn.text = Loc.t("relic_choice_skip")
	skip_btn.custom_minimum_size = Vector2(120, 32)
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(skip_btn)
	
	skip_btn.pressed.connect(func():
		_clear_popup()
		on_done.call()
	)

# ============================================================
#  SHOP
# ============================================================

func _open_shop(room):
	var vbox = _create_popup(Loc.t("shop_title"), 600, 460)
	
	# Gold display (updated dynamically)
	var gold_lbl = Label.new()
	gold_lbl.name = "GoldLabel"
	gold_lbl.text = Loc.tf("shop_gold", [GameState.player_gold])
	gold_lbl.add_theme_font_size_override("font_size", 16)
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gold_lbl)
	
	# Two columns
	var columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	vbox.add_child(columns)
	
	# === LEFT: Cards ===
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	
	var cards_title = Label.new()
	cards_title.text = Loc.t("shop_cards_section")
	cards_title.add_theme_font_size_override("font_size", 15)
	cards_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.9))
	left.add_child(cards_title)
	
	# Pick 3 random cards to offer
	var all_card_keys = GameData.CARDS.keys()
	all_card_keys.shuffle()
	var offered_cards = all_card_keys.slice(0, 3)
	
	for card_id in offered_cards:
		var cdef = GameData.CARDS.get(card_id)
		if not cdef:
			continue
		var cost = 15 + cdef.energy_cost * 8
		var btn = Button.new()
		btn.text = Loc.tf("shop_buy_card", [_card_name(card_id), cdef.energy_cost, cost])
		btn.custom_minimum_size = Vector2(240, 34)
		btn.add_theme_font_size_override("font_size", 13)
		left.add_child(btn)
		
		btn.pressed.connect(func():
			if GameState.player_gold >= cost:
				GameState.player_gold -= cost
				GameState.gold_changed.emit(GameState.player_gold)
				GameState.add_card_to_deck(card_id)
				gold_lbl.text = Loc.tf("shop_gold", [GameState.player_gold])
				btn.disabled = true
				btn.text = _card_name(card_id) + " — " + Loc.t("shop_sold")
		)
	
	# === RIGHT: Relics ===
	var right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	
	var relics_title = Label.new()
	relics_title.text = Loc.t("shop_relics_section")
	relics_title.add_theme_font_size_override("font_size", 15)
	relics_title.add_theme_color_override("font_color", Color(0.85, 0.82, 0.9))
	right.add_child(relics_title)
	
	# Pick 2 random relics (not BOSS rarity, not already owned)
	var offered_relics = RelicData.pick_for_shop(2, GameState.relics)
	
	if offered_relics.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = Loc.t("shop_no_relics")
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
		right.add_child(empty_lbl)
	
	for relic_id in offered_relics:
		var rdef = RelicData.RELICS.get(relic_id)
		if not rdef:
			continue
		var relic_row = HBoxContainer.new()
		relic_row.add_theme_constant_override("separation", 6)
		right.add_child(relic_row)
		
		# Icon
		var tex = TextureRect.new()
		tex.texture = load(rdef.texture_path)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(24, 24)
		relic_row.add_child(tex)
		
		var info_vbox = VBoxContainer.new()
		info_vbox.add_theme_constant_override("separation", 1)
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		relic_row.add_child(info_vbox)
		
		var relic_btn = Button.new()
		var rarity_str = RelicData.rarity_tag(rdef.rarity)
		relic_btn.text = Loc.tf("shop_buy_relic", [Loc.t(rdef.name_key), rarity_str, rdef.cost])
		relic_btn.add_theme_font_size_override("font_size", 12)
		relic_btn.custom_minimum_size = Vector2(220, 28)
		info_vbox.add_child(relic_btn)
		
		var desc_lbl = Label.new()
		desc_lbl.text = Loc.t(rdef.desc_key)
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.45))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(desc_lbl)
		
		relic_btn.pressed.connect(func():
			if GameState.player_gold >= rdef.cost:
				GameState.player_gold -= rdef.cost
				GameState.gold_changed.emit(GameState.player_gold)
				GameState.add_relic(relic_id)
				gold_lbl.text = Loc.tf("shop_gold", [GameState.player_gold])
				relic_btn.disabled = true
				relic_btn.text = Loc.t(rdef.name_key) + " — " + Loc.t("shop_sold")
		)
	
	# === Bottom actions ===
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)
	
	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 12)
	actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(actions_row)
	
	# Remove card button
	var remove_btn = Button.new()
	remove_btn.text = Loc.tf("shop_remove_card", [SHOP_REMOVE_COST])
	remove_btn.add_theme_font_size_override("font_size", 13)
	remove_btn.custom_minimum_size = Vector2(180, 36)
	actions_row.add_child(remove_btn)
	
	remove_btn.pressed.connect(func():
		if GameState.player_gold >= SHOP_REMOVE_COST:
			_clear_popup()
			_show_card_removal(room, func():
				# Re-open shop after card removal
				_open_shop(room)
			)
	)
	
	# Heal button
	var heal_btn = Button.new()
	heal_btn.text = Loc.tf("shop_heal", [SHOP_HEAL_COST])
	heal_btn.add_theme_font_size_override("font_size", 13)
	heal_btn.custom_minimum_size = Vector2(180, 36)
	actions_row.add_child(heal_btn)
	
	heal_btn.pressed.connect(func():
		if GameState.player_gold >= SHOP_HEAL_COST:
			GameState.player_gold -= SHOP_HEAL_COST
			GameState.gold_changed.emit(GameState.player_gold)
			GameState.heal(GameState.player_max_hp * 3 / 10)
			gold_lbl.text = Loc.tf("shop_gold", [GameState.player_gold])
			heal_btn.disabled = true
			heal_btn.text = Loc.t("shop_sold")
	)
	
	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = Loc.t("shop_leave")
	leave_btn.add_theme_font_size_override("font_size", 14)
	leave_btn.custom_minimum_size = Vector2(160, 40)
	leave_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(leave_btn)
	
	leave_btn.pressed.connect(func():
		_close_popup_and_finish(room)
	)

# ============================================================
#  CARD REMOVAL (sub-popup from shop)
# ============================================================

func _show_card_removal(room, on_done: Callable):
	var all_cards = GameState.get_all_deck_card_ids()
	if all_cards.is_empty():
		on_done.call()
		return
	
	var vbox = _create_popup(Loc.t("remove_card_title"), 480, 400)
	
	var card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(card_grid)
	
	# Count duplicates
	var card_counts: Dictionary = {}
	for cid in all_cards:
		card_counts[cid] = card_counts.get(cid, 0) + 1
	
	for card_id in card_counts:
		var cdef = GameData.CARDS.get(card_id)
		if not cdef:
			continue
		var count = card_counts[card_id]
		
		var card_btn = Button.new()
		var display_name = _card_name(card_id)
		if count > 1:
			display_name += " x%d" % count
		card_btn.text = display_name
		card_btn.add_theme_font_size_override("font_size", 12)
		card_btn.custom_minimum_size = Vector2(100, 32)
		card_grid.add_child(card_btn)
		
		card_btn.pressed.connect(func():
			GameState.player_gold -= SHOP_REMOVE_COST
			GameState.gold_changed.emit(GameState.player_gold)
			GameState.remove_card_from_deck(card_id)
			_clear_popup()
			on_done.call()
		)
	
	# Cancel
	var cancel_btn = Button.new()
	cancel_btn.text = Loc.t("back") if Loc.has_key("back") else "Back"
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.custom_minimum_size = Vector2(120, 34)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(cancel_btn)
	
	cancel_btn.pressed.connect(func():
		_clear_popup()
		on_done.call()
	)

# ============================================================
#  TREASURE
# ============================================================

func _open_treasure(room):
	var gold = randi_range(15, 40)
	GameState.add_gold(gold)
	
	var vbox = _create_popup(Loc.t("treasure_title"), 500, 420)
	
	# Gold found
	var gold_lbl = Label.new()
	gold_lbl.text = Loc.tf("treasure_gold_found", [gold])
	gold_lbl.add_theme_font_size_override("font_size", 16)
	gold_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(gold_lbl)
	
	# Possible dice
	var got_dice = ""
	if randf() < 0.3:
		var types = ["fire", "ice", "poison"]
		got_dice = types[randi() % types.size()]
		GameState.add_dice(got_dice)
		var dice_lbl = Label.new()
		dice_lbl.text = Loc.tf("treasure_dice_found", [_dice_name(got_dice)])
		dice_lbl.add_theme_font_size_override("font_size", 14)
		dice_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1))
		dice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(dice_lbl)
	
	# Choose one of 3 cards
	var choose_lbl = Label.new()
	choose_lbl.text = Loc.t("treasure_choose_card")
	choose_lbl.add_theme_font_size_override("font_size", 14)
	choose_lbl.add_theme_color_override("font_color", Color(0.8, 0.78, 0.7))
	choose_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(choose_lbl)
	
	var all_cards = GameData.CARDS.keys()
	all_cards.shuffle()
	var card_choices = all_cards.slice(0, 3)
	
	var cards_row = HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 12)
	cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(cards_row)
	
	for card_id in card_choices:
		var cdef = GameData.CARDS.get(card_id)
		if not cdef:
			continue
		
		var card_panel = PanelContainer.new()
		card_panel.custom_minimum_size = Vector2(120, 150)
		card_panel.add_theme_stylebox_override("panel", ThemeGen.get_card_style(cdef.type))
		cards_row.add_child(card_panel)
		
		var cvbox = VBoxContainer.new()
		cvbox.alignment = BoxContainer.ALIGNMENT_CENTER
		cvbox.add_theme_constant_override("separation", 4)
		card_panel.add_child(cvbox)
		
		# Cost row
		var cost_row = HBoxContainer.new()
		cvbox.add_child(cost_row)
		var cost_lbl = Label.new()
		cost_lbl.text = "%d⚡" % cdef.energy_cost
		cost_lbl.add_theme_font_size_override("font_size", 11)
		cost_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		cost_row.add_child(cost_lbl)
		if cdef.dice_slots > 0:
			var dice_slot_lbl = Label.new()
			dice_slot_lbl.text = "  🎲x%d" % cdef.dice_slots
			dice_slot_lbl.add_theme_font_size_override("font_size", 9)
			dice_slot_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
			cost_row.add_child(dice_slot_lbl)
		
		# Card icon
		var tex = TextureRect.new()
		tex.texture = load(cdef.texture_path)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(40, 48)
		cvbox.add_child(tex)
		
		# Name
		var name_lbl = Label.new()
		name_lbl.text = _card_name(card_id)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cvbox.add_child(name_lbl)
		
		# Description
		var desc_lbl = Label.new()
		desc_lbl.text = cdef.description.replace("{value}", str(cdef.base_value))
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(100, 0)
		cvbox.add_child(desc_lbl)
		
		# Take button
		var take_btn = Button.new()
		take_btn.text = Loc.t("treasure_take")
		take_btn.add_theme_font_size_override("font_size", 11)
		take_btn.custom_minimum_size = Vector2(70, 24)
		take_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cvbox.add_child(take_btn)
		
		take_btn.pressed.connect(func():
			GameState.add_card_to_deck(card_id)
			_close_popup_and_finish(room)
		)
	
	# Skip
	var skip_btn = Button.new()
	skip_btn.text = Loc.t("treasure_skip")
	skip_btn.add_theme_font_size_override("font_size", 13)
	skip_btn.add_theme_color_override("font_color", Color(0.5, 0.45, 0.4))
	skip_btn.custom_minimum_size = Vector2(100, 32)
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(skip_btn)
	
	skip_btn.pressed.connect(func():
		_close_popup_and_finish(room)
	)

# ============================================================
#  REST SITE
# ============================================================

func _open_rest(room):
	var heal_amount = GameState.player_max_hp * 3 / 10
	
	var vbox = _create_popup(Loc.t("rest_title"), 440, 320)
	
	# Description
	var desc = Label.new()
	desc.text = "💤"
	desc.add_theme_font_size_override("font_size", 28)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)
	
	var choices_row = HBoxContainer.new()
	choices_row.add_theme_constant_override("separation", 20)
	choices_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(choices_row)
	
	# Option A: Heal
	var heal_panel = PanelContainer.new()
	heal_panel.custom_minimum_size = Vector2(170, 140)
	choices_row.add_child(heal_panel)
	
	var heal_vbox = VBoxContainer.new()
	heal_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	heal_vbox.add_theme_constant_override("separation", 8)
	heal_panel.add_child(heal_vbox)
	
	var heal_title = Label.new()
	heal_title.text = Loc.t("rest_heal")
	heal_title.add_theme_font_size_override("font_size", 15)
	heal_title.add_theme_color_override("font_color", Color(0.3, 0.85, 0.35))
	heal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_vbox.add_child(heal_title)
	
	var heal_desc = Label.new()
	heal_desc.text = Loc.tf("rest_heal_desc", [heal_amount])
	heal_desc.add_theme_font_size_override("font_size", 12)
	heal_desc.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
	heal_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heal_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heal_vbox.add_child(heal_desc)
	
	var heal_btn = Button.new()
	heal_btn.text = Loc.t("rest_heal")
	heal_btn.add_theme_font_size_override("font_size", 14)
	heal_btn.custom_minimum_size = Vector2(140, 36)
	heal_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	heal_vbox.add_child(heal_btn)
	
	heal_btn.pressed.connect(func():
		GameState.heal(heal_amount)
		_close_popup_and_finish(room)
	)
	
	# Option B: Upgrade
	var upgrade_panel = PanelContainer.new()
	upgrade_panel.custom_minimum_size = Vector2(170, 140)
	choices_row.add_child(upgrade_panel)
	
	var upgrade_vbox = VBoxContainer.new()
	upgrade_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	upgrade_vbox.add_theme_constant_override("separation", 8)
	upgrade_panel.add_child(upgrade_vbox)
	
	var upgrade_title = Label.new()
	upgrade_title.text = Loc.t("rest_upgrade")
	upgrade_title.add_theme_font_size_override("font_size", 15)
	upgrade_title.add_theme_color_override("font_color", Color(0.4, 0.6, 1))
	upgrade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_vbox.add_child(upgrade_title)
	
	var upgrade_desc = Label.new()
	upgrade_desc.text = Loc.t("rest_upgrade_desc")
	upgrade_desc.add_theme_font_size_override("font_size", 12)
	upgrade_desc.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
	upgrade_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upgrade_vbox.add_child(upgrade_desc)
	
	var upgrade_btn = Button.new()
	upgrade_btn.text = Loc.t("rest_upgrade")
	upgrade_btn.add_theme_font_size_override("font_size", 14)
	upgrade_btn.custom_minimum_size = Vector2(140, 36)
	upgrade_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	upgrade_vbox.add_child(upgrade_btn)
	
	upgrade_btn.pressed.connect(func():
		_clear_popup()
		_show_card_upgrade(room)
	)

func _show_card_upgrade(room):
	var all_cards = GameState.get_all_deck_card_ids()
	if all_cards.is_empty():
		# No cards to upgrade, just heal instead
		GameState.heal(GameState.player_max_hp * 3 / 10)
		room.cleared = true
		_draw_map()
		return
	
	var vbox = _create_popup(Loc.t("rest_pick_card"), 520, 400)
	
	var card_grid = GridContainer.new()
	card_grid.columns = 4
	card_grid.add_theme_constant_override("h_separation", 8)
	card_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(card_grid)
	
	# Unique card IDs
	var seen: Dictionary = {}
	for card_id in all_cards:
		if seen.has(card_id):
			continue
		seen[card_id] = true
		
		var cdef = GameData.CARDS.get(card_id)
		if not cdef:
			continue
		var current_lvl = GameState.get_card_upgrade_level(card_id)
		
		var btn = Button.new()
		var label_text = _card_name(card_id)
		if current_lvl > 0:
			label_text += " +%d" % current_lvl
		label_text += "\n(%d → %d)" % [cdef.base_value + current_lvl * 2, cdef.base_value + (current_lvl + 1) * 2]
		btn.text = label_text
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(110, 50)
		card_grid.add_child(btn)
		
		btn.pressed.connect(func():
			GameState.upgrade_card(card_id)
			_close_popup_and_finish(room)
		)
	
	# Cancel - go back to rest choices
	var cancel_btn = Button.new()
	cancel_btn.text = Loc.t("back") if Loc.has_key("back") else "Back"
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.custom_minimum_size = Vector2(120, 34)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(cancel_btn)
	
	cancel_btn.pressed.connect(func():
		_clear_popup()
		_open_rest(room)
	)

# ============================================================
#  RANDOM EVENT
# ============================================================

func _trigger_event(room):
	var vbox = _create_popup(Loc.t("event_title"), 400, 280)
	
	var roll = randf()
	var event_text: String
	var event_color: Color
	
	if roll < 0.33:
		# Blessing
		GameState.player_max_hp += 5
		GameState.heal(5)
		event_text = Loc.t("event_blessing")
		event_color = Color(0.4, 0.9, 0.5)
	elif roll < 0.66:
		# Curse
		GameState.take_damage(5)
		event_text = Loc.t("event_curse")
		event_color = Color(0.9, 0.3, 0.25)
	else:
		# Gift
		GameState.add_dice("normal")
		event_text = Loc.t("event_gift")
		event_color = Color(0.5, 0.8, 1)
	
	var event_icon = Label.new()
	event_icon.text = "🔮"
	event_icon.add_theme_font_size_override("font_size", 36)
	event_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(event_icon)
	
	var desc_lbl = Label.new()
	desc_lbl.text = event_text
	desc_lbl.add_theme_font_size_override("font_size", 16)
	desc_lbl.add_theme_color_override("font_color", event_color)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc_lbl)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)
	
	var continue_btn = Button.new()
	continue_btn.text = Loc.t("event_continue")
	continue_btn.add_theme_font_size_override("font_size", 15)
	continue_btn.custom_minimum_size = Vector2(160, 40)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(continue_btn)
	
	continue_btn.pressed.connect(func():
		_close_popup_and_finish(room)
	)

# ============================================================
#  NAVIGATION
# ============================================================

func _on_back():
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")