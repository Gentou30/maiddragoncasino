extends Control

## 3日間で借金を返すラン全体の進行。
## TITLE（→ STORY）→ DAY_INTRO → PLAYING → SHOP（1・2日目の夜）→ … → 3日目終了で RESULT。
## 1日目: スロット(A)、途中からカード(S)。2日目からルーレット(D)も加わる。

enum State { TITLE, STORY, DAY_INTRO, PLAYING, SHOP, RESULT }

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
const RICH_MARGIN := 10_000_000 # 完済してさらにこれだけ残れば大富豪エンド
const DISHWASH_PER_YEAR := 2_000_000 # 破産エンドで「あと何年」を出すための皿洗いの年収
# FEVER：コンボがこの数に達するたびに一定時間、収入が増える
const FEVER_COMBO := 15
const FEVER_SEC := 6.0
const FEVER_MULT := 1.5
# メイドの無茶ぶり指令：時々「◯◯で n 回成功して」と言われ、時間内に達成するとボーナス
const ORDER_FIRST_SEC := 10.0
const ORDER_GAP_SEC := Vector2(9.0, 14.0)
const ORDER_SEC := 6.0
const ORDER_REWARD := 400_000
const ORDER_NEED: Array[int] = [2, 2, 1] # ゲームごとの必要回数（スロット・カード・ルーレット）
const CLOSE_SEC := 1.6 # 閉店の演出を見せる秒数
const ENDINGS := {
	"rich": {"title": "大富豪エンド", "art": preload("res://assets/images/ending_rich.jpg")},
	"clear": {"title": "完済エンド", "art": preload("res://assets/images/ending_clear.jpg")},
	"bad": {"title": "破産エンド", "art": preload("res://assets/images/ending_bad.jpg")},
}

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
const NEGLECT_PENALTY := -150_000

var games: Array[MiniGame] = []
var _idle: Array[float] = [] # games[n] を最後に押してからの秒数
var _alert_labels: Array[Label] = []
var lanes: Array[int] = [0, 1, 2] # games[n] はレーン lanes[n] で操作する

var _state_at := 0.0 # 現在の画面になった時刻（入力ロック用）
var _clock := 0.0
var _said_hurry := false
var _closing := false # 閉店の演出中
var _fever_left := 0.0
var _order := {} # {"game", "need", "got", "left"}。空なら指令なし
var _next_order_at := 0.0
var _day_start_money := 0
var _last_day_gain := 0
var _shown_money := 0.0 # 表示用。実際の所持金に向かって数字が流れる
var _last_tick := -1
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
var _art_frame: Panel
var _money_label: Label
var _status_label: Label
var _time_label: Label
var _maid: TextureRect
var _speech: Label
var _overlay: ColorRect
var _overlay_label: Label
var _shop_box: VBoxContainer
var _menu_box: HBoxContainer
var _touch_pad: CanvasLayer
var _banner: Label
var _badge_red := UiStyle.panel(UiStyle.RED, Color(0.45, 0.02, 0.1, 0.95), 6, 12)
var _badge_gold := UiStyle.panel(UiStyle.GOLD, Color(0.35, 0.22, 0.02, 0.95), 8, 12)


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
		_badge_red.set_content_margin_all(4)
		_badge_gold.set_content_margin_all(4)
		l.add_theme_stylebox_override("normal", _badge_red)
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

	# 開店・閉店・FEVER などの大きな文字
	_banner = _make_label(72, UiStyle.GOLD)
	UiStyle.outline(_banner, 16)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.z_index = 10
	_banner.visible = false

	_overlay = ColorRect.new()
	_overlay.color = Color(0.05, 0.0, 0.08, 0.9)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_title_art = TextureRect.new()
	_title_art.texture = MAID_FULL
	_title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# エンディング絵（背景つきの正方形）の後ろに敷く額縁
	_art_frame = Panel.new()
	_art_frame.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.GOLD, UiStyle.GOLD, 18, 6))
	_art_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_art_frame)
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
	_menu_box = HBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 24)
	_menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(_menu_box)
	for item in [["スタート", "Space", _new_run], ["あらすじ", "A", _show_story], ["音", "M", _toggle_mute]]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(200 if item[1] != "M" else 150, 72)
		b.add_theme_font_size_override("font_size", 28)
		UiStyle.button_styles(b)
		b.set_meta("label", item[0])
		b.set_meta("key", item[1])
		b.pressed.connect(func():
			if state == State.TITLE and not _locked():
				Audio.sfx("click")
				item[2].call())
		_menu_box.add_child(b)

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
	_menu_box.visible = s == State.TITLE
	_title_art.visible = s in [State.TITLE, State.STORY, State.RESULT]
	_title_art.texture = MAID_FULL
	_overlay_label.add_theme_font_size_override("font_size", 28 if s in [State.TITLE, State.SHOP] else 24)
	match s:
		State.TITLE, State.STORY, State.DAY_INTRO:
			Audio.bgm("title")
		State.SHOP:
			Audio.bgm("shop")
	for g in games:
		g.active = false
	_update_hud()
	# 見出しや本文の高さで配置が変わるので、呼び出し側が文言を入れ終えてから組み直す
	_layout.call_deferred()


