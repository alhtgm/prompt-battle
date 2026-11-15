# 本番の頭脳の測定ツール。モデルごとにサーバーを起動し、決まったプロンプトと戦況の組み合わせで「速さ」と「指示どおりか」を測る。
# 実行（プロジェクト直下で）：godot --headless --path . -s tools/llm_bench.gd
#   モデルを絞る：-- --models=Qwen3.5-0.8B-Q4_K_M.gguf,Qwen3.5-2B-Q4_K_M.gguf　繰り返し回数：-- --repeat=2
#   渡し方を比べる：-- --variants=json,text,text_say（指定しなければ data/llm.json の設定のまま）
extends SceneTree

const LlmConfig := preload("res://agent/llm_config.gd")
const LlmServer := preload("res://agent/llm_server.gd")
const LlmBrain := preload("res://agent/llm_brain.gd")
const GameData := preload("res://core/game_data.gd")

const DEFAULT_MODELS: Array[String] = [
	"Qwen3.5-0.8B-Q4_K_M.gguf",
	"LFM2.5-1.2B-JP-202606-Q4_K_M.gguf",
	"Qwen3.5-2B-Q4_K_M.gguf",
]

## 渡し方の違い（data/llm.json の値を差し替える）
const VARIANTS: Dictionary = {
	"json": {"obs_style": "json", "say_first": false},
	"text": {"obs_style": "text", "say_first": false},
	"text_say": {"obs_style": "text", "say_first": true},
	"greedy": {"temperature": 0.0},
}

const MELEE: Dictionary = {
	"frame": {"name": "標準フレーム"},
	"weapons": [{"name": "ハンマー", "behavior": "strike"}],
	"skills": [{"name": "ブースター", "behavior": "booster"}],
}
const GUNNER: Dictionary = {
	"frame": {"name": "軽量フレーム"},
	"weapons": [{"name": "機関銃", "behavior": "shoot"}],
	"skills": [],
}

## [名前, 機体, プロンプト, 戦況の差分, 正しい方針]
const CASES: Array = [
	["穴：相手が穴の近く", "melee", "相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ", {"enemy.near_pit": true, "enemy.dist": 4.0}, ["push_to_pit"]],
	["穴：相手が穴から遠い", "melee", "相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ", {}, ["charge"]],
	["修理：HPが少ない", "melee", "慎重に戦え。HPが減ったら修理に行け", {"me.hp": 25}, ["go_repair"]],
	["修理：HPが多い", "melee", "慎重に戦え。HPが減ったら修理に行け", {"me.hp": 90}, ["charge", "flank", "keep_distance", "circle", "hold"]],
	["射撃：弾がある", "gunner", "距離をとって撃ちまくれ。弾が切れたら突っ込め", {"me.ammo": 80}, ["keep_distance"]],
	["射撃：弾切れ", "gunner", "距離をとって撃ちまくれ。弾が切れたら突っ込め", {"me.ammo": 0}, ["charge"]],
	["回り込み", "melee", "相手の後ろに回り込んで攻めろ", {}, ["flank"]],
	["周回", "melee", "相手の周りをぐるぐる回って様子を見ろ", {}, ["circle"]],
	["待ち", "melee", "その場から動くな。近づいてきた相手を迎え撃て", {}, ["hold"]],
	["逃げ", "melee", "とにかく逃げ回れ", {}, ["retreat", "circle"]],
	["条件：体力が3割未満", "melee", "強気でいけ。でも体力が3割を切ったら逃げろ", {"me.hp": 20}, ["retreat", "go_repair"]],
	["条件：体力が多い", "melee", "強気でいけ。でも体力が3割を切ったら逃げろ", {"me.hp": 85}, ["charge"]],
	["居座り：試合開始直後", "melee", "初手で修理ステーションに行き居座れ", {"me.hp": 100, "me.intent": "hold", "time_left": 75.0, "enemy.dist": 22.0}, ["go_repair"]],
	["居座り：着いた後", "melee", "初手で修理ステーションに行き居座れ", {"me.hp": 100, "me.intent": "go_repair", "repair.dist": 0.4, "enemy.dist": 6.0}, ["go_repair"]],
]


func _initialize() -> void:
	_run()


func _base_obs() -> Dictionary:
	return {
		"t": 20.0, "time_left": 55.0,
		"me": {"hp": 80, "pos": [0.0, 0.0], "facing": 0, "ammo": null, "stunned": false, "near_pit": false,
			"intent": "charge", "skills": [{"name": "ブースター", "behavior": "booster", "ready": true}]},
		"enemy": {"hp": 70, "dist": 7.0, "dir": "前方", "near_pit": false, "behind_me": false,
			"facing_me": true, "stunned": false},
		"repair": {"dist": 12.0, "left": 30},
		"events": [],
	}


