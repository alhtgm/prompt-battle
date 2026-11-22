# 撃つ武器の弾の見た目と演出。機関銃は細長く光る曳光弾、ロケットは弾体・噴射炎・煙の尾。
# 撃った瞬間の銃口の光、当たった所（機体・壁）の火花、ロケットの爆発も出す。バトルの状態は読むだけで、乱数は使わない。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")

## 飛んでいる弾の見た目：弾の番号 → [ノード, 最後に見た位置, 最後に見た速度, 撃った機体, ロケットか, 煙の尾（なければ null）]
var live: Dictionary = {}
## 消えるまで動かす演出：[ノード, 経過時間, 寿命, 動かし方]
var effects: Array = []
var _time: float = 0.0
## このコマで、映っていた弾が機体に当たった数（撃たれた機体の番号 → 数）。被弾の記録と突き合わせる
var _robot_hits: Dictionary = {}
var _half: float = 10.0
var _radius: float = 1.0
var _tracer_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _body_mat: StandardMaterial3D
var _nose_mat: StandardMaterial3D


## half_size：アリーナの半分の幅、radius：機体の半径
func setup(half_size: float, radius: float) -> void:
	_half = half_size
	_radius = radius
	_tracer_mat = _glow_mat(Look.TRACER_COLOR, 1.0)
	_tail_mat = _glow_mat(Look.TRACER_COLOR, Look.TRACER_TAIL_ALPHA)
	_flash_mat = _glow_mat(Look.MUZZLE_COLOR, 1.0)
	_spark_mat = _glow_mat(Look.SPARK_COLOR, 1.0)
	_fire_mat = _glow_mat(Look.ROCKET_FIRE_COLOR, 1.0)
	_core_mat = _glow_mat(Look.ROCKET_CORE_COLOR, 1.0)
	# 光と火の玉は機体に隠れないよう、手前に重ねて描く
	for m: StandardMaterial3D in [_flash_mat, _fire_mat, _core_mat]:
		m.no_depth_test = true
		m.render_priority = 1
	_flame_mat = _glow_mat(Look.ROCKET_FLAME_COLOR, 1.0)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Look.ROCKET_BODY_COLOR
	_body_mat.metallic = 0.6
	_body_mat.roughness = 0.5
	_nose_mat = StandardMaterial3D.new()
	_nose_mat.albedo_color = Look.ROCKET_NOSE_COLOR
	_nose_mat.roughness = 0.6


## 弾を数える（テスト用）
func shot_count() -> int:
	return live.size()


## バトルの状態を読んで、弾の見た目を合わせ、新しい弾には銃口の光を、消えた弾には着弾の演出を出す。
## delta が 0（一時停止）のときは、火花や煙も止める
func sync(sim: Variant, delta: float) -> void:
	_time += delta
	_robot_hits.clear()
	var seen: Dictionary = {}
	for s: Variant in sim.shots:
		var id: int = int(s.id)
		seen[id] = true
		var pos := Vector3(s.x, Look.SHOT_HEIGHT, s.z)
		var vel := Vector3(s.vx, 0.0, s.vz)
		if not live.has(id):
			var rocket: bool = Look.ROCKET_WEAPONS.has(str(s.weapon))
			var made: Node3D = _make_rocket() if rocket else _make_tracer()
			add_child(made)
			var trail: CPUParticles3D = _make_trail() if rocket else null
			if trail != null:
				trail.position = pos
				add_child(trail)
				trail.emitting = true  # 煙は世界に置いていくので、置いてから出し始める
			live[id] = [made, pos, vel, int(s.owner), rocket, trail]
			_muzzle(pos, vel, rocket)
		var e: Array = live[id]
		e[1] = pos
		e[2] = vel
		var node: Node3D = e[0]
		node.position = pos
		if vel.length() > 0.01:
			node.look_at(pos + vel, Vector3.UP)
		if e[5] != null:
			(e[5] as CPUParticles3D).position = pos - vel.normalized() * Look.ROCKET_LENGTH * 0.6
		if e[4]:
			# 噴射炎は時間の関数で伸び縮みさせる（乱数は使わない）
			var flame: Node3D = node.get_node("Flame")
			flame.scale = Vector3.ONE * (1.0 + Look.ROCKET_FLAME_FLICKER * sin(_time * 71.0 + id))
	for id: int in live.keys():
		if not seen.has(id):
			_finish(live[id], sim)
			live.erase(id)
	_update_effects(delta)


