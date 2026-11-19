# 機体を回して見せる小さな3Dの舞台（タイトルの背景、パーツの吹き出しの見本、最終順位の表彰台）。
# 薄暗い中に吊った電球、背後からの冷たい光、霧。試合の状態には関わらず、見た目だけを作る。値は view/look.gd。
extends Node3D

const GameData := preload("res://core/game_data.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const RobotView := preload("res://view/arena/robot_view.gd")
const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")

## 機体がカメラに背を向けた瞬間（1回転に1度）。このときに載せ替えれば、替わる瞬間が見えにくい
signal turned_away

## 機体の前（+x）がカメラと反対（-z）を向く台の角度
const AWAY_ANGLE: float = PI * 0.5
## 電球が瞬く時間（秒）と、そのときの明るさの割合
const FLICKER_SEC: float = 0.18
const FLICKER_DIM: float = 0.15

var data: GameData
var camera: Camera3D
## 今載っている機体の見た目（なければ null）
var robot: Node3D = null
var _turntable: Node3D
## 台ごとに回す機体（表彰台用。add_robot_at で足す）
var _pivots: Array[Node3D] = []
var _lamp: SpotLight3D
var _lamp_energy: float = 0.0
var _flicker_t: float = 0.0
var _spin: float = 0.0
var _angle: float = 0.0


## stage は view/look.gd の TITLE_STAGE / PREVIEW_STAGE / PODIUM_STAGE
func setup(game_data: GameData, stage: Dictionary) -> void:
	data = game_data
	_spin = deg_to_rad(float(stage.get("spin_deg_per_sec", 20.0)))
	_add_environment(bool(stage.get("floor", true)))
	_add_lights()
	if bool(stage.get("floor", true)):
		# 汚れた床
		_disc(30.0, 0.05, Vector3(0, -0.05, 0), Grime.material(Look.FLOOR_COLOR * 0.7, 0.0, 0.95, 0.08))
	if bool(stage.get("floor", true)) and bool(stage.get("turntable", true)):
		# さびたターンテーブル（縁が鈍く光る）
		_disc(2.3, 0.12, Vector3(0, 0.0, 0), Grime.material(Look.UI_ACCENT * 0.55, 0.7, 0.6, 1.0, Look.UI_ACCENT * 0.25))
		_disc(2.05, 0.14, Vector3(0, 0.01, 0), Grime.material(Color(0.22, 0.2, 0.18), 0.6, 0.7, 0.8))
	_turntable = Node3D.new()
	add_child(_turntable)
	camera = Camera3D.new()
	camera.fov = float(stage.get("fov", 45.0))
	camera.current = true
	add_child(camera)
	camera.position = stage.get("camera", Vector3(0, 2, 6))
	camera.look_at(stage.get("target", Vector3.ZERO))


## 載せる機体を差し替える。body / glow は地の色と光る目印の色
func show_build(build: Build, body: Color, glow: Color) -> void:
	if robot != null:
		robot.queue_free()
	robot = RobotView.new()
	_turntable.add_child(robot)
	var radius: float = float(data.rule("battle.robot.radius"))
	robot.setup(data, build, radius, body, glow)


## 台（箱）を置いて、その上で別に回る機体を載せる（表彰台用）。上から照らす光も足す。返すのは機体の見た目
func add_robot_at(build: Build, body: Color, glow: Color, pos: Vector3, block_height: float) -> Node3D:
	if block_height > 0.0:
		var m := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(3.0, block_height, 3.0)
		m.mesh = mesh
		m.material_override = Grime.material(Look.PODIUM_COLOR, 0.5, 0.7, 0.6)
		m.position = pos + Vector3(0, block_height * 0.5, 0)
		add_child(m)
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, block_height, 0)
	pivot.rotation.y = float(_pivots.size()) * 1.3  # 台ごとに向きをずらす
	add_child(pivot)
	_pivots.append(pivot)
	var light := SpotLight3D.new()
	light.position = pos + Vector3(0, block_height + 5.0, 0.8)
	light.rotation_degrees = Vector3(-90, 0, 0)
	light.light_color = Look.LAMP_COLOR
	light.light_energy = Look.LAMP_ENERGY * 0.3
	light.spot_range = 8.0
	light.spot_angle = 24.0
	add_child(light)
	var v: Node3D = RobotView.new()
	pivot.add_child(v)
	v.setup(data, build, float(data.rule("battle.robot.radius")), body, glow)
	return v


