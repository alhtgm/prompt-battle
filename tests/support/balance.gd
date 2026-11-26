# 勝ち方の偏りを測る手伝い。ランダムな機体同士の試合を回して数え、docs/design.md の「偏りすぎない」の基準①〜④と比べる。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const H := preload("res://tests/support/battle_helpers.gd")

## パーツの勝率を見るのに必要な出場数
const MIN_APPEARANCES: int = 40
## 自爆で相打ちは、自爆装置を持った機体が負けかけたときだけ起きる珍しい決着なので、下限は見ない
const RARE_REASONS: Array[String] = [BattleSim.REASON_SELF_DESTRUCT]


## 種 seed_base から seed_base + count - 1 までの試合を stage で回して数える
static func measure(data: GameData, stage: Dictionary, count: int, seed_base: int) -> Dictionary:
	var reasons: Dictionary = {BattleSim.REASON_DESTROYED: 0, BattleSim.REASON_PIT: 0, BattleSim.REASON_TIME: 0,
		BattleSim.REASON_SELF_DESTRUCT: 0}
	var wins: Array[int] = [0, 0]
	var draws: int = 0
	var part_win: Dictionary = {}
	var part_games: Dictionary = {}
	var total_time: float = 0.0
	for k: int in count:
		var sim: BattleSim = H.make_match(data, seed_base + k, stage)
		var res: Dictionary = sim.run_to_end()
		reasons[res["reason"]] += 1
		total_time += float(res["time"])
		var w: int = res["winner"]
		if w < 0:
			draws += 1
			continue
		wins[w] += 1
		for side: int in 2:
			var ids: Dictionary = {}
			for id: String in sim.robots[side].build.part_def_ids():
				ids[id] = true
			for id: String in ids:
				part_games[id] = part_games.get(id, 0) + 1
				if side == w:
					part_win[id] = part_win.get(id, 0) + 1
	return {"count": count, "reasons": reasons, "wins": wins, "draws": draws,
		"part_win": part_win, "part_games": part_games, "avg_time": total_time / maxf(1.0, float(count))}


## 数えた結果を1〜2行の文にする
static func summary(stats: Dictionary) -> PackedStringArray:
	var r: Dictionary = stats["reasons"]
	var wins: Array = stats["wins"]
	var decided: int = int(wins[0]) + int(wins[1])
	var lines := PackedStringArray()
	lines.append("%d試合 破壊 %d / 穴 %d / 時間切れ %d / 自爆で相打ち %d / 引き分け %d / 先の側の勝率 %.1f%% / 平均 %.1f 秒" % [
		stats["count"], r[BattleSim.REASON_DESTROYED], r[BattleSim.REASON_PIT],
		r[BattleSim.REASON_TIME], r[BattleSim.REASON_SELF_DESTRUCT], stats["draws"],
		100.0 * int(wins[0]) / maxf(1.0, decided), stats["avg_time"]])
	var games: Dictionary = stats["part_games"]
	var ids: Array = games.keys()
	ids.sort()
	var parts := PackedStringArray()
	for id: String in ids:
		parts.append("%s %d%%(%d)" % [id, roundi(100.0 * stats["part_win"].get(id, 0) / games[id]), games[id]])
	lines.append("勝率 " + ", ".join(parts))
	return lines


## 基準①〜④を満たさないものを、1つずつ文にして返す（空なら全部満たす）
static func problems(data: GameData, stats: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var n: float = float(stats["count"])
	var reasons: Dictionary = stats["reasons"]
	# ① 決着の種類：どれも 5% 以上、80% 以下
	for r: String in reasons:
		var ratio: float = reasons[r] / n
		var low: float = 0.0 if RARE_REASONS.has(r) else 0.05
		if ratio < low or ratio > 0.80:
			out.append("① 決着「%s」の割合が %d〜80%% から外れる（%.1f%%）" % [r, roundi(low * 100.0), ratio * 100.0])
	# ② 先に置かれた側の勝率が 40〜60%
	var wins: Array = stats["wins"]
	var side_a: float = int(wins[0]) / maxf(1.0, int(wins[0]) + int(wins[1]))
	if side_a < 0.40 or side_a > 0.60:
		out.append("② 先の側の勝率が 40〜60%% から外れる（%.1f%%）" % (side_a * 100.0))
	# ③ 引き分けが 20% 未満
	if stats["draws"] / n >= 0.20:
		out.append("③ 引き分けが 20%% 以上（%.1f%%）" % (100.0 * stats["draws"] / n))
	# ④ どのフレーム・武器も勝率 25〜75%（スキルは見ない）
	var games: Dictionary = stats["part_games"]
	var ids: Array = games.keys()
	ids.sort()
	for id: String in ids:
		if data.get_part(id).kind == GameData.KIND_SKILL:
			continue
		var g: int = games[id]
		if g < MIN_APPEARANCES:
			out.append("④ %s の出場数が %d 未満（%d）" % [id, MIN_APPEARANCES, g])
			continue
		var rate: float = float(stats["part_win"].get(id, 0)) / g
		if rate < 0.25 or rate > 0.75:
			out.append("④ %s の勝率が 25〜75%% から外れる（%.1f%%）" % [id, rate * 100.0])
	return out
