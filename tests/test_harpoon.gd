# ハープーンガンのテスト。前の相手に釣り針を撃ち、当たれば小さなダメージを与えて自分の前まで引き寄せ、
# 着いたら相手は少し動けない。届かない・前にいない相手には撃たない。外れたら巻き戻す。引く途中に穴があれば相手は落ちる。
# 見た目：鎖が張られ、引き寄せる間に巻き取られ、引きずる音が鳴る。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Rng := preload("res://core/rng.gd")
const Loot := preload("res://core/loot.gd")
const Build := preload("res://core/build.gd")
const BattleSim := preload("res://core/battle_sim.gd")
const Robot := preload("res://core/battle_robot.gd")
const MockBrain := preload("res://agent/mock_brain.gd")
const ArenaView := preload("res://view/arena/arena_view.gd")

const DT: float = 1.0 / 60.0


func _data() -> GameData:
	var d := GameData.new()
	d.load_dir()
	return d


## 0番はハープーンガンだけ、1番は武器もスキルもない機体。1番は動かない（止めておく）
func _sim(data: GameData, seed_value: int) -> BattleSim:
	var rng := Rng.new(seed_value)
	var setup: Rng = rng.fork("setup")
	var builds: Array = []
	for i: int in 2:
		var b: Build = Loot.random_build(data, setup, 1 + i * 100)
		b.weapons.clear()
		b.skills.clear()
		if i == 0:
			b.weapons.append(Loot.roll_part(data.get_part("weapon_harpoon"), setup, 50))
		builds.append(b)
	var brains: Array = [MockBrain.new(rng.fork("brain/0")), MockBrain.new(rng.fork("brain/1"))]
	return BattleSim.new(data, builds, brains, ["", ""], ["A", "B"], rng.fork("battle"))


## 0番を (ax, az) に置いて相手の方を向かせ、1番を (bx, bz) に置く。0番は動かさない（向きだけ）
func _face_off(sim: BattleSim, ax: float, az: float, bx: float, bz: float) -> void:
	var a: Robot = sim.robots[0]
	var b: Robot = sim.robots[1]
	a.x = ax
	a.z = az
	b.x = bx
	b.z = bz
	a.th = atan2(bz - az, bx - ax)
	a.intent = "hold"
	b.intent = "hold"


func _hold_still(sim: BattleSim) -> void:
	# 頭脳の答えで動かないよう、両方その場で待たせる（1番は少しのあいだ止める）
	for r: Robot in sim.robots:
		r.intent = "hold"
		r.vx = 0.0
		r.vz = 0.0


