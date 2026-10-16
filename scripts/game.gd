extends Control

## 3日間で借金を返すラン全体の進行。
## TITLE → DAY_INTRO → PLAYING → SHOP（1・2日目の夜）→ … → 3日目終了で RESULT。
## 1日目: スロット(A)、途中からカード(S)。2日目からルーレット(D)も加わる。

enum State { TITLE, DAY_INTRO, PLAYING, SHOP, RESULT }

const DAYS := 3
const DAY_SEC := 40.0
const CARD_JOIN_SEC := 5.0 # 1日目だけ、カードが途中から加わる
const START_DEBT := 30_000_000
const LOAN_AMOUNT := 10_000_000
const INPUT_LOCK_SEC := 1.2 # 画面が切り替わった直後の連打で先に進まないようにする
const SHOP_LOCK_SEC := 2.0 # 1日の終わりの連打でアイテムを誤って買わないようにする
const MAID_TEXTURE := preload("res://assets/images/test_maid_dragon.png")

const SlotGame := preload("res://scripts/games/slot_game.gd")
const CardGame := preload("res://scripts/games/card_game.gd")
const RouletteGame := preload("res://scripts/games/roulette_game.gd")
const TouchPad := preload("res://scripts/touch_pad.gd")

var state := State.TITLE
var day := 1
var money := 0
var debt := START_DEBT
var combo := 0
var best_combo := 0
var elapsed := 0.0 # その日の経過秒
var owned: Array[String] = [] # 買ったアイテムの id（重複あり）
var event: Dictionary = RunData.NORMAL_DAY
var offers: Array[Dictionary] = []

# アイテム・イベントによる全体補正（_apply_mods で毎日計算し直す）
var gain_mult := 1.0
var loss_mult := 1.0
var combo_step := 0.5

var games: Array[MiniGame] = []
var lanes: Array[int] = [0, 1, 2] # games[n] はレーン lanes[n] で操作する

var _state_at := 0.0 # 現在の画面になった時刻（入力ロック用）
var _clock := 0.0
var _said_hurry := false
var _version := ""

var _bg: ColorRect
var _money_label: Label
var _status_label: Label
var _time_label: Label
var _maid: TextureRect
var _speech: Label
var _overlay: ColorRect
var _overlay_label: Label
var _shop_box: VBoxContainer
var _touch_pad: CanvasLayer


func _ready() -> void:
	var v := FileAccess.get_file_as_string("res://version.txt").strip_edges()
	_version = v if v != "" else "dev"

	_bg = ColorRect.new()
	_bg.color = Color(0.06, 0.01, 0.1)
	add_child(_bg)

	for g: MiniGame in [SlotGame.new(), CardGame.new(), RouletteGame.new()]:
		g.judged.connect(_on_judged.bind(g))
		add_child(g)
		games.append(g)

	_money_label = _make_label(30, MiniGame.GOLD)
	_status_label = _make_label(22, Color(0.9, 0.8, 1.0))
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

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.0, 0.08, 0.9)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay_label = _make_label(30, Color.WHITE, _overlay)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 12)
	_overlay.add_child(_shop_box)

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


func _touch() -> bool:
	return Lanes.is_touch_device()


func _go_text() -> String:
	return "タップ" if _touch() else "Space / クリック"


# ---- 画面の切り替え ----

func _set_state(s: State) -> void:
	state = s
	_state_at = _clock
	var playing := s == State.PLAYING
	_overlay.visible = not playing
	_touch_pad.visible = playing and _touch()
	_shop_box.visible = s == State.SHOP
	for g in games:
		g.active = false
	_update_hud()
	_layout()


func _show_title() -> void:
	_set_state(State.TITLE)
	var how := "下のボタン" if _touch() else "A / S / D キー"
	_overlay_label.text = "メイドドラゴンカジノ（試作）\n\n借金 %s を3日で返せ！\n%sで複数のギャンブルを同時に操作\n\n%sでスタート\n\nbuild %s" % [
		_money_text(START_DEBT), how, _go_text(), _version]
	_say("ご主人様♡ 借金はたったの3000万円です！")