## 消えた弾：機体に当たった／壁に当たった／届く距離の端で消えた、を見分けて演出を出す
func _finish(e: Array, sim: Variant) -> void:
	var node: Node3D = e[0]
	var pos: Vector3 = e[1]
	var vel: Vector3 = e[2]
	var rocket: bool = e[4]
	node.queue_free()
	if e[5] != null:
		# 煙の尾は切り離して、出した煙が消えるまで残す
		var trail: CPUParticles3D = e[5]
		trail.emitting = false
		effects.append([trail, 0.0, trail.lifetime + 0.1, ""])
	var dir: Vector3 = vel.normalized() if vel.length() > 0.01 else Vector3.FORWARD
	var where: String = "range"
	var at: Vector3 = pos
	var shooter: int = int(e[3])
	if shooter >= 0 and shooter < sim.robots.size():
		var tgt: Variant = sim.robots[1 - shooter]
		var c := Vector3(tgt.x, Look.SHOT_HEIGHT, tgt.z)
		# 最後に見た位置から少し前までの道のりが機体にかかっていれば、当たったとみなす
		var back: Vector3 = pos - vel * Look.SHOT_HIT_LOOKBACK_SEC
		if not tgt.fell and _segment_distance(c, back, pos) < _radius + Look.SHOT_HIT_MARGIN:
			where = "robot"
			_robot_hits[1 - shooter] = int(_robot_hits.get(1 - shooter, 0)) + 1
			at = c - dir * _radius * 0.9  # 撃たれた側の表面
	if where == "range":
		var to_wall: float = _distance_to_wall(pos, dir)
		if to_wall < Look.SHOT_WALL_MARGIN:
			where = "wall"
			at = pos + dir * to_wall
	if rocket:
		_explode(at, where == "range")
	elif where != "range":
		_impact_sparks(at, dir)


## 撃つ武器の被弾の記録を受け取る（sync の後に呼ぶ）。映っていた弾の着弾で演出を出し済みなら何もしない。
## 倍速などで弾が一度も映らずに当たったときは、撃ってきた側の表面に演出を出す
func on_shot_hit(sim: Variant, victim: int, attacker: int, weapon_id: String) -> void:
	var done: int = int(_robot_hits.get(victim, 0))
	if done > 0:
		_robot_hits[victim] = done - 1
		return
	if victim < 0 or victim >= sim.robots.size() or attacker < 0 or attacker >= sim.robots.size():
		return
	var v: Variant = sim.robots[victim]
	var a: Variant = sim.robots[attacker]
	var c := Vector3(v.x, Look.SHOT_HEIGHT, v.z)
	var dir := Vector3(v.x - a.x, 0.0, v.z - a.z)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var at: Vector3 = c - dir * _radius * 0.9
	if Look.ROCKET_WEAPONS.has(weapon_id):
		_explode(at, false)
	else:
		_impact_sparks(at, dir)


func _update_effects(delta: float) -> void:
	for k: int in range(effects.size() - 1, -1, -1):
		var fx: Array = effects[k]
		var n: Node3D = fx[0]
		if n is CPUParticles3D:
			(n as CPUParticles3D).speed_scale = 0.0 if delta <= 0.0 else 1.0
		fx[1] += delta
		var t: float = clampf(fx[1] / fx[2], 0.0, 1.0)
		match str(fx[3]):
			"flash":
				# すぐ大きくなって、薄れながら消える光
				n.scale = Vector3.ONE * maxf(0.01, sqrt(t))
				_set_alpha(n, 1.0 - t)
			"fireball":
				n.scale = Vector3.ONE * maxf(0.01, lerpf(0.3, 1.0, sqrt(t)))
				_set_alpha(n, 1.0 - t)
		if fx[1] >= fx[2]:
			n.queue_free()
			effects.remove_at(k)


# ---- 弾の見た目 ----

