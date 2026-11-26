# バトル1試合のテスト。段階2の完成の目安「ランダムな機体同士で数百試合回して、必ず決着し、勝ち方が偏りすぎない」を確かめる。
extends "res://tests/support/test_case.gd"

const H := preload("res://tests/support/battle_helpers.gd")
const Balance := preload("res://tests/support/balance.gd")
const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const AgentBrain := preload("res://agent/agent_brain.gd")

## 偏りを測る試合数
const BALANCE_MATCHES: int = 400


## いつも壊れた答えを返す頭脳（テスト用）
class BrokenBrain extends "res://agent/agent_brain.gd":
	var asked: int = 0
	func request(_obs: Dictionary) -> void:
		asked += 1
	func poll(_now: float) -> Dictionary:
		return {"intent": "dance", "say": "わーい"} if asked > 0 else {}


## すぐに決まった方針を返す頭脳（テスト用）
class FixedBrain extends "res://agent/agent_brain.gd":
	var intent: String
	var pending: bool = false
	func _init(i: String) -> void:
		intent = i
	func request(_obs: Dictionary) -> void:
		pending = true
	func poll(_now: float) -> Dictionary:
		if not pending:
			return {}
		pending = false
		return {"intent": intent, "skill": null, "say": ""}


func _robot_ok(r: Robot, half: float) -> bool:
	for v: float in [r.x, r.z, r.th, r.vx, r.vz, r.hp]:
		if not is_finite(v):
			return false
	return r.hp >= 0.0 and r.hp <= r.max_hp + 1e-6 and absf(r.x) <= half + 1e-6 and absf(r.z) <= half + 1e-6


func test_every_match_finishes_with_sane_numbers() -> void:
	var data := H.load_data()
	for seed_value: int in 40:
		var sim: BattleSim = H.make_match(data, seed_value)
		var half: float = float(sim.stage["half_size"])
		var broken: int = 0
		while not sim.over and sim.tick <= sim.time_limit_ticks + 1:
			sim.step()
			for r: Robot in sim.robots:
				if not _robot_ok(r, half):
					broken += 1
		check(sim.over, "種 %d：制限時間までに決着する" % seed_value)
		check_eq(broken, 0, "種 %d：位置・速度・HPが壊れない（NaN・範囲外）" % seed_value)
		check(sim.tick <= sim.time_limit_ticks, "種 %d：制限時間を超えない" % seed_value)
		var res: Dictionary = sim.result
		check([-1, 0, 1].has(res.get("winner")), "種 %d：勝者が 0/1/-1" % seed_value)
		check([BattleSim.REASON_DESTROYED, BattleSim.REASON_PIT, BattleSim.REASON_TIME,
				BattleSim.REASON_SELF_DESTRUCT].has(res.get("reason")),
			"種 %d：決着のつき方が決まっている" % seed_value)
		var m: float = float(res.get("margin", -1.0))
		check(is_finite(m) and m >= 0.0 and m <= 1.0, "種 %d：差（margin）が 0〜1" % seed_value)


func test_same_seed_gives_same_match() -> void:
	var data := H.load_data()
	for seed_value: int in [3, 77, 2024]:
		var a: BattleSim = H.make_match(data, seed_value)
		var b: BattleSim = H.make_match(H.load_data(), seed_value)
		var mismatch_tick: int = -1
		while not a.over or not b.over:
			a.step()
			b.step()
			if mismatch_tick < 0 and not same(a.snapshot(), b.snapshot()):
				mismatch_tick = a.tick
			if a.tick > a.time_limit_ticks + 1:
				break
		check_eq(mismatch_tick, -1, "種 %d：毎刻みの状態が完全に同じ（違った刻み）" % seed_value)
		check(same(a.result, b.result), "種 %d：結果が同じ" % seed_value)


func test_balance_over_many_matches() -> void:
	# 標準ステージ。ほかのステージは tests/test_stage_balance.gd で確かめる
	var data := H.load_data()
	var stats: Dictionary = Balance.measure(data, data.first_stage(), BALANCE_MATCHES, 10000)
	var lines: PackedStringArray = Balance.summary(stats)
	print("    [偏り] " + lines[0])
	print("    [勝率] " + lines[1])
	var bad: PackedStringArray = Balance.problems(data, stats)
	check(bad.is_empty(), "基準①〜④をすべて満たす：" + " / ".join(bad))


func test_mock_brain_answers_after_delay_in_match_time() -> void:
	var data := H.load_data()
	var sim: BattleSim = H.make_match(data, 5)
	var first_intent_tick: int = -1
	while not sim.over and first_intent_tick < 0:
		sim.step()
		for e: Dictionary in sim.events:
			if e["type"] == "intent" and first_intent_tick < 0:
				first_intent_tick = sim.tick
	var t: float = float(first_intent_tick) / sim.tick_rate
	check(t >= float(data.rule("agent.mock_delay_min_sec")) and t <= float(data.rule("agent.mock_delay_max_sec")) + 0.05,
		"最初の答えは 0.3〜1.5 秒後に届く（実際 %.2f 秒）" % t)


