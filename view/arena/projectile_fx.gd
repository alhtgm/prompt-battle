# 撃つ武器の弾の見た目。ロケットは尾翼のついた弾体が後ろから炎を噴いて飛び、煙の尾を引く。撃つと発射炎と後ろへの煙、
# 当たる（消える）と爆発。機関銃は光の筋（曳光弾）が飛び、銃口が光り、当たると火花。弾の通し番号で、出た・消えたを見分ける。
# 試合の状態は読むだけ。arena_view.gd が毎フレーム sync() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")

## 弾の高さ（m）
const SHOT_Y: float = 0.9

## 飛んでいる弾：通し番号 → {"node", "style", "pos", "dir", "trail"}
var live: Dictionary = {}
## 発射・着弾の演出の数（テストと確認用）
var launches: int = 0
var impacts: int = 0
var _effects: Array = []  # [ノード, 残り秒数]
var _clock: float = 0.0
var _mats: Dictionary = {}


## shots は今飛んでいる弾（x, z, vx, vz, id, def_id を持つ）
func sync(shots: Array, delta: float) -> void:
	_clock += delta
	var seen: Dictionary = {}
	for s: Variant in shots:
		var id: int = int(s.id)
		seen[id] = true
		var pos := Vector3(float(s.x), SHOT_Y, float(s.z))
		var v := Vector3(float(s.vx), 0.0, float(s.vz))
		var dir: Vector3 = v.normalized() if v.length() > 0.01 else Vector3.RIGHT
		if not live.has(id):
			var style: String = Look.SHOT_STYLES.get(str(s.def_id), "tracer")
			live[id] = _spawn(style, pos, dir)
		var e: Dictionary = live[id]
		e["pos"] = pos
		e["dir"] = dir
		var n: Node3D = e["node"]
		n.global_transform = Transform3D(_basis_along(dir), pos)
		if e["style"] == "rocket":
			_flicker_flame(n)
	# 消えた弾：当たったか、射程の終わり。そこで着弾の演出
	for id: Variant in live.keys():
		if seen.has(id):
			continue
		var e: Dictionary = live[id]
		_impact(e["style"], e["pos"], e["dir"])
		# 煙の尾や火の粉（世界に置く粒）は弾から切り離し、少しのあいだ残して消す
		for c: Node in (e["node"] as Node).get_children():
			if c is CPUParticles3D and not (c as CPUParticles3D).local_coords:
				var p: CPUParticles3D = c
				var keep: Transform3D = p.global_transform
				p.emitting = false
				p.reparent(self, false)
				p.global_transform = keep
				_effects.append([p, p.lifetime + 0.1])
		(e["node"] as Node).queue_free()
		live.erase(id)
	for k: int in range(_effects.size() - 1, -1, -1):
		var fx: Array = _effects[k]
		fx[1] -= delta
		var node: Node3D = fx[0]
		if node.has_method("tick"):
			node.call("tick", delta)
		if fx[1] <= 0.0:
			node.queue_free()
			_effects.remove_at(k)


# ---- 弾 ----

func _spawn(style: String, pos: Vector3, dir: Vector3) -> Dictionary:
	launches += 1
	if style == "rocket":
		var r: Node3D = _make_rocket()
		add_child(r)
		r.global_transform = Transform3D(_basis_along(dir), pos)
		var trail: CPUParticles3D = r.get_node("Trail")
		# 世界に置く粒は、木に入ってから出し始める
		trail.emitting = true
		(r.get_node("Embers") as CPUParticles3D).emitting = true
		_launch_rocket(pos, dir)
		return {"node": r, "style": style, "pos": pos, "dir": dir, "trail": trail}
	var t: Node3D = _make_tracer()
	add_child(t)
	t.global_transform = Transform3D(_basis_along(dir), pos)
	_muzzle_flash(pos, dir, 0.5, 0.06)
	return {"node": t, "style": style, "pos": pos, "dir": dir, "trail": null}


