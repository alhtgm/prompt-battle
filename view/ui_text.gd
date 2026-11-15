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
