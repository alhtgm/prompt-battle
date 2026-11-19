# 機体が壊されたときの爆発。機体の部品（メッシュ1つずつ）をばらして飛ばし、床で跳ねて転がらせ、火の玉・閃光・衝撃の輪・火の粉・煙・焦げ跡を出す。
# 見た目だけの動きで、試合の計算には関わらない。乱数は使わず、部品の番号から作る決まった値でばらつかせる。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")

## ばらした部品：[ノード, 速さ, 回る速さ, 床からの高さの下限]
var pieces: Array = []
var age: float = 0.0
var _fireball: MeshInstance3D
var _core: MeshInstance3D
var _fire_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _flash: OmniLight3D
var _smolder: CPUParticles3D
var _ring_radius: float = 5.0


## 爆発を始める。source の中のメッシュを部品としてばらす。center は爆発の中心（この爆発から見た位置）、size は機体の大きさ（m）、
## ring_radius は床を広がる衝撃の輪の最後の半径（m。省くと決まった大きさ）
func start(source: Node3D, center: Vector3, size: float, ring_radius: float = -1.0) -> void:
	_ring_radius = ring_radius if ring_radius > 0.0 else Look.EXPLOSION_RING_RADIUS
	var meshes: Array[MeshInstance3D] = []
	_collect(source, meshes)
	var world_center: Vector3 = to_global(center)
	for k: int in meshes.size():
		var mi: MeshInstance3D = meshes[k]
		var xf: Transform3D = mi.global_transform
		mi.get_parent().remove_child(mi)
		add_child(mi)
		mi.top_level = true  # 機体の向きや縮みに引きずられず、自分の位置で飛ぶ
		mi.global_transform = xf
		var out: Vector3 = xf.origin - world_center
		out.y = 0.0
		if out.length() < 0.05:
			out = Vector3(cos(k * 2.4), 0.0, sin(k * 2.4))
		out = out.normalized()
		# 外へ飛ぶ向きに、番号から作るばらつきを足す
		out = out.rotated(Vector3.UP, (_h(k, 1) - 0.5) * 1.2)
		var speed: float = lerpf(Look.EXPLOSION_SPEED_MIN, Look.EXPLOSION_SPEED_MAX, _h(k, 2))
		var vel: Vector3 = out * speed + Vector3.UP * lerpf(Look.EXPLOSION_UP_MIN, Look.EXPLOSION_UP_MAX, _h(k, 3))
		var spin: Vector3 = Vector3(_h(k, 4) - 0.5, _h(k, 5) - 0.5, _h(k, 6) - 0.5) * Look.EXPLOSION_SPIN
		pieces.append([mi, vel, spin, _rest_height(mi)])
	source.visible = false
	_add_effects(center, size)


## 毎フレーム進める（robot_view.gd の sync から呼ぶ）
func update(delta: float) -> void:
	age += delta
	for p: Array in pieces:
		var mi: MeshInstance3D = p[0]
		var vel: Vector3 = p[1]
		var spin: Vector3 = p[2]
		var floor_y: float = p[3]
		vel.y -= Look.EXPLOSION_GRAVITY * delta
		var pos: Vector3 = mi.global_position + vel * delta
		if pos.y < floor_y:
			# 床で跳ねる。跳ねるたびに勢いと回転が落ち、やがて止まる
			pos.y = floor_y
			vel.y = -vel.y * Look.EXPLOSION_BOUNCE
			vel.x *= Look.EXPLOSION_FRICTION
			vel.z *= Look.EXPLOSION_FRICTION
			spin *= Look.EXPLOSION_FRICTION
			if absf(vel.y) < 0.6:
				vel.y = 0.0
		mi.global_position = pos
		if spin.length() > 0.01:
			mi.global_basis = Basis(spin.normalized(), spin.length() * delta) * mi.global_basis
		p[1] = vel
		p[2] = spin
	# 火の玉：一気にふくらんで、暗い色に変わりながら消える
	var t: float = clampf(age / Look.EXPLOSION_FIREBALL_SEC, 0.0, 1.0)
	_fireball.visible = t < 1.0
	_core.visible = t < 0.6
	var grow: float = 1.0 - pow(1.0 - t, 3.0)
	_fireball.scale = Vector3.ONE * lerpf(0.3, 1.0, grow)
	_core.scale = Vector3.ONE * lerpf(0.4, 0.7, grow)
	_fire_mat.albedo_color = Look.EXPLOSION_FIRE.lerp(Look.EXPLOSION_SMOKE, t) * Color(1, 1, 1, 1.0 - t)
	_core_mat.albedo_color.a = clampf(1.0 - t / 0.6, 0.0, 1.0)
	# 衝撃の輪：床を速く広がって消える
	var rt: float = clampf(age / Look.EXPLOSION_RING_SEC, 0.0, 1.0)
	_ring.visible = rt < 1.0
	_ring.scale = Vector3(1.0, 1.0, 1.0) * lerpf(0.3, _ring_radius, 1.0 - pow(1.0 - rt, 2.0))
	_ring_mat.albedo_color.a = 1.0 - rt
	# 閃光：一瞬だけ強く照らす
	_flash.light_energy = Look.EXPLOSION_FLASH_ENERGY * exp(-age * 7.0)
	# くすぶる煙は少し遅れて出し始める
	if age > 0.3 and not _smolder.emitting and age < 0.4:
		_smolder.emitting = true


