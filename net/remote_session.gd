# 通信対戦のクライアントが持つ、試合（MatchSession）の写し。サーバーから届く状態を組み立て直し、同じ名前で読めるようにする。
# 操作（パーツ選び・組み立て・パーク選び・スクラップ）はサーバーへ送るだけで、締め切りや進行はサーバーが決める（finish_* は何もしない）。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")
const Player := preload("res://core/player.gd")
const Protocol := preload("res://net/protocol.gd")
const Loot := preload("res://core/loot.gd")
const RemoteSim := preload("res://net/remote_sim.gd")

const GHOST_ID: int = -1


## 今のラウンドのバトル1つ（MatchSession.Battle と同じ項目）
class RemoteBattle:
	var a: int = 0
	var b: int = 0
	var ghost_of: int = -1
	var prompts: Array = ["", ""]
	var sim: RemoteSim


var data: GameData
var players: Array[Player] = []
var phase: String = ""
var round_no: int = 0
var my_id: int = -1
var draft_offer: Dictionary = {}
var battles: Array[RemoteBattle] = []
var history: Array = []
var phase_time_left: float = 0.0

## メッセージを送る関数（type: String, payload: Dictionary）
var _send: Callable
var _battle_round: int = -1
var _lineup: String = ""


func _init(game_data: GameData, send: Callable) -> void:
	data = game_data
	_send = send


func is_online() -> bool:
	return true


func is_finished() -> bool:
	return phase == "finished"


func get_player(id: int) -> Player:
	return players[id] if id >= 0 and id < players.size() else null


func alive_players() -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in players:
		if p.alive:
			out.append(p)
	return out


func battle_of(player_id: int) -> RemoteBattle:
	for bt: RemoteBattle in battles:
		if bt.a == player_id or bt.b == player_id:
			return bt
	return null


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


# ---- サーバーから届いたものを当てはめる ----

func apply_state(st: Dictionary) -> void:
	phase = str(st.get("phase", ""))
	round_no = int(st.get("round_no", 0))
	my_id = int(st.get("my_id", -1))
	phase_time_left = float(st.get("time_left", 0.0))
	history = st.get("history", [])

	var ps: Array[Player] = []
	for d: Dictionary in st.get("players", []):
		var p := Player.new()
		p.id = int(d["id"])
		p.name = str(d["name"])
		p.is_human = bool(d["is_human"])
		p.health = float(d["health"])
		p.alive = bool(d["alive"])
		p.place = int(d["place"])
		p.perks.assign(d["perks"])
		p.eliminated_round = int(d["eliminated_round"])
		ps.append(p)
	players = ps
	var me: Player = get_player(my_id)
	var mine: Dictionary = st.get("me", {})
	if me != null and not mine.is_empty():
		for pd: Dictionary in mine.get("hand", []):
			me.hand.append(PartInstance.from_dict(pd))
		for uid: Variant in mine.get("new_parts", []):
			var part: PartInstance = me.find_part(int(uid))
			if part != null:
				me.new_parts.append(part)
		var b: Variant = mine.get("build")
		if b is Dictionary:
			me.build = _build_from_uids(me, b)
		me.prompt = str(mine.get("prompt", ""))
		me.perk_choices.assign(mine.get("perk_choices", []))
		me.done_this_phase = bool(mine.get("done", false))
		me.scrap = int(mine.get("scrap", 0))
		var pr: Variant = mine.get("pending_reroll", {})
		me.pending_reroll = (pr as Dictionary).duplicate(true) if pr is Dictionary else {}
		me.perk_rerolls_used = int(mine.get("perk_rerolls_used", 0))

	draft_offer = {}
	var offer: Dictionary = st.get("draft_offer", {})
	for kind: Variant in offer:
		var parts: Array[PartInstance] = []
		for pd: Dictionary in offer[kind]:
			parts.append(PartInstance.from_dict(pd))
		draft_offer[str(kind)] = parts

	# バトルの顔ぶれが変わったら作り直す。同じ顔ぶれの間は動きを持ち越す
	# （組み立ての段階では、サーバーはまだ前のラウンドの顔ぶれを持っているので、ラウンド番号ではなく顔ぶれで比べる）
	var bs: Array = st.get("battles", [])
	var lineup: String = ""
	for d: Dictionary in bs:
		lineup += "%d/%d/%d;" % [int(d["a"]), int(d["b"]), int(d["ghost_of"])]
	if round_no != _battle_round or lineup != _lineup:
		_lineup = lineup
		battles = []
		for d: Dictionary in bs:
			var bt := RemoteBattle.new()
			bt.a = int(d["a"])
			bt.b = int(d["b"])
			bt.ghost_of = int(d["ghost_of"])
			bt.sim = RemoteSim.new()
			bt.sim.setup(data, [Build.from_dict(d["builds"][0]), Build.from_dict(d["builds"][1])], d["names"])
			battles.append(bt)
		_battle_round = round_no
	for k: int in mini(bs.size(), battles.size()):
		battles[k].prompts = bs[k]["prompts"]


