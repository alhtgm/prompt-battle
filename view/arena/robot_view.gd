# 3Dのアリーナに置く機体1体の見た目。パーツの .glb があればそれを、なければ仮の箱で描き、バトルの状態を読んで位置・向き・転倒・落下を映す。
# 計算上の (x, z) をそのまま3Dの (x, z) に置く。計算上の向き th（+x から +z へ回る）は rotation.y = -th になる。
extends Node3D

const GameData := preload("res://core/game_data.gd")
const Grime := preload("res://view/grime.gd")
const Look := preload("res://view/look.gd")
const PartModels := preload("res://view/arena/part_models.gd")
const ShieldView := preload("res://view/arena/shield_view.gd")
const ExplosionView := preload("res://view/arena/explosion_view.gd")
const SkillFxView := preload("res://view/arena/skill_fx_view.gd")
const FallBurstView := preload("res://view/arena/fall_burst_view.gd")
const HookView := preload("res://view/arena/hook_view.gd")

## 武器とスキルの目印の色（動き方ごと）
const WEAPON_COLORS: Dictionary = {
	"grind": Color(0.62, 0.62, 0.6), "strike": Color(0.4, 0.4, 0.42), "lift": Color(0.7, 0.55, 0.12),
	"ram": Color(0.35, 0.34, 0.33), "shoot": Color(0.18, 0.18, 0.2), "hook": Color(0.3, 0.32, 0.3),
}
const SKILL_COLOR := Color(0.4, 0.95, 1.0)
## ひっくり返る・戻る・落ちる速さ（見た目だけの値）
const FLIP_SPEED: float = 10.0
const FALL_SPEED: float = 6.0

var body: Node3D
var label: Label3D
## ブースターとオーバークロックの見た目
var skill_fx: Node3D
## バリア（シールドのスキル）の見た目
var shield: Node3D
## 穴に落ちたときの光の柱（落ちる前は null）
var fall_burst: Node3D = null
var _glow: Color = Color.WHITE
## ハープーンガンの鎖と釣り針（持っていなければ null）と、武器の先の位置（機体の中の座標。武器の番号順）
var hook_view: Node3D = null
var weapon_tips: Array[Vector3] = []
var _radius: float = 0.9
## 自爆装置の赤い点滅の重ね塗り（点滅していなければ null）と、今点いているか
var blink_mat: StandardMaterial3D = null
var blink_on: bool = false
var _blink_light: OmniLight3D = null
var _blink_phase: float = 0.0
## どのパーツをモデルで描いたか（テストと確認用）。false は仮の箱
var used_models: Dictionary = {"frame": false, "weapons": [], "skills": []}
## 壊されたときの爆発（壊される前は null）
var explosion: Node3D = null
var _fell_time: float = 0.0
var _roll: float = 0.0
var _top: float = 1.0
var _size: float = 1.8


