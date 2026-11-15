# 仮の頭脳。プロンプトのキーワードと戦況から、決まった規則で方針を選ぶ。
# 答えは試合時間で 0.3〜1.5 秒（rules.json）遅らせて返し、本番のLLMの遅さを真似る。
extends "res://agent/agent_brain.gd"

const Rng := preload("res://core/rng.gd")

## プロンプトの作風を決めるキーワード
const STYLE_WORDS: Dictionary = {
	"aggressive": ["突撃", "突っ込", "攻め", "殴", "叩", "削", "体当たり", "ガンガン"],
	"pit": ["穴"],
	"ranged": ["撃", "距離", "遠く", "射"],
	"cautious": ["慎重", "逃げ", "修理", "回復", "守"],
	"flank": ["回り込", "背後", "後ろ", "横から"],
	"circle": ["回って", "ぐるぐる", "周り"],
}

## たまに出る気まぐれな方針
const WHIM_INTENTS: Array[String] = ["circle", "hold", "flank", "charge"]

## 方針ごとの操縦士の一言
const SAYINGS: Dictionary = {
	"charge": ["突っ込むっす！", "いくぞー！", "正面からいくっす"],
	"flank": ["後ろに回るっす", "横からいくっす"],
	"keep_distance": ["距離をとるっす", "近寄らせないっす"],
	"retreat": ["いったん下がるっす！", "逃げるっす～"],
	"push_to_pit": ["穴に寄せるっす！", "落としてやるっす"],
	"go_repair": ["修理してくるっす", "ちょっと直すっす"],
	"circle": ["ぐるぐる回るっす", "様子見っす"],
	"hold": ["……待つっす", "ここで待つっす"],
}

var _rng: Rng
var _style: Dictionary = {}
var _has_melee: bool = false
var _cfg: Dictionary = {}
var _delay_min: float = 0.0
var _delay_max: float = 0.0
var _pending: Dictionary = {}
var _ready_t: float = INF


func _init(rng: Rng) -> void:
	_rng = rng


func begin(prompt: String, build: Dictionary, rules: Dictionary) -> void:
	var agent: Dictionary = rules["agent"]
	_cfg = agent["mock"]
	_delay_min = float(agent["mock_delay_min_sec"])
	_delay_max = float(agent["mock_delay_max_sec"])
	_style = {}
	for style: String in STYLE_WORDS:
		_style[style] = false
		for w: String in STYLE_WORDS[style]:
			if prompt.contains(w):
				_style[style] = true
				break
	_has_melee = false
	for w: Dictionary in build.get("weapons", []):
		if w.get("behavior", "") != "shoot":
			_has_melee = true
	_pending = {}
	_ready_t = INF


func request(observation: Dictionary) -> void:
	# 新しい質問が来たら、前の考えは捨てて考え直す
	_pending = _decide(observation)
	_ready_t = float(observation["t"]) + _rng.randf_range(_delay_min, _delay_max)


func poll(now: float) -> Dictionary:
	if _pending.is_empty() or now < _ready_t:
		return {}
	var answer: Dictionary = _pending
	_pending = {}
	_ready_t = INF
	return answer


func _decide(obs: Dictionary) -> Dictionary:
	var me: Dictionary = obs["me"]
	var en: Dictionary = obs["enemy"]
	var repair: Dictionary = obs["repair"]
	var hp: float = float(me["hp"])
	var dist: float = float(en["dist"])
	var ammo: Variant = me.get("ammo")
	var has_gun: bool = ammo != null and int(ammo) > 0

	var intent: String = "charge"
	var low_hp: bool = hp < float(_cfg["repair_hp_any_style"]) \
		or (_style["cautious"] and hp < float(_cfg["repair_hp"]))
	if low_hp and float(repair["left"]) > 0.0 and dist > float(_cfg["repair_enemy_dist"]):
		intent = "go_repair"
	elif _style["pit"] and en["near_pit"]:
		intent = "push_to_pit"
	elif has_gun and (_style["ranged"] or not _has_melee):
		intent = "keep_distance"
	elif _style["cautious"] and hp < float(_cfg["cautious_hp"]):
		intent = "circle"
	elif _style["flank"] and en["facing_me"]:
		intent = "flank"
	elif _style["circle"]:
		intent = "circle"
	if _rng.chance(float(_cfg["random_intent_chance"])):
		intent = _rng.pick(WHIM_INTENTS)

	return {"intent": intent, "skill": _choose_skill(me, dist, intent), "say": _rng.pick(SAYINGS[intent])}


## 使えるスキルのうち、今の状況に合う最初のものの番号。なければ null
func _choose_skill(me: Dictionary, dist: float, intent: String) -> Variant:
	var skills: Array = me.get("skills", [])
	for i: int in skills.size():
		var s: Dictionary = skills[i]
		if not s.get("ready", false):
			continue
		var use: bool = false
		match str(s.get("behavior", "")):
			"booster":
				use = (intent == "charge" or intent == "push_to_pit" or intent == "go_repair") \
					and dist < float(_cfg["skill_booster_dist"])
			"shield":
				use = dist < float(_cfg["skill_shield_dist"])
			"repair":
				use = float(me["hp"]) < float(_cfg["skill_repair_hp"])
			"shockwave":
				use = dist < float(_cfg["skill_shockwave_dist"])
			"emp":
				use = dist < float(_cfg["skill_emp_dist"])
			"overclock":
				use = dist < float(_cfg["skill_overclock_dist"])
		if use:
			return i
	return null
