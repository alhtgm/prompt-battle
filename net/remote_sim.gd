# 通信対戦のクライアントが持つ、バトル1試合の写し。サーバーから届く動き（毎秒20回ほど）を受け取り、画面のために滑らかにつなぐ。
# BattleSim と同じ名前の項目とメソッドを持つので、バトルの画面はそのまま使える。計算はしない。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Robot := preload("res://core/battle_robot.gd")
const Build := preload("res://core/build.gd")

## 届いた位置へ追いつく速さ（見た目だけの値）
const FOLLOW: float = 14.0


class ShotView:
	var x: float = 0.0
	var z: float = 0.0


var robots: Array[Robot] = []
var shots: Array[ShotView] = []
var log: Array[Dictionary] = []
var tick: int = 0
var tick_rate: int = 60
var time_limit_ticks: int = 0
var over: bool = false
var result: Dictionary = {}

var _targets: Array[Vector3] = []
var _got_frame: bool = false
var _since_frame: float = 0.0


func setup(data: GameData, builds: Array, names: Array) -> void:
	var b: Dictionary = data.rules["battle"]
	tick_rate = int(data.rule("tick_rate"))
	time_limit_ticks = roundi(float(b["time_limit_sec"]) * tick_rate)
	for i: int in 2:
		var r := Robot.new()
		r.setup(data, builds[i], i, str(names[i]), b["arena"]["spawns"][i], b["robot"],
			float(b["repair"]["total_per_robot"]))
		robots.append(r)
		_targets.append(Vector3(r.x, r.z, r.th))


## 試合時間。最後に届いた刻みから、届いてからの時間だけ進めて見せる（止まって見えないように）
func now() -> float:
	var t: float = float(tick) / float(tick_rate)
	return t if over else minf(t + _since_frame, float(time_limit_ticks) / float(tick_rate))


func time_left() -> float:
	return maxf(0.0, float(time_limit_ticks) / float(tick_rate) - now())


func apply_frame(f: Dictionary) -> void:
	tick = int(f.get("tick", tick))
	over = bool(f.get("over", false))
	result = f.get("result", {})
	_since_frame = 0.0
	var rs: Array = f.get("robots", [])
	for i: int in mini(2, rs.size()):
		var d: Dictionary = rs[i]
		var r: Robot = robots[i]
		r.hp = float(d["hp"])
		r.stun = float(d["stun"])
		r.fell = bool(d["fell"])
		r.intent = str(d["intent"])
		r.say = str(d["say"])
		r.repairing = bool(d["repairing"])
		r.repair_left = float(d["repair_left"])
		r.fuse = float(d.get("fuse", -1.0))
		r.fuse_total = float(d.get("fuse_total", 0.0))
		r.self_destructed = bool(d.get("self_destructed", false))
		var sk: Array = d.get("skills", [])
		for k: int in mini(sk.size(), r.skills.size()):
			r.skills[k].active_t = float(sk[k][0])
			r.skills[k].cd = float(sk[k][1])
			r.skills[k].charges_left = int(sk[k][2])
		var ammo: Array = d.get("ammo", [])
		for k: int in mini(ammo.size(), r.weapons.size()):
			r.weapons[k].ammo = int(ammo[k])
		_targets[i] = Vector3(float(d["x"]), float(d["z"]), float(d["th"]))
		if not _got_frame:
			r.x = _targets[i].x
			r.z = _targets[i].y
			r.th = _targets[i].z
	_got_frame = true
	var sh: Array = f.get("shots", [])
	while shots.size() < sh.size():
		shots.append(ShotView.new())
	shots.resize(sh.size())
	for k: int in sh.size():
		shots[k].x = float(sh[k][0])
		shots[k].z = float(sh[k][1])
	# 実況：まだ持っていない番号のものだけ足す
	var first: int = int(f.get("log_from", 0))
	var entries: Array = f.get("log", [])
	for k: int in entries.size():
		if first + k == log.size():
			log.append(entries[k])


## 描くたびに呼ぶ。届いた位置へ滑らかに近づける
func advance(delta: float) -> void:
	_since_frame += delta
	var w: float = minf(1.0, FOLLOW * delta)
	for i: int in robots.size():
		var r: Robot = robots[i]
		r.x = lerpf(r.x, _targets[i].x, w)
		r.z = lerpf(r.z, _targets[i].y, w)
		r.th = lerp_angle(r.th, _targets[i].z, w)
