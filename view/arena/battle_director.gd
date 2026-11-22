# バトルの演出：試合の始まりの名札と VS・READY・FIGHT!、強い一撃のヒットストップ、ダメージの数字、掛け声（BACKSTAB! など）、
# 決着のスローモーションと黒帯と K.O.! の看板。試合の状態は読むだけで、時間の倍率は main.cinematic_scale に入れる。値は view/look.gd。
extends Control

const Look := preload("res://view/look.gd")
const Sfx := preload("res://view/sfx.gd")

## スキルを使ったときの掛け声（スキルの behavior ごと。自爆装置は導火線に火がついたときに出す）
const SKILL_CALLOUTS: Dictionary = {
	"booster": "BOOST!", "shield": "SHIELD UP!", "overclock": "OVERCLOCK!", "emp": "EMP!",
	"shockwave": "SHOCKWAVE!", "repair": "REPAIR!",
}

var main: Node
var arena: Node3D
var sim: Variant
var side_colors: Array[Color] = []
## 始まりの演出の経過秒（出していなければ -1）。テストと確認用
var intro_t: float = -1.0
## 決着の演出の経過秒（まだなら -1）
var ko_t: float = -1.0
## ヒットストップの残り秒（実時間）
var hitstop_left: float = 0.0
## 浮かんでいる数字と掛け声：{node, world, t, life, rise, jx}
var popups: Array[Dictionary] = []
## 決着の看板の文字（テストと確認用）
var banner_text: String = ""
## 出した掛け声の記録（テストと確認用）
var callouts_shown: Array[String] = []

var _log_seen: int = 0
var _last_hp: Array[float] = [0.0, 0.0]
var _pool: Array[float] = [0.0, 0.0]
var _pool_t: Array[float] = [0.0, 0.0]
var _gap: Array[float] = [0.0, 0.0]
var _jitter: int = 0
var _plates: Array[PanelContainer] = []
var _vs: Label
var _ready: Label
var _fight: Label
var _slammed: bool = false
var _fought: bool = false
var _flash: ColorRect
var _bars: Array[ColorRect] = []
var _banner: Label
var _sub: Label
var _small_player: AudioStreamPlayer
var _big_player: AudioStreamPlayer


func setup(main_node: Node, arena_node: Node3D, battle_sim: Variant, colors: Array[Color]) -> void:
	main = main_node
	arena = arena_node
	sim = battle_sim
	side_colors = colors
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_small_player = AudioStreamPlayer.new()
	add_child(_small_player)
	_big_player = AudioStreamPlayer.new()
	add_child(_big_player)
	for i: int in 2:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
		_bars.append(bar)
	if sim == null:
		return
	_log_seen = sim.log.size()
	for i: int in 2:
		_last_hp[i] = sim.robots[i].hp
	# 始まりの名札（左右から滑り込む）と VS・READY・FIGHT!
	for i: int in 2:
		_plates.append(_make_plate(i))
	_vs = _big_label("VS", 64, Look.CALLOUT_COLOR)
	_ready = _big_label("READY...", 46, Look.UI_TEXT)
	_fight = _big_label("FIGHT!", 96, Look.CALLOUT_HOT)
	_banner = _big_label("", 110, Look.CALLOUT_HOT)
	_sub = _big_label("", 40, Look.UI_TEXT)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	# 画面ができる前に数刻み進んでいることがあるので、始まって間もなければ始まりの演出を出す
	if sim.now() <= Look.INTRO_MAX_START_SEC and not sim.over:
		intro_t = 0.0


## 毎フレーム呼ぶ（delta は実時間）。時間の倍率を決めて main と arena に渡す
func update(delta: float) -> void:
	if sim == null:
		return
	var scale: float = 1.0
	var freeze_visual: bool = false
	if intro_t >= 0.0:
		intro_t += delta
		_update_intro()
		if intro_t < Look.INTRO_GO_AT:
			scale = 0.0
			freeze_visual = true
	_read_events()
	_update_numbers(delta)
	if hitstop_left > 0.0:
		hitstop_left -= delta
		scale = minf(scale, Look.HITSTOP_SCALE)
	if ko_t >= 0.0:
		ko_t += delta
		_update_ko()
		if ko_t < Look.KO_SLOWMO_SEC:
			scale = minf(scale, Look.KO_SLOWMO_SCALE)
	for i: int in 2:
		_gap[i] = maxf(0.0, _gap[i] - delta)
	_update_popups(delta)
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 2.5)
	var timed: bool = main != null and bool(main.get("cinematics")) and not main.session.is_online()
	if main != null:
		main.cinematic_scale = scale if timed else 1.0
	if arena != null:
		arena.time_scale = (1.0 if freeze_visual else scale) if timed else 1.0


