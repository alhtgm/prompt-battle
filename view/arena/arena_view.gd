# 3Dのアリーナ。床・壁・穴・修理ステーションを置き、バトルの状態を読んで機体・弾・火花を映す。
# 薄暗い中に吊った電球の光、壁の外の松明、穴の底の赤い光、修理ステーションの緑の光、霧。強い被弾で画面が揺れる。
# 状態は読むだけで書き換えない。カメラは2機の真ん中を斜め上から追う。見た目の値は view/look.gd。
extends Node3D

const GameData := preload("res://core/game_data.gd")
const RobotView := preload("res://view/arena/robot_view.gd")
const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")
const Torch := preload("res://view/arena/torch.gd")

## カメラの位置（見る点からのずれ）と追いかける速さ
const CAMERA_OFFSET := Vector3(0, 14, 12)
const CAMERA_FOLLOW: float = 3.0
## カメラが見る点を、アリーナの中心からこれ以上離さない（場外を映しすぎないように）
const CAMERA_LIMIT: float = 6.0
## 2機目の頭上の文字を上げる量
const LABEL_LIFT: float = 0.8
## 火花が消えるまでの秒数
const SPARK_LIFE: float = 0.6

var data: GameData
var sim: Variant = null
var robot_views: Array[Node3D] = []
var camera: Camera3D
var _shots: Array[MeshInstance3D] = []
var _sparks: Array = []  # [ノード, 残り時間]
var _log_seen: int = 0
var _look_at := Vector3.ZERO
var _shake: float = 0.0
var _time: float = 0.0
var _shot_mat: StandardMaterial3D
## 壁の外の松明
var torches: Array[Node3D] = []
## 床のタイル
var floor_tiles: Array[MeshInstance3D] = []
var _spark_mat: StandardMaterial3D


func setup(game_data: GameData) -> void:
	data = game_data
	var arena: Dictionary = data.rules["battle"]["arena"]
	var half: float = float(arena["half_size"])
	_add_environment()
	_add_lights(half)

	# 床（汚れたコンクリート）。模様を世界の座標で貼るので、タイルに分けても継ぎ目は見えない
	var floor_mat: StandardMaterial3D = Grime.material(Look.FLOOR_COLOR, 0.0, 0.95, 0.08).duplicate()
	floor_mat.uv1_world_triplanar = true
	var n: int = maxi(1, ceili(half * 2.0 / Look.FLOOR_TILE))
	var tile: float = half * 2.0 / float(n)
	for ix: int in n:
		for iz: int in n:
			var c := Vector3(-half + tile * (ix + 0.5), -0.2, -half + tile * (iz + 0.5))
			floor_tiles.append(_box(Vector3(tile, 0.4, tile), c, floor_mat))
	# 壁（さびた鉄板）
	var wall: StandardMaterial3D = Grime.material(Look.WALL_COLOR, 0.55, 0.75, 0.25)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(half * 2.0 + 1.0, 1.2, 0.5), Vector3(0, 0.6, s * (half + 0.25)), wall)
		_box(Vector3(0.5, 1.2, half * 2.0), Vector3(s * (half + 0.25), 0.6, 0), wall)
	# 穴：黒い円と黄色い縁、底から赤い光
	for pit: Dictionary in arena["pits"]:
		var c := Vector3(float(pit["x"]), 0.0, float(pit["z"]))
		var r: float = float(pit["r"])
		_disc(r + 0.25, c + Vector3(0, 0.01, 0), Grime.material(Look.PIT_RIM_COLOR, 0.3, 0.8, 0.6))
		_disc(r, c + Vector3(0, 0.02, 0), _flat(Color(0.0, 0.0, 0.0)))
		_light(c + Vector3(0, 0.6, 0), Look.PIT_LIGHT, Look.PIT_LIGHT_ENERGY, r * 2.2)
	# 修理ステーション：鈍く光る緑の円と、緑の光
	for pad: Dictionary in arena["repair_pads"]:
		var c := Vector3(float(pad["x"]), 0.0, float(pad["z"]))
		_disc(float(pad["r"]), c + Vector3(0, 0.02, 0), Grime.material(Look.PAD_COLOR, 0.2, 0.6, 0.5, Look.PAD_LIGHT * 0.5))
		_light(c + Vector3(0, 1.2, 0), Look.PAD_LIGHT, Look.PAD_LIGHT_ENERGY, 5.0)

	# 壁の外の松明
	var reach: float = half + Look.TORCH_OUTSET
	for i: int in Look.TORCH_SPOTS.size():
		var spot: Vector2 = Look.TORCH_SPOTS[i]
		var t: Node3D = Torch.new()
		t.position = Vector3(spot.x * reach, 0.0, spot.y * reach)
		add_child(t)
		t.setup(float(i) * 1.37)  # 松明ごとに揺れをずらす
		torches.append(t)

	camera = Camera3D.new()
	camera.fov = 55.0
	camera.current = true
	add_child(camera)
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.ZERO)

	_shot_mat = _glow_mat(Color(1.0, 0.9, 0.55))
	_spark_mat = _glow_mat(Look.SPARK_COLOR)


