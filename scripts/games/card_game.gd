extends MiniGame

## 瞬間判断型のカード。赤いカード（♥♦）が出たら押す、黒（♠♣）なら押さない。
## 早く押すほど報酬が増える。赤を見逃すとコンボが切れる。

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS := ["♥", "♦", "♠", "♣"]
const REWARD := 200_000
const PENALTY_WRONG := -100_000
const PENALTY_MISSED := -30_000
const GAP_SEC := 0.3 # カードとカードの間の空白

var _card := {} # {"rank", "suit", "red", "left", "duration"}。空なら次のカード待ち
var _gap := 0.5
var _front := UiStyle.panel(UiStyle.GOLD, Color(0.98, 0.96, 0.9), 10, 12)
var _back := UiStyle.panel(UiStyle.NEON.darkened(0.3), Color(0.35, 0.05, 0.25), 4, 12)


func _init() -> void:
	title = "CARD"
	caption = "カード"


func duration() -> float:
	return lerpf(1.5, 0.8, difficulty) / speed_mult


func _process(delta: float) -> void:
	if active:
		if _card.is_empty():
			_gap -= delta
			if _gap <= 0.0:
				_deal()
		else:
			_card["left"] -= delta
			if _card["left"] <= 0.0:
				if _card["red"]:
					judged.emit("見逃し", PENALTY_MISSED, false)
				_clear()
	queue_redraw()


func _deal() -> void:
	var suit: String = SUITS[randi() % SUITS.size()]
	_card = {
		"rank": RANKS[randi() % RANKS.size()],
		"suit": suit,
		"red": suit == "♥" or suit == "♦",
		"left": duration(),
		"duration": duration(),
	}


func _clear() -> void:
	_card = {}
	_gap = GAP_SEC


func press() -> void:
	if not active:
		return
	if _card.is_empty() or not _card["red"]:
		judged.emit("ちがう!", PENALTY_WRONG, false)
		_clear()
		return
	# 残り時間が多いほど高報酬（最大1.5倍、最低0.5倍）
	var ratio: float = _card["left"] / _card["duration"]
	var text := "はやい!" if ratio > 0.6 else "OK"
	judged.emit(text, int(REWARD * (0.5 + ratio) * reward_mult), true)
	_clear()


func _draw() -> void:
	draw_panel()
	if is_locked():
		return
	var center := size / 2.0 + Vector2(0, 10)
	draw_centered("赤(♥♦)なら押す", Vector2(size.x / 2.0, 80), 22, Color(1, 0.6, 0.7))
	var card_h := minf(size.y - 170.0, 260.0)
	var card_size := Vector2(card_h * 0.7, card_h)
	var rect := Rect2(center - card_size / 2.0, card_size)
	if not active or _card.is_empty():
		# 裏面
		draw_style_box(_back, rect)
		draw_centered("♦", center, int(card_h * 0.3), Color(1, 0.8, 0.3, 0.5))
		return
	draw_style_box(_front, rect)
	var col := Color(0.85, 0.1, 0.2) if _card["red"] else Color(0.1, 0.1, 0.15)
	draw_centered(_card["suit"], center + Vector2(0, card_h * 0.05), int(card_h * 0.5), col)
	var corner := int(card_h * 0.13)
	draw_centered(_card["rank"], rect.position + Vector2(card_h * 0.1, card_h * 0.1), corner, col)
	draw_centered(_card["suit"], rect.position + Vector2(card_h * 0.1, card_h * 0.22), corner, col)
	# 残り時間バー
	var ratio: float = _card["left"] / _card["duration"]
	var bar := Rect2(rect.position.x, rect.end.y + 8, rect.size.x * ratio, 10)
	draw_rect(bar, GOLD if ratio > 0.3 else Color(1, 0.3, 0.3))
