# 火炎放射器のテスト。前の近い相手に炎を浴びせ続け（ダメージは少なめ）、燃料が切れると待って満タンに戻る。
# 当たっている間ときどき火傷にし、火傷は重ならずに時間が戻り、続けてダメージを与える。バリア中は火傷にならず、
# 回復パックで火傷は治る。見た目：撃つと炎と音、火傷の機体は燃えている。
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


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


## 0番は火炎放射器だけ、1番は武器もスキルもない。1番は0番の正面 dist m に置く。回復パックは置かない
func _sim(data: GameData, dist: float, shield_for_enemy: bool = false) -> BattleSim:
	var rng := Rng.new(13)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		b.weapons.clear()
		b.skills.clear()
		if i == 0:
			b.weapons.append(Loot.roll_part(data.get_part("weapon_flamethrower"), setup, 50))
		elif shield_for_enemy:
			b.skills.append(Loot.roll_part(data.get_part("skill_shield"), setup, 150))
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	var sim := BattleSim.new(data, builds, brains, ["", ""], ["A", "B"], rng.fork("battle"))
	sim.packs.clear()
	sim.robots[0].x = -4.0
	sim.robots[0].z = 2.0
	sim.robots[0].th = 0.0
	sim.robots[1].x = -4.0 + dist
	sim.robots[1].z = 2.0
	return sim


func _hold(sim: BattleSim) -> void:
	for r: Robot in sim.robots:
		r.intent = "hold"
		r.vx = 0.0
		r.vz = 0.0
	sim.robots[0].th = 0.0
	sim.robots[1].x = sim.robots[1].x  # 動かさない


func _run(sim: BattleSim, seconds: float, stay: Vector2 = Vector2.INF) -> void:
	for k: int in int(seconds * 60.0):
		_hold(sim)
		if stay != Vector2.INF:
			sim.robots[1].x = stay.x
			sim.robots[1].z = stay.y
		sim.step()


func _count(sim: BattleSim, type: String) -> int:
	var n: int = 0
	for e: Dictionary in sim.log:
		if e["type"] == type:
			n += 1
	return n


func test_part_is_valid_and_weak_per_hit() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_flamethrower")
	check(def != null, "火炎放射器のパーツがある")
	if def == null:
		return
	check_eq(def.behavior, "flame", "動き方は flame")
	var dps: float = def.stats["damage"].max_value * float(data.rule("battle.hit.damage_scale"))
	check(dps <= 6.0, "ダメージは少なめ（1秒あたり最大 %.1f）" % dps)
	check(def.get_fixed("burn_chance") > 0.0 and def.get_fixed("burn_sec") > 0.0 and def.get_fixed("burn_dps") > 0.0,
		"火傷の確率・時間・ダメージがある")


func test_flame_hits_near_enemy_continuously_but_not_far() -> void:
	var data := _data()
	var near := _sim(data, 4.0)
	var hp0: float = near.robots[1].hp
	_run(near, 1.0, Vector2(0.0, 2.0))
	check(near.robots[0].flame_on, "近くの相手には炎を浴びせ続ける")
	var lost: float = hp0 - near.robots[1].hp
	check(lost > 1.0 and lost < 15.0, "1秒で少しずつダメージ（%.1f）" % lost)
	check(_count(near, "flame") == 1, "浴びせ始めの出来事は1回")
	var far := _sim(data, 12.0)
	var hp1: float = far.robots[1].hp
	_run(far, 1.0, Vector2(8.0, 2.0))
	check(not far.robots[0].flame_on and is_equal_approx(far.robots[1].hp, hp1), "遠い相手には届かない")


func test_fuel_runs_out_and_refills() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_flamethrower")
	var sim := _sim(data, 4.0)
	var stay := Vector2(0.0, 2.0)
	_run(sim, def.get_fixed("fuel_sec") + 0.2, stay)
	check(not sim.robots[0].flame_on, "燃料が切れると炎が止まる")
	_run(sim, def.get_fixed("cooldown_sec") * 0.5, stay)
	check(not sim.robots[0].flame_on, "少しのあいだは撃てない")
	_run(sim, def.get_fixed("cooldown_sec") * 0.6, stay)
	check(sim.robots[0].flame_on, "待つと燃料が戻ってまた撃てる")


