# 3Dのアリーナ（骨組みでは箱と円柱）。床・壁・穴・修理ステーションを置き、バトルの状態を読んで機体・弾・火花を映す。
# 状態は読むだけで書き換えない。カメラは2機の真ん中を斜め上から追う。
extends Node3D

const GameData := preload("res://core/game_data.gd")
const RobotView := preload("res://view/arena/robot_view.gd")

const SIDE_COLORS: Array[Color] = [Color(0.25, 0.5, 0.95), Color(0.95, 0.5, 0.15)]
## カメラの位置（見る点からのずれ）と追いかける速さ（見た目だけの値）
const CAMERA_OFFSET := Vector3(0, 14, 12)
const CAMERA_FOLLOW: float = 3.0
## カメラが見る点を、アリーナの中心からこれ以上離さない（場外を映しすぎないように）
const CAMERA_LIMIT: float = 6.0
## 2機目の頭上の文字を上げる量
const LABEL_LIFT: float = 0.8
## 火花が消えるまでの秒数
const SPARK_LIFE: float = 0.25

var data: GameData
var sim: Variant = null
var robot_views: Array[Node3D] = []
var camera: Camera3D
var _shots: Array[MeshInstance3D] = []
var _sparks: Array = []  # [MeshInstance3D, 残り時間]
var _log_seen: int = 0
var _look_at := Vector3.ZERO
var _shot_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D


func setup(game_data: GameData) -> void:
	data = game_data
	var arena: Dictionary = data.rules["battle"]["arena"]
	var half: float = float(arena["half_size"])

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.04, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.35, 0.4)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	# 床と壁
	_box(Vector3(half * 2.0, 0.4, half * 2.0), Vector3(0, -0.2, 0), Color(0.22, 0.22, 0.23))
	var wall_col := Color(0.35, 0.33, 0.3)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(half * 2.0 + 1.0, 1.0, 0.5), Vector3(0, 0.5, s * (half + 0.25)), wall_col)
		_box(Vector3(0.5, 1.0, half * 2.0), Vector3(s * (half + 0.25), 0.5, 0), wall_col)
	# 穴：黒い円と赤い縁
	for pit: Dictionary in arena["pits"]:
		var c := Vector3(float(pit["x"]), 0.0, float(pit["z"]))
		_disc(float(pit["r"]) + 0.15, c + Vector3(0, 0.01, 0), Color(0.7, 0.15, 0.1), false)
		_disc(float(pit["r"]), c + Vector3(0, 0.02, 0), Color(0.0, 0.0, 0.0), false)
	# 修理ステーション：光る緑の円
	for pad: Dictionary in arena["repair_pads"]:
		_disc(float(pad["r"]), Vector3(float(pad["x"]), 0.02, float(pad["z"])), Color(0.2, 0.8, 0.35), true)

	camera = Camera3D.new()
	camera.fov = 55.0
	camera.current = true
	add_child(camera)
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.ZERO)

	_shot_mat = _unshaded(Color(1.0, 0.95, 0.6))
	_spark_mat = _unshaded(Color(1.0, 0.8, 0.3))


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
		v.setup(data, sim.robots[i].build, radius, SIDE_COLORS[i], LABEL_LIFT * i)
		robot_views.append(v)
	_log_seen = sim.log.size()
	sync(0.0)
	_look_at = _midpoint()


func _process(delta: float) -> void:
	if sim != null:
		sync(delta)


## バトルの状態を読んで、機体・弾・火花・カメラを合わせる
func sync(delta: float) -> void:
	for i: int in 2:
		robot_views[i].sync(sim.robots[i], delta)
	_sync_shots()
	_spawn_sparks()
	_update_sparks(delta)
	_look_at = _look_at.lerp(_midpoint(), minf(1.0, CAMERA_FOLLOW * delta))
	camera.position = _look_at + CAMERA_OFFSET
	camera.look_at(_look_at)


func _midpoint() -> Vector3:
	var a: Variant = sim.robots[0]
	var b: Variant = sim.robots[1]
	return Vector3(clampf((a.x + b.x) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT), 0.0,
		clampf((a.z + b.z) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT))


func _sync_shots() -> void:
	while _shots.size() < sim.shots.size():
		var m := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.24
		m.mesh = mesh
		m.material_override = _shot_mat
		add_child(m)
		_shots.append(m)
	for k: int in _shots.size():
		var on: bool = k < sim.shots.size()
		_shots[k].visible = on
		if on:
			_shots[k].position = Vector3(sim.shots[k].x, 0.9, sim.shots[k].z)


## 新しく起きた被弾の出来事から火花を出す
func _spawn_sparks() -> void:
	while _log_seen < sim.log.size():
		var e: Dictionary = sim.log[_log_seen]
		_log_seen += 1
		if e["type"] != "hit" and e["type"] != "flip":
			continue
		var r: Variant = sim.robots[int(e["robot"])]
		var m := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.5 if e["type"] == "flip" or float(e.get("damage", 0.0)) >= 8.0 else 0.25
		mesh.height = mesh.radius * 2.0
		m.mesh = mesh
		m.material_override = _spark_mat
		m.position = Vector3(r.x, 1.0, r.z)
		add_child(m)
		_sparks.append([m, SPARK_LIFE])


func _update_sparks(delta: float) -> void:
	for k: int in range(_sparks.size() - 1, -1, -1):
		var s: Array = _sparks[k]
		s[1] -= delta
		var m: MeshInstance3D = s[0]
		m.scale = Vector3.ONE * maxf(0.01, s[1] / SPARK_LIFE)
		if s[1] <= 0.0:
			m.queue_free()
			_sparks.remove_at(k)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	m.material_override = mat
	m.position = pos
	add_child(m)


func _disc(radius: float, pos: Vector3, color: Color, glow: bool) -> void:
	var m := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.02
	mesh.radial_segments = 48
	m.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if glow:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.position = pos
	add_child(m)


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
