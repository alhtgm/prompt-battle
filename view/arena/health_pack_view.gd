# 回復パックの見た目。光る輪のついた台の上に、白い十字（赤い縁どり）のついた水色の箱が浮かび、ゆっくり回って上下する。
# 大は箱が大きく、台の輪が二重で、より明るい。取られると光と粒がはじけて音が鳴り、新しく出るときは光の中から現れる。
# 試合の状態（packs）は読むだけ。arena_view.gd が毎フレーム sync() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const Sfx := preload("res://view/sfx.gd")

## パックの枠ごとの見た目：{"node", "id", "active", "big", "age"}
var slots: Array[Dictionary] = []
## 取られた・出たときの演出の数（テストと確認用）
var pickups: int = 0
var spawns: int = 0
var _effects: Array = []  # [ノード, 残り秒数]
var _clock: float = 0.0
var _mats: Dictionary = {}
var _player: AudioStreamPlayer3D


func _ready() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.stream = Sfx.heal_chime()
	_player.unit_size = 14.0
	add_child(_player)


## packs は battle_sim.gd の packs（{"id", "x", "z", "big", "active", ...} の配列）
func sync(packs: Array, delta: float) -> void:
	_clock += delta
	while slots.size() < packs.size():
		slots.append({"node": null, "id": -1, "active": false, "big": false, "age": 0.0, "pos": Vector3.ZERO})
	for k: int in packs.size():
		var p: Dictionary = packs[k]
		var s: Dictionary = slots[k]
		var active: bool = bool(p.get("active", false))
		var pos := Vector3(float(p.get("x", 0.0)), 0.0, float(p.get("z", 0.0)))
		# 取られた：今いた場所で光がはじける
		if s["active"] and not active:
			_pickup(s["pos"], s["big"])
		# 新しく出た（または別の場所に出直した）：作り直して、光の中から現れる
		if active and (not s["active"] or int(p.get("id", -1)) != int(s["id"])):
			if s["node"] != null:
				(s["node"] as Node).queue_free()
			var n: Node3D = _make_pack(bool(p.get("big", false)))
			add_child(n)
			n.global_position = pos
			s["node"] = n
			s["age"] = 0.0
			s["big"] = bool(p.get("big", false))
			s["id"] = int(p.get("id", -1))
			spawns += 1
			_spawn_flash(pos, s["big"])
		if not active and s["node"] != null:
			(s["node"] as Node).queue_free()
			s["node"] = null
		s["active"] = active
		s["pos"] = pos
		if s["node"] != null:
			s["age"] = float(s["age"]) + delta
			_animate(s["node"], float(s["age"]), k)
	for k: int in range(_effects.size() - 1, -1, -1):
		var fx: Array = _effects[k]
		fx[1] -= delta
		var node: Node3D = fx[0]
		if node.has_method("tick"):
			node.call("tick", delta)
		if fx[1] <= 0.0:
			node.queue_free()
			_effects.remove_at(k)


## 浮かぶ箱を回して上下させる。出たばかりは小さい所から少し行き過ぎて大きくなる
func _animate(n: Node3D, age: float, k: int) -> void:
	var box: Node3D = n.get_node("Box")
	var pop: float = clampf(age / 0.35, 0.0, 1.0)
	var grow: float = 1.0 + 1.70158 * pow(pop - 1.0, 3.0) + 0.70158 * pow(pop - 1.0, 2.0) if pop < 1.0 else 1.0
	box.scale = Vector3.ONE * maxf(0.01, grow)
	box.position.y = Look.PACK_HOVER + sin(_clock * 2.2 + k * 1.7) * 0.12
	box.rotation.y = _clock * 1.1 + k
	var glow: OmniLight3D = n.get_node("Light")
	glow.light_energy = (Look.PACK_LIGHT * (1.4 if n.get_meta("big") else 1.0)) * (0.85 + 0.15 * sin(_clock * 3.0 + k))


# ---- 形 ----

