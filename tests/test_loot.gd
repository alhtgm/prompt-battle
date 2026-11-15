# パーツの抽選のテスト。段階1の完成の目安「同じ種で同じパーツが同じステータスで出る」を確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const PartInstance := preload("res://core/part_instance.gd")

const KINDS: Array[String] = ["frame", "weapon", "skill"]


## 種から「開始時の選出」と同じ形で各種類のパーツを出し、比べやすい形にして返す
func _draw(data: GameData, seed_value: int) -> Array:
	var rng := Rng.new(seed_value)
	var count: int = int(data.rule("draft.choices_per_kind"))
	var out: Array = []
	var uid: int = 1
	for kind: String in KINDS:
		var sub: Rng = rng.fork("draft/" + kind)
		for inst: PartInstance in Loot.roll_offer(data, kind, count, sub, uid):
			out.append(inst.to_dict())
		uid += count
	return out


func _load() -> GameData:
	var data := GameData.new()
	data.load_dir()
	return data


func test_same_seed_gives_same_parts_and_stats() -> void:
	# データも乱数も作り直して、別々に出しても同じになること
	for seed_value: int in [0, 1, 42, 12345, 987654321, -5, 9007199254740991]:
		var first: Array = _draw(_load(), seed_value)
		var second: Array = _draw(_load(), seed_value)
		check_eq(first.size(), 15, "種 %d：各種類5つずつ出る" % seed_value)
		check(same(first, second), "種 %d：同じパーツが同じステータスで出る" % seed_value)


func test_different_seeds_give_different_results() -> void:
	var data := _load()
	var results: Dictionary = {}
	for seed_value: int in 50:
		results[JSON.stringify(_draw(data, seed_value))] = true
	check(results.size() >= 49, "違う種ならほぼ毎回違う結果になる（50種中 %d 通り）" % results.size())


func test_offer_has_no_duplicate_types() -> void:
	var data := _load()
	for seed_value: int in 200:
		var drawn: Array = _draw(data, seed_value)
		var ids: Dictionary = {}
		for d: Dictionary in drawn:
			ids[d["def_id"]] = true
		check_eq(ids.size(), drawn.size(), "種 %d：選出に同じ型が重ならない" % seed_value)


func test_rolled_stats_stay_in_range() -> void:
	var data := _load()
	var bad: int = 0
	for seed_value: int in 300:
		var rng := Rng.new(seed_value)
		for d: GameData.PartDef in data.parts:
			var inst: PartInstance = Loot.roll_part(d, rng, 1)
			for s: String in d.stat_names():
				var r: GameData.StatRange = d.stats[s]
				var v: float = inst.get_stat(s, NAN)
				var ok: bool = is_finite(v) and v >= r.min_value and v <= r.max_value
				if ok and r.step > 0.0:
					var k: float = v / r.step
					ok = absf(k - roundf(k)) < 1e-6 or v == r.min_value or v == r.max_value
				if not ok:
					bad += 1
					if bad <= 5:
						check(false, "種 %d：%s.%s = %s が範囲 %s〜%s か刻み %s から外れた" \
							% [seed_value, d.id, s, v, r.min_value, r.max_value, r.step])
	check_eq(bad, 0, "範囲外・刻み外のステータスの数")


func test_stats_actually_vary() -> void:
	var data := _load()
	var def: GameData.PartDef = data.get_part("frame_standard")
	var seen: Dictionary = {}
	for seed_value: int in 100:
		seen[Loot.roll_part(def, Rng.new(seed_value), 1).get_stat("hp")] = true
	check(seen.size() >= 20, "同じ型でもステータスが変わる（HP が %d 通り）" % seen.size())


func test_instance_keeps_type_and_uid() -> void:
	var data := _load()
	var inst: PartInstance = Loot.roll_part(data.get_part("weapon_hammer"), Rng.new(5), 77)
	check_eq(inst.uid, 77, "固有IDが入る")
	check_eq(inst.def_id, "weapon_hammer", "型のIDが入る")
	check_eq(inst.kind, "weapon", "種類が入る")
	check(inst.stats.has("damage") and inst.stats.has("knockback"), "武器のステータスが入る")
