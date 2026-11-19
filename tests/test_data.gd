# data/ の読み込みと検証のテスト。正しいデータが読めること、壊れたデータを見つけることを確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")


func _load() -> GameData:
	var data := GameData.new()
	data.load_dir()
	return data


func _raw(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + file))


func test_loads_without_errors() -> void:
	var data := _load()
	check(data.errors.is_empty(), "data/ がエラーなしで読める：%s" % "\n".join(data.errors))


func test_part_counts_match_design() -> void:
	# docs/design.md「仮置きした値」：フレーム6、武器8、スキル6
	var data := _load()
	check_eq(data.defs_of_kind(GameData.KIND_FRAME).size(), 6, "フレームの型の数")
	check_eq(data.defs_of_kind(GameData.KIND_WEAPON).size(), 9, "武器の型の数（ハープーンガンを含む）")
	check_eq(data.defs_of_kind(GameData.KIND_SKILL).size(), 7, "スキルの型の数（自爆装置を含む）")


func test_rules_match_design() -> void:
	# docs/design.md「仮置きした値」と食い違っていないか
	var data := _load()
	check_eq(int(data.rule("initial_health")), 100, "初期体力")
	check_eq(float(data.rule("agent.think_interval_sec")), 2.0, "考える間隔")
	check_eq(float(data.rule("agent.think_min_gap_sec")), 0.5, "考え直しの最低間隔")
	check_eq(float(data.rule("battle.time_limit_sec")), 75.0, "バトルの制限時間")
	check_eq(float(data.rule("round.build_time_limit_sec")), 45.0, "組み立ての制限時間")
	check_eq(int(data.rule("round.prompt_max_chars")), 120, "プロンプトの文字数")
	check_eq(float(data.rule("damage.rank_coef")), 6.0, "ダメージ係数 A")
	check_eq(float(data.rule("damage.margin_coef")), 60.0, "ダメージ係数 B")
	check_eq(float(data.rule("parts.stat_spread")), 0.2, "ステータスの振れ幅")
	check_eq(data.rule("parts.frame_weapon_slots"), [1.0, 3.0], "フレームの武器の枚数")
	check_eq(data.rule("parts.frame_skill_slots"), [0.0, 2.0], "フレームのスキルの枚数")
	check_eq(int(data.rule("draft.choices_per_kind")), 5, "開始時の選出")
	check_eq(int(data.rule("loot.parts_per_round")), 5, "ラウンド後の配布")
	check_eq(int(data.rule("loot.perk_choices")), 3, "パークの候補数")
	check_eq(int(data.rule("tick_rate")), 60, "1秒あたりの刻み")
	check_eq(float(data.rule("agent.mock_delay_min_sec")), 0.3, "仮の頭脳の応答時間（最短）")
	check_eq(float(data.rule("agent.mock_delay_max_sec")), 1.5, "仮の頭脳の応答時間（最長）")


func test_part_definitions_are_sane() -> void:
	var data := _load()
	var weapon_range: Array = data.rule("parts.frame_weapon_slots")
	var skill_range: Array = data.rule("parts.frame_skill_slots")
	for d: GameData.PartDef in data.parts:
		check(not d.name.is_empty(), "%s に名前がある" % d.id)
		check(not d.model.is_empty(), "%s に見た目の場所がある" % d.id)
		for s: String in d.stat_names():
			var r: GameData.StatRange = d.stats[s]
			check(is_finite(r.min_value) and is_finite(r.max_value), "%s.%s が有限" % [d.id, s])
			check(r.min_value <= r.max_value, "%s.%s の min ≦ max" % [d.id, s])
			check(r.step >= 0.0, "%s.%s の刻みが 0 以上" % [d.id, s])
		if d.kind == GameData.KIND_FRAME:
			check(d.weapon_slots >= int(weapon_range[0]) and d.weapon_slots <= int(weapon_range[1]),
				"%s の武器の枚数が範囲内" % d.id)
			check(d.skill_slots >= int(skill_range[0]) and d.skill_slots <= int(skill_range[1]),
				"%s のスキルの枚数が範囲内" % d.id)
			check(d.stats.has("hp") and d.stats.has("speed_penalty"), "%s に HP と移動速度の低下がある" % d.id)
		elif d.kind == GameData.KIND_WEAPON:
			check(d.stats.has("damage") and d.stats.has("knockback"), "%s にダメージとノックバックがある" % d.id)


