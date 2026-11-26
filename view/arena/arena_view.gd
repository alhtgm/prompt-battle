# 3Dのアリーナ。床・壁・穴を置き、バトルの状態を読んで機体・弾・回復パック・火花を映す。
# 薄暗い中に吊った電球の光、壁の外の松明、穴の底の赤い光、霧。強い被弾で画面が揺れる。
# 状態は読むだけで書き換えない。カメラは2機の真ん中を斜め上から追う。見た目の値は view/look.gd。
# 開発用に、自由カメラ（見る点を中心に回す・動かす・近づく）と、機体1体を追うカメラに切り替えられる（操作は battle_screen）。
extends Node3D

const GameData := preload("res://core/game_data.gd")
## 撃つ武器の弾の見た目と、撃つ・当たるときの演出
const ShotFx := preload("res://view/arena/shot_fx.gd")
const RobotView := preload("res://view/arena/robot_view.gd")
const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")
const HealthPackView := preload("res://view/arena/health_pack_view.gd")
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

## カメラの動き方：いつもの追いかけるカメラ／自由カメラ／機体1体を追う
enum CameraMode { FOLLOW, FREE, TRACK }

var data: GameData
## 描いているステージ（data/stages.json の1つ）
var stage: Dictionary = {}
var sim: Variant = null
var robot_views: Array[Node3D] = []
var camera: Camera3D
var shot_fx: Node3D
## 回復パックの見た目（view/arena/health_pack_view.gd）
var health_packs: Node3D = null
var _sparks: Array = []  # [ノード, 残り時間]
var _log_seen: int = 0
var _look_at := Vector3.ZERO
var _shake: float = 0.0
var _time: float = 0.0
## 壁の外の松明
var torches: Array[Node3D] = []
## 床のタイル
var floor_tiles: Array[MeshInstance3D] = []
## 開発用のカメラ：今の動き方、追う機体（TRACK のとき）、見る点、回す角度（左右・上下）、見る点からの距離
var camera_mode: CameraMode = CameraMode.FOLLOW
var track_index: int = 0
var cam_pivot := Vector3.ZERO
var cam_yaw: float = 0.0
var cam_pitch: float = 0.0
var cam_dist: float = 0.0
## 止めている（開発用の一時停止）。機体の動きや火花も止め、カメラだけ動かせるようにする
var paused: bool = false
var _spark_mat: StandardMaterial3D
## 撃つ武器の名前（被弾の記録の武器名）→ パーツID。撃つ武器の被弾の火花は shot_fx が当たった所に出すので、ここでは出さない
var _shoot_names: Dictionary = {}


## arena_stage は描くステージ。空なら1ラウンド目のステージ
func setup(game_data: GameData, arena_stage: Dictionary = {}) -> void:
	data = game_data
	stage = arena_stage if not arena_stage.is_empty() else data.first_stage()
	var arena: Dictionary = stage
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

	shot_fx = ShotFx.new()
	add_child(shot_fx)
	shot_fx.setup(half, float(data.rule("battle.robot.radius")))
	for def: Variant in data.parts:
		if str(def.behavior) == "shoot":
			_shoot_names[str(def.name)] = str(def.id)
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
	# 回復パックの見た目はバトルごとに作り直す
	if health_packs != null:
		health_packs.queue_free()
	health_packs = HealthPackView.new()
	add_child(health_packs)
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
	var cam_delta: float = delta
	if paused:
		delta = 0.0  # 止めている間は、機体の落ちる動きや火花も止める（カメラだけ動かせる）
	_time += delta
	for i: int in 2:
		robot_views[i].sync(sim.robots[i], delta)
	shot_fx.sync(sim, delta)
	if health_packs != null and health_packs.is_inside_tree() and "packs" in sim:
		health_packs.sync(sim.packs, delta)
	_spawn_sparks()
	_update_sparks(delta)
	_look_at = _look_at.lerp(_midpoint(), minf(1.0, CAMERA_FOLLOW * delta))
	# 揺れは時間の関数で作る（乱数は使わない）
	_shake = maxf(0.0, _shake - Look.SHAKE_DECAY * delta * _shake)
	if camera_mode != CameraMode.FOLLOW:
		_sync_dev_camera(cam_delta)
		return
	var wobble := Vector3(sin(_time * 53.0), cos(_time * 47.0), sin(_time * 61.0)) * _shake
	camera.position = _look_at + CAMERA_OFFSET + wobble
	camera.look_at(_look_at + wobble * 0.5)


