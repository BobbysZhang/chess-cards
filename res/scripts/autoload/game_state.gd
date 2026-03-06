# GameState — 当前对局状态单例（参考 GAME_RULES.md）
# 四家手牌、副露、牌库、回合、庄家；发牌、出牌、摸牌、吃碰杠胡、结算。
extends Node

const GameRules = preload("res://res/scripts/autoload/game_rules.gd")

## 一局中四家手牌，每元素为 Array of card dict
var hands: Array = [[], [], [], []]
## 四家副露：每元素为 Array of meld dict，meld = { type, tiles: [] } 或 { type, tiles, from_seat }
var melds: Array = [[], [], [], []]
## 牌库（未发的牌）
var deck: Array = []
## 当前回合玩家座位 0..3
var current_player: int = 0
## 庄家座位
var dealer_seat: int = 0
## 最后打出的牌（用于响应）
var last_discard: Dictionary = {}
## 最后出牌者座位
var last_discard_seat: int = -1
## 是否处于「等待对 last_discard 响应」阶段（胡/杠/碰/吃）
var waiting_for_response: bool = false
## 响应优先权顺序：从 last_discard_seat 下家起顺时针
var response_order: Array = []
## 刚完成碰/杠，当前玩家只需出牌不摸牌
var must_discard_only: bool = false

## 对局是否已结束
var game_ended: bool = false
## 胡牌者座位（-1 表示流局或未结束）
var winner_seat: int = -1
## 相公（无效胡）
var false_win: bool = false
## 结算胡数（用于结算界面）
var final_hu_points: int = 0
## 本局第一张打出的牌（点花备用，牌库空时用）
var first_discard_of_round: Dictionary = {}
## 本局所有打出的牌（按顺序），每项 { "seat": int, "card": dict }，用于牌桌展示
var discard_history: Array = []
## 摸牌后必须打出该牌：刚摸牌的座位（-1 表示无）；该座位出牌时只能打出 last_drawn_card
var last_drawn_seat: int = -1
var last_drawn_card: Dictionary = {}
## 最后打出的牌是否来自「摸牌后打出」：是则出牌者可响应且自己吃优先于下家吃，否则出牌者不可响应、仅下家可吃
var last_discard_from_draw: bool = false

signal state_changed
signal game_started
signal round_ended(winner_seat: int, is_draw: bool, hu_points: int, false_win: bool)

func _ready() -> void:
	pass

## 新局：洗牌、发牌、设庄
func new_game() -> void:
	game_ended = false
	winner_seat = -1
	false_win = false
	final_hu_points = 0
	first_discard_of_round = {}
	hands = [[], [], [], []]
	melds = [[], [], [], []]
	deck = GameRules.create_deck()
	GameRules.shuffle_deck(deck)
	var result = GameRules.deal_cards(deck, dealer_seat)
	hands = result[0]
	deck = result[1]
	current_player = dealer_seat
	last_discard = {}
	last_discard_seat = -1
	waiting_for_response = false
	response_order = []
	must_discard_only = false
	discard_history.clear()
	last_drawn_seat = -1
	last_drawn_card = {}
	last_discard_from_draw = false
	game_started.emit()
	state_changed.emit()

## 设置庄家（下一局用，在 new_game 前调或 new_game 内用上次最后出牌者）
func set_dealer(seat: int) -> void:
	dealer_seat = seat

## 开始响应阶段：摸牌后打出则 [出牌者, 下家, 下下家]（自己可响应，自己吃>下家吃）；从手牌打出则仅 [下家, 下下家, 下下下家]（自己不可响应，仅下家可吃）
func _start_response_phase() -> void:
	waiting_for_response = true
	response_order.clear()
	if last_discard_from_draw:
		response_order.append(last_discard_seat)
	var s := GameRules.next_seat(last_discard_seat)
	var n: int = 3 if not last_discard_from_draw else 2
	for _i in range(n):
		response_order.append(s)
		s = GameRules.next_seat(s)
	state_changed.emit()

