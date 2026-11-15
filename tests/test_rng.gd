# core/rng.gd のテスト。同じ種なら同じ並び、子の乱数は名前と種だけで決まることを確かめる。
extends "res://tests/support/test_case.gd"

const Rng := preload("res://core/rng.gd")


func _sequence(rng: Rng, n: int) -> Array[float]:
	var out: Array[float] = []
	for i: int in n:
		out.append(rng.randf())
	return out


func test_same_seed_same_sequence() -> void:
	check_eq(_sequence(Rng.new(12345), 1000), _sequence(Rng.new(12345), 1000), "同じ種なら同じ並び")


func test_different_seed_different_sequence() -> void:
	check(not same(_sequence(Rng.new(1), 50), _sequence(Rng.new(2), 50)), "違う種なら違う並び")


func test_fork_is_deterministic_and_independent_of_parent_usage() -> void:
	var a := Rng.new(777)
	var b := Rng.new(777)
	for i: int in 37:
		b.randf()  # 親を使ってから子を作っても同じ子になる
	var ca: Rng = a.fork("battle/1")
	var cb: Rng = b.fork("battle/1")
	check_eq(ca.get_seed(), cb.get_seed(), "子の種は親の使い方に左右されない")
	check_eq(_sequence(ca, 100), _sequence(cb, 100), "子の並びも同じ")


func test_fork_labels_and_seeds_differ() -> void:
	var r := Rng.new(777)
	check(r.fork("a").get_seed() != r.fork("b").get_seed(), "名前が違えば子の種も違う")
	check(Rng.new(1).fork("a").get_seed() != Rng.new(2).fork("a").get_seed(), "親の種が違えば子の種も違う")
	check(r.fork("a").get_seed() != r.get_seed(), "子の種は親と違う")


func test_ranges() -> void:
	var r := Rng.new(42)
	var seen_lo: bool = false
	var seen_hi: bool = false
	for i: int in 5000:
		var f: float = r.randf()
		check(f >= 0.0 and f < 1.0, "randf は 0 以上 1 未満")
		var n: int = r.randi_range(3, 7)
		check(n >= 3 and n <= 7, "randi_range は両端を含む範囲内")
		seen_lo = seen_lo or n == 3
		seen_hi = seen_hi or n == 7
		var g: float = r.randf_range(-2.0, 5.0)
		check(g >= -2.0 and g <= 5.0, "randf_range は範囲内")
	check(seen_lo and seen_hi, "randi_range の両端が出る")


func test_shuffle_and_sample() -> void:
	var base: Array = range(20)
	var a: Array = base.duplicate()
	var b: Array = base.duplicate()
	Rng.new(9).shuffle(a)
	Rng.new(9).shuffle(b)
	check_eq(a, b, "同じ種なら同じ並べ替え")
	var sorted_a: Array = a.duplicate()
	sorted_a.sort()
	check_eq(sorted_a, base, "並べ替えても中身は同じ")
	check(not same(a, base), "並べ替えで順番が変わる")

	var s: Array = Rng.new(3).sample(base, 5)
	check_eq(s.size(), 5, "sample は指定した数だけ返す")
	var uniq: Dictionary = {}
	for v: Variant in s:
		uniq[v] = true
	check_eq(uniq.size(), 5, "sample は重複しない")
	check_eq(base, range(20), "sample は元の配列を変えない")
	check_eq(Rng.new(3).sample([1, 2], 5).size(), 2, "数が足りなければあるだけ返す")
	check(Rng.new(3).pick([]) == null, "空の配列から pick すると null")


func test_state_save_and_restore() -> void:
	var r := Rng.new(2024)
	r.randf()
	var saved: int = r.get_state()
	var first: Array[float] = _sequence(r, 20)
	r.set_state(saved)
	check_eq(_sequence(r, 20), first, "状態を戻せば同じ並びがもう一度出る")