## 機関銃の曳光弾：明るい芯と、後ろへ伸びる薄い尾（-Z が進む向き）
func _make_tracer() -> Node3D:
	var root := Node3D.new()
	var w: float = Look.TRACER_WIDTH
	root.add_child(_mesh_box(Vector3(w, w, Look.TRACER_LENGTH), Vector3.ZERO, _tracer_mat))
	var tail: float = Look.TRACER_TAIL_LENGTH
	root.add_child(_mesh_box(Vector3(w * 0.7, w * 0.7, tail), Vector3(0, 0, (Look.TRACER_LENGTH + tail) * 0.5), _tail_mat))
	return root


## ロケット：灰色の筒、赤い先、後ろの噴射炎
func _make_rocket() -> Node3D:
	var root := Node3D.new()
	var r: float = Look.ROCKET_RADIUS
	var length: float = Look.ROCKET_LENGTH
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = length
	cyl.radial_segments = 8
	body.mesh = cyl
	body.material_override = _body_mat
	body.rotation_degrees = Vector3(90, 0, 0)  # 筒の向きを進む向き（Z）にそろえる
	root.add_child(body)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = r
	cone.height = r * 2.5
	cone.radial_segments = 8
	nose.mesh = cone
	nose.material_override = _nose_mat
	nose.rotation_degrees = Vector3(-90, 0, 0)  # とがった方を前（-Z）へ
	nose.position = Vector3(0, 0, -(length * 0.5 + r * 1.25))
	root.add_child(nose)
	var flame := Node3D.new()
	flame.name = "Flame"
	flame.position = Vector3(0, 0, length * 0.5)
	var fm := MeshInstance3D.new()
	var fc := CylinderMesh.new()
	fc.top_radius = 0.0
	fc.bottom_radius = r * 1.1
	fc.height = Look.ROCKET_FLAME_LENGTH
	fc.radial_segments = 6
	fm.mesh = fc
	fm.material_override = _flame_mat
	fm.rotation_degrees = Vector3(90, 0, 0)  # とがった方を後ろ（+Z）へ
	fm.position = Vector3(0, 0, Look.ROCKET_FLAME_LENGTH * 0.5)
	flame.add_child(fm)
	root.add_child(flame)
	for c: Node in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


## ロケットの煙の尾。煙は世界に置いていく（弾についていかない）
func _make_trail() -> CPUParticles3D:
	var p := _particles(Look.ROCKET_TRAIL_AMOUNT, Look.ROCKET_TRAIL_LIFE, false)
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.spread = 30.0
	p.initial_velocity_min = 0.1
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0, 0.8, 0)
	return p


# ---- 撃つ・当たる ----

## 銃口の光（ロケットは大きめの光と、煙のひと吹き）
func _muzzle(pos: Vector3, vel: Vector3, rocket: bool) -> void:
	var size: float = Look.ROCKET_MUZZLE_SIZE if rocket else Look.MUZZLE_SIZE
	var f: MeshInstance3D = _mesh_sphere(size, pos, _flash_mat.duplicate())
	add_child(f)
	effects.append([f, 0.0, Look.ROCKET_MUZZLE_LIFE if rocket else Look.MUZZLE_LIFE, "flash"])
	if rocket:
		var puff := _particles(Look.ROCKET_MUZZLE_SMOKE, 0.7, false)
		puff.position = pos - vel.normalized() * 0.3
		puff.spread = 70.0
		add_child(puff)
		puff.emitting = true
		effects.append([puff, 0.0, 0.8, ""])


## 機関銃の弾が当たった所の火花。撃ってきた方へ跳ね返るように散らす
func _impact_sparks(at: Vector3, dir: Vector3) -> void:
	var p := _particles(Look.BULLET_SPARK_AMOUNT, Look.BULLET_SPARK_LIFE, true)
	p.direction = (-dir + Vector3.UP * 0.6).normalized()
	p.spread = Look.BULLET_SPARK_SPREAD_DEG
	p.initial_velocity_min = Look.BULLET_SPARK_SPEED * 0.4
	p.initial_velocity_max = Look.BULLET_SPARK_SPEED
	p.gravity = Vector3(0, -18, 0)
	p.position = at
	add_child(p)
	p.emitting = true
	effects.append([p, 0.0, Look.BULLET_SPARK_LIFE + 0.1, ""])
	var f: MeshInstance3D = _mesh_sphere(Look.BULLET_HIT_FLASH_SIZE, at, _flash_mat.duplicate())
	add_child(f)
	effects.append([f, 0.0, Look.MUZZLE_LIFE, "flash"])


