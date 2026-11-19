# ハープーンガンの見た目。銃口から釣り針まで鎖の輪を並べ、飛んでいる間は少したわませ、引き寄せる間はぴんと張って
# 輪が銃口の巻き取り機へ吸い込まれていく（巻き取り機は回る）。引きずられる相手の足もとに火花、鉄を引きずる音と鎖の音。
# 試合の状態は読むだけ。robot_view.gd が毎フレーム update() を呼ぶ。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")
const Sfx := preload("res://view/sfx.gd")

## 今の状態（"" / "fly" / "pull" / "back"）と、見えている鎖の輪の数（テストと確認用）
var state: String = ""
var visible_links: int = 0
## 巻き取った鎖の長さ（輪が銃口へ動いていく量）と、巻き取り機の回った角度
var reeled: float = 0.0
var reel_angle: float = 0.0
var drag_player: AudioStreamPlayer3D
var _links: Array[MeshInstance3D] = []
var _head: Node3D
var _reel: Node3D
var _sparks: CPUParticles3D
var _fx_player: AudioStreamPlayer3D
var _prev_len: float = -1.0


func setup() -> void:
	var steel: StandardMaterial3D = Grime.material(Look.HOOK_CHAIN_COLOR, 0.85, 0.45, 2.0)
	for k: int in Look.HOOK_MAX_LINKS:
		var m := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = Look.HOOK_LINK_SIZE * 0.45
		ring.outer_radius = Look.HOOK_LINK_SIZE * 0.75
		ring.rings = 8
		ring.ring_segments = 4
		m.mesh = ring
		m.material_override = steel
		m.visible = false
		add_child(m)
		_links.append(m)
	_head = _make_head()
	add_child(_head)
	_reel = _make_reel()
	add_child(_reel)
	# 引きずられる相手の足もとで床をこする火花
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.amount = 40
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3.UP
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 2.0
	_sparks.initial_velocity_max = 6.0
	_sparks.gravity = Vector3(0, -14, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.06, 0.06, 0.06)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.albedo_color = Look.SPARK_COLOR
	spark_mesh.material = sm
	_sparks.mesh = spark_mesh
	add_child(_sparks)
	# 音：引きずる音（くり返し）と、撃つ・刺さる・着くときの音
	drag_player = AudioStreamPlayer3D.new()
	drag_player.stream = Sfx.chain_drag()
	drag_player.unit_size = 12.0
	add_child(drag_player)
	_fx_player = AudioStreamPlayer3D.new()
	_fx_player.unit_size = 12.0
	add_child(_fx_player)
	_hide_all()


## state は釣り針の状態、muzzle は銃口、hook は釣り針の位置（どちらも世界の座標）、target_radius は引き寄せる相手の半径
func update(new_state: String, muzzle: Vector3, hook: Vector3, target_radius: float, delta: float) -> void:
	if new_state != state:
		_on_change(state, new_state, hook)
		state = new_state
	if state == "":
		_hide_all()
		return
	var line: Vector3 = hook - muzzle
	var length: float = line.length()
	if length < 0.01:
		_hide_all()
		return
	var dir: Vector3 = line / length
	# 引き寄せている間は、縮んだぶんだけ鎖を巻き取ったことにする（輪が銃口へ流れ、巻き取り機が回る）
	if state == "pull" and _prev_len >= 0.0:
		var got: float = maxf(0.0, _prev_len - length)
		reeled += got
		reel_angle += got / Look.HOOK_REEL_RADIUS
	elif state == "back" and _prev_len >= 0.0:
		var got_back: float = maxf(0.0, _prev_len - length)
		reeled += got_back
		reel_angle += got_back / Look.HOOK_REEL_RADIUS
	_prev_len = length
	# 釣り針の頭：引き寄せている間は相手の体の表面（自分の側）に刺さっている
	var head_at: Vector3 = hook - dir * target_radius * 0.8 if state == "pull" else hook
	var chain_end: Vector3 = head_at
	var chain_len: float = (chain_end - muzzle).length()
	_place_links(muzzle, chain_end, chain_len)
	_head.visible = true
	_head.global_transform = Transform3D(_basis_along(dir, 1.0), head_at)
	# 巻き取り機：銃口のところで、鎖と直角な軸で回る
	_reel.visible = true
	var side: Vector3 = _side_of(dir)
	_reel.global_transform = Transform3D(Basis(side, reel_angle) * _basis_along(dir, 1.0), muzzle)
	# 引きずる火花と音
	var dragging: bool = state == "pull"
	_sparks.emitting = dragging
	_sparks.global_position = Vector3(hook.x, 0.05, hook.z) - dir * target_radius * 0.5
	drag_player.global_position = Vector3(hook.x, 0.5, hook.z)
	if dragging and not drag_player.playing and drag_player.is_inside_tree():
		drag_player.play()
	elif not dragging and drag_player.playing:
		drag_player.stop()


