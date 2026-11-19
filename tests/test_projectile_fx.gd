# 撃つ武器の弾の見た目のテスト。ロケットは炎と煙の尾つきの弾体で飛び、当たると爆発する。機関銃は光の筋で飛ぶ。
# 弾が消えたら見た目も消え、着弾の演出が出る。画面には描かない（ノードの状態だけを見る）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")

const DT: float = 1.0 / 60.0


## 0番は weapon_id だけを持ち、1番の正面 8m に置く。どちらも動かない
func _setup(data: GameData, weapon_id: String) -> BattleSim:
	var rng := Rng.new(9)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		b.weapons.clear()
		b.skills.clear()
		if i == 0:
			b.weapons.append(Loot.roll_part(data.get_part(weapon_id), setup, 50))
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	var sim := BattleSim.new(data, builds, brains, ["", ""], ["A", "B"], rng.fork("battle"))
	sim.robots[0].x = -6.0
	sim.robots[0].z = 2.0
	sim.robots[0].th = 0.0
	sim.robots[1].x = 2.0
	sim.robots[1].z = 2.0
	return sim


func _hold(sim: BattleSim) -> void:
	for r: Robot in sim.robots:
		r.intent = "hold"
		r.vx = 0.0
		r.vz = 0.0
	sim.robots[0].th = 0.0


func _arena(data: GameData, sim: BattleSim) -> Node3D:
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	return arena


func test_rocket_flies_with_flame_and_smoke_then_explodes() -> void:
	var data := GameData.new()
	data.load_dir()
	var sim := _setup(data, "weapon_rocket")
	var arena: Node3D = _arena(data, sim)
	var fx: Node3D = arena.projectiles
	var saw_rocket: bool = false
	var flame_ok: bool = false
	var trail_ok: bool = false
	for k: int in 120:
		_hold(sim)
		sim.step()
		arena.sync(DT)
		for id: Variant in fx.live:
			var e: Dictionary = fx.live[id]
			if e["style"] == "rocket":
				saw_rocket = true
				var n: Node3D = e["node"]
				flame_ok = flame_ok or (n.has_node("FlameOuter") and n.has_node("FlameInner"))
				trail_ok = trail_ok or (e["trail"] != null and (e["trail"] as CPUParticles3D).emitting)
		if fx.impacts > 0:
			break
	check(fx.launches > 0, "ロケットを撃つと発射の演出が出る")
	check(saw_rocket, "ロケットの弾体が飛ぶ（黄色い箱ではない）")
	check(flame_ok, "後ろから炎を噴く")
	check(trail_ok, "煙の尾を引く")
	check(fx.impacts > 0, "当たると爆発する")
	var hits: int = 0
	for e: Dictionary in sim.log:
		if e["type"] == "hit":
			hits += 1
	check(hits > 0, "ロケットは相手に当たった")
	arena.free()


func test_machine_gun_fires_tracers_and_cleans_up() -> void:
	var data := GameData.new()
	data.load_dir()
	var sim := _setup(data, "weapon_mg")
	var arena: Node3D = _arena(data, sim)
	var fx: Node3D = arena.projectiles
	var saw_tracer: bool = false
	for k: int in 90:
		_hold(sim)
		sim.step()
		arena.sync(DT)
		for id: Variant in fx.live:
			if fx.live[id]["style"] == "tracer":
				saw_tracer = true
	check(saw_tracer, "機関銃の弾は光の筋で飛ぶ")
	check(fx.impacts > 0, "当たったり射程を過ぎた弾には着弾の演出が出る")
	check_eq(fx.live.size(), sim.shots.size(), "飛んでいる弾と見た目の数が合う")
	var live_ids: Array = fx.live.keys()
	for s: Variant in sim.shots:
		check(live_ids.has(s.id), "弾 %d の見た目がある" % s.id)
	arena.free()