func _add_environment() -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Look.BACKGROUND
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Look.AMBIENT
	e.ambient_light_energy = Look.AMBIENT_ENERGY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.fog_enabled = true
	e.fog_light_color = Look.FOG_COLOR
	e.fog_density = Look.FOG_DENSITY
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.05
	var env := WorldEnvironment.new()
	env.environment = e
	add_child(env)


func _add_lights(half: float) -> void:
	# 真上に吊った電球（影を落とす）。電球はカメラより低い位置にあって映り込むので、光だけにする
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, Look.LAMP_HEIGHT, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_color = Look.LAMP_COLOR
	lamp.light_energy = Look.LAMP_ENERGY
	lamp.spot_range = Look.LAMP_HEIGHT + 6.0
	lamp.spot_angle = Look.LAMP_ANGLE_DEG
	lamp.spot_attenuation = 0.6
	lamp.shadow_enabled = true
	add_child(lamp)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 140, 0)
	fill.light_color = Look.FILL_COLOR
	fill.light_energy = Look.FILL_ENERGY
	add_child(fill)


## 映すバトルを決める（機体の見た目を作り直す）
func bind(battle_sim: Variant) -> void:
	sim = battle_sim
	for v: Node3D in robot_views:
		v.queue_free()
	robot_views.clear()
	var radius: float = float(data.rule("battle.robot.radius"))
	for i: int in 2:
		var v: Node3D = RobotView.new()
		add_child(v)
		v.setup(data, sim.robots[i].build, radius, Look.SIDE_BODY[i], Look.SIDE_GLOW[i], LABEL_LIFT * i)
		robot_views.append(v)
	_log_seen = sim.log.size()
	sync(0.0)
	_look_at = _midpoint()


func _process(delta: float) -> void:
	if sim != null:
		sync(delta)
	else:
		_time += delta
	for t: Node3D in torches:
		t.flicker(_time)


## バトルの状態を読んで、機体・弾・火花・カメラを合わせる
func sync(delta: float) -> void:
	_time += delta
	for i: int in 2:
		robot_views[i].sync(sim.robots[i], delta)
	_sync_shots()
	_spawn_sparks()
	_update_sparks(delta)
	_look_at = _look_at.lerp(_midpoint(), minf(1.0, CAMERA_FOLLOW * delta))
	# 揺れは時間の関数で作る（乱数は使わない）
	_shake = maxf(0.0, _shake - Look.SHAKE_DECAY * delta * _shake)
	var wobble := Vector3(sin(_time * 53.0), cos(_time * 47.0), sin(_time * 61.0)) * _shake
	camera.position = _look_at + CAMERA_OFFSET + wobble
	camera.look_at(_look_at + wobble * 0.5)


func _midpoint() -> Vector3:
	var a: Variant = sim.robots[0]
	var b: Variant = sim.robots[1]
	return Vector3(clampf((a.x + b.x) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT), 0.0,
		clampf((a.z + b.z) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT))


func _sync_shots() -> void:
	while _shots.size() < sim.shots.size():
		var m := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.18, 0.18, 0.18)
		m.mesh = mesh
		m.material_override = _shot_mat
		add_child(m)
		_shots.append(m)
	for k: int in _shots.size():
		var on: bool = k < sim.shots.size()
		_shots[k].visible = on
		if on:
			_shots[k].position = Vector3(sim.shots[k].x, 0.9, sim.shots[k].z)


## 新しく起きた出来事から、火花・画面の揺れを出す
func _spawn_sparks() -> void:
	while _log_seen < sim.log.size():
		var e: Dictionary = sim.log[_log_seen]
		_log_seen += 1
		var t: String = e["type"]
		if t == "over" and str(e.get("reason", "")) == "destroyed":
			_shake = maxf(_shake, Look.EXPLOSION_SHAKE)  # 機体の爆発（爆発そのものは robot_view が出す）
			continue
		if t != "hit" and t != "flip" and t != "fall":
			continue
		var r: Variant = sim.robots[int(e["robot"])]
		if t == "hit" and e.has("by") and int(e["by"]) >= 0:
			# バリアを張っていれば、攻撃が来た向きに波紋を出す
			var by: Variant = sim.robots[int(e["by"])]
			robot_views[int(e["robot"])].on_hit(Vector3(by.x, 0.0, by.z))
		var big: bool = t != "hit" or float(e.get("damage", 0.0)) >= Look.SHAKE_DAMAGE
		if big:
			_shake = maxf(_shake, Look.SHAKE_AMOUNT * (1.6 if t == "fall" else 1.0))
		if t == "fall":
			continue
		_burst(Vector3(r.x, 0.9, r.z), 24 if big else 8)


## 火花を一度だけ散らす
func _burst(pos: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = SPARK_LIFE
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -18, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	mesh.material = _spark_mat
	p.mesh = mesh
	p.position = pos
	add_child(p)
	p.emitting = true
	_sparks.append([p, SPARK_LIFE + 0.2])


func _update_sparks(delta: float) -> void:
	for k: int in range(_sparks.size() - 1, -1, -1):
		var s: Array = _sparks[k]
		s[1] -= delta
		if s[1] <= 0.0:
			(s[0] as Node).queue_free()
			_sparks.remove_at(k)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _disc(radius: float, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 24  # 低い解像度に合わせて角ばらせる
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)


func _light(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.4
	add_child(l)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _glow_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	return mat
