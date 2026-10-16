extends MiniGame

## リスク判断型のルーレット。押すたびに掛け金を払い、上の針が指した枠の倍率で払い戻される。
## 当たり枠は x1.5 / x3 / x8 / x3 / x1.5 と固まっていて、残りはすべて BUST（没収）。
## 適当に押すと期待値がマイナスになるよう、当たり枠の合計は円の3割にしている。
## 押したあとは少し止まって結果を見せ、当たり枠の位置を変えてから再び回る。

const STAKE := 200_000
const COOLDOWN_SEC := 0.55
# 当たり枠（円に対する割合）。並び順のまま隣り合って配置する
const PRIZES: Array[Dictionary] = [
	{"mult": 1.5, "width": 0.075, "color": Color(0.2, 0.55, 0.9)},
	{"mult": 3.0, "width": 0.05, "color": Color(0.75, 0.3, 0.95)},
	{"mult": 8.0, "width": 0.05, "color": Color(1.0, 0.75, 0.15)},
	{"mult": 3.0, "width": 0.05, "color": Color(0.75, 0.3, 0.95)},
	{"mult": 1.5, "width": 0.075, "color": Color(0.2, 0.55, 0.9)},
]
const BUST_COLOR := Color(0.35, 0.05, 0.1)

var stake_mult := 1.0 # アイテムで変わる掛け金倍率
var prize_width_mult := 1.0 # アイテムで変わる当たり枠の広さ

var _rot := 0.0 # ホイールの回転（ラジアン）
var _cluster_at := 0.0 # 当たり枠の始まりの位置（ホイール上の角度）
var _cooldown := 0.0
var _last_hit := -2 # 直前に止まった枠。-1 は BUST、-2 は表示なし


func _init() -> void:
	title = "ROULETTE"
	caption = "ルーレット"


func reset_mods() -> void:
	super.reset_mods()
	stake_mult = 1.0
	prize_width_mult = 1.0


func stake() -> int:
	return int(STAKE * stake_mult)


func rev_per_sec() -> float:
	return lerpf(0.45, 0.8, difficulty) * speed_mult


func _process(delta: float) -> void:
	if active:
		if _cooldown > 0.0:
			_cooldown -= delta
			if _cooldown <= 0.0:
				_last_hit = -2
				_cluster_at = randf() * TAU
		else:
			_rot = fmod(_rot + rev_per_sec() * TAU * delta, TAU)
	queue_redraw()


## 針（真上）が指しているホイール上の角度
func _pointer_local() -> float:
	return fposmod(-PI / 2.0 - _rot, TAU)


## 角度 a にある当たり枠の番号。BUST なら -1
func _prize_at(a: float) -> int:
	var start := _cluster_at
	for i in PRIZES.size():
		var w: float = PRIZES[i]["width"] * prize_width_mult * TAU
		if fposmod(a - start, TAU) < w:
			return i
		start += w
	return -1


func press() -> void:
	if not active or _cooldown > 0.0:
		return
	_last_hit = _prize_at(_pointer_local())
	_cooldown = COOLDOWN_SEC
	if _last_hit < 0:
		judged.emit("BUST", -stake(), false)
	else:
		var mult: float = PRIZES[_last_hit]["mult"]
		judged.emit("x%s" % _fmt_mult(mult), int(stake() * (mult - 1.0) * reward_mult), true)


static func _fmt_mult(m: float) -> String:
	return str(int(m)) if is_equal_approx(m, roundf(m)) else "%.1f" % m


func _draw() -> void:
	draw_panel()
	if is_locked():
		return
	draw_centered("掛け金 ¥%s  金色を狙え" % _short(stake()), Vector2(size.x / 2.0, 72), 20, Color(1, 0.7, 0.8))
	var center := size / 2.0 + Vector2(0, 22)
	var r := minf(size.x * 0.4, (size.y - 130.0) / 2.0)
	if r < 20.0:
		return
	var ring := r * 0.32
	var mid := r - ring / 2.0
	# 外枠と BUST の下地
	draw_circle(center, r + 8, Color(0.55, 0.38, 0.1))
	draw_arc(center, r + 4, 0, TAU, 96, UiStyle.GOLD, 4.0)
	draw_arc(center, mid, 0, TAU, 96, BUST_COLOR, ring)
	# 当たり枠
	var start := _cluster_at + _rot
	for i in PRIZES.size():
		var w: float = PRIZES[i]["width"] * prize_width_mult * TAU
		var col: Color = PRIZES[i]["color"]
		if _last_hit == i:
			col = col.lightened(0.4)
		draw_arc(center, mid, start, start + w, 16, col, ring)
		var label_pos := center + Vector2.from_angle(start + w / 2.0) * mid
		draw_centered(_fmt_mult(PRIZES[i]["mult"]), label_pos, int(ring * 0.42), Color.WHITE)
		start += w
	draw_circle(center, r - ring, Color(0.55, 0.38, 0.1))
	draw_circle(center, r - ring - 6, Color(0.08, 0.02, 0.12))
	# 結果表示
	if _last_hit == -1:
		draw_centered("BUST", center, int(r * 0.32), Color(1, 0.3, 0.3))
	elif _last_hit >= 0:
		draw_centered("x" + _fmt_mult(PRIZES[_last_hit]["mult"]), center, int(r * 0.4), GOLD)
	# 針（真上に固定）
	var tip := center + Vector2(0, -r + ring * 0.6)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-12, -ring * 0.9), tip + Vector2(12, -ring * 0.9)]), Color.WHITE)


static func _short(v: int) -> String:
	if v >= 10_000:
		return "%d万" % (v / 10_000)
	return str(v)