## 機体の形を作る。build は Build、color は陣営の地の色、glow は陣営の光る目印の色、
## label_lift は頭上の文字を上げる量（2機の文字が重ならないように）
func setup(data: GameData, build: Variant, robot_radius: float, color: Color, glow: Color, label_lift: float = 0.0) -> void:
	var fdef: GameData.PartDef = data.get_part(build.frame.def_id)
	body = Node3D.new()
	add_child(body)
	# 車体：モデルがあればそれを、なければ箱で作る。どちらでも、大きさと取り付け位置の目印が決まる
	var dims: Dictionary = _add_frame_model(fdef, robot_radius, color)
	if dims.is_empty():
		dims = _add_frame_boxes(fdef, robot_radius, color)
	var length: float = dims["length"]
	var width: float = dims["width"]
	var top: float = dims["top"]
	_top = top
	_size = robot_radius * 2.0
	used_models["frame"] = dims["model"]
	# 陣営の目印：箱の車体は前の光る帯。モデルは形がいろいろで帯が浮くので、足もとの光る輪にする
	if dims["model"]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = robot_radius * Look.MODEL_RING_RADIUS - 0.05
		torus.outer_radius = robot_radius * Look.MODEL_RING_RADIUS + 0.05
		torus.rings = 24
		torus.ring_segments = 4
		ring.mesh = torus
		ring.material_override = Grime.material(glow, 0.0, 0.5, 1.0, glow)
		ring.scale = Vector3(1.0, 0.2, 1.0)
		ring.position.y = 0.03
		ring.set_meta("debris", false)  # 爆発しても部品として飛ばさず、消すだけ
		body.add_child(ring)
	else:
		_box(Vector3(0.08, 0.14, width * 0.8), Vector3(length * 0.5 + 0.02, top * 0.6, 0),
			Grime.material(glow, 0.0, 0.5, 1.0, glow))
	# 武器：目印があればそこへ、なければ前に並べる（撃つ武器は上に砲身）
	var weapon_mounts: Array = dims["weapon_mounts"]
	var n: int = build.weapons.size()
	for i: int in n:
		var wdef: GameData.PartDef = data.get_part(build.weapons[i].def_id)
		# ハープーンガンも、撃つ武器と同じく長い銃身として上に載せる
		var shoot: bool = wdef.behavior == "shoot" or wdef.behavior == "hook"
		var side: float = (float(i) - (n - 1) * 0.5) * (width / maxf(1.0, n)) * 0.9
		var mount: Transform3D
		if i < weapon_mounts.size():
			mount = weapon_mounts[i]
		elif shoot:
			mount = Transform3D(Basis.IDENTITY, Vector3(length * 0.35 - 0.6, top + 0.2, side))
		else:
			mount = Transform3D(Basis.IDENTITY, Vector3(length * 0.5 + 0.15, 0.4, side))
		var size: float = Look.MODEL_SHOOT_SIZE if shoot else Look.MODEL_WEAPON_SIZE
		# 武器の先（銃口）の位置。ハープーンガンの鎖はここから出る
		weapon_tips.append(mount * Vector3(size if shoot else 0.6, 0, 0))
		if _attach_model(wdef.model, mount, size, false, color):
			used_models["weapons"].append(true)
			continue
		used_models["weapons"].append(false)
		var mat: StandardMaterial3D = Grime.material(WEAPON_COLORS.get(wdef.behavior, Color.GRAY), 0.8, 0.55, 1.2)
		if shoot:
			_box(Vector3(1.2, 0.18, 0.18), mount * Vector3(0.6, 0, 0), mat)
		else:
			_box(Vector3(0.6, 0.3, width / maxf(1.0, n) * 0.7), mount * Vector3(0.3, 0, 0), mat)
	# スキル：目印があればそこへ、なければ後ろの上にアンテナ（先が光る）
	var skill_mounts: Array = dims["skill_mounts"]
	for i: int in build.skills.size():
		var sdef: GameData.PartDef = data.get_part(build.skills[i].def_id)
		var mount: Transform3D = skill_mounts[i] if i < skill_mounts.size() \
			else Transform3D(Basis.IDENTITY, Vector3(-length * 0.3, top, (i - 0.5) * 0.5))
		if _attach_model(sdef.model, mount, Look.MODEL_SKILL_SIZE, true, color):
			used_models["skills"].append(true)
			continue
		used_models["skills"].append(false)
		_box(Vector3(0.1, 0.6, 0.1), mount * Vector3(0, 0.3, 0), Grime.material(Color(0.2, 0.2, 0.2), 0.8, 0.6, 1.0))
		_box(Vector3(0.16, 0.12, 0.16), mount * Vector3(0, 0.65, 0),
			Grime.material(SKILL_COLOR, 0.0, 0.5, 1.0, SKILL_COLOR))
	# ハープーンガンを持っていれば、鎖と釣り針の見た目を用意する（鎖は世界の中に張るので、機体の向きに引きずられない）
	for w: Variant in build.weapons:
		if data.get_part(w.def_id).behavior == "hook" and hook_view == null:
			hook_view = HookView.new()
			add_child(hook_view)
			hook_view.top_level = true
			hook_view.setup()
	_radius = robot_radius
	# シールド以外の効果が続くスキル（ブースターの噴射炎、オーバークロックの赤い火花）
	skill_fx = SkillFxView.new()
	add_child(skill_fx)
	skill_fx.setup(length, top, robot_radius)
	_glow = glow
	# バリア（シールドのスキル）。機体が裏返っても膜は立ったままにするため、body ではなくここに置く
	shield = ShieldView.new()
	add_child(shield)
	shield.setup(robot_radius * Look.SHIELD_RADIUS, top + Look.SHIELD_HEIGHT_PAD)
	# 頭上の名前と一言（いつもカメラを向く）
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, top + 1.25 + label_lift, 0)
	label.font_size = 56
	label.modulate = glow.lightened(0.3)
	label.pixel_size = 0.01
	label.outline_size = 12
	label.no_depth_test = true
	label.visible = false  # 低い解像度では読めないので、文字は画面側（battle_screen）が2Dで重ねる
	add_child(label)


