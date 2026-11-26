# パーツ選び画面の右側。選んだフレーム・武器・スキルで組んだ機体を回して見せ、その下に3つの詳しい性能を並べる。
# 状態は読むだけで、操作は受け取らない。フレームの枠より多いパーツは見本に付けず、一覧に注意書きを出す。
extends VBoxContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const Showroom := preload("res://view/showroom.gd")
const PartDetail := preload("res://view/draft/part_detail.gd")


var data: GameData
var preview: Showroom
## 今見本に載せている機体
var build: Build = null
## 種類 → 1パーツ分の欄（PartDetail）
var details: Dictionary = {}
## 種類 → 名前・動き方・説明・ステータスの表・決まった値・注意書き（欄の中の部品）
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
	var d: PartDetail = PartDetail.new()
	add_child(d)
	d.setup(data, kind)
	details[kind] = d
	name_labels[kind] = d.name_label
	tagline_labels[kind] = d.tagline_label
	desc_labels[kind] = d.desc_label
	stats_boxes[kind] = d.stats_box
	fixed_labels[kind] = d.fixed_label
	note_labels[kind] = d.note_label


func _fill_section(kind: String, p: PartInstance, fits: bool) -> void:
	details[kind].show_part(p, fits)
