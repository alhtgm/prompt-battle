# 画面で使う文字の組み立て（パーツの説明、方針や決着の言葉、実況の行）。状態は読むだけ。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")

const KIND_LABELS: Dictionary = {"frame": "フレーム", "weapon": "武器", "skill": "スキル"}
const INTENT_LABELS: Dictionary = {
	"charge": "突撃", "flank": "回り込み", "keep_distance": "距離を取る", "retreat": "逃げる",
	"push_to_pit": "穴へ押し込む", "go_repair": "修理に向かう", "circle": "周りを回る", "hold": "その場で待つ",
}
const REASON_LABELS: Dictionary = {"destroyed": "破壊", "pit": "穴落ち", "time": "時間切れ"}
const STAT_LABELS: Dictionary = {
	"hp": "HP", "speed_penalty": "速度低下", "damage": "ダメージ", "knockback": "吹き飛ばし",
	"speed_mult": "速さ", "damage_cut": "被ダメ軽減", "heal": "回復", "stun_sec": "停止",
	"damage_mult": "与ダメ",
}
const BEHAVIOR_LABELS: Dictionary = {
	"grind": "触れている間削る", "strike": "叩く", "lift": "ひっくり返す", "ram": "体当たり",
	"shoot": "撃つ", "booster": "一時的に速くなる", "shield": "一時的に被ダメ軽減",
	"repair": "HP回復", "shockwave": "近くの相手を吹き飛ばす", "emp": "近くの相手を止める",
	"overclock": "一時的に与ダメ増",
}


## パーツの効果の説明（吹き出しに出す）。フレームは動き方を持たないので "frame" で引く
const BEHAVIOR_DESCRIPTIONS: Dictionary = {
	"frame": "機体の土台。HPと重さ、曲がりやすさ、付けられる武器とスキルの数が決まる。重いほど押し合いに強いが遅くなる。",
	"grind": "相手に触れている間、毎秒ダメージを与え続ける。張り付いて削り切る武器。",
	"strike": "前にいる相手を叩いて、ダメージと吹き飛ばしを与える。叩いたあとは少し間が空く。",
	"lift": "相手をすくい上げてひっくり返し、しばらく動けなくする。穴の近くで使うと強い。",
	"ram": "勢いをつけてぶつかったときだけ効く。速く当たるほど相手を大きく吹き飛ばす。",
	"shoot": "離れた相手に弾を撃つ。弾数に限りがあり、撃ち尽くすと使えない。",
	"booster": "一定時間、移動が速くなる。追いかけるのにも逃げるのにも使える。",
	"shield": "一定時間、受けるダメージを減らす。",
	"repair": "その場でHPを回復する。使える回数に限りがある。",
	"shockwave": "近くの相手をまとめて吹き飛ばす。穴へ押し出すのにも使える。",
	"emp": "近くの相手を一定時間止める。",
	"overclock": "一定時間、与えるダメージが増える。",
}
## 抽選しない固定値の名前
const FIXED_LABELS: Dictionary = {
	"mass": "重さ", "turn_rate_deg": "曲がる速さ", "cooldown_sec": "使える間隔", "arc_deg": "当たる角度",
	"reach": "届く距離", "range": "射程", "ammo": "弾数", "stun_sec": "止める時間", "min_speed": "必要な速さ",
	"duration_sec": "効果時間", "charges": "使える回数",
}
## 吹き出しに出す固定値（種類ごと、この順で）。値が 0 のものは出さない（charges の 0 は「無制限」として出す）
const FIXED_SHOWN: Dictionary = {
	"frame": ["mass", "turn_rate_deg"],
	"weapon": ["cooldown_sec", "range", "ammo", "stun_sec", "min_speed"],
	"skill": ["duration_sec", "cooldown_sec", "range", "charges"],
}
## 小さいほど良いステータス（吹き出しで、抽選の当たり外れの色を逆にする）
const LOWER_IS_BETTER: Array[String] = ["speed_penalty"]


## 固定値1つを読みやすい文字にする
static func fixed_text(key: String, v: float) -> String:
	var label: String = FIXED_LABELS.get(key, key)
	match key:
		"cooldown_sec", "duration_sec", "stun_sec":
			return "%s %.1f秒" % [label, v]
		"turn_rate_deg", "arc_deg":
			return "%s %d°" % [label, roundi(v)]
		"ammo":
			return "%s %d発" % [label, roundi(v)]
		"charges":
			return "%s %s" % [label, "無制限" if v <= 0.0 else "%d回" % roundi(v)]
		"mass":
			return "%s ×%.1f" % [label, v]
	return "%s %.1f" % [label, v]


