# GameRules — 规则与常量（参考 docs/GAME_RULES.md）
# 牌型、发牌、组合类型、胡数表、合法性判断。
extends Node

## 花色（GAME_RULES 1.1）
enum Suit {
	RED,
	YELLOW,
	WHITE,
	GREEN
}

## 牌面（GAME_RULES 1.1 将/帅→卒/兵）
enum Rank {
	KING,     # 将/帅
	ADVISOR,  # 士/仕
	ELEPHANT, # 象/相
	ROOK,     # 车/俥
	HORSE,    # 马/傌
	CANNON,   # 包/炮
	PAWN      # 卒/兵
}

const SUIT_COUNT := 4
const RANK_COUNT := 7
const COPIES_PER_CARD := 4
const TOTAL_TILES := SUIT_COUNT * RANK_COUNT * COPIES_PER_CARD  # 112

## 每人每轮发牌数、轮数（GAME_RULES 三）
const DEAL_PER_ROUND := 7
const DEAL_ROUNDS := 3
const DEALER_HAND_SIZE := 21   # 7+7+7
const NON_DEALER_HAND_SIZE := 20  # 7+7+6

## 胡牌门槛（GAME_RULES 六）
const MIN_HU_POINTS := 10
const SCORE_MULTIPLIER := 1
const FALSE_WIN_PENALTY := 11

## 组合类型（GAME_RULES 五）
enum MeldType {
	PAIR,           # 对
	SINGLE_KING,    # 单张将/帅
	KING_ADVISOR_ELEPHANT,  # 将士象
	ROOK_HORSE_CANNON,      # 车马包
	THREE_PAWN,     # 三色兵卒
	FOUR_PAWN,      # 四色兵卒
	PONG,           # 碰
	KONG            # 杠
}

## 胡数表：手中 / 已亮出（GAME_RULES 七）
const HU_POINTS_IN_HAND := {
	MeldType.PAIR: 0,
	MeldType.SINGLE_KING: 1,
	MeldType.ROOK_HORSE_CANNON: 1,
	MeldType.KING_ADVISOR_ELEPHANT: 2,
	MeldType.PONG: 3,
	MeldType.THREE_PAWN: 3,
	MeldType.FOUR_PAWN: 5,
	MeldType.KONG: 8,
}

const HU_POINTS_EXPOSED := {
	MeldType.PAIR: 0,
	MeldType.SINGLE_KING: 1,
	MeldType.ROOK_HORSE_CANNON: 1,
	MeldType.KING_ADVISOR_ELEPHANT: 2,
	MeldType.PONG: 1,
	MeldType.THREE_PAWN: 3,
	MeldType.FOUR_PAWN: 5,
	MeldType.KONG: 6,
}

## 将/帅杠特殊：手中 6，亮出 8
const KING_KONG_IN_HAND := 6
const KING_KONG_EXPOSED := 8

const PLAYER_COUNT := 4

## 生成 112 张牌（GAME_RULES 1.2）
static func create_deck() -> Array:
	var deck: Array = []
	for s in range(SUIT_COUNT):
		for r in range(RANK_COUNT):
			for _i in range(COPIES_PER_CARD):
				deck.append(_card(s, r))
	return deck

## 牌表示为 dict，便于序列化与比较
static func _card(suit: int, rank: int) -> Dictionary:
	return {"suit": suit, "rank": rank}

static func card_equals(a: Dictionary, b: Dictionary) -> bool:
	return a.suit == b.suit and a.rank == b.rank

static func is_king(c: Dictionary) -> bool:
	return c.rank == Rank.KING

## 将/帅不可打出（GAME_RULES 4.4）
static func can_discard(c: Dictionary) -> bool:
	return c.rank != Rank.KING

## 发牌：庄家 21 张，闲家 20 张（GAME_RULES 三）
static func deal_cards(deck: Array, dealer_seat: int) -> Array:
	var hands: Array = [[], [], [], []]
	var idx := 0
	for rnd in range(DEAL_ROUNDS):
		var count_this_round := DEAL_PER_ROUND
		if rnd == DEAL_ROUNDS - 1:
			count_this_round = DEAL_PER_ROUND - 1  # 最后一轮闲家少 1 张
		for _c in range(count_this_round):
			for p in range(PLAYER_COUNT):
				if idx >= deck.size():
					break
				hands[p].append(deck[idx])
				idx += 1
	# 庄家补最后一轮多出的 1 张
	if idx < deck.size():
		hands[dealer_seat].append(deck[idx])
		idx += 1
	var remaining: Array = []
	while idx < deck.size():
		remaining.append(deck[idx])
		idx += 1
	return [hands, remaining]

## 洗牌
static func shuffle_deck(deck: Array) -> void:
	deck.shuffle()

## 上家座位（逆时针：0 的上家是 1，1 的上家是 2，2 的上家是 3，3 的上家是 0）
static func previous_seat(seat: int) -> int:
	return (seat + 1) % PLAYER_COUNT

## 下家
static func next_seat(seat: int) -> int:
	return (seat + PLAYER_COUNT - 1) % PLAYER_COUNT

## 某组合的胡数；is_exposed 表示已亮出（碰/杠/吃出）
static func get_meld_hu_points(meld_type: int, is_exposed: bool, is_king_kong: bool) -> int:
	if is_king_kong and meld_type == MeldType.KONG:
		return KING_KONG_EXPOSED if is_exposed else KING_KONG_IN_HAND
	if is_exposed:
		return HU_POINTS_EXPOSED.get(meld_type, 0)
	return HU_POINTS_IN_HAND.get(meld_type, 0)

## 点花额外胡数：每多一张同牌 +1 胡，最多 +3（GAME_RULES 7.2）
static func flower_hu_bonus(hand: Array, flower_tile: Dictionary) -> int:
	var count := 0
	for c in hand:
		if card_equals(c, flower_tile):
			count += 1
	return mini(count, 3)

## 牌面中文名（便于 UI）
static func rank_name(r: int) -> String:
	match r:
		Rank.KING: return "将"
		Rank.ADVISOR: return "士"
		Rank.ELEPHANT: return "象"
		Rank.ROOK: return "车"
		Rank.HORSE: return "马"
		Rank.CANNON: return "包"
		Rank.PAWN: return "卒"
	return "?"

static func suit_name(s: int) -> String:
	match s:
		Suit.RED: return "红"
		Suit.YELLOW: return "黄"
		Suit.WHITE: return "白"
		Suit.GREEN: return "绿"
	return "?"
