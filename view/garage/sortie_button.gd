# 出撃ボタン。黄と黒の斜めの警告ストライプ（導火線の縞と同じ「/」の向き）で、画面の中で一番目立たせる。
# 縞は小さな絵を作ってタイル状に敷く。見た目だけの部品で、押したときの処理は画面が pressed につなぐ。値は view/look.gd。
extends Button

const Look := preload("res://view/look.gd")


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Look.SORTIE_SIZE
	add_theme_font_size_override("font_size", Look.SORTIE_FONT)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, Look.SORTIE_TEXT)
	add_theme_color_override("font_outline_color", Look.HAZARD_BLACK)
	add_theme_constant_override("outline_size", Look.SORTIE_OUTLINE)
	add_theme_stylebox_override("normal", _stripes(1.0))
	add_theme_stylebox_override("hover", _stripes(Look.SORTIE_HOVER_LIGHT))
	add_theme_stylebox_override("pressed", _stripes(Look.SORTIE_PRESSED_LIGHT))
	add_theme_stylebox_override("hover_pressed", _stripes(Look.SORTIE_PRESSED_LIGHT))
	add_theme_stylebox_override("disabled", _stripes(0.45))
	# キーボードで合わせたときは、縞の上に明るい枠だけを重ねる
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Look.UI_ACCENT.lightened(0.3)
	focus.set_border_width_all(2)
	add_theme_stylebox_override("focus", focus)


## 縞の下地。light は明るさ（1.0 が基準。合わせると明るく、押すと暗く）
static func _stripes(light: float) -> StyleBoxTexture:
	var n: int = Look.HAZARD_STRIPE_PX * 2  # 黄と黒で1周期。タイルの縦横を周期と同じにすると、つなぎ目が出ない
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var yellow: Color = Look.HAZARD_YELLOW * light
	var black: Color = Look.HAZARD_BLACK * light
	yellow.a = 1.0
	black.a = 1.0
	for y: int in n:
		for x: int in n:
			# x + y が同じ点は「/」の向きに並ぶ
			img.set_pixel(x, y, yellow if (x + y) % n < Look.HAZARD_STRIPE_PX else black)
	var s := StyleBoxTexture.new()
	s.texture = ImageTexture.create_from_image(img)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.set_content_margin_all(6)
	return s