func _add_effects(center: Vector3, size: float) -> void:
	var r: float = size * Look.EXPLOSION_FIREBALL_SIZE
	_fire_mat = _glow_mat(Look.EXPLOSION_FIRE)
	_fireball = _sphere(r, _fire_mat, center)
	_core_mat = _glow_mat(Look.EXPLOSION_CORE)
	_core = _sphere(r, _core_mat, center)
	# 床の衝撃の輪と焦げ跡
	_ring_mat = _glow_mat(Look.EXPLOSION_FIRE)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	_ring.mesh = torus
	_ring.material_override = _ring_mat
	_ring.position = Vector3(center.x, 0.05, center.z)
	add_child(_ring)
	var scorch := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = size * 0.9
	disc.bottom_radius = size * 0.9
	disc.height = 0.01
	disc.radial_segments = 16
	scorch.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.02, 0.015, 0.01, 0.75)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scorch.material_override = sm
	scorch.position = Vector3(center.x, 0.015, center.z)
	add_child(scorch)
	# 閃光
	_flash = OmniLight3D.new()
	_flash.light_color = Look.EXPLOSION_FIRE
	_flash.omni_range = size * 5.0
	_flash.light_energy = Look.EXPLOSION_FLASH_ENERGY
	_flash.position = center + Vector3.UP * 0.5
	add_child(_flash)
	# 火の粉（飛び散って落ちる）
	var embers: CPUParticles3D = _particles(70, 1.1, 180.0, 4.0, 12.0, Vector3(0, -15, 0), true)
	var ember_ramp := Gradient.new()
	ember_ramp.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	ember_ramp.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	embers.color_ramp = ember_ramp
	embers.position = center
	embers.emitting = true
	# 煙のかたまり（ゆっくり上がりながら広がる）
	var smoke: CPUParticles3D = _particles(26, 1.8, 60.0, 1.0, 3.0, Vector3(0, 1.5, 0), false)
	smoke.position = center
	smoke.emitting = true
	# 残骸からくすぶり続ける煙
	_smolder = _particles(10, 2.6, 15.0, 0.5, 1.2, Vector3(0, 1.0, 0), false)
	_smolder.one_shot = false
	_smolder.explosiveness = 0.0
	_smolder.position = Vector3(center.x, 0.3, center.z)


## メッシュをすべて集める（見えているもので、"debris" の印が false でないもの）
func _collect(n: Node, out: Array[MeshInstance3D]) -> void:
	for c: Node in n.get_children():
		if not c.get_meta("debris", true):
			continue  # 陣営の輪など、部品ではない飾り（元の機体と一緒に消える）
		if c is MeshInstance3D and (c as MeshInstance3D).visible and (c as MeshInstance3D).mesh != null:
			out.append(c)
		if c is Node3D and not (c as Node3D).visible:
			continue
		_collect(c, out)


## 部品が床に転がったときの高さ（一番薄い向きの半分）
func _rest_height(mi: MeshInstance3D) -> float:
	var s: Vector3 = mi.mesh.get_aabb().size * mi.global_basis.get_scale()
	return maxf(0.03, minf(s.x, minf(s.y, s.z)) * 0.5)


## 番号から作る 0〜1 の決まった値（乱数の代わり）
static func _h(i: int, k: int) -> float:
	var v: float = sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453
	return v - floorf(v)


func _sphere(radius: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 16
	s.rings = 8
	m.mesh = s
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m


## glow なら光を足し合わせる火の粉、そうでなければ暗い煙
func _particles(amount: int, life: float, spread: float, vmin: float, vmax: float, gravity: Vector3,
		glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	var mesh := BoxMesh.new()
	var m: StandardMaterial3D
	if glow:
		mesh.size = Vector3(0.08, 0.08, 0.08)
		m = _glow_mat(Color(1, 1, 1))
	else:
		mesh.size = Vector3(0.5, 0.5, 0.5)
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1, 1, 1)
		var ramp := Gradient.new()
		ramp.set_color(0, Color(Look.EXPLOSION_SMOKE, 0.7))
		ramp.set_color(1, Color(Look.EXPLOSION_SMOKE, 0.0))
		p.color_ramp = ramp
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.4))
		grow.add_point(Vector2(1, 1.6))
		p.scale_amount_curve = grow
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.5
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	add_child(p)
	return p
