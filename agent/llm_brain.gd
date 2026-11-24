# 本番の頭脳。小さいLLM（llama-server）に、プレイヤーのプロンプトと戦況を渡して方針を決めさせる。
# 変わらない部分（ルール・機体・プロンプト）は最初の1回だけ組み立て、毎回は戦況だけを足す（サーバー側で前半が使い回される）。
# 出力は文法で {"intent","skill","say"} の形に縛る。答えを待たずに試合を進め、壊れた答えや時間切れは「えっと…」にする。
# サーバーが使えないときは、中に持っている仮の頭脳で動く。
extends "res://agent/agent_brain.gd"

const LlmServer := preload("res://agent/llm_server.gd")
const HttpJob := preload("res://agent/http_job.gd")
const RobotDriver := preload("res://core/robot_driver.gd")

const INTENT_TEXT: Dictionary = {
	"charge": "相手に突撃する",
	"flank": "相手の後ろに回り込んでから攻める",
	"keep_distance": "相手を向いたまま距離を保つ（撃つ武器向き）",
	"retreat": "相手から逃げる",
	"push_to_pit": "相手の向こう側に回って、相手を穴へ押し込む",
	"go_repair": "一番近い回復パックを取りに行って回復する（ダメージを受けているときだけ取れる）",
	"circle": "相手の周りを回る",
	"hold": "その場で相手を向いて待つ",
}
const BEHAVIOR_TEXT: Dictionary = {
	"grind": "触れている間削る", "strike": "叩く", "lift": "ひっくり返す", "ram": "体当たり", "shoot": "撃つ",
	"hook": "前の相手に釣り針を撃って目の前まで引き寄せ、少し動けなくする（届く距離で相手を向くと撃つ）",
	"flame": "前の近い相手（6m以内）に炎を浴びせ続け、ときどき火傷（しばらく燃え続けてダメージ）にする",
	"booster": "一時的に速くなる", "shield": "一時的に受けるダメージが減る", "repair": "HPを回復する",
	"shockwave": "近くの相手を吹き飛ばす", "emp": "近くの相手を止める", "overclock": "一時的に与えるダメージが増える",
	"self_destruct": "HPが0になると自動で相手に突っ込んで自爆する。選ぶ必要はなく、選んでも何も起きない",
}

## 壊れた答えのとき BattleSim に渡すもの（方針が不正なので、前の方針を続けて「えっと…」と言う）
const CONFUSED: Dictionary = {"intent": "", "skill": null, "say": ""}

var server: LlmServer
## サーバーが使えないときに代わりに動かす頭脳
var fallback: RefCounted
var system_prompt: String = ""
var grammar: String = ""
var skill_count: int = 0
## 測定用の記録
var stats: Dictionary = {"requests": 0, "ok": 0, "bad": 0, "failed": 0, "total_ms": 0, "max_ms": 0}
var last_error: String = ""
var last_raw: String = ""
## 開発用の記録：1回の問い合わせごとに、送った戦況・生の答え・読み取った結果・かかった時間を残す（新しいものが後ろ）
## {"asked_at": 試合時間, "answered_at": 試合時間か -1, "ms": int, "sent": String, "raw": String, "answer": Dictionary, "error": String}
var history: Array[Dictionary] = []
const HISTORY_MAX: int = 50

var _job: HttpJob = null
var _now: float = 0.0
var _pending_obs: Dictionary = {}
var _answer: Dictionary = {}
var _say_max: int = 12
var _text_obs: bool = true
var _describe: Dictionary = {}


func _init(llm_server: LlmServer, fallback_brain: RefCounted = null) -> void:
	server = llm_server
	fallback = fallback_brain


func begin(prompt: String, build: Dictionary, rules: Dictionary) -> void:
	var cfg: Variant = server.config
	_say_max = int(cfg.get_value("say_max_chars"))
	_text_obs = str(cfg.get_value("obs_style")) == "text"
	_describe = cfg.get_value("describe")
	var say_first: bool = bool(cfg.get_value("say_first"))
	skill_count = (build.get("skills", []) as Array).size()
	system_prompt = build_system_prompt(prompt, build, _say_max, say_first, _text_obs)
	grammar = build_grammar(skill_count, _say_max, say_first)
	_pending_obs = {}
	_answer = {}
	history.clear()
	if _job != null:
		_job.cancel()
	_job = null
	if fallback != null:
		fallback.begin(prompt, build, rules)


