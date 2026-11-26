# 試作：ルール方式の頭脳。試合前にプレイヤーの指示を「土台」のルールに翻訳して固定し、試合中は数秒おきに LLM が「作戦欄」を1か所だけ直す。
# ロボットは毎刻みルールを上から評価して方針を切り替える。試作なので BattleSim の状態を直接読む（本実装では評価を BattleSim 側へ移す）。
extends RefCounted

const RuleSet := preload("res://proto/rule_pilot/rule_set.gd")
const HttpJob := preload("res://agent/http_job.gd")
const LlmBrain := preload("res://agent/llm_brain.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const Robot := preload("res://core/battle_robot.gd")
const Observation := preload("res://core/observation.gd")

const SAY_MAX: int = 8
const WHY_MAX: int = 24
const MAX_TACTICS: int = 3
const MIN_HOLD_SEC: float = 0.25
const OP_TEXT: Dictionary = {"add": "作戦欄に追加", "replace": "%d番を差し替え", "delete": "%d番を削除", "keep": "様子見"}

var sim: RefCounted = null
var index: int = 0
var host: String = "127.0.0.1"
var port: int = 8399
var rewrite_interval: float = 4.0
## 見直しの時刻をずらす量（0 か、間隔の半分）。2台を半周ずらし、画面全体では交互に作戦が変わるようにする
var phase_offset: float = 0.0
var timeout_sec: float = 25.0

var prompt: String = ""
var build: Dictionary = {}
var n_skills: int = 0
var ruleset := RuleSet.new()
var have_rules: bool = false
var say: String = ""
var active: int = -1
## 画面用：作戦欄を実際に変えた回数と、問い合わせの履歴
## history の1件：{"asked","got": 時刻, "ok": 答えが使えたか, "op","n","why", "rejected": 却下の理由（なければ空）}
var rewrites: int = 0
var history: Array[Dictionary] = []
## 画面用：直前の変更で変わった行・変更前の文字・消したルール
var changed: Array[bool] = []
var prev_text: Array[String] = []
var removed_text: String = ""
var last_error: String = ""
var thinking: bool = false
var asked_at: float = 0.0
var log: Array[String] = []

var _job: HttpJob = null
var _job_is_base: bool = false
var _system: String = ""
var _next_ask_t: float = 0.0
var _last_hp: float = -1.0
var _last_hit_t: float = -100.0
var _last_dealt: float = 0.0
var _last_give_t: float = -100.0
var _switched_t: float = -100.0
var _last_poll_t: float = 0.0
## 前回の問い合わせからの、与えた・受けたダメージ
var _since_given: float = 0.0
var _since_taken: float = 0.0


func begin(p: String, b: Dictionary, _rules: Dictionary) -> void:
	prompt = p
	build = b
	n_skills = (b.get("skills", []) as Array).size()
	_system = build_system_prompt(p, b)
	ruleset.rules = RuleSet.default_rules()
	_reset_marks()
	_next_ask_t = next_slot(-1.0)
	_send_base()  # 試合の前に、指示を土台のルールに翻訳させる


## 試合側からの戦況は使わない（決まった時刻に、その場で戦況を組み立てて聞く）
func request(_observation: Dictionary) -> void:
	pass


func poll(now: float) -> Dictionary:
	if _job != null and _job.poll() != HttpJob.State.RUNNING:
		_take(_job, now)
		_job = null
	if sim == null or sim.robots.is_empty():
		return {}
	var me: Robot = sim.robots[index]
	var en: Robot = sim.robots[1 - index]
	if _job == null and have_rules and now >= _next_ask_t:
		_send_patch(Observation.build(me, en, now, sim.time_left(), sim._b), now)
	# 実行中のルールの成績をつける
	var d_taken: float = maxf(0.0, _last_hp - me.hp) if _last_hp >= 0.0 else 0.0
	var d_given: float = maxf(0.0, me.dealt - _last_dealt)
	if active >= 0 and active < ruleset.rules.size():
		var cur: Dictionary = ruleset.rules[active]
		cur["sec"] = float(cur["sec"]) + maxf(0.0, now - _last_poll_t)
		cur["given"] = float(cur["given"]) + d_given
		cur["taken"] = float(cur["taken"]) + d_taken
	_since_given += d_given
	_since_taken += d_taken
	if d_taken > 0.01:
		_last_hit_t = now
	if d_given > 0.01:
		_last_give_t = now
	_last_hp = me.hp
	_last_dealt = me.dealt
	_last_poll_t = now
	var f: Dictionary = RuleSet.facts(me, en, now, sim.time_left(), sim._b, _last_hit_t, _last_give_t)
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


func n_tactics() -> int:
	var n: int = 0
	for r: Dictionary in ruleset.rules:
		if not r["lock"]:
			n += 1
	return n


## 次の見直しまでの秒数
func next_ask_in(now: float) -> float:
	return _next_ask_t - now


## now より後の、次の見直しの時刻。見直しは「間隔の半分＋ずらす量」から間隔ごと（例：青 2・6・10秒、橙 4・8・12秒）
## 答えが遅れて時刻を過ぎたら、その回は飛ばして次の時刻を待つ（リズムを崩さない）
func next_slot(now: float) -> float:
	var first: float = rewrite_interval * 0.5 + phase_offset
	if now < first:
		return first
	return first + (floorf((now - first) / rewrite_interval) + 1.0) * rewrite_interval


static func op_text(op: String, n: int) -> String:
	var t: String = OP_TEXT.get(op, op)
	return t % n if op in ["replace", "delete"] else t


# ---- 問い合わせ ----

func _send_base() -> void:
	var user: String = "試合開始前。プレイヤーの指示を「土台」のルール（3〜4個、最後は「いつも」）にする。" + \
		"答えは {\"say\":\"作戦名\",\"rules\":[{\"if\":\"条件\",\"do\":\"行動\",\"skill\":番号かnull},…]} の形だけ。say は%d文字以内。" % SAY_MAX
	_job_is_base = true
	_post(user, build_base_grammar(n_skills), 300, 0.3, 0.0)


func _send_patch(obs: Variant, now: float) -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("戦況：" + JSON.stringify(LlmBrain.compact_observation(obs)))
	lines.append("今のルールと成績（実行した秒数・そのあいだに与えたダメージ・受けたダメージ）：")
	for k: int in ruleset.rules.size():
		var r: Dictionary = ruleset.rules[k]
		lines.append("%d. [%s] if=%s do=%s skill=%s：%.1f秒 与%d 受%d" % [k + 1, "土台・変更不可" if r["lock"] else "作戦欄",
			"&".join(r["if"]) if not (r["if"] as Array).is_empty() else "（いつも）", r["do"],
			str(r["skill"]) if r["skill"] >= 0 else "null", float(r["sec"]), roundi(float(r["given"])), roundi(float(r["taken"]))])
	lines.append("前回の問い合わせから今まで：与えたダメージ%d、受けたダメージ%d。" % [roundi(_since_given), roundi(_since_taken)])
	var k_now: int = n_tactics()
	lines.append("作戦欄は今%d行（最大%d行）。作戦欄を1か所だけ直すか、様子見（keep）にする。" % [k_now, MAX_TACTICS])
	_since_given = 0.0
	_since_taken = 0.0
	_job_is_base = false
	_post("\n".join(lines), build_patch_grammar(k_now, n_skills), 120, 0.4, now)


func _post(user: String, grammar: String, max_tokens: int, temp: float, now: float) -> void:
	var payload: Dictionary = {
		"messages": [{"role": "system", "content": _system}, {"role": "user", "content": user}],
		"grammar": grammar, "max_tokens": max_tokens, "temperature": temp, "cache_prompt": true,
		"chat_template_kwargs": {"enable_thinking": false},
	}
	_job = HttpJob.new()
	_job.start(host, port, HTTPClient.METHOD_POST, "/v1/chat/completions", JSON.stringify(payload), timeout_sec)
	asked_at = now
	thinking = true


func _take(job: HttpJob, now: float) -> void:
	thinking = false
	_next_ask_t = next_slot(now)
	var ans: Variant = null
	if job.state == HttpJob.State.FAILED or job.status_code != 200:
		last_error = job.error if job.state == HttpJob.State.FAILED else "HTTP %d" % job.status_code
	else:
		var parsed: Variant = LlmBrain.quiet_parse(job.text())
		if parsed is Dictionary and not (parsed.get("choices", []) as Array).is_empty():
			ans = LlmBrain.quiet_parse(str(parsed["choices"][0].get("message", {}).get("content", "")))
		last_error = "" if ans is Dictionary else "壊れた答え"
	if _job_is_base:
		_take_base(ans if ans is Dictionary else {})
		return
	if not (ans is Dictionary):
		history.append({"asked": asked_at, "got": now, "ok": false, "op": "", "n": 0, "why": "", "rejected": ""})
		_add_log("%.1f秒 失敗（%s）" % [now, last_error])
		return
	_apply_patch(ans, now)


## 土台：指示を翻訳したルールを固定で使う。失敗したら既定のルールのまま
func _take_base(ans: Dictionary) -> void:
	have_rules = true
	var base: Array[Dictionary] = RuleSet.parse(ans.get("rules"), n_skills, true)
	if base.is_empty():
		_add_log("土台の翻訳に失敗（%s）。既定のルールで戦う" % (last_error if not last_error.is_empty() else "壊れた答え"))
		return
	ruleset.rules = base
	say = str(ans.get("say", "")).left(SAY_MAX)
	_reset_marks()
	_add_log("土台を作成「%s」（%d行）" % [say, base.size()])


## 作戦欄を1か所だけ直す。おかしな変更（矛盾・重複・隠れて使われない・ほかの行を隠す）はコードで却下する
func _apply_patch(ans: Dictionary, now: float) -> void:
	var op: String = str(ans.get("op", "keep"))
	var n: int = int(ans.get("n", 0)) if (ans.get("n") is float or ans.get("n") is int) else 0
	var why: String = str(ans.get("why", "")).left(WHY_MAX)
	var entry: Dictionary = {"asked": asked_at, "got": now, "ok": true, "op": op, "n": n, "why": why, "rejected": ""}
	history.append(entry)
	var k_now: int = n_tactics()
	if op == "keep":
		_add_log("%.1f秒 様子見「%s」" % [now, why])
		return
	var cand: Array[Dictionary] = ruleset.rules.duplicate()
	var j: int = -1
	var old_text: String = ""
	var removed: String = ""
	var reason: String = ""
	if op == "delete":
		if n < 1 or n > k_now:
			reason = "作戦欄にない番号"
		else:
			removed = RuleSet.rule_to_text(cand[n - 1])
			cand.remove_at(n - 1)
	else:
		var nr: Dictionary = RuleSet.parse_rule(ans.get("rule"), n_skills, false)
		if nr.is_empty() or (nr["if"] as Array).is_empty():
			reason = "条件のないルール"
		elif op == "add":
			if k_now >= MAX_TACTICS:
				reason = "作戦欄がいっぱい"
			else:
				cand.insert(0, nr)
				j = 0
		elif op == "replace":
			if n < 1 or n > k_now:
				reason = "作戦欄にない番号"
			else:
				old_text = RuleSet.rule_to_text(cand[n - 1])
				cand[n - 1] = nr
				j = n - 1
		else:
			reason = "知らない操作"
	if reason.is_empty() and j >= 0:
		reason = _check_new_rule(cand, j)
	if not reason.is_empty():
		entry["rejected"] = reason
		_add_log("%.1f秒 却下：%s（%s）" % [now, op_text(op, n), reason])
		return
	ruleset.rules = cand
	active = -1
	_reset_marks()
	if j >= 0:
		changed[j] = true
		prev_text[j] = old_text
	removed_text = removed
	rewrites += 1
	_add_log("%.1f秒 %s「%s」" % [now, op_text(op, n), why])


func _check_new_rule(cand: Array[Dictionary], j: int) -> String:
	var nr: Dictionary = cand[j]
	if RuleSet.is_contradictory(nr["if"]):
		return "同時に成り立たない条件"
	for i: int in cand.size():
		if i != j and RuleSet.same_rule(cand[i], nr):
			return "%d番と同じルール" % (i + 1)
	var rs := RuleSet.new()
	rs.rules = cand
	var by: int = rs.shadowed_by(j)
	if by >= 0:
		return "%d番に隠れて使われない" % (by + 1)
	for i: int in range(j + 1, cand.size() - 1):
		if rs.shadowed_by(i) == j:
			return "%s%d番が使われなくなる" % ["土台の" if cand[i]["lock"] else "", i + 1]
	return ""


func _reset_marks() -> void:
	changed.clear()
	prev_text.clear()
	for i: int in ruleset.rules.size():
		changed.append(false)
		prev_text.append("")
	removed_text = ""


func _add_log(s: String) -> void:
	log.append(s)
	if log.size() > 30:
		log.pop_front()


# ---- 指示文と文法 ----

static func build_system_prompt(p: String, b: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("あなたはロボット対戦ゲームの操縦士。ロボットは「ルール」に従って毎瞬（1/60秒ごと）自動で動く。")
	lines.append("ルールは上から順に調べ、条件がすべて当てはまった最初のルールの行動（do）を実行する。")
	lines.append("ルールは2つの欄に分かれる。上が「作戦欄」（最大%d行。試合中にあなたが戦況を見て直す）、下が「土台」（試合前にプレイヤーの指示から作る固定のルール。最後は条件なしの「いつも」）。" % MAX_TACTICS)
	lines.append("土台の作り方：プレイヤーの指示をそのままルールにする。3〜4個。最後の「いつも」は普段の基本の動きなので、指示に合った攻め方（charge・flank・circle・keep_distance など）にする。hold は「動くな」「待ち伏せ」の指示のときだけ使う。")
	lines.append("作戦欄の直し方：1回に1か所だけ。add（作戦欄の一番上に追加）、replace（作戦欄のn番を差し替え）、delete（作戦欄のn番を削除）、keep（様子見）のどれか。土台は変えられない。")
	lines.append("作戦欄のルールには必ず条件を付ける。作戦欄は土台より先に調べられるので、特定の場面で土台の動きを上書きするのに使う。プレイヤーの指示に反するルールは作らない。")
	lines.append("判断の目安：受けたダメージが与えたダメージより多いルールは差し替えるか削除する。0秒のまま使われていない作戦欄のルールは削除するか、別の場面のルールに差し替える。相手の動き（突っ込んでくる・離れていく・こちらを向いている）や場所（穴・壁）への対策が足りなければ追加する。うまくいっているなら keep。")
	lines.append("why には、その判断の理由を%d文字以内の日本語で先に書く。" % WHY_MAX)
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
	var pp: String = p.strip_edges()
	lines.append("プレイヤーの指示：「%s」" % (pp if not pp.is_empty() else "（指示なし。自分で考えて戦え）"))
	return "\n".join(lines)


static func _common_grammar(n_skills: int) -> PackedStringArray:
	var atoms: PackedStringArray = PackedStringArray()
	for a: String in RuleSet.ATOMS:
		atoms.append("\"%s\"" % a)
	var intents: PackedStringArray = PackedStringArray()
	for it: String in RobotDriver.INTENTS:
		intents.append("\"%s\"" % it)
	var skills: PackedStringArray = ["\"null\""]
	for i: int in n_skills:
		skills.append("\"%d\"" % i)
	return PackedStringArray([
		"rule ::= \"{\\\"if\\\":\\\"\" cond \"\\\",\\\"do\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \"}\"",
		"cond ::= atom | atom \"&\" atom",
		"atom ::= " + " | ".join(atoms),
		"intent ::= " + " | ".join(intents),
		"skill ::= " + " | ".join(skills),
	])


static func build_base_grammar(n_skills: int) -> String:
	var g: PackedStringArray = _common_grammar(n_skills)
	g.append("root ::= \"{\\\"say\\\":\\\"\" say \"\\\",\\\"rules\\\":[\" (rule \",\"){2,3} last \"]}\"")
	g.append("last ::= \"{\\\"if\\\":\\\"\\\",\\\"do\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \"}\"")
	g.append("say ::= [^\"\\\\\\n]{1,%d}" % SAY_MAX)
	return "\n".join(g)


## 作戦欄の変更：理由を先に書かせてから、操作を1つ。今の作戦欄の行数で、できる操作と番号を絞る
static func build_patch_grammar(k: int, n_skills: int) -> String:
	var g: PackedStringArray = _common_grammar(n_skills)
	var ops: PackedStringArray = ["keepop"]
	if k < MAX_TACTICS:
		ops.append("addop")
	if k > 0:
		ops.append("repop")
		ops.append("delop")
		var nums: PackedStringArray = PackedStringArray()
		for i: int in k:
			nums.append("\"%d\"" % (i + 1))
		g.append("num ::= " + " | ".join(nums))
	g.append("root ::= \"{\\\"why\\\":\\\"\" why \"\\\",\" (" + " | ".join(ops) + ") \"}\"")
	g.append("keepop ::= \"\\\"op\\\":\\\"keep\\\"\"")
	if k < MAX_TACTICS:
		g.append("addop ::= \"\\\"op\\\":\\\"add\\\",\\\"rule\\\":\" rule")
	if k > 0:  # 使わない記号を定義だけしておくと、未定義の num を参照してしまうので分ける
		g.append("repop ::= \"\\\"op\\\":\\\"replace\\\",\\\"n\\\":\" num \",\\\"rule\\\":\" rule")
		g.append("delop ::= \"\\\"op\\\":\\\"delete\\\",\\\"n\\\":\" num")
	g.append("why ::= [^\"\\\\\\n]{1,%d}" % WHY_MAX)
	return "\n".join(g)