func test_burn_refreshes_without_stacking_and_keeps_burning() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_flamethrower")
	def.fixed["burn_chance"] = 1000.0  # 必ず火傷にする（確率の部分を除いて確かめる）
	var sim := _sim(data, 4.0)
	var b: Robot = sim.robots[1]
	_run(sim, 0.2, Vector2(0.0, 2.0))
	check(b.burn_t > 0.0, "炎に当たると火傷になる")
	check(_count(sim, "burn") == 1, "火傷になった出来事は1回")
	_run(sim, 0.5, Vector2(0.0, 2.0))
	check(is_equal_approx(b.burn_t, def.get_fixed("burn_sec")) or b.burn_t > def.get_fixed("burn_sec") - 0.05,
		"火傷中にまたかかると時間が戻る（%.2f 秒）" % b.burn_t)
	check(is_equal_approx(b.burn_dps, def.get_fixed("burn_dps")), "火傷は重ならない（1秒あたりのダメージは同じ）")
	check(_count(sim, "burn") == 1, "重ねがけで出来事は増えない")
	# 炎の届かない所へ逃げても、火傷のダメージは続く
	b.x = 10.0
	var hp0: float = b.hp
	_run(sim, 1.0, Vector2(10.0, 2.0))
	var lost: float = hp0 - b.hp
	var expect: float = def.get_fixed("burn_dps") * float(data.rule("battle.hit.damage_scale"))
	check(absf(lost - expect) < 0.5, "離れても火傷で1秒あたり %.1f のダメージ（%.2f）" % [expect, lost])
	_run(sim, def.get_fixed("burn_sec"), Vector2(10.0, 2.0))
	check(b.burn_t == 0.0, "時間がたつと火が消える")
	check(_count(sim, "burn_end") >= 1, "火が消えた出来事が残る")


func test_rolls_are_random_but_deterministic() -> void:
	var data := _data()
	var results: Array = []
	for k: int in 2:
		var sim := _sim(data, 4.0)
		_run(sim, 3.0, Vector2(0.0, 2.0))
		results.append([sim.robots[1].burn_t, sim.robots[1].hp, _count(sim, "burn")])
	check_eq(results[0], results[1], "同じ種なら火傷のかかり方も同じ")


func test_shield_blocks_burn_and_health_pack_cures_it() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_flamethrower")
	def.fixed["burn_chance"] = 1000.0
	var sim := _sim(data, 4.0, true)
	var b: Robot = sim.robots[1]
	b.skills[0].active_t = 5.0  # バリアを張っている
	_run(sim, 0.5, Vector2(0.0, 2.0))
	check(b.burn_t == 0.0, "バリア中は火傷にならない")
	# 火傷した機体が回復パックを取ると治る
	var sim2 := _sim(data, 4.0)
	var c: Robot = sim2.robots[1]
	_run(sim2, 0.2, Vector2(0.0, 2.0))
	check(c.burn_t > 0.0, "火傷している")
	sim2.packs.append({"id": 99, "x": 10.0, "z": 2.0, "big": false, "heal": 50.0, "active": true, "t": 0.0})
	c.x = 10.0
	_run(sim2, DT, Vector2(10.0, 2.0))
	check(c.burn_t == 0.0, "回復パックを取ると火傷が治る")


func test_flame_and_burning_views() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_flamethrower")
	def.fixed["burn_chance"] = 1000.0
	var sim := _sim(data, 4.0)
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	var fv: Node3D = arena.robot_views[0].flame_view
	check(fv != null, "火炎放射器を持つ機体には炎の見た目がある")
	check(arena.robot_views[1].flame_view == null, "持たない機体にはない")
	if fv == null:
		arena.free()
		return
	var saw_roar: bool = false
	for k: int in 30:
		_hold(sim)
		sim.robots[1].x = 0.0
		sim.step()
		arena.sync(DT)
		saw_roar = saw_roar or fv.roar_player.playing
	check(fv.firing, "撃っている間は炎が出る")
	check(saw_roar, "撃っている間は轟音が鳴る")
	check(arena.robot_views[1].burn_fx.burning, "火傷した機体は燃えている")
	check(not arena.robot_views[0].burn_fx.burning, "火傷していない機体は燃えていない")
	arena.free()