func _obs_for(build_key: String, patch: Dictionary) -> Dictionary:
	var obs: Dictionary = _base_obs()
	if build_key == "gunner":
		obs["me"]["skills"] = []
		obs["me"]["ammo"] = 80
	for path: String in patch:
		var parts: PackedStringArray = path.split(".")
		if parts.size() == 1:
			obs[path] = patch[path]
		else:
			obs[parts[0]][parts[1]] = patch[path]
	return obs


func _wait_frames(n: int) -> void:
	for i: int in n:
		await process_frame


func _run() -> void:
	var models: Array[String] = DEFAULT_MODELS.duplicate()
	var repeat: int = 2
	var variants: Array[String] = [""]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--models="):
			models.assign(arg.get_slice("=", 1).split(","))
		elif arg.begins_with("--repeat="):
			repeat = int(arg.get_slice("=", 1))
		elif arg.begins_with("--variants="):
			variants.assign(arg.get_slice("=", 1).split(","))
	var data := GameData.new()
	data.load_dir()
	var summary: Array[String] = []
	for variant: String in variants:
		for model: String in models:
			await _bench_one(data, model, variant, repeat, summary)
	print("\n==== まとめ ====")
	for line: String in summary:
		print(line)
	quit()


## 1つのモデル・1つの渡し方で全部の組み合わせを測り、まとめの1行を summary に足す
func _bench_one(data: GameData, model: String, variant: String, repeat: int, summary: Array[String]) -> void:
	var override: Dictionary = {"model": "models/" + model}
	override.merge(VARIANTS.get(variant, {}), true)
	var cfg := LlmConfig.new()
	if not cfg.load_config(override):
		print("[%s] 使えない：%s" % [model, cfg.problem])
		return
	var label: String = "%s / %s" % [model.get_basename(), variant if not variant.is_empty() else "設定のまま"]
	var server := LlmServer.new(cfg)
	var t0: int = Time.get_ticks_msec()
	server.start()
	while server.update() == LlmServer.Status.STARTING:
		await process_frame
	if server.status != LlmServer.Status.READY:
		print("[%s] 起動できない：%s" % [label, server.problem])
		server.stop()
		return
	print("\n[%s] 起動 %d ms" % [label, Time.get_ticks_msec() - t0])

	var correct: int = 0
	var total: int = 0
	var broken: int = 0
	var cold_ms: Array[int] = []
	var warm_ms: Array[int] = []
	for c: Array in CASES:
		var brain := LlmBrain.new(server)
		brain.begin(c[2], MELEE if c[1] == "melee" else GUNNER, data.rules)
		if OS.get_cmdline_user_args().has("--prewarm"):
			# 組み立て中の先読みを真似る（ゲームでは組み立て画面で手が止まったときに行う）
			server.prewarm(brain.system_prompt)
			while server.warmed_prompt != brain.system_prompt and Time.get_ticks_msec() - t0 < 600000:
				server.update()
				await process_frame
		for k: int in repeat:
			var before: int = brain.stats["total_ms"]
			var obs: Dictionary = _obs_for(c[1], c[3])
			# 2回目以降は時間と距離を少し変える（ゲームの中と同じく、毎回戦況が違う）
			obs["time_left"] = float(obs["time_left"]) - 2.0 * k
			obs["enemy"]["dist"] = float(obs["enemy"]["dist"]) + 0.3 * k
			brain.request(obs)
			var answer: Dictionary = {}
			while answer.is_empty():
				answer = brain.poll(0.0)
				if answer.is_empty():
					await process_frame
			var ms: int = brain.stats["total_ms"] - before
			(cold_ms if k == 0 else warm_ms).append(ms)
			total += 1
			var ok: bool = (c[4] as Array).has(answer["intent"])
			if answer["intent"] == "":
				broken += 1
			if ok:
				correct += 1
			print("  %s %-18s → %-13s %s「%s」 %d ms%s" % ["○" if ok else "×", c[0], answer["intent"],
				"skill=%s" % str(answer["skill"]), answer["say"], ms,
				"" if brain.last_error.is_empty() else "（%s）" % brain.last_error])
	server.stop()
	await _wait_frames(30)  # サーバーが終わってポートが空くのを待つ
	var line: String = "%-40s 正解 %2d/%d（%3d%%） 壊れた答え %d　1回目 平均 %4d ms　2回目以降 平均 %4d ms（最大 %d ms）" % [
		label, correct, total, roundi(100.0 * correct / maxf(1, total)), broken,
		_avg(cold_ms), _avg(warm_ms), warm_ms.max() if not warm_ms.is_empty() else 0]
	summary.append(line)
	print("  → " + line)


func _avg(xs: Array[int]) -> int:
	if xs.is_empty():
		return 0
	var s: int = 0
	for x: int in xs:
		s += x
	return s / xs.size()
