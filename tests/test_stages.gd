# ステージの土台のテスト。docs/design.md「ステージとギミックの順番」の1段階目の完成の目安を確かめる。
# 全ステージが検査を通る、同じ種なら同じステージの並びになる、バトルと通信対戦の写しがそのラウンドのステージを使う。
# 今のステージは標準の1つだけなので、ラウンドごとの選び方は、テストの中で2つ目のステージを足して確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const MatchSession := preload("res://core/match_session.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const Protocol := preload("res://net/protocol.gd")
const RemoteSession := preload("res://net/remote_session.gd")
const H := preload("res://tests/support/battle_helpers.gd")


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


func _raw(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))


## 標準に、穴を左右反対にしたテスト用のステージを足したデータ
func _two_stage_data() -> GameData:
	var stages: Dictionary = _raw("stages.json")
	var extra: Dictionary = (stages["stages"][0] as Dictionary).duplicate(true)
	extra["id"] = "test_mirror"
	extra["name"] = "テスト用"
	extra["pits"] = [{"x": 4, "z": -7, "r": 2.4}, {"x": -4, "z": 7, "r": 2.4}]
	stages["stages"].append(extra)
	var data := GameData.new()
	check(data.load_from_values(_raw("parts.json"), _raw("perks.json"), _raw("rules.json"), stages),
		"テスト用のステージを足しても読める：%s" % "
".join(data.errors))
	return data


func _cpu_match(data: GameData, seed_value: int) -> MatchSession:
	var setup: Array = []
	for i: int in 6:
		setup.append({"name": "CPU%d" % (i + 1), "is_human": false})
	return MatchSession.new(data, seed_value, setup, DefaultAgents.new())


## 最後まで回し、ラウンドごとのステージのIDを返す
func _stage_sequence(data: GameData, seed_value: int) -> Array:
	var s := _cpu_match(data, seed_value)
	s.finish_draft()
	var guard: int = 0
	while not s.is_finished() and guard < 1000:
		guard += 1
		match s.phase:
			MatchSession.PHASE_BUILD: s.finish_build()
			MatchSession.PHASE_BATTLE: s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT: s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	var out: Array = []
	for h: Dictionary in s.history:
		out.append(h["stage"])
	return out


func _sim_on(data: GameData, seed_value: int, stage: Dictionary) -> BattleSim:
	var root := Rng.new(seed_value)
	var setup: Rng = root.fork("setup")
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 100)]
	var brains: Array = [MockBrain.new(root.fork("brain/0")), MockBrain.new(root.fork("brain/1"))]
	return BattleSim.new(data, builds, brains, [setup.pick(H.PROMPTS), setup.pick(H.PROMPTS)], ["A", "B"],
		root.fork("battle"), stage)


func test_all_stages_load() -> void:
	var data := _data()
	check(data.errors.is_empty(), "data/ がエラーなしで読める：%s" % "\n".join(data.errors))
	var ids: Array = []
	for st: Dictionary in data.stages:
		ids.append(st["id"])
	check_eq(ids, ["standard"], "今は標準のステージだけ（ギミックとほかのステージは見送り）")
	check_eq(data.first_stage_id, "standard", "1ラウンド目は標準")


func test_standard_is_the_old_arena() -> void:
	# 「標準」は、ステージを分ける前の rules.json の battle.arena と同じ形
	var st: Dictionary = _data().get_stage("standard")
	# JSON の数は小数として読まれるので、期待する値も小数で書く
	check_eq(st["half_size"], 15.0, "広さ")
	check_eq(st["pits"], [{"x": -4.0, "z": -7.0, "r": 2.4}, {"x": 4.0, "z": 7.0, "r": 2.4}], "穴")
	check_eq(st["spawns"], [{"x": -11.0, "z": 0.0, "facing_deg": 0.0}, {"x": 11.0, "z": 0.0, "facing_deg": 180.0}], "出る位置")
	check_eq(st["packs"], [{"x": 11.5, "z": -10.5}, {"x": -11.5, "z": 10.5}], "回復パックの最初の場所")


func _expect_stage_error(label: String, stages: Dictionary, needle: String) -> void:
	var data := GameData.new()
	var ok: bool = data.load_from_values(_raw("parts.json"), _raw("perks.json"), _raw("rules.json"), stages)
	check(not ok, "%s：読み込みが失敗する" % label)
	var joined: String = "\n".join(data.errors)
	check(joined.contains(needle), "%s：エラーに「%s」が含まれる（実際：%s）" % [label, needle, joined])


func test_broken_stages_are_rejected() -> void:
	var good: Dictionary = _raw("stages.json")
	var s: Dictionary = good.duplicate(true)
	s["first"] = "nowhere"
	_expect_stage_error("first が知らないID", s, "first")
	s = good.duplicate(true)
	s["stages"].append((s["stages"][0] as Dictionary).duplicate(true))
	_expect_stage_error("IDの重複", s, "id")
	s = good.duplicate(true)
	s["stages"][0]["pits"] = []
	_expect_stage_error("穴がない", s, "pits")
	s = good.duplicate(true)
	s["stages"][0]["spawns"].pop_back()
	_expect_stage_error("出る位置が1つ", s, "spawns")
	s = good.duplicate(true)
	s["stages"][0]["spawns"][0] = {"x": -4, "z": -3, "facing_deg": 0}
	_expect_stage_error("出る位置が穴に近い", s, "出る位置")
	s = good.duplicate(true)
	s["stages"][0]["packs"][0] = {"x": 20, "z": 0}
	_expect_stage_error("回復パックが場の外", s, "場の外")
	s = good.duplicate(true)
	s["stages"][0]["half_size"] = NAN
	_expect_stage_error("広さが NaN", s, "half_size")
	_expect_stage_error("ステージがない", {"first": "standard", "stages": []}, "stages.json")