## 打出一张牌（手牌索引）。将/帅不可打出；摸牌后必须打出刚摸到的那张。
func play_discard(player_seat: int, hand_index: int) -> bool:
	if game_ended or waiting_for_response:
		return false
	if player_seat != current_player:
		return false
	if hand_index < 0 or hand_index >= hands[player_seat].size():
		return false
	var card: Dictionary = hands[player_seat][hand_index]
	if not GameRules.can_discard(card):
		return false
	# 摸牌后必须打出刚摸到的那张，询问他人碰杠胡；记录是否「摸牌后打出」以决定响应顺序与谁可吃
	var from_draw: bool = (last_drawn_seat == player_seat and not last_drawn_card.is_empty() and GameRules.card_equals(card, last_drawn_card))
	if last_drawn_seat == player_seat and not last_drawn_card.is_empty():
		if not GameRules.card_equals(card, last_drawn_card):
			return false
		last_drawn_seat = -1
		last_drawn_card = {}
	must_discard_only = false
	hands[player_seat].remove_at(hand_index)
	last_discard = card
	last_discard_seat = player_seat
	last_discard_from_draw = from_draw
	discard_history.append({"seat": player_seat, "card": card})
	if first_discard_of_round.is_empty():
		first_discard_of_round = card
	# 进入响应阶段
	_start_response_phase()
	state_changed.emit()
	return true

## 摸牌（从牌库顶摸一张）
func draw_from_deck(player_seat: int) -> Dictionary:
	if game_ended or waiting_for_response:
		return {}
	if player_seat != current_player:
		return {}
	if deck.is_empty():
		return {}
	var card: Dictionary = deck.pop_back()
	hands[player_seat].append(card)
	last_drawn_seat = player_seat
	last_drawn_card = card
	# 摸牌后当前玩家必须打出这张牌，打出后询问他人碰杠胡；若摸到将帅需特殊处理（简化：允许先摸再打）
	state_changed.emit()
	return card

## 放弃响应，轮到下家摸牌或继续
func pass_response(player_seat: int) -> void:
	if not waiting_for_response:
		return
	var idx := response_order.find(player_seat)
	if idx < 0:
		return
	# 从 response_order 移除该玩家，若所有人都 pass 则 current_player 下家摸牌
	response_order.remove_at(idx)
	if response_order.is_empty():
		waiting_for_response = false
		must_discard_only = false
		current_player = GameRules.next_seat(last_discard_seat)
		print("[GameState] pass_response: 玩家%d 过, order=%s, empty=%s" % [player_seat + 1, str(response_order), response_order.is_empty()])
	# 每次有人 pass 都通知 UI 刷新，以便继续轮到下一位或进入下家摸牌
	state_changed.emit()

