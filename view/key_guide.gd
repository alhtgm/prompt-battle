# 画面下部の共通キーガイド。「[←][→] 選ぶ　[↑][↓] 種類」のように、キーの札と短い説明を横に並べる。
# 見た目だけの部品で、キーの処理はしない（処理は各画面の _input などが行う）。色と大きさは view/look.gd。
extends HBoxContainer

const Look := preload("res://view/look.gd")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", Look.KEY_GUIDE_GAP)


## items は [[キーの文字, ...], 説明] の並び。例：[[["←", "→"], "選ぶ"], [["↑", "↓"], "種類"]]
func set_items(items: Array) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for item: Array in items:
		var group := HBoxContainer.new()
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_theme_constant_override("separation", 3)
		add_child(group)
		for key: String in item[0]:
			group.add_child(_keycap(key))
		var text := Label.new()
		text.text = " " + String(item[1])
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_font_size_override("font_size", Look.KEY_GUIDE_FONT)
		text.add_theme_color_override("font_color", Look.KEY_GUIDE_TEXT)
		group.add_child(text)


## キー1つ分の札（細い枠で囲んだ文字）
static func _keycap(key: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := StyleBoxFlat.new()
	s.bg_color = Look.KEY_GUIDE_CAP_BG
	s.border_color = Look.KEY_GUIDE_CAP_BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 0
	s.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", s)
	var l := Label.new()
	l.text = key
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", Look.KEY_GUIDE_FONT)
	l.add_theme_color_override("font_color", Look.UI_TEXT)
	cap.add_child(l)
	return cap
