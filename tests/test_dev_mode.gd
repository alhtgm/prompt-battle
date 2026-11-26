# 開発モードのテスト。設定どおりの機体・ステージ・ギミックで試合ができる、HP無限と時間無制限が効く、
# 同じ設定ならやり直しても同じ試合になる、画面からタイトル→設定→バトル→編集→やり直しと行き来できる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const DevSession := preload("res://core/dev_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const Robot := preload("res://core/battle_robot.gd")
const TitleScreen := preload("res://view/title/title_screen.gd")
const DevSetupScreen := preload("res://view/dev/dev_setup_screen.gd")
const BattleScreen := preload("res://view/arena/battle_screen.gd")


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


## 近接で殴り合う設定（どちらも突撃）
func _brawl_setup(data: GameData) -> Dictionary:
	var s: Dictionary = DevSession.default_setup(data)
	for i: int in 2:
		s["builds"][i] = {"frame": "frame_standard", "weapons": ["weapon_hammer"], "skills": []}
		s["prompts"][i] = "とにかく突撃して殴れ"
	return s


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for c: Node in node.get_children():
		var b: Button = _find_button(c, text)
		if b != null:
			return b
	return null


func test_session_follows_the_setup() -> void:
	var data := _data()
	var s: Dictionary = DevSession.default_setup(data)
	s["stage_id"] = "standard"
	s["builds"][0] = {"frame": "frame_heavy", "weapons": ["weapon_hammer", "weapon_mg"], "skills": ["skill_shield"]}
	s["builds"][1] = {"frame": "frame_light", "weapons": ["weapon_spike"], "skills": []}
	s["prompts"] = ["距離をとって撃て", "突撃しろ"]
	check_eq(DevSession.check_setup(data, s), "", "正しい設定なら始められる")
	var dev := DevSession.new(data, DefaultAgents.new(false), s)
	var sim: Variant = dev.battles[0].sim
	check_eq(sim.stage["id"], "standard", "選んだステージ")
	check_eq(sim.robots[0].build.part_def_ids(), ["frame_heavy", "weapon_hammer", "weapon_mg", "skill_shield"], "自分の装備")
	check_eq(sim.robots[1].build.part_def_ids(), ["frame_light", "weapon_spike"], "相手の装備")
	check_eq(dev.battles[0].prompts, ["距離をとって撃て", "突撃しろ"], "両機のプロンプト")
	# 性能は範囲の真ん中
	var hp: GameData.StatRange = data.get_part("frame_heavy").stats["hp"]
	check(absf(sim.robots[0].build.frame.get_stat("hp") - (hp.min_value + hp.max_value) * 0.5) <= hp.step + 1e-6,
		"フレームのHPは範囲の真ん中")
	check(dev.get_player(0).alive and dev.battle_of(0) == dev.battles[0], "バトルの画面が読む形になっている")


func test_setup_problems_are_reported() -> void:
	var data := _data()
	var s: Dictionary = DevSession.default_setup(data)
	s["builds"][1] = {"frame": "frame_light", "weapons": ["weapon_hammer", "weapon_spike", "weapon_mg", "weapon_saw"], "skills": []}
	check(DevSession.check_setup(data, s).contains("相手の機体"), "枠を超える武器は始める前に分かる")
	s = DevSession.default_setup(data)
	var st: Dictionary = data.get_stage("standard").duplicate(true)
	st["spawns"][0] = {"x": -4, "z": -4, "facing_deg": 0}
	s["stage"] = st
	check(DevSession.check_setup(data, s).contains("出る位置"), "作り替えたステージの問題も始める前に分かる")
	check(data.errors.is_empty(), "ステージを確かめても、読み込みのエラーの記録は変わらない")


func test_gimmicks_can_be_turned_off() -> void:
	# ギミックは見送りになったので、今はどのステージにもない。外すしくみ（gimmicks_off）は、ギミックを足したときに使う
	var data := _data()
	check(GameData.GIMMICKS.is_empty(), "ギミックはまだない")
	for st: Dictionary in data.stages:
		check(GameData.stage_gimmicks(st).is_empty(), "%s：ギミックがない" % st["id"])
	var s: Dictionary = DevSession.default_setup(data)
	s["gimmicks_off"] = ["warps"]  # 知らないギミックの名前は無視する
	var made: Dictionary = DevSession.make_stage(data, s)
	check_eq(made, data.get_stage(str(s["stage_id"])), "知らないギミックを外しても、ステージは変わらない")
	var dev := DevSession.new(data, DefaultAgents.new(false), s)
	check_eq(dev.battles[0].sim.stage, made, "バトルに設定のステージが渡る")