## バトルの機体の状態 r を映す
func sync(r: Variant, delta: float) -> void:
	position = Vector3(r.x, 0.0, r.z)
	rotation.y = -r.th
	# ひっくり返されている間は前後の軸で回して裏返す
	# ひっくり返されたとき（リフター）だけ裏返す。EMP やハープーンガンで止められているだけなら裏返さない
	var flipped: bool = bool(r.get("flipped")) if "flipped" in r else r.stun > 0.0
	var target_roll: float = PI if flipped and r.stun > 0.0 else 0.0
	_roll = move_toward(_roll, target_roll, FLIP_SPEED * delta)
	body.rotation.x = _roll
	# 穴に落ちたら沈んで小さくなる
	if r.fell:
		if fall_burst == null:
			# 穴から光の柱が吹き上がる演出。機体は沈んで縮むので、演出は落ちた場所に独立して置く
			fall_burst = FallBurstView.new()
			add_child(fall_burst)
			fall_burst.top_level = true
			fall_burst.global_position = get_parent_node_3d().to_global(Vector3(r.x, 0.0, r.z)) \
				if get_parent_node_3d() != null else Vector3(r.x, 0.0, r.z)
			fall_burst.setup(_glow)
		fall_burst.update(delta)
		_fell_time += delta
		position.y = -FALL_SPEED * _fell_time * _fell_time
		scale = Vector3.ONE * maxf(0.05, 1.0 - _fell_time * 0.8)
	# シールドはバリア、ブースターとオーバークロックはそれぞれの演出で見せる
	var booster: bool = false
	var overclock: bool = false
	var shield_left: float = 0.0
	for s: Variant in r.skills:
		if s.active_t <= 0.0:
			continue
		match s.def.behavior:
			"shield":
				shield_left = maxf(shield_left, s.active_t / maxf(0.001, s.def.get_fixed("duration_sec", 1.0)))
			"booster":
				booster = true
			"overclock":
				overclock = true
	# 自爆装置の導火線が燃えている間は、赤く点滅し、自爆が近づくほど速くなる
	var fuse: float = float(r.get("fuse")) if "fuse" in r else -1.0
	var fuse_total: float = float(r.get("fuse_total")) if "fuse_total" in r else 0.0
	_update_fuse_blink(fuse, fuse_total, delta)
	# HPが尽きたら爆発して部品が散らばる（穴に落ちたときは爆発しない。導火線が燃えている間はまだ）
	var destroyed: bool = r.hp <= 0.0 and not r.fell and fuse < 0.0
	if destroyed and explosion == null:
		_clear_blink()
		explosion = ExplosionView.new()
		add_child(explosion)
		var self_destructed: bool = bool(r.get("self_destructed")) if "self_destructed" in r else false
		if self_destructed:
			# 自爆：ふつうの爆発より大きく、衝撃の輪は自爆の届く範囲まで広がる
			explosion.start(body, Vector3(0, _top * 0.5, 0), _size * Look.SELF_DESTRUCT_SIZE, _blast_range(r))
		else:
			explosion.start(body, Vector3(0, _top * 0.5, 0), _size)
	if explosion != null:
		explosion.update(delta)
	var alive: bool = not r.fell and not destroyed
	skill_fx.update(booster and alive, overclock and alive, delta)
	shield.update(shield_left > 0.0 and not r.fell and not destroyed, shield_left, delta)
	# ハープーンガンの鎖と釣り針：銃口から、釣り針（引き寄せている間は相手）まで
	if hook_view != null:
		var hs: String = str(r.get("hook_state")) if "hook_state" in r else ""
		if hs != "" and is_inside_tree():
			var slot: int = int(r.get("hook_slot"))
			var tip: Vector3 = weapon_tips[slot] if slot >= 0 and slot < weapon_tips.size() \
				else Vector3(_size * 0.5, _top * 0.6, 0)
			var muzzle: Vector3 = body.to_global(tip)
			var y: float = Look.HOOK_TARGET_HEIGHT if hs == "pull" else muzzle.y
			var parent: Node3D = get_parent_node_3d()
			var at := Vector3(float(r.get("hook_x")), y, float(r.get("hook_z")))
			hook_view.update(hs, muzzle, parent.to_global(at) if parent != null else at, _radius, delta)
		else:
			hook_view.update("", Vector3.ZERO, Vector3.ZERO, _radius, delta)
	label.text = r.name if r.say.is_empty() else "%s「%s」" % [r.name, r.say]


