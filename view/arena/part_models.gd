# パーツの3Dモデル（data/parts.json の model に書いた .glb）を読み込む係。ファイルがなければ null を返し、呼ぶ側は仮の箱で描く。
# 読み込んだモデルは大きさを機体に合わせ、材質をぼかさない・つやを抑える設定に直して、低解像度の荒い見た目になじませる。
extends RefCounted

const Look := preload("res://view/look.gd")

## 取り付け位置の目印にする空のノードの名前の頭（フレームのモデルの中に置く。例：weapon_0、skill_1）
const MOUNT_WEAPON: String = "weapon_"
const MOUNT_SKILL: String = "skill_"
## ライトの位置の目印（lamp_0, lamp_1 …）。view/arena/motion_fx_view.gd が光るレンズを置く
const MOUNT_LAMP: String = "lamp_"

## 読み込んだモデルのひな形（パス → PackedScene。見つからなかったものは null）
static var _templates: Dictionary = {}
## 直した材質（元の材質と陣営の色 → 直した材質）
static var _materials: Dictionary = {}


## モデルを1つ作って返す。ファイルがない・読めないときは null。
## Godot に取り込み済みならそれを使い、まだ取り込んでいない .glb はその場で読む（置いてすぐ試せるように）
static func instantiate(path: String) -> Node3D:
	if path.is_empty():
		return null
	if not _templates.has(path):
		_templates[path] = _load(path)
	var t: PackedScene = _templates[path]
	if t == null:
		return null
	var n: Node = t.instantiate()
	if n is Node3D:
		return n
	n.free()
	return null


## 読み込みの覚えを消す（テストや、モデルを置き換えたとき用）
static func clear_cache() -> void:
	_templates.clear()
	_materials.clear()


static func _load(path: String) -> PackedScene:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		return res as PackedScene if res is PackedScene else null
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_warning("モデルを読めない：%s" % path)
		return null
	var root: Node = doc.generate_scene(state)
	if root == null:
		return null
	# ひな形として覚えるため、中のノードをすべて根元の持ち物にしてから1つにまとめる
	_own_all(root, root)
	var packed := PackedScene.new()
	var ok: bool = root is Node3D and packed.pack(root) == OK
	root.free()
	return packed if ok else null


static func _own_all(n: Node, owner_node: Node) -> void:
	for c: Node in n.get_children():
		c.owner = owner_node
		_own_all(c, owner_node)


## モデルの中のメッシュ全体を囲む箱（モデルの根元から見た位置）
static func bounds(root: Node3D) -> AABB:
	var acc: Array = [AABB(), false]
	_collect_bounds(root, Transform3D.IDENTITY, acc)
	return acc[0]


static func _collect_bounds(n: Node, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var box: AABB = xf * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = box if not acc[1] else (acc[0] as AABB).merge(box)
		acc[1] = true
	for c: Node in n.get_children():
		var cx: Transform3D = xf * (c as Node3D).transform if c is Node3D else xf
		_collect_bounds(c, cx, acc)


## 取り付け位置の目印を探す。prefix で始まる名前のノードを番号順に並べ、モデルの根元から見た位置と向きを返す
static func mounts(root: Node3D, prefix: String) -> Array[Transform3D]:
	var found: Dictionary = {}
	_collect_mounts(root, Transform3D.IDENTITY, prefix.to_lower(), found)
	var keys: Array = found.keys()
	keys.sort()
	var out: Array[Transform3D] = []
	for k: Variant in keys:
		out.append(found[k])
	return out


static func _collect_mounts(n: Node, xf: Transform3D, prefix: String, found: Dictionary) -> void:
	for c: Node in n.get_children():
		if not (c is Node3D):
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		var name: String = String(c.name).to_lower()
		if name.begins_with(prefix) and name.substr(prefix.length()).is_valid_int():
			found[int(name.substr(prefix.length()))] = cx
		_collect_mounts(c, cx, prefix, found)


## 大きさをそろえる倍率：囲む箱の一番長い辺（axes で選んだ軸の中で）が size になるように
static func fit_scale(box: AABB, size: float, axes: Vector3 = Vector3.ONE) -> float:
	if not Look.MODEL_AUTO_FIT:
		return 1.0
	var s: Vector3 = box.size * axes
	var longest: float = maxf(s.x, maxf(s.y, s.z))
	return size / longest if longest > 0.0001 else 1.0


## 材質を荒い見た目に直す：テクスチャをぼかさない、つやを抑える、陣営の色を少し混ぜる
static func roughen(root: Node, side_color: Color) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var src: Material = mi.get_active_material(i)
				if src is BaseMaterial3D:
					mi.set_surface_override_material(i, _rough_material(src as BaseMaterial3D, side_color))
	for c: Node in root.get_children():
		roughen(c, side_color)


static func _rough_material(src: BaseMaterial3D, side_color: Color) -> BaseMaterial3D:
	var key: String = "%d/%s" % [src.get_instance_id(), side_color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var m := src.duplicate() as BaseMaterial3D
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.roughness = maxf(m.roughness, Look.MODEL_ROUGHNESS_MIN)
	m.metallic = minf(m.metallic, Look.MODEL_METALLIC_MAX)
	m.albedo_color = m.albedo_color.lerp(side_color, Look.MODEL_SIDE_TINT) if side_color.a > 0.0 else m.albedo_color
	_materials[key] = m
	return m
