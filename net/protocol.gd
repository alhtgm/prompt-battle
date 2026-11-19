# 通信対戦のやり取りの形。メッセージの種類、送る前後の変換（var_to_bytes。物は送らない）、サーバーが送る状態の組み立て。
# 状態の組み立ては「見る人」ごとに行い、見せてはいけないもの（生き残っている間の相手のプロンプト、ほかの人の手持ち）は入れない。
extends RefCounted

const VERSION: int = 1

# クライアント → サーバー
const HELLO: String = "hello"
const START: String = "start"
const DRAFT_PICK: String = "draft_pick"
const SUBMIT_BUILD: String = "submit_build"
const CHOOSE_PERK: String = "choose_perk"
const BRAIN_ANSWER: String = "brain_answer"

# サーバー → クライアント
const WELCOME: String = "welcome"
const REJECT: String = "reject"
const LOBBY: String = "lobby"
const STATE: String = "state"
const FRAME: String = "frame"
const BRAIN_BEGIN: String = "brain_begin"
const BRAIN_REQUEST: String = "brain_request"
const OP_ERROR: String = "op_error"


static func encode(type: String, payload: Dictionary = {}) -> PackedByteArray:
	var msg: Dictionary = payload.duplicate()
	msg["type"] = type
	return var_to_bytes(msg)


## 受け取ったバイト列を辞書に戻す。物（Object）は戻さないので、相手が何を送ってきても安全。壊れていれば空の辞書
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 8:  # 辞書なら必ずこれより長い。短いものは読む前にはじく
		return {}
	var v: Variant = bytes_to_var(bytes)
	return v if v is Dictionary and (v as Dictionary).get("type") is String else {}


## 試合の状態（バトルの動き以外）を、viewer_id のプレイヤーから見える分だけ組み立てる
## extra：サーバーが持つ段階の残り時間など
static func session_state(s: RefCounted, viewer_id: int, extra: Dictionary) -> Dictionary:
	var players: Array = []
	for p: Variant in s.players:
		players.append({
			"id": p.id, "name": p.name, "is_human": p.is_human, "health": p.health, "alive": p.alive,
			"place": p.place, "perks": p.perks.duplicate(), "eliminated_round": p.eliminated_round,
		})
	var me: Variant = s.get_player(viewer_id)
	var mine: Dictionary = {}
	if me != null:
		var hand: Array = []
		for part: Variant in me.hand:
			hand.append(part.to_dict())
		var new_parts: Array = []
		for part: Variant in me.new_parts:
			new_parts.append(part.uid)
		var build: Variant = null
		if me.build != null:
			var w: Array = []
			for part: Variant in me.build.weapons:
				w.append(part.uid)
			var sk: Array = []
			for part: Variant in me.build.skills:
				sk.append(part.uid)
			build = {"frame": me.build.frame.uid, "weapons": w, "skills": sk}
		mine = {"hand": hand, "new_parts": new_parts, "build": build, "prompt": me.prompt,
			"perk_choices": me.perk_choices.duplicate(), "done": me.done_this_phase}
	var offer: Dictionary = {}
	for kind: Variant in s.draft_offer:
		var parts: Array = []
		for part: Variant in s.draft_offer[kind]:
			parts.append(part.to_dict())
		offer[kind] = parts
	var viewer_alive: bool = me != null and me.alive
	var battles: Array = []
	for bt: Variant in s.battles:
		var prompts: Array = []
		var ids: Array = [bt.a, bt.b]
		for side: int in 2:
			# 生き残っている間は、自分のもの以外のプロンプトを送らない（企画メモ「観戦」）
			prompts.append(bt.prompts[side] if not viewer_alive or ids[side] == viewer_id else "")
		battles.append({
			"a": bt.a, "b": bt.b, "ghost_of": bt.ghost_of, "prompts": prompts,
			"names": [bt.sim.robots[0].name, bt.sim.robots[1].name],
			"builds": [bt.sim.robots[0].build.to_dict(), bt.sim.robots[1].build.to_dict()],
		})
	var st: Dictionary = {
		"phase": s.phase, "round_no": s.round_no, "my_id": viewer_id, "players": players, "me": mine,
		"draft_offer": offer, "history": s.history, "battles": battles,
	}
	st.merge(extra, true)
	return st


## バトルの動き（全バトル）。実況は log_from[k] 番目から最大 max_log 件
static func battle_frame(s: RefCounted, max_log: int) -> Dictionary:
	var battles: Array = []
	for bt: Variant in s.battles:
		var sim: Variant = bt.sim
		var robots: Array = []
		for r: Variant in sim.robots:
			var skills: Array = []
			for sk: Variant in r.skills:
				skills.append([sk.active_t, sk.cd, sk.charges_left])
			var ammo: Array = []
			for w: Variant in r.weapons:
				ammo.append(w.ammo)
			robots.append({
				"x": r.x, "z": r.z, "th": r.th, "hp": r.hp, "stun": r.stun, "fell": r.fell, "intent": r.intent,
				"say": r.say, "repairing": r.repairing, "repair_left": r.repair_left, "skills": skills, "ammo": ammo,
				"fuse": r.fuse, "fuse_total": r.fuse_total, "self_destructed": r.self_destructed,
				"hook": [r.hook_state, r.hook_x, r.hook_z, r.hook_slot], "flipped": r.flipped,
			})
		var shots: Array = []
		for sh: Variant in sim.shots:
			shots.append([sh.x, sh.z, sh.vx, sh.vz, sh.id, sh.def_id])
		var first: int = maxi(0, sim.log.size() - max_log)
		battles.append({
			"tick": sim.tick, "over": sim.over, "result": sim.result, "robots": robots, "shots": shots,
			"log_from": first, "log": sim.log.slice(first),
		})
	return {"round_no": s.round_no, "battles": battles}