func _make_pack(big: bool) -> Node3D:
	var n := Node3D.new()
	n.set_meta("big", big)
	var size: float = Look.PACK_SIZE_BIG if big else Look.PACK_SIZE_SMALL
	# 台：暗い金属の円盤と、水色に光る輪（大は二重）
	var base := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = size * 1.25
	disc.bottom_radius = size * 1.35
	disc.height = 0.12
	disc.radial_segments = 16
	base.mesh = disc
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.16, 0.17, 0.19)
	bm.metallic = 0.7
	bm.roughness = 0.5
	base.material_override = bm
	base.position.y = 0.06
	n.add_child(base)
	for r: float in ([size * 1.3, size * 1.55] if big else [size * 1.3]):
		var ring := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = r - 0.04
		t.outer_radius = r + 0.04
		t.rings = 32
		t.ring_segments = 4
		ring.mesh = t
		ring.material_override = _glow(Look.PACK_COLOR)
		ring.position.y = 0.13
		n.add_child(ring)
	# 台の上の、寝かせた十字
	var flat := Node3D.new()
	flat.position.y = 0.125
	flat.rotation = Vector3(-PI * 0.5, 0, 0)
	_add_cross(flat, size * 0.9)
	n.add_child(flat)
	# 薄い光の柱（遠くからでも見つけやすく）
	var beam := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = size * 0.5
	bc.bottom_radius = size * 0.9
	bc.height = 3.0
	bc.radial_segments = 12
	beam.mesh = bc
	beam.material_override = _glow(Look.PACK_COLOR, 0.12)
	beam.position.y = 1.5
	n.add_child(beam)
	# 浮かぶ箱：水色の箱の4つの横の面と上に、赤い縁の白い十字
	var box := Node3D.new()
	box.name = "Box"
	n.add_child(box)
	var body := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE * size
	body.mesh = bx
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Look.PACK_COLOR
	bmat.emission_enabled = true
	bmat.emission = Look.PACK_COLOR
	bmat.emission_energy_multiplier = 0.45
	bmat.roughness = 0.35
	bmat.metallic = 0.1
	body.material_override = bmat
	box.add_child(body)
	# 角の縁（少し濃い水色の枠で、箱らしく）
	for e: Array in [[Vector3(1, 1, 0), Vector3(0.06, 0.06, 1.02)], [Vector3(1, -1, 0), Vector3(0.06, 0.06, 1.02)],
			[Vector3(-1, 1, 0), Vector3(0.06, 0.06, 1.02)], [Vector3(-1, -1, 0), Vector3(0.06, 0.06, 1.02)]]:
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = e[1] * size
		edge.mesh = eb
		var em := StandardMaterial3D.new()
		em.albedo_color = Look.PACK_COLOR.darkened(0.35)
		edge.material_override = em
		edge.position = (e[0] as Vector3) * size * 0.5
		box.add_child(edge)
	for face: Array in [[Vector3(0, 0, 0), 0.0], [Vector3(0, PI * 0.5, 0), 0.0], [Vector3(0, PI, 0), 0.0],
			[Vector3(0, -PI * 0.5, 0), 0.0], [Vector3(-PI * 0.5, 0, 0), 0.0]]:
		var holder := Node3D.new()
		holder.rotation = face[0]
		box.add_child(holder)
		var front := Node3D.new()
		front.position.z = size * 0.5 + 0.005
		holder.add_child(front)
		_add_cross(front, size * 0.78)
	# 水色の光
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = Look.PACK_COLOR
	light.omni_range = 4.0 if big else 3.0
	light.position.y = Look.PACK_HOVER
	n.add_child(light)
	return n


## 赤い縁どりの白い十字を、parent の XY 面（+Z 向き）に置く。span は十字の端から端までの長さ
func _add_cross(parent: Node3D, span: float) -> void:
	var arm: float = span * 0.3
	for k: int in 2:
		var red := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(span, arm, 0.02) if k == 0 else Vector3(arm, span, 0.02)
		red.mesh = rb
		red.material_override = _solid(Look.PACK_CROSS_EDGE)
		parent.add_child(red)
		var white := MeshInstance3D.new()
		var wb := BoxMesh.new()
		var inset: float = span * 0.1
		wb.size = Vector3(span - inset, arm - inset, 0.03) if k == 0 else Vector3(arm - inset, span - inset, 0.03)
		white.mesh = wb
		white.material_override = _solid(Look.PACK_CROSS, true)
		white.position.z = 0.01
		parent.add_child(white)


# ---- 演出 ----

## 取ったとき：白と水色の光の粒が舞い上がり、輪が広がり、一瞬明るく光って音が鳴る
func _pickup(pos: Vector3, big: bool) -> void:
	pickups += 1
	var burst := CPUParticles3D.new()
	burst.one_shot = true
	burst.amount = 50 if big else 30
	burst.lifetime = 0.9
	burst.explosiveness = 0.9
	burst.direction = Vector3.UP
	burst.spread = 40.0
	burst.initial_velocity_min = 2.0
	burst.initial_velocity_max = 6.0
	burst.gravity = Vector3(0, -2.0, 0)
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.6
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.1, 0.1, 0.1)
	var m := _glow(Color(1, 1, 1)).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	burst.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(Look.PACK_COLOR, 0.0))
	burst.color_ramp = ramp
	add_child(burst)
	burst.global_position = pos + Vector3.UP * 0.6
	burst.restart()
	_effects.append([burst, 1.0])
	var ring := RingFx.new()
	add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.1
	ring.setup(_glow(Look.PACK_COLOR).duplicate(), 2.5 if big else 1.8, 0.45)
	_effects.append([ring, 0.45])
	if _player.is_inside_tree():
		_player.global_position = pos
		_player.play()


## 新しく出たとき：光の柱がさっと立つ
func _spawn_flash(pos: Vector3, big: bool) -> void:
	var col := RingFx.new()
	add_child(col)
	col.global_position = pos + Vector3.UP * 0.1
	col.setup(_glow(Color(1, 1, 1)).duplicate(), 1.2 if big else 0.9, 0.35)
	_effects.append([col, 0.35])


func _glow(col: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var key: String = "g/%s/%.2f" % [col.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col, alpha)
	_mats[key] = m
	return m


## 十字の色：暗いアリーナでもくっきり見えるよう、自分で少し光らせる
func _solid(col: Color, bright: bool = false) -> StandardMaterial3D:
	var key: String = "s/%s" % col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9 if bright else 0.5
	m.roughness = 0.6
	_mats[key] = m
	return m


## 床を広がって消える光の輪。tick で進む
class RingFx:
	extends Node3D
	var _age: float = 0.0
	var _life: float = 0.4
	var _size: float = 1.0
	var _ring: MeshInstance3D
	var _mat: StandardMaterial3D

	func setup(mat: StandardMaterial3D, size: float, life: float) -> void:
		_mat = mat
		_size = size
		_life = life
		_ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.85
		t.outer_radius = 1.0
		t.rings = 32
		t.ring_segments = 4
		_ring.mesh = t
		_ring.material_override = _mat
		add_child(_ring)
		tick(0.0)

	func tick(delta: float) -> void:
		_age += delta
		var k: float = clampf(_age / _life, 0.0, 1.0)
		var r: float = lerpf(0.3, _size, 1.0 - pow(1.0 - k, 2.0))
		_ring.scale = Vector3(r, 1.0, r)
		_mat.albedo_color.a = 1.0 - k