func _new_run() -> void:
	day = 1
	money = 0
	debt = START_DEBT
	best_combo = 0
	owned.clear()
	_show_day_intro()


func _show_day_intro() -> void:
	if day == 1:
		event = RunData.NORMAL_DAY
	else:
		event = RunData.EVENTS[randi() % RunData.EVENTS.size()]
	_apply_mods()
	for g in games:
		g.lock_text = ""
	if day == 1:
		games[1].lock_text = "まもなく合流…"
		games[2].lock_text = "DAY 2 で解禁"
	_set_state(State.DAY_INTRO)
	var target := maxi(debt - money, 0)
	var added := ""
	if day == 2:
		added = "\n★ ルーレット(D) 解禁！"
	_overlay_label.text = "DAY %d / %d\n\n今日のイベント: %s\n%s%s\n\n返済まであと %s\n\n%sで開店" % [
		day, DAYS, event["name"], event["desc"], added, _money_text(target), _go_text()]
	match day:
		1: _say("1日目です♡ まずはスロットで肩慣らしですね！")
		2: _say("今日はルーレットもありますよ♡ 全部同時です♡")
		_: _say("最終日です♡ 返せなかったら…うふふ♡")


func _start_day() -> void:
	_set_state(State.PLAYING)
	elapsed = 0.0
	combo = 0
	_said_hurry = false
	for g in games:
		g.difficulty = _difficulty()
	_activate_games()


func _activate_games() -> void:
	for g in games:
		g.active = not g.is_locked()


func _end_day() -> void:
	if day >= DAYS:
		_show_result()
	else:
		_show_shop()


func _show_shop() -> void:
	_set_state(State.SHOP)
	# 持っていないアイテムから3つ（闇金契約は何度でも出る）
	var pool: Array[Dictionary] = []
	for item in RunData.ITEMS:
		if item.get("stackable", false) or not owned.has(item["id"]):
			pool.append(item)
	pool.shuffle()
	offers = pool.slice(0, 3)
	_overlay_label.text = "DAY %d 終了！  所持金 %s / 借金 %s\n\n― 夜の闇市 ―  1つだけ持ち帰れます" % [day, _money_text(money), _money_text(debt)]
	for c in _shop_box.get_children():
		c.queue_free()
	var keys := ["A", "S", "D"]
	for i in offers.size():
		var item := offers[i]
		var b := Button.new()
		var key := "" if _touch() else "[%s] " % keys[i]
		b.text = "%s%s\n◎ %s   ✕ %s" % [key, item["name"], item["good"], item["bad"]]
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_buy.bind(i))
		_shop_box.add_child(b)
	var skip := Button.new()
	skip.text = "何も買わない" if _touch() else "[Space] 何も買わない"
	skip.add_theme_font_size_override("font_size", 22)
	skip.pressed.connect(_buy.bind(-1))
	_shop_box.add_child(skip)
	_say("ご主人様♡ どれも合法ですよ（たぶん）")
	_layout()


func _buy(i: int) -> void:
	if state != State.SHOP or _locked():
		return
	if i >= 0:
		var item := offers[i]
		owned.append(item["id"])
		if item["id"] == "vip_loan":
			debt += LOAN_AMOUNT
	day += 1
	_show_day_intro()


func _show_result() -> void:
	_set_state(State.RESULT)
	var cleared := money >= debt
	var lines := "完済！！" if cleared else "破産…"
	lines += "\n\n所持金 %s\n借金 %s\n%s\n最大コンボ %d\n\n%sでもう一回" % [
		_money_text(money), _money_text(debt),
		("残り %s はメイドのお給料に" % _money_text(money - debt)) if cleared else ("足りない額 %s" % _money_text(debt - money)),
		best_combo, _go_text()]
	_overlay_label.text = lines
	_say("おめでとうございます！ 次は私の借金ですね♡" if cleared else "大丈夫です！ ご主人様にはまだ担保があります♡")


# ---- 補正 ----