func _show_title() -> void:
	_set_state(State.TITLE)
	var how := "下のボタン" if _touch() else "A / S / D キー"
	_ov_title.text = "メイドドラゴン\nカジノ"
	_overlay_label.text = "借金 %s を3日で返せ！\n%sで複数のギャンブルを同時に操作\n\nbuild %s" % [
		_money_text(START_DEBT), how, _version]
	_update_menu()
	_say("ご主人様♡ 借金はたったの3000万円です！")


func _update_menu() -> void:
	for b: Button in _menu_box.get_children():
		var label: String = b.get_meta("label")
		if label == "音":
			label = "音 OFF" if Audio.muted else "音 ON"
		b.text = label if _touch() else "[%s] %s" % [b.get_meta("key"), label]


func _toggle_mute() -> void:
	Audio.toggle_mute()
	_update_menu()


func _show_story() -> void:
	_set_state(State.STORY)
	_ov_title.text = "あらすじ"
	_overlay_label.text = Scenario.STORY + "\n\n%sでもどる" % _go_text()
	_say("ぜんぶ合法ですよ♡ たぶん", "scheme")


func _new_run() -> void:
	day = 1
	money = 0
	_shown_money = 0.0
	debt = START_DEBT
	best_combo = 0
	_last_day_gain = 0
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
		added = "\n★ ルーレット(D) 解禁！ ※ 触らないゲームは「放置」で損失"
	_ov_title.text = "DAY %d / %d" % [day, DAYS]
	# 会話：前日の結果かイベントへの一言 ＋ その日の会話。吹き出しは暗幕の後ろに隠れるので本文に書く
	var talk: Array = []
	if event["id"] in Scenario.EVENT_TALKS:
		talk += Scenario.EVENT_TALKS[event["id"]]
	elif day > 1 and _last_day_gain >= 8_000_000:
		talk += Scenario.PACE_GOOD
	elif day > 1 and _last_day_gain < 3_000_000:
		talk += Scenario.PACE_BAD
	talk += Scenario.pick(Scenario.DAY_TALKS[mini(day, 3)])
	_say(talk[-1][1] if talk[-1][0] == "M" else talk[-2][1], "scheme" if day > 1 else "normal")
	_overlay_label.text = "%s\n\n今日のイベント: %s（%s）%s\n返済まであと %s\n\n%sで開店" % [
		Scenario.talk_text(talk), event["name"], event["desc"], added, _money_text(target), _go_text()]


func _start_day() -> void:
	_set_state(State.PLAYING)
	elapsed = 0.0
	combo = 0
	_said_hurry = false
	_closing = false
	_fever_left = 0.0
	_order = {}
	_next_order_at = ORDER_FIRST_SEC
	_last_tick = -1
	_day_start_money = money
	_show_banner("開店！", UiStyle.GOLD)
	Audio.jingle("start")
	get_tree().create_timer(0.9).timeout.connect(func():
		if state == State.PLAYING and not _closing:
			Audio.bgm("play", _bgm_pitch()))
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
				_say(Scenario.pick(Scenario.SAY_IDLE) % games[i].caption, "panic")
		elif _idle[i] >= NEGLECT_WARN_SEC and before < NEGLECT_WARN_SEC:
			Audio.sfx("warn", -10.0)
	_update_alerts()