## 检查某座位是否可执行胡（不修改状态）；从手牌打出时自己不能响应，摸牌后打出时自己可胡
func can_hu(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response or not responder_seat in response_order:
		return false
	if responder_seat == last_discard_seat and not last_discard_from_draw:
		return false  # 从手牌打出时自己不可操作
	if last_discard.is_empty():
		return false
	var hand_with_discard: Array = hands[responder_seat].duplicate()
	hand_with_discard.append(last_discard)
	var hu_result := _compute_hu(hand_with_discard, melds[responder_seat])
	return hu_result.can_hu

## 检查某座位是否可执行碰（手牌至少 2 张与 last_discard 相同）；从手牌打出时自己不可碰
func can_pong(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response or not responder_seat in response_order:
		return false
	if responder_seat == last_discard_seat and not last_discard_from_draw:
		return false
	if last_discard.is_empty():
		return false
	var count := 0
	for c in hands[responder_seat]:
		if GameRules.card_equals(c, last_discard):
			count += 1
	return count >= 2

## 检查某座位是否可执行杠（手牌至少 3 张与 last_discard 相同）；从手牌打出时自己不可杠
func can_kong(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response or not responder_seat in response_order:
		return false
	if responder_seat == last_discard_seat and not last_discard_from_draw:
		return false
	if last_discard.is_empty():
		return false
	var count := 0
	for c in hands[responder_seat]:
		if GameRules.card_equals(c, last_discard):
			count += 1
	return count >= 3

## 检查某座位是否可执行吃：只能吃上家打出的牌。吃 = 两张相同（成对）或 将士象/车马包/三色兵卒（三张）。
func can_claim(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response or not responder_seat in response_order:
		return false
	if last_discard.is_empty():
		return false
	# 吃 = 只能吃上家打的牌：previous_seat(responder)==last_discard_seat 表示「出牌者是我的上家」
	if not last_discard_from_draw:
		if GameRules.previous_seat(responder_seat) != last_discard_seat:
			return false
	else:
		if responder_seat != last_discard_seat and GameRules.previous_seat(responder_seat) != last_discard_seat:
			return false
	var hand: Array = hands[responder_seat]
	# 吃 = 两张相同：手牌一张与上家牌相同（将/帅不可吃成对）
	if GameRules.can_discard(last_discard):
		for i in range(hand.size()):
			if GameRules.card_equals(hand[i], last_discard):
				return true
	# 吃 = 三张：将士象、车马包、三色兵卒
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			if GameRules.is_valid_claim_meld([last_discard, hand[i], hand[j]]):
				return true
	return false

## 响应阶段吃上家牌：成对吃返回 [i]，三张吃返回 [i, j]
func get_claim_response_hand_indices(responder_seat: int) -> Array:
	var result: Array = []
	if not can_claim(responder_seat):
		return result
	var hand: Array = hands[responder_seat]
	# 优先三张组合
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			if GameRules.is_valid_claim_meld([last_discard, hand[i], hand[j]]):
				result.append(i)
				result.append(j)
				return result
	# 再试两张相同（成对吃）
	if GameRules.can_discard(last_discard):
		for i in range(hand.size()):
			if GameRules.card_equals(hand[i], last_discard):
				result.append(i)
				return result
	return result

## 检查是否可「自己吃摸出来的牌」：成对（手牌一张相同）或三张组合
func can_claim_own_draw(seat: int) -> bool:
	if game_ended or waiting_for_response:
		return false
	if last_drawn_seat != seat or last_drawn_card.is_empty():
		return false
	var hand: Array = hands[seat]
	if GameRules.can_discard(last_drawn_card):
		for i in range(hand.size()):
			if GameRules.card_equals(hand[i], last_drawn_card):
				return true
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			if GameRules.is_valid_claim_meld([last_drawn_card, hand[i], hand[j]]):
				return true
	return false

## 返回「自己吃摸出来的牌」时用的手牌索引：成对返回 [i]，三张返回 [i, j]
func get_claim_own_draw_hand_indices(seat: int) -> Array:
	var result: Array = []
	if last_drawn_seat != seat or last_drawn_card.is_empty():
		return result
	var hand: Array = hands[seat]
	for i in range(hand.size()):
		for j in range(i + 1, hand.size()):
			if GameRules.is_valid_claim_meld([last_drawn_card, hand[i], hand[j]]):
				result.append(i)
				result.append(j)
				return result
	if GameRules.can_discard(last_drawn_card):
		for i in range(hand.size()):
			if GameRules.card_equals(hand[i], last_drawn_card):
				result.append(i)
				return result
	return result

## 自己吃摸出来的牌：成对 used_hand_indices 为 [i]，三张为 [i, j]；然后必须出牌
func do_claim_own_draw(seat: int, used_hand_indices: Array) -> bool:
	if game_ended or waiting_for_response or seat != current_player:
		return false
	if last_drawn_seat != seat or last_drawn_card.is_empty():
		return false
	if used_hand_indices.is_empty():
		return false
	var hand: Array = hands[seat]
	var tiles: Array = [last_drawn_card]
	var to_remove: Array = []
	if used_hand_indices.size() == 1:
		var i0: int = used_hand_indices[0]
		if i0 < 0 or i0 >= hand.size():
			return false
		if not GameRules.card_equals(hand[i0], last_drawn_card) or not GameRules.can_discard(last_drawn_card):
			return false
		tiles.append(hand[i0])
		to_remove.append(i0)
	else:
		var i0: int = used_hand_indices[0]
		var i1: int = used_hand_indices[1]
		if i0 < 0 or i1 < 0 or i0 >= hand.size() or i1 >= hand.size() or i0 == i1:
			return false
		tiles = [last_drawn_card, hand[i0], hand[i1]]
		if not GameRules.is_valid_claim_meld(tiles):
			return false
		to_remove.append(i0)
		to_remove.append(i1)
	var meld_type: int = GameRules.MeldType.PAIR if tiles.size() == 2 else GameRules.get_claim_meld_type(tiles)
	if tiles.size() == 3 and meld_type < 0:
		return false
	var drawn_idx: int = hand.size() - 1
	for k in range(hand.size()):
		if GameRules.card_equals(hand[k], last_drawn_card):
			drawn_idx = k
			break
	to_remove.append(drawn_idx)
	to_remove.sort()
	for k in range(to_remove.size() - 1, -1, -1):
		hand.remove_at(to_remove[k])
	melds[seat].append({
		"type": meld_type,
		"tiles": tiles,
		"from_seat": seat
	})
	last_drawn_seat = -1
	last_drawn_card = {}
	must_discard_only = true
	state_changed.emit()
	return true

## 执行胡（叫胡）。返回是否成功；若成功会结束对局
func do_hu(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response:
		return false
	if not responder_seat in response_order:
		return false
	# 检查是否真的能胡：手牌+last_discard 能组成合法组合且胡数>=10（简化：先允许任何叫胡，再算胡数判相公）
	var hand_with_discard: Array = hands[responder_seat].duplicate()
	hand_with_discard.append(last_discard)
	var hu_result := _compute_hu(hand_with_discard, melds[responder_seat])
	if hu_result.can_hu:
		# 胡牌成功，加入最后一张
		hands[responder_seat].append(last_discard)
		last_discard = {}
		waiting_for_response = false
		game_ended = true
		if hu_result.points >= GameRules.MIN_HU_POINTS:
			winner_seat = responder_seat
			final_hu_points = hu_result.points
			false_win = false
		else:
			false_win = true
			final_hu_points = hu_result.points
		round_ended.emit(responder_seat, false, final_hu_points, false_win)
		state_changed.emit()
		return true
	return false

## 碰：三张相同
func do_pong(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response:
		return false
	if not responder_seat in response_order:
		return false
	var count := 0
	for c in hands[responder_seat]:
		if GameRules.card_equals(c, last_discard):
			count += 1
	if count < 2:
		return false
	# 取出两张 + last_discard 组成碰
	var taken: Array = []
	var left := 2
	for i in range(hands[responder_seat].size() - 1, -1, -1):
		if left > 0 and GameRules.card_equals(hands[responder_seat][i], last_discard):
			taken.append(hands[responder_seat][i])
			hands[responder_seat].remove_at(i)
			left -= 1
	taken.append(last_discard)
	melds[responder_seat].append({
		"type": GameRules.MeldType.PONG,
		"tiles": taken,
		"from_seat": last_discard_seat
	})
	last_discard = {}
	waiting_for_response = false
	current_player = responder_seat
	must_discard_only = true
	last_drawn_seat = -1
	last_drawn_card = {}
	state_changed.emit()
	return true

## 杠：四张相同（明杠：手牌三张+last_discard）
func do_kong(responder_seat: int) -> bool:
	if game_ended or not waiting_for_response:
		return false
	if not responder_seat in response_order:
		return false
	var count := 0
	for c in hands[responder_seat]:
		if GameRules.card_equals(c, last_discard):
			count += 1
	if count < 3:
		return false
	var taken: Array = []
	var left := 3
	for i in range(hands[responder_seat].size() - 1, -1, -1):
		if left > 0 and GameRules.card_equals(hands[responder_seat][i], last_discard):
			taken.append(hands[responder_seat][i])
			hands[responder_seat].remove_at(i)
			left -= 1
	taken.append(last_discard)
	melds[responder_seat].append({
		"type": GameRules.MeldType.KONG,
		"tiles": taken,
		"from_seat": last_discard_seat
	})
	last_discard = {}
	waiting_for_response = false
	current_player = responder_seat
	must_discard_only = true
	last_drawn_seat = -1
	last_drawn_card = {}
	state_changed.emit()
	return true

## 吃：成对吃 used_hand_indices 为 [i]，三张吃为 [i, j]
func do_claim(responder_seat: int, meld_type: int, used_hand_indices: Array) -> bool:
	if game_ended or not waiting_for_response:
		return false
	if responder_seat == last_discard_seat and not last_discard_from_draw:
		return false
	if responder_seat != last_discard_seat and GameRules.previous_seat(responder_seat) != last_discard_seat:
		return false
	if not responder_seat in response_order:
		return false
	if used_hand_indices.is_empty():
		return false
	var tiles: Array = [last_discard]
	var to_remove: Array = []
	for i in used_hand_indices:
		if i >= 0 and i < hands[responder_seat].size():
			tiles.append(hands[responder_seat][i])
			to_remove.append(i)
	# 成对吃：2 张；三张吃：3 张
	if tiles.size() != 2 and tiles.size() != 3:
		return false
	if tiles.size() == 2 and meld_type != GameRules.MeldType.PAIR:
		return false
	if tiles.size() == 3 and meld_type == GameRules.MeldType.PAIR:
		return false
	to_remove.sort()
	for i in range(to_remove.size() - 1, -1, -1):
		hands[responder_seat].remove_at(to_remove[i])
	melds[responder_seat].append({
		"type": meld_type,
		"tiles": tiles,
		"from_seat": last_discard_seat
	})
	last_discard = {}
	waiting_for_response = false
	current_player = responder_seat
	must_discard_only = true
	last_drawn_seat = -1
	last_drawn_card = {}
	state_changed.emit()
	return true

## 检查流局（牌库空且无人胡）
func check_draw() -> bool:
	if deck.is_empty() and not waiting_for_response:
		game_ended = true
		winner_seat = -1
		round_ended.emit(-1, true, 0, false)
		state_changed.emit()
		return true
	return false

## 简化胡牌判定：能否划分成合法组合且总胡数>=10
## 返回 { can_hu: bool, points: int }
func _compute_hu(hand: Array, existing_melds: Array) -> Dictionary:
	# 暴力枚举较复杂，这里做最小实现：只检查张数 3n+2（将牌型），且用简单组合凑 10 胡
	# 更完整实现应枚举所有划分方式
	if hand.size() % 3 != 2:
		return { "can_hu": false, "points": 0 }
	var total_hu := _count_melds_hu(existing_melds, true)
	var hand_hu := _count_hand_hu(hand)
	if hand_hu < 0:
		return { "can_hu": false, "points": 0 }
	total_hu += hand_hu
	return { "can_hu": total_hu >= GameRules.MIN_HU_POINTS, "points": total_hu }

func _count_melds_hu(melds_list: Array, is_exposed: bool) -> int:
	var total := 0
	for m in melds_list:
		var t: int = m.get("type", GameRules.MeldType.PAIR)
		var tiles: Array = m.get("tiles", [])
		var king_kong := (t == GameRules.MeldType.KONG and tiles.size() > 0 and GameRules.is_king(tiles[0]))
		total += GameRules.get_meld_hu_points(t, is_exposed, king_kong)
	return total

func _count_hand_hu(hand: Array) -> int:
	# 极简：只算已有成组的，未成组返回 0 胡但允许胡（或 -1 表示不能胡）
	# 这里返回一个估计值以便至少能触发胡牌流程
	var n := hand.size()
	if n % 3 != 2:
		return -1
	# 简化：若手牌>=2 张且能成对+若干组合，给一个基础分
	return 10