func test_spread_is_applied() -> void:
	var data := _load()
	var r: GameData.StatRange = data.get_part("frame_standard").stats["hp"]
	check(is_equal_approx(r.min_value, 96.0) and is_equal_approx(r.max_value, 144.0),
		"基準値 120 は ±20%% で 96〜144（実際 %s〜%s）" % [r.min_value, r.max_value])
	check_eq(r.step, 1.0, "HP は 1 刻み")


func test_explicit_min_max_is_supported() -> void:
	var parts: Dictionary = _raw("parts.json")
	parts["parts"][0]["stats"]["hp"] = {"min": 50, "max": 70}
	var data := GameData.new()
	check(data.load_from_values(parts, _raw("perks.json"), _raw("rules.json")), "min/max の書き方も読める")
	var r: GameData.StatRange = data.parts[0].stats["hp"]
	check(r.min_value == 50.0 and r.max_value == 70.0, "min/max がそのまま使われる")


func test_perks_load() -> void:
	var data := _load()
	check(data.perks.size() >= 3, "パークがパークの候補数（3）以上ある")
	var armor: GameData.PerkDef = data.get_perk("perk_armor")
	check(armor != null, "HP+5% のパークがある")
	if armor != null:
		check_eq(armor.effects[0], {"target": "frame.hp", "op": "mul", "value": 1.05}, "パークの効果が読める")


## 壊したデータを読ませて、エラーとして見つかることを確かめる
func _expect_error(label: String, parts: Variant, perks: Variant, rules: Variant, needle: String) -> void:
	var data := GameData.new()
	var ok: bool = data.load_from_values(parts, perks, rules)
	check(not ok, "%s：読み込みが失敗する" % label)
	var joined: String = "\n".join(data.errors)
	check(joined.contains(needle), "%s：エラーに「%s」が含まれる（実際：%s）" % [label, needle, joined])


func test_broken_data_is_rejected() -> void:
	var good_parts: Variant = _raw("parts.json")
	var good_perks: Variant = _raw("perks.json")
	var good_rules: Variant = _raw("rules.json")

	var rules: Dictionary = good_rules.duplicate(true)
	rules["battle"].erase("time_limit_sec")
	_expect_error("ルールの項目がない", good_parts, good_perks, rules, "battle.time_limit_sec")

	rules = good_rules.duplicate(true)
	rules["initial_health"] = NAN
	_expect_error("ルールが NaN", good_parts, good_perks, rules, "initial_health")

	rules = good_rules.duplicate(true)
	rules["players"] = 6.5
	_expect_error("整数の項目が小数", good_parts, good_perks, rules, "players")

	var parts: Dictionary = good_parts.duplicate(true)
	parts["parts"][0]["stats"]["hp"] = {"min": 10, "max": 5}
	_expect_error("min > max", parts, good_perks, good_rules, "min が max より大きい")

	parts = good_parts.duplicate(true)
	parts["parts"][1]["id"] = parts["parts"][0]["id"]
	_expect_error("id の重複", parts, good_perks, good_rules, "重複")

	parts = good_parts.duplicate(true)
	parts["parts"][0]["kind"] = "wheel"
	_expect_error("知らない種類", parts, good_perks, good_rules, "kind")

	parts = good_parts.duplicate(true)
	parts["parts"][0]["weapon_slots"] = 9
	_expect_error("武器の枚数が範囲外", parts, good_perks, good_rules, "weapon_slots")

	parts = good_parts.duplicate(true)
	parts["parts"][0]["stats"].erase("hp")
	_expect_error("フレームに HP がない", parts, good_perks, good_rules, "hp")

	parts = good_parts.duplicate(true)
	parts["parts"][0]["stats"]["hp"] = INF
	_expect_error("ステータスが無限大", parts, good_perks, good_rules, "hp")

	var perks: Dictionary = good_perks.duplicate(true)
	perks["perks"][0]["effects"][0]["op"] = "pow"
	_expect_error("パークの op が不正", good_parts, perks, good_rules, "op")

	perks = good_perks.duplicate(true)
	perks["perks"][0]["effects"][0]["target"] = "frame.wings"
	_expect_error("パークの対象のステータスがない", good_parts, perks, good_rules, "wings")

	_expect_error("JSONの形が違う", [], good_perks, good_rules, "parts.json")
