# バトルの演出（view/arena/battle_director.gd）のテスト。始まりは FIGHT! まで試合を止め、強い一撃で一瞬止め、
# 受けたダメージを数字で出し、背後の一撃などで掛け声を出し、決着ではゆっくりにして看板を出す。演出を切れば時間は変えない。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")
const BattleDirector := preload("res://view/arena/battle_director.gd")
const Look := preload("res://view/look.gd")

const DT: float = 1.0 / 60.0
const COLORS: Array[Color] = [Color(0.45, 0.78, 1.0), Color(1.0, 0.62, 0.25)]


## main.gd の代わり（演出が読み書きするものだけ）
class FakeSession extends RefCounted:
	func is_online() -> bool:
		return false


class FakeMain extends Node:
	var cinematic_scale: float = 1.0
	var cinematics: bool = true
	var data: Variant
	var session := FakeSession.new()


func _sim(data: GameData) -> BattleSim:
	var rng := Rng.new(21)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	var sim := BattleSim.new(data, builds, brains, ["", ""], ["アカ", "アオ"], rng.fork("battle"))
	sim.packs.clear()
	return sim


## 演出・アリーナ・偽の main を組み立てる。終わったら _free(parts) で消す
func _make(cinematics: bool = true) -> Array:
	var data := GameData.new()
	data.load_dir()
	var sim: BattleSim = _sim(data)
	var main := FakeMain.new()
	main.data = data
	main.cinematics = cinematics
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	root.add_child(main)
	var arena: Node3D = ArenaView.new()
	root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	var d: Control = BattleDirector.new()
	root.add_child(d)
	d.setup(main, arena, sim, COLORS)
	return [d, main, arena, sim]


func _free(parts: Array) -> void:
	for k: int in 3:
		(parts[k] as Node).free()


## 実時間で seconds 秒、演出を進める（試合は main と同じように倍率をかけて進める）
func _run(d: Control, main: FakeMain, sim: BattleSim, seconds: float) -> void:
	var acc: float = 0.0
	for k: int in int(seconds * 60.0):
		d.update(DT)
		acc += DT * main.cinematic_scale
		while acc >= DT and not sim.over:
			acc -= DT
			sim.step()


func test_intro_holds_battle_until_fight() -> void:
	var parts: Array = _make()
	var d: Control = parts[0]
	var main: FakeMain = parts[1]
	var sim: BattleSim = parts[3]
	check(d.intro_t >= 0.0, "試合の始まりで VS の演出が始まる")
	_run(d, main, sim, Look.INTRO_FIGHT_AT - 0.1)
	check_eq(main.cinematic_scale, 0.0, "FIGHT! までは試合を止めておく")
	check_eq(sim.tick, 0, "止めている間は試合が進まない")
	_run(d, main, sim, Look.INTRO_END_AT - Look.INTRO_FIGHT_AT + 0.2)
	check(d.intro_t < 0.0, "FIGHT! のあと始まりの演出は消える")
	check(sim.tick > 0, "FIGHT! のあと試合が動き出す")
	check_eq(main.cinematic_scale, 1.0, "動き出したら時間の倍率はもとどおり")
	_free(parts)