func test_brain_requests_every_interval_and_match_runs_without_answers() -> void:
	# 答えを返さない頭脳（共通の入口そのもの）でも、試合は止まらずに時間切れまで進む
	var data := H.load_data()
	var setup := Rng.new(1)
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 50)]
	var sim := BattleSim.new(data, builds, [AgentBrain.new(), AgentBrain.new()], ["", ""], ["A", "B"], Rng.new(2))
	var res: Dictionary = sim.run_to_end()
	check_eq(res["reason"], BattleSim.REASON_TIME, "誰も動かなければ時間切れ")
	check_eq(res["ticks"], sim.time_limit_ticks, "制限時間ちょうどで終わる")


func test_think_interval_and_broken_answer() -> void:
	var data := H.load_data()
	var setup := Rng.new(1)
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 50)]
	var broken := BrokenBrain.new()
	var sim := BattleSim.new(data, builds, [broken, FixedBrain.new("hold")], ["", ""], ["A", "B"], Rng.new(2))
	var confused: int = 0
	for k: int in sim.tick_rate * 10:  # 10秒
		sim.step()
		for e: Dictionary in sim.events:
			if e["type"] == "confused":
				confused += 1
	check_eq(sim.robots[0].intent, "hold", "壊れた答えでは方針を変えない（最初の hold のまま）")
	check_eq(sim.robots[0].say, BattleSim.CONFUSED_SAY, "壊れた答えには「えっと…」と言う")
	check(confused > 0, "戸惑いのイベントが出る")
	# 2秒おき＋切っ掛けのとき。10秒で5回以上、最低間隔0.5秒なら20回以下
	check(broken.asked >= 5 and broken.asked <= 20, "考える回数が 2 秒おき程度（10秒で %d 回）" % broken.asked)


func test_driver_outputs_are_finite_for_every_intent() -> void:
	var data := H.load_data()
	var b: Dictionary = BattleSim.rules_for(data, data.first_stage())
	var rng := Rng.new(8)
	var bad: int = 0
	for k: int in 300:
		var builds: Array = [Loot.random_build(data, rng, 1), Loot.random_build(data, rng, 50)]
		var me := Robot.new()
		var en := Robot.new()
		var st: Dictionary = data.first_stage()
		me.setup(data, builds[0], 0, "A", st["spawns"][0], b["robot"])
		en.setup(data, builds[1], 1, "B", st["spawns"][1], b["robot"])
		var half: float = float(st["half_size"])
		me.x = rng.randf_range(-half, half)
		me.z = rng.randf_range(-half, half)
		en.x = me.x if k % 10 == 0 else rng.randf_range(-half, half)  # 重なったときも調べる
		en.z = me.z if k % 10 == 0 else rng.randf_range(-half, half)
		me.th = rng.randf_range(-PI, PI)
		en.th = rng.randf_range(-PI, PI)
		for intent: String in RobotDriver.INTENTS:
			me.intent = intent
			var c: Dictionary = RobotDriver.drive(me, en, b)
			var thr: float = c["throttle"]
			if not is_finite(float(c["heading"])) or not is_finite(thr) or thr < 0.0 or thr > 1.0:
				bad += 1
	check_eq(bad, 0, "どの方針でも向きとアクセルが壊れない")


func test_observation_has_expected_shape() -> void:
	var data := H.load_data()
	var sim: BattleSim = H.make_match(data, 11)
	for k: int in 120:
		sim.step()
	var Observation := preload("res://core/observation.gd")
	var obs: Dictionary = Observation.build(sim.robots[0], sim.robots[1], sim.now(), sim.time_left(), sim.battle_rules())
	for key: String in ["t", "me", "enemy", "repair", "events"]:
		check(obs.has(key), "戦況に %s がある" % key)
	for key: String in ["hp", "pos", "facing", "ammo", "stunned", "skills"]:
		check(obs["me"].has(key), "戦況の me に %s がある" % key)
	for key: String in ["hp", "dist", "dir", "near_pit", "behind_me"]:
		check(obs["enemy"].has(key), "戦況の enemy に %s がある" % key)
	check(JSON.stringify(obs).length() < 600, "戦況が小さい（%d 文字）" % JSON.stringify(obs).length())
	check_eq(Observation.direction_text(0.0), "前方", "正面は前方")
	check_eq(Observation.direction_text(PI / 2), "右", "+90度は右")
	check_eq(Observation.direction_text(-PI / 4), "前方やや左", "-45度は前方やや左")
	check_eq(Observation.direction_text(PI), "後方", "180度は後方")


func test_build_validation() -> void:
	var data := H.load_data()
	var rng := Rng.new(4)
	for k: int in 100:
		var b = Loot.random_build(data, rng, 1)
		check_eq(b.validate(data), "", "ランダムな機体は正しく組めている")
	var b2 = Loot.random_build(data, rng, 1)
	var fdef: GameData.PartDef = data.get_part(b2.frame.def_id)
	while b2.weapons.size() <= fdef.weapon_slots:
		b2.weapons.append(Loot.roll_part(data.get_part("weapon_drill"), rng, 900 + b2.weapons.size()))
	check(b2.validate(data).contains("武器が多すぎる"), "枠を超える武器は組めない")
