# 撃つ武器の弾の見た目と演出のテスト。弾に番号と武器の種類が付くこと（通信対戦でも届くこと）、
# 曳光弾・ロケットが弾に合わせて動くこと、機体・壁に当たったら火花やロケットの爆発が出ること、演出がやがて消えることを確かめる。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Helpers := preload("res://tests/support/battle_helpers.gd")
const MatchSession := preload("res://core/match_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const Protocol := preload("res://net/protocol.gd")
const RemoteSim := preload("res://net/remote_sim.gd")
const ShotFx := preload("res://view/arena/shot_fx.gd")
const Look := preload("res://view/look.gd")

const DT: float = 1.0 / 60.0
const RADIUS: float = 0.9
const HALF: float = 10.0


class FakeRobot:
	var x: float = 0.0
	var z: float = 0.0
	var fell: bool = false


class FakeShot:
	var x: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vz: float = 0.0
	var id: int = 0
	var weapon: String = ""
	var owner: int = 0


class FakeSim:
	var robots: Array = []
	var shots: Array = []


func _fake_sim() -> FakeSim:
	var s := FakeSim.new()
	for i: int in 2:
		var r := FakeRobot.new()
		r.x = -4.0 if i == 0 else 4.0
		s.robots.append(r)
	return s


func _shot(id: int, weapon: String, x: float, z: float, vx: float, vz: float, owner: int = 0) -> FakeShot:
	var s := FakeShot.new()
	s.id = id
	s.weapon = weapon
	s.x = x
	s.z = z
	s.vx = vx
	s.vz = vz
	s.owner = owner
	return s


func _fx() -> Node3D:
	var fx: Node3D = ShotFx.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(fx)
	fx.setup(HALF, RADIUS)
	return fx


func _count_particles(fx: Node3D) -> int:
	var n: int = 0
	for e: Array in fx.effects:
		if e[0] is CPUParticles3D:
			n += 1
	return n


func test_shots_carry_id_and_weapon() -> void:
	var data: GameData = Helpers.load_data()
	var ids: Dictionary = {}
	var found: int = 0
	for seed_value: int in range(1, 30):
		var sim: Variant = Helpers.make_match(data, seed_value)
		var last_id: int = 0
		var guard: int = 0
		while not sim.over and guard < 60 * 200:
			sim.step()
			guard += 1
			for s: Variant in sim.shots:
				var key: String = "%d:%d" % [seed_value, s.id]
				if ids.has(key):
					continue
				ids[key] = true
				found += 1
				check(s.id > last_id, "弾の番号は撃った順に増える")
				last_id = s.id
				var def: Variant = data.get_part(s.weapon)
				check(def != null and def.behavior == "shoot", "弾には撃った武器のパーツIDが付く（%s）" % s.weapon)
		if found >= 20:
			break
	check(found >= 20, "撃つ武器のある試合で弾が見つかる（%d）" % found)


func test_frames_carry_shot_id_and_weapon_online() -> void:
	var data: GameData = Helpers.load_data()
	var setup: Array = []
	for i: int in 6:
		setup.append({"name": "P%d" % i, "is_human": false})
	var s := MatchSession.new(data, 31, setup, DefaultAgents.new())
	s.finish_draft()
	s.finish_build()
	var frame: Dictionary = {}
	var bi: int = -1
	for k: int in 60 * 60:
		s.update(DT)
		if s.phase != "battle":
			break
		frame = Protocol.battle_frame(s, 10)
		for j: int in frame["battles"].size():
			if not frame["battles"][j]["shots"].is_empty():
				bi = j
				break
		if bi >= 0:
			break
	check(bi >= 0, "どこかのバトルで弾が飛ぶ")
	if bi < 0:
		return
	var sim: Variant = s.battles[bi].sim
	var e: Array = frame["battles"][bi]["shots"][0]
	check_eq(e.size(), 7, "弾は位置・速度・番号・武器・撃った機体を送る")
	check_eq(int(e[4]), sim.shots[0].id, "番号が届く")
	check_eq(str(e[5]), sim.shots[0].weapon, "武器の種類が届く")
	# 送られてきた形からも同じ番号と武器が読める。届くまでの間は速度で先へ進める
	var decoded: Dictionary = Protocol.decode(Protocol.encode(Protocol.FRAME, frame))
	var remote := RemoteSim.new()
	remote.setup(data, [sim.robots[0].build, sim.robots[1].build], ["A", "B"])
	remote.apply_frame(decoded["battles"][bi])
	check_eq(remote.shots[0].id, sim.shots[0].id, "通信対戦の写しにも番号が入る")
	check_eq(remote.shots[0].weapon, sim.shots[0].weapon, "通信対戦の写しにも武器の種類が入る")
	check_eq(remote.shots[0].owner, sim.shots[0].owner, "通信対戦の写しにも撃った機体が入る")
	var x0: float = remote.shots[0].x
	remote.advance(0.05)
	check(absf(remote.shots[0].x - (x0 + sim.shots[0].vx * 0.05)) < 0.0001, "次の動きが届くまで、弾は速度で進む")
	# 古い形（位置だけ）が来ても壊れない
	remote.apply_frame({"robots": decoded["battles"][bi]["robots"], "shots": [[1.0, 2.0]]})
	check(remote.shots[0].x == 1.0 and remote.shots[0].id == 0, "位置だけの弾も読める")


func test_tracer_and_rocket_follow_shots() -> void:
	var fx: Node3D = _fx()
	var sim := _fake_sim()
	sim.shots.append(_shot(1, "weapon_mg", -3.0, 0.0, 32.0, 0.0))
	sim.shots.append(_shot(2, "weapon_rocket", -3.0, 1.0, 0.0, 16.0))
	fx.sync(sim, DT)
	check_eq(fx.shot_count(), 2, "弾ごとに見た目ができる")
	var mg: Node3D = fx.live[1][0]
	var rk: Node3D = fx.live[2][0]
	check(not fx.live[1][4] and fx.live[2][4], "機関銃は曳光弾、ロケットはロケットの見た目")
	check(fx.live[1][5] == null and fx.live[2][5] != null, "ロケットだけ煙の尾を引く")
	check(mg.position.distance_to(Vector3(-3.0, Look.SHOT_HEIGHT, 0.0)) < 0.001, "曳光弾は弾の位置にある")
	check((-mg.global_transform.basis.z).distance_to(Vector3(1, 0, 0)) < 0.01, "曳光弾は進む向きを向く")
	check((-rk.global_transform.basis.z).distance_to(Vector3(0, 0, 1)) < 0.01, "ロケットは進む向きを向く")
	var flashes: int = 0
	for e: Array in fx.effects:
		if e[3] == "flash":
			flashes += 1
	check_eq(flashes, 2, "撃った瞬間に、弾ごとに銃口が光る")
	sim.shots[0].x = -2.0
	fx.sync(sim, DT)
	check(mg.position.x > -2.01 and mg.position.x < -1.99, "弾が進むと見た目も進む")
	check_eq(fx.shot_count(), 2, "同じ弾に見た目を作り直さない")
	fx.queue_free()


func test_hits_make_sparks_and_rockets_explode() -> void:
	var fx: Node3D = _fx()
	var sim := _fake_sim()
	# 1. 機関銃の弾が相手（x=4）に当たって消える
	sim.shots.append(_shot(1, "weapon_mg", 3.4, 0.0, 32.0, 0.0))
	fx.sync(sim, DT)
	var before: int = _count_particles(fx)
	sim.shots.clear()
	fx.sync(sim, DT)
	check_eq(fx.shot_count(), 0, "消えた弾の見た目は消す")
	check_eq(_count_particles(fx), before + 1, "機体に当たると火花が散る")
	var spark: CPUParticles3D = null
	for e: Array in fx.effects:
		if e[0] is CPUParticles3D:
			spark = e[0]
	check(spark != null and spark.position.x < 4.0 - RADIUS * 0.5, "火花は撃たれた側の表面に出る")
	check(spark != null and spark.direction.x < 0.0, "火花は撃ってきた方へ跳ね返る")
	# 被弾の記録が来ても、映っていた弾の分は二重に出さない
	var n: int = fx.effects.size()
	fx.on_shot_hit(sim, 1, 0, "weapon_mg")
	check_eq(fx.effects.size(), n, "映っていた弾の着弾は二重に出さない")
	# 倍速などで弾が映らないまま当たったときは、被弾の記録から出す
	fx.on_shot_hit(sim, 1, 0, "weapon_mg")
	check(fx.effects.size() > n, "映らなかった弾の被弾でも火花が出る")
	# 2. 届く距離の端で消えた機関銃の弾は何も出さない
	sim.shots.append(_shot(2, "weapon_mg", 0.0, 3.0, 32.0, 0.0))
	fx.sync(sim, DT)
	before = _count_particles(fx)
	sim.shots.clear()
	fx.sync(sim, DT)
	check_eq(_count_particles(fx), before, "宙で消えた弾は火花を出さない")
	# 3. 壁に当たった弾は火花を出す
	sim.shots.append(_shot(3, "weapon_mg", 0.0, HALF - 0.3, 0.0, 32.0))
	fx.sync(sim, DT)
	before = _count_particles(fx)
	sim.shots.clear()
	fx.sync(sim, DT)
	check_eq(_count_particles(fx), before + 1, "壁に当たると火花が散る")
	# 4. ロケットは当たると爆発する（火の玉・火花・煙）
	sim.shots.append(_shot(4, "weapon_rocket", 3.3, 0.0, 16.0, 0.0))
	fx.sync(sim, DT)
	var fireballs: int = 0
	sim.shots.clear()
	fx.sync(sim, DT)
	for e: Array in fx.effects:
		if e[3] == "fireball":
			fireballs += 1
	check(fireballs >= 1, "ロケットが当たると火の玉が出る")
	# 5. 穴に落ちた相手には当たらない
	sim.robots[1].fell = true
	sim.shots.append(_shot(5, "weapon_mg", 3.4, 0.0, 32.0, 0.0))
	fx.sync(sim, DT)
	before = _count_particles(fx)
	sim.shots.clear()
	fx.sync(sim, DT)
	check_eq(_count_particles(fx), before, "落ちた機体には火花を出さない")
	fx.queue_free()


func test_effects_freeze_on_pause_and_clean_up() -> void:
	var fx: Node3D = _fx()
	var sim := _fake_sim()
	sim.shots.append(_shot(1, "weapon_rocket", 3.3, 0.0, 16.0, 0.0))
	fx.sync(sim, DT)
	sim.shots.clear()
	fx.sync(sim, DT)
	check(not fx.effects.is_empty(), "爆発の演出が出ている")
	var count: int = fx.effects.size()
	fx.sync(sim, 0.0)
	var frozen: bool = true
	for e: Array in fx.effects:
		if e[0] is CPUParticles3D and (e[0] as CPUParticles3D).speed_scale != 0.0:
			frozen = false
	check(frozen, "止めている間（delta が 0）は火花や煙も止まる")
	for k: int in 30:
		fx.sync(sim, 0.0)
	check_eq(fx.effects.size(), count, "止めている間は演出が消えない")
	for k: int in 200:
		fx.sync(sim, DT)
	check(fx.effects.is_empty(), "演出はやがてすべて消える")
	for e: Node in fx.get_children():
		check(e.is_queued_for_deletion(), "消えた演出のノードは片付ける")
	fx.queue_free()
