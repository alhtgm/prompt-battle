# 方針をハンドルとアクセルに直す実行役。毎刻み、今の方針から進みたい向きとアクセルを決める。
# 方針の種類はここで決める（docs/design.md「方針の種類（仮）」）。
extends RefCounted

const Robot := preload("res://core/battle_robot.gd")

const INTENTS: Array[String] = [
	"charge", "flank", "keep_distance", "retreat", "push_to_pit", "go_repair", "circle", "hold",
]


## 返す辞書：heading（向きたい角度）, throttle（0〜1）, reverse（後ろ向きに進む）, aim（向きを直接指定した）
## packs は回復パック（battle_sim.gd の packs）。「回復しに行く」方針のときだけ使う
static func drive(me: Robot, en: Robot, battle: Dictionary, packs: Array = []) -> Dictionary:
	var it: Dictionary = battle["intent"]
	var arena: Dictionary = battle["arena"]
	var robot_cfg: Dictionary = battle["robot"]
	var arrive: float = float(robot_cfg["arrive_dist"])

	var ex: float = en.x - me.x
	var ez: float = en.z - me.z
	var d: float = sqrt(ex * ex + ez * ez)
	var ux: float = ex / d if d > 1e-6 else 1.0
	var uz: float = ez / d if d > 1e-6 else 0.0

	var tx: float = en.x
	var tz: float = en.z
	var throttle: float = 1.0
	var reverse: bool = false
	var aim: bool = false
	var face: float = 0.0

	match me.intent:
		"charge":
			pass
		"flank":
			# 相手の正面〜横にいる間は、相手の横から後ろへ回り込む
			var rel: float = absf(angle_difference(en.th, atan2(me.z - en.z, me.x - en.x)))
			if rel < deg_to_rad(float(it["flank_behind_deg"])):
				var hx: float = cos(en.th)
				var hz: float = sin(en.th)
				var px: float = -hz * me.side
				var pz: float = hx * me.side
				tx = en.x + px * float(it["flank_side"]) - hx * float(it["flank_back"])
				tz = en.z + pz * float(it["flank_side"]) - hz * float(it["flank_back"])
		"keep_distance":
			var want: float = float(it["keep_distance"])
			var band: float = float(it["keep_distance_band"])
			aim = true
			face = atan2(uz, ux)
			if d < want - band:
				reverse = true
			elif d <= want + band:
				throttle = 0.0
		"retreat":
			var back: float = float(it["retreat_dist"])
			tx = me.x - ux * back
			tz = me.z - uz * back
			var lim: float = float(arena["half_size"]) - float(it["wall_margin"])
			if absf(tx) > lim or absf(tz) > lim:  # 壁際では横へ流れる
				tx = me.x - uz * back * me.side
				tz = me.z + ux * back * me.side
		"push_to_pit":
			var pit: Dictionary = nearest_circle(en.x, en.z, arena["pits"])
			var px2: float = en.x - float(pit["x"])
			var pz2: float = en.z - float(pit["z"])
			var pl: float = sqrt(px2 * px2 + pz2 * pz2)
			if pl > 1e-6:
				px2 /= pl
				pz2 /= pl
			# 相手をはさんで穴の反対側に立ってから押す
			var sx: float = en.x + px2 * float(it["push_behind"])
			var sz: float = en.z + pz2 * float(it["push_behind"])
			var lined: bool = (ux * -px2 + uz * -pz2) > float(it["push_lined_dot"])
			if not lined and Vector2(sx - me.x, sz - me.z).length() > arrive * 2.0:
				tx = sx
				tz = sz
		"go_repair":
			# 一番近い回復パックを取りに行く。場に1つもなければ、相手から離れて待つ
			var pack: Dictionary = nearest_pack(me.x, me.z, packs)
			if pack.is_empty():
				tx = me.x - ux * float(it["retreat_dist"])
				tz = me.z - uz * float(it["retreat_dist"])
			else:
				tx = float(pack["x"])
				tz = float(pack["z"])
		"circle":
			var rad: float = float(it["circle_radius"])
			var sd: float = float(it["circle_side"]) * me.side
			tx = en.x - ux * rad - uz * sd
			tz = en.z - uz * rad + ux * sd
		"hold":
			aim = true
			face = atan2(uz, ux)
			throttle = 0.0

	var dx: float = tx - me.x
	var dz: float = tz - me.z
	var dl: float = sqrt(dx * dx + dz * dz)
	if dl > 1e-6:
		dx /= dl
		dz /= dl
	if not reverse and not aim:
		var avoided: Vector2 = avoid_pits(me, Vector2(dx, dz), battle)
		dx = avoided.x
		dz = avoided.y
	var heading: float = face if aim else atan2(dz, dx)
	if not aim and dl < arrive and me.intent != "charge":
		throttle = 0.0
	return {"heading": heading, "throttle": throttle, "reverse": reverse, "aim": aim}


## 穴の近くでは、穴から離れる向きと穴の縁に沿う向きを足して、進む向きをそらす
static func avoid_pits(me: Robot, dir: Vector2, battle: Dictionary) -> Vector2:
	var pit_cfg: Dictionary = battle["pit"]
	var extra: float = float(pit_cfg["avoid_extra"])
	var out: Vector2 = dir
	for pit: Dictionary in battle["arena"]["pits"]:
		var a := Vector2(me.x - float(pit["x"]), me.z - float(pit["z"]))
		var ad: float = a.length()
		var reach: float = float(pit["r"]) + extra
		if ad < reach and ad > 1e-6 and extra > 0.0:
			a /= ad
			var w: float = (reach - ad) / extra
			var t := Vector2(-a.y, a.x)
			if t.dot(dir) < 0.0:
				t = -t
			out += a * w * float(pit_cfg["avoid_push"]) + t * w * float(pit_cfg["avoid_slide"])
	return out


## { x, z, r } の配列から一番近いものを返す
## 一番近い、場に出ている回復パック（なければ空の辞書）
static func nearest_pack(x: float, z: float, packs: Array) -> Dictionary:
	var best: Dictionary = {}
	var bd: float = INF
	for p: Dictionary in packs:
		if not p.get("active", false):
			continue
		var dd: float = Vector2(x - float(p["x"]), z - float(p["z"])).length()
		if dd < bd:
			bd = dd
			best = p
	return best


static func nearest_circle(x: float, z: float, circles: Array) -> Dictionary:
	var best: Dictionary = circles[0]
	var bd: float = INF
	for c: Dictionary in circles:
		var dd: float = Vector2(x - float(c["x"]), z - float(c["z"])).length()
		if dd < bd:
			bd = dd
			best = c
	return best