## 鎖の輪を、銃口から釣り針まで並べる。巻き取った量だけ輪の並びを銃口側へずらす（吸い込まれていくように見える）
func _place_links(a: Vector3, b: Vector3, length: float) -> void:
	var dir: Vector3 = (b - a) / maxf(0.001, length)
	var spacing: float = Look.HOOK_LINK_SIZE * 1.25
	var offset: float = fposmod(-reeled, spacing)
	var shift: int = int(floor(reeled / spacing))
	var sag: float = 0.0 if state == "pull" else Look.HOOK_SAG * minf(1.0, length / 10.0)
	var up_axis: Vector3 = _side_of(dir).cross(dir).normalized()
	var side_axis: Vector3 = _side_of(dir)
	var count: int = 0
	var s: float = offset
	while s < length and count < _links.size():
		var u: float = s / length
		var p: Vector3 = a + dir * s + Vector3.DOWN * sag * 4.0 * u * (1.0 - u)
		var m: MeshInstance3D = _links[count]
		m.visible = true
		# 輪は1つおきに 90° ねじる（本物の鎖のように）
		var ring_axis: Vector3 = up_axis if (count + shift) % 2 == 0 else side_axis
		var x_axis: Vector3 = dir * 1.6
		m.global_transform = Transform3D(Basis(x_axis, ring_axis, dir.cross(ring_axis)), p)
		count += 1
		s += spacing
	for k: int in range(count, _links.size()):
		_links[k].visible = false
	visible_links = count


func _on_change(old: String, new: String, at: Vector3) -> void:
	if new == "fly":
		reeled = 0.0
		_prev_len = -1.0
		_play_fx(Sfx.launch(), at)
	elif new == "pull":
		_play_fx(Sfx.clank(), at)  # 刺さった
	elif new == "" and old == "pull":
		_play_fx(Sfx.clank(), at)  # 引き寄せ終わり、ぶつかった


func _play_fx(stream: AudioStream, at: Vector3) -> void:
	if not _fx_player.is_inside_tree():
		return
	_fx_player.stream = stream
	_fx_player.global_position = at
	_fx_player.play()


func _hide_all() -> void:
	for m: MeshInstance3D in _links:
		m.visible = false
	visible_links = 0
	if _head != null:
		_head.visible = false
	if _reel != null:
		_reel.visible = false
	if _sparks != null:
		_sparks.emitting = false
	if drag_player != null and drag_player.playing:
		drag_player.stop()
	_prev_len = -1.0


## 釣り針の頭：太い軸、後ろに鎖をつなぐ輪、前に返しのついた3本の爪。先は熱で赤く光る
func _make_head() -> Node3D:
	var h := Node3D.new()
	var metal: StandardMaterial3D = Grime.material(Look.HOOK_HEAD_COLOR, 0.85, 0.45, 2.0)
	var hot: StandardMaterial3D = Grime.material(Look.HOOK_HOT_COLOR, 0.2, 0.6, 2.0, Look.HOOK_HOT_COLOR)
	_part(h, _box(Vector3(0.5, 0.12, 0.12)), Vector3(-0.15, 0, 0), Vector3.ZERO, metal)
	for k: int in 3:
		var a: float = TAU * k / 3.0
		var off := Vector3(0, cos(a), sin(a)) * 0.12
		# 前へ伸びる爪と、後ろへ反り返る返し
		_part(h, _box(Vector3(0.32, 0.06, 0.06)), Vector3(0.18, 0, 0) + off * 0.8, Vector3(rad_to_deg(a), 0, 0), metal)
		_part(h, _box(Vector3(0.16, 0.05, 0.05)), Vector3(0.22, 0, 0) + off * 1.7,
			Vector3(rad_to_deg(a), 0, 0) + Vector3(0, 0, 0), hot)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = 0.28
	cone.radial_segments = 6
	tip.mesh = cone
	tip.material_override = hot
	tip.rotation_degrees = Vector3(0, 0, -90)
	tip.position = Vector3(0.42, 0, 0)
	h.add_child(tip)
	return h


## 巻き取り機：鎖を巻く太鼓と、両側のつば
func _make_reel() -> Node3D:
	var r := Node3D.new()
	var metal: StandardMaterial3D = Grime.material(Look.HOOK_CHAIN_COLOR.darkened(0.3), 0.8, 0.5, 2.0)
	var drum := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = Look.HOOK_REEL_RADIUS
	c.bottom_radius = Look.HOOK_REEL_RADIUS
	c.height = 0.32
	c.radial_segments = 8
	drum.mesh = c
	drum.material_override = metal
	drum.rotation_degrees = Vector3(90, 0, 0)  # 軸を横（鎖と直角）に
	r.add_child(drum)
	for z: float in [-0.18, 0.18]:
		var fl := MeshInstance3D.new()
		var fc := CylinderMesh.new()
		fc.top_radius = Look.HOOK_REEL_RADIUS * 1.6
		fc.bottom_radius = Look.HOOK_REEL_RADIUS * 1.6
		fc.height = 0.04
		fc.radial_segments = 8
		fl.mesh = fc
		fl.material_override = metal
		fl.rotation_degrees = Vector3(90, 0, 0)
		fl.position = Vector3(0, 0, z)
		r.add_child(fl)
	# 回っているのが分かるよう、太鼓に1本だけ明るい筋
	_part(r, _box(Vector3(0.05, 0.05, 0.3)), Vector3(0, Look.HOOK_REEL_RADIUS, 0), Vector3.ZERO,
		Grime.material(Look.HOOK_HOT_COLOR, 0.2, 0.6, 2.0))
	return r


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	parent.add_child(m)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## dir を X 軸にした向き（Y はなるべく上）
static func _basis_along(dir: Vector3, scale_x: float) -> Basis:
	var side: Vector3 = _side_of(dir)
	var up: Vector3 = side.cross(dir).normalized()
	return Basis(dir * scale_x, up, dir.cross(up))


static func _side_of(dir: Vector3) -> Vector3:
	var s: Vector3 = dir.cross(Vector3.UP)
	if s.length() < 0.001:
		s = dir.cross(Vector3.RIGHT)
	return s.normalized()