func _events(sim: BattleSim, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in sim.log:
		if e["type"] == type:
			out.append(e)
	return out


func test_part_is_valid() -> void:
	var data := _data()
	var def: GameData.PartDef = data.get_part("weapon_harpoon")
	check(def != null, "ハープーンガンのパーツがある")
	if def == null:
		return
	check_eq(def.behavior, "hook", "動き方は hook")
	check(def.get_fixed("range") > 5.0 and def.get_fixed("pull_speed") > 0.0 and def.get_fixed("hold_sec") > 0.0,
		"射程・引き寄せる速さ・動けなくする時間がある")
	check(data.get_part("weapon_harpoon").stats["damage"].max_value < data.get_part("weapon_rocket").stats["damage"].min_value,
		"ダメージは低め（ロケットより弱い）")


func test_hook_pulls_enemy_in_and_holds_it() -> void:
	var data := _data()
	var sim := _sim(data, 1)
	_face_off(sim, -6.0, 0.0, 4.0, 0.0)
	var b: Robot = sim.robots[1]
	var hp0: float = b.hp
	var def: GameData.PartDef = data.get_part("weapon_harpoon")
	var hit_at: int = -1
	var end_at: int = -1
	var reached_pull: bool = false
	for k: int in 240:
		_hold_still(sim)
		sim.step()
		if sim.robots[0].hook_state == Robot.HOOK_PULL:
			reached_pull = true
		if hit_at < 0 and not _events(sim, "hook_hit").is_empty():
			hit_at = k
		if end_at < 0 and not _events(sim, "hook_end").is_empty():
			end_at = k
			break
	check(not _events(sim, "hook_fire").is_empty(), "前にいる相手に釣り針を撃つ")
	check(hit_at >= 0, "釣り針が当たる")
	check(reached_pull, "当たると引き寄せ始める")
	check(end_at > hit_at, "引き寄せが終わる")
	check(b.hp < hp0 and hp0 - b.hp < 10.0, "ダメージは小さい（%.1f）" % (hp0 - b.hp))
	var a: Robot = sim.robots[0]
	var gap: float = Vector2(b.x - a.x, b.z - a.z).length() - a.radius - b.radius
	check(gap < 0.2, "引き寄せた相手は自分にぴったり付く（すき間 %.2f m）" % gap)
	check(b.stun >= def.get_fixed("hold_sec") - 0.05, "引き寄せた相手は少しのあいだ動けない（%.2f 秒）" % b.stun)
	check_eq(a.hook_state, Robot.HOOK_NONE, "引き寄せ終わったら釣り針は戻る")


func test_no_fire_when_out_of_range_or_not_in_front() -> void:
	var data := _data()
	var far := _sim(data, 2)
	_face_off(far, -14.0, 0.0, 14.0, 0.0)
	var behind := _sim(data, 2)
	_face_off(behind, -2.0, 0.0, 4.0, 0.0)
	behind.robots[0].th = PI  # 相手に背を向ける
	for k: int in 30:
		for s: BattleSim in [far, behind]:
			_hold_still(s)
			s.robots[0].th = PI if s == behind else s.robots[0].th
			s.step()
	check(_events(far, "hook_fire").is_empty(), "届かない相手には撃たない")
	check(_events(behind, "hook_fire").is_empty(), "前にいない相手には撃たない")


func test_missed_hook_reels_back() -> void:
	var data := _data()
	var sim := _sim(data, 3)
	_face_off(sim, -6.0, 0.0, 4.0, 0.0)
	_hold_still(sim)
	sim.step()
	check_eq(sim.robots[0].hook_state, Robot.HOOK_FLY, "釣り針が飛ぶ")
	# 撃った直後に相手が横へ逃げた
	sim.robots[1].z = -4.0  # （穴のない場所へ）
	var came_back: bool = false
	var went_back: bool = false
	for k: int in 120:
		_hold_still(sim)
		sim.step()
		if sim.robots[0].hook_state == Robot.HOOK_BACK:
			went_back = true
		if went_back and sim.robots[0].hook_state == Robot.HOOK_NONE:
			came_back = true
			break
	check(went_back, "外れたら巻き戻す")
	check(came_back, "巻き戻し終わる")
	check(_events(sim, "hook_hit").is_empty(), "外れたら引き寄せない")


func test_pulling_across_a_pit_drops_the_enemy() -> void:
	var data := _data()
	var sim := _sim(data, 4)
	# 穴（-4, -7）をはさんで向かい合う。引き寄せる途中で相手が穴に落ちる
	_face_off(sim, -4.0, -12.5, -4.0, -1.5)
	for k: int in 300:
		if sim.over:
			break
		_hold_still(sim)
		sim.step()
	check(sim.robots[1].fell, "引き寄せる途中に穴があれば、相手は落ちる")
	check(sim.over and int(sim.result["winner"]) == 0 and str(sim.result["reason"]) == BattleSim.REASON_PIT,
		"穴に落とした側の勝ち")


func test_chain_view_reels_and_plays_drag_sound() -> void:
	var data := _data()
	var sim := _sim(data, 1)
	_face_off(sim, -6.0, 0.0, 4.0, 0.0)
	var arena: Node3D = ArenaView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(arena)
	arena.setup(data)
	arena.bind(sim)
	var hv: Node3D = arena.robot_views[0].hook_view
	check(hv != null, "ハープーンガンを持つ機体には鎖の見た目がある")
	check(arena.robot_views[1].hook_view == null, "持たない機体にはない")
	if hv == null:
		arena.free()
		return
	var saw_fly_links: bool = false
	var saw_pull_sound: bool = false
	var reeled_before: float = -1.0
	for k: int in 240:
		_hold_still(sim)
		sim.step()
		arena.sync(DT)
		if hv.state == "fly" and hv.visible_links > 3:
			saw_fly_links = true
		if hv.state == "pull":
			if reeled_before < 0.0:
				reeled_before = hv.reeled
			saw_pull_sound = saw_pull_sound or hv.drag_player.playing
		if not _events(sim, "hook_end").is_empty():
			break
	check(saw_fly_links, "飛んでいる間、鎖の輪が並ぶ")
	check(hv.reeled > reeled_before + 1.0, "引き寄せる間、鎖が巻き取られる（%.1f m）" % hv.reeled)
	check(hv.reel_angle > 1.0, "巻き取り機が回る")
	check(saw_pull_sound, "引き寄せる間、引きずる音が鳴る")
	arena.sync(DT)
	check_eq(hv.visible_links, 0, "引き寄せ終わったら鎖は消える")
	check(not hv.drag_player.playing, "引き寄せ終わったら音は止まる")
	arena.free()
