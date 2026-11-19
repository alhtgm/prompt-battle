# 試合全体の状態と段階の進行。プレイヤー、ラウンド、ペア、バトル、ダメージ、配布とパーク、脱落と順位を受け持つ。
# 画面はここの状態を読み、操作はここのメソッドだけを通す。CPUの判断と頭脳は外から渡された agents に任せる。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Player := preload("res://core/player.gd")
const Pairing := preload("res://core/pairing.gd")
const Damage := preload("res://core/damage.gd")
const BattleSim := preload("res://core/battle_sim.gd")

## 段階（docs/design.md「画面と状態の流れ」）
const PHASE_DRAFT: String = "draft"
const PHASE_BUILD: String = "build"
const PHASE_BATTLE: String = "battle"
const PHASE_ROUND_RESULT: String = "round_result"
const PHASE_LOOT: String = "loot"
const PHASE_FINISHED: String = "finished"

## 記録の再生の相手のID（プレイヤーのIDとかぶらない）
const GHOST_ID: int = -1


## このラウンドのバトル1つ
class Battle:
	var a: int = 0
	## 相手のID。記録の再生なら GHOST_ID
	var b: int = 0
	## 記録の再生のとき、元になった脱落者のID
	var ghost_of: int = -1
	## 両者のプロンプト（観戦で見せるかどうかは画面が決める）
	var prompts: Array = ["", ""]
	var sim: BattleSim


var data: GameData
var seed_value: int = 0
var players: Array[Player] = []
var phase: String = PHASE_DRAFT
var round_no: int = 0
## 開始時の選出（種類 → 実物の配列）。全員に同じものを見せる
var draft_offer: Dictionary = {}
## 今のラウンドのバトル
var battles: Array[Battle] = []
## 終わったラウンドの記録（古い順）
var history: Array[Dictionary] = []
## 今の段階の残り時間（組み立ての段階だけ使う）
var phase_time_left: float = 0.0
## 3試合とも決着してから、ラウンド結果へ切り替えるまでの残り秒数（決着前は -1）
var battle_end_left: float = -1.0

var _rng: Rng
var _agents: RefCounted
var _next_uid: int = 1
var _draft_picks: Dictionary = {}
## 直前に脱落した人の記録（奇数のときの相手）
var _ghost: Dictionary = {}
var _accum: float = 0.0


## player_setup は {"name": String, "is_human": bool} の配列。agents は agent/default_agents.gd の形
func _init(game_data: GameData, seed_v: int, player_setup: Array, agents: RefCounted) -> void:
	data = game_data
	seed_value = seed_v
	_rng = Rng.new(seed_v)
	_agents = agents
	for i: int in player_setup.size():
		var p := Player.new()
		p.id = i
		p.name = str(player_setup[i].get("name", "P%d" % (i + 1)))
		p.is_human = bool(player_setup[i].get("is_human", false))
		p.health = float(data.rule("initial_health"))
		players.append(p)
	var per_kind: int = int(data.rule("draft.choices_per_kind"))
	draft_offer = Loot.draft_offer(data, _rng.fork("draft"), per_kind, _take_uids(per_kind * GameData.KINDS.size()))
	phase = PHASE_DRAFT


# ---- 状態を読む ----

func get_player(id: int) -> Player:
	return players[id] if id >= 0 and id < players.size() else null


func alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players:
		if p.alive:
			out.append(p)
	return out


## 自分が出ているバトル（なければ null）
func battle_of(player_id: int) -> Battle:
	for b: Battle in battles:
		if b.a == player_id or b.b == player_id:
			return b
	return null


## 順位表：順位が決まった人は順位順、まだの人は体力の多い順
func standings() -> Array[Player]:
	var out: Array[Player] = players.duplicate()
	out.sort_custom(func(x: Player, y: Player) -> bool:
		if x.alive != y.alive:
			return x.alive
		if not x.alive:
			return x.place < y.place
		if x.health != y.health:
			return x.health > y.health
		return x.id < y.id)
	return out


## 通信対戦の写し（net/remote_session.gd）なら true。画面が「待っています」などの出し分けに使う
func is_online() -> bool:
	return false


func is_finished() -> bool:
	return phase == PHASE_FINISHED


# ---- 開始時のパーツ選び ----

