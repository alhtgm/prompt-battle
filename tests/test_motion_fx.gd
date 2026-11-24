# 機体の身ぶり（view/arena/motion_fx_view.gd）のテスト。加速で先が上がり、ブレーキで前へのめり、曲がると外へ傾き、
# 速いと土ぼこりが出て、傷むと煙が出て、ライトは動ける間だけ点く。数値が壊れない（NaN にならない）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")
const Look := preload("res://view/look.gd")

const DT: float = 1.0 / 60.0


func _make(frame_id: String = "") -> Array:
	var data := GameData.new()
	data.load_dir()
	var rng := Rng.new(5)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		if not frame_id.is_empty():
			b.frame = Loot.roll_part(data.get_part(frame_id), setup, 7 + i)
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	var sim := BattleSim.new(data, builds, brains, ["", ""], ["A", "B"], rng.fork("battle"))
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	return [arena, sim]


func _frames(arena: Node3D, n: int) -> void:
	for k: int in n:
		arena.sync(DT)


func test_lean_dust_and_lights() -> void:
	var parts: Array = _make()
	var arena: Node3D = parts[0]
	var sim: BattleSim = parts[1]
	var r: Variant = sim.robots[0]
	var mv: Node3D = arena.robot_views[0].motion
	r.th = 0.0
	r.vx = 0.0
	r.vz = 0.0
	_frames(arena, 10)
	check(absf(mv.pitch) < 0.01, "止まっていれば傾かない")
	check(not mv.dusting, "止まっていれば土ぼこりは出ない")
	check(mv.lamp_light.light_energy > 0.0, "動ける間はライトが点いている")
	# 急に走り出す：先が上がる
	for k: int in 6:
		r.vx = float(k + 1) * 1.2
		arena.sync(DT)
	check(mv.pitch > 0.02, "加速すると先が上がる（%.3f）" % mv.pitch)
	check(mv.dusting, "速く走ると土ぼこりが出る")
	check(absf(arena.robot_views[0].body.rotation.z - mv.pitch) < 0.0001, "傾きが車体にかかる")
	# 急ブレーキ：前へのめる
	for k: int in 6:
		r.vx = maxf(0.0, 7.2 - float(k + 1) * 1.2)
		arena.sync(DT)
	check(mv.pitch < -0.02, "ブレーキで前へのめる（%.3f）" % mv.pitch)
	# 走りながら曲がる（th が増える向き）：外へ傾く
	r.vx = 6.0
	for k: int in 20:
		r.th += 0.04
		r.vx = 6.0 * cos(r.th)
		r.vz = 6.0 * sin(r.th)
		arena.sync(DT)
	check(mv.roll < -0.02, "曲がると外へ傾く（%.3f）" % mv.roll)
	check(is_finite(mv.pitch) and is_finite(mv.roll) and is_finite(mv.bob), "傾きと揺れが壊れない")
	# 傷む：半分を切ると灰色の煙、4分の1を切ると黒煙
	r.hp = r.max_hp * 0.4
	_frames(arena, 2)
	check_eq(mv.smoking, 1, "HPが半分を切ると灰色の煙")
	r.hp = r.max_hp * 0.1
	_frames(arena, 2)
	check_eq(mv.smoking, 2, "HPが4分の1を切ると黒煙")
	# 穴に落ちたらライトは消え、煙も止まる
	r.fell = true
	_frames(arena, 2)
	check_eq(mv.lamp_light.light_energy, 0.0, "落ちたらライトは消える")
	check_eq(mv.smoking, 0, "落ちたら煙は止まる")
	arena.free()


func test_every_frame_has_motion() -> void:
	for f: String in ["frame_light", "frame_standard", "frame_heavy", "frame_wedge", "frame_tank", "frame_spider"]:
		var parts: Array = _make(f)
		var arena: Node3D = parts[0]
		var sim: BattleSim = parts[1]
		var rv: Node3D = arena.robot_views[0]
		check(rv.motion != null, "%s：身ぶりがある" % f)
		sim.robots[0].vx = 5.0
		_frames(arena, 30)
		check(is_finite(rv.body.rotation.z) and is_finite(rv.body.position.y), "%s：傾きが壊れない" % f)
		# 車輪のあるフレームは車輪が回り、脚のあるフレームは脚が振れる（モデルの wheel_* / leg_* の節）
		var mv: Node3D = rv.motion
		if f in ["frame_light", "frame_standard", "frame_wedge", "frame_tank"]:
			check(not mv.wheels.is_empty(), "%s：車輪の節がある" % f)
			if not mv.wheels.is_empty():
				check(not mv.wheels[0].basis.is_equal_approx(mv._wheel_base[0]), "%s：走ると車輪が回る" % f)
		if f in ["frame_spider"]:
			check(not mv.legs.is_empty(), "%s：脚の節がある" % f)
			if not mv.legs.is_empty():
				check(not mv.legs[0].basis.is_equal_approx(mv._leg_base[0]), "%s：歩くと脚が振れる" % f)
		arena.free()
