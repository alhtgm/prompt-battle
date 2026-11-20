# 回復パックを取った機体の見た目。機体全体が緑に光り（2回脈打って消える）、緑の「＋」が体のまわりから立ちのぼり、
# 足もとに緑の輪が広がって、緑の光が周りを照らす。どちらが回復したかがひと目で分かるようにする。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")

## 演出の残り秒数（0 なら出ていない）と、緑に光らせているか（テストと確認用）
var left: float = 0.0
var glowing: bool = false
var _body: Node3D
var _overlay: StandardMaterial3D
var _plus: CPUParticles3D
var _light: OmniLight3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _big: bool = false
var _radius: float = 1.0


## body は機体の形（中のメッシュを緑に光らせる）、radius は当たり判定の半径、top は機体の高さ
func setup(body: Node3D, radius: float, top: float) -> void:
	_body = body
	_radius = radius
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(Look.HEAL_COLOR, 0.0)
	# 立ちのぼる緑の「＋」（いつもカメラの方を向く）
	_plus = CPUParticles3D.new()
	_plus.emitting = false
	_plus.amount = 26
	_plus.lifetime = 1.0
	_plus.local_coords = false
	_plus.direction = Vector3.UP
	_plus.spread = 12.0
	_plus.initial_velocity_min = 1.2
	_plus.initial_velocity_max = 2.6
	_plus.gravity = Vector3(0, 0.6, 0)
	_plus.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_plus.emission_ring_axis = Vector3.UP
	_plus.emission_ring_radius = radius * 1.1
	_plus.emission_ring_inner_radius = radius * 0.6
	_plus.emission_ring_height = top * 0.6
	_plus.scale_amount_min = 0.8
	_plus.scale_amount_max = 1.4
	_plus.mesh = _plus_mesh()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(Look.HEAL_COLOR.lightened(0.4), 1.0))
	ramp.set_color(1, Color(Look.HEAL_COLOR, 0.0))
	_plus.color_ramp = ramp
	_plus.position.y = top * 0.4
	add_child(_plus)
	_light = OmniLight3D.new()
	_light.light_color = Look.HEAL_COLOR
	_light.omni_range = radius * 4.0
	_light.light_energy = 0.0
	_light.position.y = top * 0.7
	add_child(_light)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(Look.HEAL_COLOR, 0.0)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.88
	t.outer_radius = 1.0
	t.rings = 32
	t.ring_segments = 4
	_ring.mesh = t
	_ring.material_override = _ring_mat
	_ring.position.y = 0.05
	_ring.visible = false
	add_child(_ring)


## 回復した。big なら強く長く光る
func play(big: bool) -> void:
	_big = big
	left = Look.HEAL_FX_SEC * (1.3 if big else 1.0)
	_plus.amount = 40 if big else 26
	if _plus.is_inside_tree():
		_plus.restart()
	_plus.emitting = true


## 毎フレーム進める。can_overlay が false のとき（自爆装置の点滅中など）は体を緑に塗らない
func update(delta: float, can_overlay: bool) -> void:
	if left <= 0.0:
		if glowing:
			_set_overlay(_body, null)
			glowing = false
		_plus.emitting = false
		_light.light_energy = 0.0
		_ring.visible = false
		return
	left = maxf(0.0, left - delta)
	var total: float = Look.HEAL_FX_SEC * (1.3 if _big else 1.0)
	var k: float = 1.0 - left / total  # 0 → 1
	# 体の緑：2回脈打ちながら薄れていく
	var pulse: float = (0.55 + 0.45 * cos(k * TAU * 2.0)) * (1.0 - k)
	_overlay.albedo_color = Color(Look.HEAL_COLOR, (0.9 if _big else 0.7) * pulse)
	if can_overlay and not glowing:
		_set_overlay(_body, _overlay)
		glowing = true
	elif not can_overlay and glowing:
		_set_overlay(_body, null)
		glowing = false
	# 立ちのぼる「＋」は最初の半分だけ出し続ける
	_plus.emitting = k < 0.5
	_light.light_energy = Look.HEAL_LIGHT * (1.4 if _big else 1.0) * pulse
	# 足もとの輪：広がって消える
	var rk: float = clampf(k / 0.6, 0.0, 1.0)
	_ring.visible = rk < 1.0
	var r: float = _radius * lerpf(0.6, 2.4 if _big else 1.9, 1.0 - pow(1.0 - rk, 2.0))
	_ring.scale = Vector3(r, 1.0, r)
	_ring_mat.albedo_color = Color(Look.HEAL_COLOR, 1.0 - rk)
	if left <= 0.0:
		_set_overlay(_body, null)
		glowing = false


func _set_overlay(n: Node, mat: Material) -> void:
	if n == null:
		return
	for c: Node in n.get_children():
		if c is MeshInstance3D and c.get_meta("debris", true):
			(c as MeshInstance3D).material_overlay = mat
		_set_overlay(c, mat)


## 「＋」の形のメッシュ（横棒と縦棒を1つにまとめる）。いつもカメラの方を向く
func _plus_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := BoxMesh.new()
	h.size = Vector3(0.26, 0.08, 0.04)
	var v := BoxMesh.new()
	v.size = Vector3(0.08, 0.26, 0.04)
	st.append_from(h, 0, Transform3D.IDENTITY)
	st.append_from(v, 0, Transform3D.IDENTITY)
	var mesh: ArrayMesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.surface_set_material(0, m)
	return mesh
