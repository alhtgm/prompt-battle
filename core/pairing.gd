# ペア作り。生き残っている人を並べ替え、直前に当たった相手と組まない組み合わせを乱数で探す。
# 見つからなければ条件を外して組む。奇数のときは余った1人を返す（記録の再生と戦わせる）。
extends RefCounted

const Rng := preload("res://core/rng.gd")


## alive_ids：生き残っている人のID。last_opponent：ID → 直前に当たった相手のID
## 返す辞書：pairs（[a, b] の配列）, leftover（余った人のID、いなければ -1）, relaxed（条件を外したか）
static func make_pairs(alive_ids: Array[int], last_opponent: Dictionary, rng: Rng, attempts: int) -> Dictionary:
	var order: Array = alive_ids.duplicate()
	order.sort()  # 呼び出し側の並びに左右されないようにする
	var best: Array = []
	for k: int in maxi(1, attempts):
		var trial: Array = order.duplicate()
		rng.shuffle(trial)
		best = trial
		if _no_repeat(trial, last_opponent):
			return _to_result(trial, false)
	return _to_result(best, not _no_repeat(best, last_opponent))


static func _no_repeat(order: Array, last_opponent: Dictionary) -> bool:
	for i: int in range(0, order.size() - 1, 2):
		var a: int = order[i]
		var b: int = order[i + 1]
		if last_opponent.get(a, -1) == b or last_opponent.get(b, -1) == a:
			return false
	return true


static func _to_result(order: Array, relaxed: bool) -> Dictionary:
	var pairs: Array = []
	for i: int in range(0, order.size() - 1, 2):
		pairs.append([order[i], order[i + 1]])
	var leftover: int = order[order.size() - 1] if order.size() % 2 == 1 else -1
	return {"pairs": pairs, "leftover": leftover, "relaxed": relaxed}