# ---- 開発用のカメラ ----

## 自由カメラにする（今のカメラの位置から始める）
func dev_free_camera() -> void:
	if camera_mode == CameraMode.FOLLOW:
		cam_pivot = _look_at
		var off: Vector3 = CAMERA_OFFSET
		cam_dist = off.length()
		cam_yaw = atan2(off.x, off.z)
		cam_pitch = asin(clampf(off.y / cam_dist, -1.0, 1.0))
	camera_mode = CameraMode.FREE


## 見る点を中心に回す（dx：左右、dy：上下。ラジアン）
func dev_orbit(dx: float, dy: float) -> void:
	dev_free_camera_keep_track()
	cam_yaw = wrapf(cam_yaw - dx, -PI, PI)
	cam_pitch = clampf(cam_pitch + dy, deg_to_rad(Look.DEV_CAM_PITCH_MIN_DEG), deg_to_rad(Look.DEV_CAM_PITCH_MAX_DEG))


## 平行に動かす（right：画面の右へ、forward：画面の奥へ。メートル）。機体を追っていたら自由カメラに切り替える
func dev_pan(right: float, forward: float) -> void:
	dev_free_camera()
	var r := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var f := Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
	var lim: float = float(stage["half_size"]) + Look.DEV_CAM_PAN_MARGIN
	cam_pivot += r * right + f * forward
	cam_pivot.x = clampf(cam_pivot.x, -lim, lim)
	cam_pivot.z = clampf(cam_pivot.z, -lim, lim)


## 近づく・離れる（factor が 1 より小さいと近づく）
func dev_zoom(factor: float) -> void:
	dev_free_camera_keep_track()
	cam_dist = clampf(cam_dist * factor, Look.DEV_CAM_DIST_MIN, Look.DEV_CAM_DIST_MAX)


## 機体1体を中心に追う（i は 0 か 1）
func dev_track(i: int) -> void:
	dev_free_camera()
	track_index = clampi(i, 0, 1)
	camera_mode = CameraMode.TRACK


## いつもの追いかけるカメラに戻す
func dev_reset_camera() -> void:
	camera_mode = CameraMode.FOLLOW


## 回す・近づく操作では、機体を追っているならそのまま追い続ける
func dev_free_camera_keep_track() -> void:
	if camera_mode == CameraMode.FOLLOW:
		dev_free_camera()


func _sync_dev_camera(delta: float) -> void:
	if camera_mode == CameraMode.TRACK and sim != null:
		var r: Variant = sim.robots[track_index]
		cam_pivot = cam_pivot.lerp(Vector3(r.x, 0.0, r.z), minf(1.0, CAMERA_FOLLOW * 2.0 * delta))
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	camera.position = cam_pivot + dir * cam_dist
	camera.look_at(cam_pivot)  # 自由に動かしている間は揺らさない（見たいところがぶれないように）


func _midpoint() -> Vector3:
	var a: Variant = sim.robots[0]
	var b: Variant = sim.robots[1]
	return Vector3(clampf((a.x + b.x) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT), 0.0,
		clampf((a.z + b.z) * 0.5, -CAMERA_LIMIT, CAMERA_LIMIT))


## 新しく起きた出来事から、火花・画面の揺れを出す
func _spawn_sparks() -> void:
	while _log_seen < sim.log.size():
		var e: Dictionary = sim.log[_log_seen]
		_log_seen += 1
		var t: String = e["type"]
		if t == "pack":
			robot_views[int(e["robot"])].on_heal(bool(e.get("big", false)))  # 回復した機体を緑に光らせる
			continue
		if t == "self_destruct":
			_shake = maxf(_shake, Look.SELF_DESTRUCT_SHAKE)  # 自爆（爆発そのものは robot_view が出す）
			continue
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
			# 穴に落ちたときは、光の柱が吹き上がるのに合わせて大きく揺らす
			_shake = maxf(_shake, Look.FALL_BURST_SHAKE if t == "fall" else Look.SHAKE_AMOUNT)
		if t == "hit" and _shoot_names.has(str(e.get("weapon", ""))):
			shot_fx.on_shot_hit(sim, int(e["robot"]), int(e.get("by", -1)), _shoot_names[str(e["weapon"])])
			continue
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
