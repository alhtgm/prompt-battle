# ラウンドの進行のテスト。段階3の完成の目安「CPU6人の試合が最後の1人まで進み、何ラウンドかかるかが測れる」を確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const MatchSession := preload("res://core/match_session.gd")
const Player := preload("res://core/player.gd")
const Pairing := preload("res://core/pairing.gd")
const Damage := preload("res://core/damage.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")

## 最後まで回す試合の数
const FULL_MATCHES: int = 12


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


func _cpu_setup(n: int = 6) -> Array:
	var out: Array = []
	for i: int in n:
		out.append({"name": "CPU%d" % (i + 1), "is_human": false})
	return out


## 画面なしで最後まで回す。返すのはかかったラウンド数
func _play_to_end(s: MatchSession) -> int:
	s.finish_draft()
	var guard: int = 0
	while not s.is_finished() and guard < 1000:
		guard += 1
		match s.phase:
			MatchSession.PHASE_BUILD: s.finish_build()
			MatchSession.PHASE_BATTLE: s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT: s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	return s.round_no


func test_cpu_matches_reach_last_one_and_rounds_are_measured() -> void:
	var data := _data()
	var rounds: Array[int] = []
	var battle_secs: float = 0.0
	var battle_count: int = 0
	var max_rounds: int = int(data.rule("match.max_rounds"))
	var saw_ghost: bool = false
	for k: int in FULL_MATCHES:
		var s := MatchSession.new(data, 500 + k, _cpu_setup(), DefaultAgents.new())
		var n: int = _play_to_end(s)
		rounds.append(n)
		check(s.is_finished(), "種 %d：試合が終わる" % s.seed_value)
		check(n < max_rounds, "種 %d：安全装置（%d ラウンド）に頼らず終わる（%d ラウンド）" % [s.seed_value, max_rounds, n])
		check_eq(s.alive_players().size(), 1, "種 %d：生き残りは1人" % s.seed_value)
		var places: Array = []
		for p: Player in s.players:
			places.append(p.place)
			check(is_finite(p.health), "種 %d：体力が壊れない" % s.seed_value)
		places.sort()
		check_eq(places, [1, 2, 3, 4, 5, 6], "種 %d：順位が 1〜6 に1人ずつ" % s.seed_value)
		var winner: Player = s.standings()[0]
		check(winner.alive and winner.place == 1 and winner.health > 0.0, "種 %d：1位は生き残った人" % s.seed_value)
		# 早く脱落した人ほど下の順位
		for p: Player in s.players:
			for q: Player in s.players:
				if not p.alive and not q.alive and p.eliminated_round < q.eliminated_round:
					check(p.place > q.place, "種 %d：先に脱落した %s が下の順位" % [s.seed_value, p.name])
		for h: Dictionary in s.history:
			for e: Dictionary in h["battles"]:
				battle_secs += float(e["time"])
				battle_count += 1
		saw_ghost = _check_rounds(s) or saw_ghost
	check(saw_ghost, "記録の再生との試合が1度は起きる")
	rounds.sort()
	var total: int = 0
	for n: int in rounds:
		total += n
	print("    [ラウンド数] %d試合 最少 %d / 平均 %.1f / 中央 %d / 最多 %d　（バトル平均 %.1f 秒）" % [
		FULL_MATCHES, rounds[0], float(total) / rounds.size(), rounds[rounds.size() / 2],
		rounds[rounds.size() - 1], battle_secs / maxf(1.0, battle_count)])


func test_same_seed_same_match() -> void:
	var data := _data()
	var a := MatchSession.new(data, 4242, _cpu_setup(), DefaultAgents.new())
	var b := MatchSession.new(_data(), 4242, _cpu_setup(), DefaultAgents.new())
	_play_to_end(a)
	_play_to_end(b)
	check(same(a.history, b.history), "同じ種なら全ラウンドの記録が同じ")
	var pa: Array = []
	var pb: Array = []
	for p: Player in a.players:
		pa.append([p.place, p.health, p.perks])
	for p: Player in b.players:
		pb.append([p.place, p.health, p.perks])
	check(same(pa, pb), "同じ種なら順位・体力・パークが同じ")
	var c := MatchSession.new(data, 4243, _cpu_setup(), DefaultAgents.new())
	_play_to_end(c)
	check(not same(a.history, c.history), "違う種なら違う試合になる")