func _update_alerts() -> void:
	for i in games.size():
		var g := games[i]
		var a := 0
		if g.active and state == State.PLAYING and not _closing:
			if _idle[i] >= NEGLECT_SEC:
				a = 2
			elif _idle[i] >= NEGLECT_WARN_SEC:
				a = 1
		g.alert = a
		var l := _alert_labels[i]
		var ordered: bool = a == 0 and not _order.is_empty() and _order["game"] == i and state == State.PLAYING
		l.visible = a > 0 or ordered
		l.add_theme_stylebox_override("normal", _badge_gold if ordered else _badge_red)
		if a == 1:
			l.text = " あと%d秒で放置！ " % ceili(NEGLECT_SEC - _idle[i])
		elif a == 2:
			l.text = " 放置中！ 損失発生 "
		elif ordered:
			l.text = " 指令 %d/%d  あと%d秒 " % [_order["got"], _order["need"], ceili(_order["left"])]
		l.reset_size()
		l.position = Vector2((g.size.x - l.size.x) / 2.0, -l.size.y / 2.0)


## 3日目・イベントほど BGM を速くする
func _bgm_pitch() -> float:
	var p := 1.0 + (day - 1) * 0.04
	if event["id"] == "rush":
		p += 0.06
	return p


## 時間切れ：ゲームを止めて閉店の演出を見せてから夜（または結果）へ
func _close_day() -> void:
	_closing = true
	_last_day_gain = money - _day_start_money
	_order = {}
	_fever_left = 0.0
	for g in games:
		g.active = false
		g.fever = false
	_update_alerts()
	_bg_dim.color = Color(0.04, 0.0, 0.08, 0.45)
	_show_banner("閉店ーー！", Color(1, 0.5, 0.7))
	Audio.jingle("end")
	get_tree().create_timer(CLOSE_SEC).timeout.connect(_end_day)


func _end_day() -> void:
	if state != State.PLAYING:
		return
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
		b.text = "%s%s\n◎ %s   ✕ %s\n「%s」" % [key, item["name"], item["good"], item["bad"], Scenario.ITEM_QUIPS.get(item["id"], "")]
		b.add_theme_font_size_override("font_size", 20)
		UiStyle.button_styles(b)
		b.pressed.connect(_buy.bind(i))
		_shop_box.add_child(b)
	var skip := Button.new()
	skip.text = "何も買わない" if _touch() else "[Space] 何も買わない"
	skip.add_theme_font_size_override("font_size", 20)
	skip.custom_minimum_size = Vector2(0, 56)
	UiStyle.button_styles(skip)
	skip.pressed.connect(_buy.bind(-1))
	_shop_box.add_child(skip)
	_say("ご主人様♡ どれも合法ですよ（たぶん）", "scheme")
	_layout()


func _buy(i: int) -> void:
	if state != State.SHOP or _locked():
		return
	Audio.sfx("click")
	if i >= 0:
		var item := offers[i]
		owned.append(item["id"])
		if item["id"] == "vip_loan":
			debt += LOAN_AMOUNT
	day += 1
	_show_day_intro()


func _ending() -> String:
	if money - debt >= RICH_MARGIN:
		return "rich"
	return "clear" if money >= debt else "bad"


func _show_result() -> void:
	_set_state(State.RESULT)
	var id := _ending()
	_ov_title.text = ENDINGS[id]["title"]
	_title_art.texture = ENDINGS[id]["art"]
	var story := ""
	match id:
		"rich":
			story = "借金を返しても、お金があふれて止まらない！\nご主人様はついにカジノのオーナーになった。"
			_say("次はどこを買い占めます？", "happy")
			Audio.jingle("clear")
		"clear":
			story = "夜明けとともに、借金を完済！\nご主人様は自由の身だ。…自由の身のはずだった。"
			_say("来週もよろしくお願いします♡", "happy")
			Audio.jingle("clear")
		_:
			var years := ceili(float(debt - money) / DISHWASH_PER_YEAR)
			story = "借金は返しきれなかった…\nご主人様はカジノの厨房で皿洗いをすることに。\n（皿洗いのお給料だと、完済まであと約%d年）" % years
			_say("お皿は1日1万枚です♡", "scheme")
			Audio.jingle("bad")
	var left := "手元に残ったお金 %s" % _money_text(money - debt) if money >= debt else "足りない額 %s" % _money_text(debt - money)
	_overlay_label.text = "%s\n\n%s\n\n所持金 %s / 借金 %s\n%s　最大コンボ %d\n\n%sでタイトルへ" % [
		story, Scenario.talk_text(Scenario.ENDING_TALKS[id]), _money_text(money), _money_text(debt), left, best_combo, _go_text()]
	_layout()


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


