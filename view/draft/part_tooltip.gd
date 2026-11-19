# パーツの吹き出し。カードに合わせると横に出て、回る見本（3D）・効果の説明・ステータスを見せる。
# ステータスは、抽選の幅のどこに入ったかを棒で見せる。状態は読むだけで、操作は受け取らない（マウスを素通しする）。
extends PanelContainer

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const Showroom := preload("res://view/showroom.gd")

const WIDTH: float = 340.0
## カードとの隙間と、矢印の大きさ
const GAP: float = 18.0
const ARROW: float = 12.0
const FADE_SEC: float = 0.12
const COL_DIM := Color(0.6, 0.58, 0.53)
const COL_GOOD := Color(0.55, 0.85, 0.45)
const COL_BAD := Color(0.95, 0.45, 0.35)

var data: GameData
## 今見せているパーツ（隠れていれば null）
var part: PartInstance = null
var preview: Showroom
var kind_label: Label
var name_label: Label
var desc_label: Label
var stats_box: GridContainer
var fixed_label: Label
## 矢印を左右どちらに出すか（true なら左。吹き出しがカードの右にある）
var _arrow_left: bool = true
var _arrow_y: float = 0.0
var _tween: Tween = null


func setup(game_data: GameData) -> void:
	data = game_data
	top_level = true
	z_index = 20
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.065, 0.06, 0.97)
	s.border_color = Look.UI_ACCENT.darkened(0.2)
	s.set_border_width_all(2)
	s.set_content_margin_all(12)
	s.shadow_color = Color(0, 0, 0, 0.6)
	s.shadow_size = 8
	add_theme_stylebox_override("panel", s)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	kind_label = _label(head, "", 14, Color.BLACK)
	kind_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tag := StyleBoxFlat.new()
	tag.bg_color = Color.WHITE
	tag.set_content_margin_all(3)
	tag.content_margin_left = 8
	tag.content_margin_right = 8
	kind_label.add_theme_stylebox_override("normal", tag)
	name_label = _label(head, "", 24, Look.UI_ACCENT)

	# 見本：自分だけの3D空間に、低い解像度で描いて拡大する
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color(0, 0, 0)
	fs.border_color = Look.UI_BORDER
	fs.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", fs)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = Look.PREVIEW_SHRINK
	container.custom_minimum_size = Look.PREVIEW_SIZE
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	container.add_child(vp)
	preview = Showroom.new()
	vp.add_child(preview)
	preview.setup(data, Look.PREVIEW_STAGE)

	desc_label = _label(box, "", 16, Look.UI_TEXT)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(WIDTH, 0)  # 幅を決めておかないと、折り返しの高さを細い幅で測って縦に伸びる
	stats_box = GridContainer.new()
	stats_box.columns = 3
	stats_box.add_theme_constant_override("h_separation", 10)
	stats_box.add_theme_constant_override("v_separation", 4)
	box.add_child(stats_box)
	fixed_label = _label(box, "", 14, COL_DIM)
	fixed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixed_label.custom_minimum_size = Vector2(WIDTH, 0)


## anchor（カード）の横に、p の吹き出しを出す
func show_for(p: PartInstance, anchor: Control) -> void:
	var def: GameData.PartDef = data.get_part(p.def_id)
	if def == null:
		return
	if part != p:
		part = p
		_fill(p, def)
	visible = true
	reset_size()
	_place(anchor.get_global_rect())
	if _tween != null:
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_SEC)


func hide_tip() -> void:
	visible = false
	part = null