# ---- 試合の始まり ----

func _update_intro() -> void:
	var t: float = intro_t
	var w: float = size.x
	var cy: float = size.y * 0.4
	for i: int in 2:
		var p: PanelContainer = _plates[i]
		p.reset_size()
		var k: float = _ease_out(clampf(t / Look.INTRO_SLIDE_SEC, 0.0, 1.0))
		var from_x: float = -p.size.x - 20.0 if i == 0 else w + 20.0
		var to_x: float = w * 0.5 - p.size.x - 70.0 if i == 0 else w * 0.5 + 70.0
		p.position = Vector2(lerpf(from_x, to_x, k), cy - p.size.y * 0.5)
		p.visible = t < Look.INTRO_READY_AT + 0.3
		p.modulate.a = 1.0 - clampf((t - Look.INTRO_READY_AT) / 0.3, 0.0, 1.0)
	# VS：名札がそろったら叩きつける
	_vs.visible = t >= Look.INTRO_SLIDE_SEC and t < Look.INTRO_READY_AT + 0.3
	if _vs.visible:
		if not _slammed:
			_slammed = true
			_play(_small_player, Sfx.slam())
		_place_center(_vs, Vector2(w * 0.5, cy), _slam_scale(t - Look.INTRO_SLIDE_SEC, 3.0))
		_vs.modulate.a = 1.0 - clampf((t - Look.INTRO_READY_AT) / 0.3, 0.0, 1.0)
	_ready.visible = t >= Look.INTRO_READY_AT and t < Look.INTRO_FIGHT_AT
	if _ready.visible:
		_place_center(_ready, Vector2(w * 0.5, cy), 1.0 + 0.04 * sin(t * 18.0))
		_ready.modulate.a = 0.6 + 0.4 * absf(sin(t * 9.0))
	_fight.visible = t >= Look.INTRO_FIGHT_AT
	if _fight.visible:
		if not _fought:
			_fought = true
			_flash.color.a = Look.FLASH_ALPHA
			_play(_big_player, Sfx.fight_stab())
			if arena != null:
				arena.punch(0.8)
		_place_center(_fight, Vector2(w * 0.5, cy), _slam_scale(t - Look.INTRO_FIGHT_AT, 3.2))
		_fight.modulate.a = 1.0 - clampf((t - Look.INTRO_END_AT + 0.3) / 0.3, 0.0, 1.0)
	if t >= Look.INTRO_END_AT:
		_end_intro()


func _end_intro() -> void:
	intro_t = -1.0
	for p: PanelContainer in _plates:
		p.visible = false
	_vs.visible = false
	_ready.visible = false
	_fight.visible = false


## 名札：チームの色の斜めの板に、機体の名前とフレームの名前
func _make_plate(i: int) -> PanelContainer:
	var r: Variant = sim.robots[i]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(side_colors[i].darkened(0.55), 0.92)
	style.border_color = side_colors[i]
	style.set_border_width_all(3)
	style.skew = Vector2(-0.25 if i == 0 else 0.25, 0.0)
	style.content_margin_left = 34
	style.content_margin_right = 34
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var name_l: Label = _plain_label(str(r.name), 40, side_colors[i])
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if i == 0 else HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(name_l)
	var sub_l: Label = _plain_label(_frame_name(r), 20, Look.UI_TEXT)
	sub_l.horizontal_alignment = name_l.horizontal_alignment
	box.add_child(sub_l)
	panel.visible = false
	add_child(panel)
	return panel


func _frame_name(r: Variant) -> String:
	if main == null or not ("build" in r) or r.build == null:
		return ""
	var def: Variant = main.data.get_part(r.build.frame.def_id)
	return str(def.name) if def != null else ""


# ---- 出来事を読む（ヒットストップ・掛け声・決着） ----