## コンボ5回ごとに倍率が上がる（最大x5）。FEVER 中はさらに2倍
func multiplier() -> float:
	var m := minf(1.0 + floorf(combo / 5.0) * combo_step, 5.0)
	return m * (FEVER_MULT if _fever_left > 0.0 else 1.0)


# ---- 毎フレーム・入力 ----

func _process(delta: float) -> void:
	_clock += delta
	# 所持金の表示は実際の値に向かって流れるように近づける
	_shown_money = lerpf(_shown_money, money, minf(1.0, delta * 8.0))
	if absf(_shown_money - money) < 1000.0:
		_shown_money = money
	if state in [State.SHOP, State.TITLE]:
		for b: Button in (_shop_box if state == State.SHOP else _menu_box).get_children():
			b.disabled = _locked()
	if state != State.PLAYING or _closing:
		_update_hud()
		return
	elapsed += delta
	_tick_fever(delta)
	_tick_order(delta)
	for g in games:
		g.difficulty = _difficulty()
	if day == 1 and games[1].is_locked() and elapsed >= CARD_JOIN_SEC:
		games[1].lock_text = ""
		_activate_games()
		_say("カードも同時にどうぞ♡ 赤が出たら押してください！")
	if _clock - _speech_at > SPEECH_HOLD_SEC and _order.is_empty():
		var left := debt - money
		if left > 0:
			_say("返済まであと %s です♡" % _money_text(left))
		else:
			_say("もう返せちゃいます♡ もっと稼ぎましょう！", "happy")
	var left := DAY_SEC - elapsed
	if not _said_hurry and left <= 10.0:
		_said_hurry = true
		_say(Scenario.pick(Scenario.SAY_HURRY), "panic")
		Audio.bgm_pitch(_bgm_pitch() * 1.12)
	# 残り5秒はカウントの音で急かす
	if left <= 5.0 and ceili(left) != _last_tick:
		_last_tick = ceili(left)
		if _last_tick > 0:
			Audio.sfx("spin", -6.0, 1.0 + (5 - _last_tick) * 0.1)
	_tick_neglect(delta)
	if elapsed >= DAY_SEC:
		_close_day()
	_update_hud()


func _tick_fever(delta: float) -> void:
	if _fever_left <= 0.0:
		return
	_fever_left -= delta
	if _fever_left <= 0.0:
		for g in games:
			g.fever = false
		_bg_dim.color = Color(0.04, 0.0, 0.08, 0.45)
		Audio.bgm_pitch(_bgm_pitch() * (1.12 if _said_hurry else 1.0))
	else:
		# 背景を金色にゆっくり明滅させる（激しい点滅にはしない）
		var k := 0.5 + 0.5 * sin(_clock * 4.0)
		_bg_dim.color = Color(0.35, 0.2, 0.0, 0.35 + 0.1 * k)


func _start_fever() -> void:
	_fever_left = FEVER_SEC
	for g in games:
		g.fever = g.active
	_show_banner("FEVER!! 収入x1.5", UiStyle.GOLD, 1.0, 56, true)
	Audio.sfx("fever", 0.0)
	Audio.bgm_pitch(_bgm_pitch() * 1.15)
	_say("フィーバーです♡ 今のうちに全部押してください！", "happy")


func _tick_order(delta: float) -> void:
	if _order.is_empty():
		if elapsed >= _next_order_at and DAY_SEC - elapsed > ORDER_SEC + 1.0:
			_start_order()
		return
	_order["left"] -= delta
	if _order["left"] <= 0.0:
		_order = {}
		_next_order_at = elapsed + randf_range(ORDER_GAP_SEC.x, ORDER_GAP_SEC.y)
		_say(Scenario.pick(Scenario.ORDER_FAIL), "scheme")


func _start_order() -> void:
	var cands: Array[int] = []
	for i in games.size():
		if games[i].active:
			cands.append(i)
	var n: int = cands[randi() % cands.size()]
	_order = {"game": n, "need": ORDER_NEED[n], "got": 0, "left": ORDER_SEC}
	Audio.sfx("order")
	_say("【指令】" + Scenario.pick(Scenario.ORDERS) % [games[n].caption, ORDER_NEED[n]], "scheme")


