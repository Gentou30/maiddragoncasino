extends Node2D

# 環境確認用の仮シーン。キー入力がブラウザで即反応するかを確かめる。

@onready var label: Label = $Label


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_A, KEY_S, KEY_D:
				label.text = "Maid Dragon Casino - setup OK\nPressed: %s" % OS.get_keycode_string(event.physical_keycode)
