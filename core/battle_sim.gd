# バトル1試合の計算。1/60秒の固定刻みで進め、画面の速さには左右されない。
# 状態（robots, shots, 経過時間）は外から読むだけにし、進めるのは step() だけ。頭脳とは begin/request/poll だけでやり取りする。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Robot := preload("res://core/battle_robot.gd")
const RobotDriver := preload("res://core/robot_driver.gd")
const Observation := preload("res://core/observation.gd")

## 決着のつき方
const REASON_DESTROYED: String = "destroyed"
const REASON_PIT: String = "pit"
const REASON_TIME: String = "time"
## 自爆装置の自爆で相手を道連れにした（引き分け）
const REASON_SELF_DESTRUCT: String = "self_destruct"

## 頭脳が壊れた答えを返したときの一言
const CONFUSED_SAY: String = "えっと…"
## 自爆装置が動き出したときの一言
const SELF_DESTRUCT_SAY: String = "道連れだ！"


## 飛んでいる弾
class Shot:
	var x: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vz: float = 0.0
	var owner: int = 0
	var damage: float = 0.0
	var knockback: float = 0.0
	var life: float = 0.0
	var label: String = ""


var data: GameData
var rng: Rng
var robots: Array[Robot] = []
var shots: Array[Shot] = []
var tick: int = 0
var tick_rate: int = 60
var dt: float = 1.0 / 60.0
var time_limit_ticks: int = 0
var over: bool = false
## 決着したら入る：winner（0/1、引き分けは -1）, reason, ticks, time, hp_ratio, dealt, margin
var result: Dictionary = {}
## この刻みで起きた出来事（画面の演出と実況用）
var events: Array[Dictionary] = []
## 試合を通した出来事の記録（弾を撃った、は省く）。各出来事に "t"（試合時間）を付ける。画面の実況用
var log: Array[Dictionary] = []

var _brains: Array = []
var _b: Dictionary = {}
var _think_interval: float = 2.0
var _think_min_gap: float = 0.5
var _say_max: int = 40
## 自爆のダメージを与えている最中（壊された相手の自爆装置には火をつけない）
var _blasting: bool = false
## 自爆が相手を壊したか（決着のつき方を「自爆で相打ち」にする）
var _blast_kill: bool = false


## builds・brains・prompts・names はどれも2つ。brains は agent_brain.gd を継承したもの
func _init(game_data: GameData, builds: Array, brains: Array, prompts: Array, names: Array, battle_rng: Rng) -> void:
	data = game_data
	rng = battle_rng
	_brains = brains
	_b = data.rules["battle"]
	tick_rate = int(data.rule("tick_rate"))
	dt = 1.0 / float(tick_rate)
	time_limit_ticks = roundi(float(_b["time_limit_sec"]) * tick_rate)
	_think_interval = float(data.rule("agent.think_interval_sec"))
	_think_min_gap = float(data.rule("agent.think_min_gap_sec"))
	_say_max = int(data.rule("agent.say_max_chars"))
	var spawns: Array = _b["arena"]["spawns"]
	for i: int in 2:
		var r := Robot.new()
		r.setup(data, builds[i], i, str(names[i]), spawns[i], _b["robot"], float(_b["repair"]["total_per_robot"]))
		robots.append(r)
	for i: int in 2:
		_brains[i].begin(str(prompts[i]), build_summary(data, builds[i]), data.rules)


## エージェントに渡す機体の説明
static func build_summary(game_data: GameData, b: Build) -> Dictionary:
	var fdef: GameData.PartDef = game_data.get_part(b.frame.def_id)
	var ws: Array = []
	for w: PartInstance in b.weapons:
		var d: GameData.PartDef = game_data.get_part(w.def_id)
		ws.append({"name": d.name, "behavior": d.behavior,
			"damage": w.get_stat("damage"), "knockback": w.get_stat("knockback")})
	var ss: Array = []
	for s: PartInstance in b.skills:
		var d: GameData.PartDef = game_data.get_part(s.def_id)
		ss.append({"name": d.name, "behavior": d.behavior})
	return {
		"frame": {"name": fdef.name, "hp": b.frame.get_stat("hp"),
			"speed_penalty": b.frame.get_stat("speed_penalty"), "mass": fdef.get_fixed("mass")},
		"weapons": ws,
		"skills": ss,
	}


## 今の試合時間（秒）
func now() -> float:
	return float(tick) / float(tick_rate)


