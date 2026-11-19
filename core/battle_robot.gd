# バトル中の機体1体の状態（位置・向き・速度・HP・武器とスキルの状態・今の方針・考える時刻）。
# BattleSim が書き換え、画面とテストは読むだけにする。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")

## ハープーンガンの釣り針の状態：撃っていない／飛んでいる／当たった相手を引き寄せている／外れて戻っている
const HOOK_NONE: String = ""
const HOOK_FLY: String = "fly"
const HOOK_PULL: String = "pull"
const HOOK_BACK: String = "back"


## 武器1つの状態
class WeaponSlot:
	var def: GameData.PartDef
	var inst: PartInstance
	var cd: float = 0.0
	## 残りの弾。-1 は弾を使わない武器
	var ammo: int = -1


## スキル1つの状態
class SkillSlot:
	var def: GameData.PartDef
	var inst: PartInstance
	var cd: float = 0.0
	## 効果が続く残り時間
	var active_t: float = 0.0
	## 残りの使用回数。-1 は無制限
	var charges_left: int = -1

	func is_ready() -> bool:
		return cd <= 0.0 and charges_left != 0


var index: int = 0
var name: String = ""
var build: Build
## 位置（上から見た平面）、向き（ラジアン。+x から +z へ回る向きが正）、速度
var x: float = 0.0
var z: float = 0.0
var th: float = 0.0
var vx: float = 0.0
var vz: float = 0.0
var hp: float = 0.0
var max_hp: float = 1.0
var mass: float = 1.0
## 1秒に曲がれる角度（ラジアン）
var turn_rate: float = 1.0
var max_speed: float = 1.0
var radius: float = 1.0
var weapons: Array[WeaponSlot] = []
var skills: Array[SkillSlot] = []
## 動けない残り時間（ひっくり返された、EMP）
var stun: float = 0.0
## ひっくり返されているか（リフターで。EMP やハープーンガンで止められているだけなら false）
var flipped: bool = false
var ram_cd: float = 0.0
var repair_left: float = 0.0
var repairing: bool = false
var fell: bool = false
## 回り込みや周回で回る向き（1 か -1）
var side: float = 1.0
## 今の方針と一言
var intent: String = "hold"
var say: String = ""
## 使いたいスキルの番号（-1 はなし）。使えるようになるまで待つ
var want_skill: int = -1
## 相手に与えたダメージの合計
var dealt: float = 0.0
## 自爆装置：HPが尽きてから自爆するまでの残り秒数（-1 は動いていない）と、その長さ。自爆し終えたか
var fuse: float = -1.0
var fuse_total: float = 0.0
var self_destructed: bool = false
## ハープーンガンの釣り針。状態は HOOK_* のどれか。位置と速さ、飛べる残りの距離、撃った武器の番号
var hook_state: String = ""
var hook_x: float = 0.0
var hook_z: float = 0.0
var hook_vx: float = 0.0
var hook_vz: float = 0.0
var hook_left: float = 0.0
var hook_slot: int = -1

# ---- 考えるための記録 ----
var last_request_t: float = -INF
## 考え直す切っ掛け（空ならなし）
var trigger: String = ""
## 前回考えてから起きたこと（戦況の events に入れる）
var notes: Array[String] = []
var damage_since_request: float = 0.0
var hp_was_low: bool = false
var enemy_was_near_pit: bool = false


func setup(data: GameData, b: Build, idx: int, robot_name: String, spawn: Dictionary,
		robot_cfg: Dictionary, repair_total: float) -> void:
	index = idx
	name = robot_name
	build = b
	var fdef: GameData.PartDef = data.get_part(b.frame.def_id)
	x = float(spawn["x"])
	z = float(spawn["z"])
	th = deg_to_rad(float(spawn["facing_deg"]))
	max_hp = maxf(1.0, b.frame.get_stat("hp"))
	hp = max_hp
	mass = maxf(0.1, fdef.get_fixed("mass", 1.0))
	turn_rate = deg_to_rad(fdef.get_fixed("turn_rate_deg"))
	max_speed = float(robot_cfg["base_speed"]) * maxf(0.0, 1.0 - b.frame.get_stat("speed_penalty"))
	radius = float(robot_cfg["radius"])
	repair_left = repair_total
	for w: PartInstance in b.weapons:
		var ws := WeaponSlot.new()
		ws.inst = w
		ws.def = data.get_part(w.def_id)
		ws.ammo = int(ws.def.get_fixed("ammo")) if ws.def.behavior == "shoot" else -1
		weapons.append(ws)
	for s: PartInstance in b.skills:
		var ss := SkillSlot.new()
		ss.inst = s
		ss.def = data.get_part(s.def_id)
		var charges: int = int(ss.def.get_fixed("charges"))
		ss.charges_left = charges if charges > 0 else -1
		skills.append(ss)


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func speed() -> float:
	return sqrt(vx * vx + vz * vz)


## 撃つ武器の残り弾の合計。撃つ武器がなければ null
func ammo_total() -> Variant:
	var total: int = 0
	var has_gun: bool = false
	for w: WeaponSlot in weapons:
		if w.ammo >= 0:
			has_gun = true
			total += w.ammo
	return total if has_gun else null


## 効果中のスキル（behavior）があればそのステータスの値、なければ fallback
func active_value(behavior: String, stat_name: String, fallback: float) -> float:
	for s: SkillSlot in skills:
		if s.active_t > 0.0 and s.def.behavior == behavior:
			return s.inst.get_stat(stat_name, fallback)
	return fallback


## まだ動いていない自爆装置（なければ null）
func self_destruct_slot() -> SkillSlot:
	for s: SkillSlot in skills:
		if s.def.behavior == "self_destruct" and s.charges_left != 0:
			return s
	return null


## 倒れたか（HPが尽き、自爆装置の導火線も燃えていない）
func is_down() -> bool:
	return hp <= 0.0 and fuse < 0.0


func add_note(text: String) -> void:
	notes.append(text)
	while notes.size() > 5:
		notes.remove_at(0)


## 比較・表示用の辞書
func to_dict() -> Dictionary:
	var ws: Array = []
	for w: WeaponSlot in weapons:
		ws.append({"id": w.def.id, "cd": w.cd, "ammo": w.ammo})
	var ss: Array = []
	for s: SkillSlot in skills:
		ss.append({"id": s.def.id, "cd": s.cd, "active": s.active_t, "charges": s.charges_left})
	return {
		"x": x, "z": z, "th": th, "vx": vx, "vz": vz, "hp": hp, "max_hp": max_hp,
		"stun": stun, "flipped": flipped, "fell": fell, "intent": intent, "say": say, "dealt": dealt,
		"repair_left": repair_left, "weapons": ws, "skills": ss,
		"fuse": fuse, "self_destructed": self_destructed,
		"hook": [hook_state, hook_x, hook_z, hook_slot],
	}
