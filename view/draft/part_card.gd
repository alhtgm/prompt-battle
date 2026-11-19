# パーツのカード1枚（押すと選ぶ）。上に種類の色の帯、名前、動き方、ステータスを短く出す。
# 合わせる・フォーカスすると hovered、離れると unhovered を出す（吹き出しを出すのは画面の役目）。
extends Button

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")

const CARD_SIZE := Vector2(212, 120)

signal hovered(card: Button)
signal unhovered(card: Button)

var part: PartInstance
var name_label: Label
## ステータスの行（比べる印 ▲▼ に色を付けるので RichTextLabel）
var stats_label: RichTextLabel
## いつも札を出しておくか
var always_badge: bool = false
var _mark: Label


## group が null なら選べないカード（見るだけ）。badge は右下の札（"NEW" など）。
## compare を渡すと、同じ名前のステータスを比べて ▲（良い）▼（悪い）を付ける
func setup(data: GameData, p: PartInstance, group: ButtonGroup, badge: String = "", compare: PartInstance = null) -> void:
	part = p
	toggle_mode = group != null
	button_group = group
	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	var kind_col: Color = Look.KIND_COLORS.get(p.kind, Look.UI_TEXT)
	add_theme_stylebox_override("normal", _box(Color(0.1, 0.095, 0.085), Look.UI_BORDER, 1))
	add_theme_stylebox_override("hover", _box(Color(0.15, 0.13, 0.1), Look.UI_ACCENT.darkened(0.25), 1))
	add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Look.UI_ACCENT.darkened(0.25), 1))
	add_theme_stylebox_override("pressed", _box(Color(0.2, 0.15, 0.08), Look.UI_ACCENT, 3))
	add_theme_stylebox_override("hover_pressed", _box(Color(0.23, 0.17, 0.09), Look.UI_ACCENT, 3))

	var stripe := ColorRect.new()
	stripe.color = kind_col
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 4
	add_child(stripe)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 10
	box.offset_right = -10
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	name_label = _label(box, data.get_part(p.def_id).name, 20, Look.UI_TEXT)
	_label(box, UiText.part_tagline(data, p), 14, kind_col.darkened(0.1))
	var stats := PackedStringArray()
	var def: GameData.PartDef = data.get_part(p.def_id)
	for s: String in def.stat_names():
		stats.append(UiText.stat_text(s, p.get_stat(s)) + _compare_mark(s, p, compare))
	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_label.add_theme_font_size_override("normal_font_size", 14)
	stats_label.add_theme_color_override("default_color", Color(0.62, 0.6, 0.55))
	stats_label.text = " / ".join(stats)
	box.add_child(stats_label)
	# 選んでいる印（カードの下。名前に重ならないように、残りの高さを空けてから置く）
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill)
	_mark = _label(box, badge if not badge.is_empty() else "選択中", 13, Color.BLACK)
	_mark.size_flags_horizontal = Control.SIZE_SHRINK_END
	_mark.clip_text = false
	var ms := StyleBoxFlat.new()
	ms.bg_color = Look.UI_ACCENT
	ms.content_margin_left = 8
	ms.content_margin_right = 8
	_mark.add_theme_stylebox_override("normal", ms)
	# 選んでいないときも場所は取っておき、選んでもカードの中身が動かないようにする（札があればいつも出す）
	_mark.modulate.a = 1.0 if not badge.is_empty() else 0.0
	if not badge.is_empty():
		always_badge = true
	toggled.connect(func(on: bool) -> void: _mark.modulate.a = 1.0 if on or always_badge else 0.0)
	mouse_entered.connect(func() -> void: hovered.emit(self))
	focus_entered.connect(func() -> void: hovered.emit(self))
	mouse_exited.connect(func() -> void: unhovered.emit(self))
	focus_exited.connect(func() -> void: unhovered.emit(self))


## 比べる相手と同じステータスがあれば、良ければ緑の▲、悪ければ赤の▼（小さいほど良いものは逆）
static func _compare_mark(stat: String, p: PartInstance, other: PartInstance) -> String:
	if other == null or other == p or not other.stats.has(stat):
		return ""
	var diff: float = p.get_stat(stat) - other.get_stat(stat)
	if absf(diff) < 0.001:
		return ""
	var better: bool = (diff < 0.0) if UiText.LOWER_IS_BETTER.has(stat) else (diff > 0.0)
	return " [color=#8cd973]▲[/color]" if better else " [color=#f06450]▼[/color]"


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	return s


func _label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	parent.add_child(l)
	return l
