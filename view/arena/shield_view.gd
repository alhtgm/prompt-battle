# バリア（シールドのスキル）の見た目。展開→維持→消滅を順に動かし、被弾の波紋・床に広がる光の輪・粒・照り返しの光を出す。
# 試合の状態は読むだけ。robot_view.gd が毎フレーム update() を呼び、被弾したら hit() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const SHIELD_SHADER := preload("res://view/shaders/shield.gdshader")

enum State { OFF, OPENING, ON, CLOSING }

var state: State = State.OFF
## 今の段階に入ってからの秒数
var phase_t: float = 0.0
var dome: MeshInstance3D
var light: OmniLight3D
var _mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring_t: float = -1.0
var _floor: MeshInstance3D
var _floor_mat: StandardMaterial3D
var _rise: CPUParticles3D
var _shards: CPUParticles3D
var _hit_sparks: CPUParticles3D
var _clock: float = 0.0
var _hit_age: float = 10.0
var _radius: float = 1.0
var _height: float = 1.0


## radius：膜の横の半径、height：膜の高さ（機体を包む楕円の球）
func setup(radius: float, height: float) -> void:
	_radius = radius
	_height = height
	var col: Color = Look.SHIELD_COLOR
	# 膜
	dome = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	dome.mesh = sphere
	_mat = ShaderMaterial.new()
	_mat.shader = SHIELD_SHADER
	_mat.set_shader_parameter("color", col)
	_mat.set_shader_parameter("cells_x", Look.SHIELD_CELLS.x)
	_mat.set_shader_parameter("cells_y", Look.SHIELD_CELLS.y)
	dome.material_override = _mat
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.position.y = height * 0.5
	add_child(dome)
	# 展開のときに床を広がる光の輪と、張っている間の足もとの光
	_ring_mat = _glow_material(col)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.92
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position.y = 0.04
	add_child(_ring)
	_floor_mat = _glow_material(col)
	_floor = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 24
	_floor.mesh = disc
	_floor.material_override = _floor_mat
	_floor.position.y = 0.02
	add_child(_floor)
	# 機体と床を照らす光
	light = OmniLight3D.new()
	light.light_color = col
	light.omni_range = radius * 3.0
	light.light_energy = 0.0
	light.position.y = height * 0.6
	add_child(light)
	# 粒：展開で立ちのぼる光、消滅で飛び散るかけら、被弾の火花
	_rise = _particles(col, 40, 0.8, Vector3.UP, 15.0, 1.5, 3.5, Vector3(0, 1.5, 0))
	_rise.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_rise.emission_ring_axis = Vector3.UP
	_rise.emission_ring_radius = radius
	_rise.emission_ring_inner_radius = radius * 0.8
	_rise.emission_ring_height = 0.0
	_shards = _particles(col, 48, 0.7, Vector3.UP, 180.0, 2.0, 6.0, Vector3(0, -9.0, 0))
	_shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	_shards.emission_sphere_radius = radius
	_shards.position.y = height * 0.5
	_hit_sparks = _particles(Color(1, 1, 1), 16, 0.35, Vector3.UP, 70.0, 2.0, 5.0, Vector3(0, -6.0, 0))
	_apply(0.0)


## 張っているかと、残り時間の割合（1 で張ったばかり、0 で切れる）を受けて、見た目を進める
func update(active: bool, remaining_frac: float, delta: float) -> void:
	_clock += delta
	_hit_age += delta
	phase_t += delta
	match state:
		State.OFF:
			if active:
				_enter(State.OPENING)
		State.OPENING:
			if not active:
				_enter(State.CLOSING)
			elif phase_t >= Look.SHIELD_OPEN_SEC:
				_enter(State.ON)
		State.ON:
			if not active:
				_enter(State.CLOSING)
		State.CLOSING:
			if active:
				_enter(State.OPENING)
			elif phase_t >= Look.SHIELD_CLOSE_SEC:
				_enter(State.OFF)
	if _ring_t >= 0.0:
		_ring_t += delta
	_apply(remaining_frac)


