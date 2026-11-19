# ダメージ計算。負けた人のダメージ = A × 順位 + B × 差（docs/design.md「ダメージ計算」）。
# 順位は残り体力での今の順位（1が最上位、同じ体力は同じ順位）。差は勝った側の機体の残りHPの割合。
extends RefCounted


## health：ID → 体力（生き残っている人だけ）。返す辞書：ID → 順位
static func ranks(health: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id: int in health:
		var better: int = 0
		for other: int in health:
			if float(health[other]) > float(health[id]):
				better += 1
		out[id] = better + 1
	return out


## 負けた人のダメージ（整数）
static func loss_damage(rank: int, margin: float, cfg: Dictionary) -> int:
	var parts: Dictionary = loss_parts(rank, margin, cfg)
	return maxi(0, roundi(float(parts["rank"]) + float(parts["margin"])))


## 負けた人のダメージの内訳（丸める前）。"rank"：順位の分、"margin"：差の分（画面で内訳を見せる用）
static func loss_parts(rank: int, margin: float, cfg: Dictionary) -> Dictionary:
	var m: float = clampf(margin, 0.0, 1.0) if is_finite(margin) else 0.0
	return {"rank": float(cfg["rank_coef"]) * rank, "margin": float(cfg["margin_coef"]) * m}


## 引き分けのときのダメージ（整数）
static func draw_damage(rank: int, cfg: Dictionary) -> int:
	if str(cfg["on_draw"]) == "rank_only":
		return maxi(0, roundi(float(cfg["rank_coef"]) * rank))
	return 0