func _order_progress(game: MiniGame) -> void:
	if _order.is_empty() or games[_order["game"]] != game:
		return
	_order["got"] += 1
	if _order["got"] < _order["need"]:
		return
	_order = {}
	_next_order_at = elapsed + randf_range(ORDER_GAP_SEC.x, ORDER_GAP_SEC.y)
	var bonus := int(roundf(ORDER_REWARD * gain_mult / 1000.0)) * 1000
	money += bonus
	_popup(game, "指令クリア！\n+%s" % _money_text(bonus), true, -60.0)
	_coin_burst(game, 30)
	Audio.sfx("jackpot")
	_say(Scenario.pick(Scenario.ORDER_CLEAR), "happy")


func _locked() -> bool:
	# 1日の終わりの連打で、アイテム購入や結果画面を読み飛ばさないよう長めにロックする
	return _clock - _state_at < (SHOP_LOCK_SEC if state in [State.SHOP, State.RESULT] else INPUT_LOCK_SEC)


func _input(event_in: InputEvent) -> void:
	if OS.is_debug_build() and _debug_key(event_in):
		return
	if event_in is InputEventKey and event_in.pressed and not event_in.echo and event_in.physical_keycode == KEY_M:
		_toggle_mute()
		return
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
		State.TITLE:
			# タッチ・クリックはボタン側で処理する（画面のどこを押しても始まると、あらすじボタンが押せない）
			if _locked():
				return
			if _is_go_key(event_in):
				Audio.sfx("click")
				_new_run()
			elif lane == 0:
				Audio.sfx("click")
				_show_story()
		_:
			# プレイ中の連打で読み飛ばさないよう、レーンのキーではなく Space / タップで進める
			if _locked() or not (_is_go_key(event_in) or _is_tap(event_in)):
				return
			Audio.sfx("click")
			match state:
				State.STORY, State.RESULT:
					_show_title()
				State.DAY_INTRO:
					_start_day()


## デバッグビルドだけ：F1〜F3 で各エンディング、F4 で3日目の残り5秒へ、F5 で FEVER、F6 で指令（確認用）
func _debug_key(e: InputEvent) -> bool:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return false
	match e.physical_keycode:
		KEY_F1, KEY_F2, KEY_F3:
			money = debt + [RICH_MARGIN, 0, -12_345_000][e.physical_keycode - KEY_F1]
			best_combo = 42
			_show_result()
		KEY_F4:
			if state == State.PLAYING:
				day = DAYS
				elapsed = DAY_SEC - 5.0
		KEY_F5:
			if state == State.PLAYING:
				_start_fever()
		KEY_F6:
			if state == State.PLAYING:
				_start_order()
		_:
			return false
	return true


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
		_order_progress(game)
	else:
		_shake_panel(game)
	_play_judge_sound(text, success, big)
	if success and combo % FEVER_COMBO == 0:
		_start_fever()
	elif success and combo % 5 == 0:
		_show_banner("%d COMBO!  倍率 x%.1f" % [combo, multiplier()], Color(0.6, 0.95, 1.0), 0.6, 40, true)
		Audio.sfx("combo")
	if text == "x4":
		_shake_screen()
		_say(Scenario.pick(Scenario.SAY_BIG), "happy")
	elif money < 0 and money - gain >= 0:
		_say("ご主人様!? 所持金がマイナスです！", "panic")
	elif big and randf() < 0.5:
		_say(Scenario.pick(Scenario.SAY_BIG), "happy")
	elif not success and text != "放置" and randf() < 0.3:
		_say(Scenario.pick(Scenario.SAY_MISS), "scheme")


func _play_judge_sound(text: String, success: bool, big: bool) -> void:
	match text:
		"PERFECT!":
			Audio.sfx("perfect")
		"x4":
			Audio.sfx("jackpot")
		"BUST":
			Audio.sfx("bust")
		"放置":
			Audio.sfx("miss", -10.0, 0.8)
		_:
			if success:
				Audio.sfx("coin", -4.0, 1.15 if big else 1.0)
			else:
				Audio.sfx("miss")


# ---- 表示 ----

