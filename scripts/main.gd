extends Node2D

## 入力テスト用の仮シーン。キーボード同時押し・マルチタッチがどこまで効くかを確かめる。

const LANE_COUNT := 8

@onready var info: Label = $Info
@onready var lamps: HBoxContainer = $Lamps
@onready var touch_pad: CanvasLayer = $TouchPad
@onready var rotate_hint: ColorRect = $RotateHint

var _hits: Array[int] = []
var _max_held := 0


func _ready() -> void:
	_hits.resize(LANE_COUNT)
	for i in LANE_COUNT:
		var lamp := Label.new()
		lamp.custom_minimum_size = Vector2(110, 110)
		lamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lamp.add_theme_font_size_override("font_size", 28)
		lamps.add_child(lamp)
	touch_pad.setup(LANE_COUNT)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()


func _input(event: InputEvent) -> void:
	var lane := Lanes.pressed_lane(event)
	if lane >= 0:
		_hits[lane] += 1


func _process(_delta: float) -> void:
	var held := 0
	for i in LANE_COUNT:
		var on := Input.is_action_pressed(Lanes.action_name(i))
		if on:
			held += 1
		var lamp := lamps.get_child(i) as Label
		lamp.text = "%s\n%d" % [Lanes.label(i), _hits[i]]
		lamp.modulate = Color(1, 0.85, 0.2) if on else Color(0.6, 0.6, 0.7)
	_max_held = maxi(_max_held, held)
	info.text = "Maid Dragon Casino - 入力テスト\n同時押し: %d（最大 %d）  タッチ端末: %s" % [
		held, _max_held, "あり" if Lanes.is_touch_device() else "なし"]


func _on_resized() -> void:
	var view := get_viewport().get_visible_rect().size
	var lamps_size := lamps.get_combined_minimum_size()
	lamps.position = Vector2((view.x - lamps_size.x) / 2.0, view.y * 0.3)
	rotate_hint.visible = view.y > view.x
	touch_pad.visible = not rotate_hint.visible
	rotate_hint.size = view
