# パークのカード1枚（押すと選ばれて金枠になる。確定は画面の決定ボタン）。上に種類の札（機体・プロンプト・操縦士）と番号キー、名前、説明、
# 「今の機体にどう効くか」（例 HP 120 → 126）を出す。同じパークを持っていれば何個目かも出す。状態は読むだけ。
extends Button

const GameData := preload("res://core/game_data.gd")
const Player := preload("res://core/player.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")

const GROUP_LABELS: Dictionary = {"machine": "機体の強化", "prompt": "プロンプトの強化", "pilot": "操縦士の強化"}
## 効き方の行を出す上限（多すぎるとカードからあふれる）
const MAX_EFFECT_LINES: int = 4

var perk_id: String = ""
var name_label: Label
## 「今の機体にどう効くか」の行
var effect_lines: PackedStringArray = PackedStringArray()


## group：同じ組のカードは1枚だけ選ばれる
func setup(data: GameData, player: Player, id: String, key_no: int, group: ButtonGroup) -> void:
	perk_id = id
	toggle_mode = true
	button_group = group
	var perk: GameData.PerkDef = data.get_perk(id)
	var kind: String = perk_group(perk)
	var col: Color = Look.PERK_GROUP_COLORS.get(kind, Look.UI_TEXT)
	custom_minimum_size = Look.PERK_CARD_SIZE
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("normal", _box(Color(0.1, 0.095, 0.085), col.darkened(0.35), 2))
	# 金枠は選んだカードだけ。合わせたときは明るい枠、キーボードのフォーカスは薄い枠（選んだように見えないように）
	add_theme_stylebox_override("hover", _box(Color(0.15, 0.135, 0.11), col.lightened(0.1), 2))
	add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.22), 1))
	add_theme_stylebox_override("pressed", _box(Color(0.22, 0.16, 0.08), Look.UI_ACCENT, 4))
	add_theme_stylebox_override("hover_pressed", _box(Color(0.24, 0.18, 0.09), Look.UI_ACCENT, 4))
	add_theme_stylebox_override("disabled", _box(Color(0.07, 0.07, 0.065), Color(0.25, 0.22, 0.18), 1))

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_top = 12
	box.offset_right = -14
	box.offset_bottom = -12
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var tag: Label = _label(head, GROUP_LABELS.get(kind, "強化"), 13, Color.BLACK)
	var ts := StyleBoxFlat.new()
	ts.bg_color = col
	ts.content_margin_left = 8
	ts.content_margin_right = 8
	tag.add_theme_stylebox_override("normal", ts)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(gap)
	_label(head, "[%d]" % key_no, 14, Color(0.55, 0.53, 0.48))

	var owned: int = player.perks.count(id)
	name_label = _label(box, perk.name if perk != null else id, 26, Look.UI_ACCENT)
	if owned > 0:
		_label(box, "×%d 個目（重ねて効く）" % (owned + 1), 14, col)
	var desc: Label = _label(box, perk.description if perk != null else "", 16, Look.UI_TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.08)
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(line)
	effect_lines = effect_preview(data, player, id)
	for l: String in effect_lines:
		var el: Label = _label(box, l, 15, Color(0.75, 0.88, 0.6))
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 選んでいる印（カードの下）
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fill)
	var mark: Label = _label(box, "選択中", 13, Color.BLACK)
	mark.size_flags_horizontal = Control.SIZE_SHRINK_END
	var ms := StyleBoxFlat.new()
	ms.bg_color = Look.UI_ACCENT
	ms.content_margin_left = 8
	ms.content_margin_right = 8
	mark.add_theme_stylebox_override("normal", ms)
	mark.modulate.a = 0.0
	toggled.connect(func(on: bool) -> void: mark.modulate.a = 1.0 if on else 0.0)


## パークの種類（効果の対象の先頭で決める）
static func perk_group(perk: GameData.PerkDef) -> String:
	if perk == null or perk.effects.is_empty():
		return "machine"
	var head: String = str(perk.effects[0]["target"]).get_slice(".", 0)
	if head == "prompt":
		return "prompt"
	if head == "pilot":
		return "pilot"
	return "machine"


## 今の機体と持っているパークに、このパークを足したらどう変わるか（「名前 HP 120 → 126」の行）
static func effect_preview(data: GameData, player: Player, id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var perk: GameData.PerkDef = data.get_perk(id)
	if perk == null:
		return out
	var now := Player.new()
	now.build = player.build
	now.perks = player.perks.duplicate()
	var next := Player.new()
	next.build = player.build
	next.perks = player.perks.duplicate()
	next.perks.append(id)
	for e: Dictionary in perk.effects:
		var target: String = str(e["target"])
		match target:
			"build.weapon_slots", "build.skill_slots":
				if player.build == null:
					continue
				var fdef: GameData.PartDef = data.get_part(player.build.frame.def_id)
				var weapon: bool = target == "build.weapon_slots"
				var base: int = fdef.weapon_slots if weapon else fdef.skill_slots
				var a: int = base + (now.extra_weapon_slots(data) if weapon else now.extra_skill_slots(data))
				var b: int = base + (next.extra_weapon_slots(data) if weapon else next.extra_skill_slots(data))
				out.append("%sの枠 %d → %d" % ["武器" if weapon else "スキル", a, b])
			"prompt.max_chars":
				out.append("プロンプトの文字数 %d → %d" % [now.prompt_max_chars(data), next.prompt_max_chars(data)])
			_:
				if player.build != null:
					_append_part_changes(data, now.effective_build(data), next.effective_build(data), target, out)
	if out.is_empty():
		var kind: String = str(perk.effects[0]["target"]).get_slice(".", 0)
		out.append("今の機体には%sがない（付けると効く）" % UiText.KIND_LABELS.get(kind, "対象"))
	if out.size() > MAX_EFFECT_LINES:
		var more: int = out.size() - (MAX_EFFECT_LINES - 1)
		out.resize(MAX_EFFECT_LINES - 1)
		out.append("ほか %d 件" % more)
	return out


## 対象（例 weapon.damage、skill.*）のパーツごとに、変わったステータスを「名前 前 → 後」で足す
static func _append_part_changes(data: GameData, before: Variant, after: Variant, target: String, out: PackedStringArray) -> void:
	var kind: String = target.get_slice(".", 0)
	var pairs: Array = []
	if kind == GameData.KIND_FRAME:
		pairs.append([before.frame, after.frame])
	elif kind == GameData.KIND_WEAPON:
		for i: int in before.weapons.size():
			pairs.append([before.weapons[i], after.weapons[i]])
	elif kind == GameData.KIND_SKILL:
		for i: int in before.skills.size():
			pairs.append([before.skills[i], after.skills[i]])
	for pair: Array in pairs:
		var part_name: String = data.get_part(pair[0].def_id).name
		for stat: String in pair[0].stats.keys():
			var a: float = pair[0].get_stat(stat)
			var b: float = pair[1].get_stat(stat)
			if absf(a - b) < 0.0001:
				continue
			out.append("%s：%s → %s" % [part_name, UiText.stat_text(stat, a), _value_only(stat, b)])


## ステータスの値だけ（「→」の右側に名前を繰り返さないため）
static func _value_only(stat: String, v: float) -> String:
	var full: String = UiText.stat_text(stat, v)
	var label: String = UiText.STAT_LABELS.get(stat, stat)
	return full.trim_prefix(label).strip_edges()


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(4)
	return s


func _label(parent: Control, text: String, size_px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l
