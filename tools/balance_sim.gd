extends SceneTree

## バランス確認用の自動プレイ。人間の反応の遅れやタイミングのずれを入れたボットで3日間を遊び、結果を表示する。
## 使い方: godot --headless --fixed-fps 60 -s tools/balance_sim.gd -- [回数]
## （tools/ は .gdignore でゲームに含めない）

const DT := 1.0 / 60.0

# 腕前の想定。slot_sd / wheel_sd はタイミングのずれ（秒）、card_rt は反応時間（秒）、
# switch は別のゲームに目を移して押せるようになるまでの秒数（同時に全部は見られない）
const SKILLS := {
	"上手い": {"slot_sd": 0.05, "card_rt": 0.4, "card_err": 0.03, "wheel_sd": 0.05, "switch": 0.3},
	"ふつう": {"slot_sd": 0.09, "card_rt": 0.55, "card_err": 0.1, "wheel_sd": 0.1, "switch": 0.5},
}
# 遊び方。play は操作するゲームの番号（0: スロット, 1: カード, 2: ルーレット）
const PLANS := [
	{"name": "全部やる", "play": [0, 1, 2], "buy": ""},
	{"name": "全部やる＋闇金VIP", "play": [0, 1, 2], "buy": "vip_loan"},
	{"name": "スロット＋カードだけ", "play": [0, 1], "buy": ""},
	{"name": "ルーレットだけ", "play": [2], "buy": ""},
	{"name": "スロットだけ", "play": [0], "buy": ""},
]
const MIN_GAP := 0.12 # 同じゲームを続けて押せる最短間隔

var game: Control
var skill: Dictionary
var plan: Dictionary
var _last_game := -1
var _last_press := -100.0
var _slot_offset := {} # 7のマス番号 → 押すタイミングのずれ
var _last_card := {}
var _card_press_at := -1.0
var _wheel_offset := NAN # 次に回すときのタイミングのずれ。NAN なら未決定
var _t := 0.0
var _tally := {} # 判定ごとの回数（ゲーム名:判定）


func _initialize() -> void:
	var runs := 20
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	await process_frame
	for sk in SKILLS:
		for p in PLANS:
			var results: Array[int] = []
			var clears := 0
			_tally.clear()
			for i in runs:
				var r := await _run(SKILLS[sk], p)
				results.append(r[0] - r[1])
				if r[0] >= r[1]:
					clears += 1
			results.sort()
			print("%s / %-16s  完済 %2d/%d  残り(中央値) %s  最低 %s  最高 %s" % [
				sk, p["name"], clears, runs, _m(results[runs / 2]), _m(results[0]), _m(results[-1])])
			if "detail" in args:
				var keys := _tally.keys()
				keys.sort()
				print("    1回あたり: ", ", ".join(keys.map(func(k): return "%s %.1f" % [k, _tally[k] / float(runs)])))
	quit()


static func _m(v: int) -> String:
	return "%+.1f万" % (v / 10000.0)


func _run(sk: Dictionary, p: Dictionary) -> Array:
	skill = sk
	plan = p
	_slot_offset.clear()
	_last_card = {}
	_wheel_offset = NAN
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for g in game.games:
		g.judged.connect(func(text: String, _a: int, _s: bool):
			var k: String = g.title + ":" + text
			_tally[k] = _tally.get(k, 0) + 1)
	await process_frame
	game._new_run()
	while game.state != game.State.RESULT:
		match game.state:
			game.State.DAY_INTRO:
				game._start_day()
			game.State.SHOP:
				var pick := -1
				for i in game.offers.size():
					if game.offers[i]["id"] == p["buy"]:
						pick = i
				game._state_at = -100.0
				game._buy(pick)
			game.State.PLAYING:
				_bot()
		await process_frame
	var out := [game.money, game.debt]
	game.queue_free()
	await process_frame
	return out


func _press(n: int) -> void:
	game._idle[n] = 0.0
	game.games[n].press()
	_last_game = n
	_last_press = _t


func _bot() -> void:
	_t += DT
	var games: Array = game.games
	for n in plan["play"]:
		var g = games[n]
		var wait: float = MIN_GAP if n == _last_game else skill["switch"]
		if not g.active or _t - _last_press < wait:
			continue
		match n:
			0: _bot_slot(g, n)
			1: _bot_card(g, n)
			2: _bot_wheel(g, n)


func _bot_slot(g, n: int) -> void:
	for i in range(floori(g._pos), floori(g._pos) + 3):
		if g._cell(i) != "seven" or g._used.has(i) or (_slot_offset.has(i) and _slot_offset[i] == null):
			continue
		if not _slot_offset.has(i):
			_slot_offset[i] = randfn(0.0, skill["slot_sd"])
		# 中央に来るまでの秒数が、自分のずれ以下になったら押す（1つの7につき1回だけ）
		var to_center: float = (i - g._pos) / g.speed()
		if to_center <= _slot_offset[i]:
			_press(n)
			_slot_offset[i] = null
		return


func _bot_card(g, n: int) -> void:
	var c: Dictionary = g._card
	if c.is_empty():
		_card_press_at = -1.0
		return
	if not is_same(c, _last_card):
		_last_card = c
		var wrong: bool = randf() < skill["card_err"]
		if c["red"] != wrong:
			_card_press_at = _t + maxf(0.15, randfn(skill["card_rt"], 0.08))
		else:
			_card_press_at = -1.0
	if _card_press_at > 0.0 and _t >= _card_press_at:
		_card_press_at = -1.0
		_press(n)


func _bot_wheel(g, n: int) -> void:
	if g._cooldown > 0.0:
		return
	if is_nan(_wheel_offset):
		_wheel_offset = randfn(0.0, skill["wheel_sd"])
	# 金色の枠の中心に針が来るまでの秒数
	var start: float = g._cluster_at
	for i in 2:
		start += g.PRIZES[i]["width"] * g.prize_width_mult * TAU
	var center: float = start + g.PRIZES[2]["width"] * g.prize_width_mult * TAU / 2.0
	var rem := fposmod(g._pointer_local() - center, TAU)
	var t: float = rem / (g.rev_per_sec() * TAU)
	if t <= _wheel_offset or (_wheel_offset < 0.0 and t > 1.0 / g.rev_per_sec() + _wheel_offset):
		_press(n)
		_wheel_offset = NAN
