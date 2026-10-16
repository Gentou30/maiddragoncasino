class_name RunData

## 3日間で使うアイテムと日替わりイベントの定義。
## 効果の中身は game.gd の _apply_mods() で解釈する。

const ITEMS: Array[Dictionary] = [
	{"id": "slot_mod", "name": "違法改造スロット", "good": "スロット報酬 x3", "bad": "リール速度 x1.6"},
	{"id": "black_card", "name": "ブラックカード", "good": "カード報酬 x2", "bad": "カード表示時間 半分"},
	{"id": "rigged_wheel", "name": "イカサマルーレット", "good": "当たり枠が2倍の広さ", "bad": "掛け金 x3（BUSTの損も3倍）"},
	{"id": "maneki", "name": "招き猫の置物", "good": "成功報酬 x1.5", "bad": "失敗の損失 x3"},
	{"id": "energy", "name": "謎のエナジードリンク", "good": "全収入 x1.3", "bad": "全ゲーム速度 x1.25"},
	{"id": "vip_loan", "name": "闇金VIP契約", "good": "全収入 x1.5", "bad": "借金 +¥10,000,000", "stackable": true},
]

const EVENTS: Array[Dictionary] = [
	{"id": "inflation", "name": "インフレの日", "desc": "収入 x2 / 損失 x2"},
	{"id": "rush", "name": "超高速営業", "desc": "全ゲーム速度 x1.3 / 収入 x1.3"},
	{"id": "bonus", "name": "ボーナスデー", "desc": "コンボ倍率の伸びが2倍"},
]

const NORMAL_DAY := {"id": "normal", "name": "平常営業", "desc": "特になし"}
