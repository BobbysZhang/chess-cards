# Table — 对局场景：牌桌 UI、四家手牌/副露、牌库、当前打出的牌、操作按钮
extends Control

## 座位 0 为玩家，1～3 为 AI
const HUMAN_SEAT := 0

@onready var label_deck: Label = $TableUI/Center/GameInfo/DeckLabel
@onready var label_turn: Label = $TableUI/Center/GameInfo/TurnLabel
@onready var last_discard_from_label: Label = $TableUI/Center/LastDiscardFromLabel
@onready var last_discard_container: Control = $TableUI/Center/LastDiscard
@onready var discard_pile_container: HBoxContainer = $TableUI/Center/DiscardPileScroll/DiscardPile
@onready var other_seat_hand: Array[HBoxContainer] = [
	$TableUI/OtherPlayers/Seat1/Hand,
	$TableUI/OtherPlayers/Seat2/Hand,
	$TableUI/OtherPlayers/Seat3/Hand
]
@onready var other_seat_melds: Array[HBoxContainer] = [
	$TableUI/OtherPlayers/Seat1/Melds,
	$TableUI/OtherPlayers/Seat2/Melds,
	$TableUI/OtherPlayers/Seat3/Melds
]
@onready var player_hand: HBoxContainer = $TableUI/Bottom/PlayerHand
@onready var player_melds: HBoxContainer = $TableUI/Bottom/PlayerMelds
@onready var action_buttons: HBoxContainer = $TableUI/Bottom/ActionButtons
@onready var settlement_panel: PanelContainer = $SettlementPanel
@onready var settlement_label: Label = $SettlementPanel/Margin/VBox/ResultLabel
@onready var btn_back_lobby: Button = $SettlementPanel/Margin/VBox/BtnBackLobby
@onready var _ai_timer: Timer = $AITimer

var card_scene: PackedScene
var _ai_timer_pending: bool = false
## 本回合出牌阶段是否已摸牌（规则：下家先摸牌再出牌，人类也需先摸再出）
var _human_has_drawn_this_turn: bool = false

func _ready() -> void:
	card_scene = preload("res://res/scenes/card/card.tscn")
	_setup_action_buttons()
	if btn_back_lobby:
		btn_back_lobby.pressed.connect(_on_back_to_lobby)
	_ai_timer.timeout.connect(_on_ai_turn_timeout)
	GameState.round_ended.connect(_on_game_ended)
	GameState.state_changed.connect(_refresh_ui)
	GameState.new_game()
	_refresh_ui()
	_settlement_visible(false)

func _setup_action_buttons() -> void:
	if not action_buttons:
		return
	for c in action_buttons.get_children():
		if c is Button:
			var name_str := c.name.to_lower()
			if "hu" in name_str or "胡" in c.text:
				c.pressed.connect(_on_btn_hu)
			elif "pong" in name_str or "碰" in c.text:
				c.pressed.connect(_on_btn_pong)
			elif "kong" in name_str or "杠" in c.text:
				c.pressed.connect(_on_btn_kong)
			elif "claim" in name_str or "吃" in c.text:
				c.pressed.connect(_on_btn_claim)
			elif "pass" in name_str or "过" in c.text:
				c.pressed.connect(_on_btn_pass)

