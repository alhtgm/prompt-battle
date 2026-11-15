# data/ の3ファイル（parts.json / perks.json / rules.json）を読み込み、検証して保持する。
# シーンやノードに依存しないので、画面なしでもサーバーでも使える。
extends RefCounted

const KIND_FRAME: String = "frame"
const KIND_WEAPON: String = "weapon"
const KIND_SKILL: String = "skill"
const KINDS: Array[String] = [KIND_FRAME, KIND_WEAPON, KIND_SKILL]

## 種類ごとに必ず持つステータス（docs/game-rules.md の「パーツ」の節）
const REQUIRED_STATS: Dictionary = {
	KIND_FRAME: ["hp", "speed_penalty"],
	KIND_WEAPON: ["damage", "knockback"],
	KIND_SKILL: [],
}

## 種類ごとに必ず持つ固定値（抽選しない値）
const REQUIRED_FIXED: Dictionary = {
	KIND_FRAME: ["mass", "turn_rate_deg"],
	KIND_WEAPON: ["cooldown_sec", "arc_deg"],
	KIND_SKILL: ["cooldown_sec", "charges"],
}

## 武器とスキルの動き方と、それぞれに要るステータス・固定値
const BEHAVIORS: Dictionary = {
	KIND_WEAPON: {
		"grind": {"stats": [], "fixed": ["reach"]},
		"strike": {"stats": [], "fixed": ["reach"]},
		"lift": {"stats": [], "fixed": ["reach", "stun_sec"]},
		"ram": {"stats": [], "fixed": ["reach", "min_speed"]},
		"shoot": {"stats": [], "fixed": ["range", "ammo", "projectile_speed", "spread_deg"]},
	},
	KIND_SKILL: {
		"booster": {"stats": ["speed_mult"], "fixed": ["duration_sec"]},
		"shield": {"stats": ["damage_cut"], "fixed": ["duration_sec"]},
		"repair": {"stats": ["heal"], "fixed": []},
		"shockwave": {"stats": ["knockback"], "fixed": ["range"]},
		"emp": {"stats": ["stun_sec"], "fixed": ["range"]},
		"overclock": {"stats": ["damage_mult"], "fixed": ["duration_sec"]},
	},
}

## rules.json のうち、0 以上の数値が並ぶまとまり（バトルの物理や頭脳のしきい値）
const NUMBER_GROUPS: Dictionary = {
	"battle.robot": ["radius", "base_speed", "accel", "reverse_mult", "stun_friction",
		"sharp_turn_deg", "sharp_turn_throttle", "arrive_dist"],
	"battle.pit": ["fall_margin", "avoid_extra", "avoid_push", "avoid_slide", "near_dist"],
	"battle.repair": ["total_per_robot", "rate_per_sec", "max_speed"],
	"battle.collision": ["restitution", "ram_min_speed", "ram_damage_coef", "ram_cooldown_sec"],
	"battle.hit": ["damage_scale", "back_angle_deg", "back_mult"],
	"battle.replan": ["big_hit_damage", "hp_low_ratio"],
	"battle.intent": ["keep_distance", "keep_distance_band", "circle_radius", "circle_side",
		"retreat_dist", "wall_margin", "flank_behind_deg", "flank_side", "flank_back",
		"push_behind", "push_lined_dot"],
	"agent.cpu": ["frame_slot_weight", "frame_whim", "part_whim"],
	"online": ["port", "draft_time_limit_sec", "result_view_sec", "perk_time_limit_sec", "final_view_sec",
		"state_send_hz", "frame_send_hz", "frame_log_entries"],
	"agent.mock": ["repair_hp", "repair_hp_any_style", "repair_enemy_dist", "cautious_hp",
		"random_intent_chance", "skill_booster_dist", "skill_shield_dist", "skill_repair_hp",
		"skill_shockwave_dist", "skill_emp_dist", "skill_overclock_dist"],
}

const PERK_OPS: Array[String] = ["add", "mul"]
## パークの効果の対象にできる頭の部分（種類のほか）
const PERK_EXTRA_TARGETS: Array[String] = ["build", "prompt"]

