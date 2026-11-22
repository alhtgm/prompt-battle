# 機体の身ぶり：加速で車体が後ろへ沈み、ブレーキで前へのめり、曲がると外へ傾き、走ると揺れ、後ろに土ぼこりと排気の煙。
# 前を照らすライト、傷むと煙（半分で灰色、4分の1で黒煙と火花、ライトが瞬く）、車輪（wheel_*）と脚（leg_*）が回り振れる。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const FlameView := preload("res://view/arena/flame_view.gd")

## robot_view が車体に重ねる傾き（ラジアン）と上下の揺れ（m）
var pitch: float = 0.0
var roll: float = 0.0
var bob: float = 0.0
## 前への速さ（m/秒。テストと確認用）と、土ぼこり・煙を出しているか
var forward_speed: float = 0.0
var dusting: bool = false
var smoking: int = 0
var lamp_light: SpotLight3D
var wheels: Array[Node3D] = []
var legs: Array[Node3D] = []
var _body: Node3D
var _lamps: Node3D
var _lens_mat: StandardMaterial3D
var _dust: CPUParticles3D
var _exhaust: CPUParticles3D
var _smoke_gray: CPUParticles3D
var _smoke_black: CPUParticles3D
var _sparks: CPUParticles3D
var _wheel_base: Array[Basis] = []
var _leg_base: Array[Basis] = []
var _length: float = 1.8
var _top: float = 1.0
var _prev_fwd: float = 0.0
var _prev_th: float = 0.0
var _accel: float = 0.0
var _turn: float = 0.0
var _dist: float = 0.0
var _clock: float = 0.0
var _started: bool = false


