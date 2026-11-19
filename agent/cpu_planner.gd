# CPUプレイヤーの判断：開始時のパーツ選び、組み立てとプロンプト、パーク選び、スクラップの使い方。
# 人間が時間内に決めなかったときの代わりにも使う。乱数は渡された Rng だけを使う。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Loot := preload("res://core/loot.gd")

## 機体に合わせて選ぶプロンプト
const PROMPT_SHOOTER: String = "距離をとって撃ちまくれ。弾が切れたら突っ込め。HPが減ったら修理に行け"
const PROMPT_PUSHER: String = "相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ"
const PROMPTS_MELEE: Array[String] = [
	"とにかく突撃して殴れ",
	"相手の後ろに回り込んで攻めろ",
	"ガンガン攻めろ。相手が穴の近くなら押し込め",
	"慎重に戦え。HPが減ったら修理に行け",
]


## 開始時の選出から種類ごとに1つ選ぶ。返す辞書：種類 → uid
static func pick_draft(offer: Dictionary, rng: Rng) -> Dictionary:
	var out: Dictionary = {}
	for kind: String in GameData.KINDS:
		var p: PartInstance = rng.pick(offer[kind])
		out[kind] = p.uid
	return out


## 手持ちから機体を組み、プロンプトを決める。返す辞書：frame（uid）, weapons（uid の配列）, skills, prompt
static func plan_build(data: GameData, hand: Array[PartInstance], extra_weapons: int, extra_skills: int,
		max_chars: int, rng: Rng) -> Dictionary:
	var frames: Array[PartInstance] = []
	var weapons: Array[PartInstance] = []
	var skills: Array[PartInstance] = []
	for p: PartInstance in hand:
		match p.kind:
			GameData.KIND_FRAME: frames.append(p)
			GameData.KIND_WEAPON: weapons.append(p)
			GameData.KIND_SKILL: skills.append(p)

	# フレーム：HPと速さと枠の多さで点を付け、少しだけ気まぐれを混ぜる
	var cfg: Dictionary = data.rules["agent"]["cpu"]
	var whim: float = float(cfg["frame_whim"])
	var frame: PartInstance = null
	var best: float = -INF
	for f: PartInstance in frames:
		var def: GameData.PartDef = data.get_part(f.def_id)
		var score: float = f.get_stat("hp") * (1.0 - f.get_stat("speed_penalty")) \
			* (1.0 + float(cfg["frame_slot_weight"]) * (def.weapon_slots + def.skill_slots)) \
			* rng.randf_range(1.0 - whim, 1.0 + whim)
		if score > best:
			best = score
			frame = f
	var fdef: GameData.PartDef = data.get_part(frame.def_id)

	var chosen_w: Array[PartInstance] = _best_parts(data, weapons, fdef.weapon_slots + extra_weapons, rng)
	var chosen_s: Array[PartInstance] = _best_parts(data, skills, fdef.skill_slots + extra_skills, rng)

	var has_gun: bool = false
	var has_ram: bool = false
	for w: PartInstance in chosen_w:
		var b: String = data.get_part(w.def_id).behavior
		has_gun = has_gun or b == "shoot"
		has_ram = has_ram or b == "ram"
	var prompt: String
	if has_gun and chosen_w.size() == 1:
		prompt = PROMPT_SHOOTER
	elif has_ram:
		prompt = PROMPT_PUSHER
	else:
		prompt = rng.pick(PROMPTS_MELEE)

	var w_uids: Array[int] = []
	for w: PartInstance in chosen_w:
		w_uids.append(w.uid)
	var s_uids: Array[int] = []
	for s: PartInstance in chosen_s:
		s_uids.append(s.uid)
	return {"frame": frame.uid, "weapons": w_uids, "skills": s_uids, "prompt": prompt.left(max_chars)}


## 当たりの良さ（型の基準の真ん中に比べた抽選の良さ）で並べ、型が重ならないように上から count 個
static func _best_parts(data: GameData, parts: Array[PartInstance], count: int, rng: Rng) -> Array[PartInstance]:
	var scored: Array = []
	for p: PartInstance in parts:
		var def: GameData.PartDef = data.get_part(p.def_id)
		var quality: float = 0.0
		for s: String in def.stat_names():
			var r: GameData.StatRange = def.stats[s]
			var mid: float = (r.min_value + r.max_value) * 0.5
			quality += p.get_stat(s) / mid if mid > 0.0 else 1.0
		quality = quality / maxf(1.0, def.stats.size()) \
			+ rng.randf_range(0.0, float(data.rules["agent"]["cpu"]["part_whim"]))
		scored.append([quality, p.uid, p])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	var out: Array[PartInstance] = []
	var used_defs: Dictionary = {}
	for row: Array in scored:
		if out.size() >= count:
			break
		var p: PartInstance = row[2]
		if used_defs.has(p.def_id):
			continue
		used_defs[p.def_id] = true
		out.append(p)
	return out


## パークを1つ選ぶ
static func pick_perk(choices: Array[String], rng: Rng) -> String:
	return rng.pick(choices) if not choices.is_empty() else ""


## スクラップの使い方。付けていないパーツは全部解体し、付けているパーツを抽選の悪い順に再抽選する
## 返す辞書：{"scrap": 解体する uid の配列, "reroll": 再抽選する uid の配列（スクラップが足りなくなったら試合側で止める）}
static func plan_upkeep(data: GameData, hand: Array[PartInstance], equipped_uids: Array, _rng: Rng) -> Dictionary:
	var scrap: Array = []
	var equipped: Array = []
	for p: PartInstance in hand:
		if equipped_uids.has(p.uid):
			equipped.append([Loot.roll_quality(data.get_part(p.def_id), p.stats), p.uid])
		else:
			scrap.append(p.uid)
	equipped.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var reroll: Array = []
	for row: Array in equipped:
		reroll.append(row[1])
	return {"scrap": scrap, "reroll": reroll}


## 再抽選の結果を取るか。抽選の良さが上がったときだけ新しい性能にする
static func accept_reroll(data: GameData, part: PartInstance, new_stats: Dictionary) -> bool:
	var def: GameData.PartDef = data.get_part(part.def_id)
	return Loot.roll_quality(def, new_stats) > Loot.roll_quality(def, part.stats)