func time_left() -> float:
	return maxf(0.0, float(time_limit_ticks - tick) / float(tick_rate))


## 決着するまで進めて結果を返す（画面なしの試合用）
func run_to_end() -> Dictionary:
	while not over:
		step()
	return result


## 1刻み進める。順番は docs/design.md「1刻みでやること」のとおり
func step() -> void:
	if over:
		return
	events.clear()
	tick += 1
	var t: float = now()
	for i: int in 2:
		_think(i, t)  # 1. 考える時刻なら戦況を渡す
	for i: int in 2:
		_poll(i, t)  # 2. 答えが届いていれば方針を入れ替える
	var controls: Array[Dictionary] = []
	for i: int in 2:
		if robots[i].fuse >= 0.0:
			# 自爆装置の導火線が燃えている間は、操縦士の方針に関係なく相手へ突っ込む
			robots[i].intent = "charge"
			robots[i].want_skill = -1
		_try_skill(i)  # 3. 実行役（スキルを含む）
		controls.append(RobotDriver.drive(robots[i], robots[1 - i], _b))
	for i: int in 2:
		_apply_control(robots[i], controls[i])  # 4. 物理
	_move()
	_collide()
	_clamp_walls()
	for i: int in 2:
		_weapons(i)  # 5. 武器の当たり判定とダメージ
	_update_shots()
	for i: int in 2:
		_hazards(i)  # 6. 修理ステーションと穴
	for i: int in 2:
		_fuse(i)  # 6.5 自爆装置の導火線
	_check_over()  # 7. 決着
	for e: Dictionary in events:
		if e["type"] != "shot":
			var logged: Dictionary = e.duplicate()
			logged["t"] = t
			log.append(logged)


## 比較・保存用に、今の状態をまるごと辞書にする
func snapshot() -> Dictionary:
	var rs: Array = []
	for r: Robot in robots:
		rs.append(r.to_dict())
	var ss: Array = []
	for s: Shot in shots:
		ss.append([s.x, s.z, s.owner])
	return {"tick": tick, "robots": rs, "shots": ss, "over": over, "result": result}


# ---- 1. 2. 考える ----

func _think(i: int, t: float) -> void:
	var r: Robot = robots[i]
	if r.fell:
		return
	var gap: float = t - r.last_request_t
	var due: bool = gap >= _think_interval - 1e-9
	var triggered: bool = not r.trigger.is_empty() and gap >= _think_min_gap - 1e-9
	if not due and not triggered:
		return
	var obs: Dictionary = Observation.build(r, robots[1 - i], t, time_left(), _b)
	_brains[i].request(obs)
	r.last_request_t = t
	r.trigger = ""
	r.notes.clear()
	r.damage_since_request = 0.0


func _poll(i: int, t: float) -> void:
	var r: Robot = robots[i]
	var answer: Variant = _brains[i].poll(t)
	if not (answer is Dictionary) or (answer as Dictionary).is_empty():
		return
	if r.fuse >= 0.0 or r.self_destructed:
		return  # 自爆装置が動き出したら、操縦士の答えはもう使わない
	var a: Dictionary = answer
	var intent: Variant = a.get("intent")
	if not (intent is String) or not RobotDriver.INTENTS.has(intent):
		# 壊れた答え：前の方針を続け、操縦士に戸惑わせる
		r.say = CONFUSED_SAY
		events.append({"type": "confused", "robot": i, "say": r.say})
		return
	r.intent = intent
	r.say = str(a.get("say", "")).left(_say_max)
	var sk: Variant = a.get("skill")
	if (sk is int or sk is float) and int(sk) >= 0 and int(sk) < r.skills.size():
		r.want_skill = int(sk)
	events.append({"type": "intent", "robot": i, "intent": r.intent, "say": r.say})


# ---- 3. スキル ----