func _refresh_ui() -> void:
	# 非「轮到玩家出牌」阶段时重置“已摸牌”标记，确保下次轮到时先摸再出
	if GameState.current_player != HUMAN_SEAT or GameState.waiting_for_response:
		_human_has_drawn_this_turn = false
	if label_deck:
		label_deck.text = "牌库: %d" % GameState.deck.size()
	if label_turn:
		if GameState.waiting_for_response and GameState.response_order.size() > 0:
			var resp_seat: int = GameState.response_order[0]
			var who_resp := "你" if resp_seat == HUMAN_SEAT else "玩家%d" % (resp_seat + 1)
			label_turn.text = "%s 响应中…" % who_resp
		else:
			var who := "你" if GameState.current_player == HUMAN_SEAT else "玩家%d" % (GameState.current_player + 1)
			label_turn.text = "当前: %s" % who
	# 规则 4.1/4.3：轮到玩家出牌时，先摸牌再出牌（第一手、碰/杠后只出牌不摸）
	if GameState.current_player == HUMAN_SEAT and not GameState.waiting_for_response:
		if not _human_has_drawn_this_turn and not GameState.must_discard_only and GameState.last_discard_seat >= 0 and GameState.deck.size() > 0:
			GameState.draw_from_deck(HUMAN_SEAT)
			_human_has_drawn_this_turn = true
	_refresh_player_hand()
	_refresh_player_melds()
	_refresh_other_players()
	_refresh_last_discard()
	_refresh_discard_pile()
	_update_action_buttons_visibility()
	if GameState.game_ended:
		_ai_timer_pending = false
		return
	if _ai_timer_pending:
		print("[Table] _refresh_ui: skip start timer, pending=true")
		return
	if GameState.waiting_for_response:
		if GameState.response_order.size() > 0 and GameState.response_order[0] != HUMAN_SEAT:
			print("[Table] _refresh_ui: defer start timer (response phase, next=玩家%d)" % (GameState.response_order[0] + 1))
			call_deferred("_start_ai_timer")
		else:
			print("[Table] _refresh_ui: response phase but no AI in line, order=%s" % str(GameState.response_order))
	elif GameState.current_player != HUMAN_SEAT:
		print("[Table] _refresh_ui: defer start timer (discard phase, current=玩家%d)" % (GameState.current_player + 1))
		call_deferred("_start_ai_timer")

func _start_ai_timer() -> void:
	if _ai_timer_pending:
		print("[Table] _start_ai_timer: skip, already pending")
		return
	if not _ai_timer:
		print("[Table] _start_ai_timer: ERROR _ai_timer is null")
		return
	_ai_timer_pending = true
	_ai_timer.start(0.6)
	print("[Table] _start_ai_timer: started 0.6s")

func _on_ai_turn_timeout() -> void:
	print("[Table] _on_ai_turn_timeout: fired")
	_ai_timer_pending = false
	_on_ai_turn()

func _refresh_player_hand() -> void:
	if not player_hand:
		return
	for c in player_hand.get_children():
		c.queue_free()
	var hand: Array = GameState.hands[HUMAN_SEAT]
	for i in range(hand.size()):
		var card_data: Dictionary = hand[i]
		var card_node: Button = card_scene.instantiate() as Button
		player_hand.add_child(card_node)
		if card_node.has_method("set_card"):
			card_node.set_card(card_data)
		var idx := i
		# 轮到玩家出牌（非响应阶段）时可点击出牌；摸牌后必须打出刚摸到的那张
		var can_play: bool = GameState.current_player == HUMAN_SEAT and not GameState.waiting_for_response
		if can_play and GameState.last_drawn_seat == HUMAN_SEAT and not GameState.last_drawn_card.is_empty():
			can_play = GameRules.card_equals(card_data, GameState.last_drawn_card)
		if can_play:
			card_node.disabled = false
			card_node.pressed.connect(_on_play_card.bind(idx))
		else:
			card_node.disabled = true

func _refresh_player_melds() -> void:
	if not player_melds:
		return
	for c in player_melds.get_children():
		c.queue_free()
	for meld in GameState.melds[HUMAN_SEAT]:
		var tiles: Array = meld.get("tiles", [])
		for tile in tiles:
			var card_node: Control = card_scene.instantiate()
			player_melds.add_child(card_node)
			if card_node.has_method("set_card"):
				card_node.set_card(tile)

func _refresh_other_players() -> void:
	for seat in range(1, 4):
		var hand_container: HBoxContainer = other_seat_hand[seat - 1]
		var melds_container: HBoxContainer = other_seat_melds[seat - 1]
		if not hand_container or not melds_container:
			continue
		for c in hand_container.get_children():
			c.queue_free()
		for c in melds_container.get_children():
			c.queue_free()
		var hand: Array = GameState.hands[seat]
		for _i in range(hand.size()):
			var card_node: Button = card_scene.instantiate() as Button
			hand_container.add_child(card_node)
			card_node.set_face_down(true)
			card_node.disabled = true
		for meld in GameState.melds[seat]:
			var tiles: Array = meld.get("tiles", [])
			for tile in tiles:
				var card_node: Control = card_scene.instantiate()
				melds_container.add_child(card_node)
				if card_node.has_method("set_card"):
					card_node.set_card(tile)
				if card_node is Button:
					card_node.disabled = true