func test_invincible_and_no_time_limit() -> void:
	var data := _data()
	var s: Dictionary = _brawl_setup(data)
	s["invincible"] = [true, true]
	s["no_time_limit"] = true
	var dev := DevSession.new(data, DefaultAgents.new(false), s)
	var sim: Variant = dev.battles[0].sim
	var limit: int = sim.time_limit_ticks
	var hp_ok: bool = true
	for k: int in 120 * 4:  # 120秒ぶん（制限時間より長い）
		dev.update(0.25)
		for r: Robot in sim.robots:
			if r.hp != r.max_hp:
				hp_ok = false
		if sim.over:
			break
	check(hp_ok, "HP無限の機体はHPが減らない")
	var hits: int = 0
	for e: Dictionary in sim.log:
		if e["type"] == "hit":
			hits += 1
	check(hits > 0, "当たったことは記録に残る（%d 回）" % hits)
	if sim.over:
		check_eq(sim.result["reason"], "pit", "決着するなら穴だけ（破壊と時間切れでは終わらない）")
	else:
		check(sim.tick > limit, "制限時間を過ぎても続く")
	# 「最後まで飛ばす」は、制限時間がなくても止まる
	dev.restart()
	dev.run_battles_to_end()
	check(dev.battles[0].sim.tick <= limit, "飛ばしても制限時間の分で止まる")


func test_restart_gives_the_same_battle() -> void:
	var data := _data()
	var s: Dictionary = _brawl_setup(data)
	s["seed"] = 77
	var dev := DevSession.new(data, DefaultAgents.new(false), s)
	for k: int in 40:
		dev.update(0.25)
	var first: Dictionary = dev.battles[0].sim.snapshot()
	var old_sim: Variant = dev.battles[0].sim
	dev.restart()
	check(dev.battles[0].sim != old_sim and dev.battles[0].sim.tick == 0, "やり直すと最初から")
	for k: int in 40:
		dev.update(0.25)
	check_eq(dev.battles[0].sim.snapshot(), first, "同じ設定・同じ種なら同じ試合")


func test_screens_title_setup_battle_edit_restart() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	check(main.screen is TitleScreen, "最初はタイトル")
	var dev_button: Button = null
	for b: Button in main.screen.menu_buttons:
		if b.text == "開発モード":
			dev_button = b
	check(dev_button != null, "開発用の実行では、タイトルに開発モードがある")
	main.screen.open_dev_mode()
	await _frame()
	check(main.screen is DevSetupScreen, "開発モードの設定画面が出る")
	var setup_screen: Node = main.screen
	setup_screen.set_stage("standard")
	check(setup_screen.gimmick_boxes.is_empty(), "ギミックがないので、ギミックの欄は出ない")
	setup_screen.set_frame(1, "frame_light")
	setup_screen.set_parts(1, ["weapon_hammer", "weapon_spike", "weapon_mg", "weapon_saw"], [])
	check(setup_screen.start_button.disabled, "装備に問題があれば開始できない")
	check(not setup_screen.start().is_empty(), "開始しようとすると理由が返る")
	setup_screen.set_parts(1, ["weapon_spike"], [])
	setup_screen.set_prompt(1, "相手の周りを回れ")
	setup_screen.invincible_boxes[0].button_pressed = true
	check(main.dev_setup["invincible"][0], "チェックでHP無限が設定に入る")
	check_eq(setup_screen.start(), "", "正しい設定なら開始できる")
	await _frame()
	check(main.screen is BattleScreen, "3Dのバトル画面になる")
	var b: Node = main.screen
	check_eq(b.watched_battle.sim.stage["id"], "standard", "選んだステージで戦う")
	check_eq(b.arena.stage["id"], "standard", "3Dのアリーナも選んだステージ")
	check(b.side_names[0].text.contains("無限"), "HP無限が画面に出る")
	var edit: Button = _find_button(b, "編集")
	var again: Button = _find_button(b, "やり直し")
	check(edit != null and again != null, "バトル画面に「編集」と「やり直し」がある")
	main.session.update(3.0)
	await _frame()
	var before: Variant = main.session.battles[0].sim
	again.pressed.emit()
	await _frame()
	check(main.screen is BattleScreen and main.session.battles[0].sim != before and main.session.battles[0].sim.tick < 30,
		"やり直しで最初から始まる")
	_find_button(main.screen, "編集").pressed.emit()
	await _frame()
	check(main.screen is DevSetupScreen, "編集で設定画面に戻る")
	check_eq(main.screen.stage_select.selected, 0, "選んだステージ（標準）が選ばれている")
	check_eq(main.screen.prompt_edits[1].text, "相手の周りを回れ", "書いたプロンプトが残っている")
	main.show_title()
	await _frame()
	main.queue_free()
	await _frame()
