# パーツ選び画面の右側。選んだフレーム・武器・スキルで組んだ機体を回して見せ、その下に3つの詳しい性能を並べる。
# 状態は読むだけで、操作は受け取らない。フレームの枠より多いパーツは見本に付けず、一覧に注意書きを出す。
extends VBoxContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const Showroom := preload("res://view/showroom.gd")
const PartTooltip := preload("res://view/draft/part_tooltip.gd")

const COL_DIM := Color(0.6, 0.58, 0.53)
const COL_BAD := Color(0.95, 0.45, 0.35)
const NOTE_NO_SLOT: String = "このフレームには付けられない"

var data: GameData
var preview: Showroom
## 今見本に載せている機体
var build: Build = null
## 種類 → 名前・動き方・説明・ステータスの表・決まった値・注意書き
var name_labels: Dictionary = {}
var tagline_labels: Dictionary = {}
var desc_labels: Dictionary = {}
var stats_boxes: Dictionary = {}
var fixed_labels: Dictionary = {}
var note_labels: Dictionary = {}
## 見本の組み合わせ（同じなら組み直さない）
var _shown_key: String = ""


func setup(game_data: GameData) -> void:
	data = game_data
	add_theme_constant_override("separation", 3)
	# 見本：自分だけの3D空間に、低い解像度で描いて拡大する
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0)
	fs.border_color = Look.UI_BORDER
	fs.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = Look.DRAFT_PREVIEW_SHRINK
	container.custom_minimum_size = Look.DRAFT_PREVIEW_SIZE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	container.add_child(vp)
	preview = Showroom.new()
	vp.add_child(preview)
	preview.setup(data, Look.DRAFT_PREVIEW_STAGE)

	for kind: String in GameData.KINDS:
		_add_section(kind)


## picks は 種類 → PartInstance。見本を組み直し、一覧を書き直す
func show_parts(picks: Dictionary) -> void:
	var frame: PartInstance = picks.get(GameData.KIND_FRAME)
	if frame == null:
		return
	var fdef: GameData.PartDef = data.get_part(frame.def_id)
	var fits: Dictionary = {
		GameData.KIND_FRAME: true,
		GameData.KIND_WEAPON: fdef.weapon_slots > 0,
		GameData.KIND_SKILL: fdef.skill_slots > 0,
	}
	var weapons: Array = []
	var skills: Array = []
	if picks.has(GameData.KIND_WEAPON) and fits[GameData.KIND_WEAPON]:
		weapons.append(picks[GameData.KIND_WEAPON].def_id)
	if picks.has(GameData.KIND_SKILL) and fits[GameData.KIND_SKILL]:
		skills.append(picks[GameData.KIND_SKILL].def_id)
	var key: String = "%s|%s|%s" % [frame.def_id, ",".join(weapons), ",".join(skills)]
	if key != _shown_key:
		var first: bool = _shown_key.is_empty()
		_shown_key = key
		build = Showroom.make_build(frame.def_id, weapons, skills)
		preview.show_build(build, Look.SIDE_BODY[0], Look.SIDE_GLOW[0])
		if not first:
			preview.flicker()
	for kind: String in GameData.KINDS:
		if picks.has(kind):
			_fill_section(kind, picks[kind], bool(fits[kind]))


func _add_section(kind: String) -> void:
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
	name_labels[kind] = _label(head, "", 19, Look.UI_TEXT)
	var how: Label = _label(head, "", 14, kind_col.darkened(0.1))
	how.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tagline_labels[kind] = how
	var note: Label = _label(head, NOTE_NO_SLOT, 14, COL_BAD)
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.visible = false
	note_labels[kind] = note
	var desc: Label = _label(self, "", 14, Look.UI_TEXT.darkened(0.1))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_labels[kind] = desc
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	stats_boxes[kind] = grid
	var fixed: Label = _label(self, "", 13, COL_DIM)
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixed_labels[kind] = fixed


func _fill_section(kind: String, p: PartInstance, fits: bool) -> void:
	var def: GameData.PartDef = data.get_part(p.def_id)
	name_labels[kind].text = def.name
	tagline_labels[kind].text = UiText.part_tagline(data, p)
	note_labels[kind].visible = not fits
	# フレームの説明はどのフレームでも同じ文なので出さない（違いはステータスで見る）
	desc_labels[kind].text = UiText.part_description(data, p)
	desc_labels[kind].visible = kind != GameData.KIND_FRAME
	var grid: GridContainer = stats_boxes[kind]
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	PartTooltip.add_stat_rows(grid, data, p, 15)
	var fixed: PackedStringArray = UiText.part_fixed_lines(data, p)  # 武器・スキルの枠の数は名前の横（動き方の欄）に出ている
	fixed_labels[kind].text = " / ".join(fixed)
	fixed_labels[kind].visible = not fixed.is_empty()


func _label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
