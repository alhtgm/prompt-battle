# 回復パックのテスト。いつも決まった数が、穴・壁・機体から離れた場所に出ている。ダメージを受けた機体が近づくと取り、
# 大は100・小は50（最大HPまで）回復する。取られると決まった秒数のあとに別の場所へ出る。同じ種なら同じ場所。
# 「回復しに行く」方針は一番近いパックへ向かい、戦況にも一番近いパックが入る。見た目は、出たパックを描き、取られると演出が出る。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const Observation := preload("res://core/observation.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")

const DT: float = 1.0 / 60.0


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


## 武器もスキルもない2機の試合（パックの働きだけを見る）
func _sim(data: GameData, seed_value: int) -> BattleSim:
	var rng := Rng.new(seed_value)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		b.weapons.clear()
		b.skills.clear()
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	return BattleSim.new(data, builds, brains, ["", ""], ["A", "B"], rng.fork("battle"))


func _active(sim: BattleSim) -> Array:
	var out: Array = []
	for p: Dictionary in sim.packs:
		if p["active"]:
			out.append(p)
	return out


func _hold(sim: BattleSim) -> void:
	for r: Robot in sim.robots:
		r.intent = "hold"
		r.vx = 0.0
		r.vz = 0.0


func test_packs_start_on_field_in_safe_places() -> void:
	var data := _data()
	var cfg: Dictionary = data.rules["battle"]["health_packs"]
	var arena: Dictionary = data.first_stage()
	for seed_value: int in range(1, 30):
		var sim := _sim(data, seed_value)
		var act: Array = _active(sim)
		check_eq(act.size(), int(cfg["count"]), "種 %d：最初からパックが %d 個ある" % [seed_value, int(cfg["count"])])
		for p: Dictionary in act:
			var c := Vector2(float(p["x"]), float(p["z"]))
			check(absf(c.x) <= float(arena["half_size"]) and absf(c.y) <= float(arena["half_size"]), "種 %d：パックは場の中" % seed_value)
			for pit: Dictionary in arena["pits"]:
				check(c.distance_to(Vector2(float(pit["x"]), float(pit["z"]))) > float(pit["r"]),
					"種 %d：パックは穴の中に出ない" % seed_value)
			var heal: float = float(cfg["large_heal"] if p["big"] else cfg["small_heal"])
			check_eq(float(p["heal"]), heal, "種 %d：大は %d、小は %d 回復" % [seed_value, int(cfg["large_heal"]), int(cfg["small_heal"])])


func test_same_seed_same_packs() -> void:
	var data := _data()
	var a := _sim(data, 7)
	var b := _sim(data, 7)
	check(same(a.packs, b.packs), "同じ種なら同じ場所に同じ大きさのパック")


func test_large_and_small_both_appear() -> void:
	var data := _data()
	var big: int = 0
	var total: int = 0
	for seed_value: int in range(1, 101):
		for p: Dictionary in _sim(data, seed_value).packs:
			total += 1
			if p["big"]:
				big += 1
	var ratio: float = float(big) / total
	var want: float = float(data.rules["battle"]["health_packs"]["large_chance"])
	check(absf(ratio - want) < 0.1, "大の出る割合はおよそ %d%%（%.0f%%）" % [roundi(want * 100.0), ratio * 100.0])


func test_damaged_robot_picks_up_and_pack_respawns_elsewhere() -> void:
	var data := _data()
	var cfg: Dictionary = data.rules["battle"]["health_packs"]
	var sim := _sim(data, 3)
	var r: Robot = sim.robots[0]
	var p: Dictionary = sim.packs[0]
	var old_id: int = int(p["id"])
	var old_pos := Vector2(float(p["x"]), float(p["z"]))
	var heal: float = float(p["heal"])
	r.hp = maxf(1.0, r.max_hp - heal - 10.0)
	var before: float = r.hp
	r.x = float(p["x"])
	r.z = float(p["z"])
	_hold(sim)
	sim.step()
	check(is_equal_approx(r.hp, before + heal), "ダメージを受けた機体が近づくとパックを取って %d 回復（%.0f → %.0f）" % [int(heal), before, r.hp])
	check(not p["active"], "取られたパックは消える")
	var seen: bool = false
	for e: Dictionary in sim.log:
		if e["type"] == "pack":
			seen = true
	check(seen, "パックを取った出来事が残る")
	# 取ったあと、同じ場所にいてもしばらくは出ない。決まった秒数のあとに別の場所へ出る
	r.x = 12.0
	r.z = 12.0
	var ticks: int = 0
	while not p["active"] and ticks < 60 * 20:
		_hold(sim)
		sim.robots[0].x = 12.0
		sim.robots[0].z = 12.0
		sim.step()
		ticks += 1
	check(absf(ticks * DT - float(cfg["respawn_sec"])) < 0.1, "%d 秒後に出直す（%.2f 秒）" % [int(cfg["respawn_sec"]), ticks * DT])
	check(int(p["id"]) != old_id, "出直したパックは新しいパック")