## 各ラウンドがルールどおりかを記録から調べる。記録の再生との試合があれば true
func _check_rounds(s: MatchSession) -> bool:
	var saw_ghost: bool = false
	var alive: int = s.players.size()
	for h: Dictionary in s.history:
		var ghost_battles: int = 0
		var fighters: Dictionary = {}
		for e: Dictionary in h["battles"]:
			if int(e["b"]) == MatchSession.GHOST_ID:
				ghost_battles += 1
			for id: int in [int(e["a"]), int(e["b"])]:
				if id != MatchSession.GHOST_ID:
					check(not fighters.has(id), "種 %d ラウンド %d：同じ人が2試合しない" % [s.seed_value, h["round"]])
					fighters[id] = true
		check_eq(fighters.size(), alive, "種 %d ラウンド %d：生き残り全員が戦う" % [s.seed_value, h["round"]])
		check_eq(ghost_battles, alive % 2, "種 %d ラウンド %d：奇数のときだけ記録の再生と戦う" % [s.seed_value, h["round"]])
		saw_ghost = saw_ghost or ghost_battles > 0
		check(not h["damage"].has(MatchSession.GHOST_ID), "記録の再生の側はダメージを受けない")
		for id: Variant in h["damage"]:
			check(int(h["damage"][id]) >= 0, "ダメージは0以上")
		alive -= h["eliminated"].size()
	return saw_ghost


func test_pairing_avoids_last_opponent() -> void:
	var ids: Array[int] = [0, 1, 2, 3, 4, 5]
	var last: Dictionary = {0: 1, 1: 0, 2: 3, 3: 2, 4: 5, 5: 4}
	for k: int in 50:
		var r: Dictionary = Pairing.make_pairs(ids, last, Rng.new(k), 50)
		check(not r["relaxed"], "組み合わせが見つかる")
		for pair: Array in r["pairs"]:
			check(last.get(pair[0], -1) != pair[1], "直前の相手とは組まない")
		check_eq(r["leftover"], -1, "偶数なら余りなし")
	var odd: Dictionary = Pairing.make_pairs([0, 1, 2] as Array[int], {}, Rng.new(1), 50)
	check_eq(odd["pairs"].size(), 1, "3人なら1組")
	check(odd["leftover"] >= 0, "3人なら1人余る")
	var forced: Dictionary = Pairing.make_pairs([0, 1] as Array[int], {0: 1, 1: 0}, Rng.new(1), 50)
	check(forced["relaxed"] and forced["pairs"].size() == 1, "2人しかいなければ条件を外して組む")


func test_damage_formula() -> void:
	var data := _data()
	var cfg: Dictionary = data.rules["damage"]
	check_eq(Damage.ranks({0: 100.0, 1: 80.0, 2: 80.0, 3: 10.0}), {0: 1, 1: 2, 2: 2, 3: 4}, "同じ体力は同じ順位")
	check_eq(Damage.loss_damage(1, 0.0, cfg), 6, "A=6、順位1、差0 → 6")
	check_eq(Damage.loss_damage(6, 1.0, cfg), 96, "順位6、差1 → 36+60=96")
	check_eq(Damage.loss_damage(3, 0.5, cfg), 48, "順位3、差0.5 → 18+30=48")
	check_eq(Damage.loss_damage(2, NAN, cfg), 12, "差が壊れていても順位の分だけ")
	check_eq(Damage.draw_damage(4, cfg), 0, "引き分けはダメージなし（仮）")


func test_loot_and_perks() -> void:
	var data := _data()
	for k: int in 100:
		var parts: Array = Loot.deal_round(data, Rng.new(k), 5, 1, 1)
		check_eq(parts.size(), 5, "配布は5つ")
		var kinds: Dictionary = {}
		for p: Variant in parts:
			kinds[p.kind] = true
		check_eq(kinds.size(), 3, "フレーム・武器・スキルを各1つ以上")
		var perks: Array[String] = Loot.perk_choices(data, Rng.new(k), 3)
		var uniq: Dictionary = {}
		for id: String in perks:
			uniq[id] = true
		check(perks.size() == 3 and uniq.size() == 3, "パークの候補は重ならない3つ")


func test_perk_effects_stack() -> void:
	var data := _data()
	var p := Player.new()
	var b = Loot.random_build(data, Rng.new(3), 1)
	p.build = b
	var base_hp: float = b.frame.get_stat("hp")
	p.perks = ["perk_armor", "perk_armor", "perk_mount", "perk_vocab", "perk_tuning"]
	var eff = p.effective_build(data)
	check(is_equal_approx(eff.frame.get_stat("hp"), base_hp * 1.05 * 1.05), "HP+5% が2回積み重なる")
	check_eq(b.frame.get_stat("hp"), base_hp, "元の手持ちパーツは変わらない")
	check_eq(p.extra_weapon_slots(data), 1, "増設マウントで武器の枠+1")
	check_eq(p.prompt_max_chars(data), 140, "プロンプトの文字数+20")
	for i: int in b.skills.size():
		for s: String in b.skills[i].stats:
			check(is_equal_approx(eff.skills[i].get_stat(s), b.skills[i].get_stat(s) * 1.1), "スキルの性能+10%")