func _refresh_last_discard() -> void:
	if last_discard_from_label:
		if GameState.last_discard_seat >= 0:
			var who := "你" if GameState.last_discard_seat == HUMAN_SEAT else "玩家%d" % (GameState.last_discard_seat + 1)
			last_discard_from_label.text = "%s 出牌" % who
		else:
			last_discard_from_label.text = ""
	if not last_discard_container:
		return
	for c in last_discard_container.get_children():
		c.queue_free()
	if GameState.last_discard.is_empty():
		return
	var card_node: Control = card_scene.instantiate()
	last_discard_container.add_child(card_node)
	if card_node.has_method("set_card"):
		card_node.set_card(GameState.last_discard)
	if card_node is Button:
		card_node.disabled = true

func _refresh_discard_pile() -> void:
	if not discard_pile_container:
		return
	for c in discard_pile_container.get_children():
		c.queue_free()
	var history: Array = GameState.discard_history
	const MAX_SHOW := 28
	var start_idx := 0
	if history.size() > MAX_SHOW:
		start_idx = history.size() - MAX_SHOW
	for i in range(start_idx, history.size()):
		var entry: Dictionary = history[i]
		var card: Dictionary = entry.get("card", {})
		if card.is_empty():
			continue
		var card_node: Control = card_scene.instantiate()
		discard_pile_container.add_child(card_node)
		if card_node.has_method("set_card"):
			card_node.set_card(card)
		if card_node is Button:
			card_node.disabled = true

func _update_action_buttons_visibility() -> void:
	if not action_buttons:
		return
	var can_respond: bool = GameState.waiting_for_response and HUMAN_SEAT in GameState.response_order
	for c in action_buttons.get_children():
		if c is Button:
			var name_str := c.name.to_lower()
			var show_btn := false
			if can_respond:
				if "hu" in name_str or "胡" in c.text:
					show_btn = GameState.can_hu(HUMAN_SEAT)
				elif "pong" in name_str or "碰" in c.text:
					show_btn = GameState.can_pong(HUMAN_SEAT)
				elif "kong" in name_str or "杠" in c.text:
					show_btn = GameState.can_kong(HUMAN_SEAT)
				elif "claim" in name_str or "吃" in c.text:
					show_btn = GameState.can_claim(HUMAN_SEAT)
				elif "pass" in name_str or "过" in c.text:
					show_btn = true  # 过：轮到响应时始终显示，以便放弃
			# 自己吃摸出来的牌：出牌阶段且刚摸牌时也可选吃该张
			if ("claim" in name_str or "吃" in c.text) and not show_btn:
				if GameState.current_player == HUMAN_SEAT and not GameState.waiting_for_response and GameState.can_claim_own_draw(HUMAN_SEAT):
					show_btn = true
			c.visible = show_btn

func _on_play_card(hand_index: int) -> void:
	if GameState.current_player != HUMAN_SEAT or GameState.waiting_for_response:
		return
	print("[Table] 你出牌 hand_index=%d" % hand_index)
	GameState.play_discard(HUMAN_SEAT, hand_index)

func _on_btn_hu() -> void:
	GameState.do_hu(HUMAN_SEAT)

func _on_btn_pong() -> void:
	GameState.do_pong(HUMAN_SEAT)

func _on_btn_kong() -> void:
	GameState.do_kong(HUMAN_SEAT)

func _on_btn_claim() -> void:
	# 自己吃摸出来的牌
	if GameState.can_claim_own_draw(HUMAN_SEAT):
		var indices: Array = GameState.get_claim_own_draw_hand_indices(HUMAN_SEAT)
		if indices.size() >= 2:
			GameState.do_claim_own_draw(HUMAN_SEAT, indices)
		return
	# 响应阶段吃上家牌（取第一组可用组合）
	if GameState.can_claim(HUMAN_SEAT):
		var indices: Array = GameState.get_claim_response_hand_indices(HUMAN_SEAT)
		if indices.size() >= 2:
			var hand: Array = GameState.hands[HUMAN_SEAT]
			var tiles: Array = [GameState.last_discard, hand[indices[0]], hand[indices[1]]]
			var meld_type: int = GameRules.get_claim_meld_type(tiles)
			if meld_type >= 0:
				GameState.do_claim(HUMAN_SEAT, meld_type, indices)

