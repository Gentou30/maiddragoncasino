class_name UiStyle

## 見た目の共通設定。色とパネルの描き方をここに集めて、画面ごとにばらばらにならないようにする。

const GOLD := Color(1.0, 0.82, 0.25)
const PINK := Color(1.0, 0.45, 0.8)
const NEON := Color(0.9, 0.3, 1.0)
const RED := Color(1.0, 0.35, 0.35)
const PANEL_BG := Color(0.07, 0.02, 0.12, 0.82)


## ネオンのふち取りと外側の光（影を光として使う）を持つ角丸パネル
static func panel(glow: Color, bg: Color = PANEL_BG, glow_size: int = 14, radius: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = glow
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(glow, 0.45)
	sb.shadow_size = glow_size
	sb.anti_aliasing = true
	return sb


static func button_styles(b: Button) -> void:
	b.add_theme_stylebox_override("normal", panel(NEON, Color(0.15, 0.04, 0.22, 0.95), 8, 14))
	b.add_theme_stylebox_override("hover", panel(GOLD, Color(0.25, 0.08, 0.3, 0.95), 12, 14))
	b.add_theme_stylebox_override("pressed", panel(GOLD, Color(0.4, 0.15, 0.1, 0.95), 12, 14))
	b.add_theme_stylebox_override("focus", panel(GOLD, Color(0, 0, 0, 0), 12, 14))
	b.add_theme_stylebox_override("disabled", panel(Color(0.4, 0.3, 0.5), Color(0.1, 0.05, 0.12, 0.9), 0, 14))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.65))


## 文字に黒いふち取りを付けて、派手な背景の上でも読めるようにする
static func outline(l: Label, size: int = 8) -> void:
	l.add_theme_constant_override("outline_size", size)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.08, 0.95))
