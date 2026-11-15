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
## 今のラウンドで配られたパーツと、パークの候補（画面用）
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