func test_hitstop_numbers_and_callouts() -> void:
	var parts: Array = _make()
	var d: Control = parts[0]
	var main: FakeMain = parts[1]
	var arena: Node3D = parts[2]
	var sim: BattleSim = parts[3]
	d.intro_t = -1.0  # 始まりの演出は飛ばす
	d._end_intro()
	# 背後からの強い一撃（出来事だけ足し、HPも同じだけ減らす）
	sim.robots[1].hp -= 15.0
	sim.log.append({"type": "hit", "robot": 1, "by": 0, "weapon": "ハンマー", "damage": 15.0, "back": true, "t": 0.0})
	d.update(DT)
	check(d.hitstop_left > 0.0, "強い一撃でヒットストップが始まる")
	check(is_equal_approx(main.cinematic_scale, Look.HITSTOP_SCALE), "ヒットストップの間は時間がほとんど止まる")
	check(d.callouts_shown.has("BACKSTAB!"), "背後からの一撃で BACKSTAB! が出る")
	check(float(arena.get("_punch")) > 0.0, "強い一撃でカメラを押し込む")
	var found: bool = false
	for p: Dictionary in d.popups:
		if (p["node"] as Label).text == "15":
			found = true
	check(found, "受けたダメージ 15 が数字で浮かぶ")
	_run(d, main, sim, 0.3)
	check_eq(main.cinematic_scale, 1.0, "ヒットストップはすぐ終わる")
	# 回復は緑の +数字
	sim.robots[1].hp += 30.0
	d.update(DT)
	var healed: bool = false
	for p: Dictionary in d.popups:
		if (p["node"] as Label).text == "+30":
			healed = true
	check(healed, "回復した量が +30 で浮かぶ")
	# スキルの掛け声
	sim.log.append({"type": "skill", "robot": 0, "skill": "シールド", "behavior": "shield", "t": 0.0})
	d.update(DT)
	check(d.callouts_shown.has("SHIELD UP!"), "シールドを使うと SHIELD UP! が出る")
	for p: Dictionary in d.popups:
		var l: Label = p["node"]
		check(is_finite(l.position.x) and is_finite(l.position.y), "浮かぶ文字の位置が壊れない")
	# 試合は進めず（新しいダメージを出さず）、演出だけ進める
	for k: int in 90:
		d.update(DT)
	check(d.popups.is_empty(), "数字と掛け声はしばらくすると消える")
	_free(parts)


func test_ko_slowmo_and_banner() -> void:
	var parts: Array = _make()
	var d: Control = parts[0]
	var main: FakeMain = parts[1]
	var arena: Node3D = parts[2]
	var sim: BattleSim = parts[3]
	d.intro_t = -1.0
	d._end_intro()
	# 1番の機体を壊して決着させる（自爆装置を持っていても導火線が燃え尽きるまで進める）
	sim.robots[1].hp = 0.0
	for k: int in 60 * 12:
		if sim.over:
			break
		sim.robots[1].hp = 0.0
		sim.step()
	check(sim.over, "機体を壊すと決着する")
	d.update(DT)
	check(d.ko_t >= 0.0, "決着で K.O. の演出が始まる")
	check(not d.banner_text.is_empty(), "決着の看板の文字が決まる（%s）" % d.banner_text)
	if int(sim.result["winner"]) == 0 and sim.result["reason"] == "destroyed":
		check_eq(d.banner_text, "K.O.!", "壊して勝てば K.O.!")
	check(is_equal_approx(main.cinematic_scale, Look.KO_SLOWMO_SCALE), "決着の直後はゆっくりになる")
	check(float(arena.get("_cine_target_z")) > 0.0, "決着でカメラが寄る")
	_run(d, main, sim, Look.KO_SLOWMO_SEC + 0.1)
	check_eq(main.cinematic_scale, 1.0, "ゆっくりはしばらくで戻る")
	check(d._banner.visible and d._bars[0].visible, "看板と黒帯が出ている")
	check(d._bars[0].size.y > 0.0, "黒帯に太さがある")
	_free(parts)


func test_no_cinematics_keeps_time() -> void:
	var parts: Array = _make(false)
	var d: Control = parts[0]
	var main: FakeMain = parts[1]
	var arena: Node3D = parts[2]
	var sim: BattleSim = parts[3]
	_run(d, main, sim, 0.5)
	check_eq(main.cinematic_scale, 1.0, "演出を切ると、始まりでも試合を止めない")
	check(sim.tick > 0, "演出を切ると試合はすぐ進む")
	check_eq(arena.time_scale, 1.0, "演出を切ると見た目の時間もそのまま")
	_free(parts)
