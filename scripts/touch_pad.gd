extends CanvasLayer

## スマホ用のタッチボタン。TouchScreenButton はマルチタッチ対応で、
## 押すと Lanes のアクションを直接発火するので、キーボード入力と同じ経路で処理される。
## 配置はゲーム側が place() で矩形を渡して決める。

var _buttons: Array[TouchScreenButton] = []
var _faces: Array[ColorRect] = []
var _texts: Array[Label] = []


## lanes: 使うレーン番号、captions: ボタンに出す説明（例: "スロット"）
func setup(lanes: Array[int], captions: Array[String]) -> void:
	for b in _buttons:
		b.queue_free()
	_buttons.clear()
	_faces.clear()
	_texts.clear()
	for n in lanes.size():
		var lane := lanes[n]
		var button := TouchScreenButton.new()
		button.action = Lanes.action_name(lane)
		button.shape = RectangleShape2D.new()
		button.shape_visible = false
		# 指を滑らせて隣のボタンに移っても反応させる
		button.passby_press = true

		var face := ColorRect.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face)

		var text := Label.new()
		text.text = "%s\n%s" % [captions[n], Lanes.label(lane)]
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.add_theme_font_size_override("font_size", 30)
		face.add_child(text)

		button.pressed.connect(_set_lit.bind(n, true))
		button.released.connect(_set_lit.bind(n, false))
		add_child(button)
		_buttons.append(button)
		_faces.append(face)
		_texts.append(text)
		_set_lit(n, false)


func place(rects: Array[Rect2]) -> void:
	for n in mini(rects.size(), _buttons.size()):
		var r := rects[n]
		_buttons[n].position = r.get_center()
		(_buttons[n].shape as RectangleShape2D).size = r.size
		_faces[n].position = -r.size / 2.0
		_faces[n].size = r.size


func _set_lit(n: int, lit: bool) -> void:
	_faces[n].color = Color(1.0, 0.8, 0.2, 0.9) if lit else Color(0.45, 0.12, 0.6, 0.85)
