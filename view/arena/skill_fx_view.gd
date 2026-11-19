# シールド以外の、効果が続くスキルの見た目。ブースターは後ろの噴射炎と光の尾、オーバークロックは赤い火花と脈打つ赤い光。
# 試合の状態は読むだけ。robot_view.gd が毎フレーム update() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")

## 今それぞれの効果を出しているか（テストと確認用）
var booster_on: bool = false
var overclock_on: bool = false
var _flames: Array[MeshInstance3D] = []
var _flame_mat: StandardMaterial3D
var _trail: CPUParticles3D
var _boost_light: OmniLight3D
var _sparks: CPUParticles3D
var _oc_light: OmniLight3D
var _clock: float = 0.0
## 機体の後ろの面の位置（噴射炎の根元）
var _rear_x: float = 0.0


## length：機体の前後の長さ、top：機体の高さ、radius：当たり判定の半径
func setup(length: float, top: float, radius: float) -> void:
	# ブースター：後ろに2本の噴射炎（前 +X なので後ろは -X 向き）
	_flame_mat = _glow_mat(Look.BOOSTER_FLAME)
	_rear_x = -length * 0.5
	for z: float in [-0.25, 0.25]:
		var f := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.18
		cone.height = 1.0
		cone.radial_segments = 8
		f.mesh = cone
		f.material_override = _flame_mat
		f.rotation_degrees = Vector3(0, 0, 90)  # 円すいの先を -X（後ろ）へ
		f.position = Vector3(-length * 0.5 - 0.3, top * 0.45, z * radius * 1.4)
		f.visible = false
		add_child(f)
		_flames.append(f)
	# 光の尾：機体が動くと後ろに残る（粒は世界に置く）
	_trail = _particles(Look.BOOSTER_TRAIL, 40, 0.45, 0.06)
	_trail.local_coords = false
	_trail.position = Vector3(-length * 0.5 - 0.2, top * 0.45, 0)
	_trail.direction = Vector3(-1, 0, 0)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 2.0
	_trail.initial_velocity_max = 4.0
	_boost_light = _light(Look.BOOSTER_FLAME, Vector3(-length * 0.5 - 0.6, top * 0.5, 0), radius * 3.0)
	# オーバークロック：機体のまわりで赤い火花がはじけ、赤い光が脈打つ
	_sparks = _particles(Look.OVERCLOCK_COLOR, 36, 0.35, 0.05)
	_sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_sparks.emission_sphere_radius = radius * 1.1
	_sparks.position = Vector3(0, top * 0.5, 0)
	_sparks.direction = Vector3.UP
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 1.5
	_sparks.initial_velocity_max = 4.0
	_sparks.gravity = Vector3(0, -6, 0)
	_oc_light = _light(Look.OVERCLOCK_COLOR, Vector3(0, top * 0.6, 0), radius * 3.5)


## 効いているスキルに合わせて出す・止める
func update(booster: bool, overclock: bool, delta: float) -> void:
	_clock += delta
	booster_on = booster
	overclock_on = overclock
	# 噴射炎は長さと太さが小刻みにゆらぐ（時間の関数。乱数は使わない）
	for i: int in _flames.size():
		var f: MeshInstance3D = _flames[i]
		f.visible = booster
		if booster:
			var flick: float = 0.75 + 0.25 * sin(_clock * 47.0 + i * 2.1) * sin(_clock * 31.0 + i)
			var length: float = Look.BOOSTER_FLAME_LENGTH * flick
			f.scale = Vector3(0.9 + 0.2 * flick, length, 0.9 + 0.2 * flick)
			f.position.x = _rear_x - length * 0.5  # 炎の根元を機体の後ろの面にそろえる
	_trail.emitting = booster
	_boost_light.light_energy = (1.2 + 0.4 * sin(_clock * 40.0)) if booster else 0.0
	_sparks.emitting = overclock
	_oc_light.light_energy = (0.8 + 0.7 * (0.5 + 0.5 * sin(_clock * 9.0))) if overclock else 0.0


func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m


func _particles(col: Color, amount: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.gravity = Vector3.ZERO
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size)
	var m := _glow_mat(col)
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	add_child(p)
	return p


func _light(col: Color, pos: Vector3, light_range: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = light_range
	l.light_energy = 0.0
	l.position = pos
	add_child(l)
	return l
