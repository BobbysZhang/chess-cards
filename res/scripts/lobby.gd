extends Control

@onready var btn_start: Button = $MarginContainer/VBoxContainer/BtnStart

func _ready() -> void:
	if btn_start:
		btn_start.pressed.connect(_on_start_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://res/scenes/game/table.tscn")
