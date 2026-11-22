# エージェントに渡す戦況（観測）を作る。毎回この程度の小ささに収める（docs/design.md「渡す戦況の例」）。
extends RefCounted

const Robot := preload("res://core/battle_robot.gd")
const RobotDriver := preload("res://core/robot_driver.gd")


## packs は回復パック（battle_sim.gd の packs）。一番近いものを repair に入れる（場になければ null）
static func build(me: Robot, en: Robot, t: float, time_left: float, battle: Dictionary, packs: Array = []) -> Dictionary:
	var back_angle: float = deg_to_rad(float(battle["hit"]["back_angle_deg"]))
	var ex: float = en.x - me.x
	var ez: float = en.z - me.z
	var rel_me: float = angle_difference(me.th, atan2(ez, ex))
	var rel_en: float = angle_difference(en.th, atan2(-ez, -ex))
	var pack: Dictionary = RobotDriver.nearest_pack(me.x, me.z, packs)
	var repair: Variant = null
	if not pack.is_empty():
		var px: float = float(pack["x"]) - me.x
		var pz: float = float(pack["z"]) - me.z
		repair = {
			"dist": snappedf(Vector2(px, pz).length(), 0.1),
			"dir": direction_text(angle_difference(me.th, atan2(pz, px))),
			"heal": roundi(float(pack["heal"])),
		}

	var skills: Array = []
	for s: Robot.SkillSlot in me.skills:
		skills.append({"name": s.def.name, "behavior": s.def.behavior, "ready": s.is_ready()})

	return {
		"t": snappedf(t, 0.1),
		"time_left": snappedf(time_left, 0.1),
		"me": {
			"hp": roundi(me.hp_ratio() * 100.0),
			"pos": [snappedf(me.x, 0.1), snappedf(me.z, 0.1)],
			"facing": roundi(rad_to_deg(me.th)),
			"ammo": me.ammo_total(),
			"stunned": me.stun > 0.0,
			"burning": me.burn_t > 0.0,
			"near_pit": near_pit(me, battle),
			"intent": me.intent,
			"skills": skills,
		},
		"enemy": {
			"hp": roundi(en.hp_ratio() * 100.0),
			"dist": snappedf(sqrt(ex * ex + ez * ez), 0.1),
			"dir": direction_text(rel_me),
			"near_pit": near_pit(en, battle),
			"behind_me": absf(rel_me) > back_angle,
			"facing_me": absf(rel_en) < PI - back_angle,
			"stunned": en.stun > 0.0,
			"burning": en.burn_t > 0.0,
		},
		"repair": repair,
		"events": me.notes.duplicate(),
	}


## 穴の縁から near_dist 以内にいるか
static func near_pit(r: Robot, battle: Dictionary) -> bool:
	var near: float = float(battle["pit"]["near_dist"])
	for pit: Dictionary in battle["arena"]["pits"]:
		var dd: float = Vector2(r.x - float(pit["x"]), r.z - float(pit["z"])).length()
		if dd - float(pit["r"]) < near:
			return true
	return false


## 自分の向きから見た相手の方向を言葉にする（正の角度が右）
static func direction_text(rel: float) -> String:
	var deg: float = rad_to_deg(rel)
	var a: float = absf(deg)
	var lr: String = "右" if deg > 0.0 else "左"
	if a < 22.5:
		return "前方"
	if a < 67.5:
		return "前方やや" + lr
	if a < 112.5:
		return lr
	if a < 157.5:
		return "後方やや" + lr
	return "後方"