## ロケット：くすんだ緑の弾体、赤い弾頭、4枚の尾翼。後ろに二重の炎（外は橙、芯は白っぽい黄色）と、照らす光と、煙の尾
func _make_rocket() -> Node3D:
	var r := Node3D.new()
	var body: StandardMaterial3D = Grime.material(Look.ROCKET_BODY, 0.6, 0.6, 3.0)
	_cyl_part(r, 0.09, 0.09, 0.55, Vector3(0, 0, 0), body)
	_cyl_part(r, 0.09, 0.0, 0.2, Vector3(0.37, 0, 0), Grime.material(Look.ROCKET_NOSE, 0.4, 0.6, 3.0))
	for k: int in 4:
		var fin := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.16, 0.02, 0.12)
		fin.mesh = b
		fin.material_override = body
		fin.position = Vector3(-0.22, 0, 0)
		fin.rotation = Vector3(TAU * k / 4.0, 0, 0)
		fin.position += Vector3(0, cos(TAU * k / 4.0), sin(TAU * k / 4.0)) * 0.1
		r.add_child(fin)
	var outer := _cyl_part(r, 0.11, 0.0, 0.7, Vector3(-0.62, 0, 0), _glow(Look.ROCKET_FLAME), true)
	outer.name = "FlameOuter"
	var inner := _cyl_part(r, 0.06, 0.0, 0.4, Vector3(-0.47, 0, 0), _glow(Look.ROCKET_FLAME_CORE), true)
	inner.name = "FlameInner"
	var light := OmniLight3D.new()
	light.light_color = Look.ROCKET_FLAME
	light.light_energy = Look.ROCKET_LIGHT
	light.omni_range = 4.0
	light.position = Vector3(-0.6, 0, 0)
	r.add_child(light)
	# 煙の尾：粒は世界に置くので、弾が進むと後ろに残る
	var trail: CPUParticles3D = _smoke(90, 1.6, 0.34, 0.8, 2.6)
	trail.name = "Trail"
	trail.local_coords = false
	trail.explosiveness = 0.0
	trail.one_shot = false
	trail.direction = Vector3(-1, 0.2, 0)
	trail.spread = 15.0
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 0.9
	trail.gravity = Vector3(0, 0.4, 0)
	trail.position = Vector3(-0.45, 0, 0)
	r.add_child(trail)
	# 炎のかけら（火の粉）も少し散らす
	var embers: CPUParticles3D = _sparks(20, 0.25, Look.ROCKET_FLAME, 1.0, 3.0)
	embers.local_coords = false
	embers.name = "Embers"
	embers.one_shot = false
	embers.explosiveness = 0.0
	embers.direction = Vector3(-1, 0, 0)
	embers.spread = 25.0
	embers.position = Vector3(-0.55, 0, 0)
	r.add_child(embers)
	return r


## 炎の長さと太さを小刻みにゆらす（時間の関数。乱数は使わない）
func _flicker_flame(r: Node3D) -> void:
	var outer: MeshInstance3D = r.get_node("FlameOuter")
	var inner: MeshInstance3D = r.get_node("FlameInner")
	var f: float = 0.8 + 0.2 * sin(_clock * 53.0) * sin(_clock * 37.0 + 1.3)
	outer.scale = Vector3(0.9 + 0.2 * f, f * 1.15, 0.9 + 0.2 * f)
	inner.scale = Vector3(1.0, 0.85 + 0.3 * f, 1.0)
	outer.position.x = -0.27 - 0.35 * f * 1.15
	inner.position.x = -0.27 - 0.2 * (0.85 + 0.3 * f)


## 曳光弾：進む向きに細長く光る筋（芯が白っぽい）
func _make_tracer() -> Node3D:
	var t := Node3D.new()
	var outer := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(Look.TRACER_LENGTH, 0.07, 0.07)
	outer.mesh = b
	outer.material_override = _glow(Look.TRACER_COLOR)
	outer.position = Vector3(-Look.TRACER_LENGTH * 0.5, 0, 0)
	t.add_child(outer)
	var core := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(Look.TRACER_LENGTH * 0.6, 0.03, 0.03)
	core.mesh = cb
	core.material_override = _glow(Color(1.0, 1.0, 0.85))
	core.position = Vector3(-Look.TRACER_LENGTH * 0.3, 0, 0)
	t.add_child(core)
	return t


