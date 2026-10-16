extends CanvasLayer

## スマホ用のタッチボタン列。TouchScreenButton はマルチタッチ対応で、
## 押すと Lanes のアクションを直接発火するので、キーボード入力と同じ経路で処理される。
## レーンの前半を画面左下、後半を右下に並べて両手の親指で押せるようにする。

const BUTTON_HEIGHT_RATIO := 0.22 # 画面の高さに対するボタンの高さ
const MARGIN := 12.0

var lane_count := 0
var _buttons: Array[TouchScreenButton] = []
var _faces: Array[ColorRect] = []


func setup(count: int) -> void:
	lane_count = count
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_faces.clear()
	for i in lane_count:
		var button := TouchScreenButton.new()
		button.action = Lanes.action_name(i)
		button.shape = RectangleShape2D.new()
		button.shape_visible = false
		# 指を滑らせて隣のボタンに移っても反応させる
		button.passby_press = true

		var face := ColorRect.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face)

		var text := Label.new()
		text.text = Lanes.label(i)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.add_theme_font_size_override("font_size", 36)
		face.add_child(text)

		button.pressed.connect(_set_lit.bind(i, true))
		button.released.connect(_set_lit.bind(i, false))
		add_child(button)
		_buttons.append(button)
		_faces.append(face)
		_set_lit(i, false)
	_layout()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	if lane_count == 0:
		return
	var view := get_viewport().get_visible_rect().size
	var left_count := ceili(lane_count / 2.0)
	var right_count := lane_count - left_count
	var h := view.y * BUTTON_HEIGHT_RATIO
	# 左右それぞれ画面幅の半分弱にボタンを詰める
	var w := minf(h * 1.2, (view.x / 2.0 - MARGIN * 2.0) / maxi(left_count, 1) - MARGIN)
	var size := Vector2(w, h)
	var y := view.y - MARGIN - h / 2.0
	for i in lane_count:
		var x: float
		if i < left_count:
			x = MARGIN + w / 2.0 + i * (w + MARGIN)
		else:
			var j := i - left_count
			x = view.x - MARGIN - w / 2.0 - (right_count - 1 - j) * (w + MARGIN)
		_buttons[i].position = Vector2(x, y)
		(_buttons[i].shape as RectangleShape2D).size = size
		_faces[i].position = -size / 2.0
		_faces[i].size = size


func _set_lit(i: int, lit: bool) -> void:
	_faces[i].color = Color(1.0, 0.8, 0.2, 0.85) if lit else Color(0.6, 0.2, 0.8, 0.45)
