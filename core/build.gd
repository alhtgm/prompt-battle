# 機体（Build）：フレーム1つ、武器のリスト、スキルのリスト。数はフレームの枠まで。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")

var frame: PartInstance = null
var weapons: Array[PartInstance] = []
var skills: Array[PartInstance] = []


## 組み立てが正しいかを調べる。問題がなければ空文字。extra_* はパークで増えた枠
func validate(data: GameData, extra_weapon_slots: int = 0, extra_skill_slots: int = 0) -> String:
	if frame == null or frame.kind != GameData.KIND_FRAME:
		return "フレームがない"
	var fdef: GameData.PartDef = data.get_part(frame.def_id)
	if fdef == null:
		return "フレームの型 %s がない" % frame.def_id
	if weapons.size() > fdef.weapon_slots + extra_weapon_slots:
		return "武器が多すぎる（%d / %d）" % [weapons.size(), fdef.weapon_slots + extra_weapon_slots]
	if skills.size() > fdef.skill_slots + extra_skill_slots:
		return "スキルが多すぎる（%d / %d）" % [skills.size(), fdef.skill_slots + extra_skill_slots]
	var uids: Dictionary = {frame.uid: true}
	for w: PartInstance in weapons:
		if w.kind != GameData.KIND_WEAPON or data.get_part(w.def_id) == null:
			return "武器の枠に武器でないもの（%s）がある" % w.def_id
		if uids.has(w.uid):
			return "同じパーツ（uid %d）を2回使っている" % w.uid
		uids[w.uid] = true
	for s: PartInstance in skills:
		if s.kind != GameData.KIND_SKILL or data.get_part(s.def_id) == null:
			return "スキルの枠にスキルでないもの（%s）がある" % s.def_id
		if uids.has(s.uid):
			return "同じパーツ（uid %d）を2回使っている" % s.uid
		uids[s.uid] = true
	return ""


## 使っているパーツの型のID（フレーム、武器、スキルの順）
func part_def_ids() -> Array[String]:
	var out: Array[String] = []
	if frame != null:
		out.append(frame.def_id)
	for w: PartInstance in weapons:
		out.append(w.def_id)
	for s: PartInstance in skills:
		out.append(s.def_id)
	return out


## to_dict() の辞書から作り直す（通信で受け取ったとき）
static func from_dict(d: Dictionary) -> RefCounted:
	var b: RefCounted = (load("res://core/build.gd") as GDScript).new()
	if d.get("frame") is Dictionary:
		b.frame = PartInstance.from_dict(d["frame"])
	for w: Variant in d.get("weapons", []):
		b.weapons.append(PartInstance.from_dict(w))
	for s: Variant in d.get("skills", []):
		b.skills.append(PartInstance.from_dict(s))
	return b


func to_dict() -> Dictionary:
	var w: Array = []
	for p: PartInstance in weapons:
		w.append(p.to_dict())
	var s: Array = []
	for p: PartInstance in skills:
		s.append(p.to_dict())
	return {"frame": frame.to_dict() if frame != null else null, "weapons": w, "skills": s}