func _try_skill(i: int) -> void:
	var r: Robot = robots[i]
	if r.want_skill < 0 or r.fell or r.stun > 0.0:
		return
	var s: Robot.SkillSlot = r.skills[r.want_skill]
	if s.def.behavior == "self_destruct":
		r.want_skill = -1  # 自爆装置は自分では使えない（HPが0になると自動で動く）
		return
	if not s.is_ready():
		return  # 使えるようになるまで待つ
	var en: Robot = robots[1 - i]
	r.want_skill = -1
	s.cd = s.def.get_fixed("cooldown_sec")
	if s.charges_left > 0:
		s.charges_left -= 1
	var dist: float = Vector2(en.x - r.x, en.z - r.z).length()
	var in_range: bool = dist <= s.def.get_fixed("range") + r.radius + en.radius
	match s.def.behavior:
		"booster", "shield", "overclock":
			s.active_t = s.def.get_fixed("duration_sec")
		"repair":
			r.hp = minf(r.max_hp, r.hp + s.inst.get_stat("heal"))
		"shockwave":
			if in_range and not en.fell:
				var n := Vector2(en.x - r.x, en.z - r.z).normalized()
				_knock(en, n.x, n.y, s.inst.get_stat("knockback"))
		"emp":
			if in_range and not en.fell:
				en.stun = maxf(en.stun, s.inst.get_stat("stun_sec"))
				en.trigger = "動けなくされた"
				en.add_note("EMPで停止")
	events.append({"type": "skill", "robot": i, "skill": s.def.name, "behavior": s.def.behavior})


# ---- 4. 物理 ----

func _apply_control(r: Robot, c: Dictionary) -> void:
	r.ram_cd -= dt
	for w: Robot.WeaponSlot in r.weapons:
		w.cd -= dt
	for s: Robot.SkillSlot in r.skills:
		s.cd -= dt
		s.active_t = maxf(0.0, s.active_t - dt)
	if r.fell:
		r.vx = 0.0
		r.vz = 0.0
		return
	var cfg: Dictionary = _b["robot"]
	if r.stun > 0.0:
		r.stun = maxf(0.0, r.stun - dt)
		var f: float = minf(1.0, float(cfg["stun_friction"]) * dt)
		r.vx -= r.vx * f
		r.vz -= r.vz * f
		return
	var diff: float = angle_difference(r.th, float(c["heading"]))
	var max_turn: float = r.turn_rate * dt
	r.th = wrapf(r.th + clampf(diff, -max_turn, max_turn), -PI, PI)
	var thr: float = float(c["throttle"])
	if not c["aim"] and not c["reverse"] and absf(diff) > deg_to_rad(float(cfg["sharp_turn_deg"])):
		thr *= float(cfg["sharp_turn_throttle"])
	var sp: float = r.max_speed * r.active_value("booster", "speed_mult", 1.0) * thr
	if r.fuse >= 0.0:
		sp *= _fuse_speed(r)
	if c["reverse"]:
		sp = -sp * float(cfg["reverse_mult"])
	var k: float = minf(1.0, float(cfg["accel"]) * dt)
	r.vx += (cos(r.th) * sp - r.vx) * k
	r.vz += (sin(r.th) * sp - r.vz) * k


func _move() -> void:
	for r: Robot in robots:
		r.x += r.vx * dt
		r.z += r.vz * dt
	_clamp_walls()


func _clamp_walls() -> void:
	var half: float = float(_b["arena"]["half_size"])
	for r: Robot in robots:
		var lim: float = half - r.radius
		if r.x > lim:
			r.x = lim
			r.vx = minf(r.vx, 0.0)
		elif r.x < -lim:
			r.x = -lim
			r.vx = maxf(r.vx, 0.0)
		if r.z > lim:
			r.z = lim
			r.vz = minf(r.vz, 0.0)
		elif r.z < -lim:
			r.z = -lim
			r.vz = maxf(r.vz, 0.0)


## 機体どうしの押し合いと、速くぶつかったときの体当たりダメージ
func _collide() -> void:
	var a: Robot = robots[0]
	var b: Robot = robots[1]
	if a.fell or b.fell:
		return
	var dx: float = b.x - a.x
	var dz: float = b.z - a.z
	var dd: float = sqrt(dx * dx + dz * dz)
	var min_d: float = a.radius + b.radius
	if dd >= min_d:
		return
	var nx: float = 1.0
	var nz: float = 0.0
	if dd > 1e-6:
		nx = dx / dd
		nz = dz / dd
	var overlap: float = min_d - dd
	var tot: float = a.mass + b.mass
	a.x -= nx * overlap * (b.mass / tot)
	a.z -= nz * overlap * (b.mass / tot)
	b.x += nx * overlap * (a.mass / tot)
	b.z += nz * overlap * (a.mass / tot)
	var vrel: float = (a.vx - b.vx) * nx + (a.vz - b.vz) * nz
	if vrel <= 0.0:
		return
	var col: Dictionary = _b["collision"]
	var j: float = vrel * float(col["restitution"]) * (a.mass * b.mass / tot)
	a.vx -= nx * j / a.mass
	a.vz -= nz * j / a.mass
	b.vx += nx * j / b.mass
	b.vz += nz * j / b.mass
	var min_speed: float = float(col["ram_min_speed"])
	if vrel > min_speed and a.ram_cd <= 0.0 and b.ram_cd <= 0.0:
		a.ram_cd = float(col["ram_cooldown_sec"])
		b.ram_cd = a.ram_cd
		var base: float = (vrel - min_speed) * float(col["ram_damage_coef"])
		_damage(1, base * (a.mass / tot) * 2.0, a.x, a.z, "体当たり", 0, true)
		_damage(0, base * (b.mass / tot) * 2.0, b.x, b.z, "体当たり", 1, true)


