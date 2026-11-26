# 試作：ルール方式の操縦。ルールは上から順に調べ、条件がすべて当てはまった最初のルールの方針で動く。
# 条件は決まった語彙（ATOMS）だけ。毎刻み（1/60秒）評価するので、LLM の答えを待たずに状況の変化へすぐ反応する。
extends RefCounted

const Robot := preload("res://core/battle_robot.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const Observation := preload("res://core/observation.gd")

## 条件の語彙と、画面・LLM向けの説明
const ATOMS: Dictionary = {
	"my_hp<30": "自分のHPが30%未満",
	"my_hp<50": "自分のHPが50%未満",
	"my_hp<70": "自分のHPが70%未満",
	"enemy_hp<30": "相手のHPが30%未満",
	"enemy_hp<50": "相手のHPが50%未満",
	"touch": "相手と接触している（距離3.5以下）",
	"near": "相手が近い（距離6未満）",
	"far": "相手が遠い（距離10以上）",
	"ammo_out": "弾切れ（撃つ武器の弾が0）",
	"enemy_near_pit": "相手が穴の近く",
	"me_near_pit": "自分が穴の近く",
	"enemy_behind_me": "相手が自分の後ろ側にいる",
	"behind_enemy": "自分が相手の背後にいる",
	"enemy_stunned": "相手が動けない",
	"hit_recent": "1.5秒以内に被弾した",
	"repair_ok": "修理ステーションでまだ回復できる",
	"skill_ready": "スキルが使える",
	"time_low": "残り20秒未満",
	"enemy_charging": "相手がこちらへ突っ込んでくる",
	"enemy_fleeing": "相手が離れていく",
	"enemy_facing_me": "相手がこちらを向いている（正面に入っている）",
	"me_near_wall": "自分が壁際",
	"enemy_near_wall": "相手が壁際",
	"winning": "HPの割合で相手に勝っている",
	"losing": "HPの割合で相手に負けている",
	"hit_given": "1.5秒以内に攻撃を当てた",
}
## 画面のフローチャート用の短い言い方
const ATOM_SHORT: Dictionary = {
	"my_hp<30": "自HP<30%", "my_hp<50": "自HP<50%", "my_hp<70": "自HP<70%",
	"enemy_hp<30": "敵HP<30%", "enemy_hp<50": "敵HP<50%",
	"touch": "接触中", "near": "距離<6", "far": "距離≧10", "ammo_out": "弾切れ",
	"enemy_near_pit": "敵が穴の近く", "me_near_pit": "自分が穴の近く",
	"enemy_behind_me": "背後をとられた", "behind_enemy": "敵の背後にいる",
	"enemy_stunned": "敵が動けない", "hit_recent": "被弾した直後",
	"repair_ok": "修理が残っている", "skill_ready": "スキル使用可", "time_low": "残り<20秒",
	"enemy_charging": "敵が突っ込んでくる", "enemy_fleeing": "敵が離れていく", "enemy_facing_me": "敵がこちらを向いた",
	"me_near_wall": "自分が壁際", "enemy_near_wall": "敵が壁際", "winning": "優勢", "losing": "劣勢",
	"hit_given": "当てた直後",
}
const INTENT_SHORT: Dictionary = {
	"charge": "突撃", "flank": "回り込み", "keep_distance": "距離を保つ", "retreat": "逃げる",
	"push_to_pit": "穴へ押し込む", "go_repair": "修理に向かう", "circle": "周りを回る", "hold": "その場で待つ",
}

const HIT_RECENT_SEC: float = 1.5
const TIME_LOW_SEC: float = 20.0
const WALL_MARGIN: float = 3.0
const FACING_DEG: float = 30.0
const LEAD_RATIO: float = 0.1

## 上が作戦欄（lock=false）、下が土台（lock=true、最後は if が空の「いつも」）
var rules: Array[Dictionary] = []


static func default_rules() -> Array[Dictionary]:
	var r: Array[Dictionary] = [
		make_rule(["my_hp<30", "repair_ok"], "go_repair", -1, true),
		make_rule([], "charge", -1, true),
	]
	return r


## 同時には成り立たない条件の組
const CONTRADICTIONS: Array = [
	["near", "far"], ["touch", "far"], ["winning", "losing"], ["enemy_charging", "enemy_fleeing"],
]


## LLM の答え（JSON）を読む。形が正しければルールの配列、壊れていれば空。lock は土台（固定）かどうか
static func parse(rules_json: Variant, n_skills: int, lock: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (rules_json is Array):
		return out
	for item: Variant in rules_json:
		var r: Dictionary = parse_rule(item, n_skills, lock)
		if r.is_empty():
			return []
		out.append(r)
	if out.is_empty() or not (out.back()["if"] as Array).is_empty():
		out.append(make_rule([], "charge", -1, lock))  # 「いつも」が抜けていたら足す
	return out


## ルール1つを読む。壊れていれば空
static func parse_rule(item: Variant, n_skills: int, lock: bool = false) -> Dictionary:
	if not (item is Dictionary):
		return {}
	var conds: Array = []
	var cond_text: String = str(item.get("if", ""))
	if not cond_text.is_empty():
		for a: String in cond_text.split("&"):
			if not ATOMS.has(a) or conds.has(a):
				return {}
			conds.append(a)
	var intent: String = str(item.get("do", ""))
	if not RobotDriver.INTENTS.has(intent):
		return {}
	var sk: Variant = item.get("skill")
	var skill: int = int(sk) if (sk is float or sk is int) and int(sk) >= 0 and int(sk) < n_skills else -1
	return make_rule(conds, intent, skill, lock)


## ルールの形。sec・given・taken はそのルールを実行していた秒数と、そのあいだに与えた・受けたダメージ
static func make_rule(conds: Array, intent: String, skill: int, lock: bool) -> Dictionary:
	return {"if": conds, "do": intent, "skill": skill, "lock": lock, "sec": 0.0, "given": 0.0, "taken": 0.0}


static func is_contradictory(conds: Array) -> bool:
	for pair: Array in CONTRADICTIONS:
		if conds.has(pair[0]) and conds.has(pair[1]):
			return true
	return false


static func same_rule(a: Dictionary, b: Dictionary) -> bool:
	var ca: Array = (a["if"] as Array).duplicate()
	var cb: Array = (b["if"] as Array).duplicate()
	ca.sort()
	cb.sort()
	return ca == cb and a["do"] == b["do"]


## idx 番のルールを、上のどのルールが隠しているか（上のルールの条件がすべて含まれていれば、上が必ず先に選ばれる）。なければ -1
func shadowed_by(idx: int) -> int:
	var mine: Array = rules[idx]["if"]
	for i: int in idx:
		var ok: bool = true
		for a: String in rules[i]["if"]:
			if not mine.has(a):
				ok = false
				break
		if ok:
			return i
	return -1


## 今の状況で当てはまる条件の集まりを作る（毎刻み）
static func facts(me: Robot, en: Robot, t: float, time_left: float, battle: Dictionary, last_hit_t: float, last_give_t: float) -> Dictionary:
	var ex: float = en.x - me.x
	var ez: float = en.z - me.z
	var d: float = sqrt(ex * ex + ez * ez)
	var back: float = deg_to_rad(float(battle["hit"]["back_angle_deg"]))
	var hp: float = me.hp_ratio() * 100.0
	var ehp: float = en.hp_ratio() * 100.0
	var ammo: Variant = me.ammo_total()
	var to_me := Vector2(-ex, -ez) / maxf(d, 0.001)
	var closing: float = Vector2(en.vx, en.vz).dot(to_me)  # 相手がこちらへ近づく速さ
	var half: float = float(battle["arena"]["half_size"]) - WALL_MARGIN
	var lead: float = me.hp_ratio() - en.hp_ratio()
	var any_ready: bool = false
	for s: Robot.SkillSlot in me.skills:
		if s.is_ready():
			any_ready = true
	return {
		"my_hp<30": hp < 30.0, "my_hp<50": hp < 50.0, "my_hp<70": hp < 70.0,
		"enemy_hp<30": ehp < 30.0, "enemy_hp<50": ehp < 50.0,
		"touch": d <= 3.5, "near": d < 6.0, "far": d >= 10.0,
		"ammo_out": ammo != null and int(ammo) <= 0,
		"enemy_near_pit": Observation.near_pit(en, battle), "me_near_pit": Observation.near_pit(me, battle),
		"enemy_behind_me": absf(angle_difference(me.th, atan2(ez, ex))) > back,
		"behind_enemy": absf(angle_difference(en.th, atan2(-ez, -ex))) > back,
		"enemy_stunned": en.stun > 0.0,
		"hit_recent": t - last_hit_t < HIT_RECENT_SEC,
		"repair_ok": me.repair_left > 0.0,
		"skill_ready": any_ready,
		"time_low": time_left < TIME_LOW_SEC,
		"enemy_charging": closing > 0.4 * en.max_speed,
		"enemy_fleeing": closing < -0.3 * en.max_speed,
		"enemy_facing_me": absf(angle_difference(en.th, atan2(-ez, -ex))) < deg_to_rad(FACING_DEG),
		"me_near_wall": absf(me.x) > half or absf(me.z) > half,
		"enemy_near_wall": absf(en.x) > half or absf(en.z) > half,
		"winning": lead > LEAD_RATIO,
		"losing": lead < -LEAD_RATIO,
		"hit_given": t - last_give_t < HIT_RECENT_SEC,
	}


## 当てはまった最初のルールの番号
func pick(f: Dictionary) -> int:
	for i: int in rules.size():
		var ok: bool = true
		for a: String in rules[i]["if"]:
			if not f.get(a, false):
				ok = false
				break
		if ok:
			return i
	return rules.size() - 1


static func rule_to_text(r: Dictionary) -> String:
	var c: PackedStringArray = PackedStringArray()
	for a: String in r["if"]:
		c.append(ATOM_SHORT.get(a, a))
	return "%s → %s" % [" かつ ".join(c) if c.size() > 0 else "いつも", INTENT_SHORT.get(r["do"], r["do"])]