# ---- 発射と着弾 ----

## ロケットの発射：銃口の閃光、前への炎、後ろへ噴き出す白い煙（バックブラスト）
func _launch_rocket(pos: Vector3, dir: Vector3) -> void:
	_muzzle_flash(pos, dir, 1.3, 0.15)
	var back: CPUParticles3D = _smoke(28, 1.4, 0.3, 0.6, 2.2)
	add_child(back)
	back.global_transform = Transform3D(_basis_along(-dir), pos - dir * 0.6)
	back.direction = Vector3(1, 0.3, 0)
	back.spread = 35.0
	back.initial_velocity_min = 2.0
	back.initial_velocity_max = 5.0
	back.gravity = Vector3(0, 0.6, 0)
	back.restart()
	_effects.append([back, 1.6])


## 銃口の閃光：短い光の星と、一瞬の光
func _muzzle_flash(pos: Vector3, dir: Vector3, size: float, life: float) -> void:
	var f := FlashNode.new()
	add_child(f)
	f.global_position = pos + dir * 0.15
	f.setup(_glow(Look.MUZZLE_FLASH), size, life)
	_effects.append([f, life])


## 着弾：ロケットは火の玉・火花・煙・閃光・床の輪。機関銃は小さな火花
func _impact(style: String, pos: Vector3, dir: Vector3) -> void:
	impacts += 1
	if style != "rocket":
		var sp: CPUParticles3D = _sparks(10, 0.3, Look.TRACER_COLOR, 2.0, 5.0)
		add_child(sp)
		sp.global_position = pos
		sp.direction = -dir + Vector3.UP * 0.5
		sp.spread = 60.0
		sp.restart()
		_effects.append([sp, 0.5])
		return
	var boom := BoomNode.new()
	add_child(boom)
	boom.global_position = pos
	boom.setup(_glow(Look.ROCKET_FLAME), _glow(Look.ROCKET_FLAME_CORE), _glow(Look.ROCKET_FLAME))
	_effects.append([boom, Look.ROCKET_BOOM_SEC])
	var sp2: CPUParticles3D = _sparks(36, 0.7, Look.ROCKET_FLAME, 4.0, 10.0)
	add_child(sp2)
	sp2.global_position = pos
	sp2.spread = 180.0
	sp2.restart()
	_effects.append([sp2, 1.0])
	var sm: CPUParticles3D = _smoke(18, 1.6, 0.4, 0.8, 2.4)
	add_child(sm)
	sm.global_position = pos
	sm.spread = 180.0
	sm.initial_velocity_min = 0.5
	sm.initial_velocity_max = 1.8
	sm.gravity = Vector3(0, 1.2, 0)
	sm.restart()
	_effects.append([sm, 1.8])


# ---- 部品 ----

func _cyl_part(parent: Node3D, bottom: float, top: float, height: float, pos: Vector3, mat: Material,
		flame: bool = false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = 8
	m.mesh = c
	m.material_override = mat
	# 円柱は縦向き。弾体と弾頭は前（+X）へ、炎は後ろ（-X）へ先を向ける
	m.rotation = Vector3(0, 0, PI * 0.5 if flame else -PI * 0.5)
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _glow(col: Color) -> StandardMaterial3D:
	var key: String = col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## 煙の粒：灰色で、だんだん大きく薄くなる
func _smoke(amount: int, life: float, size_from: float, size_to_mul: float, grow: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.9
	# 煙の粒は角ばらない低い多面体の球（低い解像度で、ふんわりした塊に見える）
	var mesh := SphereMesh.new()
	mesh.radius = size_from * 0.5
	mesh.height = size_from
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(Look.SMOKE_COLOR.lightened(0.25), 0.75 * size_to_mul))
	ramp.set_color(1, Color(Look.SMOKE_COLOR, 0.0))
	p.color_ramp = ramp
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, grow))
	p.scale_amount_curve = c
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	return p


