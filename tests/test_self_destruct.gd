# 自爆装置のテスト。HPが0になると導火線に火がつき、速く突っ込み、ダメージを受けず、時間がたつと自爆する。
# 自爆で相手を壊せば引き分け、届かなければ負け。自爆で壊された相手の自爆装置は動かない。同じ種なら同じ結果になる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const MockBrain := preload("res://agent/mock_brain.gd")


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


## 2機の試合を作る。with_bomb[i] が true なら、その機体のスキルを自爆装置1つにする
func _sim(data: GameData, seed_value: int, with_bomb: Array) -> BattleSim:
	var rng := Rng.new(seed_value)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		b.skills.clear()
		if with_bomb[i]:
			b.skills.append(Loot.roll_part(data.get_part("skill_self_destruct"), setup, 50 + i * 100))
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	return BattleSim.new(data, builds, brains, ["とにかく突撃して殴れ", "とにかく突撃して殴れ"], ["A", "B"], rng.fork("battle"))


## 2機を近くに置く（自爆が届く距離）
func _place_close(sim: BattleSim) -> void:
	sim.robots[0].x = -1.5
	sim.robots[0].z = 0.0
	sim.robots[1].x = 1.5
	sim.robots[1].z = 0.0


## 自爆そのものだけで相手を壊すかを見るため、自爆する機体（0番）の武器を外し、
## 相手のHPを、体当たりでは壊れず自爆の一撃なら壊れる量にする
func _only_blast_can_kill(sim: BattleSim) -> void:
	sim.robots[0].weapons.clear()
	var def: GameData.PartDef = sim.data.get_part("skill_self_destruct")
	var blast: float = sim.robots[0].skills[0].inst.get_stat("blast_damage") * float(sim.data.rule("battle.hit.damage_scale"))
	sim.robots[1].hp = blast * 0.8
	check(def != null and blast > 10.0, "自爆のダメージ（%.0f）" % blast)


func _run(sim: BattleSim, max_seconds: float) -> void:
	for k: int in int(max_seconds * 60.0):
		if sim.over:
			return
		sim.step()


func test_part_is_valid_and_passive() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("skill_self_destruct")
	check(def != null, "自爆装置のパーツがある")
	if def == null:
		return
	check_eq(def.behavior, "self_destruct", "動き方は self_destruct")
	check(def.get_fixed("fuse_sec") > 0.0, "自爆までの時間がある")
	check(def.get_fixed("speed_mult") > 1.0, "突撃は速くなる")
	var sim := _sim(data, 1, [true, false])
	sim.robots[0].want_skill = 0
	sim.step()
	check(sim.robots[0].fuse < 0.0, "操縦士が選んでも、HPが残っている間は動かない")
	check_eq(sim.robots[0].skills[0].charges_left, int(def.get_fixed("charges")), "選んでも使用回数は減らない")


func test_fuse_starts_at_zero_hp_and_makes_it_fast_and_invulnerable() -> void:
	var data := _data()
	var sim := _sim(data, 2, [true, false])
	_place_close(sim)
	var r: Variant = sim.robots[0]
	r.hp = 1.0
	sim._damage(0, 100.0, 5.0, 0.0, "テスト", 1, true)
	check_eq(r.hp, 0.0, "HPは0")
	check(r.fuse > 0.0, "HPが0になると導火線に火がつく")
	check(not r.is_down(), "導火線が燃えている間は倒れていない")
	check_eq(r.intent, "charge", "相手へ突っ込む")
	sim.step()
	check(not sim.over, "導火線が燃えている間は決着しない")
	check_eq(sim._damage(0, 50.0, 5.0, 0.0, "テスト", 1, true), 0.0, "導火線が燃えている間はダメージを受けない")
	# 速さ：導火線の倍率がかかる（同じ条件で比べる）
	var fast := _sim(data, 3, [true, false])
	var slow := _sim(data, 3, [true, false])
	for s: BattleSim in [fast, slow]:
		s.robots[0].x = -10.0
		s.robots[1].x = 10.0
		s.robots[0].th = 0.0
		s.robots[0].intent = "charge"
	fast.robots[0].hp = 0.0
	fast.robots[0].fuse = 5.0
	for k: int in 30:
		fast.step()
		slow.step()
	check(fast.robots[0].x - (-10.0) > (slow.robots[0].x - (-10.0)) * 1.2,
		"導火線が燃えている機体は速く走る（%.1f m と %.1f m）" % [fast.robots[0].x + 10.0, slow.robots[0].x + 10.0])


func test_blast_that_destroys_enemy_is_a_draw() -> void:
	var data := _data()
	var sim := _sim(data, 4, [true, false])
	_place_close(sim)
	_only_blast_can_kill(sim)
	sim.robots[0].hp = 1.0
	sim._damage(0, 100.0, 5.0, 0.0, "テスト", 1, true)
	sim.robots[1].stun = 10.0  # 相手は逃げない
	_run(sim, 10.0)
	check(sim.over, "決着する")
	check(sim.robots[0].self_destructed, "自爆した")
	check_eq(int(sim.result["winner"]), -1, "自爆で相手を壊したら引き分け")
	check_eq(str(sim.result["reason"]), BattleSim.REASON_SELF_DESTRUCT, "決着のつき方は自爆で相打ち")
	var seen: bool = false
	for e: Dictionary in sim.log:
		if e["type"] == "self_destruct":
			seen = true
			check(e["hit"], "自爆は相手に当たった")
	check(seen, "自爆の出来事が実況に残る")


func test_blast_that_misses_is_a_loss() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("skill_self_destruct")
	def.fixed["fuse_sec"] = 0.05  # すぐに自爆させ、遠くの相手には届かないようにする
	var sim := _sim(data, 5, [true, false])
	sim.robots[0].x = -12.0
	sim.robots[1].x = 12.0
	sim.robots[0].hp = 1.0
	var enemy_hp: float = sim.robots[1].hp
	sim._damage(0, 100.0, -20.0, 0.0, "テスト", 1, true)
	_run(sim, 3.0)
	check(sim.over, "決着する")
	check_eq(int(sim.result["winner"]), 1, "自爆が届かなければ自爆した側の負け")
	check_eq(str(sim.result["reason"]), BattleSim.REASON_DESTROYED, "決着のつき方は破壊")
	check(is_equal_approx(sim.robots[1].hp, enemy_hp), "届かなければ相手は無傷")


func test_enemy_destroyed_by_blast_does_not_arm_its_own_bomb() -> void:
	var data := _data()
	var sim := _sim(data, 6, [true, true])
	_place_close(sim)
	_only_blast_can_kill(sim)
	sim.robots[1].stun = 10.0
	sim.robots[0].hp = 1.0
	sim._damage(0, 100.0, 5.0, 0.0, "テスト", 1, true)
	_run(sim, 10.0)
	check(sim.over, "決着する")
	check(sim.robots[1].fuse < 0.0 and not sim.robots[1].self_destructed, "自爆で壊された相手の自爆装置は動かない")
	check_eq(int(sim.result["winner"]), -1, "引き分け")


func test_same_seed_same_result_with_bombs() -> void:
	var data := _data()
	var results: Array = []
	for k: int in 2:
		var sim := _sim(data, 77, [true, true])
		_run(sim, 120.0)
		results.append([sim.result.get("winner"), sim.result.get("reason"), sim.tick])
	check_eq(results[0], results[1], "自爆装置があっても同じ種なら同じ結果")