func test_heal_is_capped_and_full_hp_robot_does_not_pick_up() -> void:
	var data := _data()
	var sim := _sim(data, 4)
	var r: Robot = sim.robots[0]
	var p: Dictionary = sim.packs[0]
	r.x = float(p["x"])
	r.z = float(p["z"])
	_hold(sim)
	sim.step()
	check(p["active"], "HPが満タンの機体はパックを取らない")
	r.hp = r.max_hp - 5.0
	_hold(sim)
	sim.step()
	check(not p["active"], "少しでも減っていれば取る")
	check(is_equal_approx(r.hp, r.max_hp), "回復は最大HPまで")


func test_go_repair_heads_to_nearest_pack_and_observation_reports_it() -> void:
	var data := _data()
	var sim := _sim(data, 5)
	var me: Robot = sim.robots[0]
	var en: Robot = sim.robots[1]
	me.intent = "go_repair"
	var nearest: Dictionary = RobotDriver.nearest_pack(me.x, me.z, sim.packs)
	var c: Dictionary = RobotDriver.drive(me, en, sim.battle_rules(), sim.packs)
	var want: float = atan2(float(nearest["z"]) - me.z, float(nearest["x"]) - me.x)
	check(absf(angle_difference(float(c["heading"]), want)) < 0.6, "「回復しに行く」は一番近いパックへ向かう")
	var obs: Dictionary = Observation.build(me, en, 0.0, 75.0, sim.battle_rules(), sim.packs)
	check(obs["repair"] is Dictionary, "戦況に一番近いパックが入る")
	if obs["repair"] is Dictionary:
		check(is_equal_approx(float(obs["repair"]["heal"]), float(nearest["heal"])), "回復量が分かる")
	for p: Dictionary in sim.packs:
		p["active"] = false
	var obs2: Dictionary = Observation.build(me, en, 0.0, 75.0, sim.battle_rules(), sim.packs)
	check(obs2["repair"] == null, "場にパックがなければ null")


func test_pack_view_draws_and_reacts_to_pickup() -> void:
	var data := _data()
	var sim := _sim(data, 3)
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	arena.sync(DT)
	var pv: Node3D = arena.health_packs
	var drawn: int = 0
	for s: Dictionary in pv.slots:
		if s["node"] != null:
			drawn += 1
	check_eq(drawn, _active(sim).size(), "出ているパックの数だけ描く")
	var r: Robot = sim.robots[0]
	var p: Dictionary = sim.packs[0]
	r.hp = r.max_hp * 0.5
	r.x = float(p["x"])
	r.z = float(p["z"])
	_hold(sim)
	sim.step()
	arena.sync(DT)
	check(pv.pickups > 0, "取られると演出が出る")
	check(pv.slots[0]["node"] == null, "取られたパックは消える")
	arena.free()


func test_first_packs_are_at_fixed_spots() -> void:
	var data := _data()
	var initial: Array = data.first_stage()["packs"]
	check(initial.size() >= 2, "最初の場所が2つ決まっている（右上と左下）")
	for seed_value: int in [1, 2, 3, 50]:
		var sim := _sim(data, seed_value)
		for k: int in mini(initial.size(), sim.packs.size()):
			check(is_equal_approx(float(sim.packs[k]["x"]), float(initial[k]["x"]))
				and is_equal_approx(float(sim.packs[k]["z"]), float(initial[k]["z"])),
				"種 %d：最初のパック %d は決まった場所に出る" % [seed_value, k])
	# 画面の右上（x が正、z が負＝奥）と左下（x が負、z が正＝手前）
	check(float(initial[0]["x"]) > 0.0 and float(initial[0]["z"]) < 0.0, "1つ目は右上")
	check(float(initial[1]["x"]) < 0.0 and float(initial[1]["z"]) > 0.0, "2つ目は左下")


func test_robot_that_heals_glows_green() -> void:
	var data := _data()
	var sim := _sim(data, 3)
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	var r: Robot = sim.robots[0]
	var p: Dictionary = sim.packs[0]
	r.hp = r.max_hp * 0.5
	r.x = float(p["x"])
	r.z = float(p["z"])
	_hold(sim)
	sim.step()
	arena.sync(DT)
	var fx: Node3D = arena.robot_views[0].heal_fx
	check(fx.left > 0.0, "回復した機体に緑の演出が出る")
	check(fx.glowing, "機体全体が緑に光る")
	check(arena.robot_views[1].heal_fx.left == 0.0, "回復していない機体には出ない")
	for k: int in 120:
		arena.sync(DT)
	check(fx.left == 0.0 and not fx.glowing, "少しすると緑の光は消える")
	arena.free()