func apply_frame(f: Dictionary) -> void:
	if int(f.get("round_no", -1)) != round_no:
		return
	var bs: Array = f.get("battles", [])
	for k: int in mini(bs.size(), battles.size()):
		battles[k].sim.apply_frame(bs[k])


## 描くたびに呼ぶ（残り時間を減らし、バトルの動きを滑らかにつなぐ）
func update(delta: float) -> void:
	phase_time_left = maxf(0.0, phase_time_left - delta)
	for bt: RemoteBattle in battles:
		bt.sim.advance(delta)


# ---- 操作（サーバーへ送る。その場で分かる間違いはここで返す） ----

func draft_pick(_player_id: int, picks: Dictionary) -> String:
	for kind: String in GameData.KINDS:
		if not picks.has(kind):
			return "%s を選んでいない" % kind
	_send.call(Protocol.DRAFT_PICK, {"picks": picks})
	_mark_done()
	return ""


func submit_build(_player_id: int, frame_uid: int, weapon_uids: Array, skill_uids: Array, prompt: String) -> String:
	var me: Player = get_player(my_id)
	if me == null or not me.alive:
		return "参加していない"
	var r: Dictionary = me.assemble_build(data, frame_uid, weapon_uids, skill_uids, prompt)
	if not str(r["error"]).is_empty():
		return r["error"]
	_send.call(Protocol.SUBMIT_BUILD, {"frame": frame_uid, "weapons": weapon_uids, "skills": skill_uids, "prompt": prompt})
	me.build = r["build"]
	me.prompt = prompt
	_mark_done()
	return ""


## 出撃できるかだけを調べる（状態は変えない）。確かめ方は試合側（core）と同じ
func check_build(_player_id: int, frame_uid: int, weapon_uids: Array, skill_uids: Array, prompt: String) -> String:
	var me: Player = get_player(my_id)
	if me == null or not me.alive:
		return "参加していない"
	return me.assemble_build(data, frame_uid, weapon_uids, skill_uids, prompt)["error"]


func choose_perk(_player_id: int, perk_id: String) -> String:
	var me: Player = get_player(my_id)
	if me == null or not me.alive:
		return "参加していない"
	if me.done_this_phase:
		return "このラウンドのパークはもう選んだ"
	if not me.perk_choices.has(perk_id):
		return "候補にないパーク"
	_send.call(Protocol.CHOOSE_PERK, {"perk": perk_id})
	_mark_done()
	return ""


## スクラップが使えるラウンドか（試合と同じ決まり）
func scrap_unlocked() -> bool:
	return round_no >= int(data.rule("scrap.unlock_round"))


## パーツを解体したときにもらえるスクラップ（試合と同じ計算。表示用）
func scrap_value(part: PartInstance) -> int:
	var v: int = int(data.rule("scrap.value." + part.kind))
	var def: GameData.PartDef = data.get_part(part.def_id)
	if def != null and Loot.roll_quality(def, part.stats) > 0.5:
		v += int(data.rule("scrap.high_roll_bonus"))
	return v


## スクラップの操作。結果（増減や再抽選の新しい性能）はサーバーから届く状態で分かる
func scrap_part(_player_id: int, uid: int) -> String:
	_send.call(Protocol.SCRAP_PART, {"uid": uid})
	return ""


func reroll_part(_player_id: int, uid: int) -> String:
	var me: Player = get_player(my_id)
	var cost: int = int(data.rule("scrap.reroll_part_cost"))
	if me != null and me.scrap < cost:
		return "スクラップが足りない（%d / %d）" % [me.scrap, cost]
	_send.call(Protocol.REROLL_PART, {"uid": uid})
	return ""


func resolve_reroll(_player_id: int, take_new: bool) -> String:
	var me: Player = get_player(my_id)
	if me != null:
		me.pending_reroll = {}  # 次の状態が届くまでの間、選んだ画面を閉じておく
	_send.call(Protocol.RESOLVE_REROLL, {"take_new": take_new})
	return ""


func reroll_perk_choices(_player_id: int) -> String:
	var me: Player = get_player(my_id)
	var cost: int = int(data.rule("scrap.reroll_perks_cost"))
	if me != null and me.scrap < cost:
		return "スクラップが足りない（%d / %d）" % [me.scrap, cost]
	_send.call(Protocol.REROLL_PERKS, {})
	return ""


## 進行はサーバーが決めるので、クライアントからは何もしない
func finish_draft() -> void:
	pass


func finish_build() -> void:
	pass


func finish_round_result() -> void:
	pass


func finish_loot() -> void:
	pass


func run_battles_to_end() -> void:
	pass


func _mark_done() -> void:
	var me: Player = get_player(my_id)
	if me != null:
		me.done_this_phase = true


func _build_from_uids(me: Player, d: Dictionary) -> Build:
	var b := Build.new()
	b.frame = me.find_part(int(d.get("frame", -1)))
	for uid: Variant in d.get("weapons", []):
		var w: PartInstance = me.find_part(int(uid))
		if w != null:
			b.weapons.append(w)
	for uid: Variant in d.get("skills", []):
		var s: PartInstance = me.find_part(int(uid))
		if s != null:
			b.skills.append(s)
	return b
