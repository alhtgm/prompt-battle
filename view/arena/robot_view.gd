# 3Dのアリーナに置く機体1体の見た目（骨組みでは箱）。バトルの機体の状態を読んで、位置・向き・転倒・落下・一言を映す。
# 計算上の (x, z) をそのまま3Dの (x, z) に置く。計算上の向き th（+x から +z へ回る）は rotation.y = -th になる。
extends Node3D

const GameData := preload("res://core/game_data.gd")
const Grime := preload("res://view/grime.gd")

## 武器とスキルの目印の色（動き方ごと）
const WEAPON_COLORS: Dictionary = {
	"grind": Color(0.62, 0.62, 0.6), "strike": Color(0.4, 0.4, 0.42), "lift": Color(0.7, 0.55, 0.12),
	"ram": Color(0.35, 0.34, 0.33), "shoot": Color(0.18, 0.18, 0.2),
}
const SKILL_COLOR := Color(0.4, 0.95, 1.0)
## ひっくり返る・戻る・落ちる速さ（見た目だけの値）
const FLIP_SPEED: float = 10.0
const FALL_SPEED: float = 6.0

var body: Node3D
var label: Label3D
var aura: MeshInstance3D
var _fell_time: float = 0.0
var _roll: float = 0.0


## 機体の形を作る。build は Build、color は陣営の地の色、glow は陣営の光る目印の色、
## label_lift は頭上の文字を上げる量（2機の文字が重ならないように）
func setup(data: GameData, build: Variant, robot_radius: float, color: Color, glow: Color, label_lift: float = 0.0) -> void:
	var fdef: GameData.PartDef = data.get_part(build.frame.def_id)
	var mass: float = fdef.get_fixed("mass", 1.0)
	var length: float = robot_radius * 1.7
	var width: float = robot_radius * 1.4
	var height: float = 0.5 + 0.35 * mass
	body = Node3D.new()
	add_child(body)
	# 車体（くすんだ鉄板）と、下の黒いタイヤ
	_box(Vector3(length, height, width), Vector3(0, height * 0.5 + 0.15, 0), Grime.material(color, 0.6, 0.7, 0.9))
	var tire: StandardMaterial3D = Grime.material(Color(0.08, 0.08, 0.08), 0.0, 1.0, 1.5)
	for sx: float in [-0.32, 0.32]:
		for sz: float in [-0.5, 0.5]:
			_box(Vector3(0.5, 0.3, 0.2), Vector3(length * sx, 0.15, width * sz + sign(sz) * 0.1), tire)
	# 前の目印（陣営の色で光る帯）
	_box(Vector3(0.08, 0.14, width * 0.8), Vector3(length * 0.5 + 0.02, height * 0.7 + 0.15, 0),
		Grime.material(glow, 0.0, 0.5, 1.0, glow))
	# 武器：前に並べる。撃つ武器は上に砲身
	var n: int = build.weapons.size()
	for i: int in n:
		var wdef: GameData.PartDef = data.get_part(build.weapons[i].def_id)
		var mat: StandardMaterial3D = Grime.material(WEAPON_COLORS.get(wdef.behavior, Color.GRAY), 0.8, 0.55, 1.2)
		var side: float = (float(i) - (n - 1) * 0.5) * (width / maxf(1.0, n)) * 0.9
		if wdef.behavior == "shoot":
			_box(Vector3(1.2, 0.18, 0.18), Vector3(length * 0.35, height + 0.35, side), mat)
		else:
			_box(Vector3(0.6, 0.3, width / maxf(1.0, n) * 0.7), Vector3(length * 0.5 + 0.45, 0.4, side), mat)
	# スキル：上にアンテナ（先が光る）
	for i: int in build.skills.size():
		_box(Vector3(0.1, 0.6, 0.1), Vector3(-length * 0.3, height + 0.45, (i - 0.5) * 0.5),
			Grime.material(Color(0.2, 0.2, 0.2), 0.8, 0.6, 1.0))
		_box(Vector3(0.16, 0.12, 0.16), Vector3(-length * 0.3, height + 0.8, (i - 0.5) * 0.5),
			Grime.material(SKILL_COLOR, 0.0, 0.5, 1.0, SKILL_COLOR))
	# スキルが効いている間の光
	aura = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = robot_radius * 1.3
	sphere.height = robot_radius * 2.0
	aura.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(SKILL_COLOR, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura.material_override = mat
	aura.position.y = height * 0.5
	aura.visible = false
	add_child(aura)
	# 頭上の名前と一言（いつもカメラを向く）
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, height + 1.4 + label_lift, 0)
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
	var target_roll: float = PI if r.stun > 0.0 else 0.0
	_roll = move_toward(_roll, target_roll, FLIP_SPEED * delta)
	body.rotation.x = _roll
	# 穴に落ちたら沈んで小さくなる
	if r.fell:
		_fell_time += delta
		position.y = -FALL_SPEED * _fell_time * _fell_time
		scale = Vector3.ONE * maxf(0.05, 1.0 - _fell_time * 0.8)
	var active: bool = false
	for s: Variant in r.skills:
		active = active or s.active_t > 0.0
	aura.visible = active and not r.fell
	label.text = r.name if r.say.is_empty() else "%s「%s」" % [r.name, r.say]


## 頭上の文字を出す位置（3D）
func label_position() -> Vector3:
	return label.global_position


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	body.add_child(m)
	return m
