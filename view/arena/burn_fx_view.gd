# 火傷（状態異常）で燃えている機体の見た目。体のあちこちから炎が立ちのぼり、黒い煙が上がり、火の粉が舞い、
# 橙の光が揺れる。動くと炎と煙が後ろへ流れる（粒は世界に置く）。試合の状態は読むだけ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const FlameView := preload("res://view/arena/flame_view.gd")

## 燃えている見た目を出しているか（テストと確認用）
var burning: bool = false
var _flames: CPUParticles3D
var _smoke: CPUParticles3D
var _embers: CPUParticles3D
var _light: OmniLight3D
var _clock: float = 0.0
var _top: float = 1.0


## radius は機体の半径、top は機体の高さ（炎を出す範囲）
func setup(radius: float, top: float) -> void:
	_top = top
	var box := Vector3(radius * 0.8, top * 0.4, radius * 0.7)
	var flame_ramp: Gradient = FlameView.ramp([0.0, 0.35, 0.7, 1.0], [Color(1.0, 0.7, 0.3, 0.85),
		Color(Look.FLAME_ORANGE, 0.8), Color(Look.FLAME_RED, 0.55), Color(0.2, 0.03, 0.01, 0.0)])
	_flames = _particles(48, 0.6, box, 1.2, 2.4, flame_ramp, 0.3, 1.6, true)
	_flames.gravity = Vector3(0, 2.5, 0)
	var smoke_ramp: Gradient = FlameView.ramp([0.0, 0.2, 1.0],
		[Color(Look.FLAME_SMOKE, 0.0), Color(Look.FLAME_SMOKE, 0.8), Color(Look.FLAME_SMOKE, 0.0)])
	_smoke = _particles(26, 1.8, box, 0.8, 1.6, smoke_ramp, 0.45, 3.0, false)
	_smoke.gravity = Vector3(0, 1.4, 0)
	var ember_ramp: Gradient = FlameView.ramp([0.0, 1.0], [Color(1.0, 0.75, 0.3, 1.0), Color(0.9, 0.15, 0.05, 0.0)])
	_embers = _particles(16, 0.9, box, 1.5, 3.5, ember_ramp, 0.05, 0.8, true)
	_embers.spread = 40.0
	_embers.gravity = Vector3(0, -3.0, 0)
	_light = OmniLight3D.new()
	_light.light_color = Look.FLAME_ORANGE
	_light.omni_range = radius * 3.5
	_light.light_energy = 0.0
	_light.position.y = top * 0.8
	add_child(_light)


## on は燃えているか（落ちた・壊れた機体は false にする）
func update(on: bool, delta: float) -> void:
	_clock += delta
	burning = on
	if not is_inside_tree():
		return
	for p: CPUParticles3D in [_flames, _smoke, _embers]:
		p.emitting = on
	_light.light_energy = (Look.BURN_LIGHT * (0.7 + 0.3 * sin(_clock * 23.0) * sin(_clock * 13.0 + 1.0))) if on else 0.0


func _particles(amount: int, life: float, box: Vector3, vmin: float, vmax: float, ramp: Gradient,
		size_from: float, grow: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.local_coords = false
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
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
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, grow))
	p.scale_amount_curve = c
	p.position.y = _top * 0.55
	add_child(p)
	return p