func _knock(r: Robot, nx: float, nz: float, power: float) -> void:
	r.vx += nx * power / r.mass
	r.vz += nz * power / r.mass


# ---- 5. 武器とダメージ ----

func _weapons(i: int) -> void:
	var me: Robot = robots[i]
	var en: Robot = robots[1 - i]
	if me.fell or en.fell or me.stun > 0.0:
		return
	var ex: float = en.x - me.x
	var ez: float = en.z - me.z
	var d: float = sqrt(ex * ex + ez * ez)
	var nx: float = ex / d if d > 1e-6 else cos(me.th)
	var nz: float = ez / d if d > 1e-6 else sin(me.th)
	var rel: float = absf(angle_difference(me.th, atan2(ez, ex)))
	for w: Robot.WeaponSlot in me.weapons:
		var def: GameData.PartDef = w.def
		var in_arc: bool = rel <= deg_to_rad(def.get_fixed("arc_deg")) * 0.5
		var touch: bool = d <= me.radius + en.radius + def.get_fixed("reach")
		var dmg: float = w.inst.get_stat("damage")
		var kb: float = w.inst.get_stat("knockback")
		match def.behavior:
			"grind":
				if touch and in_arc:
					_damage(en.index, dmg * dt, me.x, me.z, def.name, i, false)
					_knock(en, nx, nz, kb * dt)
			"strike":
				if touch and in_arc and w.cd <= 0.0:
					w.cd = def.get_fixed("cooldown_sec")
					_damage(en.index, dmg, me.x, me.z, def.name, i, true)
					_knock(en, nx, nz, kb)
			"lift":
				if touch and in_arc and w.cd <= 0.0 and en.stun <= 0.0:
					w.cd = def.get_fixed("cooldown_sec")
					_damage(en.index, dmg, me.x, me.z, def.name, i, true)
					_knock(en, nx, nz, kb)
					en.stun = def.get_fixed("stun_sec")
					en.trigger = "ひっくり返された"
					en.add_note("ひっくり返された")
					events.append({"type": "flip", "robot": en.index, "by": i})
			"ram":
				var closing: float = (me.vx - en.vx) * nx + (me.vz - en.vz) * nz
				var need: float = maxf(0.01, def.get_fixed("min_speed"))
				if touch and in_arc and w.cd <= 0.0 and closing >= need:
					w.cd = def.get_fixed("cooldown_sec")
					_damage(en.index, dmg * clampf(closing / need, 1.0, 2.0), me.x, me.z, def.name, i, true)
					_knock(en, nx, nz, kb)
			"shoot":
				if w.ammo > 0 and w.cd <= 0.0 and in_arc and d <= def.get_fixed("range"):
					w.cd = def.get_fixed("cooldown_sec")
					w.ammo -= 1
					var spread: float = deg_to_rad(def.get_fixed("spread_deg"))
					var ang: float = me.th + rng.randf_range(-spread * 0.5, spread * 0.5)
					var spd: float = def.get_fixed("projectile_speed")
					var s := Shot.new()
					s.x = me.x + cos(me.th) * (me.radius + 0.1)
					s.z = me.z + sin(me.th) * (me.radius + 0.1)
					s.vx = cos(ang) * spd
					s.vz = sin(ang) * spd
					s.owner = i
					s.damage = dmg
					s.knockback = kb
					s.life = def.get_fixed("range") / maxf(0.01, spd)
					s.label = def.name
					shots.append(s)
					events.append({"type": "shot", "robot": i, "weapon": def.name})
					if w.ammo == 0:
						me.trigger = "弾切れ"
						me.add_note("弾切れ:%s" % def.name)
						events.append({"type": "ammo_out", "robot": i, "weapon": def.name})


