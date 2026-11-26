# 開発モードの試合。決めた設定（ステージ・ギミック・両機の装備とプロンプト・HP無限・時間無制限・種）で、1対1のバトルを1つだけ行う。
# バトルの画面がそのまま使えるよう、MatchSession と同じ名前の項目とメソッドを持つ。決着してもラウンド結果には進まない。
extends RefCounted

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Player := preload("res://core/player.gd")
const BattleSim := preload("res://core/battle_sim.gd")

## バトルの段階の名前（MatchSession.PHASE_BATTLE と同じ）
const PHASE_BATTLE: String = "battle"
## 両機の名前（0 が自分の側）
const NAMES: Array[String] = ["自分", "相手"]


## このバトル（MatchSession.Battle と同じ形）
class Battle:
	var a: int = 0
	var b: int = 1
	var ghost_of: int = -1
	var prompts: Array = ["", ""]
	var sim: BattleSim


var data: GameData
## 設定（default_setup の形）。やり直すときもこれを使う
var setup: Dictionary = {}
var seed_value: int = 1
var players: Array[Player] = []
var phase: String = PHASE_BATTLE
var round_no: int = 1
## このバトルのステージ（設定で外したギミックは入っていない）
var stage: Dictionary = {}
var battles: Array[Battle] = []
var history: Array[Dictionary] = []
var phase_time_left: float = 0.0
## 決着したかどうかを、画面が MatchSession と同じ読み方で読めるようにする（開発モードでは次へ進まない）
var battle_end_left: float = -1.0

var _agents: RefCounted
var _accum: float = 0.0


## 設定の形。装備はパーツの型のID、gimmicks_off は外すギミック（GameData.GIMMICKS の項目）
## stage は使うステージの辞書（空なら stage_id のステージ。置き場所を作り替えたステージを渡すときに使う）
static func default_setup(game_data: GameData) -> Dictionary:
	var frames: Array[GameData.PartDef] = game_data.defs_of_kind(GameData.KIND_FRAME)
	var weapons: Array[GameData.PartDef] = game_data.defs_of_kind(GameData.KIND_WEAPON)
	var builds: Array = []
	for i: int in 2:
		builds.append({"frame": frames[i % frames.size()].id, "weapons": [weapons[i % weapons.size()].id], "skills": []})
	return {
		"seed": 1,
		"stage_id": game_data.first_stage_id,
		"stage": {},
		"gimmicks_off": [],
		"builds": builds,
		"prompts": ["", ""],
		"invincible": [false, false],
		"no_time_limit": false,
	}


## 設定のステージ（ギミックを外したもの）
static func make_stage(game_data: GameData, s: Dictionary) -> Dictionary:
	var base: Dictionary = s.get("stage", {})
	if base.is_empty():
		base = game_data.get_stage(str(s.get("stage_id", "")))
	if base.is_empty():
		base = game_data.first_stage()
	return GameData.without_gimmicks(base, s.get("gimmicks_off", []))


## 装備の設定（型のID）から機体を作る。性能は範囲の真ん中。first_uid から番号を振る
static func make_build(game_data: GameData, b: Dictionary, first_uid: int) -> Build:
	var out := Build.new()
	var uid: int = first_uid
	var fdef: GameData.PartDef = game_data.get_part(str(b.get("frame", "")))
	if fdef != null and fdef.kind == GameData.KIND_FRAME:
		out.frame = Loot.middle_part(fdef, uid)
		uid += 1
	for id: Variant in b.get("weapons", []):
		var d: GameData.PartDef = game_data.get_part(str(id))
		if d != null and d.kind == GameData.KIND_WEAPON:
			out.weapons.append(Loot.middle_part(d, uid))
			uid += 1
	for id: Variant in b.get("skills", []):
		var d: GameData.PartDef = game_data.get_part(str(id))
		if d != null and d.kind == GameData.KIND_SKILL:
			out.skills.append(Loot.middle_part(d, uid))
			uid += 1
	return out


## 設定の問題（空なら始められる）
static func check_setup(game_data: GameData, s: Dictionary) -> String:
	for i: int in 2:
		var problem: String = make_build(game_data, s["builds"][i], 1).validate(game_data)
		if not problem.is_empty():
			return "%sの機体：%s" % [NAMES[i], problem]
	var st_errors: PackedStringArray = game_data.check_stage(make_stage(game_data, s))
	if not st_errors.is_empty():
		return st_errors[0]
	return ""


## agents は agent/default_agents.gd の形（make_brain を持つ）
func _init(game_data: GameData, agents: RefCounted, s: Dictionary) -> void:
	data = game_data
	_agents = agents
	setup = s.duplicate(true)
	restart()


## 設定のまま、最初からやり直す（同じ種なら同じ試合になる）
func restart() -> void:
	seed_value = int(setup.get("seed", 1))
	stage = make_stage(data, setup)
	players = []
	for i: int in 2:
		var p := Player.new()
		p.id = i
		p.name = NAMES[i]
		p.is_human = i == 0
		p.health = float(data.rule("initial_health"))
		p.prompt = str(setup["prompts"][i])
		players.append(p)
	var root := Rng.new(seed_value)
	var builds: Array = [make_build(data, setup["builds"][0], 1), make_build(data, setup["builds"][1], 100)]
	var brains: Array = []
	for i: int in 2:
		brains.append(_agents.make_brain(i == 0, root.fork("brain/%d" % i), i, i == 1))
	var bt := Battle.new()
	bt.prompts = [players[0].prompt, players[1].prompt]
	bt.sim = BattleSim.new(data, builds, brains, bt.prompts, NAMES, root.fork("battle"), stage)
	var inv: Array = setup.get("invincible", [false, false])
	for i: int in 2:
		bt.sim.invincible[i] = bool(inv[i])
	bt.sim.no_time_limit = bool(setup.get("no_time_limit", false))
	battles = [bt]
	phase = PHASE_BATTLE
	battle_end_left = -1.0
	_accum = 0.0


func is_online() -> bool:
	return false


func is_finished() -> bool:
	return false


func get_player(id: int) -> Player:
	return players[id] if id >= 0 and id < players.size() else null


func alive_players() -> Array[Player]:
	return players.duplicate()


func standings() -> Array[Player]:
	return players.duplicate()


func battle_of(_player_id: int) -> Battle:
	return battles[0] if not battles.is_empty() else null


## 実時間で進める（1/60秒の固定刻み）。決着したら止まる
func update(delta: float) -> void:
	var sim: BattleSim = battles[0].sim
	if sim.over:
		battle_end_left = 0.0
		return
	_accum += delta
	var steps: int = 0
	while _accum >= sim.dt and steps < 600 and not sim.over:
		sim.step()
		_accum -= sim.dt
		steps += 1


## 決着まで一気に進める（制限時間がないときは、制限時間の分だけ進める）
func run_battles_to_end() -> void:
	battles[0].sim.run_to_end()
	_accum = 0.0
