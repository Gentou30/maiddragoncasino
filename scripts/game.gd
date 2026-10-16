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
const BG_TEXTURE := preload("res://assets/images/bg_casino.jpg")
const MAID_FULL := preload("res://assets/images/maid_full.png")
const COIN_TEXTURE := preload("res://assets/images/slot/coin.png")
const MAID_MOODS := ["normal", "happy", "scheme", "panic"]

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

# 放置ペナルティ：1つのゲームだけに集中させないため、しばらく触っていないゲームから損失が出る
const NEGLECT_WARN_SEC := 4.0 # 触らずにこの秒数たつと警告
const NEGLECT_SEC := 7.0 # この秒数たつと放置中になり、以後一定間隔で損失
const NEGLECT_TICK_SEC := 2.0
const NEGLECT_PENALTY := -100_000

var games: Array[MiniGame] = []
var _idle: Array[float] = [] # games[n] を最後に押してからの秒数
var _alert_labels: Array[Label] = []
var lanes: Array[int] = [0, 1, 2] # games[n] はレーン lanes[n] で操作する

var _state_at := 0.0 # 現在の画面になった時刻（入力ロック用）
var _clock := 0.0
var _said_hurry := false
var _version := ""

var _bg: TextureRect
var _bg_dim: ColorRect
var _hud_box: Panel
var _bubble: Panel
var _maid_tex := {}
var _mood := ""
var _speech_at := 0.0
const SPEECH_HOLD_SEC := 5.0 # プレイ中、この秒数たったら古いセリフを状況のセリフに置き換える
var _ov_title: Label
var _title_art: TextureRect
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

	for m in MAID_MOODS:
		_maid_tex[m] = load("res://assets/images/maid_%s.png" % m)

	_bg = TextureRect.new()
	_bg.texture = BG_TEXTURE
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_bg)
	_bg_dim = ColorRect.new()
	_bg_dim.color = Color(0.04, 0.0, 0.08, 0.45)
	add_child(_bg_dim)
	_hud_box = Panel.new()
	_hud_box.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PINK, Color(0.08, 0.02, 0.12, 0.85), 10, 16))
	add_child(_hud_box)

	for g: MiniGame in [SlotGame.new(), CardGame.new(), RouletteGame.new()]:
		g.judged.connect(_on_judged.bind(g))
		add_child(g)
		games.append(g)
		_idle.append(0.0)
		# パネルの上辺に重ねる警告バッジ（ゲームの描画より手前に出すため子にする）
		var l := _make_label(20, Color.WHITE, g)
		UiStyle.outline(l, 6)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.z_index = 1
		var badge := UiStyle.panel(UiStyle.RED, Color(0.45, 0.02, 0.1, 0.95), 6, 12)
		badge.set_content_margin_all(4)
		l.add_theme_stylebox_override("normal", badge)
		l.visible = false
		_alert_labels.append(l)

	_money_label = _make_label(30, MiniGame.GOLD)
	UiStyle.outline(_money_label)
	_status_label = _make_label(22, Color(0.95, 0.85, 1.0))
	UiStyle.outline(_status_label, 6)
	_time_label = _make_label(52, Color.WHITE)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiStyle.outline(_time_label, 10)

	_bubble = Panel.new()
	_bubble.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.PINK, Color(1, 0.95, 0.98, 0.95), 6, 18))
	add_child(_bubble)
	_speech = _make_label(20, Color(0.35, 0.05, 0.25))
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_maid = TextureRect.new()
	_maid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_maid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_maid)

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
	_title_art = TextureRect.new()
	_title_art.texture = MAID_FULL
	_title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_title_art)
	_ov_title = _make_label(60, UiStyle.GOLD, _overlay)
	_ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ov_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.outline(_ov_title, 14)
	_overlay_label = _make_label(28, Color.WHITE, _overlay)
	UiStyle.outline(_overlay_label, 8)
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
	_title_art.visible = s == State.TITLE or s == State.RESULT
	for g in games:
		g.active = false
	_update_hud()
	_layout()