## 導火線が燃えている間の赤い点滅。最初はゆっくり、自爆の直前はとても速く点滅する
func _update_fuse_blink(fuse: float, fuse_total: float, delta: float) -> void:
	if fuse < 0.0:
		if blink_mat != null:
			_clear_blink()
		return
	if blink_mat == null:
		# 機体のすべての部品に、赤く光る重ね塗りをかける
		blink_mat = StandardMaterial3D.new()
		blink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		blink_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		blink_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blink_mat.albedo_color = Color(Look.SELF_DESTRUCT_COLOR, 0.0)
		_set_overlay(body, blink_mat)
		_blink_light = OmniLight3D.new()
		_blink_light.light_color = Look.SELF_DESTRUCT_COLOR
		_blink_light.omni_range = _size * 2.5
		_blink_light.position.y = _top * 0.7
		add_child(_blink_light)
		_blink_phase = 0.0
	var p: float = clampf(1.0 - fuse / maxf(0.001, fuse_total), 0.0, 1.0)
	var hz: float = lerpf(Look.SELF_DESTRUCT_BLINK_START_HZ, Look.SELF_DESTRUCT_BLINK_END_HZ, p * p)
	_blink_phase += hz * delta
	blink_on = fmod(_blink_phase, 1.0) < 0.5
	# 点いている間は強く赤く、自爆が近いほど消えている間も赤みが残る
	var a: float = (0.85 if blink_on else 0.12 * p)
	blink_mat.albedo_color = Color(Look.SELF_DESTRUCT_COLOR, a)
	_blink_light.light_energy = (Look.SELF_DESTRUCT_LIGHT * (0.6 + 0.6 * p)) if blink_on else 0.0


func _clear_blink() -> void:
	if blink_mat != null:
		_set_overlay(body, null)
		blink_mat = null
	if _blink_light != null:
		_blink_light.queue_free()
		_blink_light = null
	blink_on = false


func _set_overlay(n: Node, mat: Material) -> void:
	for c: Node in n.get_children():
		if c is MeshInstance3D and c.get_meta("debris", true):
			(c as MeshInstance3D).material_overlay = mat
		_set_overlay(c, mat)


## 自爆が届く範囲（m）。わからなければ機体の大きさの3倍
func _blast_range(r: Variant) -> float:
	for s: Variant in r.skills:
		if s.def.behavior == "self_destruct":
			return s.def.get_fixed("range") + _size
	return _size * 3.0


## 被弾した（arena_view が出来事から呼ぶ）。バリアを張っていれば、攻撃が来た向きに波紋を出す
func on_hit(from_world: Vector3) -> void:
	shield.hit(from_world)