## ロケットの爆発：火の玉・白い芯・火花・煙。空中（届く距離の端）では少し小さく
func _explode(at: Vector3, in_air: bool) -> void:
	var size: float = Look.ROCKET_BLAST_SIZE * (0.7 if in_air else 1.0)
	var ball: MeshInstance3D = _mesh_sphere(size, at, _fire_mat.duplicate())
	add_child(ball)
	effects.append([ball, 0.0, Look.ROCKET_BLAST_LIFE, "fireball"])
	var core: MeshInstance3D = _mesh_sphere(size * 0.6, at, _core_mat.duplicate())
	add_child(core)
	effects.append([core, 0.0, Look.ROCKET_BLAST_LIFE * 0.6, "fireball"])
	var flash: MeshInstance3D = _mesh_sphere(size * 0.35, at, _flash_mat.duplicate())
	add_child(flash)
	effects.append([flash, 0.0, Look.ROCKET_BLAST_LIFE * 0.3, "flash"])
	var sparks := _particles(Look.ROCKET_BLAST_SPARKS, 0.7, true)
	sparks.spread = 90.0
	sparks.initial_velocity_min = 3.0
	sparks.initial_velocity_max = 9.0
	sparks.gravity = Vector3(0, -16, 0)
	sparks.position = at
	add_child(sparks)
	sparks.emitting = true
	effects.append([sparks, 0.0, 0.8, ""])
	var smoke := _particles(Look.ROCKET_BLAST_SMOKE, 1.4, false)
	smoke.spread = 90.0
	smoke.initial_velocity_min = 0.5
	smoke.initial_velocity_max = 1.6
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.position = at
	add_child(smoke)
	smoke.emitting = true
	effects.append([smoke, 0.0, 1.5, ""])


# ---- 計算の手助け ----

## 点 c から線分 a-b までの距離
static func _segment_distance(c: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var l2: float = ab.length_squared()
	if l2 < 0.000001:
		return c.distance_to(a)
	var t: float = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return c.distance_to(a + ab * t)


## pos から dir の向きに進んで壁に着くまでの距離
func _distance_to_wall(pos: Vector3, dir: Vector3) -> float:
	var best: float = INF
	if absf(dir.x) > 0.0001:
		best = minf(best, ((_half if dir.x > 0.0 else -_half) - pos.x) / dir.x)
	if absf(dir.z) > 0.0001:
		best = minf(best, ((_half if dir.z > 0.0 else -_half) - pos.z) / dir.z)
	return maxf(0.0, best)


# ---- 部品 ----

func _mesh_box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _mesh_sphere(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	m.mesh = s
	m.material_override = mat
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


func _set_alpha(n: Node3D, a: float) -> void:
	var m := n as MeshInstance3D
	if m != null and m.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = m.material_override
		mat.albedo_color.a = clampf(a, 0.0, 1.0)


## 光を足し合わせる、影のない材質
func _glow_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	return m


## glow なら光る火花、そうでなければ灰色の煙（薄れながら大きくなる）
func _particles(amount: int, life: float, glow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	var mesh := BoxMesh.new()
	if glow:
		mesh.size = Vector3(0.08, 0.08, 0.08)
		mesh.material = _spark_mat
	else:
		mesh.size = Vector3(0.36, 0.36, 0.36)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		mesh.material = m
		var ramp := Gradient.new()
		ramp.set_color(0, Color(Look.SHOT_SMOKE_COLOR, 0.7))
		ramp.set_color(1, Color(Look.SHOT_SMOKE_COLOR, 0.0))
		p.color_ramp = ramp
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.5))
		grow.add_point(Vector2(1, 1.8))
		p.scale_amount_curve = grow
	p.mesh = mesh
	return p