## 全パーツから機体を1つ組む。フレームを選び、その枠の数だけ武器とスキルを重ならないように付ける。
## rng は core/rng.gd（見た目だけに使う乱数。試合の乱数とは別）
static func random_build(game_data: GameData, rng: RefCounted) -> Build:
	var by_kind: Dictionary = {}
	for kind: String in GameData.KINDS:
		by_kind[kind] = []
	for def: GameData.PartDef in game_data.parts:
		by_kind[def.kind].append(def.id)
	var frame_id: String = str(rng.pick(by_kind[GameData.KIND_FRAME]))
	var fdef: GameData.PartDef = game_data.get_part(frame_id)
	var weapons: Array = rng.sample(by_kind[GameData.KIND_WEAPON], fdef.weapon_slots)
	var skills: Array = rng.sample(by_kind[GameData.KIND_SKILL], fdef.skill_slots)
	return make_build(frame_id, weapons, skills)


## パーツの型のIDから、見本の機体を組む（抽選の値は使わないので空のまま）
static func make_build(frame_id: String, weapon_ids: Array, skill_ids: Array) -> Build:
	var b := Build.new()
	b.frame = _part(frame_id, GameData.KIND_FRAME, 1)
	for id: Variant in weapon_ids:
		b.weapons.append(_part(str(id), GameData.KIND_WEAPON, 2 + b.weapons.size()))
	for id: Variant in skill_ids:
		b.skills.append(_part(str(id), GameData.KIND_SKILL, 2 + weapon_ids.size() + b.skills.size()))
	return b


## 見本のパーツ1つ。uid は機体の中で重ならない番号（試合の uid とは関係ない）
static func _part(def_id: String, kind: String, uid: int) -> PartInstance:
	var p := PartInstance.new()
	p.uid = uid
	p.def_id = def_id
	p.kind = kind
	return p


## 電球を一瞬暗くする（載せ替えの演出）
func flicker() -> void:
	_flicker_t = FLICKER_SEC


func _process(delta: float) -> void:
	var before: float = _angle
	_angle = wrapf(_angle + _spin * delta, 0.0, TAU)
	_turntable.rotation.y = _angle
	for pv: Node3D in _pivots:
		pv.rotation.y = wrapf(pv.rotation.y + _spin * delta, 0.0, TAU)
	if before < AWAY_ANGLE and _angle >= AWAY_ANGLE:
		turned_away.emit()
	if _flicker_t > 0.0:
		_flicker_t = maxf(0.0, _flicker_t - delta)
		# 暗い・明るいを2回繰り返す、古い電球の瞬き
		var on: bool = fmod(_flicker_t, FLICKER_SEC * 0.5) < FLICKER_SEC * 0.2
		_lamp.light_energy = _lamp_energy * (1.0 if on or _flicker_t <= 0.0 else FLICKER_DIM)


func _add_environment(with_fog: bool) -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Look.BACKGROUND
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Look.AMBIENT
	e.ambient_light_energy = Look.AMBIENT_ENERGY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = with_fog
	e.fog_light_color = Look.FOG_COLOR
	e.fog_density = Look.FOG_DENSITY * 3.0
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	var env := WorldEnvironment.new()
	env.environment = e
	add_child(env)


func _add_lights() -> void:
	# 真上の電球（影を落とす）
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 6.0, 0.6)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = Look.LAMP_ENERGY * 0.45
	lamp.spot_range = 10.0
	lamp.spot_angle = 32.0
	lamp.spot_attenuation = 0.8
	lamp.shadow_enabled = true
	add_child(lamp)
	_lamp = lamp
	_lamp_energy = lamp.light_energy
	# 背後からの冷たい光で、輪郭を浮かせる
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_color = Look.FILL_COLOR
	rim.light_energy = Look.FILL_ENERGY * 1.6
	add_child(rim)
	# 前から弱く当てる光（暗すぎて形が分からなくならないように）
	var front := OmniLight3D.new()
	front.position = Vector3(1.5, 1.8, 3.5)
	front.light_color = Look.LAMP_COLOR
	front.light_energy = 0.5
	front.omni_range = 8.0
	add_child(front)


func _disc(radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