## 頭上の文字を出す位置（3D）
func label_position() -> Vector3:
	return label.global_position


## フレームのモデルを置く。大きさをそろえ、前後左右の真ん中を機体の中心に、底を床に合わせる。
## モデルがなければ空の辞書。あれば大きさと、モデルの中の取り付け位置の目印（機体から見た位置）を返す
func _add_frame_model(fdef: GameData.PartDef, robot_radius: float, color: Color) -> Dictionary:
	var model: Node3D = PartModels.instantiate(fdef.model)
	if model == null:
		return {}
	var box: AABB = PartModels.bounds(model)
	var s: float = PartModels.fit_scale(box, robot_radius * 2.0 * Look.MODEL_FRAME_FOOTPRINT, Vector3(1, 0, 1))
	var c: Vector3 = box.get_center()
	var holder := Node3D.new()
	holder.scale = Vector3.ONE * s
	holder.position = Vector3(-c.x, -box.position.y, -c.z) * s
	holder.add_child(model)
	body.add_child(holder)
	PartModels.roughen(model, color)
	var mounts: Dictionary = {PartModels.MOUNT_WEAPON: [], PartModels.MOUNT_SKILL: []}
	for prefix: String in mounts:
		for t: Transform3D in PartModels.mounts(model, prefix):
			var m: Transform3D = holder.transform * t
			m.basis = m.basis.orthonormalized()  # 付けるパーツはフレームの倍率で伸ばさない
			mounts[prefix].append(m)
	return {"model": true, "length": box.size.x * s, "width": box.size.z * s, "top": box.size.y * s,
		"weapon_mounts": mounts[PartModels.MOUNT_WEAPON], "skill_mounts": mounts[PartModels.MOUNT_SKILL]}


## 仮の車体（くすんだ鉄板の箱と、下の黒いタイヤ）。重いフレームほど背が高い
func _add_frame_boxes(fdef: GameData.PartDef, robot_radius: float, color: Color) -> Dictionary:
	var mass: float = fdef.get_fixed("mass", 1.0)
	var length: float = robot_radius * 1.7
	var width: float = robot_radius * 1.4
	var height: float = 0.5 + 0.35 * mass
	_box(Vector3(length, height, width), Vector3(0, height * 0.5 + 0.15, 0), Grime.material(color, 0.6, 0.7, 0.9))
	var tire: StandardMaterial3D = Grime.material(Color(0.08, 0.08, 0.08), 0.0, 1.0, 1.5)
	for sx: float in [-0.32, 0.32]:
		for sz: float in [-0.5, 0.5]:
			_box(Vector3(0.5, 0.3, 0.2), Vector3(length * sx, 0.15, width * sz + sign(sz) * 0.1), tire)
	return {"model": false, "length": length, "width": width, "top": height + 0.15, "weapon_mounts": [], "skill_mounts": []}


## 武器やスキルのモデルを取り付け位置に付ける。モデルがなければ false。
## 武器はモデルの後ろの面を取り付け位置に当てて前（+X）へ伸ばし、スキル（on_top）は底を取り付け位置に乗せる
func _attach_model(path: String, mount: Transform3D, size: float, on_top: bool, color: Color) -> bool:
	var model: Node3D = PartModels.instantiate(path)
	if model == null:
		return false
	var box: AABB = PartModels.bounds(model)
	var s: float = PartModels.fit_scale(box, size)
	var c: Vector3 = box.get_center()
	var offset: Vector3 = Vector3(-c.x, -box.position.y, -c.z) if on_top else Vector3(-box.position.x, -c.y, -c.z)
	var holder := Node3D.new()
	holder.transform = mount
	var inner := Node3D.new()
	inner.scale = Vector3.ONE * s
	inner.position = offset * s
	inner.add_child(model)
	holder.add_child(inner)
	body.add_child(holder)
	PartModels.roughen(model, color)
	return true


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	body.add_child(m)
	return m