func _fill(p: PartInstance, def: GameData.PartDef) -> void:
	var kind_col: Color = Look.KIND_COLORS.get(def.kind, Look.UI_TEXT)
	kind_label.text = UiText.KIND_LABELS.get(def.kind, def.kind)
	(kind_label.get_theme_stylebox("normal") as StyleBoxFlat).bg_color = kind_col
	name_label.text = def.name
	var how: String = UiText.part_tagline(data, p)
	desc_label.text = "【%s】%s" % [how, UiText.part_description(data, p)]

	# 見本の機体：フレームならそのフレームだけ。武器とスキルは、暗い色の台に載せて見せる
	var b: Variant
	var body: Color = Look.PREVIEW_BASE_COLOR
	match def.kind:
		GameData.KIND_FRAME:
			b = Showroom.make_build(def.id, [], [])
			body = Look.SIDE_BODY[0]
		GameData.KIND_WEAPON:
			b = Showroom.make_build(Look.PREVIEW_BASE_FRAME, [def.id], [])
		_:
			b = Showroom.make_build(Look.PREVIEW_BASE_FRAME, [], [def.id])
	preview.show_build(b, body, kind_col)

	for c: Node in stats_box.get_children():
		stats_box.remove_child(c)
		c.queue_free()
	for stat: String in def.stat_names():
		var v: float = p.get_stat(stat)
		var r: GameData.StatRange = def.stats[stat]
		_label(stats_box, UiText.stat_text(stat, v), 17, Look.UI_TEXT)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(90, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t: float = 0.5 if r.max_value <= r.min_value else clampf((v - r.min_value) / (r.max_value - r.min_value), 0.0, 1.0)
		bar.value = t * 100.0
		var good: float = 1.0 - t if UiText.LOWER_IS_BETTER.has(stat) else t
		var fill := StyleBoxFlat.new()
		fill.bg_color = COL_BAD.lerp(COL_GOOD, good)
		bar.add_theme_stylebox_override("fill", fill)
		stats_box.add_child(bar)
		_label(stats_box, _span(stat, r), 13, COL_DIM)
	var fixed: PackedStringArray = UiText.part_fixed_lines(data, p)
	if def.kind == GameData.KIND_FRAME:
		fixed.insert(0, "武器%d・スキル%d" % [def.weapon_slots, def.skill_slots])
	fixed_label.text = " / ".join(fixed)
	fixed_label.visible = not fixed.is_empty()


## カードの右に置く。はみ出すなら左。縦はカードの真ん中に合わせ、画面からはみ出さないようにずらす
func _place(rect: Rect2) -> void:
	var screen: Vector2 = get_viewport_rect().size
	var x: float = rect.end.x + GAP
	_arrow_left = true
	if x + size.x > screen.x - 8.0:
		x = rect.position.x - GAP - size.x
		_arrow_left = false
	var y: float = clampf(rect.get_center().y - size.y * 0.5, 8.0, maxf(8.0, screen.y - size.y - 8.0))
	global_position = Vector2(x, y)
	_arrow_y = clampf(rect.get_center().y - y, ARROW + 6.0, size.y - ARROW - 6.0)
	queue_redraw()


## カードを指す矢印（吹き出しのしっぽ）
func _draw() -> void:
	var tip_x: float = -GAP + 4.0 if _arrow_left else size.x + GAP - 4.0
	var base_x: float = 1.0 if _arrow_left else size.x - 1.0
	var pts := PackedVector2Array([
		Vector2(base_x, _arrow_y - ARROW), Vector2(tip_x, _arrow_y), Vector2(base_x, _arrow_y + ARROW)])
	draw_colored_polygon(pts, Color(0.07, 0.065, 0.06, 0.97))
	draw_polyline(pts, Look.UI_ACCENT.darkened(0.2), 2.0)


## 抽選の幅（ステータスの文字と同じ単位で）
static func _span(stat: String, r: GameData.StatRange) -> String:
	if r.max_value <= r.min_value:
		return "固定"
	if stat in ["speed_penalty", "damage_cut"]:
		return "%d〜%d%%" % [roundi(r.min_value * 100.0), roundi(r.max_value * 100.0)]
	return "%s〜%s" % [_num(r.min_value), _num(r.max_value)]


static func _num(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.001 else "%.2f" % v


func _label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