## 人間が種類ごとに1つ選ぶ。picks は 種類 → uid。問題がなければ空文字
func draft_pick(player_id: int, picks: Dictionary) -> String:
	if phase != PHASE_DRAFT:
		return "今はパーツ選びの段階ではない"
	var p: Player = get_player(player_id)
	if p == null:
		return "そのプレイヤーはいない"
	for kind: String in GameData.KINDS:
		if _offer_part(kind, int(picks.get(kind, -1))) == null:
			return "%s の選択が候補にない" % kind
	_draft_picks[player_id] = picks.duplicate()
	p.done_this_phase = true
	return ""


## パーツ選びを締め切る。選んでいない人は CPU の判断で選ぶ。同じパーツを複数人が選べる（それぞれ別の実物になる）
func finish_draft() -> void:
	if phase != PHASE_DRAFT:
		return
	for p: Player in players:
		var picks: Dictionary = _draft_picks.get(p.id, {})
		if picks.is_empty():
			picks = _agents.pick_draft(draft_offer, _rng.fork("draft/pick/%d" % p.id))
		for kind: String in GameData.KINDS:
			var src: PartInstance = _offer_part(kind, int(picks[kind]))
			p.hand.append(_copy_part(src))
	_start_round()


# ---- 組み立てとプロンプト ----

## 人間が機体とプロンプトを決める。問題がなければ空文字
func submit_build(player_id: int, frame_uid: int, weapon_uids: Array, skill_uids: Array, prompt: String) -> String:
	if phase != PHASE_BUILD:
		return "今は組み立ての段階ではない"
	var p: Player = get_player(player_id)
	if p == null or not p.alive:
		return "そのプレイヤーは参加していない"
	var r: Dictionary = p.assemble_build(data, frame_uid, weapon_uids, skill_uids, prompt)
	if not str(r["error"]).is_empty():
		return r["error"]
	p.build = r["build"]
	p.prompt = prompt
	p.done_this_phase = true
	return ""


## 出撃できるかだけを調べる（状態は変えない）。組み立て画面が、押す前に問題を見せるのに使う
func check_build(player_id: int, frame_uid: int, weapon_uids: Array, skill_uids: Array, prompt: String) -> String:
	var p: Player = get_player(player_id)
	if p == null or not p.alive:
		return "そのプレイヤーは参加していない"
	return p.assemble_build(data, frame_uid, weapon_uids, skill_uids, prompt)["error"]


## 組み立てを締め切ってバトルを始める。決めていない人は、前の機体があればそのまま、なければ CPU の判断で組む
func finish_build() -> void:
	if phase != PHASE_BUILD:
		return
	for p: Player in alive_players():
		if p.done_this_phase:
			continue
		var keep: bool = p.is_human and p.build != null \
			and p.build.validate(data, p.extra_weapon_slots(data), p.extra_skill_slots(data)).is_empty()
		if keep:
			continue
		var plan: Dictionary = _agents.plan_build(data, p, _rng.fork("round/%d/plan/%d" % [round_no, p.id]))
		var err: String = submit_build(p.id, plan["frame"], plan["weapons"], plan["skills"], plan["prompt"])
		if not err.is_empty():
			push_error("CPU の組み立てが不正：%s" % err)
	_start_battles()


# ---- バトル ----

## 実時間で進める（画面用）。組み立ての制限時間もここで数える
func update(delta: float) -> void:
	match phase:
		PHASE_BUILD:
			phase_time_left -= delta
			if phase_time_left <= 0.0:
				finish_build()
		PHASE_BATTLE:
			_accum += delta
			var dt: float = 1.0 / float(data.rule("tick_rate"))
			var steps: int = 0
			while _accum >= dt and steps < 600:
				for b: Battle in battles:
					b.sim.step()
				_accum -= dt
				steps += 1
			if _all_battles_over():
				# 決着してすぐには切り替えず、少し余韻を残す（爆発や勝ち負けを見せる）
				if battle_end_left < 0.0:
					battle_end_left = float(data.rule("round.battle_end_delay_sec"))
				else:
					battle_end_left -= delta
				if battle_end_left <= 0.0:
					_finish_battles()


## 3試合とも決着まで一気に進める（画面なしの試合用。「最後まで飛ばす」もこれで、余韻は待たない）
func run_battles_to_end() -> void:
	if phase != PHASE_BATTLE:
		return
	for b: Battle in battles:
		b.sim.run_to_end()
	_finish_battles()


# ---- ラウンド結果、配布とパーク ----