func _read_events() -> void:
	while _log_seen < sim.log.size():
		var e: Dictionary = sim.log[_log_seen]
		_log_seen += 1
		var t: String = e["type"]
		var i: int = int(e.get("robot", -1))
		match t:
			"hit":
				var dmg: float = float(e.get("damage", 0.0))
				var big: bool = dmg >= Look.HITSTOP_BIG_DAMAGE
				if ko_t < 0.0 and dmg >= Look.HITSTOP_DAMAGE:
					hitstop_left = maxf(hitstop_left, Look.HITSTOP_BIG_SEC if big else Look.HITSTOP_SEC)
					if arena != null:
						arena.punch(1.0 if big else 0.5)
				if bool(e.get("back", false)):
					_callout(i, "BACKSTAB!", Look.CALLOUT_HOT)
				elif big:
					_callout(i, "CRITICAL!", Look.CALLOUT_HOT)
			"flip":
				_callout(i, "FLIPPED!", Look.CALLOUT_COLOR)
				if ko_t < 0.0:
					hitstop_left = maxf(hitstop_left, Look.HITSTOP_BIG_SEC)
				if arena != null:
					arena.punch(0.8)
			"burn":
				_callout(i, "BURNING!", Look.CALLOUT_HOT)
			"hook_hit":
				_callout(i, "HOOKED!", Look.CALLOUT_COOL)
			"fuse":
				_gap[i] = 0.0  # 自爆の始まりは必ず見せる
				_callout(i, "SELF-DESTRUCT!", Look.CALLOUT_HOT)
			"skill":
				var text: String = str(SKILL_CALLOUTS.get(str(e.get("behavior", "")), ""))
				if not text.is_empty():
					_callout(i, text, Look.CALLOUT_COOL)
			"over":
				_start_ko(int(e.get("winner", -1)), str(e.get("reason", "")))


func _callout(i: int, text: String, col: Color) -> void:
	if i < 0 or i > 1 or _gap[i] > 0.0 or ko_t >= 0.0:
		return
	_gap[i] = Look.CALLOUT_GAP_SEC
	callouts_shown.append(text)
	var l: Label = _big_label(text, 34, col)
	l.rotation = -0.08 if i == 0 else 0.08
	l.visible = true
	var r: Variant = sim.robots[i]
	_add_popup(l, Vector3(r.x, 2.7, r.z), Look.CALLOUT_SEC, 26.0, 0.0)
	_play(_small_player, Sfx.slam())


# ---- ダメージの数字 ----

func _update_numbers(delta: float) -> void:
	for i: int in 2:
		var hp: float = sim.robots[i].hp
		var d: float = _last_hp[i] - hp
		_last_hp[i] = hp
		if d > 0.01:
			_pool[i] += d
			if _pool_t[i] <= 0.0:
				_pool_t[i] = Look.DMG_POOL_SEC
			if d >= Look.DMG_BIG:
				_flush(i)
		elif d < -0.5:
			_number(i, "+%d" % roundi(-d), Look.HEAL_NUMBER_COLOR, 36)
		if _pool_t[i] > 0.0:
			_pool_t[i] -= delta
			if _pool_t[i] <= 0.0:
				_flush(i)


func _flush(i: int) -> void:
	var amount: float = _pool[i]
	_pool[i] = 0.0
	_pool_t[i] = 0.0
	if amount < 0.5:
		return
	var big: bool = amount >= Look.DMG_BIG
	_number(i, "%d" % roundi(amount), Look.DMG_BIG_COLOR if big else Look.DMG_COLOR, 50 if big else 32)


func _number(i: int, text: String, col: Color, font: int) -> void:
	var l: Label = _big_label(text, font, col)
	l.visible = true
	var r: Variant = sim.robots[i]
	# 続けて出る数字が重ならないよう、左右に少しずつずらす（乱数は使わない）
	_jitter += 1
	var jx: float = float((_jitter * 37) % 5 - 2) * 14.0
	_add_popup(l, Vector3(r.x, 1.7, r.z), Look.DMG_POP_SEC, Look.DMG_RISE, jx)


func _add_popup(l: Label, world: Vector3, life: float, rise: float, jx: float) -> void:
	popups.append({"node": l, "world": world, "t": 0.0, "life": life, "rise": rise, "jx": jx})


