# スクラップ（ポイント）のテスト。解体・再抽選（元のまま／新しい性能を選ぶ）・パーク候補の引き直し・負けたラウンドの +1、
# 使えるのは後半だけ、同じ種なら同じ結果、CPU も使う、スクラップが負にならないことを確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Loot := preload("res://core/loot.gd")
const MatchSession := preload("res://core/match_session.gd")
const Player := preload("res://core/player.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


func _setup_with_human() -> Array:
	var out: Array = [{"name": "あなた", "is_human": true}]
	for i: int in range(1, 6):
		out.append({"name": "CPU%d" % i, "is_human": false})
	return out


## 人間1人＋CPU5人の試合を、スクラップが使えるラウンドの組み立ての段階まで進める（人間は脱落しないよう体力を足す）
func _session_at_unlock(data: GameData, seed_value: int) -> MatchSession:
	var s := MatchSession.new(data, seed_value, _setup_with_human(), DefaultAgents.new())
	s.finish_draft()
	var guard: int = 0
	while guard < 200 and not (s.phase == MatchSession.PHASE_BUILD and s.scrap_unlocked()):
		guard += 1
		s.get_player(0).health = 1000.0
		match s.phase:
			MatchSession.PHASE_BUILD: s.finish_build()
			MatchSession.PHASE_BATTLE: s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT: s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	return s


func _spare_part(s: MatchSession, p: Player) -> Variant:
	for part: Variant in p.hand:
		if not s._is_equipped(p, part.uid):
			return part
	return null


func test_locked_before_unlock_round() -> void:
	var data := _data()
	var s := MatchSession.new(data, 5, _setup_with_human(), DefaultAgents.new())
	s.finish_draft()
	check(not s.scrap_unlocked(), "1ラウンド目はまだ使えない")
	var me: Player = s.get_player(0)
	me.scrap = 99
	check(s.scrap_part(0, me.hand[0].uid).contains("ラウンド目から"), "解体できない")
	check(s.reroll_part(0, me.hand[0].uid).contains("ラウンド目から"), "再抽選できない")
	check_eq(me.hand.size(), 3, "手持ちは減らない")


func test_scrap_part_gives_points() -> void:
	var data := _data()
	var s: MatchSession = _session_at_unlock(data, 11)
	check(s.phase == MatchSession.PHASE_BUILD and s.scrap_unlocked(), "使えるラウンドの組み立てまで進む")
	check_eq(s.round_no, int(data.rule("scrap.unlock_round")), "使えるのは決めたラウンドから")
	var me: Player = s.get_player(0)
	var spare: Variant = _spare_part(s, me)
	check(spare != null, "付けていないパーツがある")
	var before: int = me.scrap
	var size: int = me.hand.size()
	var want: int = int(data.rule("scrap.value." + spare.kind))
	if Loot.roll_quality(data.get_part(spare.def_id), spare.stats) > 0.5:
		want += int(data.rule("scrap.high_roll_bonus"))
	check_eq(s.scrap_part(0, spare.uid), "", "付けていないパーツは解体できる")
	check_eq(me.scrap, before + want, "種類ごとの量（上振れなら上乗せ）をもらえる")
	check_eq(me.hand.size(), size - 1, "解体したパーツは手持ちから消える")
	check(me.find_part(spare.uid) == null, "もう手持ちにない")
	check(not s.scrap_part(0, me.build.frame.uid).is_empty(), "付けているパーツは解体できない")
	check(not s.scrap_part(0, 999999).is_empty(), "手持ちにないパーツは解体できない")


func test_reroll_keep_or_take() -> void:
	var data := _data()
	var s: MatchSession = _session_at_unlock(data, 12)
	var me: Player = s.get_player(0)
	var cost: int = int(data.rule("scrap.reroll_part_cost"))
	var part: Variant = me.build.weapons[0]
	var def: GameData.PartDef = data.get_part(part.def_id)
	me.scrap = cost - 1
	check(s.reroll_part(0, part.uid).contains("足りない"), "スクラップが足りなければ再抽選できない")
	me.scrap = cost * 3
	var old_stats: Dictionary = part.stats.duplicate()
	check_eq(s.reroll_part(0, part.uid), "", "再抽選できる")
	check_eq(me.scrap, cost * 2, "再抽選するとスクラップが減る")
	check(not me.pending_reroll.is_empty() and int(me.pending_reroll["uid"]) == part.uid, "結果は選ぶまで保留される")
	check_eq(part.stats, old_stats, "選ぶまでは元の性能のまま")
	for k: Variant in me.pending_reroll["stats"]:
		var r: GameData.StatRange = def.stats[str(k)]
		var v: float = float(me.pending_reroll["stats"][k])
		check(is_finite(v) and v >= r.min_value and v <= r.max_value, "新しい性能は範囲内（%s %.3f）" % [str(k), v])
	check(s.reroll_part(0, part.uid).contains("選んでいない"), "結果を選ぶまで次の再抽選はできない")
	check(not s.scrap_part(0, part.uid).is_empty(), "結果を選んでいるパーツは解体できない")
	# 元のまま
	check_eq(s.resolve_reroll(0, false), "", "元のままを選べる")
	check_eq(part.stats, old_stats, "元のままなら性能は変わらない")
	check_eq(me.scrap, cost * 2, "元のままでもスクラップは戻らない")
	# 新しい性能
	check_eq(s.reroll_part(0, part.uid), "", "もう一度再抽選できる")
	var new_stats: Dictionary = me.pending_reroll["stats"].duplicate()
	check_eq(s.resolve_reroll(0, true), "", "新しい性能を選べる")
	for k: Variant in new_stats:
		check_eq(part.stats[str(k)], float(new_stats[k]), "新しい性能になる（%s）" % str(k))
	check(me.pending_reroll.is_empty(), "選んだら保留は消える")
	check(not s.resolve_reroll(0, true).is_empty(), "保留がなければ選べない")
	# 選ばないまま締め切ると元のまま
	var before_close: Dictionary = part.stats.duplicate()
	check_eq(s.reroll_part(0, part.uid), "", "3回目の再抽選")
	s.finish_build()
	check_eq(part.stats, before_close, "選ばないまま締め切ったら元のまま")
	check(me.pending_reroll.is_empty(), "締め切ったら保留は消える")
	check(me.scrap >= 0, "スクラップは負にならない")


func test_reroll_perk_choices() -> void:
	var data := _data()
	var s: MatchSession = _session_at_unlock(data, 13)
	var me: Player = s.get_player(0)
	check(not s.reroll_perk_choices(0).is_empty(), "組み立ての段階ではパーク候補を引き直せない")
	s.finish_build()
	s.run_battles_to_end()
	me.health = 1000.0
	s.finish_round_result()
	check_eq(s.phase, MatchSession.PHASE_LOOT, "パーク選びの段階")
	var cost: int = int(data.rule("scrap.reroll_perks_cost"))
	var limit: int = int(data.rule("scrap.reroll_perks_per_round"))
	me.scrap = cost * (limit + 2)
	var seen_change: bool = false
	for i: int in limit:
		var before: Array = me.perk_choices.duplicate()
		check_eq(s.reroll_perk_choices(0), "", "引き直せる（%d 回目）" % (i + 1))
		check_eq(me.perk_choices.size(), int(data.rule("loot.perk_choices")), "候補の数は変わらない")
		seen_change = seen_change or before != Array(me.perk_choices)
	check(seen_change, "候補が変わることがある")
	check_eq(me.scrap, cost * 2, "引き直すたびにスクラップが減る")
	check(s.reroll_perk_choices(0).contains("使い切った"), "1ラウンドの回数を超えては引き直せない")
	# 配られたパーツは、パーク選びの段階でも解体できる
	var np: Variant = me.new_parts[0]
	check_eq(s.scrap_part(0, np.uid), "", "配られたパーツをその場で解体できる")
	check(not me.new_parts.has(np), "解体したパーツは配られたパーツの一覧からも消える")
	check_eq(s.choose_perk(0, me.perk_choices[0]), "", "引き直した候補から選べる")
	check(not s.reroll_perk_choices(0).is_empty(), "選んだあとは引き直せない")
	s.finish_loot()
	s.finish_build()
	s.run_battles_to_end()
	me.health = 1000.0
	s.finish_round_result()
	if s.phase == MatchSession.PHASE_LOOT:
		check_eq(me.perk_rerolls_used, 0, "次のラウンドは回数が戻る")


func test_loss_bonus_and_cpu_use() -> void:
	var data := _data()
	var bonus: int = int(data.rule("scrap.loss_bonus"))
	var setup: Array = []
	for i: int in 6:
		setup.append({"name": "CPU%d" % (i + 1), "is_human": false})
	var s := MatchSession.new(data, 2024, setup, DefaultAgents.new())
	s.finish_draft()
	s.finish_build()
	s.run_battles_to_end()
	var h: Dictionary = s.history[0]
	for e: Dictionary in h["battles"]:
		var w: int = int(e["winner"])
		var ids: Array = [int(e["a"]), int(e["b"])]
		for id: int in ids:
			if id == MatchSession.GHOST_ID:
				continue
			var lost: bool = w != -2 and w != id
			check_eq(s.get_player(id).scrap, bonus if lost else 0, "1ラウンド目：負けた人だけ +%d（%d）" % [bonus, id])
			check_eq(int(h["scrap_gain"].get(id, 0)), bonus if lost else 0, "記録にももらった量が残る（%d）" % id)
	# 最後まで回す：CPU は後半に解体と再抽選を使い、スクラップは負にならない
	var used: bool = false
	var guard: int = 0
	while not s.is_finished() and guard < 1000:
		guard += 1
		match s.phase:
			MatchSession.PHASE_BUILD:
				s.finish_build()
				if s.scrap_unlocked():
					for p: Player in s.alive_players():
						check(p.scrap >= 0, "スクラップは負にならない")
						check(p.pending_reroll.is_empty(), "CPU は再抽選の結果をその場で選ぶ")
						used = used or p.rerolls_done > 0
						check_eq(p.hand.size(), 1 + p.build.weapons.size() + p.build.skills.size(),
							"CPU は付けていないパーツを解体する")
			MatchSession.PHASE_BATTLE: s.run_battles_to_end()
			MatchSession.PHASE_ROUND_RESULT: s.finish_round_result()
			MatchSession.PHASE_LOOT: s.finish_loot()
	check(s.is_finished(), "最後まで進む")
	check(used, "CPU も再抽選を使う")


func test_same_seed_same_reroll() -> void:
	var data := _data()
	var results: Array = []
	for k: int in 2:
		var s: MatchSession = _session_at_unlock(data, 31)
		var me: Player = s.get_player(0)
		me.scrap = 20
		var part: Variant = me.build.frame
		s.reroll_part(0, part.uid)
		var first: Dictionary = me.pending_reroll["stats"].duplicate()
		s.resolve_reroll(0, true)
		s.reroll_part(0, part.uid)
		results.append([first, me.pending_reroll["stats"].duplicate(), me.scrap])
	check_eq(results[0], results[1], "同じ種・同じ操作なら同じ再抽選の結果")
	check(results[0][0] != results[0][1], "続けて引くと別の結果になる")


## 通信対戦：自分のスクラップと再抽選の結果待ちが、サーバーの状態から写しに届く
func test_online_state_carries_scrap() -> void:
	var data := _data()
	var s: MatchSession = _session_at_unlock(data, 41)
	var me: Player = s.get_player(0)
	me.scrap = 9
	check_eq(s.reroll_part(0, me.build.frame.uid), "", "再抽選できる")
	var Protocol: GDScript = load("res://net/protocol.gd")
	var RemoteSession: GDScript = load("res://net/remote_session.gd")
	var st: Dictionary = Protocol.session_state(s, 0, {})
	var sent: Array = []
	var remote: RefCounted = RemoteSession.new(data, func(type: String, payload: Dictionary) -> void: sent.append([type, payload]))
	remote.apply_state(st)
	var rme: Variant = remote.get_player(0)
	check_eq(rme.scrap, me.scrap, "スクラップの量が届く")
	check_eq(rme.pending_reroll, me.pending_reroll, "再抽選の結果待ちが届く")
	check(remote.scrap_unlocked(), "写しでも使えるラウンドが分かる")
	var other: Dictionary = Protocol.session_state(s, 1, {})
	check(not str(other["players"]).contains("pending_reroll"), "ほかの人の再抽選の結果は送らない")
	remote.scrap_part(0, 123)
	remote.reroll_part(0, me.build.frame.uid)
	remote.resolve_reroll(0, true)
	remote.reroll_perk_choices(0)
	var types: Array = []
	for m: Array in sent:
		types.append(m[0])
	check_eq(types, [Protocol.SCRAP_PART, Protocol.REROLL_PART, Protocol.RESOLVE_REROLL, Protocol.REROLL_PERKS],
		"写しの操作はサーバーへ送るだけ")
