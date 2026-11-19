# パーツの3Dモデルの読み込みのテスト。テストの中で小さな .glb を作り、読み込み・取り付け位置・大きさ・荒い材質・箱への戻りを確かめる。
# 置いたモデルは user:// の下に作り、終わったら消す（プロジェクトのファイルは触らない）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Look := preload("res://view/look.gd")
const PartModels := preload("res://view/arena/part_models.gd")
const RobotView := preload("res://view/arena/robot_view.gd")

const DIR: String = "user://test_part_models"


## 箱1つと、名前のついた空のノード（取り付け位置の目印）でできたモデルを .glb に書き出す
func _write_glb(path: String, size: Vector3, markers: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Model"
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.metallic = 1.0
	mat.roughness = 0.1  # つるつるの材質（荒い見た目に直されるかを見る）
	mesh.material = mat
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	for marker_name: String in markers:
		var m := Node3D.new()
		m.name = marker_name
		m.position = markers[marker_name]
		root.add_child(m)
		m.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	check_eq(doc.append_from_scene(root, state), OK, "テスト用モデルを組める：%s" % path)
	check_eq(doc.write_to_filesystem(state, ProjectSettings.globalize_path(path)), OK, "テスト用モデルを書き出せる：%s" % path)
	root.free()


func _cleanup() -> void:
	PartModels.clear_cache()
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f: String in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


## 一番上の材質を探す（荒い見た目に直されたかを見る）
func _first_surface_material(n: Node) -> Material:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return (n as MeshInstance3D).get_active_material(0)
	for c: Node in n.get_children():
		var m: Material = _first_surface_material(c)
		if m != null:
			return m
	return null


## assets/ に置いたパーツのモデル：あるものは読めて、フレームには枠の数だけ取り付け位置の目印がある
func test_shipped_models_load_and_frames_have_mounts() -> void:
	var data := GameData.new()
	data.load_dir()
	PartModels.clear_cache()
	for def: GameData.PartDef in data.parts:
		var def_id: String = def.id
		if not (ResourceLoader.exists(def.model) or FileAccess.file_exists(def.model)):
			continue  # まだモデルのないパーツは箱で描く（それでよい）
		var model: Node3D = PartModels.instantiate(def.model)
		check(model != null, "%s のモデルが読める" % def_id)
		if model == null:
			continue
		check(PartModels.bounds(model).size.length() > 0.01, "%s のモデルに形がある" % def_id)
		if def.kind == GameData.KIND_FRAME:
			check(PartModels.mounts(model, PartModels.MOUNT_WEAPON).size() >= def.weapon_slots,
				"%s に武器の目印が枠の数（%d）だけある" % [def_id, def.weapon_slots])
			check(PartModels.mounts(model, PartModels.MOUNT_SKILL).size() >= def.skill_slots,
				"%s にスキルの目印が枠の数（%d）だけある" % [def_id, def.skill_slots])
		model.free()
	PartModels.clear_cache()


func test_missing_model_is_null() -> void:
	check(PartModels.instantiate("") == null, "場所が空ならモデルなし")
	check(PartModels.instantiate("res://assets/models/parts/no_such_part.glb") == null, "ファイルがなければモデルなし")


func test_load_mounts_and_bounds() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var path: String = DIR + "/frame.glb"
	# 目印は番号の順番どおりに並ばなくても、番号順に返ってくる
	_write_glb(path, Vector3(4, 1, 2), {
		"weapon_1": Vector3(2, 0.5, 0.6), "weapon_0": Vector3(2, 0.5, -0.6), "skill_0": Vector3(-1, 1, 0),
		"weapon_x": Vector3(9, 9, 9),
	})
	var model: Node3D = PartModels.instantiate(path)
	check(model != null, "取り込んでいない .glb もその場で読める")
	if model == null:
		_cleanup()
		return
	var box: AABB = PartModels.bounds(model)
	check(box.size.is_equal_approx(Vector3(4, 1, 2)), "モデル全体の大きさが分かる（%s）" % box.size)
	var w: Array[Transform3D] = PartModels.mounts(model, PartModels.MOUNT_WEAPON)
	check_eq(w.size(), 2, "武器の目印は番号つきの2つだけ（weapon_x は数えない）")
	if w.size() == 2:
		check(w[0].origin.is_equal_approx(Vector3(2, 0.5, -0.6)), "weapon_0 が最初")
		check(w[1].origin.is_equal_approx(Vector3(2, 0.5, 0.6)), "weapon_1 が次")
	check_eq(PartModels.mounts(model, PartModels.MOUNT_SKILL).size(), 1, "スキルの目印は1つ")
	check(is_equal_approx(PartModels.fit_scale(box, 2.0, Vector3(1, 0, 1)), 0.5), "前後の長さ4を2にそろえる倍率は0.5")
	var other: Node3D = PartModels.instantiate(path)
	check(other != model, "呼ぶたびに別のモデルを作る")
	model.free()
	other.free()
	_cleanup()


func test_robot_uses_models_and_falls_back_to_boxes() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var frame_path: String = DIR + "/frame.glb"
	var weapon_path: String = DIR + "/weapon.glb"
	_write_glb(frame_path, Vector3(4, 1, 2), {"weapon_0": Vector3(2, 0.5, 0), "weapon_1": Vector3(2, 0.5, 0.5),
		"weapon_2": Vector3(2, 0.5, -0.5)})
	_write_glb(weapon_path, Vector3(1, 0.2, 0.2), {})
	var data := GameData.new()
	data.load_dir()
	var build: Variant = Loot.random_build(data, Rng.new(5), 1)
	# この機体のフレームと武器だけモデルを持たせ、スキルはモデルなし（箱に戻る）にする
	var fdef: GameData.PartDef = data.get_part(build.frame.def_id)
	fdef.model = frame_path
	for wp: Variant in build.weapons:
		data.get_part(wp.def_id).model = weapon_path
	for sp: Variant in build.skills:
		data.get_part(sp.def_id).model = DIR + "/missing.glb"
	var radius: float = 0.9
	var view: Node3D = RobotView.new()
	view.setup(data, build, radius, Color(0.4, 0.5, 0.7), Color(0.3, 0.7, 1.0))
	check(view.used_models["frame"], "フレームはモデルで描く")
	check_eq(view.used_models["weapons"].size(), build.weapons.size(), "武器の数だけ描く")
	check(not view.used_models["weapons"].has(false), "武器はモデルで描く")
	check(not view.used_models["skills"].has(true), "モデルがないスキルは箱で描く")
	# フレームは当たり判定の大きさにそろう（前後の長さ = 直径）
	var holder: Node3D = view.body.get_child(0)
	var fitted: AABB = holder.transform * PartModels.bounds(holder.get_child(0))
	check(is_equal_approx(fitted.size.x, radius * 2.0 * Look.MODEL_FRAME_FOOTPRINT), "フレームの長さが機体の大きさにそろう（%.2f）" % fitted.size.x)
	check(is_equal_approx(fitted.position.y, 0.0), "フレームの底が床にある")
	var mat: Material = _first_surface_material(holder)
	check(mat is BaseMaterial3D, "フレームに材質がある")
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		# 材質の値は32ビットの小数で持つので、少しの誤差を許す
		check(bm.roughness >= Look.MODEL_ROUGHNESS_MIN - 0.001, "つるつるの材質はつやを抑える（%.2f）" % bm.roughness)
		check(bm.metallic <= Look.MODEL_METALLIC_MAX + 0.001, "金属らしさを抑える（%.2f）" % bm.metallic)
		check_eq(bm.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS, "テクスチャをぼかさない")
	view.free()
	_cleanup()
