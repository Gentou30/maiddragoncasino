extends CanvasLayer

## スマホ用のタッチボタン。TouchScreenButton はマルチタッチ対応で、
## 押すと Lanes のアクションを直接発火するので、キーボード入力と同じ経路で処理される。
## 配置はゲーム側が place() で矩形を渡して決める。

var _buttons: Array[TouchScreenButton] = []
var _faces: Array[Panel] = []
var _style_off := UiStyle.panel(UiStyle.NEON, Color(0.3, 0.06, 0.4, 0.85), 8, 20)
var _style_on := UiStyle.panel(UiStyle.GOLD, Color(0.85, 0.55, 0.1, 0.95), 18, 20)
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

		var face := Panel.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(face)

		var text := Label.new()
		text.text = "%s\n%s" % [captions[n], Lanes.label(lane)]
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.set_anchors_preset(Control.PRESET_FULL_RECT)
		text.add_theme_font_size_override("font_size", 30)
		UiStyle.outline(text, 6)
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
	_faces[n].add_theme_stylebox_override("panel", _style_on if lit else _style_off)