## rules.json に必ずある数値の項目と、検査の条件 [パス, 下限, 整数か]
## 下限は「壊れていないか」を見るためのもので、ゲームの値ではない
const NUMBER_RULES: Array = [
	["players", 2, true],
	["initial_health", 1, false],
	["tick_rate", 1, true],
	["battle.time_limit_sec", 1, false],
	["agent.think_interval_sec", 0.01, false],
	["agent.think_min_gap_sec", 0, false],
	["agent.mock_delay_min_sec", 0, false],
	["agent.mock_delay_max_sec", 0, false],
	["round.build_time_limit_sec", 1, false],
	["round.prompt_max_chars", 1, true],
	["damage.rank_coef", 0, false],
	["damage.margin_coef", 0, false],
	["draft.choices_per_kind", 1, true],
	["loot.parts_per_round", 1, true],
	["loot.min_per_kind", 0, true],
	["loot.perk_choices", 1, true],
	["loot.hand_limit", 0, true],
	["parts.stat_spread", 0, false],
	["parts.stat_step_default", 0, false],
	["battle.draw_hp_ratio_diff", 0, false],
	["battle.arena.half_size", 1, false],
	["agent.say_max_chars", 1, true],
	["match.max_rounds", 1, true],
	["match.pairing_attempts", 1, true],
]

## 引き分けのときのダメージの扱い
const DRAW_DAMAGE_MODES: Array[String] = ["none", "rank_only"]


## ステータスの範囲と、抽選後に丸める刻み
class StatRange:
	var min_value: float
	var max_value: float
	var step: float

	func _init(mn: float, mx: float, st: float) -> void:
		min_value = mn
		max_value = mx
		step = st


## パーツの型
class PartDef:
	var id: String = ""
	var name: String = ""
	var kind: String = ""
	## バトルでの動き方（武器とスキル）。フレームは空
	var behavior: String = ""
	## 見た目のモデルの場所
	var model: String = ""
	## フレームだけ：付けられる武器とスキルの数
	var weapon_slots: int = 0
	var skill_slots: int = 0
	## ステータス名 → 範囲
	var stats: Dictionary[String, StatRange] = {}
	## 抽選しない固定値（重さ、連射間隔、射程など）
	var fixed: Dictionary[String, float] = {}

	func get_fixed(key: String, fallback: float = 0.0) -> float:
		return fixed.get(key, fallback)

	## ステータス名を名前順で返す
	func stat_names() -> Array[String]:
		var names: Array[String] = []
		names.assign(stats.keys())
		names.sort()
		return names


## パークの定義
class PerkDef:
	var id: String = ""
	var name: String = ""
	var description: String = ""
	## {"target": String, "op": "add"|"mul", "value": float} の配列
	var effects: Array[Dictionary] = []


var parts: Array[PartDef] = []
var parts_by_id: Dictionary[String, PartDef] = {}
var perks: Array[PerkDef] = []
var perks_by_id: Dictionary[String, PerkDef] = {}
var rules: Dictionary = {}
## 読み込みと検証で見つかった問題（空なら正常）
var errors: PackedStringArray = PackedStringArray()


## フォルダから3ファイルを読む。問題がなければ true
func load_dir(dir: String = "res://data") -> bool:
	errors.clear()
	var parts_json: Variant = _read_json(dir.path_join("parts.json"))
	var perks_json: Variant = _read_json(dir.path_join("perks.json"))
	var rules_json: Variant = _read_json(dir.path_join("rules.json"))
	if not errors.is_empty():
		return false
	return load_from_values(parts_json, perks_json, rules_json)


## 読み込み済みのJSONの値から作る（テストで壊れたデータを試すのにも使う）
func load_from_values(parts_json: Variant, perks_json: Variant, rules_json: Variant) -> bool:
	errors.clear()
	parts.clear()
	parts_by_id.clear()
	perks.clear()
	perks_by_id.clear()
	rules = {}
	_load_rules(rules_json)
	if not errors.is_empty():
		return false  # パーツの読み込みにルールの値を使うので、ここで止める
	_load_parts(parts_json)
	_load_perks(perks_json)
	return errors.is_empty()


## ある種類の型をデータファイルの順で返す
func defs_of_kind(kind: String) -> Array[PartDef]:
	var out: Array[PartDef] = []
	for d: PartDef in parts:
		if d.kind == kind:
			out.append(d)
	return out


func get_part(id: String) -> PartDef:
	return parts_by_id.get(id, null)


func get_perk(id: String) -> PerkDef:
	return perks_by_id.get(id, null)


## "battle.time_limit_sec" のような点区切りのパスでルールの値を取る
func rule(path: String) -> Variant:
	var found: Array = _find_rule(path)
	if not found[0]:
		push_error("rules.json に %s がない" % path)
		return null
	return found[1]


func has_rule(path: String) -> bool:
	return _find_rule(path)[0]


# ---- 内部 ----

