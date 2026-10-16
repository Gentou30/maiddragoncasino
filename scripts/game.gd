extends Control

## 試作ラウンド: 30秒間、スロット(A)とカード(S)を同時に処理していくら稼げるか。
## 最初の数秒はスロットだけ、途中からカードが加わる。

enum State { TITLE, PLAYING, RESULT }

const ROUND_SEC := 30.0
const CARD_JOIN_SEC := 5.0
const QUOTA := 5_000_000
const RESULT_LOCK_SEC := 1.0 # 結果画面で連打による即リトライを防ぐ
const MAID_TEXTURE := preload("res://assets/images/test_maid_dragon.png")

const SlotGame := preload("res://scripts/games/slot_game.gd")
const CardGame := preload("res://scripts/games/card_game.gd")
const TouchPad := preload("res://scripts/touch_pad.gd")

var state := State.TITLE
var money := 0
var combo := 0
var best_combo := 0
var elapsed := 0.0
var _result_at := 0.0
var _said_hurry := false

var games: Array[MiniGame] = []
var lanes: Array[int] = [0, 1] # games[n] はレーン lanes[n] で操作する

var _bg: ColorRect
var _money_label: Label
var _combo_label: Label
var _time_label: Label
var _maid: TextureRect
var _speech: Label
var _overlay: ColorRect
var _overlay_label: Label
var _touch_pad: CanvasLayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.color = Color(0.06, 0.01, 0.1)
	add_child(_bg)

	for g: MiniGame in [SlotGame.new(), CardGame.new()]:
		g.judged.connect(_on_judged.bind(g))
		add_child(g)
		games.append(g)

	_money_label = _make_label(34, MiniGame.GOLD)
	_combo_label = _make_label(24, Color(0.9, 0.8, 1.0))
	_time_label = _make_label(48, Color.WHITE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_maid = TextureRect.new()
	_maid.texture = MAID_TEXTURE
	_maid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_maid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_maid)
	_speech = _make_label(20, Color(1, 0.85, 0.95))
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_touch_pad = TouchPad.new()
	add_child(_touch_pad)
	var captions: Array[String] = []
	for g in games:
		captions.append(g.caption)
	_touch_pad.setup(lanes, captions)
	_touch_pad.visible = Lanes.is_touch_device()

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.0, 0.08, 0.88)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay_label = _make_label(34, Color.WHITE, _overlay)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_overlay_label.set_anchors_preset(Control.PRESET_FULL_RECT)

	Screen.layout_changed.connect(_layout)
	_layout()
	_show_title()


func _make_label(font_size: int, color: Color, parent: Node = self) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


# ---- 進行 ----

func _show_title() -> void:
	state = State.TITLE
	for g in games:
		g.active = false
	var how := "下のボタン" if Lanes.is_touch_device() else "A / S キー"
	_overlay_label.text = "メイドドラゴンカジノ（試作）\n\n30秒で ¥%s 稼げ！\n%sで2つのゲームを同時に操作\n\n%sでスタート" % [
		_yen(QUOTA), how, "タップ" if Lanes.is_touch_device() else "Space / A"]
	_overlay.visible = true
	_say("ご主人様♡ 借金はたったの3000万円です！")
	_update_hud()


func _start() -> void:
	state = State.PLAYING
	money = 0
	combo = 0
	best_combo = 0
	elapsed = 0.0
	_said_hurry = false
	_overlay.visible = false
	games[0].active = true
	games[1].active = false
	for g in games:
		g.difficulty = 0.0
	_say("まずはスロットです♡ 7が枠に来たら押してください！")


func _finish() -> void:
	state = State.RESULT
	_result_at = elapsed
	for g in games:
		g.active = false
	var cleared := money >= QUOTA
	_overlay_label.text = "%s\n\n稼ぎ %s\n最大コンボ %d\n\n%sでもう一回" % [
		"ノルマ達成！" if cleared else "ノルマ未達…",
		_money_text(money), best_combo, "タップ" if Lanes.is_touch_device() else "Space / A"]
	_overlay.visible = true
	_say("おめでとうございます！ 次は私の借金ですね♡" if cleared else "大丈夫です！ ご主人様にはまだ担保があります♡")


func _process(delta: float) -> void:
	if state == State.RESULT:
		elapsed += delta
		return
	if state != State.PLAYING:
		return
	elapsed += delta
	var progress := elapsed / ROUND_SEC
	for g in games:
		g.difficulty = progress
	if not games[1].active and elapsed >= CARD_JOIN_SEC:
		games[1].active = true
		_say("カードも同時にどうぞ♡ 赤が出たら押してください！")
	if not _said_hurry and ROUND_SEC - elapsed <= 10.0:
		_said_hurry = true
		_say("あれ？ もう時間がないですね♡")
	if elapsed >= ROUND_SEC:
		_finish()
	_update_hud()


