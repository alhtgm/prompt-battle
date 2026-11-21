# 穴に落ちたときの光の柱と、敵味方どちらにもスキルの見た目が出ることのテスト。画面には描かない（ノードの状態だけを見る）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const MatchSession := preload("res://core/match_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Look := preload("res://view/look.gd")
const RobotView := preload("res://view/arena/robot_view.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")

const DT: float = 1.0 / 60.0


class FakeSkill:
	var def: Variant
	var active_t: float = 0.0


class FakeRobot:
	var x: float = 3.0
	var z: float = -2.0
	var th: float = 0.0
	var stun: float = 0.0
	var fell: bool = false
	var hp: float = 100.0
	var name: String = "テスト"
	var say: String = ""
	var skills: Array = []


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _make_view(data: GameData, skills: Array) -> Node3D:
	var b := Build.new()
	var uid: int = 1
	var specs: Array = [["frame_spider", "frame"], ["weapon_drill", "weapon"]]
	for sk: String in skills:
		specs.append([sk, "skill"])
	for spec: Array in specs:
		var p := PartInstance.new()
		p.def_id = spec[0]
		p.kind = spec[1]
		p.uid = uid
		uid += 1
		match spec[1]:
			"frame": b.frame = p
			"weapon": b.weapons.append(p)
			_: b.skills.append(p)
	var v: Node3D = RobotView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.setup(data, b, 0.9, Color(0.7, 0.45, 0.26), Color(1.0, 0.55, 0.15))
	return v


func test_fall_into_pit_erupts_pillar_of_light() -> void:
	var data := GameData.new()
	data.load_dir()
	var v: Node3D = _make_view(data, [])
	var r := FakeRobot.new()
	v.sync(r, DT)
	check(v.fall_burst == null, "落ちる前は光の柱を出さない")
	r.fell = true
	v.sync(r, DT)
	check(v.fall_burst != null, "穴に落ちると演出が始まる")
	if v.fall_burst == null:
		v.queue_free()
		return
	var fb: Node3D = v.fall_burst
	check(fb.global_position.is_equal_approx(Vector3(3.0, 0.0, -2.0)), "演出は落ちた場所の床に置く（%s）" % fb.global_position)
	check(not fb.erupted, "落ちた直後（沈んでいる間）はまだ吹き上がらない")
	for k: int in ceili((Look.FALL_BURST_DELAY + 0.1) / DT):
		v.sync(r, DT)
	check(fb.erupted, "少し沈んだあとに光が吹き上がる")
	check(fb.global_position.is_equal_approx(Vector3(3.0, 0.0, -2.0)), "機体が沈んで縮んでも、演出は床に残る")
	check(fb.global_basis.get_scale().is_equal_approx(Vector3.ONE), "機体が縮んでも、演出は縮まない")
	check(v.fall_burst == fb, "演出は一度だけ")
	check(v.explosion == null, "穴に落ちたときは爆発しない")
	v.queue_free()
	await _frame()


func test_skill_effects_follow_the_skill() -> void:
	var data := GameData.new()
	data.load_dir()
	var v: Node3D = _make_view(data, ["skill_booster", "skill_overclock"])
	var r := FakeRobot.new()
	var booster := FakeSkill.new()
	booster.def = data.get_part("skill_booster")
	var oc := FakeSkill.new()
	oc.def = data.get_part("skill_overclock")
	r.skills = [booster, oc]
	v.sync(r, DT)
	check(not v.skill_fx.booster_on and not v.skill_fx.overclock_on, "スキルが効いていなければ何も出さない")
	booster.active_t = 1.0
	v.sync(r, DT)
	check(v.skill_fx.booster_on and not v.skill_fx.overclock_on, "ブースターだけが効けば噴射炎だけ")
	oc.active_t = 1.0
	booster.active_t = 0.0
	v.sync(r, DT)
	check(not v.skill_fx.booster_on and v.skill_fx.overclock_on, "オーバークロックだけが効けば赤い火花だけ")
	v.queue_free()
	await _frame()


## 実際の試合で、敵（機体2）がシールドを使ったときもバリアが出る
func test_enemy_shield_shows_barrier_in_real_battles() -> void:
	var data := GameData.new()
	data.load_dir()
	var checked: Array = [false, false]
	for seed_value: int in range(1, 12):
		if checked[0] and checked[1]:
			break
		var setup: Array = []
		for i: int in 6:
			setup.append({"name": "P%d" % i, "is_human": false})
		var s := MatchSession.new(data, seed_value, setup, DefaultAgents.new(false))
		s.finish_draft()
		s.finish_build()
		for bt: Variant in s.battles:
			var sim: Variant = bt.sim
			var arena: Node3D = ArenaView.new()
			(Engine.get_main_loop() as SceneTree).root.add_child(arena)
			arena.setup(data)
			arena.bind(sim)
			while not sim.over:
				sim.step()
				arena.sync(DT)
				for i: int in 2:
					for sk: Variant in sim.robots[i].skills:
						if sk.def.behavior == "shield" and sk.active_t > 0.0 and not sim.robots[i].fell:
							if not checked[i]:
								checked[i] = true
								check(arena.robot_views[i].shield.state != 0, "機体 %d のシールドにバリアが出る" % (i + 1))
			arena.free()
	check(checked[1], "敵（機体2）がシールドを使う試合を確かめた")
