# バリア（シールドのスキル）の見た目のテスト。展開→維持→消滅の順に進むこと、被弾の波紋、機体の見た目からの使われ方を確かめる。
# 画面には描かない（状態とシェーダーに渡す値だけを見る）。
extends "res://tests/support/test_case.gd"

const GameData := preload("res://core/game_data.gd")
const Build := preload("res://core/build.gd")
const PartInstance := preload("res://core/part_instance.gd")
const Look := preload("res://view/look.gd")
const ShieldView := preload("res://view/arena/shield_view.gd")
const RobotView := preload("res://view/arena/robot_view.gd")

const DT: float = 1.0 / 60.0


class FakeSkill:
	var def: Variant
	var active_t: float = 0.0


class FakeRobot:
	var x: float = 0.0
	var z: float = 0.0
	var th: float = 0.0
	var stun: float = 0.0
	var fell: bool = false
	var hp: float = 100.0
	var name: String = "テスト"
	var say: String = ""
	var skills: Array = []


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _run(view: Node3D, active: bool, frac: float, seconds: float) -> void:
	var n: int = ceili(seconds / DT)
	for k: int in n:
		view.update(active, frac, DT)


func _param(view: Node3D, key: String) -> Variant:
	return (view.dome.material_override as ShaderMaterial).get_shader_parameter(key)


func test_open_hold_close() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var v: Node3D = ShieldView.new()
	tree.root.add_child(v)
	v.setup(1.5, 2.0)
	check_eq(v.state, ShieldView.State.OFF, "最初は張っていない")
	check(not v.dome.visible, "張っていないときは膜が見えない")
	_run(v, true, 1.0, DT)
	check_eq(v.state, ShieldView.State.OPENING, "スキルが効くと展開が始まる")
	check(v.dome.visible, "展開が始まると膜が見える")
	_run(v, true, 1.0, Look.SHIELD_OPEN_SEC * 0.5)
	var open_mid: float = _param(v, "open")
	check(open_mid > 0.0 and open_mid < 1.0, "展開の途中は少しずつ現れる（%.2f）" % open_mid)
	_run(v, true, 0.9, Look.SHIELD_OPEN_SEC * 0.5 + 0.05)
	check_eq(v.state, ShieldView.State.ON, "展開が終わると張った状態")
	check(is_equal_approx(float(_param(v, "open")), 1.0), "張った状態では全部見える")
	var ds: Vector3 = v.dome.scale
	check(is_equal_approx(ds.x, ds.y) and is_equal_approx(ds.y, ds.z), "膜はつぶれていない丸い球")
	check(v.streaks.emitting, "張っている間は中を光の筋が飛び交う")
	check(is_equal_approx(float(_param(v, "flicker")), 0.0), "残り時間が多いときはちらつかない")
	_run(v, true, Look.SHIELD_LOW_FRAC * 0.3, DT)
	check(float(_param(v, "flicker")) > 0.5, "残り時間が少ないとちらつく")
	# 被弾：攻撃が来た向きに波紋が出る
	await _frame()
	v.hit(v.global_position + Vector3(5, 0, 0))
	_run(v, true, 0.5, DT)
	check(float(_param(v, "hit_age")) < 0.1, "被弾してすぐは波紋が若い")
	var dir: Vector3 = _param(v, "hit_dir")
	check(dir.x > 0.8, "波紋は攻撃が来た向き（+X）から広がる（%s）" % dir)
	# 消滅
	_run(v, false, 0.0, DT)
	check_eq(v.state, ShieldView.State.CLOSING, "効果が切れると消滅が始まる")
	_run(v, false, 0.0, Look.SHIELD_CLOSE_SEC * 0.5)
	var dis: float = _param(v, "dissolve")
	check(dis > 0.0 and dis < 1.0, "消滅の途中は膜が少しずつ焼け切れて消える（%.2f）" % dis)
	_run(v, false, 0.0, Look.SHIELD_CLOSE_SEC)
	check_eq(v.state, ShieldView.State.OFF, "消滅が終わると張っていない状態に戻る")
	check(not v.dome.visible, "消えたら膜は見えない")
	check(not v.streaks.emitting, "消えたら光の筋も止まる")
	check(is_equal_approx(v.light.light_energy, 0.0), "消えたら照り返しの光も消える")
	# 張っていないときの被弾は何も起こさない
	v.hit(v.global_position + Vector3(5, 0, 0))
	check_eq(v.state, ShieldView.State.OFF, "張っていないときの被弾では何も出ない")
	v.queue_free()
	await _frame()


func test_robot_shows_shield_only_for_shield_skill() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var data := GameData.new()
	data.load_dir()
	var b := Build.new()
	for spec: Array in [["frame_light", "frame", 1], ["weapon_drill", "weapon", 2], ["skill_shield", "skill", 3],
			["skill_booster", "skill", 4]]:
		var p := PartInstance.new()
		p.def_id = spec[0]
		p.kind = spec[1]
		p.uid = spec[2]
		if spec[1] == "frame":
			b.frame = p
		elif spec[1] == "weapon":
			b.weapons.append(p)
		else:
			b.skills.append(p)
	var v: Node3D = RobotView.new()
	tree.root.add_child(v)
	v.setup(data, b, 0.9, Color(0.4, 0.5, 0.7), Color(0.3, 0.7, 1.0))
	var r := FakeRobot.new()
	var shield := FakeSkill.new()
	shield.def = data.get_part("skill_shield")
	var booster := FakeSkill.new()
	booster.def = data.get_part("skill_booster")
	r.skills = [shield, booster]
	shield.active_t = 2.0
	v.sync(r, DT)
	check_eq(v.shield.state, ShieldView.State.OPENING, "シールドが効くとバリアを張る")
	check(not v.skill_fx.booster_on, "シールドだけならブースターの炎は出さない")
	booster.active_t = 1.0
	v.sync(r, DT)
	check(v.skill_fx.booster_on, "ブースターが効いていれば噴射炎を出す")
	check(v.shield.state != ShieldView.State.OFF, "ブースターと同時でもバリアは張ったまま")
	shield.active_t = 0.0
	booster.active_t = 0.0
	v.sync(r, DT)
	check_eq(v.shield.state, ShieldView.State.CLOSING, "シールドが切れるとバリアが消え始める")
	shield.active_t = 2.0
	r.fell = true
	v.sync(r, DT)
	check(v.shield.state != ShieldView.State.OPENING, "穴に落ちた機体はバリアを張らない")
	v.queue_free()
	await _frame()
