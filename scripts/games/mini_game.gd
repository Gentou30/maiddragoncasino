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
var difficulty := 0.0 # 0〜1。日数とラウンドの経過に合わせて上がる
var lock_text := "" # 空でなければ未解禁としてパネルにこの文言だけ出す
var alert := 0 # 放置の警告。0: なし / 1: もうすぐ放置 / 2: 放置中（ゲーム本体が設定する）

# アイテムやイベントによる補正。日の始めにゲーム本体がリセットして設定し直す
var reward_mult := 1.0
var speed_mult := 1.0


func reset_mods() -> void:
	reward_mult = 1.0
	speed_mult = 1.0


func is_locked() -> bool:
	return lock_text != ""


func press() -> void:
	pass


func font() -> Font:
	return get_theme_default_font()


var _panel_on := UiStyle.panel(UiStyle.NEON)
var _panel_off := UiStyle.panel(UiStyle.NEON.darkened(0.6), UiStyle.PANEL_BG, 4)
var _panel_alert: Array[StyleBoxFlat] = [_panel_on, UiStyle.panel(Color(1, 0.6, 0.15)), UiStyle.panel(UiStyle.RED, Color(0.2, 0.02, 0.06, 0.85), 20)]


func draw_panel() -> void:
	draw_style_box(_panel_alert[alert] if active else _panel_off, Rect2(Vector2.ZERO, size))
	var f := font()
	var col := GOLD if active else Color(0.6, 0.55, 0.65)
	draw_string_outline(f, Vector2(0, 42), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, 8, Color(0.05, 0, 0.08))
	draw_string(f, Vector2(0, 42), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, col)
	if is_locked():
		draw_centered(lock_text, size / 2.0, 26, Color(0.7, 0.6, 0.8))
	if key_hint != "":
		draw_string(font(), Vector2(0, size.y - 16), key_hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(1, 1, 1, 0.7))


func draw_centered(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var f := font()
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := f.get_ascent(font_size)
	var desc := f.get_descent(font_size)
	draw_string(f, Vector2(center.x - w / 2.0, center.y + (asc - desc) / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