func test_same_seed_same_stage_sequence() -> void:
	var data := _two_stage_data()
	var seen: Dictionary = {}
	for seed_value: int in [5, 6, 7]:
		var a: Array = _stage_sequence(data, seed_value)
		check_eq(_stage_sequence(data, seed_value), a, "種 %d：同じ種なら同じステージの並び" % seed_value)
		check(a.size() >= 2, "種 %d：2ラウンド以上ある" % seed_value)
		check_eq(a[0], "standard", "種 %d：1ラウンド目は標準" % seed_value)
		for k: int in range(1, a.size()):
			check(a[k] != a[k - 1], "種 %d：ラウンド %d は直前と違うステージ" % [seed_value, k + 1])
		for id: Variant in a:
			seen[id] = true
	check_eq(seen.size(), data.stages.size(), "どのステージも選ばれる")


func test_one_stage_only_repeats_it() -> void:
	# ステージが1つしかなければ、毎ラウンドそれを使う（直前と違うものを選べなくても止まらない）
	var stages: Dictionary = _raw("stages.json")
	stages["stages"] = [stages["stages"][0]]
	var data := GameData.new()
	check(data.load_from_values(_raw("parts.json"), _raw("perks.json"), _raw("rules.json"), stages), "1つだけでも読める")
	for id: Variant in _stage_sequence(data, 3):
		check_eq(id, "standard", "毎ラウンド標準")


func test_battles_use_the_round_stage() -> void:
	var data := _two_stage_data()
	var s := _cpu_match(data, 11)
	s.finish_draft()
	var checked: int = 0
	var guard: int = 0
	while not s.is_finished() and guard < 1000 and checked < 4:
		guard += 1
		match s.phase:
			MatchSession.PHASE_BUILD:
				check(not s.stage.is_empty(), "組み立ての段階でステージが決まっている")
				s.finish_build()
			MatchSession.PHASE_BATTLE:
				for bt: MatchSession.Battle in s.battles:
					check(bt.sim.stage == s.stage, "ラウンド %d：バトルはそのラウンドのステージ" % s.round_no)
					for i: int in 2:
						var sp: Dictionary = s.stage["spawns"][i]
						check(is_equal_approx(bt.sim.robots[i].x, float(sp["x"])) and is_equal_approx(bt.sim.robots[i].z, float(sp["z"])),
							"ラウンド %d：機体 %d はステージの出る位置から始まる" % [s.round_no, i])
				checked += 1
				s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT:
				check_eq(s.history[s.history.size() - 1]["stage"], s.stage["id"], "ラウンドの記録にステージが残る")
				s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	check(checked >= 2, "2ラウンド以上のバトルを調べた")


func test_every_stage_plays_sanely() -> void:
	# どのステージでも、試合が必ず決着し、機体が場の中にいて数値が壊れない
	var data := _data()
	for st: Dictionary in data.stages:
		var half: float = float(st["half_size"])
		var reasons: Dictionary = {}
		for seed_value: int in 25:
			var sim := _sim_on(data, seed_value, st)
			for k: int in mini(st["packs"].size(), sim.packs.size()):
				check(is_equal_approx(float(sim.packs[k]["x"]), float(st["packs"][k]["x"])),
					"%s：最初の回復パックはステージの場所" % st["id"])
			var broken: int = 0
			while not sim.over and sim.tick <= sim.time_limit_ticks + 1:
				sim.step()
				for r: Robot in sim.robots:
					if not (is_finite(r.x) and is_finite(r.z) and is_finite(r.hp)) \
							or absf(r.x) > half + 1e-6 or absf(r.z) > half + 1e-6:
						broken += 1
			check(sim.over, "%s 種 %d：決着する" % [st["id"], seed_value])
			check_eq(broken, 0, "%s 種 %d：機体が場の中で数値が壊れない" % [st["id"], seed_value])
			reasons[sim.result["reason"]] = true
		check(reasons.size() >= 2, "%s：決着のつき方が1種類に偏らない（%s）" % [st["id"], str(reasons.keys())])


func test_online_copy_uses_the_stage() -> void:
	var data := _two_stage_data()
	var s := _cpu_match(data, 21)
	s.finish_draft()
	var guard: int = 0
	while s.round_no < 2 or s.phase != MatchSession.PHASE_BATTLE:
		guard += 1
		if guard > 100:
			break
		match s.phase:
			MatchSession.PHASE_BUILD: s.finish_build()
			MatchSession.PHASE_BATTLE: s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT: s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	check_eq(s.phase, MatchSession.PHASE_BATTLE, "2ラウンド目のバトルまで進む")
	check(s.stage["id"] != "standard", "2ラウンド目は標準以外")
	var remote := RemoteSession.new(data, func(_t: String, _p: Dictionary) -> void: pass)
	remote.apply_state(Protocol.decode(Protocol.encode("state", Protocol.session_state(s, 0, {}))))
	check_eq(remote.stage.get("id"), s.stage["id"], "写しにもラウンドのステージが届く")
	check_eq(remote.battles.size(), s.battles.size(), "バトルの数が同じ")
	for k: int in mini(remote.battles.size(), s.battles.size()):
		var sim: Variant = remote.battles[k].sim
		check_eq(sim.stage.get("id"), s.stage["id"], "バトル %d の写しのステージ" % k)
		var sp: Dictionary = s.stage["spawns"][0]
		check(is_equal_approx(sim.robots[0].x, float(sp["x"])), "バトル %d の写しの機体はステージの出る位置" % k)