func test_human_player_flow() -> void:
	var data := _data()
	var setup: Array = _cpu_setup()
	setup[0] = {"name": "あなた", "is_human": true}
	var s := MatchSession.new(data, 77, setup, DefaultAgents.new())
	check_eq(s.phase, MatchSession.PHASE_DRAFT, "最初はパーツ選び")
	check_eq(s.draft_offer["frame"].size(), 5, "フレームの候補は5つ")
	check(not s.draft_pick(0, {"frame": -5, "weapon": -5, "skill": -5}).is_empty(), "候補にないものは選べない")
	var picks: Dictionary = {}
	for kind: String in GameData.KINDS:
		picks[kind] = s.draft_offer[kind][0].uid
	check_eq(s.draft_pick(0, picks), "", "候補から種類ごとに1つ選べる")
	s.finish_draft()
	var me: Player = s.get_player(0)
	check_eq(me.hand.size(), 3, "選んだ3つが手持ちになる")
	check_eq(me.hand[0].def_id, s.draft_offer["frame"][0].def_id, "選んだフレームが手持ちにある")
	check_eq(s.phase, MatchSession.PHASE_BUILD, "パーツ選びの次は組み立て")

	var frame_uid: int = me.hand[0].uid
	var weapon_uid: int = me.hand[1].uid
	var skill_uid: int = me.hand[2].uid
	check(not s.submit_build(0, frame_uid, [weapon_uid, weapon_uid, weapon_uid, weapon_uid], [], "").is_empty(),
		"枠を超える武器は付けられない")
	check(not s.submit_build(0, frame_uid, [weapon_uid], [], "あ".repeat(121)).is_empty(), "121文字のプロンプトは長すぎる")
	var skills: Array = [skill_uid] if data.get_part(me.hand[0].def_id).skill_slots > 0 else []
	# 出撃できるかの確かめ（組み立て画面が使う）：答えは submit_build と同じで、状態は変えない
	check_eq(s.check_build(0, frame_uid, [weapon_uid, weapon_uid, weapon_uid, weapon_uid], [], ""),
		s.submit_build(0, frame_uid, [weapon_uid, weapon_uid, weapon_uid, weapon_uid], [], ""), "確かめと出撃で同じ答え")
	check(s.check_build(0, frame_uid, [999999], [], "").contains("手持ちにない"), "手持ちにないパーツは確かめでも見つかる")
	check_eq(s.check_build(0, frame_uid, [weapon_uid], skills, "突撃しろ"), "", "正しい機体なら確かめも通る")
	check(me.build == null and not me.done_this_phase, "確かめただけでは機体も決定も変わらない")
	check_eq(s.submit_build(0, frame_uid, [weapon_uid], skills, "突撃しろ"), "", "正しい機体なら組める")

	# 制限時間がたつと自動で締め切られる
	s.update(float(data.rule("round.build_time_limit_sec")) + 0.1)
	check_eq(s.phase, MatchSession.PHASE_BATTLE, "組み立ての制限時間がたつとバトルへ")
	check(s.battle_of(0) != null, "自分のバトルがある")
	check_eq(s.battles.size(), 3, "6人なら3試合")
	for k: int in 60 * 80:  # 実時間で進めても決着する（80秒ぶん）
		if s.phase != MatchSession.PHASE_BATTLE:
			break
		s.update(1.0 / 60.0)
	check_eq(s.phase, MatchSession.PHASE_ROUND_RESULT, "3試合とも決着したらラウンド結果へ")
	s.finish_round_result()
	check_eq(s.phase, MatchSession.PHASE_LOOT, "ラウンド結果の次は配布とパーク")
	check_eq(me.new_parts.size(), 5, "パーツが5つ配られる")
	check_eq(me.hand.size(), 8, "手持ちが 3+5 になる")
	check(not s.choose_perk(0, "perk_nothing").is_empty(), "候補にないパークは選べない")
	check_eq(s.choose_perk(0, me.perk_choices[0]), "", "候補のパークを選べる")
	check(not s.choose_perk(0, me.perk_choices[1]).is_empty(), "1ラウンドに選べるのは1つ")
	s.finish_loot()
	check_eq(s.phase, MatchSession.PHASE_BUILD, "次のラウンドの組み立てへ")
	check_eq(s.round_no, 2, "ラウンド2になる")
	s.finish_build()
	check_eq(me.prompt, "突撃しろ", "組み立てを決めなければ前の機体とプロンプトのまま")
