extends MiniGame

## タイミング型スロット。流れてくるリールの「7」が中央の枠に来た瞬間に押す。
## ずれた時間（秒）で判定するので、リールが速くなっても判定の厳しさは変わらない。

const SYMBOLS := ["bar", "cherry", "bell", "star", "coin"]
const TARGET := "seven"
const TEXTURES := {
	"seven": preload("res://assets/images/slot/seven.png"),
	"bar": preload("res://assets/images/slot/bar.png"),
	"cherry": preload("res://assets/images/slot/cherry.png"),
	"bell": preload("res://assets/images/slot/bell.png"),
	"star": preload("res://assets/images/slot/star.png"),
	"coin": preload("res://assets/images/slot/coin.png"),
}
const PERFECT_SEC := 0.08
const GOOD_SEC := 0.16
const REWARD_PERFECT := 200_000
const REWARD_GOOD := 70_000
const PENALTY_MISS := -50_000

var _pos := 0.0 # リールの位置（単位: マス）。マス i は _pos == i のとき中央に来る
var _cells: Array[String] = []
var _used := {} # 当てた7のマス番号
var _reel: Control


func _init() -> void:
	title = "SLOT"
	caption = "スロット"


func _ready() -> void:
	_reel = Control.new()
	_reel.clip_contents = true
	_reel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reel.draw.connect(_draw_reel)
	add_child(_reel)
	resized.connect(_on_resized)
	_on_resized()


func speed() -> float: # マス/秒
	return lerpf(3.0, 5.5, difficulty) * speed_mult


func _on_resized() -> void:
	var w := minf(size.x * 0.7, 260.0)
	var h := minf(size.y - 120.0, 330.0)
	_reel.size = Vector2(w, h)
	_reel.position = Vector2((size.x - w) / 2.0, (size.y - h) / 2.0 + 10.0)


func _cell(i: int) -> String:
	while _cells.size() <= i:
		var n := _cells.size()
		# 7は連続させず、だいたい3〜4マスに1回出す
		var prev_is_target := n > 0 and _cells[n - 1] == TARGET
		if not prev_is_target and n > 2 and randf() < 0.32:
			_cells.append(TARGET)
		else:
			_cells.append(SYMBOLS[randi() % SYMBOLS.size()])
	return _cells[i]


func _process(delta: float) -> void:
	if active:
		_pos += speed() * delta
	queue_redraw()
	_reel.queue_redraw()


func press() -> void:
	if not active:
		return
	# 中央に一番近い、まだ当てていない7を探す
	var best := -1
	var best_dist := INF
	for i in range(maxi(0, floori(_pos) - 1), floori(_pos) + 3):
		if _cell(i) == TARGET and not _used.has(i):
			var d := absf(_pos - i)
			if d < best_dist:
				best_dist = d
				best = i
	var sec := best_dist / speed()
	if best >= 0 and sec <= PERFECT_SEC:
		_used[best] = true
		judged.emit("PERFECT!", int(REWARD_PERFECT * reward_mult), true)
	elif best >= 0 and sec <= GOOD_SEC:
		_used[best] = true
		judged.emit("GOOD", int(REWARD_GOOD * reward_mult), true)
	else:
		judged.emit("MISS", PENALTY_MISS, false)


func _draw() -> void:
	draw_panel()
	_reel.visible = not is_locked()


func _draw_reel() -> void:
	var r := _reel.size
	var cell_h := r.y / 3.0
	_reel.draw_rect(Rect2(Vector2.ZERO, r), Color(0.97, 0.94, 0.88))
	# 中央の当たり枠
	var band := Rect2(0, r.y / 2.0 - cell_h / 2.0, r.x, cell_h)
	_reel.draw_rect(band, Color(1, 0.8, 0.2, 0.35))
	var base := floori(_pos)
	for i in range(maxi(0, base - 2), base + 3):
		var y := r.y / 2.0 + (_pos - i) * cell_h
		var s := _cell(i)
		var tex: Texture2D = TEXTURES[s]
		# 7だけ大きく、それ以外は控えめにして見分けやすくする
		var box := cell_h * (0.88 if s == TARGET else 0.62)
		var k := minf(box / tex.get_height(), r.x * 0.8 / tex.get_width())
		var ts := tex.get_size() * k
		var mod := Color.WHITE
		if _used.has(i):
			mod = Color(0.45, 0.45, 0.45, 0.6)
		elif s != TARGET:
			mod = Color(0.85, 0.8, 0.85)
		_reel.draw_texture_rect(tex, Rect2(Vector2((r.x - ts.x) / 2.0, y - ts.y / 2.0), ts), false, mod)
	# リールの上下を暗くして筒のように見せる
	for j in 6:
		var a := 0.32 - j * 0.05
		_reel.draw_rect(Rect2(0, j * 8, r.x, 8), Color(0, 0, 0, a))
		_reel.draw_rect(Rect2(0, r.y - (j + 1) * 8, r.x, 8), Color(0, 0, 0, a))
	_reel.draw_rect(band, GOLD, false, 4.0)
	_reel.draw_rect(Rect2(Vector2.ZERO, r), Color(0.35, 0.1, 0.4), false, 4.0)