func _update_shots() -> void:
	var half: float = float(_b["arena"]["half_size"])
	for k: int in range(shots.size() - 1, -1, -1):
		var s: Shot = shots[k]
		s.x += s.vx * dt
		s.z += s.vz * dt
		s.life -= dt
		var tgt: Robot = robots[1 - s.owner]
		var gone: bool = s.life <= 0.0 or absf(s.x) > half or absf(s.z) > half
		if not gone and not tgt.fell and Vector2(s.x - tgt.x, s.z - tgt.z).length() < tgt.radius:
			var dir := Vector2(s.vx, s.vz).normalized()
			_damage(tgt.index, s.damage, s.x - dir.x, s.z - dir.y, s.label, s.owner, true)
			_knock(tgt, dir.x, dir.y, s.knockback)
			gone = true
		if gone:
			shots.remove_at(k)


## ダメージを与える。後ろからは倍率、シールドとオーバークロックの効果もここでかける
func _damage(victim_i: int, amount: float, from_x: float, from_z: float, label: String,
		attacker_i: int, discrete: bool) -> float:
	var v: Robot = robots[victim_i]
	var a: Robot = robots[attacker_i]
	# 導火線が燃えている機体と、自爆し終えた機体はもうダメージを受けない
	if amount <= 0.0 or v.fell or v.fuse >= 0.0 or v.self_destructed:
		return 0.0
	var hit: Dictionary = _b["hit"]
	var rel: float = absf(angle_difference(v.th, atan2(from_z - v.z, from_x - v.x)))
	var back: bool = rel > deg_to_rad(float(hit["back_angle_deg"]))
	var mult: float = float(hit["damage_scale"])
	if back:
		mult *= float(hit["back_mult"])
	mult *= 1.0 - clampf(v.active_value("shield", "damage_cut", 0.0), 0.0, 1.0)
	mult *= maxf(0.0, a.active_value("overclock", "damage_mult", 1.0))
	var dmg: float = amount * mult
	v.hp = maxf(0.0, v.hp - dmg)
	a.dealt += dmg
	# HPが尽きたら、自爆装置があれば導火線に火がつく（自爆で壊されたときは道連れなのでつかない）
	if v.hp <= 0.0 and not _blasting:
		_arm_fuse(victim_i)
	v.damage_since_request += dmg
	if v.damage_since_request >= float(_b["replan"]["big_hit_damage"]):
		v.trigger = "大きく被弾"
	if discrete:
		v.add_note("被弾:%s:%d" % [label, roundi(dmg)])
		events.append({"type": "hit", "robot": victim_i, "by": attacker_i, "weapon": label,
			"damage": dmg, "back": back})
	return dmg


# ---- 6. 修理ステーションと穴 ----

func _hazards(i: int) -> void:
	var r: Robot = robots[i]
	var en: Robot = robots[1 - i]
	if r.fell:
		return
	var arena: Dictionary = _b["arena"]
	var rep: Dictionary = _b["repair"]
	var on_pad: bool = false
	for pad: Dictionary in arena["repair_pads"]:
		if Vector2(r.x - float(pad["x"]), r.z - float(pad["z"])).length() < float(pad["r"]):
			on_pad = true
	var healing: bool = on_pad and r.repair_left > 0.0 and r.hp < r.max_hp and r.stun <= 0.0 \
		and r.speed() < float(rep["max_speed"])
	if healing:
		var h: float = minf(float(rep["rate_per_sec"]) * dt, minf(r.repair_left, r.max_hp - r.hp))
		r.hp += h
		r.repair_left -= h
		if not r.repairing:
			events.append({"type": "repair", "robot": i})
	r.repairing = healing

	var margin: float = float(_b["pit"]["fall_margin"])
	for pit: Dictionary in arena["pits"]:
		if Vector2(r.x - float(pit["x"]), r.z - float(pit["z"])).length() < float(pit["r"]) - margin:
			r.fell = true
			r.vx = 0.0
			r.vz = 0.0
			events.append({"type": "fall", "robot": i})
			return

	# 考え直す切っ掛け
	var low: bool = r.hp_ratio() < float(_b["replan"]["hp_low_ratio"])
	if low and not r.hp_was_low:
		r.trigger = "HPが半分を切った"
	r.hp_was_low = low
	var en_near: bool = Observation.near_pit(en, _b)
	if en_near and not r.enemy_was_near_pit and not en.fell:
		r.trigger = "相手が穴の近く"
	r.enemy_was_near_pit = en_near


