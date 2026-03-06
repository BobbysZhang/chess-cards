# Card — 单张牌展示，支持 set_card(data) 与点击出牌
extends Button

const GameRules = preload("res://res/scripts/autoload/game_rules.gd")

var _card_data: Dictionary = {}
var face_down: bool = false

func set_card(data: Dictionary) -> void:
	_card_data = data
	_update_label()

func set_face_down(back: bool) -> void:
	face_down = back
	_update_label()

func get_card_data() -> Dictionary:
	return _card_data

func _make_card_style(bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = bg_color.darkened(0.2)
	return style

func _clear_card_style() -> void:
	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
	remove_theme_stylebox_override("pressed")
	remove_theme_stylebox_override("disabled")
	remove_theme_stylebox_override("focus")

func _update_label() -> void:
	if face_down or _card_data.is_empty():
		text = "背"
		_clear_card_style()
		remove_theme_color_override("font_color")
		remove_theme_color_override("font_hover_color")
		remove_theme_color_override("font_pressed_color")
		remove_theme_color_override("font_focus_color")
		remove_theme_color_override("font_disabled_color")
		return
	var suit: int = _card_data.get("suit", 0)
	var s: String = GameRules.suit_name(suit)
	var r: String = GameRules.rank_name(_card_data.get("rank", 0))
	text = s + r
	var suit_col: Color = GameRules.suit_color(suit)
	# 卡片背景按花色着色，文字保持深色以便辨认
	add_theme_stylebox_override("normal", _make_card_style(suit_col))
	add_theme_stylebox_override("hover", _make_card_style(suit_col.lightened(0.12)))
	add_theme_stylebox_override("pressed", _make_card_style(suit_col.darkened(0.15)))
	add_theme_stylebox_override("disabled", _make_card_style(suit_col.darkened(0.1)))
	add_theme_stylebox_override("focus", _make_card_style(suit_col))
	add_theme_color_override("font_color", Color(0.15, 0.15, 0.15))
	add_theme_color_override("font_hover_color", Color(0.15, 0.15, 0.15))
	add_theme_color_override("font_pressed_color", Color(0.2, 0.2, 0.2))
	add_theme_color_override("font_focus_color", Color(0.15, 0.15, 0.15))
	add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.25))

func _ready() -> void:
	pass