func _update_popups(delta: float) -> void:
	for k: int in range(popups.size() - 1, -1, -1):
		var p: Dictionary = popups[k]
		p["t"] = float(p["t"]) + delta
		var l: Label = p["node"]
		var f: float = float(p["t"]) / float(p["life"])
		if f >= 1.0:
			l.queue_free()
			popups.remove_at(k)
			continue
		var at: Vector2 = _project(p["world"])
		if at.x < -9000.0:
			l.visible = false
			continue
		l.visible = true
		at += Vector2(float(p["jx"]), -float(p["rise"]) * _ease_out(f))
		_place_center(l, at, _slam_scale(float(p["t"]), 1.9))
		l.modulate.a = 1.0 - clampf((f - 0.65) / 0.35, 0.0, 1.0)


# ---- 決着 ----

func _start_ko(winner: int, reason: String) -> void:
	if ko_t >= 0.0:
		return
	if intro_t >= 0.0:
		_end_intro()
	ko_t = 0.0
	hitstop_left = 0.0
	# 浮かんでいる数字や掛け声は、看板と重ならないよう消す
	for p: Dictionary in popups:
		(p["node"] as Label).queue_free()
	popups.clear()
	match reason:
		"pit":
			banner_text = "RING OUT!" if winner >= 0 else "DOUBLE RING OUT!"
		"time":
			banner_text = "TIME UP!"
		"self_destruct":
			banner_text = "DOUBLE K.O.!"
		_:
			banner_text = "K.O.!" if winner >= 0 else "DOUBLE K.O.!"
	_banner.text = banner_text
	if winner >= 0:
		_sub.text = "%s  WINS!" % str(sim.robots[winner].name)
		_sub.add_theme_color_override("font_color", side_colors[winner])
	else:
		_sub.text = "DRAW"
	_flash.color.a = Look.FLASH_ALPHA
	_play(_big_player, Sfx.ko_boom())
	if arena == null:
		return
	arena.punch(1.0)
	var loser: int = 1 - winner if winner >= 0 else -1
	if loser >= 0 and reason != "time":
		var r: Variant = sim.robots[loser]
		arena.set_cinematic(Vector3(r.x, 0.0, r.z), 0.85, 0.55)
	else:
		arena.set_cinematic(Vector3.ZERO, 0.0, 0.25)


func _update_ko() -> void:
	var h: float = size.y * Look.KO_BAR * _ease_out(clampf(ko_t / 0.3, 0.0, 1.0))
	_bars[0].visible = true
	_bars[1].visible = true
	_bars[0].position = Vector2.ZERO
	_bars[0].size = Vector2(size.x, h)
	_bars[1].position = Vector2(0.0, size.y - h)
	_bars[1].size = Vector2(size.x, h)
	var bt: float = ko_t - Look.KO_BANNER_AT
	_banner.visible = bt >= 0.0
	if _banner.visible:
		var shake: Vector2 = Vector2(sin(ko_t * 61.0), cos(ko_t * 53.0)) * 6.0 * maxf(0.0, 1.0 - bt * 3.0)
		_place_center(_banner, Vector2(size.x * 0.5, size.y * 0.42) + shake, _slam_scale(bt, 3.4))
	_sub.visible = bt >= 0.35
	if _sub.visible:
		_place_center(_sub, Vector2(size.x * 0.5, size.y * 0.42 + 92.0), 1.0)
		_sub.modulate.a = clampf((bt - 0.35) / 0.25, 0.0, 1.0)


# ---- 部品 ----

## 世界の座標を画面の点にする（カメラの後ろなら x を -9999 にする）
func _project(world: Vector3) -> Vector2:
	if arena == null or arena.camera == null or arena.camera.is_position_behind(world):
		return Vector2(-9999.0, 0.0)
	return arena.camera.unproject_position(world) * float(Look.PIXEL_SHRINK)


## 叩きつける大きさ：from 倍から 0.12 秒で 1 倍へ縮み、少し弾む
static func _slam_scale(t: float, from: float) -> float:
	if t < 0.0:
		return from
	if t < 0.12:
		return lerpf(from, 0.92, t / 0.12)
	return lerpf(0.92, 1.0, clampf((t - 0.12) / 0.08, 0.0, 1.0))


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


func _place_center(l: Control, at: Vector2, s: float) -> void:
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE * s
	l.position = at - l.size * 0.5


func _big_label(text: String, font: int, col: Color) -> Label:
	var l: Label = _plain_label(text, font, col)
	l.add_theme_constant_override("outline_size", maxi(8, font / 6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.visible = false
	add_child(l)
	return l


func _plain_label(text: String, font: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	return l


func _play(player: AudioStreamPlayer, s: AudioStream) -> void:
	if player.is_inside_tree():
		player.stream = s
		player.play()