## 火花の粒：光を足し合わせ、重力で落ちる
func _sparks(amount: int, life: float, col: Color, vmin: float, vmax: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = Vector3(0, -14, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06)
	var m := _glow(Color(1, 1, 1)).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	ramp.set_color(1, Color(col, 0.0))
	p.color_ramp = ramp
	return p


## dir を X 軸にした向き（Y はなるべく上）
static func _basis_along(dir: Vector3) -> Basis:
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = side.cross(dir).normalized()
	return Basis(dir, up, dir.cross(up))


## 銃口の閃光（光の星と光）。tick で縮んで消える
class FlashNode:
	extends Node3D
	var _life: float = 0.1
	var _age: float = 0.0
	var _star: MeshInstance3D
	var _light: OmniLight3D

	func setup(mat: Material, size: float, life: float) -> void:
		_life = life
		_star = MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.2 * size
		s.height = 0.3 * size
		s.radial_segments = 6
		s.rings = 3
		_star.mesh = s
		_star.material_override = mat
		add_child(_star)
		_light = OmniLight3D.new()
		_light.light_color = Look.MUZZLE_FLASH
		_light.omni_range = 3.0 * size
		_light.light_energy = 3.0 * size
		add_child(_light)

	func tick(delta: float) -> void:
		_age += delta
		var k: float = clampf(1.0 - _age / _life, 0.0, 1.0)
		_star.scale = Vector3.ONE * (0.5 + k)
		_light.light_energy = 3.0 * k


## ロケットの爆発：一気にふくらむ火の玉と白い芯、床を走る輪、強い閃光。tick で進む
class BoomNode:
	extends Node3D
	var _age: float = 0.0
	var _ball: MeshInstance3D
	var _core: MeshInstance3D
	var _ring: MeshInstance3D
	var _light: OmniLight3D
	var _ball_mat: StandardMaterial3D
	var _core_mat: StandardMaterial3D
	var _ring_mat: StandardMaterial3D

	func setup(ball_mat: StandardMaterial3D, core_mat: StandardMaterial3D, ring_mat: StandardMaterial3D) -> void:
		_ball_mat = ball_mat.duplicate()
		_core_mat = core_mat.duplicate()
		_ring_mat = ring_mat.duplicate()
		_ball = _sphere(1.0, _ball_mat)
		_core = _sphere(0.5, _core_mat)
		_ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.85
		t.outer_radius = 1.0
		t.rings = 24
		t.ring_segments = 4
		_ring.mesh = t
		_ring.material_override = _ring_mat
		_ring.position.y = -0.85
		add_child(_ring)
		_light = OmniLight3D.new()
		_light.light_color = Look.ROCKET_FLAME
		_light.omni_range = 7.0
		add_child(_light)
		tick(0.0)

	func _sphere(r: float, mat: Material) -> MeshInstance3D:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 12
		s.rings = 6
		m.mesh = s
		m.material_override = mat
		add_child(m)
		return m

	func tick(delta: float) -> void:
		_age += delta
		var t: float = clampf(_age / Look.ROCKET_BOOM_SEC, 0.0, 1.0)
		var grow: float = 1.0 - pow(1.0 - t, 3.0)
		_ball.scale = Vector3.ONE * lerpf(0.2, Look.ROCKET_BOOM_SIZE, grow)
		_core.scale = Vector3.ONE * lerpf(0.3, Look.ROCKET_BOOM_SIZE * 0.8, grow)
		_ball_mat.albedo_color = Look.ROCKET_FLAME.lerp(Look.SMOKE_COLOR, t) * Color(1, 1, 1, 1.0 - t)
		_core_mat.albedo_color.a = clampf(1.0 - t * 2.5, 0.0, 1.0)
		var rr: float = lerpf(0.3, Look.ROCKET_BOOM_SIZE * 2.2, grow)
		_ring.scale = Vector3(rr, 1.0, rr)
		_ring_mat.albedo_color.a = clampf(1.0 - t * 1.5, 0.0, 1.0)
		_light.light_energy = Look.ROCKET_BOOM_FLASH * exp(-_age * 9.0)