## body は機体の体（傾けるもの）。length・width・top は車体の長さ・幅・高さ（m）。
## lamps はライトのレンズの位置（体の中の座標）。空で default_lamps なら前の面の左右に置き、空でなければレンズは出さない
func setup(body: Node3D, length: float, width: float, top: float, lamps: Array = [], default_lamps: bool = true) -> void:
	_body = body
	_length = length
	_top = top
	# ライト：前の面に光るレンズ2つと、前を照らすスポットライト1つ（車体と一緒に傾く。爆発では部品にしない）
	_lamps = Node3D.new()
	_lamps.set_meta("debris", false)
	body.add_child(_lamps)
	_lens_mat = StandardMaterial3D.new()
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lens_mat.albedo_color = Look.HEADLIGHT_COLOR
	if lamps.is_empty() and default_lamps:
		for side: float in [-1.0, 1.0]:
			lamps.append(Vector3(length * 0.5 + 0.02, top * Look.HEADLIGHT_HEIGHT, side * width * 0.28))
	var center := Vector3(length * 0.5 + 0.05, top * Look.HEADLIGHT_HEIGHT, 0.0)
	if not lamps.is_empty():
		center = Vector3.ZERO
		for at: Vector3 in lamps:
			center += at / float(lamps.size())
	for at: Vector3 in lamps:
		var lens := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = Look.HEADLIGHT_LENS
		m.height = Look.HEADLIGHT_LENS * 2.0
		m.radial_segments = 8
		m.rings = 4
		lens.mesh = m
		lens.material_override = _lens_mat
		lens.position = at
		lens.set_meta("debris", false)
		_lamps.add_child(lens)
	lamp_light = SpotLight3D.new()
	lamp_light.light_color = Look.HEADLIGHT_COLOR
	lamp_light.light_energy = Look.HEADLIGHT_ENERGY
	lamp_light.spot_range = Look.HEADLIGHT_RANGE
	lamp_light.spot_angle = Look.HEADLIGHT_ANGLE_DEG
	lamp_light.shadow_enabled = false
	lamp_light.position = center + Vector3(0.05, 0.0, 0.0)
	lamp_light.basis = Basis.looking_at(Vector3(1.0, -Look.HEADLIGHT_TILT, 0.0), Vector3.UP)
	_lamps.add_child(lamp_light)
	# 土ぼこり（後ろの床から舞い上がる）
	var dust_ramp: Gradient = FlameView.ramp([0.0, 0.3, 1.0],
		[Color(Look.DUST_COLOR, 0.0), Color(Look.DUST_COLOR, 0.55), Color(Look.DUST_COLOR, 0.0)])
	_dust = _particles(Look.DUST_AMOUNT, 0.9, Vector3(-1.0, 0.7, 0.0), 35.0, 0.8, 2.2, dust_ramp, 0.35, 2.4, false)
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.1, 0.05, width * 0.4)
	_dust.gravity = Vector3(0, 0.6, 0)
	# 排気の煙（後ろの上から、ぽっぽっと出る）
	var ex_ramp: Gradient = FlameView.ramp([0.0, 0.2, 1.0],
		[Color(Look.EXHAUST_COLOR, 0.0), Color(Look.EXHAUST_COLOR, 0.6), Color(Look.EXHAUST_COLOR, 0.0)])
	_exhaust = _particles(10, 1.1, Vector3(-0.4, 1.0, 0.0), 15.0, 0.8, 1.4, ex_ramp, 0.18, 2.6, false)
	_exhaust.gravity = Vector3(0, 0.8, 0)
	# 傷んだときの煙（灰色・黒）と火花
	var gray_ramp: Gradient = FlameView.ramp([0.0, 0.25, 1.0],
		[Color(Look.DAMAGE_SMOKE_GRAY, 0.0), Color(Look.DAMAGE_SMOKE_GRAY, 0.6), Color(Look.DAMAGE_SMOKE_GRAY, 0.0)])
	_smoke_gray = _particles(18, 1.6, Vector3.UP, 12.0, 1.0, 1.8, gray_ramp, 0.3, 3.0, false)
	_smoke_gray.gravity = Vector3(0, 1.0, 0)
	var black_ramp: Gradient = FlameView.ramp([0.0, 0.2, 1.0],
		[Color(Look.DAMAGE_SMOKE_BLACK, 0.0), Color(Look.DAMAGE_SMOKE_BLACK, 0.9), Color(Look.DAMAGE_SMOKE_BLACK, 0.0)])
	_smoke_black = _particles(30, 2.0, Vector3.UP, 15.0, 1.4, 2.4, black_ramp, 0.45, 3.6, false)
	_smoke_black.gravity = Vector3(0, 1.4, 0)
	var spark_ramp: Gradient = FlameView.ramp([0.0, 1.0], [Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0)])
	_sparks = _particles(12, 0.5, Vector3.UP, 60.0, 2.5, 5.0, spark_ramp, 0.06, 0.6, true)
	_sparks.gravity = Vector3(0, -9.0, 0)
	_sparks.explosiveness = 0.85
	# 車輪と脚（モデルの中の wheel_* / leg_* という名前の節）
	_find_moving_parts(body)