func _find_rule(path: String) -> Array:
	var node: Variant = rules
	for key: String in path.split("."):
		if not (node is Dictionary) or not (node as Dictionary).has(key):
			return [false, null]
		node = node[key]
	return [true, node]


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s が見つからない" % path)
		return null
	var json := JSON.new()
	var err: Error = json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		errors.append("%s の %d 行目が読めない：%s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _is_number(v: Variant) -> bool:
	return v is float or v is int


static func _is_finite_number(v: Variant) -> bool:
	return _is_number(v) and is_finite(float(v))


func _load_rules(rules_json: Variant) -> void:
	if not (rules_json is Dictionary):
		errors.append("rules.json：一番外側は { } にする")
		return
	rules = (rules_json as Dictionary).duplicate(true)

	for entry: Array in NUMBER_RULES:
		var path: String = entry[0]
		var lower: float = float(entry[1])
		var must_int: bool = entry[2]
		var found: Array = _find_rule(path)
		if not found[0]:
			errors.append("rules.json：%s がない" % path)
			continue
		var v: Variant = found[1]
		if not _is_finite_number(v):
			errors.append("rules.json：%s は数値にする（今は %s）" % [path, str(v)])
			continue
		var f: float = float(v)
		if f < lower:
			errors.append("rules.json：%s は %s 以上にする（今は %s）" % [path, str(lower), str(f)])
		if must_int and f != floorf(f):
			errors.append("rules.json：%s は整数にする（今は %s）" % [path, str(f)])
	if not errors.is_empty():
		return

	if float(rule("agent.mock_delay_min_sec")) > float(rule("agent.mock_delay_max_sec")):
		errors.append("rules.json：agent.mock_delay_min_sec が mock_delay_max_sec より大きい")
	if int(rule("loot.min_per_kind")) * KINDS.size() > int(rule("loot.parts_per_round")):
		errors.append("rules.json：loot.min_per_kind × 3 が loot.parts_per_round を超えている")
	_check_int_range_rule("parts.frame_weapon_slots", 1)
	_check_int_range_rule("parts.frame_skill_slots", 0)

	for group: String in NUMBER_GROUPS:
		for key: String in NUMBER_GROUPS[group]:
			var path: String = group + "." + key
			var found_v: Array = _find_rule(path)
			if not found_v[0]:
				errors.append("rules.json：%s がない" % path)
			elif not _is_finite_number(found_v[1]) or float(found_v[1]) < 0.0:
				errors.append("rules.json：%s は 0 以上の数値にする" % path)
	if not DRAW_DAMAGE_MODES.has(str(_find_rule("damage.on_draw")[1])):
		errors.append("rules.json：damage.on_draw は %s のどれかにする" % ", ".join(DRAW_DAMAGE_MODES))
	_check_circles("battle.arena.pits", true)
	_check_circles("battle.arena.repair_pads", true)
	var spawns: Variant = _find_rule("battle.arena.spawns")[1]
	if not (spawns is Array) or (spawns as Array).size() != 2:
		errors.append("rules.json：battle.arena.spawns は2つの { x, z, facing_deg } にする")
	else:
		for s: Variant in spawns:
			if not (s is Dictionary) or not _is_finite_number(s.get("x")) \
					or not _is_finite_number(s.get("z")) or not _is_finite_number(s.get("facing_deg")):
				errors.append("rules.json：battle.arena.spawns の中身は { x, z, facing_deg } にする")

	var steps: Variant = _find_rule("parts.stat_steps")[1]
	if steps != null:
		if not (steps is Dictionary):
			errors.append("rules.json：parts.stat_steps は { } にする")
		else:
			for k: Variant in steps:
				if not _is_finite_number(steps[k]) or float(steps[k]) < 0.0:
					errors.append("rules.json：parts.stat_steps.%s は 0 以上の数値にする" % str(k))


## { x, z, r } の円の配列を検査する（穴や修理ステーション）
func _check_circles(path: String, need_one: bool) -> void:
	var v: Variant = _find_rule(path)[1]
	if not (v is Array) or (need_one and (v as Array).is_empty()):
		errors.append("rules.json：%s は { x, z, r } の配列にする" % path)
		return
	for c: Variant in v:
		if not (c is Dictionary) or not _is_finite_number(c.get("x")) or not _is_finite_number(c.get("z")) \
				or not _is_finite_number(c.get("r")) or float(c.get("r")) <= 0.0:
			errors.append("rules.json：%s の中身は { x, z, r }（r は正）にする" % path)


## [最小, 最大] の形の整数の範囲を検査する
func _check_int_range_rule(path: String, lower: int) -> void:
	var found: Array = _find_rule(path)
	if not found[0]:
		errors.append("rules.json：%s がない" % path)
		return
	var v: Variant = found[1]
	if not (v is Array) or (v as Array).size() != 2 \
			or not _is_finite_number(v[0]) or not _is_finite_number(v[1]):
		errors.append("rules.json：%s は [最小, 最大] の形にする" % path)
		return
	if float(v[0]) != floorf(float(v[0])) or float(v[1]) != floorf(float(v[1])):
		errors.append("rules.json：%s は整数にする" % path)
	elif int(v[0]) < lower or int(v[0]) > int(v[1]):
		errors.append("rules.json：%s は %d 以上で、最小 ≦ 最大にする" % [path, lower])


func _stat_step(stat_name: String) -> float:
	var steps: Variant = _find_rule("parts.stat_steps")[1]
	if steps is Dictionary and (steps as Dictionary).has(stat_name):
		return float(steps[stat_name])
	return float(rule("parts.stat_step_default"))


func _load_parts(parts_json: Variant) -> void:
	if not (parts_json is Dictionary) or not ((parts_json as Dictionary).get("parts") is Array):
		errors.append("parts.json：{ \"parts\": [ ... ] } の形にする")
		return
	var spread: float = float(rule("parts.stat_spread"))
	var weapon_range: Array = rule("parts.frame_weapon_slots")
	var skill_range: Array = rule("parts.frame_skill_slots")
	var list: Array = parts_json["parts"]

	for i: int in list.size():
		var raw: Variant = list[i]
		var where: String = "parts.json の %d 番目" % (i + 1)
		if not (raw is Dictionary):
			errors.append("%s：{ } にする" % where)
			continue
		var r: Dictionary = raw
		var def := PartDef.new()
		def.id = str(r.get("id", ""))
		def.name = str(r.get("name", ""))
		def.kind = str(r.get("kind", ""))
		def.behavior = str(r.get("behavior", ""))
		def.model = str(r.get("model", ""))
		if not def.id.is_empty():
			where = "parts.json の %s" % def.id

		if def.id.is_empty():
			errors.append("%s：id がない" % where)
		elif parts_by_id.has(def.id):
			errors.append("%s：id が重複している" % where)
		if def.name.is_empty():
			errors.append("%s：name がない" % where)
		if not KINDS.has(def.kind):
			errors.append("%s：kind は frame / weapon / skill のどれかにする（今は %s）" % [where, def.kind])
			continue
		if def.kind != KIND_FRAME and def.behavior.is_empty():
			errors.append("%s：武器とスキルには behavior が要る" % where)

		# ステータス
		var stats_raw: Variant = r.get("stats")
		if not (stats_raw is Dictionary) or (stats_raw as Dictionary).is_empty():
			errors.append("%s：stats がない" % where)
		else:
			for stat_key: Variant in stats_raw:
				var stat_name: String = str(stat_key)
				var range_v: StatRange = _parse_stat(stats_raw[stat_key], stat_name, spread, where)
				if range_v != null:
					def.stats[stat_name] = range_v
		# 固定値
		var fixed_raw: Variant = r.get("fixed", {})
		if not (fixed_raw is Dictionary):
			errors.append("%s：fixed は { } にする" % where)
		else:
			for fk: Variant in fixed_raw:
				if _is_finite_number(fixed_raw[fk]) and float(fixed_raw[fk]) >= 0.0:
					def.fixed[str(fk)] = float(fixed_raw[fk])
				else:
					errors.append("%s：fixed.%s は 0 以上の数値にする" % [where, str(fk)])

		var need_stats: Array = REQUIRED_STATS[def.kind].duplicate()
		var need_fixed: Array = REQUIRED_FIXED[def.kind].duplicate()
		if BEHAVIORS.has(def.kind):
			var table: Dictionary = BEHAVIORS[def.kind]
			if not table.has(def.behavior):
				errors.append("%s：behavior は %s のどれかにする（今は %s）" % [where, ", ".join(table.keys()), def.behavior])
			else:
				need_stats.append_array(table[def.behavior]["stats"])
				need_fixed.append_array(table[def.behavior]["fixed"])
		for need: String in need_stats:
			if not def.stats.has(need):
				errors.append("%s：ステータス %s がない" % [where, need])
		for need: String in need_fixed:
			if not def.fixed.has(need):
				errors.append("%s：固定値 fixed.%s がない" % [where, need])

		# フレームの枠
		if def.kind == KIND_FRAME:
			def.weapon_slots = _parse_slot(r.get("weapon_slots"), weapon_range, "weapon_slots", where)
			def.skill_slots = _parse_slot(r.get("skill_slots"), skill_range, "skill_slots", where)

		if not def.id.is_empty() and not parts_by_id.has(def.id):
			parts.append(def)
			parts_by_id[def.id] = def

	for kind: String in KINDS:
		if defs_of_kind(kind).is_empty():
			errors.append("parts.json：%s が1つもない" % kind)


func _parse_stat(v: Variant, stat_name: String, spread: float, where: String) -> StatRange:
	var mn: float
	var mx: float
	if _is_number(v):
		if not _is_finite_number(v):
			errors.append("%s：%s が数値として壊れている" % [where, stat_name])
			return null
		var base: float = float(v)
		mn = base * (1.0 - spread)
		mx = base * (1.0 + spread)
		if mn > mx:  # 基準値がマイナスのとき
			var t: float = mn
			mn = mx
			mx = t
	elif v is Dictionary and _is_finite_number((v as Dictionary).get("min")) \
			and _is_finite_number((v as Dictionary).get("max")):
		mn = float(v["min"])
		mx = float(v["max"])
		if mn > mx:
			errors.append("%s：%s の min が max より大きい" % [where, stat_name])
			return null
	else:
		errors.append("%s：%s は数値か {\"min\": x, \"max\": y} にする" % [where, stat_name])
		return null
	return StatRange.new(mn, mx, _stat_step(stat_name))


func _parse_slot(v: Variant, allowed: Array, field: String, where: String) -> int:
	if not _is_finite_number(v) or float(v) != floorf(float(v)):
		errors.append("%s：%s は整数にする" % [where, field])
		return 0
	var n: int = int(v)
	if n < int(allowed[0]) or n > int(allowed[1]):
		errors.append("%s：%s は %d〜%d にする（今は %d）" % [where, field, int(allowed[0]), int(allowed[1]), n])
	return n


func _load_perks(perks_json: Variant) -> void:
	if not (perks_json is Dictionary) or not ((perks_json as Dictionary).get("perks") is Array):
		errors.append("perks.json：{ \"perks\": [ ... ] } の形にする")
		return
	var list: Array = perks_json["perks"]
	for i: int in list.size():
		var raw: Variant = list[i]
		var where: String = "perks.json の %d 番目" % (i + 1)
		if not (raw is Dictionary):
			errors.append("%s：{ } にする" % where)
			continue
		var r: Dictionary = raw
		var perk := PerkDef.new()
		perk.id = str(r.get("id", ""))
		perk.name = str(r.get("name", ""))
		perk.description = str(r.get("description", ""))
		if not perk.id.is_empty():
			where = "perks.json の %s" % perk.id
		if perk.id.is_empty():
			errors.append("%s：id がない" % where)
		elif perks_by_id.has(perk.id):
			errors.append("%s：id が重複している" % where)
		if perk.name.is_empty():
			errors.append("%s：name がない" % where)

		var effects: Variant = r.get("effects")
		if not (effects is Array) or (effects as Array).is_empty():
			errors.append("%s：effects がない" % where)
		else:
			for e: Variant in effects:
				var parsed: Dictionary = _parse_effect(e, where)
				if not parsed.is_empty():
					perk.effects.append(parsed)

		if not perk.id.is_empty() and not perks_by_id.has(perk.id):
			perks.append(perk)
			perks_by_id[perk.id] = perk

	if perks.is_empty():
		errors.append("perks.json：パークが1つもない")


func _parse_effect(e: Variant, where: String) -> Dictionary:
	if not (e is Dictionary):
		errors.append("%s：effects の中身は { } にする" % where)
		return {}
	var d: Dictionary = e
	var target: String = str(d.get("target", ""))
	var op: String = str(d.get("op", ""))
	var value: Variant = d.get("value")
	var ok: bool = true
	var dot: int = target.find(".")
	if dot <= 0 or dot == target.length() - 1:
		errors.append("%s：target は \"種類.項目\" の形にする（今は %s）" % [where, target])
		ok = false
	else:
		var head: String = target.substr(0, dot)
		var stat: String = target.substr(dot + 1)
		if KINDS.has(head):
			if stat != "*" and not _kind_has_stat(head, stat):
				errors.append("%s：%s を持つ %s がない" % [where, stat, head])
				ok = false
		elif not PERK_EXTRA_TARGETS.has(head):
			errors.append("%s：target の頭 %s が使えない" % [where, head])
			ok = false
	if not PERK_OPS.has(op):
		errors.append("%s：op は add か mul にする（今は %s）" % [where, op])
		ok = false
	if not _is_finite_number(value):
		errors.append("%s：value は数値にする" % where)
		ok = false
	if not ok:
		return {}
	return {"target": target, "op": op, "value": float(value)}


func _kind_has_stat(kind: String, stat: String) -> bool:
	for d: PartDef in defs_of_kind(kind):
		if d.stats.has(stat):
			return true
	return false
