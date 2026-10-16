class_name MiniGame
extends Control

## 同時進行するミニゲームの共通部分。
## 入力はゲーム本体から press() で渡され、結果は judged で返す。
## 金額は倍率をかける前の値で、倍率やコンボの計算はゲーム本体が行う。

## text: "PERFECT" など / amount: 増減額 / success: コンボを伸ばすか切るか
signal judged(text: String, amount: int, success: bool)

const BG := Color(0.12, 0.04, 0.18)
const FRAME := Color(0.9, 0.3, 1.0)
const GOLD := Color(1.0, 0.82, 0.25)

var title := ""
var caption := "" # タッチボタンに出す名前
var key_hint := ""
var active := false
var difficulty := 0.0 # 0〜1。ラウンドの経過に合わせて上がる


func press() -> void:
	pass


func font() -> Font:
	return get_theme_default_font()


func draw_panel() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	draw_rect(Rect2(Vector2.ZERO, size), FRAME if active else FRAME.darkened(0.6), false, 4.0)
	draw_string(font(), Vector2(0, 40), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, GOLD if active else Color.GRAY)
	if key_hint != "":
		draw_string(font(), Vector2(0, size.y - 16), key_hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.7))


func draw_centered(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var f := font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := f.get_ascent(font_size)
	var desc := f.get_descent(font_size)
	draw_string(f, Vector2(center.x - w / 2.0, center.y + (asc - desc) / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
