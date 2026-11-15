# パーツの抽選。型を選び、ステータスを範囲内で抽選して実物を作る。
# ラウンド後の配布とパーク候補は段階3で足す。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const PartInstance := preload("res://core/part_instance.gd")


## 型から実物を1つ作る。ステータスは名前順に抽選する（順番を固定して再現性を保つ）
static func roll_part(def: GameData.PartDef, rng: Rng, uid: int) -> PartInstance:
	var inst := PartInstance.new()
	inst.uid = uid
	inst.def_id = def.id
	inst.kind = def.kind
	for stat_name: String in def.stat_names():
		inst.stats[stat_name] = roll_stat(def.stats[stat_name], rng)
	return inst


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