func _update_hud() -> void:
	_money_label.text = "所持金 %s / 借金 %s" % [_money_text(int(roundf(_shown_money / 1000.0)) * 1000), _money_text(debt)]
	_money_label.add_theme_color_override("font_color", MiniGame.GOLD if money >= 0 else UiStyle.RED)
	var fever := "  FEVER %.1f" % _fever_left if _fever_left > 0.0 else ""
	_status_label.text = "DAY %d/%d  %s   COMBO %d  倍率 x%.1f%s" % [day, DAYS, event["name"], combo, multiplier(), fever]
	var left := maxf(DAY_SEC - elapsed, 0.0) if state == State.PLAYING else DAY_SEC
	_time_label.text = "%.1f" % left
	var hurry := state == State.PLAYING and left <= 10.0
	_time_label.add_theme_color_override("font_color", UiStyle.RED if hurry else Color.WHITE)
	# 残り10秒は1秒ごとに数字を少し弾ませる
	var k := 1.0 + (0.15 * maxf(0.0, fmod(left, 1.0) - 0.7) / 0.3 if hurry else 0.0)
	_time_label.pivot_offset = _time_label.size / 2.0
	_time_label.scale = Vector2(k, k)


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


func _popup(game: MiniGame, text: String, success: bool, dy: float = 0.0) -> void:
	var l := _make_label(28, MiniGame.GOLD if success else Color(1, 0.35, 0.35))
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(game.size.x, 90)
	l.position = game.position + Vector2(0, game.size.y * 0.25 + dy)
	l.z_index = 5
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - 60.0, 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)


## 画面中央に大きな文字を出して消す
## top: プレイ中に邪魔にならないよう、ゲーム画面の上端（パネルの見出しのあたり）に出す
func _show_banner(text: String, color: Color, dur: float = 1.2, font_size: int = 72, top: bool = false) -> void:
	_banner.text = text
	_banner.add_theme_font_size_override("font_size", font_size)
	_banner.add_theme_color_override("font_color", color)
	_banner.visible = true
	var v := Screen.view_size()
	_banner.size = Vector2(v.x, 240)
	_banner.position = Vector2(0, v.y * 0.5 - 120)
	var bg: StyleBox = StyleBoxEmpty.new()
	if top:
		var w := _banner.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 60.0
		_banner.size = Vector2(w, 80)
		_banner.position = Vector2((v.x - w) / 2.0, games[0].position.y + 4)
		bg = UiStyle.panel(color, Color(0.05, 0.0, 0.08, 0.8), 10, 12)
	_banner.add_theme_stylebox_override("normal", bg)
	_banner.pivot_offset = _banner.size / 2.0
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(0.4, 0.4)
	if _banner.has_meta("tw"):
		var old: Tween = _banner.get_meta("tw")
		old.kill()
	var tw := _banner.create_tween()
	_banner.set_meta("tw", tw)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(dur)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): _banner.visible = false)


## 大当たりのときだけ画面全体を軽く揺らす
func _shake_screen() -> void:
	var tw := create_tween()
	for d in [Vector2(6, -4), Vector2(-5, 3), Vector2(3, 2), Vector2.ZERO]:
		tw.tween_property(self, "position", d, 0.04)


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
	_art_frame.visible = art and state == State.RESULT
	if _art_frame.visible:
		var side := minf(_title_art.size.x, _title_art.size.y)
		_art_frame.size = Vector2(side, side) + Vector2(8, 8)
		_art_frame.position = _title_art.position + (_title_art.size - Vector2(side, side)) / 2.0 - Vector2(4, 4)
	_ov_title.position = text_rect.position
	_ov_title.size = Vector2(text_rect.size.x, 0)
	var title_h := _ov_title.get_combined_minimum_size().y
	if state == State.TITLE:
		_menu_box.size = Vector2(text_rect.size.x, 0)
		_menu_box.position = Vector2(text_rect.position.x, text_rect.end.y - _menu_box.get_combined_minimum_size().y)
	if state == State.SHOP:
		_overlay_label.position = Vector2(m, title_h + m)
		_overlay_label.size = Vector2(v.x - m * 2, 0)
		_overlay_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		# 縦向きでは説明が折り返して行数が増えるので、その下から並べる
		var text_h := _overlay_label.get_line_count() * _overlay_label.get_line_height()
		_shop_box.position = Vector2(v.x * 0.08, title_h + m + text_h + 24)
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
