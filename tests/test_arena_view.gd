# 3Dのアリーナの見た目のテスト。壁の外の松明が立ち、揺れても明るさが壊れないこと、
# どの物にも光が8つを超えて当たらないこと（Compatibility では1つの物を照らせる光は8つまで）を確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")
const Look := preload("res://view/look.gd")

## Compatibility で1つの物を照らせる光の数（プロジェクトの設定 rendering/limits/opengl/max_lights_per_object の既定値）
const MAX_LIGHTS_PER_OBJECT: int = 8


func _arena() -> Node3D:
	var data := GameData.new()
	data.load_dir()
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	return arena


func _collect(node: Node, script_type: String, out: Array) -> void:
	for c: Node in node.get_children():
		if c.is_class(script_type):
			out.append(c)
		_collect(c, script_type, out)


func test_torches_stand_and_flicker_safely() -> void:
	var arena: Node3D = _arena()
	check_eq(arena.torches.size(), Look.TORCH_SPOTS.size(), "松明の数")
	var half: float = float(arena.stage["half_size"])
	for t: Node3D in arena.torches:
		var p: Vector3 = t.global_position
		check(maxf(absf(p.x), absf(p.z)) > half, "松明は壁の外にある（%s）" % str(p))
		check(not t.light.shadow_enabled, "松明の光は影なし（古いPCで重いため）")
	var lo: float = Look.TORCH_ENERGY * (1.0 - Look.TORCH_FLICKER) - 0.001
	var hi: float = Look.TORCH_ENERGY * (1.0 + Look.TORCH_FLICKER) + 0.001
	for k: int in 200:
		var time: float = float(k) * 0.137
		for t: Node3D in arena.torches:
			t.flicker(time)
			var e: float = t.light.light_energy
			check(is_finite(e) and e >= lo and e <= hi, "揺れても明るさが範囲内（%.3f）" % e)
	# 揺れは時間で決まる：同じ時刻なら同じ明るさ
	arena.torches[0].flicker(3.21)
	var a: float = arena.torches[0].light.light_energy
	arena.torches[0].flicker(9.0)
	arena.torches[0].flicker(3.21)
	check_eq(arena.torches[0].light.light_energy, a, "同じ時刻なら同じ明るさ")
	arena.queue_free()


func test_no_object_is_lit_by_more_than_8_lights() -> void:
	var arena: Node3D = _arena()
	var lights: Array = []
	_collect(arena, "Light3D", lights)
	var meshes: Array = []
	_collect(arena, "MeshInstance3D", meshes)
	check(not arena.floor_tiles.is_empty(), "床はタイルに分かれている")
	var worst: int = 0
	for m: MeshInstance3D in meshes:
		var box: AABB = m.global_transform * m.get_aabb()
		var n: int = 0
		for l: Light3D in lights:
			if l is DirectionalLight3D:
				continue  # 平行光は数に入らない
			var r: float = l.omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
			var c: Vector3 = l.global_position
			var nearest: Vector3 = c.clamp(box.position, box.end)
			if nearest.distance_to(c) <= r:
				n += 1
		worst = maxi(worst, n)
		check(n <= MAX_LIGHTS_PER_OBJECT, "%s に当たる光が %d 個（8 個まで）" % [m.get_path(), n])
	print("    [光] 1つの物に当たる光は最大 %d 個" % worst)
	arena.queue_free()
