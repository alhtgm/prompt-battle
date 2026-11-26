# パーツ1つ分の詳しい性能。上に区切り線、種類の札・名前・動き方、効果の説明、ステータスの表（棒と幅）、決まった値を並べる。
# パーツ選び（build_preview.gd）と組み立て画面で使う。状態は読むだけで、操作は受け取らない。
extends VBoxContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const PartTooltip := preload("res://view/draft/part_tooltip.gd")

const COL_DIM := Color(0.6, 0.58, 0.53)
const COL_BAD := Color(0.95, 0.45, 0.35)
const NOTE_NO_SLOT: String = "このフレームには付けられない"

var data: GameData
var kind: String = ""
var name_label: Label
var tagline_label: Label
var desc_label: Label
var stats_box: GridContainer
var fixed_label: Label
var note_label: Label
## ステータスの文字の大きさ
var _stat_font: int = 15


## kind の種類の札を付けた欄を作る。stat_font はステータスの表の文字の大きさ。
## compact なら行の間を詰める（組み立て画面の下の帯で、長い説明でも1画面に収めるため）
func setup(game_data: GameData, part_kind: String, stat_font: int = 15, compact: bool = false) -> void:
	data = game_data
	kind = part_kind
	_stat_font = stat_font
	add_theme_constant_override("separation", 1 if compact else 3)
	add_child(HSeparator.new())
	var kind_col: Color = Look.KIND_COLORS.get(kind, Look.UI_TEXT)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	var tag: Label = _label(head, UiText.KIND_LABELS.get(kind, kind), 13, Color.BLACK)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ts := StyleBoxFlat.new()
	ts.bg_color = kind_col
	ts.content_margin_left = 8
	ts.content_margin_right = 8
	tag.add_theme_stylebox_override("normal", ts)
	name_label = _label(head, "", 19, Look.UI_TEXT)
	tagline_label = _label(head, "", 14, kind_col.darkened(0.1))
	tagline_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tagline_label.clip_text = true  # 狭い欄でも名前の行が欄を広げないように
	tagline_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_label = _label(head, NOTE_NO_SLOT, 14, COL_BAD)
	note_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note_label.visible = false
	desc_label = _label(self, "", 14, Look.UI_TEXT.darkened(0.1))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_box = GridContainer.new()
	stats_box.columns = 3
	stats_box.add_theme_constant_override("h_separation", 10)
	stats_box.add_theme_constant_override("v_separation", 0 if compact else 2)
	add_child(stats_box)
	fixed_label = _label(self, "", 13, COL_DIM)
	fixed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact:
		# DotGothic16 は行が高いので、折り返した行の間を詰める
		desc_label.add_theme_constant_override("line_spacing", Look.GARAGE_DETAIL_LINE_SPACING)
		fixed_label.add_theme_constant_override("line_spacing", Look.GARAGE_DETAIL_LINE_SPACING)


## パーツ p の性能を書く。fits が false なら「このフレームには付けられない」と出す
func show_part(p: PartInstance, fits: bool = true) -> void:
	var def: GameData.PartDef = data.get_part(p.def_id)
	name_label.text = def.name
	tagline_label.text = UiText.part_tagline(data, p)
	note_label.visible = not fits
	# フレームの説明はどのフレームでも同じ文なので出さない（違いはステータスで見る）
	desc_label.text = UiText.part_description(data, p)
	desc_label.visible = kind != GameData.KIND_FRAME
	for c: Node in stats_box.get_children():
		stats_box.remove_child(c)
		c.queue_free()
	PartTooltip.add_stat_rows(stats_box, data, p, _stat_font)
	var fixed: PackedStringArray = UiText.part_fixed_lines(data, p)  # 武器・スキルの枠の数は名前の横（動き方の欄）に出ている
	fixed_label.text = " / ".join(fixed)
	fixed_label.visible = not fixed.is_empty()


func _label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
