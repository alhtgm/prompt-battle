# 機体が穴に落ちたときの演出。少し沈んだあと、穴から陣営の色の光の柱が空へ吹き上がり、光の筋が放射状に飛び、
# 床を光の輪が走り、光の粒が舞い、閃光が照らす。見た目だけで、試合の計算には関わらない。乱数は使わず番号からばらつかせる。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")

## 落ちてからの秒数
var age: float = 0.0
## 吹き上がったか（テストと確認用）
var erupted: bool = false
var _color: Color = Color.WHITE
var _pillar: MeshInstance3D
var _core: MeshInstance3D
var _pillar_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _streaks: Array = []  # [ノード, 材質, 向きの角度, 上向きの角度, 長さ]
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _sparkles: CPUParticles3D
var _flash: OmniLight3D


## color は陣営の光る色。この演出のノードは、落ちた場所（床の高さ）に置く
func setup(color: Color) -> void:
	_color = color
	_pillar_mat = _glow_mat(color)
	_pillar = _cylinder(1.0, _pillar_mat)
	_core_mat = _glow_mat(Color(1, 1, 1))
	_core = _cylinder(0.35, _core_mat)
	for k: int in Look.FALL_BURST_STREAKS:
		var mat := _glow_mat(color.lerp(Color.WHITE, 0.5))
		var s := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.12, 0.12)
		s.mesh = box
		s.material_override = mat
		s.visible = false
		add_child(s)
		var yaw: float = TAU * (float(k) + _h(k, 1) * 0.6) / float(Look.FALL_BURST_STREAKS)
		var pitch: float = deg_to_rad(lerpf(15.0, 70.0, _h(k, 2)))
		var length: float = Look.FALL_BURST_STREAK_LEN * lerpf(0.6, 1.2, _h(k, 3))
		_streaks.append([s, mat, yaw, pitch, length])
	_ring_mat = _glow_mat(color)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 40
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = 0.06
	_ring.visible = false
	add_child(_ring)
	_sparkles = CPUParticles3D.new()
	_sparkles.one_shot = true
	_sparkles.emitting = false
	_sparkles.amount = 60
	_sparkles.lifetime = 1.2
	_sparkles.explosiveness = 0.85
	_sparkles.direction = Vector3.UP
	_sparkles.spread = 35.0
	_sparkles.initial_velocity_min = 6.0
	_sparkles.initial_velocity_max = 16.0
	_sparkles.gravity = Vector3(0, -6, 0)
	_sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_sparkles.emission_sphere_radius = 0.8
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(color, 0.0))
	_sparkles.color_ramp = fade
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.12, 0.12, 0.12)
	var sm := _glow_mat(Color(1, 1, 1))
	sm.vertex_color_use_as_albedo = true
	spark_mesh.material = sm
	_sparkles.mesh = spark_mesh
	add_child(_sparkles)
	_flash = OmniLight3D.new()
	_flash.light_color = color
	_flash.omni_range = 14.0
	_flash.light_energy = 0.0
	_flash.position.y = 2.0
	add_child(_flash)
	_apply()


## 毎フレーム進める（robot_view.gd の sync から呼ぶ）
func update(delta: float) -> void:
	age += delta
	if not erupted and age >= Look.FALL_BURST_DELAY:
		erupted = true
		_sparkles.restart()
	_apply()


## 吹き上がってからの割合に合わせて、柱・筋・輪・閃光の形と明るさを決める
func _apply() -> void:
	var t: float = (age - Look.FALL_BURST_DELAY) / Look.FALL_BURST_SEC
	var on: bool = erupted and t < 1.0
	_pillar.visible = on
	_core.visible = on and t < 0.6
	_ring.visible = on and t < 0.5
	for st: Array in _streaks:
		(st[0] as MeshInstance3D).visible = on and t < 0.7
	if not on:
		_flash.light_energy = 0.0
		return
	# 柱：一瞬で空まで伸び、太く光ってから細くなって消える
	var rise: float = clampf(t / 0.08, 0.0, 1.0)
	var height: float = Look.FALL_BURST_HEIGHT * rise
	var width: float = Look.FALL_BURST_WIDTH * (1.0 + 0.6 * exp(-t * 12.0)) * pow(1.0 - t, 1.5)
	_pillar.scale = Vector3(width, height, width)
	_pillar.position.y = height * 0.5
	_core.scale = Vector3(width, height, width)
	_core.position.y = height * 0.5
	_pillar_mat.albedo_color = Color(_color, clampf(1.2 * (1.0 - t), 0.0, 1.0))
	_core_mat.albedo_color = Color(1, 1, 1, clampf(1.0 - t / 0.6, 0.0, 1.0))
	# 光の筋：穴から放射状に、斜め上へ一気に伸びて細くなる
	var reach: float = 1.0 - pow(1.0 - clampf(t / 0.15, 0.0, 1.0), 3.0)
	var thin: float = clampf(1.0 - t / 0.7, 0.0, 1.0)
	for st: Array in _streaks:
		var s: MeshInstance3D = st[0]
		var yaw: float = st[2]
		var pitch: float = st[3]
		var length: float = float(st[4]) * reach
		var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
		# 箱の長い辺（X）を飛ぶ向きにそろえる
		var side: Vector3 = dir.cross(Vector3.UP).normalized()
		var up: Vector3 = side.cross(dir).normalized()
		s.basis = Basis(dir * maxf(0.001, length), up * thin * 1.6, side * thin * 1.6)
		s.position = dir * (length * 0.5) + Vector3.UP * 0.3
		(st[1] as StandardMaterial3D).albedo_color.a = thin
	# 床の光の輪：外へ速く広がって消える
	var rt: float = clampf(t / 0.5, 0.0, 1.0)
	var r: float = lerpf(1.0, 9.0, 1.0 - pow(1.0 - rt, 2.0))
	_ring.scale = Vector3(r, 1.0, r)
	_ring_mat.albedo_color.a = 1.0 - rt
	# 閃光
	_flash.light_energy = Look.FALL_BURST_FLASH * exp(-t * 6.0)


func _cylinder(radius: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = 1.0
	c.radial_segments = 16
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visible = false
	add_child(m)
	return m


func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 番号から作る 0〜1 の決まった値（乱数の代わり）
static func _h(i: int, k: int) -> float:
	var v: float = sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453
	return v - floorf(v)