## 被弾した。from_world は攻撃が来た位置（相手の機体の位置）
func hit(from_world: Vector3) -> void:
	if state == State.OFF or state == State.CLOSING:
		return
	var center: Vector3 = dome.global_position
	var dir: Vector3 = from_world - center
	dir.y = _height * 0.15
	if dir.length() < 0.001:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	# 膜の中の向きに直す（膜は楕円なので、表面の点を膜の座標に戻してから向きにする）
	var world_point: Vector3 = center + Vector3(dir.x * _radius, dir.y * _height * 0.5, dir.z * _radius)
	var local: Vector3 = dome.global_transform.affine_inverse() * world_point
	_mat.set_shader_parameter("hit_dir", local.normalized())
	_hit_age = 0.0
	_hit_sparks.global_position = world_point
	_hit_sparks.restart()


func is_visible_shield() -> bool:
	return state != State.OFF


func _enter(next: State) -> void:
	state = next
	phase_t = 0.0
	match next:
		State.OPENING:
			_ring_t = 0.0
			_rise.restart()
		State.CLOSING:
			_shards.restart()


## 今の段階と時間から、膜の大きさ・展開・消滅・明るさを決めて渡す
func _apply(remaining_frac: float) -> void:
	var open: float = 1.0
	var dissolve: float = 0.0
	var pop: float = 1.0
	var bright: float = 1.0
	match state:
		State.OFF:
			open = 0.0
		State.OPENING:
			var t: float = clampf(phase_t / Look.SHIELD_OPEN_SEC, 0.0, 1.0)
			open = t
			pop = 0.75 + 0.25 * _ease_out_back(t)
			bright = 1.0 + (1.0 - t) * 0.8
		State.CLOSING:
			var t: float = clampf(phase_t / Look.SHIELD_CLOSE_SEC, 0.0, 1.0)
			dissolve = t
			pop = 1.0 + 0.12 * t
			bright = 1.0 + 0.6 * (1.0 - t)
	var low: float = 0.0
	if state == State.ON and remaining_frac < Look.SHIELD_LOW_FRAC:
		low = 1.0 - remaining_frac / Look.SHIELD_LOW_FRAC
	dome.visible = state != State.OFF
	dome.scale = Vector3(_radius, _height * 0.5, _radius) * pop
	_mat.set_shader_parameter("open", open)
	_mat.set_shader_parameter("dissolve", dissolve)
	_mat.set_shader_parameter("flicker", low)
	_mat.set_shader_parameter("hit_age", _hit_age)
	_mat.set_shader_parameter("clock", _clock)
	_mat.set_shader_parameter("intensity", bright * Look.SHIELD_INTENSITY)
	# 床の輪：展開した瞬間に外へ広がって消える
	var ring_on: bool = _ring_t >= 0.0 and _ring_t < Look.SHIELD_RING_SEC
	_ring.visible = ring_on
	if ring_on:
		var k: float = _ring_t / Look.SHIELD_RING_SEC
		var s: float = _radius * (0.4 + 1.6 * _ease_out(k))
		_ring.scale = Vector3(s, 1.0, s)
		_ring_mat.albedo_color.a = 1.0 - k
	# 足もとの光と、照り返しの光（被弾で一瞬強くなる）
	var shown: float = open * (1.0 - dissolve)
	var hit_flash: float = exp(-_hit_age * 6.0)
	_floor.visible = shown > 0.0
	_floor_mat.albedo_color.a = 0.18 * shown * (1.0 - 0.5 * low)
	light.light_energy = (Look.SHIELD_LIGHT_ENERGY * shown + hit_flash * Look.SHIELD_LIGHT_ENERGY * 2.0) \
		* (1.0 - 0.5 * low) if state != State.OFF else 0.0


func _glow_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m


func _particles(col: Color, amount: int, life: float, dir: Vector3, spread: float, vmin: float, vmax: float,
		gravity: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.07, 0.07, 0.07)
	var m := _glow_material(col)
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	add_child(p)
	return p


static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


## 少し行き過ぎてから戻る（膜がぷるんと張る）
static func _ease_out_back(t: float) -> float:
	var c: float = 1.7
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)