## パーツの動き方の短い名前（カードに出す）。フレームは枠の数
static func part_tagline(data: GameData, p: PartInstance) -> String:
	var def: GameData.PartDef = data.get_part(p.def_id)
	if def.kind == GameData.KIND_FRAME:
		return "武器%d・スキル%d" % [def.weapon_slots, def.skill_slots]
	return BEHAVIOR_LABELS.get(def.behavior, def.behavior)


## パーツの効果の説明
static func part_description(data: GameData, p: PartInstance) -> String:
	var def: GameData.PartDef = data.get_part(p.def_id)
	var key: String = "frame" if def.kind == GameData.KIND_FRAME else def.behavior
	return BEHAVIOR_DESCRIPTIONS.get(key, "")


## 吹き出しに出す固定値の行
static func part_fixed_lines(data: GameData, p: PartInstance) -> PackedStringArray:
	var def: GameData.PartDef = data.get_part(p.def_id)
	var out := PackedStringArray()
	for key: String in FIXED_SHOWN.get(def.kind, []):
		if not def.fixed.has(key):
			continue
		var v: float = def.get_fixed(key)
		if v == 0.0 and key != "charges":
			continue
		out.append(fixed_text(key, v))
	return out


## ステータス1つを読みやすい文字にする
static func stat_text(stat_name: String, v: float) -> String:
	var label: String = STAT_LABELS.get(stat_name, stat_name)
	match stat_name:
		"speed_penalty", "damage_cut":
			return "%s %d%%" % [label, roundi(v * 100.0)]
		"speed_mult", "damage_mult":
			return "%s ×%.2f" % [label, v]
		"stun_sec":
			return "%s %.1f秒" % [label, v]
		"hp", "heal":
			return "%s %d" % [label, roundi(v)]
	return "%s %.1f" % [label, v]


## パーツ1つの説明（名前、動き方、ステータス、フレームなら枠の数）
static func part_line(data: GameData, p: PartInstance) -> String:
	var def: GameData.PartDef = data.get_part(p.def_id)
	var bits: PackedStringArray = PackedStringArray()
	for s: String in def.stat_names():
		bits.append(stat_text(s, p.get_stat(s)))
	if def.kind == GameData.KIND_FRAME:
		bits.append("武器%d・スキル%d" % [def.weapon_slots, def.skill_slots])
	var how: String = BEHAVIOR_LABELS.get(def.behavior, "")
	return "%s%s　%s" % [def.name, "（%s）" % how if not how.is_empty() else "", " / ".join(bits)]


static func perk_line(data: GameData, perk_id: String) -> String:
	var perk: GameData.PerkDef = data.get_perk(perk_id)
	return "%s：%s" % [perk.name, perk.description] if perk != null else perk_id


## バトルの出来事1つを実況の行にする。表示しないものは空文字
static func event_line(e: Dictionary, names: Array) -> String:
	var t: String = "%5.1f秒 " % float(e.get("t", 0.0))
	var who: String = str(names[int(e.get("robot", 0))]) if e.has("robot") else ""
	match str(e["type"]):
		"intent":
			return t + "%s「%s」→ %s" % [who, e["say"], INTENT_LABELS.get(e["intent"], e["intent"])]
		"confused":
			return t + "%s「%s」" % [who, e["say"]]
		"hit":
			if float(e["damage"]) < 2.0:
				return ""  # 機関銃の細かい被弾は省く
			return t + "%s が %s で %d 被弾%s" % [who, e["weapon"], roundi(e["damage"]), "（背後から）" if e["back"] else ""]
		"flip":
			return t + "%s がひっくり返された！" % who
		"skill":
			return t + "%s が %s を使った" % [who, e["skill"]]
		"fall":
			return t + "%s が穴に落ちた！" % who
		"repair":
			return t + "%s が修理中" % who
		"ammo_out":
			return t + "%s の %s が弾切れ" % [who, e["weapon"]]
		"over":
			var w: int = int(e["winner"])
			return t + "決着：%s（%s）" % ["引き分け" if w < 0 else "%s の勝ち" % names[w], REASON_LABELS.get(e["reason"], "")]
	return ""