func _show_title() -> void:
	_set_state(State.TITLE)
	var how := "下のボタン" if _touch() else "A / S / D キー"
	_ov_title.text = "メイドドラゴン\nカジノ"
	_overlay_label.text = "借金 %s を3日で返せ！\n%sで複数のギャンブルを同時に操作\n\n%sでスタート\n\nbuild %s" % [
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
		added = "\n★ ルーレット(D) 解禁！\n※ しばらく触らないゲームは「放置」で損失が出ます"
	_ov_title.text = "DAY %d / %d" % [day, DAYS]
	_overlay_label.text = "今日のイベント: %s\n%s%s\n\n返済まであと %s\n\n%sで開店" % [
		event["name"], event["desc"], added, _money_text(target), _go_text()]
	match day:
		1: _say("1日目です♡ まずはスロットで肩慣らしですね！")
		2: _say("今日はルーレットもありますよ♡ 全部同時です♡", "scheme")
		_: _say("最終日です♡ 返せなかったら…うふふ♡", "scheme")


func _start_day() -> void:
	_set_state(State.PLAYING)
	elapsed = 0.0
	combo = 0
	_said_hurry = false
	for g in games:
		g.difficulty = _difficulty()
	_activate_games()


func _activate_games() -> void:
	for i in games.size():
		games[i].active = not games[i].is_locked()
		_idle[i] = 0.0
	_update_alerts()


## 触っていないゲームの警告表示と、放置中の損失
func _tick_neglect(delta: float) -> void:
	for i in games.size():
		if not games[i].active:
			continue
		var before := _idle[i]
		_idle[i] += delta
		if _idle[i] >= NEGLECT_SEC and floorf((_idle[i] - NEGLECT_SEC) / NEGLECT_TICK_SEC) != floorf((before - NEGLECT_SEC) / NEGLECT_TICK_SEC):
			_on_judged("放置", NEGLECT_PENALTY, false, games[i])
			if _idle[i] - delta < NEGLECT_SEC:
				_say("%sがお留守ですよ♡ お客様が帰っちゃいます" % games[i].caption, "panic")
	_update_alerts()


func _update_alerts() -> void:
	for i in games.size():
		var g := games[i]
		var a := 0
		if g.active and state == State.PLAYING:
			if _idle[i] >= NEGLECT_SEC:
				a = 2
			elif _idle[i] >= NEGLECT_WARN_SEC:
				a = 1
		g.alert = a
		var l := _alert_labels[i]
		l.visible = a > 0
		if a == 1:
			l.text = " あと%d秒で放置！ " % ceili(NEGLECT_SEC - _idle[i])
		elif a == 2:
			l.text = " 放置中！ 損失発生 "
		l.reset_size()
		l.position = Vector2((g.size.x - l.size.x) / 2.0, -l.size.y / 2.0)


func _end_day() -> void:
	for g in games:
		g.alert = 0
	for l in _alert_labels:
		l.visible = false
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
	_ov_title.text = "夜の闇市"
	_overlay_label.text = "DAY %d 終了！ 所持金 %s / 借金 %s\n1つだけ持ち帰れます" % [day, _money_text(money), _money_text(debt)]
	for c in _shop_box.get_children():
		c.queue_free()
	var keys := ["A", "S", "D"]
	for i in offers.size():
		var item := offers[i]
		var b := Button.new()
		var key := "" if _touch() else "[%s] " % keys[i]
		b.text = "%s%s\n◎ %s   ✕ %s" % [key, item["name"], item["good"], item["bad"]]
		b.add_theme_font_size_override("font_size", 22)
		UiStyle.button_styles(b)
		b.pressed.connect(_buy.bind(i))
		_shop_box.add_child(b)
	var skip := Button.new()
	skip.text = "何も買わない" if _touch() else "[Space] 何も買わない"
	skip.add_theme_font_size_override("font_size", 22)
	UiStyle.button_styles(skip)
	skip.pressed.connect(_buy.bind(-1))
	_shop_box.add_child(skip)
	_say("ご主人様♡ どれも合法ですよ（たぶん）", "scheme")
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
	_ov_title.text = "完済！！" if cleared else "破産…"
	var lines := "所持金 %s\n借金 %s\n%s\n最大コンボ %d\n\n%sでもう一回" % [
		_money_text(money), _money_text(debt),
		("残り %s はメイドのお給料に" % _money_text(money - debt)) if cleared else ("足りない額 %s" % _money_text(debt - money)),
		best_combo, _go_text()]
	_overlay_label.text = lines
	if cleared:
		_say("おめでとうございます！ 次は私の借金ですね♡", "happy")
	else:
		_say("大丈夫です！ ご主人様にはまだ担保があります♡", "scheme")


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
	if _clock - _speech_at > SPEECH_HOLD_SEC:
		var left := debt - money
		if left > 0:
			_say("返済まであと %s です♡" % _money_text(left))
		else:
			_say("もう返せちゃいます♡ もっと稼ぎましょう！", "happy")
	if not _said_hurry and DAY_SEC - elapsed <= 10.0:
		_said_hurry = true
		_say("あれ？ もう時間がないですね♡", "panic")
	_tick_neglect(delta)
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
				_idle[n] = 0.0
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
	var big := gain >= 500_000
	if success:
		_coin_burst(game, 24 if big else 8)
		_pop_panel(game, 1.06 if big else 1.03)
	else:
		_shake_panel(game)
	if combo == 10:
		_say("才能があります！ ぜひ人生を賭けましょう！", "happy")
	elif text == "x4":
		_say("大当たりです♡ この調子で全部賭けましょう！", "happy")
	elif money < 0 and money - gain >= 0:
		_say("ご主人様!? 所持金がマイナスです！", "panic")
	elif not success and randf() < 0.3:
		_say("あらあら♡ 利息が増えちゃいますね", "scheme")


# ---- 表示 ----

func _update_hud() -> void:
	_money_label.text = "所持金 %s / 借金 %s" % [_money_text(money), _money_text(debt)]
	_status_label.text = "DAY %d/%d  %s   COMBO %d  倍率 x%.1f" % [day, DAYS, event["name"], combo, multiplier()]
	var left := maxf(DAY_SEC - elapsed, 0.0) if state == State.PLAYING else DAY_SEC
	_time_label.text = "%.1f" % left


func _say(text: String, mood: String = "normal") -> void:
	_speech.text = text
	_speech_at = _clock
	if mood != _mood:
		_mood = mood
		_maid.texture = _maid_tex.get(mood, _maid_tex["normal"])
	# 話すたびにぷるんと弾ませる
	_maid.pivot_offset = Vector2(_maid.size.x / 2.0, _maid.size.y)
	var tw := _maid.create_tween()
	tw.tween_property(_maid, "scale", Vector2(1.12, 0.88), 0.08)
	tw.tween_property(_maid, "scale", Vector2(0.95, 1.06), 0.1)
	tw.tween_property(_maid, "scale", Vector2.ONE, 0.12)


func _coin_burst(game: MiniGame, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = COIN_TEXTURE
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = 0.8
	p.direction = Vector2.UP
	p.spread = 70.0
	p.initial_velocity_min = 250.0
	p.initial_velocity_max = 500.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.14
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.position = game.position + game.size / 2.0
	p.z_index = 4
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _pop_panel(game: MiniGame, k: float) -> void:
	game.pivot_offset = game.size / 2.0
	var tw := game.create_tween()
	tw.tween_property(game, "scale", Vector2(k, k), 0.05)
	tw.tween_property(game, "scale", Vector2.ONE, 0.12)


func _shake_panel(game: MiniGame) -> void:
	var tw := game.create_tween()
	for dx in [-10.0, 8.0, -5.0, 0.0]:
		tw.tween_property(game, "position:x", game.position.x + dx, 0.03)
	# レイアウトが途中で変わってもずれが残らないよう、最後は元の位置に戻す
	var base := game.position.x
	tw.tween_callback(func(): game.position.x = base)


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
	_bg_dim.size = v
	_overlay.size = v
	var m := 12.0
	var touch := _touch()
	var portrait := Screen.portrait

	# 上部HUD。縦向きはメイドと吹き出しを2段目に置く
	var hud_h := 250.0 if portrait else 116.0
	_money_label.position = Vector2(m + 14, m + 4)
	_status_label.position = Vector2(m + 14, m + 50)
	_time_label.size = Vector2(160, 64)
	_time_label.position = Vector2(v.x - 160 - m - 12, m)
	_time_label.add_theme_font_size_override("font_size", 52)
	if portrait:
		# 所持金の行が長くなるので、残り時間は2段目の右に置く
		_time_label.add_theme_font_size_override("font_size", 40)
		_time_label.position = Vector2(v.x - 160 - m - 12, m + 34)
		_hud_box.position = Vector2(m, m - 4)
		_hud_box.size = Vector2(v.x - m * 2, 92)
		_maid.size = Vector2(150, 150)
		_maid.position = Vector2(m, 100)
		_bubble.position = Vector2(m + 160, 116)
		_bubble.size = Vector2(v.x - m * 2 - 160, 110)
	else:
		_hud_box.position = Vector2(m, m - 4)
		_hud_box.size = Vector2(v.x * 0.43, 92)
		_maid.size = Vector2(118, 118)
		_maid.position = Vector2(v.x - 118 - 186, 0)
		_bubble.position = Vector2(v.x * 0.45 + m, m)
		_bubble.size = Vector2(_maid.position.x - _bubble.position.x - 4, 84)
	_speech.position = _bubble.position + Vector2(16, 4)
	_speech.size = _bubble.size - Vector2(32, 8)

	# オーバーレイ。タイトル・結果は立ち絵を添える
	var art := _title_art.visible
	var text_rect := Rect2(m, m, v.x - m * 2, v.y - m * 2)
	if art:
		if portrait:
			_title_art.size = Vector2(v.x * 0.9, v.y * 0.42)
			_title_art.position = Vector2(v.x * 0.05, v.y - _title_art.size.y - m)
			text_rect = Rect2(m, v.y * 0.06, v.x - m * 2, v.y * 0.5)
		else:
			_title_art.size = Vector2(v.x * 0.4, v.y - m * 2)
			_title_art.position = Vector2(v.x * 0.58, m)
			text_rect = Rect2(m, v.y * 0.08, v.x * 0.58, v.y * 0.84)
	_ov_title.position = text_rect.position
	_ov_title.size = Vector2(text_rect.size.x, 0)
	var title_h := _ov_title.get_combined_minimum_size().y
	if state == State.SHOP:
		_overlay_label.position = Vector2(m, title_h + m)
		_overlay_label.size = Vector2(v.x - m * 2, 80)
		_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_shop_box.position = Vector2(v.x * 0.08, title_h + 110)
		_shop_box.size = Vector2(v.x * 0.84, 0)
	else:
		_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_overlay_label.position = text_rect.position + Vector2(0, title_h + 20)
		_overlay_label.size = Vector2(text_rect.size.x, text_rect.size.y - title_h - 20)

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
