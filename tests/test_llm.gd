# 本番の頭脳のテスト（サーバーは起動しない）。指示文と文法の組み立て、答えの読み取り、サーバーが使えないときの代わりの動きを確かめる。
# 実際のモデルでの速さと賢さは tools/llm_bench.gd で測る。
extends "res://tests/support/test_case.gd"

const LlmBrain := preload("res://agent/llm_brain.gd")
const LlmConfig := preload("res://agent/llm_config.gd")
const LlmServer := preload("res://agent/llm_server.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const H := preload("res://tests/support/battle_helpers.gd")

const BUILD: Dictionary = {
	"frame": {"name": "標準フレーム"},
	"weapons": [{"name": "ハンマー", "behavior": "strike"}, {"name": "機関銃", "behavior": "shoot"}],
	"skills": [{"name": "ブースター", "behavior": "booster"}],
}


func test_system_prompt_has_rules_build_and_player_prompt() -> void:
	var s: String = LlmBrain.build_system_prompt("穴に押し込め", BUILD, 12)
	for intent: String in RobotDriver.INTENTS:
		check(s.contains(intent), "方針 %s の説明がある" % intent)
	check(s.contains("ハンマー（叩く）") and s.contains("機関銃（撃つ）"), "武器が書いてある")
	check(s.contains("0：ブースター"), "スキルが番号つきで書いてある")
	check(s.ends_with("プレイヤーの指示：「穴に押し込め」"), "プレイヤーの指示が最後にある")
	var empty: String = LlmBrain.build_system_prompt("  ", {"frame": {}, "weapons": [], "skills": []}, 12)
	check(empty.contains("指示なし") and empty.contains("skill はいつも null"), "指示もスキルもないときの書き方")


func test_grammar_limits_intents_skills_and_say() -> void:
	var g: String = LlmBrain.build_grammar(2, 12)
	check(g.begins_with("root ::= \"{\\\"intent\\\":\\\"\" intent"), "答えの形が詰めたJSON")
	check(g.contains("\"push_to_pit\"") and g.contains("\"hold\""), "方針が並んでいる")
	check(g.contains("skill ::= \"null\" | \"0\" | \"1\""), "スキルは持っている番号か null")
	check(g.contains("{1,12}"), "一言は12文字まで")
	check(LlmBrain.build_grammar(0, 5).contains("skill ::= \"null\"\n"), "スキルがなければ null だけ")


func test_parse_answer() -> void:
	check_eq(LlmBrain.parse_answer('{"intent":"charge","skill":null,"say":"いくぞ"}', 1, 12),
		{"intent": "charge", "skill": null, "say": "いくぞ"}, "正しい答えを読める")
	check_eq(LlmBrain.parse_answer('{"intent":"flank","skill":0,"say":"回る"}', 1, 12)["skill"], 0, "スキルの番号を読める")
	check_eq(LlmBrain.parse_answer('{"intent":"flank","skill":5,"say":"回る"}', 1, 12)["skill"], null, "持っていない番号は使わない")
	check_eq(LlmBrain.parse_answer('{"intent":"flank","skill":0,"say":"あいうえおかきくけこさしすせそ"}', 1, 5)["say"], "あいうえお", "一言は切り詰める")
	check(LlmBrain.parse_answer('{"intent":"dance","skill":null,"say":"x"}', 1, 12).is_empty(), "知らない方針は壊れた答え")
	check(LlmBrain.parse_answer("えっと", 1, 12).is_empty(), "JSONでなければ壊れた答え")
	check(LlmBrain.parse_answer("", 1, 12).is_empty(), "空なら壊れた答え")


func test_compact_observation_keeps_what_matters() -> void:
	var data := H.load_data()
	var sim: BattleSim = H.make_match(data, 3)
	for k: int in 90:
		sim.step()
	var Observation := preload("res://core/observation.gd")
	var obs: Dictionary = Observation.build(sim.robots[0], sim.robots[1], sim.now(), sim.time_left(), sim.battle_rules())
	var c: Dictionary = LlmBrain.compact_observation(obs)
	check(not c["me"].has("pos") and not c["me"].has("facing"), "位置と向きの数字は省く")
	check(c["me"].has("hp") and c["enemy"].has("near_pit") and c.has("events"), "判断に使うものは残す")
	check(JSON.stringify(c).length() < JSON.stringify(obs).length(), "元の戦況より小さい")


func test_config_finds_or_explains() -> void:
	var cfg := LlmConfig.new()
	var ok: bool = cfg.load_config({"search_dirs": ["no_such_dir_for_test"], "external_server": false})
	check(not ok and cfg.problem.contains("llama-server"), "見つからなければ理由が分かる")
	var ext := LlmConfig.new()
	check(ext.load_config({"search_dirs": ["no_such_dir_for_test"], "external_server": true, "external_label": "試し"}),
		"外部のサーバーにつなぐなら、サーバーとモデルを探さない")
	var server := LlmServer.new(ext)
	check_eq(server.model_name(), "試し", "外部のサーバーの名前を表示に使う")
	var off := LlmConfig.new()
	check(not off.load_config({"enabled": false}) and off.problem.contains("無効"), "無効にできる")
	check(LlmConfig.resolve_dir("~/x").ends_with("x") and not LlmConfig.resolve_dir("~/x").begins_with("~"), "~ はユーザーフォルダになる")


func test_brain_falls_back_to_mock_when_server_unusable() -> void:
	# サーバーが見つからない設定で作る。本番の頭脳の中の仮の頭脳で、いつもどおり試合が進む
	var cfg := LlmConfig.new()
	cfg.load_config({"search_dirs": ["no_such_dir_for_test"], "external_server": false})
	var server := LlmServer.new(cfg)
	server.start()
	check(server.is_failed(), "サーバーは使えない状態になる")
	var data := H.load_data()
	var setup := Rng.new(1)
	var builds: Array = [Loot.random_build(data, setup, 1), Loot.random_build(data, setup, 50)]
	var brain := LlmBrain.new(server, MockBrain.new(Rng.new(2)))
	var sim := BattleSim.new(data, builds, [brain, MockBrain.new(Rng.new(3))], ["突撃しろ", ""], ["A", "B"], Rng.new(4))
	var intents: int = 0
	while not sim.over:
		sim.step()
		for e: Dictionary in sim.events:
			if e["type"] == "intent" and e["robot"] == 0:
				intents += 1
	check(intents > 0, "仮の頭脳で方針が届く（%d 回）" % intents)
	check_eq(brain.stats["requests"], 0, "サーバーには問い合わせない")


func test_history_records_sent_raw_and_answer() -> void:
	# 開発用の記録：届いた答えが、送った戦況と同じ行に残る（サーバーは動かさず、届いた答えを直接渡す）
	var cfg := LlmConfig.new()
	cfg.load_config({"search_dirs": ["no_such_dir_for_test"], "external_server": false})
	var brain := LlmBrain.new(LlmServer.new(cfg))
	brain.begin("突撃しろ", BUILD, {})
	var HttpJob := preload("res://agent/http_job.gd")
	for content: String in ['{"intent":"charge","skill":0,"say":"いくぞ"}', "えっと"]:
		brain.history.append({"asked_at": 1.0, "answered_at": -1.0, "ms": 0, "sent": "戦況", "raw": "", "answer": {}, "error": ""})
		var job := HttpJob.new()
		job.state = HttpJob.State.DONE
		job.status_code = 200
		job.body = JSON.stringify({"choices": [{"message": {"content": content}}]}).to_utf8_buffer()
		brain._take_result(job)
	check_eq(brain.history[0]["answer"], {"intent": "charge", "skill": 0, "say": "いくぞ"}, "読めた答えが残る")
	check_eq(brain.history[0]["raw"], '{"intent":"charge","skill":0,"say":"いくぞ"}', "生の答えが残る")
	check(brain.history[0]["answered_at"] >= 0.0, "答えが届いた時間が入る")
	check_eq(brain.history[1]["error"], "壊れた答え", "壊れた答えはそうと分かる")
	brain.begin("", BUILD, {})
	check(brain.history.is_empty(), "次の試合で記録は空に戻る")


func test_cpu_facing_human_uses_llm_only_when_configured() -> void:
	# サーバーは起動しない（外部のサーバーにつなぐ設定で作るだけ。使えない状態にはならない）
	for on: bool in [true, false]:
		var cfg := LlmConfig.new()
		cfg.load_config({"external_server": true, "cpu_opponent": on})
		var agents := DefaultAgents.new()
		agents.llm_server = LlmServer.new(cfg)
		check(agents.make_brain(true, Rng.new(1), 0, false) is LlmBrain, "人間はいつも本番の頭脳（cpu_opponent=%s）" % on)
		check_eq(agents.make_brain(false, Rng.new(2), 3, true) is LlmBrain, on, "人間と戦うCPUは設定しだい（%s）" % on)
		check(agents.make_brain(false, Rng.new(3), 4, false) is MockBrain, "ほかの試合のCPUは仮の頭脳（%s）" % on)
		check_eq(agents.llm_brains.has(3), on, "記録を見られるのは本番の頭脳の機体だけ（%s）" % on)
		agents.make_brain(false, Rng.new(4), 3, false)
		check(not agents.llm_brains.has(3), "次のラウンドで仮の頭脳になれば、前の記録は外れる（%s）" % on)


func test_default_agents_without_llm_use_mock() -> void:
	var agents := DefaultAgents.new()
	check(agents.make_brain(true, Rng.new(1)) is MockBrain, "使わない設定なら人間も仮の頭脳")
	check(agents.brain_status_text().contains("仮の頭脳"), "画面に仮の頭脳と出る")
	agents.shutdown()