func _input(event: InputEvent) -> void:
	var lane := Lanes.pressed_lane(event)
	match state:
		State.PLAYING:
			var n := lanes.find(lane)
			if n >= 0:
				games[n].press()
		State.TITLE:
			if lane >= 0 or _is_start_input(event):
				_start()
		State.RESULT:
			if elapsed - _result_at >= RESULT_LOCK_SEC and (lane >= 0 or _is_start_input(event)):
				_start()


func _is_start_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode in [KEY_SPACE, KEY_ENTER]
	return false


func _on_judged(text: String, amount: int, success: bool, game: MiniGame) -> void:
	if success:
		combo += 1
		best_combo = maxi(best_combo, combo)
	else:
		combo = 0
	# 表示を読みやすくするため千円単位に丸める
	var gain := int(roundf(amount * multiplier() / 1000.0)) * 1000 if amount > 0 else amount
	money += gain
	_popup(game, "%s\n%s¥%s" % [text, "+" if gain >= 0 else "-", _yen(absi(gain))], success)
	if combo == 10:
		_say("才能があります！ ぜひ人生を賭けましょう！")
	elif not success and randf() < 0.3:
		_say("あらあら♡ 利息が増えちゃいますね")


## コンボ5回ごとに倍率+0.5（最大x5）。のちの「欲張りゲージ」の土台。
func multiplier() -> float:
	return minf(1.0 + floorf(combo / 5.0) * 0.5, 5.0)


# ---- 表示 ----

func _update_hud() -> void:
	_money_label.text = "%s / ノルマ %s" % [_money_text(money), _money_text(QUOTA)]
	_combo_label.text = "COMBO %d   倍率 x%.1f" % [combo, multiplier()]
	var left := maxf(ROUND_SEC - elapsed, 0.0) if state == State.PLAYING else ROUND_SEC
	_time_label.text = "%.1f" % left


func _say(text: String) -> void:
	_speech.text = "「%s」" % text


func _popup(game: MiniGame, text: String, success: bool) -> void:
	var l := _make_label(30, MiniGame.GOLD if success else Color(1, 0.35, 0.35))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(game.size.x, 90)
	l.position = game.position + Vector2(0, game.size.y * 0.25)
	l.z_index = 5
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)


func _layout() -> void:
	var v := Screen.view_size()
	_bg.size = v
	_overlay.size = v
	var m := 12.0
	var touch := Lanes.is_touch_device()
	var portrait := Screen.portrait

	# 上部HUD。縦向きはメイドを2段目に置く
	var hud_h := 230.0 if portrait else 110.0
	_money_label.position = Vector2(m + 8, m)
	_combo_label.position = Vector2(m + 8, m + 48)
	_time_label.size = Vector2(200, 60)
	_time_label.position = Vector2(v.x - 200 - m - 8, m)
	if portrait:
		_maid.position = Vector2(m, 100)
		_maid.size = Vector2(120, 120)
		_speech.position = Vector2(m + 130, 100)
		_speech.size = Vector2(v.x - m * 2 - 140, 120)
	else:
		_maid.size = Vector2(hud_h - 10, hud_h - 10)
		_maid.position = Vector2(v.x - _maid.size.x - 220, 5)
		_speech.position = Vector2(v.x * 0.42, 5)
		_speech.size = Vector2(_maid.position.x - v.x * 0.42 - 8, hud_h - 10)

	# 下部のタッチボタン
	var pad_h := 0.0
	if touch:
		pad_h = v.y * (0.15 if portrait else 0.2)

	# ゲーム領域を縦向きは縦に、横向きは横に等分する
	var area := Rect2(m, hud_h, v.x - m * 2, v.y - hud_h - pad_h - m * (2 if touch else 1))
	var n := games.size()
	var pad_rects: Array[Rect2] = []
	for i in n:
		var r: Rect2
		if portrait:
			var h := (area.size.y - m * (n - 1)) / n
			r = Rect2(area.position.x, area.position.y + i * (h + m), area.size.x, h)
			var bw := (v.x - m * (n + 1)) / n
			pad_rects.append(Rect2(m + i * (bw + m), v.y - pad_h - m, bw, pad_h))
		else:
			var w := (area.size.x - m * (n - 1)) / n
			r = Rect2(area.position.x + i * (w + m), area.position.y, w, area.size.y)
			pad_rects.append(Rect2(r.position.x, v.y - pad_h - m, w, pad_h))
		games[i].position = r.position
		games[i].size = r.size
		games[i].key_hint = "" if touch else "[%s] で押す" % Lanes.label(lanes[i])
	_touch_pad.place(pad_rects)


static func _money_text(v: int) -> String:
	return ("-¥" if v < 0 else "¥") + _yen(absi(v))


static func _yen(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out
