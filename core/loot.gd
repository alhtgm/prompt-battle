# パーツの抽選。型を選び、ステータスを範囲内で抽選して実物を作る。
# 開始時の選出、ラウンド後の配布、パークの候補もここで作る。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")


## 型から実物を1つ作る。ステータスは名前順に抽選する（順番を固定して再現性を保つ）
static func roll_part(def: GameData.PartDef, rng: Rng, uid: int) -> PartInstance:
	var inst := PartInstance.new()
	inst.uid = uid
	inst.def_id = def.id
	inst.kind = def.kind
	for stat_name: String in def.stat_names():
		inst.stats[stat_name] = roll_stat(def.stats[stat_name], rng)
	return inst


## 小さいほど良いステータス（抽選の良さを測るときに向きを逆にする）
const LOWER_IS_BETTER: Array[String] = ["speed_penalty"]


## 抽選の良さ（0〜1）。ステータスごとに、範囲のどのあたりに入ったかの平均。振れないステータスしかなければ 0.5
static func roll_quality(def: GameData.PartDef, stats: Dictionary) -> float:
	var total: float = 0.0
	var n: int = 0
	for stat_name: String in def.stat_names():
		var r: GameData.StatRange = def.stats[stat_name]
		if r.max_value <= r.min_value or not stats.has(stat_name):
			continue
		var t: float = clampf((float(stats[stat_name]) - r.min_value) / (r.max_value - r.min_value), 0.0, 1.0)
		total += 1.0 - t if LOWER_IS_BETTER.has(stat_name) else t
		n += 1
	return total / float(n) if n > 0 else 0.5


## パーツの性能を引き直した値（元のパーツは変えない）
static func reroll_stats(def: GameData.PartDef, rng: Rng) -> Dictionary:
	var out: Dictionary = {}
	for stat_name: String in def.stat_names():
		out[stat_name] = roll_stat(def.stats[stat_name], rng)
	return out


## 範囲内で1つの値を抽選し、刻みに丸める
static func roll_stat(r: GameData.StatRange, rng: Rng) -> float:
	var v: float = rng.randf_range(r.min_value, r.max_value)
	if r.step > 0.0:
		v = snappedf(v, r.step)
	return clampf(v, r.min_value, r.max_value)


## ある種類の型から重複なしで count 個選び、それぞれ実物にする（開始時の選出などに使う）
## uid は first_uid から順に振る
static func roll_offer(data: GameData, kind: String, count: int, rng: Rng, first_uid: int) -> Array[PartInstance]:
	var defs: Array = rng.sample(data.defs_of_kind(kind), count)
	var out: Array[PartInstance] = []
	for i: int in defs.size():
		out.append(roll_part(defs[i], rng, first_uid + i))
	return out


## 開始時の選出：種類ごとに per_kind 個。返す辞書：種類 → 実物の配列
static func draft_offer(data: GameData, rng: Rng, per_kind: int, first_uid: int) -> Dictionary:
	var out: Dictionary = {}
	var uid: int = first_uid
	for kind: String in GameData.KINDS:
		out[kind] = roll_offer(data, kind, per_kind, rng, uid)
		uid += per_kind
	return out


## ラウンド後の配布：count 個。各種類を min_per_kind 個以上含め、残りは種類も含めてランダム
static func deal_round(data: GameData, rng: Rng, count: int, min_per_kind: int, first_uid: int) -> Array[PartInstance]:
	var kinds: Array[String] = []
	for kind: String in GameData.KINDS:
		for k: int in min_per_kind:
			kinds.append(kind)
	while kinds.size() < count:
		kinds.append(rng.pick(GameData.KINDS))
	var out: Array[PartInstance] = []
	for i: int in kinds.size():
		var def: GameData.PartDef = rng.pick(data.defs_of_kind(kinds[i]))
		out.append(roll_part(def, rng, first_uid + i))
	return out


## パークの候補：重ならないように count 個のID
static func perk_choices(data: GameData, rng: Rng, count: int) -> Array[String]:
	var ids: Array = []
	for p: GameData.PerkDef in data.perks:
		ids.append(p.id)
	var out: Array[String] = []
	out.assign(rng.sample(ids, count))
	return out


## ランダムな機体を1つ組む。武器は1つ以上、どちらもフレームの枠まで（型は重ならない）
## uid は first_uid から順に振る。テストやCPUの仮の機体に使う
static func random_build(data: GameData, rng: Rng, first_uid: int) -> Build:
	var b := Build.new()
	var uid: int = first_uid
	var fdef: GameData.PartDef = rng.pick(data.defs_of_kind(GameData.KIND_FRAME))
	b.frame = roll_part(fdef, rng, uid)
	uid += 1
	var n_weapons: int = rng.randi_range(1, fdef.weapon_slots)
	for d: GameData.PartDef in rng.sample(data.defs_of_kind(GameData.KIND_WEAPON), n_weapons):
		b.weapons.append(roll_part(d, rng, uid))
		uid += 1
	var n_skills: int = rng.randi_range(0, fdef.skill_slots)
	for d: GameData.PartDef in rng.sample(data.defs_of_kind(GameData.KIND_SKILL), n_skills):
		b.skills.append(roll_part(d, rng, uid))
		uid += 1
	return b
