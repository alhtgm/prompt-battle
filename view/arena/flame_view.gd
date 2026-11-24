# 火炎放射器の見た目。ノズルの先にはいつも小さな種火（青い根元と橙の先）がともり、撃つと白っぽい黄色→橙→濃い赤へ
# 変わりながら広がる炎が前へ噴き出し、炎の先から黒い煙が立ちのぼり、火の粉が舞い、赤い光が揺れて照らす。轟音つき。
# 試合の状態は読むだけ。robot_view.gd が毎フレーム update() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const Sfx := preload("res://view/sfx.gd")

## 炎を出しているか（テストと確認用）
var firing: bool = false
var roar_player: AudioStreamPlayer3D
var _pilot: Node3D
var _fire: CPUParticles3D
var _core: CPUParticles3D
var _smoke: CPUParticles3D
var _embers: CPUParticles3D
var _light: OmniLight3D
var _fx_player: AudioStreamPlayer3D
var _clock: float = 0.0


## flame_range は炎の届く長さ（m）。炎の粒の速さと寿命をこれに合わせる
func setup(flame_range: float) -> void:
	var life: float = 0.42
	var speed: float = flame_range / life
	# 種火
	_pilot = Node3D.new()
	add_child(_pilot)
	_pilot.add_child(_cone(0.05, 0.12, _glow(Look.FLAME_PILOT_BLUE)))
	var tip := _cone(0.035, 0.1, _glow(Look.FLAME_ORANGE))
	tip.position.x = 0.07
	_pilot.add_child(tip)
	# 炎：大きく広がりながら色が変わる
	_fire = _particles(160, life, Vector3(1.0, 0.0, 0.0), 12.0, speed * 0.85, speed * 1.05, _flame_ramp(), 0.4, 3.2, true)
	_fire.damping_min = speed * 0.4
	_fire.damping_max = speed * 0.6
	# 炎の芯：細く明るい
	_core = _particles(60, life * 0.6, Vector3(1.0, 0.0, 0.0), 4.0, speed * 0.9, speed * 1.1, _core_ramp(), 0.15, 1.2, true)
	# 黒い煙：炎の先のあたりから、ゆっくり立ちのぼって広がる
	var smoke_ramp: Gradient = ramp([0.0, 0.25, 1.0],
		[Color(Look.FLAME_SMOKE, 0.0), Color(Look.FLAME_SMOKE, 0.85), Color(Look.FLAME_SMOKE, 0.0)])
	_smoke = _particles(50, 1.6, Vector3(1.0, 0.35, 0.0), 18.0, speed * 0.45, speed * 0.6, smoke_ramp, 0.5, 3.4, false)
	_smoke.gravity = Vector3(0, 2.2, 0)
	_smoke.damping_min = speed * 0.25
	_smoke.damping_max = speed * 0.35
	# 火の粉
	var ember_ramp: Gradient = ramp([0.0, 1.0], [Color(1.0, 0.75, 0.3, 1.0), Color(0.9, 0.15, 0.05, 0.0)])
	_embers = _particles(30, 0.8, Vector3(1.0, 0.3, 0.0), 25.0, speed * 0.4, speed * 0.8, ember_ramp, 0.05, 0.8, true)
	_embers.gravity = Vector3(0, -4.0, 0)
	_light = OmniLight3D.new()
	_light.light_color = Look.FLAME_ORANGE
	_light.omni_range = flame_range * 1.2
	_light.light_energy = 0.0
	add_child(_light)
	roar_player = AudioStreamPlayer3D.new()
	roar_player.stream = Sfx.flame_roar()
	roar_player.unit_size = 12.0
	add_child(roar_player)
	_fx_player = AudioStreamPlayer3D.new()
	_fx_player.stream = Sfx.flame_ignite()
	_fx_player.unit_size = 12.0
	add_child(_fx_player)


## on は炎を出しているか、muzzle はノズルの先、dir は炎の向き（どちらも世界の座標）、alive は機体が動けるか（種火を出すか）
func update(on: bool, muzzle: Vector3, dir: Vector3, alive: bool, delta: float) -> void:
	_clock += delta
	var flat := Vector3(dir.x, 0.0, dir.z)
	var d: Vector3 = flat.normalized() if flat.length() > 0.01 else Vector3.RIGHT
	var basis: Basis = _basis_along(d)
	var xf := Transform3D(basis, muzzle)
	_pilot.visible = alive
	if alive:
		_pilot.global_transform = xf
		_pilot.scale = Vector3.ONE * (0.9 + 0.15 * sin(_clock * 37.0))
	for p: CPUParticles3D in [_fire, _core, _smoke, _embers]:
		p.global_transform = xf
	if on and not firing and _fx_player.is_inside_tree():
		_fx_player.play()
	firing = on
	_fire.emitting = on
	_core.emitting = on
	_smoke.emitting = on
	_embers.emitting = on
	# 赤い光は炎の中ほどで揺れる
	_light.global_position = muzzle + d * Look.FLAME_LIGHT_AHEAD + Vector3.UP * 0.4
	_light.light_energy = (Look.FLAME_LIGHT * (0.75 + 0.25 * sin(_clock * 29.0) * sin(_clock * 17.0))) if on else 0.0
	roar_player.global_position = muzzle
	if on and not roar_player.playing and roar_player.is_inside_tree():
		roar_player.play()
	elif not on and roar_player.playing:
		roar_player.stop()


# ---- 部品 ----

## 炎の色：明るい橙 → 橙 → 赤 → 暗い赤 → 消える（光を足し合わせるので、白く飛ばないよう薄めにする）
func _flame_ramp() -> Gradient:
	return ramp([0.0, 0.2, 0.5, 0.8, 1.0], [Color(1.0, 0.72, 0.3, 0.85), Color(Look.FLAME_ORANGE, 0.8),
		Color(Look.FLAME_RED, 0.7), Color(Look.FLAME_RED.darkened(0.55), 0.35), Color(0.1, 0.02, 0.01, 0.0)])


func _core_ramp() -> Gradient:
	return ramp([0.0, 1.0], [Color(1.0, 0.85, 0.5, 0.75), Color(Look.FLAME_ORANGE, 0.0)])


## 位置（0〜1）と色を並べてグラデーションを作る
static func ramp(offsets: Array, colors: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g


## additive なら光を足し合わせる炎、そうでなければ暗い煙（重ねて黒くする）
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
	p.gravity = Vector3(0, 1.0, 0)
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
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, grow))
	p.scale_amount_curve = c
	add_child(p)
	return p


func _cone(radius: float, length: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = 0.0
	c.height = length
	c.radial_segments = 6
	m.mesh = c
	m.material_override = mat
	m.rotation = Vector3(0, 0, -PI * 0.5)  # 先を前（+X）へ
	m.position = Vector3(length * 0.5, 0, 0)
	return m


func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m


## dir を X 軸にした向き（Y はなるべく上）
static func _basis_along(dir: Vector3) -> Basis:
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = side.cross(dir).normalized()
	return Basis(dir, up, dir.cross(up))