func _apply_mods() -> void:
	gain_mult = 1.0
	loss_mult = 1.0
	combo_step = 0.5
	for g in games:
		g.reset_mods()
	var speed := 1.0
	for id in owned:
		match id:
			"slot_mod":
				games[0].reward_mult *= 3.0
				games[0].speed_mult *= 1.6
			"black_card":
				games[1].reward_mult *= 2.0
				games[1].speed_mult *= 2.0
			"rigged_wheel":
				games[2].prize_width_mult *= 2.0
				games[2].stake_mult *= 3.0
			"maneki":
				gain_mult *= 1.5
				loss_mult *= 3.0
			"energy":
				gain_mult *= 1.3
				speed *= 1.25
			"vip_loan":
				gain_mult *= 1.5
	match event["id"]:
		"inflation":
			gain_mult *= 2.0
			loss_mult *= 2.0
		"rush":
			speed *= 1.3
			gain_mult *= 1.3
		"bonus":
			combo_step *= 2.0
	for g in games:
		g.speed_mult *= speed


func _difficulty() -> float:
	# 日ごとに底上げし、その日の中でも徐々に上げる
	return clampf((day - 1) * 0.3 + elapsed / DAY_SEC * 0.4, 0.0, 1.0)


## コンボ5回ごとに倍率が上がる（最大x5）
func multiplier() -> float:
	return minf(1.0 + floorf(combo / 5.0) * combo_step, 5.0)


# ---- 毎フレーム・入力 ----

func _process(delta: float) -> void:
	_clock += delta
	if state == State.SHOP:
		for b: Button in _shop_box.get_children():
			b.disabled = _locked()
	if state != State.PLAYING:
		return
	elapsed += delta
	for g in games:
		g.difficulty = _difficulty()
	if day == 1 and games[1].is_locked() and elapsed >= CARD_JOIN_SEC:
		games[1].lock_text = ""
		_activate_games()
		_say("カードも同時にどうぞ♡ 赤が出たら押してください！")
	if not _said_hurry and DAY_SEC - elapsed <= 10.0:
		_said_hurry = true
		_say("あれ？ もう時間がないですね♡")
	if elapsed >= DAY_SEC:
		_end_day()
	_update_hud()


func _locked() -> bool:
	return _clock - _state_at < (SHOP_LOCK_SEC if state == State.SHOP else INPUT_LOCK_SEC)


func _input(event_in: InputEvent) -> void:
	var lane := Lanes.pressed_lane(event_in)
	match state:
		State.PLAYING:
			var n := lanes.find(lane)
			if n >= 0:
				games[n].press()
		State.SHOP:
			# タッチ・クリックはボタン側で処理する
			if _locked():
				return
			if lane >= 0 and lane < offers.size():
				_buy(lane)
			elif _is_go_key(event_in):
				_buy(-1)
		_:
			# プレイ中の連打で読み飛ばさないよう、レーンのキーではなく Space / タップで進める
			if _locked() or not (_is_go_key(event_in) or _is_tap(event_in)):
				return
			match state:
				State.TITLE, State.RESULT:
					_new_run()
				State.DAY_INTRO:
					_start_day()


func _is_go_key(e: InputEvent) -> bool:
	return e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_SPACE, KEY_ENTER]


func _is_tap(e: InputEvent) -> bool:
	return e is InputEventScreenTouch and e.pressed


func _on_judged(text: String, amount: int, success: bool, game: MiniGame) -> void:
	if success:
		combo += 1
		best_combo = maxi(best_combo, combo)
	else:
		combo = 0
	var gain: int
	# 表示を読みやすくするため千円単位に丸める
	if amount > 0:
		gain = int(roundf(amount * multiplier() * gain_mult / 1000.0)) * 1000
	else:
		gain = int(roundf(amount * loss_mult / 1000.0)) * 1000
	money += gain
	_popup(game, "%s\n%s" % [text, ("+" if gain >= 0 else "") + _money_text(gain)], success)
	if combo == 10:
		_say("才能があります！ ぜひ人生を賭けましょう！")
	elif text == "x8":
		_say("大当たりです♡ この調子で全部賭けましょう！")
	elif not success and randf() < 0.3:
		_say("あらあら♡ 利息が増えちゃいますね")


# ---- 表示 ----