## 機体の状態 r を読んで動かす。alive は動けるか（落ちた・壊れた機体は false）
func update(r: Variant, alive: bool, delta: float) -> void:
	_clock += delta
	if delta <= 0.0:
		return
	# 速さを持たない機体（テストの仮の機体など）は止まっているものとして扱う
	var th: float = float(r.get("th")) if "th" in r else 0.0
	var vx: float = float(r.get("vx")) if "vx" in r else 0.0
	var vz: float = float(r.get("vz")) if "vz" in r else 0.0
	var fwd: float = vx * cos(th) + vz * sin(th)
	if not _started:
		_started = true
		_prev_fwd = fwd
		_prev_th = th
	var turn_rate: float = wrapf(th - _prev_th, -PI, PI) / delta
	var acc: float = (fwd - _prev_fwd) / delta
	_prev_fwd = fwd
	_prev_th = th
	forward_speed = fwd
	var k: float = minf(1.0, Look.MOTION_SMOOTH * delta)
	_accel = lerpf(_accel, acc if alive else 0.0, k)
	_turn = lerpf(_turn, turn_rate * fwd if alive else 0.0, k)
	# 加速すると後ろへ沈み（先が上がる）、ブレーキで前へのめる。曲がると外へ傾く（曲がる向きは機体の +Z 側なので、上を -Z へ）
	pitch = clampf(_accel * Look.MOTION_PITCH_PER_ACCEL, -Look.MOTION_PITCH_MAX, Look.MOTION_PITCH_MAX)
	roll = clampf(-_turn * Look.MOTION_ROLL_PER_TURN, -Look.MOTION_ROLL_MAX, Look.MOTION_ROLL_MAX)
	var speed: float = absf(fwd)
	var legged: bool = not legs.is_empty()
	var amp: float = Look.MOTION_BOB_LEGS if legged else Look.MOTION_BOB_AMP
	bob = absf(sin(_clock * Look.MOTION_BOB_HZ)) * amp * minf(1.0, speed / Look.DUST_SPEED) if alive else 0.0
	# 車輪を回し、脚を振る（進んだ道のりで動かす）
	_dist += fwd * delta
	for i: int in wheels.size():
		wheels[i].basis = _wheel_base[i] * Basis(Vector3(0, 0, 1), -_dist * Look.WHEEL_SPIN_PER_M)
	var stride: float = sin(_dist / Look.LEG_STRIDE_M * TAU) * Look.LEG_SWING * minf(1.0, speed / 2.0)
	for i: int in legs.size():
		var sgn: float = 1.0 if i % 2 == 0 else -1.0
		legs[i].basis = _leg_base[i] * Basis(Vector3(0, 0, 1), stride * sgn)
	# 粒の出る場所（世界の座標）
	var xf: Transform3D = global_transform
	_dust.global_transform = Transform3D(xf.basis, xf * Vector3(-_length * 0.45, 0.08, 0.0))
	_exhaust.global_transform = Transform3D(xf.basis, xf * Vector3(-_length * 0.35, _top + 0.05, 0.0))
	var top_at := Transform3D(Basis.IDENTITY, xf * Vector3(0.0, _top * 0.85, 0.0))
	_smoke_gray.global_transform = top_at
	_smoke_black.global_transform = top_at
	_sparks.global_transform = top_at
	dusting = alive and speed > Look.DUST_SPEED
	var ratio: float = r.hp_ratio() if r.has_method("hp_ratio") else 1.0
	smoking = 0 if not alive else (2 if ratio < Look.DAMAGE_SMOKE_LOW else (1 if ratio < Look.DAMAGE_SMOKE_HALF else 0))
	if is_inside_tree():
		_dust.emitting = dusting
		_exhaust.emitting = alive
		_smoke_gray.emitting = smoking == 1
		_smoke_black.emitting = smoking == 2
		_sparks.emitting = smoking == 2 and fmod(_clock * 1.7, 1.0) < 0.2
	# ライト：ひどく傷むと瞬く。落ちた・壊れたら消える
	var on: bool = alive and not (smoking == 2 and fmod(_clock * 7.3, 1.0) < 0.18)
	lamp_light.light_energy = Look.HEADLIGHT_ENERGY if on else 0.0
	_lens_mat.albedo_color = Look.HEADLIGHT_COLOR if on else Look.HEADLIGHT_COLOR.darkened(0.8)


func _find_moving_parts(n: Node) -> void:
	for c: Node in n.get_children():
		if c is Node3D:
			var name_l: String = String(c.name).to_lower()
			if name_l.begins_with("wheel"):
				wheels.append(c)
				_wheel_base.append((c as Node3D).basis)
			elif name_l.begins_with("leg"):
				legs.append(c)
				_leg_base.append((c as Node3D).basis)
		_find_moving_parts(c)


func _particles(amount: int, life: float, dir: Vector3, spread: float, vmin: float, vmax: float, ramp: Gradient,
		size_from: float, grow: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.local_coords = false
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.color_ramp = ramp
	var mesh := SphereMesh.new()
	mesh.radius = size_from * 0.5
	mesh.height = size_from
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, grow))
	p.scale_amount_curve = c
	add_child(p)
	return p
