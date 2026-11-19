# プレイヤー1人の状態（人間もCPUも同じ形）。体力、手持ちパーツ、取ったパーク、今の機体とプロンプト、順位。
# パークの効果をかけた「バトルで使う機体」もここで作る。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Build := preload("res://core/build.gd")

var id: int = 0
var name: String = ""
var is_human: bool = false
## 体力（初期100、0以下で脱落）
var health: float = 0.0
## 手持ちパーツ
var hand: Array[PartInstance] = []
## 取ったパークのID（同じものを何度取っても積み重なる）
var perks: Array[String] = []
## 今の機体（パーツは手持ちのもの）とプロンプト
var build: Build = null
var prompt: String = ""
var alive: bool = true
## 最終順位（決まるまで 0）
var place: int = 0
var eliminated_round: int = 0
## 直前の配布で配られたパーツ（パーク選びと組み立ての画面で NEW を出す。バトルが始まると空になる）と、パークの候補（画面用）
var new_parts: Array[PartInstance] = []
var perk_choices: Array[String] = []
## 今の段階の操作を済ませたか（人間用）
var done_this_phase: bool = false


func find_part(uid: int) -> PartInstance:
	for p: PartInstance in hand:
		if p.uid == uid:
			return p
	return null


## パークの効果のうち、ある対象への足し算の合計（例 "build.weapon_slots"）
func perk_add_total(data: GameData, target: String) -> float:
	var total: float = 0.0
	for pid: String in perks:
		var perk: GameData.PerkDef = data.get_perk(pid)
		if perk == null:
			continue
		for e: Dictionary in perk.effects:
			if e["target"] == target and e["op"] == "add":
				total += float(e["value"])
	return total


func extra_weapon_slots(data: GameData) -> int:
	return roundi(perk_add_total(data, "build.weapon_slots"))


func extra_skill_slots(data: GameData) -> int:
	return roundi(perk_add_total(data, "build.skill_slots"))


func prompt_max_chars(data: GameData) -> int:
	return int(data.rule("round.prompt_max_chars")) + roundi(perk_add_total(data, "prompt.max_chars"))


## 手持ちのパーツの uid から機体を組み、プロンプトと合わせて出撃できるかを調べる（状態は変えない）。
## 返すのは {"build": 組んだ機体（問題があれば null）, "error": 問題（なければ空文字）}。
## ひとりで遊ぶとき・通信対戦・組み立て画面の表示のすべてがこれを使い、確かめ方を1か所にまとめる
func assemble_build(data: GameData, frame_uid: int, weapon_uids: Array, skill_uids: Array, prompt_text: String) -> Dictionary:
	var b := Build.new()
	b.frame = find_part(frame_uid)
	for uid: Variant in weapon_uids:
		var w: PartInstance = find_part(int(uid))
		if w == null:
			return {"build": null, "error": "手持ちにない武器（uid %d）" % int(uid)}
		b.weapons.append(w)
	for uid: Variant in skill_uids:
		var s: PartInstance = find_part(int(uid))
		if s == null:
			return {"build": null, "error": "手持ちにないスキル（uid %d）" % int(uid)}
		b.skills.append(s)
	var err: String = b.validate(data, extra_weapon_slots(data), extra_skill_slots(data))
	if not err.is_empty():
		return {"build": null, "error": err}
	if prompt_text.length() > prompt_max_chars(data):
		return {"build": null, "error": "プロンプトが長すぎる（%d / %d 文字）" % [prompt_text.length(), prompt_max_chars(data)]}
	return {"build": b, "error": ""}


## パークの効果をかけた、バトルで使う機体を作る（元の手持ちパーツは変えない）
func effective_build(data: GameData) -> Build:
	var b := Build.new()
	b.frame = _boosted(data, build.frame)
	for w: PartInstance in build.weapons:
		b.weapons.append(_boosted(data, w))
	for s: PartInstance in build.skills:
		b.skills.append(_boosted(data, s))
	return b


func _boosted(data: GameData, src: PartInstance) -> PartInstance:
	var p := PartInstance.new()
	p.uid = src.uid
	p.def_id = src.def_id
	p.kind = src.kind
	p.stats = src.stats.duplicate()
	for pid: String in perks:
		var perk: GameData.PerkDef = data.get_perk(pid)
		if perk == null:
			continue
		for e: Dictionary in perk.effects:
			var target: String = e["target"]
			var dot: int = target.find(".")
			if target.substr(0, dot) != p.kind:
				continue
			var stat: String = target.substr(dot + 1)
			for key: String in p.stats.keys():
				if stat != "*" and stat != key:
					continue
				if e["op"] == "mul":
					p.stats[key] = p.stats[key] * float(e["value"])
				else:
					p.stats[key] = p.stats[key] + float(e["value"])
	return p