func request(observation: Dictionary) -> void:
	if _use_fallback():
		fallback.request(observation)
		return
	_pending_obs = observation  # 前の問い合わせ中なら、終わってから一番新しい戦況だけを送る
	_try_send()


func poll(now: float) -> Dictionary:
	if _use_fallback():
		return fallback.poll(now)
	_now = now
	if _job != null and _job.poll() != HttpJob.State.RUNNING:
		_take_result(_job)
		_job = null
	_try_send()
	if _answer.is_empty():
		return {}
	var a: Dictionary = _answer
	_answer = {}
	return a


## サーバーが使えないので、中の仮の頭脳で動いているか
func using_fallback() -> bool:
	return fallback != null and server.is_failed()


func _use_fallback() -> bool:
	return using_fallback()


func _try_send() -> void:
	if _job != null or _pending_obs.is_empty() or not server.is_ready():
		return
	var cfg: Variant = server.config
	var sent: String = describe_observation(_pending_obs, _describe) if _text_obs \
		else JSON.stringify(compact_observation(_pending_obs))
	history.append({"asked_at": _now, "answered_at": -1.0, "ms": 0, "sent": sent, "raw": "", "answer": {}, "error": ""})
	if history.size() > HISTORY_MAX:
		history.pop_front()
	var payload: Dictionary = {
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": sent},
		],
		"grammar": grammar,
		"max_tokens": int(cfg.get_value("max_tokens")),
		"temperature": float(cfg.get_value("temperature")),
		"cache_prompt": true,
		"chat_template_kwargs": {"enable_thinking": false},
	}
	_pending_obs = {}
	_job = HttpJob.new()
	_job.start(str(cfg.get_value("host")), int(cfg.get_value("port")), HTTPClient.METHOD_POST,
		"/v1/chat/completions", JSON.stringify(payload), float(cfg.get_value("request_timeout_sec")))
	stats["requests"] += 1


func _take_result(job: HttpJob) -> void:
	stats["total_ms"] += job.elapsed_ms
	stats["max_ms"] = maxi(int(stats["max_ms"]), job.elapsed_ms)
	var rec: Dictionary = history.back() if not history.is_empty() else {}
	rec["answered_at"] = _now
	rec["ms"] = job.elapsed_ms
	if job.state == HttpJob.State.FAILED or job.status_code != 200:
		stats["failed"] += 1
		last_error = job.error if job.state == HttpJob.State.FAILED else "HTTP %d" % job.status_code
		rec["error"] = last_error
		_answer = CONFUSED.duplicate()
		return
	var parsed: Variant = quiet_parse(job.text())
	var content: String = ""
	if parsed is Dictionary:
		var choices: Variant = parsed.get("choices", [])
		if choices is Array and not (choices as Array).is_empty():
			content = str(choices[0].get("message", {}).get("content", ""))
	last_raw = content
	rec["raw"] = content
	var answer: Dictionary = parse_answer(content, skill_count, _say_max)
	if answer.is_empty():
		stats["bad"] += 1
		rec["error"] = "壊れた答え"
		_answer = CONFUSED.duplicate()
	else:
		stats["ok"] += 1
		rec["answer"] = answer
		_answer = answer


# ---- 組み立てと読み取り（画面なしでテストできるよう static にする） ----

