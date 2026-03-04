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

func _update_label() -> void:
	if face_down or _card_data.is_empty():
		text = "背"
		return
	var s: String = GameRules.suit_name(_card_data.get("suit", 0))
	var r: String = GameRules.rank_name(_card_data.get("rank", 0))
	text = s + r

func _ready() -> void:
	pass
