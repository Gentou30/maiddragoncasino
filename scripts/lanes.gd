extends Node

## 操作レーンの定義（Autoload: Lanes）。
## キーボードとタッチボタンはどちらもここで登録したアクション "lane_N" を発火する。
## ゲーム側は event.is_action_pressed("lane_N") だけを見れば入力元を区別しなくてよい。
## レーンを増やすときはこの表に1行足すだけでキー・タッチボタンの両方に反映される。

# physical_keycode を使うので JIS/US などキーボード配列が違っても同じ位置のキーになる。
# 左手 4 キー + 右手 4 キー。
const LANES: Array[Dictionary] = [
	{"key": KEY_A, "label": "A"},
	{"key": KEY_S, "label": "S"},
	{"key": KEY_D, "label": "D"},
	{"key": KEY_F, "label": "F"},
	{"key": KEY_J, "label": "J"},
	{"key": KEY_K, "label": "K"},
	{"key": KEY_L, "label": "L"},
	{"key": KEY_SEMICOLON, "label": ";"},
]


func _ready() -> void:
	for i in LANES.size():
		var action := action_name(i)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = LANES[i]["key"]
		InputMap.action_add_event(action, ev)


func count() -> int:
	return LANES.size()


func action_name(i: int) -> String:
	return "lane_%d" % i


func label(i: int) -> String:
	return LANES[i]["label"]


## event が押下（キーリピートは除く）ならそのレーン番号、そうでなければ -1。
func pressed_lane(event: InputEvent) -> int:
	for i in LANES.size():
		if event.is_action_pressed(action_name(i), false, true):
			return i
	return -1


func is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available()