## 変わらない部分：役目、方針の一覧、スキル、機体、戦況の見方、答えの形、プレイヤーの指示
static func build_system_prompt(prompt: String, build: Dictionary, say_max: int, say_first: bool = false,
		text_obs: bool = false) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("あなたはロボット対戦ゲームの操縦士。プレイヤーの指示を一番大事に守り、戦況を見て今の方針（intent）を1つ選ぶ。")
	lines.append("方針（intent）：")
	for intent: String in RobotDriver.INTENTS:
		lines.append("- %s：%s" % [intent, INTENT_TEXT.get(intent, intent)])
	var skills: Array = build.get("skills", [])
	if skills.is_empty():
		lines.append("スキルはない。skill はいつも null。")
	else:
		lines.append("スキル（skill）：番号で今すぐ使う。使わないときは null。戦況の me.skills_ready にある番号だけ使える。")
		for i: int in skills.size():
			var s: Dictionary = skills[i]
			lines.append("- %d：%s（%s）" % [i, s.get("name", ""), BEHAVIOR_TEXT.get(s.get("behavior", ""), "")])
	var weapons: PackedStringArray = PackedStringArray()
	for w: Dictionary in build.get("weapons", []):
		weapons.append("%s（%s）" % [w.get("name", ""), BEHAVIOR_TEXT.get(w.get("behavior", ""), "")])
	var frame: Dictionary = build.get("frame", {})
	lines.append("自分の機体：%s。武器：%s。" % [frame.get("name", ""), "、".join(weapons) if weapons.size() > 0 else "なし"])
	if text_obs:
		lines.append("戦況は短い文で毎回渡す。プレイヤーの指示の条件（HPが減ったら、相手が穴の近くなら、弾が切れたら など）が今の戦況に当てはまるかを確かめてから方針を選ぶ。")
	else:
		lines.append("戦況の見方：hp は残りHPの%。enemy.dist は相手との距離（3以下で接触、10以上は遠い）。dir は相手の方向。near_pit は穴の近く。behind_me は相手が自分の後ろ側。facing_me は相手がこちらを向いている。burning は火傷で燃えている（回復パックで治る）。ammo は残り弾（null は撃つ武器なし）。repair は一番近い回復パック（dist は距離、dir は方向、heal は回復量。null は場にない）。events は前回からの出来事。")
	var shape: String = "{\"say\":\"一言\",\"intent\":\"方針\",\"skill\":番号かnull}" if say_first \
		else "{\"intent\":\"方針\",\"skill\":番号かnull,\"say\":\"一言\"}"
	lines.append("答えは %s の形だけ。say は操縦士として今の判断を自分の言葉で言う%d文字以内の日本語（指示の文をそのまま写さない）。" % [shape, say_max])
	var p: String = prompt.strip_edges()
	lines.append("プレイヤーの指示：「%s」" % (p if not p.is_empty() else "（指示なし。自分で考えて戦え）"))
	return "\n".join(lines)


## 出力の形を縛る文法（GBNF）。方針は8種類、スキルは持っている番号か null、一言は say_max 文字まで
## say_first なら一言を先に書かせる（一言が判断の下書きになる）
static func build_grammar(n_skills: int, say_max: int, say_first: bool = false) -> String:
	var intents: PackedStringArray = PackedStringArray()
	for intent: String in RobotDriver.INTENTS:
		intents.append("\"%s\"" % intent)
	var skills: PackedStringArray = ["\"null\""]
	for i: int in n_skills:
		skills.append("\"%d\"" % i)
	var root: String = "root ::= \"{\\\"say\\\":\\\"\" say \"\\\",\\\"intent\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \"}\"" \
		if say_first else "root ::= \"{\\\"intent\\\":\\\"\" intent \"\\\",\\\"skill\\\":\" skill \",\\\"say\\\":\\\"\" say \"\\\"}\""
	return "\n".join([
		root,
		"intent ::= " + " | ".join(intents),
		"skill ::= " + " | ".join(skills),
		"say ::= [^\"\\\\\\n]{1,%d}" % maxi(1, say_max),
	])


## 毎回渡す戦況。位置や向きの数字は省き、判断に使うものだけにする
static func compact_observation(obs: Dictionary) -> Dictionary:
	var me: Dictionary = obs.get("me", {})
	var ready: Array = []
	var skills: Array = me.get("skills", [])
	for i: int in skills.size():
		if skills[i].get("ready", false):
			ready.append(i)
	return {
		"time_left": obs.get("time_left"),
		"me": {"hp": me.get("hp"), "ammo": me.get("ammo"), "stunned": me.get("stunned"),
			"near_pit": me.get("near_pit"), "intent": me.get("intent"), "skills_ready": ready,
			"burning": me.get("burning", false)},
		"enemy": obs.get("enemy", {}),
		"repair": obs.get("repair"),
		"events": obs.get("events", []),
	}


