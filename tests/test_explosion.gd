# 機体が壊されたときの爆発のテスト。部品がばらばらに飛び、床より下に沈まず、やがて落ち着くこと、穴に落ちたときは爆発しないことを確かめる。
# 画面には描かない（ノードの状態だけを見る）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const RobotView := preload("res://view/arena/robot_view.gd")

const DT: float = 1.0 / 60.0


class FakeRobot:
	var x: float = 0.0
	var z: float = 0.0
	var th: float = 0.0
	var stun: float = 0.0
	var fell: bool = false
	var hp: float = 100.0
	var fuse: float = -1.0
	var fuse_total: float = 0.0
	var self_destructed: bool = false
	var name: String = "テスト"
	var say: String = ""
	var skills: Array = []


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _make_view(data: GameData) -> Node3D:
	var b := Build.new()
	var uid: int = 1
	for spec: Array in [["frame_tank", "frame"], ["weapon_rocket", "weapon"], ["weapon_spike", "weapon"]]:
		var p := PartInstance.new()
		p.def_id = spec[0]
		p.kind = spec[1]
		p.uid = uid
		uid += 1
		if spec[1] == "frame":
			b.frame = p
		else:
			b.weapons.append(p)
	var v: Node3D = RobotView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.setup(data, b, 0.9, Color(0.4, 0.5, 0.7), Color(0.3, 0.7, 1.0))
	return v


func test_destroyed_robot_explodes_into_pieces() -> void:
	var data := GameData.new()
	data.load_dir()
	var v: Node3D = _make_view(data)
	var r := FakeRobot.new()
	v.sync(r, DT)
	check(v.explosion == null, "HPが残っている間は爆発しない")
	r.hp = 0.0
	v.sync(r, DT)
	check(v.explosion != null, "HPが尽きると爆発する")
	if v.explosion == null:
		v.queue_free()
		return
	var pieces: Array = v.explosion.pieces
	check(pieces.size() >= 3, "機体が部品にばらける（%d 個）" % pieces.size())
	check(not v.body.visible, "元の機体は消える")
	var start: Array = []
	for p: Array in pieces:
		start.append((p[0] as Node3D).global_position)
	for k: int in 30:
		v.sync(r, DT)
	var moved: int = 0
	var rose: int = 0
	for i: int in pieces.size():
		var pos: Vector3 = (pieces[i][0] as Node3D).global_position
		if pos.distance_to(start[i]) > 0.3:
			moved += 1
		if pos.y > (start[i] as Vector3).y:
			rose += 1
	check(moved == pieces.size(), "すべての部品が飛び散る（%d / %d）" % [moved, pieces.size()])
	check(rose > 0, "上へ跳ね上がる部品がある")
	for k: int in 60 * 6:
		v.sync(r, DT)
	var resting: int = 0
	for p: Array in pieces:
		var n: Node3D = p[0]
		check(n.global_position.y >= float(p[3]) - 0.001, "部品は床より下に沈まない")
		if (p[1] as Vector3).length() < 0.5:
			resting += 1
	check(resting == pieces.size(), "しばらくすると部品は床に落ち着く（%d / %d）" % [resting, pieces.size()])
	var again: Node3D = v.explosion
	v.sync(r, DT)
	check(v.explosion == again, "爆発は一度だけ")
	v.queue_free()
	await _frame()


func test_robot_that_fell_does_not_explode() -> void:
	var data := GameData.new()
	data.load_dir()
	var v: Node3D = _make_view(data)
	var r := FakeRobot.new()
	r.fell = true
	r.hp = 0.0
	v.sync(r, DT)
	check(v.explosion == null, "穴に落ちた機体は爆発しない")
	v.queue_free()
	await _frame()


## 自爆装置：導火線が燃えている間は赤く点滅し、だんだん速くなり、自爆すると大きく爆発する
func test_fuse_blinks_faster_then_big_explosion() -> void:
	var data := GameData.new()
	data.load_dir()
	var v: Node3D = _make_view(data)
	var r := FakeRobot.new()
	r.hp = 0.0
	r.fuse_total = 3.0
	var toggles: Array = [0, 0]  # [最初の1秒, 最後の1秒]
	var last: bool = false
	var t: float = 0.0
	while t < 3.0:
		r.fuse = 3.0 - t
		v.sync(r, DT)
		check(v.explosion == null or t < 0.0, "導火線が燃えている間は爆発しない")
		if v.blink_on != last:
			if t < 1.0:
				toggles[0] += 1
			elif t >= 2.0:
				toggles[1] += 1
		last = v.blink_on
		t += DT
	check(v.blink_mat != null, "導火線が燃えている間は赤い重ね塗りがかかる")
	check(toggles[1] > toggles[0] * 2, "自爆が近いほど点滅が速い（最初の1秒 %d 回、最後の1秒 %d 回）" % toggles)
	r.fuse = -1.0
	r.self_destructed = true
	v.sync(r, DT)
	check(v.explosion != null, "自爆すると爆発する")
	check(v.blink_mat == null, "爆発したら点滅は止まる")
	check(v.explosion.pieces.size() >= 3, "部品が飛び散る")
	v.queue_free()
	await _frame()
