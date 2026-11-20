# 試作：ルール方式の頭脳。LLM は数秒おきにルール全体を書き直し、ロボットは毎刻みルールを評価して方針を切り替える。
# 試作なので試合（BattleSim）の状態を直接読む。本実装ではルールの評価を BattleSim 側に移し、頭脳はルールを返すだけにする。
extends RefCounted

const RuleSet := preload("res://proto/rule_pilot/rule_set.gd")
const HttpJob := preload("res://agent/http_job.gd")
const LlmBrain := preload("res://agent/llm_brain.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const Robot := preload("res://core/battle_robot.gd")

const SAY_MAX: int = 8
const MIN_HOLD_SEC: float = 0.25

var sim: RefCounted = null
var index: int = 0
var host: String = "127.0.0.1"
var port: int = 8399
var rewrite_interval: float = 6.0
var timeout_sec: float = 25.0

var prompt: String = ""
var build: Dictionary = {}
var n_skills: int = 0
var ruleset := RuleSet.new()
var have_rules: bool = false
var say: String = ""
var active: int = -1
## 画面用：書き換えの記録
var rewrites: int = 0
var last_rewrite_t: float = -100.0
var last_rewrite_ms: int = 0
var changed: Array[bool] = []
var last_error: String = ""
var thinking: bool = false
var log: Array[String] = []

var _job: HttpJob = null
var _system: String = ""
var _grammar: String = ""
var _next_ask_t: float = 0.0
var _pending_obs: Variant = null
var _last_hp: float = -1.0
var _last_hit_t: float = -100.0
var _switched_t: float = -100.0
var _asked_at: float = 0.0


func begin(p: String, b: Dictionary, _rules: Dictionary) -> void:
	prompt = p
	build = b
	n_skills = (b.get("skills", []) as Array).size()
	_system = build_system_prompt(p, b)
	_grammar = build_grammar(n_skills)
	ruleset.rules = RuleSet.default_rules()
	changed.clear()
	for i: int in ruleset.rules.size():
		changed.append(false)
	_send(null, 0.0)  # 試合の前に、指示を最初のルールに翻訳させる


func request(observation: Dictionary) -> void:
	_pending_obs = observation


func poll(now: float) -> Dictionary:
	if _job != null and _job.poll() != HttpJob.State.RUNNING:
		_take(_job, now)
		_job = null
	if _job == null and _pending_obs != null and now >= _next_ask_t and have_rules:
		_send(_pending_obs, now)
		_pending_obs = null
	if sim == null or sim.robots.is_empty():
		return {}
	var me: Robot = sim.robots[index]
	var en: Robot = sim.robots[1 - index]
	if _last_hp >= 0.0 and me.hp < _last_hp - 0.01:
		_last_hit_t = now
	_last_hp = me.hp
	var f: Dictionary = RuleSet.facts(me, en, now, sim.time_left(), sim._b, _last_hit_t)
	var pick: int = ruleset.pick(f)
	var answer: Dictionary = {}
	if pick != active and (now - _switched_t >= MIN_HOLD_SEC or active < 0):
		active = pick
		_switched_t = now
		var r: Dictionary = ruleset.rules[pick]
		answer = {"intent": r["do"], "skill": r["skill"] if r["skill"] >= 0 else null, "say": say}
	elif active >= 0 and active < ruleset.rules.size():
		var r2: Dictionary = ruleset.rules[active]
		if r2["skill"] >= 0 and me.want_skill < 0 and me.skills[r2["skill"]].is_ready():
			answer = {"intent": r2["do"], "skill": r2["skill"], "say": say}
	return answer


func _send(obs: Variant, now: float) -> void:
	var user: String = "試合開始前。まずプレイヤーの指示をルールにする。" if obs == null else \
		"戦況：%s\n今のルール：%s\n戦況とプレイヤーの指示に合わせて、ルールを書き直す（よければ同じでもよい）。" % [
			JSON.stringify(LlmBrain.compact_observation(obs)), _rules_json()]
	var payload: Dictionary = {
		"messages": [{"role": "system", "content": _system}, {"role": "user", "content": user}],
		"grammar": _grammar, "max_tokens": 200, "temperature": 0.3, "cache_prompt": true,
		"chat_template_kwargs": {"enable_thinking": false},
	}
	_job = HttpJob.new()
	_job.start(host, port, HTTPClient.METHOD_POST, "/v1/chat/completions", JSON.stringify(payload), timeout_sec)
	_asked_at = now
	thinking = true


func _take(job: HttpJob, now: float) -> void:
	thinking = false
	_next_ask_t = now + rewrite_interval
	last_rewrite_ms = job.elapsed_ms
	if job.state == HttpJob.State.FAILED or job.status_code != 200:
		last_error = job.error if job.state == HttpJob.State.FAILED else "HTTP %d" % job.status_code
		have_rules = true  # 使えないときは既定のルールのまま戦う
		_add_log("書き換え失敗（%s）" % last_error)
		return
	var parsed: Variant = LlmBrain.quiet_parse(job.text())
	var content: String = ""
	if parsed is Dictionary and not (parsed.get("choices", []) as Array).is_empty():
		content = str(parsed["choices"][0].get("message", {}).get("content", ""))
	var ans: Variant = LlmBrain.quiet_parse(content)
	var new_rules: Array[Dictionary] = RuleSet.parse(ans.get("rules") if ans is Dictionary else null, n_skills)
	if new_rules.is_empty():
		last_error = "壊れた答え"
		have_rules = true
		_add_log("書き換え失敗（壊れた答え）")
		return
	last_error = ""
	var old: Array[String] = []
	for r: Dictionary in ruleset.rules:
		old.append(RuleSet.rule_to_text(r))
	changed.clear()
	var n_changed: int = 0
	for i: int in new_rules.size():
		var c: bool = i >= old.size() or old[i] != RuleSet.rule_to_text(new_rules[i])
		changed.append(c)
		if c:
			n_changed += 1
	ruleset.rules = new_rules
	active = -1
	say = str(ans.get("say", "")).left(SAY_MAX)
	rewrites += 1
	last_rewrite_t = now
	have_rules = true
	_add_log("%.1f秒 書き換え%d回目（%.1f秒かかった、%d行変更）「%s」" % [now, rewrites, job.elapsed_ms / 1000.0, n_changed, say])


func _add_log(s: String) -> void:
	log.append(s)
	if log.size() > 6:
		log.pop_front()


func _rules_json() -> String:
	var a: Array = []
	for r: Dictionary in ruleset.rules:
		a.append({"if": "&".join(r["if"]), "do": r["do"], "skill": r["skill"] if r["skill"] >= 0 else null})
	return JSON.stringify(a)


static func build_system_prompt(p: String, b: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("あなたはロボット対戦ゲームの操縦士。ロボットは「ルール」に従って毎瞬（1/60秒ごと）自動で動く。あなたの仕事は、プレイヤーの指示と戦況を見て、ルールを書くこと。")
	lines.append("ルールは上から順に調べ、条件がすべて当てはまった最初のルールの行動（do）を実行する。最後のルールは条件なし（if が空）で「いつも」の行動。ルールは2〜4個。")
	lines.append("最後の「いつも」のルールは普段の基本の動きなので、指示に合った攻め方（charge・flank・circle・keep_distance など）にする。hold は「動くな」「待ち伏せ」の指示のときだけ使う。")
	lines.append("条件（if）：次の語を1つ、または & で2つつなぐ。")
	for a: String in RuleSet.ATOMS:
		lines.append("- %s：%s" % [a, RuleSet.ATOMS[a]])
	lines.append("行動（do）：")
	for it: String in RobotDriver.INTENTS:
		lines.append("- %s：%s" % [it, LlmBrain.INTENT_TEXT.get(it, it)])
	var skills: Array = b.get("skills", [])
	if skills.is_empty():
		lines.append("スキルはない。skill はいつも null。")
	else:
		lines.append("skill：そのルールの間に使うスキルの番号（使えるようになったら自動で使う）。使わないなら null。")
		for i: int in skills.size():
			lines.append("- %d：%s（%s）" % [i, skills[i].get("name", ""), LlmBrain.BEHAVIOR_TEXT.get(skills[i].get("behavior", ""), "")])
	var ws: PackedStringArray = PackedStringArray()
	var melee: bool = false
	var shooter: bool = false
	for w: Dictionary in b.get("weapons", []):
		ws.append("%s（%s）" % [w.get("name", ""), LlmBrain.BEHAVIOR_TEXT.get(w.get("behavior", ""), "")])
		if w.get("behavior", "") == "shoot":
			shooter = true
		else:
			melee = true
	lines.append("自分の機体：%s。武器：%s。" % [b.get("frame", {}).get("name", ""), "、".join(ws) if ws.size() > 0 else "なし"])
	lines.append("武器は条件が合えば自動で使われる。%s%s" % [
		"近接武器は相手に接触しないと当たらないので、charge・flank・push_to_pit で近づく。" if melee else "",
		"撃つ武器は正面の相手を射程内で撃つので keep_distance が向く。弾が切れたら近接で戦うしかない。" if shooter else ""])
	lines.append("答えは {\"say\":\"作戦の一言\",\"rules\":[{\"if\":\"条件\",\"do\":\"行動\",\"skill\":番号かnull},…]} の形だけ。say は今の作戦を表す%d文字以内の日本語。" % SAY_MAX)
	var pp: String = p.strip_edges()
	lines.append("プレイヤーの指示：「%s」" % (pp if not pp.is_empty() else "（指示なし。自分で考えて戦え）"))
	return "\n".join(lines)


static func build_grammar(n: int) -> String:
	var atoms: PackedStringArray = PackedStringArray()
	for a: String in RuleSet.ATOMS:
		atoms.append("\"%s\"" % a)
	var intents: PackedStringArray = PackedStringArray()
	for it: String in RobotDriver.INTENTS:
		intents.append("\"%s\"" % it)
	var skills: PackedStringArray = ["\"null\""]
	for i: int in n:
		skills.append("\"%d\"" % i)
	return "\n".join([
		"root ::= \"{\\\"say\\\":\\\"\" say \"\\\",\\\"rules\\\":[\" (rule \",\"){1,3} last \"]}\"",
		"rule ::= \"{\\\"if\\\":\\\"\" cond \"\\\",\\\"do\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \"}\"",
		"last ::= \"{\\\"if\\\":\\\"\\\",\\\"do\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \"}\"",
		"cond ::= atom | atom \"&\" atom",
		"atom ::= " + " | ".join(atoms),
		"intent ::= " + " | ".join(intents),
		"skill ::= " + " | ".join(skills),
		"say ::= [^\"\\\\\\n]{1,%d}" % SAY_MAX,
	])