## 戦況を短い日本語の文にする（小さいモデルが条件を判断しやすいように、数字に「少ない」「遠い」などの言葉を添える）
static func describe_observation(obs: Dictionary, cfg: Dictionary) -> String:
	var me: Dictionary = obs.get("me", {})
	var en: Dictionary = obs.get("enemy", {})
	var rep_v: Variant = obs.get("repair")
	var rep: Dictionary = rep_v if rep_v is Dictionary else {}
	var lines: PackedStringArray = PackedStringArray()
	lines.append("残り%d秒。" % roundi(float(obs.get("time_left", 0.0))))

	var mine: PackedStringArray = ["HP%d%%（%s）" % [int(me.get("hp", 0)), _hp_word(float(me.get("hp", 0)), cfg)]]
	var ammo: Variant = me.get("ammo")
	mine.append("撃つ武器なし" if ammo == null else ("弾切れ" if int(ammo) <= 0 else "弾あり（%d発）" % int(ammo)))
	if me.get("stunned", false):
		mine.append("動けない")
	if me.get("burning", false):
		mine.append("燃えている（火傷。回復パックで治る）")
	if me.get("near_pit", false):
		mine.append("自分が穴の近くにいる")
	var ready: PackedStringArray = PackedStringArray()
	var skills: Array = me.get("skills", [])
	for i: int in skills.size():
		if skills[i].get("ready", false):
			ready.append("%d（%s）" % [i, skills[i].get("name", "")])
	mine.append("使えるスキル：%s" % ("、".join(ready) if ready.size() > 0 else "なし"))
	mine.append("今の方針：%s" % me.get("intent", ""))
	lines.append("自分：" + "、".join(mine) + "。")

	var dist: float = float(en.get("dist", 0.0))
	var theirs: PackedStringArray = [
		"HP%d%%（%s）" % [int(en.get("hp", 0)), _hp_word(float(en.get("hp", 0)), cfg)],
		"距離%.1f（%s）" % [dist, _dist_word(dist, cfg)],
		"方向：%s" % en.get("dir", ""),
		"穴の近くにいる" if en.get("near_pit", false) else "穴から離れている",
		"こちらを向いている" if en.get("facing_me", false) else "こちらを向いていない",
	]
	if en.get("behind_me", false):
		theirs.append("自分の後ろ側にいる")
	if en.get("stunned", false):
		theirs.append("動けない")
	if en.get("burning", false):
		theirs.append("燃えている")
	lines.append("相手：" + "、".join(theirs) + "。")
	if rep.is_empty():
		lines.append("回復パック：今は場にない。")
	else:
		lines.append("回復パック：%s、距離%.0f、HPを%d回復する。" % [rep.get("dir", ""), float(rep.get("dist", 0.0)),
			int(rep.get("heal", 0))])
	var events: Array = obs.get("events", [])
	if not events.is_empty():
		var ev: PackedStringArray = PackedStringArray()
		for e: Variant in events:
			ev.append(str(e))
		lines.append("前回からの出来事：" + "、".join(ev) + "。")
	return "\n".join(lines)


static func _hp_word(hp: float, cfg: Dictionary) -> String:
	if hp < float(cfg.get("hp_low", 30)):
		return "少ない"
	if hp >= float(cfg.get("hp_high", 60)):
		return "多い"
	return "半分くらい"


static func _dist_word(d: float, cfg: Dictionary) -> String:
	if d <= float(cfg.get("dist_touch", 3.5)):
		return "接触している"
	if d >= float(cfg.get("dist_far", 10.0)):
		return "遠い"
	return "近い"


## JSONを読む。壊れていても（LLMではよくあるので）エラーを出さずに null を返す
static func quiet_parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


## サーバーの答えを読む。形が正しければ方針の辞書、壊れていれば空の辞書
static func parse_answer(content: String, n_skills: int, say_max: int) -> Dictionary:
	var parsed: Variant = quiet_parse(content)
	if not (parsed is Dictionary):
		return {}
	var d: Dictionary = parsed
	var intent: Variant = d.get("intent")
	if not (intent is String) or not RobotDriver.INTENTS.has(intent):
		return {}
	var skill: Variant = d.get("skill")
	if skill is float or skill is int:
		skill = int(skill) if int(skill) >= 0 and int(skill) < n_skills else null
	else:
		skill = null
	var say: String = str(d.get("say", "")).left(say_max)
	return {"intent": intent, "skill": skill, "say": say}