## ラウンド結果を見終えた。最後の1人が決まっていれば試合終了、そうでなければ配布とパーク選びへ
func finish_round_result() -> void:
	if phase != PHASE_ROUND_RESULT:
		return
	if alive_players().size() <= 1 or _all_placed():
		phase = PHASE_FINISHED
		return
	var count: int = int(data.rule("loot.parts_per_round"))
	var min_kind: int = int(data.rule("loot.min_per_kind"))
	var perk_count: int = int(data.rule("loot.perk_choices"))
	for p: Player in alive_players():
		var rng: Rng = _rng.fork("round/%d/loot/%d" % [round_no, p.id])
		p.new_parts = Loot.deal_round(data, rng, count, min_kind, _take_uids(count))
		p.hand.append_array(p.new_parts)
		p.perk_choices = Loot.perk_choices(data, rng, perk_count)
		p.done_this_phase = false
	phase = PHASE_LOOT


## 人間がパークを1つ選ぶ。問題がなければ空文字
func choose_perk(player_id: int, perk_id: String) -> String:
	if phase != PHASE_LOOT:
		return "今はパーク選びの段階ではない"
	var p: Player = get_player(player_id)
	if p == null or not p.alive:
		return "そのプレイヤーは参加していない"
	if p.done_this_phase:
		return "このラウンドのパークはもう選んだ"
	if not p.perk_choices.has(perk_id):
		return "候補にないパーク"
	p.perks.append(perk_id)
	p.done_this_phase = true
	return ""


## パーク選びを締め切って次のラウンドへ。選んでいない人は CPU の判断で選ぶ
func finish_loot() -> void:
	if phase != PHASE_LOOT:
		return
	for p: Player in alive_players():
		if not p.done_this_phase:
			var pick: String = _agents.pick_perk(p.perk_choices, _rng.fork("round/%d/perk/%d" % [round_no, p.id]))
			if not pick.is_empty():
				choose_perk(p.id, pick)
	_start_round()


# ---- 内部 ----

func _take_uids(count: int) -> int:
	var first: int = _next_uid
	_next_uid += count
	return first


func _offer_part(kind: String, uid: int) -> PartInstance:
	for p: PartInstance in draft_offer.get(kind, []):
		if p.uid == uid:
			return p
	return null


func _copy_part(src: PartInstance) -> PartInstance:
	var p := PartInstance.new()
	p.uid = _take_uids(1)
	p.def_id = src.def_id
	p.kind = src.kind
	p.stats = src.stats.duplicate()
	return p


func _start_round() -> void:
	round_no += 1
	for p: Player in players:
		p.done_this_phase = false
	phase_time_left = float(data.rule("round.build_time_limit_sec"))
	phase = PHASE_BUILD


func _start_battles() -> void:
	# 配られたパーツの記録は、組み立ての画面で NEW を出し終えたら消す（画面用の記録で、計算には使わない）
	for p: Player in players:
		p.new_parts = []
	var ids: Array[int] = []
	for p: Player in alive_players():
		ids.append(p.id)
	var last_opp: Dictionary = {}
	if not history.is_empty():
		for e: Dictionary in history[history.size() - 1]["battles"]:
			if int(e["b"]) != GHOST_ID:
				last_opp[int(e["a"])] = int(e["b"])
				last_opp[int(e["b"])] = int(e["a"])
	var pr: Dictionary = Pairing.make_pairs(ids, last_opp, _rng.fork("round/%d/pairing" % round_no),
		int(data.rule("match.pairing_attempts")))
	battles = []
	for pair: Array in pr["pairs"]:
		_add_battle(int(pair[0]), int(pair[1]))
	if int(pr["leftover"]) >= 0 and not _ghost.is_empty():
		_add_battle(int(pr["leftover"]), GHOST_ID)
	_accum = 0.0
	battle_end_left = -1.0
	phase = PHASE_BATTLE