# ---- 6.5 自爆装置 ----

## 自爆装置の導火線に火をつける。速くなって相手へ突っ込み、ダメージを受けなくなる
func _arm_fuse(i: int) -> void:
	var r: Robot = robots[i]
	var s: Robot.SkillSlot = r.self_destruct_slot()
	if s == null or r.fell or r.fuse >= 0.0:
		return
	if s.charges_left > 0:
		s.charges_left -= 1
	r.fuse = maxf(dt, s.def.get_fixed("fuse_sec"))
	r.fuse_total = r.fuse
	s.active_t = r.fuse
	r.stun = 0.0
	r.intent = "charge"
	r.say = SELF_DESTRUCT_SAY
	events.append({"type": "fuse", "robot": i, "skill": s.def.name})


## 導火線を進め、燃え尽きたら（または時間切れなら）自爆する
func _fuse(i: int) -> void:
	var r: Robot = robots[i]
	if r.fuse < 0.0 or r.fell:
		return
	r.fuse -= dt
	if r.fuse <= 0.0 or tick >= time_limit_ticks:
		_explode(i)


## 自爆する。範囲内の相手に大きなダメージと吹き飛ばし。自爆した機体は倒れる
func _explode(i: int) -> void:
	var r: Robot = robots[i]
	var en: Robot = robots[1 - i]
	var def: GameData.PartDef = null
	var inst: PartInstance = null
	for s: Robot.SkillSlot in r.skills:
		if s.def.behavior == "self_destruct":
			def = s.def
			inst = s.inst
			s.active_t = 0.0
	r.fuse = -1.0
	r.self_destructed = true
	r.vx = 0.0
	r.vz = 0.0
	if def == null:
		return
	var rng_m: float = def.get_fixed("range")
	var d := Vector2(en.x - r.x, en.z - r.z)
	var hit: bool = not en.fell and not en.is_down() and d.length() <= rng_m + r.radius + en.radius
	var dmg: float = 0.0
	if hit:
		_blasting = true
		dmg = _damage(1 - i, inst.get_stat("blast_damage"), r.x, r.z, def.name, i, true)
		_blasting = false
		var n: Vector2 = d.normalized() if d.length() > 0.001 else Vector2(cos(en.th), sin(en.th))
		_knock(en, n.x, n.y, def.get_fixed("knockback"))
	if hit and en.is_down():
		_blast_kill = true
	events.append({"type": "self_destruct", "robot": i, "hit": hit, "damage": dmg, "range": rng_m})


## 導火線が燃えている間の速さの倍率
func _fuse_speed(r: Robot) -> float:
	for s: Robot.SkillSlot in r.skills:
		if s.def.behavior == "self_destruct":
			return maxf(0.0, s.def.get_fixed("speed_mult", 1.0))
	return 1.0


# ---- 7. 決着 ----

func _check_over() -> void:
	var a: Robot = robots[0]
	var b: Robot = robots[1]
	var winner: int = -1
	var reason: String = ""
	if a.fell or b.fell:
		reason = REASON_PIT
		winner = -1 if a.fell and b.fell else (1 if a.fell else 0)
	elif a.fuse >= 0.0 or b.fuse >= 0.0:
		return  # 自爆装置の導火線が燃えている間は決着しない（自爆の結果を待つ）
	elif a.is_down() or b.is_down():
		var both: bool = a.is_down() and b.is_down()
		# 両方倒れていて、自爆が相手を壊したのなら、自爆による道連れ（引き分け）
		reason = REASON_SELF_DESTRUCT if both and _blast_kill else REASON_DESTROYED
		winner = -1 if both else (1 if a.is_down() else 0)
	elif tick >= time_limit_ticks:
		reason = REASON_TIME
		var diff: float = a.hp_ratio() - b.hp_ratio()
		winner = -1 if absf(diff) < float(_b["draw_hp_ratio_diff"]) else (0 if diff > 0.0 else 1)
	else:
		return
	over = true
	result = {
		"winner": winner,
		"reason": reason,
		"ticks": tick,
		"time": now(),
		"hp_ratio": [a.hp_ratio(), b.hp_ratio()],
		"dealt": [a.dealt, b.dealt],
		# ダメージ計算の「差」に使う：勝った側の機体の残りHPの割合
		"margin": robots[winner].hp_ratio() if winner >= 0 else 0.0,
	}
	events.append({"type": "over", "winner": winner, "reason": reason})