func _on_btn_pass() -> void:
	GameState.pass_response(HUMAN_SEAT)

func _on_ai_turn() -> void:
	if GameState.game_ended:
		print("[Table] _on_ai_turn: game ended, return")
		return
	if GameState.waiting_for_response:
		print("[Table] _on_ai_turn: response phase")
		_ai_response()
		return
	if GameState.current_player == HUMAN_SEAT:
		print("[Table] _on_ai_turn: current=human, return")
		return
	print("[Table] _on_ai_turn: discard phase, seat=%d" % GameState.current_player)
	_ai_discard()

func _ai_response() -> void:
	if GameState.response_order.is_empty():
		print("[Table] _ai_response: response_order empty, return")
		return
	var seat: int = GameState.response_order[0]
	print("[Table] _ai_response: seat=玩家%d" % (seat + 1))
	if GameState.do_hu(seat):
		print("[Table] _ai_response: 胡")
		return
	if GameState.do_kong(seat):
		print("[Table] _ai_response: 杠")
		return
	if GameState.do_pong(seat):
		print("[Table] _ai_response: 碰")
		return
	# 自己吃优先于下家吃（response_order 已含出牌者在前），碰杠胡已优先
	if GameState.can_claim(seat):
		var indices: Array = GameState.get_claim_response_hand_indices(seat)
		if indices.size() >= 2:
			var hand: Array = GameState.hands[seat]
			var tiles: Array = [GameState.last_discard, hand[indices[0]], hand[indices[1]]]
			var meld_type: int = GameRules.get_claim_meld_type(tiles)
			if meld_type >= 0 and GameState.do_claim(seat, meld_type, indices):
				print("[Table] _ai_response: 吃")
				return
	print("[Table] _ai_response: 过")
	GameState.pass_response(seat)

func _ai_discard() -> void:
	var seat: int = GameState.current_player
	# 规则 4.1/4.3：下家先摸牌再出牌；第一手（last_discard_seat<0）不摸牌；碰/杠后只出牌不摸牌
	if not GameState.must_discard_only and GameState.last_discard_seat >= 0 and GameState.deck.size() > 0:
		GameState.draw_from_deck(seat)
	# 自己吃摸出来的牌：若可与手牌组成吃则先吃，再出牌
	if GameState.can_claim_own_draw(seat):
		var indices: Array = GameState.get_claim_own_draw_hand_indices(seat)
		if indices.size() >= 2 and GameState.do_claim_own_draw(seat, indices):
			return  # state_changed 会触发刷新并再次启动 AI 计时器，接着出牌
	var hand: Array = GameState.hands[seat]
	# 摸牌后必须打出刚摸到的那张，再询问他人碰杠胡
	if GameState.last_drawn_seat == seat and not GameState.last_drawn_card.is_empty():
		for i in range(hand.size()):
			if GameRules.card_equals(hand[i], GameState.last_drawn_card) and GameRules.can_discard(hand[i]):
				GameState.play_discard(seat, i)
				return
		# 若摸到将/帅等不可打出，仍打第一张可出的（规则简化）
		GameState.last_drawn_seat = -1
		GameState.last_drawn_card = {}
	for i in range(hand.size()):
		if GameRules.can_discard(hand[i]):
			GameState.play_discard(seat, i)
			return
	GameState.check_draw()
	_refresh_ui()

func _on_game_ended(winner: int, is_draw: bool, hu_points: int, false_win: bool) -> void:
	_settlement_visible(true)
	if is_draw:
		settlement_label.text = "流局"
	elif false_win:
		settlement_label.text = "相公（胡数不足）"
	else:
		settlement_label.text = "玩家%d 胡牌，%d 胡" % [winner + 1, hu_points]

func _settlement_visible(show: bool) -> void:
	if settlement_panel:
		settlement_panel.visible = show

func _on_back_to_lobby() -> void:
	get_tree().change_scene_to_file("res://res/scenes/lobby/lobby.tscn")