func _add_battle(a: int, b: int) -> void:
	var k: int = battles.size()
	var bt := Battle.new()
	bt.a = a
	bt.b = b
	var pa: Player = players[a]
	var builds: Array = [pa.effective_build(data)]
	var prompts: Array = [pa.prompt]
	var names: Array = [pa.name]
	var humans: Array = [pa.is_human]
	if b == GHOST_ID:
		bt.ghost_of = int(_ghost["id"])
		builds.append(_ghost["build"])
		prompts.append(_ghost["prompt"])
		names.append("%s（記録）" % _ghost["name"])
		humans.append(false)
	else:
		var pb: Player = players[b]
		builds.append(pb.effective_build(data))
		prompts.append(pb.prompt)
		names.append(pb.name)
		humans.append(pb.is_human)
	var ids: Array = [a, b]  # 記録の再生の側は GHOST_ID
	var brains: Array = []
	for side: int in 2:
		brains.append(_agents.make_brain(humans[side], _rng.fork("round/%d/brain/%d/%d" % [round_no, k, side]),
			ids[side], humans[1 - side]))
	bt.prompts = prompts.duplicate()
	bt.sim = BattleSim.new(data, builds, brains, prompts, names, _rng.fork("round/%d/battle/%d" % [round_no, k]))
	battles.append(bt)


func _all_battles_over() -> bool:
	for b: Battle in battles:
		if not b.sim.over:
			return false
	return true


func _all_placed() -> bool:
	for p: Player in players:
		if p.place == 0:
			return false
	return true


## バトルの結果からダメージを出し、脱落と順位を決めてラウンドの記録を残す
func _finish_battles() -> void:
	var cfg: Dictionary = data.rules["damage"]
	var health_now: Dictionary = {}
	for p: Player in alive_players():
		health_now[p.id] = p.health
	var rank: Dictionary = Damage.ranks(health_now)
	var dmg: Dictionary = {}
	var entries: Array = []
	for bt: Battle in battles:
		var res: Dictionary = bt.sim.result
		var w: int = int(res["winner"])
		var winner_id: int = -2  # -2 は引き分け
		if w == 0:
			winner_id = bt.a
		elif w == 1:
			winner_id = bt.b
		var losers: Array[int] = []
		if w == 0 and bt.b != GHOST_ID:
			losers.append(bt.b)
		elif w == 1:
			losers.append(bt.a)
		for id: int in losers:  # 記録の再生の側はダメージを受けない
			dmg[id] = dmg.get(id, 0) + Damage.loss_damage(rank[id], float(res["margin"]), cfg)
		if w < 0:
			for id: int in [bt.a, bt.b]:
				if id != GHOST_ID:
					dmg[id] = dmg.get(id, 0) + Damage.draw_damage(rank[id], cfg)
		entries.append({"a": bt.a, "b": bt.b, "ghost_of": bt.ghost_of, "winner": winner_id,
			"reason": res["reason"], "margin": res["margin"], "time": res["time"],
			"hp_ratio": res["hp_ratio"]})

	var alive_before: int = health_now.size()
	for id: int in dmg:
		players[id].health -= float(dmg[id])

	# 脱落：体力がよりマイナスの人を下の順位にする
	var out_now: Array[Player] = []
	for p: Player in alive_players():
		if p.health <= 0.0:
			out_now.append(p)
	out_now.sort_custom(func(x: Player, y: Player) -> bool:
		return x.health < y.health if x.health != y.health else x.id > y.id)
	var place: int = alive_before
	for p: Player in out_now:
		p.alive = false
		p.place = place
		p.eliminated_round = round_no
		place -= 1
	if not out_now.is_empty():
		var last_out: Player = out_now[out_now.size() - 1]  # 脱落した中で一番上の順位の人
		_ghost = {"id": last_out.id, "name": last_out.name, "prompt": last_out.prompt,
			"build": last_out.effective_build(data)}

	var survivors: Array[Player] = alive_players()
	if survivors.size() == 1:
		survivors[0].place = 1
	elif survivors.size() > 1 and round_no >= int(data.rule("match.max_rounds")):
		_place_by_health(survivors)  # 安全装置：打ち切って体力の順で順位を決める

	var health_after: Dictionary = {}
	for p: Player in players:
		health_after[p.id] = p.health
	var eliminated: Array[int] = []
	for p: Player in out_now:
		eliminated.append(p.id)
	history.append({"round": round_no, "battles": entries, "damage": dmg, "eliminated": eliminated,
		"health": health_after, "ranks": rank})
	phase = PHASE_ROUND_RESULT


func _place_by_health(survivors: Array[Player]) -> void:
	var order: Array[Player] = survivors.duplicate()
	order.sort_custom(func(x: Player, y: Player) -> bool:
		return x.health > y.health if x.health != y.health else x.id < y.id)
	for i: int in order.size():
		order[i].place = i + 1