func _update_hud() -> void:
	_money_label.text = "所持金 %s / 借金 %s" % [_money_text(money), _money_text(debt)]
	_status_label.text = "DAY %d/%d  %s   COMBO %d  倍率 x%.1f" % [day, DAYS, event["name"], combo, multiplier()]
	var left := maxf(DAY_SEC - elapsed, 0.0) if state == State.PLAYING else DAY_SEC
	_time_label.text = "%.1f" % left


func _say(text: String) -> void:
	_speech.text = "「%s」" % text


func _popup(game: MiniGame, text: String, success: bool) -> void:
	var l := _make_label(28, MiniGame.GOLD if success else Color(1, 0.35, 0.35))
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
	var touch := _touch()
	var portrait := Screen.portrait

	# 上部HUD。縦向きはメイドを2段目に置く
	var hud_h := 230.0 if portrait else 110.0
	_money_label.position = Vector2(m + 8, m)
	_status_label.position = Vector2(m + 8, m + 46)
	_time_label.size = Vector2(160, 60)
	_time_label.position = Vector2(v.x - 160 - m - 8, m)
	if portrait:
		_status_label.position.y = m + 46
		_maid.position = Vector2(m, 100)
		_maid.size = Vector2(120, 120)
		_speech.position = Vector2(m + 130, 100)
		_speech.size = Vector2(v.x - m * 2 - 140, 120)
	else:
		_maid.size = Vector2(hud_h - 10, hud_h - 10)
		_maid.position = Vector2(v.x - _maid.size.x - 180, 5)
		_speech.position = Vector2(v.x * 0.47, 5)
		_speech.size = Vector2(_maid.position.x - v.x * 0.47 - 8, hud_h - 10)

	# オーバーレイ（ショップ中は文言を上に寄せてボタンを下に並べる）
	if state == State.SHOP:
		_overlay_label.position = Vector2(m, m)
		_overlay_label.size = Vector2(v.x - m * 2, v.y * 0.3)
		_shop_box.position = Vector2(v.x * 0.08, v.y * 0.3)
		_shop_box.size = Vector2(v.x * 0.84, 0)
	else:
		_overlay_label.position = Vector2(m, m)
		_overlay_label.size = v - Vector2(m * 2, m * 2)

	# 下部のタッチボタン
	var pad_h := v.y * (0.13 if portrait else 0.2) if touch else 0.0
	var area := Rect2(m, hud_h, v.x - m * 2, v.y - hud_h - pad_h - m * (2 if touch else 1))
	var rects := _game_rects(area, games.size(), portrait, m)
	var pad_rects: Array[Rect2] = []
	for i in games.size():
		games[i].position = rects[i].position
		games[i].size = rects[i].size
		games[i].key_hint = "" if touch else "[%s] で押す" % Lanes.label(lanes[i])
		if portrait:
			var bw := (v.x - m * (games.size() + 1)) / games.size()
			pad_rects.append(Rect2(m + i * (bw + m), v.y - pad_h - m, bw, pad_h))
		else:
			pad_rects.append(Rect2(rects[i].position.x, v.y - pad_h - m, rects[i].size.x, pad_h))
	_touch_pad.place(pad_rects)


## ゲームパネルの配置。横向きは横一列、縦向きは2列のグリッド（端数は最後の行で横幅いっぱい）
static func _game_rects(area: Rect2, n: int, portrait: bool, m: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if not portrait:
		var w := (area.size.x - m * (n - 1)) / n
		for i in n:
			out.append(Rect2(area.position.x + i * (w + m), area.position.y, w, area.size.y))
		return out
	var cols := 1 if n <= 2 else 2
	var rows := ceili(float(n) / cols)
	var h := (area.size.y - m * (rows - 1)) / rows
	for i in n:
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var w := (area.size.x - m * (in_row - 1)) / in_row
		var col := i % cols
		out.append(Rect2(area.position.x + col * (w + m), area.position.y + row * (h + m), w, h))
	return out


static func _money_text(v: int) -> String:
	return ("-¥" if v < 0 else "¥") + _yen(absi(v))


static func _yen(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
