# 仮のパーツモデル（全23種）を、箱・円柱・角柱などを組み合わせて作り、assets/models/parts/ に .glb で書き出す。
# 本番のモデル（AIで下地を作り Blender で仕上げたもの）ができるまでのつなぎ。実行（プロジェクト直下で）：godot --headless --path . -s tools/make_placeholder_models.gd
extends SceneTree

const OUT_DIR: String = "res://assets/models/parts"
## 模様の画像の大きさ（小さいほど荒い）
const TEX_SIZE: int = 128

# ---- 材質の色（さびた鉄、くすんだ塗装、黒いゴム、光る部品） ----
const OLIVE := Color(0.45, 0.42, 0.3)
const RUST := Color(0.5, 0.32, 0.2)
const STEEL := Color(0.55, 0.55, 0.57)
const DARK := Color(0.2, 0.2, 0.21)
const RUBBER := Color(0.12, 0.12, 0.12)
const YELLOW := Color(0.62, 0.5, 0.15)
const RED := Color(0.5, 0.17, 0.12)
# 飾りの色（光る目と排気口の奥、毒々しい緑、ガラス、黒黄の縞）
const EYE := Color(0.9, 0.08, 0.03)
const EMBER := Color(1.0, 0.45, 0.1)
const TOXIC := Color(0.4, 1.0, 0.25)
const GLASS := Color(0.25, 0.4, 0.45)
const HAZ_Y := Color(0.75, 0.6, 0.12)
const HAZ_K := Color(0.08, 0.08, 0.08)

var _mats: Dictionary = {}
var _seed: int = 1
var _written: int = 0
var _mats_x: Dictionary = {}
var _seed_x: int = 500


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# フレーム
	_frame_light()
	_frame_standard()
	_frame_heavy()
	_frame_wedge()
	_frame_tank()
	_frame_spider()
	# 武器
	_weapon_drill()
	_weapon_saw()
	_weapon_hammer()
	_weapon_spike()
	_weapon_lifter()
	_weapon_bumper()
	_weapon_mg()
	_weapon_rocket()
	# スキル
	_skill_booster()
	_skill_shield()
	_skill_repair()
	_skill_shockwave()
	_skill_emp()
	_skill_overclock()
	_skill_self_destruct()
	# 後から足したもの（前のモデルの汚れの模様が変わらないよう、最後に作る）
	_weapon_harpoon()
	_weapon_flamethrower()
	print("書き出したモデル：%d 個（%s）" % [_written, OUT_DIR])
	quit()


# ---- 材質と形の部品 ----

## 汚れた材質：色むら（大きなノイズ）と、こすれ・さびの斑点（細かいノイズ）を焼き込んだ小さな画像
func _mat(col: Color, metal: float = 0.6, rough: float = 0.7, glow: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key: String = "%s/%.2f/%.2f/%s" % [col.to_html(), metal, rough, glow.to_html()]
	if _mats.has(key):
		return _mats[key]
	_seed += 1
	var m: StandardMaterial3D = _grime(col, metal, rough, _seed)
	if glow.a > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m


## 色むらと斑点を焼き込んだ画像の材質（seed で模様が決まる）
func _grime(col: Color, metal: float, rough: float, seed_no: int) -> StandardMaterial3D:
	var big := FastNoiseLite.new()
	big.seed = seed_no
	big.frequency = 0.03
	big.fractal_octaves = 4
	var small := FastNoiseLite.new()
	small.seed = seed_no * 7
	small.frequency = 0.25
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in TEX_SIZE:
		for x: int in TEX_SIZE:
			var v: float = 0.65 + 0.45 * big.get_noise_2d(x, y)
			var c: Color = col * v
			if small.get_noise_2d(x, y) > 0.45:  # 斑点：さびの色に寄せて暗く
				c = c.lerp(Color(0.25, 0.14, 0.08), 0.6)
			c.a = 1.0
			img.set_pixel(x, y, c)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = metal
	m.roughness = rough
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## 円柱（top を 0 にすると円すい）。sides は側面の数（少ないほど角ばる）
func _cyl(bottom: float, top: float, height: float, sides: int = 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = bottom
	c.top_radius = top
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	return c


## 三角柱。apex は頂点の位置（0 で左端、0.5 で真ん中、1 で右端）
func _prism(size: Vector3, apex: float = 0.5) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	p.left_to_right = apex
	return p


func _sphere(radius: float, sides: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = sides
	s.rings = maxi(3, sides / 2)
	return s


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 12
	t.ring_segments = 6
	return t


## 形を1つ置く。rot は度（円柱は縦向きなので、z を -90 にすると前 +X を向く）
func _add(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	root.add_child(mi)
	mi.owner = root


## 取り付け位置の目印（空のノード）
func _mount(root: Node3D, mount_name: String, pos: Vector3) -> void:
	var m := Node3D.new()
	m.name = mount_name
	m.position = pos
	root.add_child(m)
	m.owner = root


func _save(root: Node3D, file: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: int = doc.append_from_scene(root, state)
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT_DIR.path_join(file + ".glb")))
	if err == OK:
		_written += 1
	else:
		push_error("書き出せない：%s（%d）" % [file, err])
	root.free()


func _new(model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	return root


# ---- 飾りの部品（後から足したもの。前からある材質の汚れの模様を変えないよう、材質は _matx で別の種の列から作る） ----

## _mat と同じ作りの材質を、別の種の列で作る。energy は光る強さ
func _matx(col: Color, metal: float = 0.6, rough: float = 0.7, glow: Color = Color(0, 0, 0, 0), energy: float = 1.5) -> StandardMaterial3D:
	var key: String = "%s/%.2f/%.2f/%s/%.1f" % [col.to_html(), metal, rough, glow.to_html(), energy]
	if _mats_x.has(key):
		return _mats_x[key]
	_seed_x += 1
	var m: StandardMaterial3D = _grime(col, metal, rough, _seed_x)
	if glow.a > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = energy
	_mats_x[key] = m
	return m


## 形を1つ、parent の下に置く（root はモデルのいちばん上。書き出しに必要）
func _add_to(parent: Node3D, root: Node3D, mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mesh.surface_set_material(0, mat)
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	mi.owner = root


## 動かす節（空のノード）。名前が wheel_* なら車輪として回り、leg_* なら脚として振れる（view/arena/motion_fx_view.gd）
func _pivot(root: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pivot_name
	p.position = pos
	root.add_child(p)
	p.owner = root
	return p


## 回る車輪（左右に対で）。タイヤ・軸・回っているのが見える十字の板
func _wheel_set(root: Node3D, xs: Array, z: float, radius: float, width: float) -> void:
	var n: int = root.get_child_count()
	for x: float in xs:
		for sz: float in [-1.0, 1.0]:
			var w: Node3D = _pivot(root, "wheel_%d" % n, Vector3(x, radius, z * sz))
			n += 1
			_add_to(w, root, _cyl(radius, radius, width, 8), Vector3.ZERO, _mat(RUBBER, 0.0, 0.95), Vector3(90, 0, 0))
			_add_to(w, root, _cyl(radius * 0.45, radius * 0.45, width + 0.02, 6), Vector3.ZERO,
				_mat(STEEL, 0.8, 0.5), Vector3(90, 0, 0))
			_add_to(w, root, _box(Vector3(radius * 1.5, radius * 0.18, width + 0.04)), Vector3.ZERO, _matx(YELLOW, 0.5, 0.6))
			_add_to(w, root, _box(Vector3(radius * 0.18, radius * 1.5, width + 0.04)), Vector3.ZERO, _matx(YELLOW, 0.5, 0.6))


## 赤く光る目（細い板）
func _eye(root: Node3D, pos: Vector3, size: Vector3) -> void:
	_add(root, _box(size), pos, _matx(EYE, 0.0, 0.5, EYE, 1.0))


## 排気管：黒い管と縁、口の奥が赤く光る。tilt は後ろへ倒す角度（度）
func _exhaust(root: Node3D, pos: Vector3, radius: float, height: float, tilt: float) -> void:
	var rot := Vector3(0, 0, -tilt)
	var dir: Vector3 = Vector3.UP.rotated(Vector3(0, 0, 1), deg_to_rad(-tilt))
	_add(root, _cyl(radius, radius, height, 8), pos + dir * height * 0.5, _matx(DARK, 0.8, 0.45), rot)
	_add(root, _cyl(radius * 1.25, radius * 1.25, 0.06, 8), pos + dir * height, _matx(STEEL, 0.8, 0.45), rot)
	_add(root, _cyl(radius * 0.8, radius * 0.8, 0.03, 8), pos + dir * (height + 0.02), _matx(EMBER, 0.0, 0.6, EMBER, 2.5), rot)


## アンテナ：細い棒の先に赤い光
func _antenna(root: Node3D, pos: Vector3, height: float) -> void:
	_add(root, _cyl(0.025, 0.015, height, 4), pos + Vector3(0, height * 0.5, 0), _matx(DARK, 0.8, 0.45))
	_add(root, _sphere(0.06, 6), pos + Vector3(0, height, 0), _matx(EYE, 0.0, 0.5, EYE, 1.0))


## 鋲の列（from から to まで count 個）
func _rivets(root: Node3D, from: Vector3, to: Vector3, count: int, mat: Material) -> void:
	for k: int in count:
		_add(root, _sphere(0.045, 4), from.lerp(to, float(k) / maxf(1.0, count - 1.0)), mat)


## 黒と黄の斜めの縞の帯。横の面（z 向きの面）に置く。front なら前後の面（x 向きの面）に置く
func _hazard(root: Node3D, center: Vector3, length: float, height: float, count: int, front: bool = false) -> void:
	var step: float = length / float(count)
	for k: int in count:
		var off: float = -length * 0.5 + step * (k + 0.5)
		var mat: StandardMaterial3D = _matx(HAZ_Y, 0.3, 0.7) if k % 2 == 0 else _matx(HAZ_K, 0.3, 0.7)
		if front:
			_add(root, _box(Vector3(0.03, height, step)), center + Vector3(0, 0, off), mat, Vector3(30, 0, 0))
		else:
			_add(root, _box(Vector3(step, height, 0.03)), center + Vector3(off, 0, 0), mat, Vector3(0, 0, 30))


# ---- フレーム（前 +X、上 +Y。武器の目印は前の面、スキルの目印は上） ----

## 軽量：低く薄い車台にむき出しの車輪と転倒よけの枠。前に光る目、後ろに羽根と2本の排気管。武器1・スキル2
func _frame_light() -> void:
	var r: Node3D = _new("frame_light")
	var body: StandardMaterial3D = _mat(YELLOW, 0.5, 0.6)
	_add(r, _box(Vector3(2.4, 0.25, 1.1)), Vector3(0, 0.45, 0), body)
	_add(r, _prism(Vector3(0.5, 0.25, 1.1), 0.0), Vector3(1.45, 0.45, 0), body)
	_wheel_set(r, [-0.8, 0.8], 0.75, 0.32, 0.22)
	var bar: StandardMaterial3D = _mat(DARK, 0.8, 0.5)
	for z: float in [-0.45, 0.45]:
		_add(r, _box(Vector3(0.08, 0.6, 0.08)), Vector3(-0.3, 0.85, z), bar)
	_add(r, _box(Vector3(0.08, 0.08, 0.98)), Vector3(-0.3, 1.15, 0), bar)
	# 飾り：転倒よけの斜めの支え、前の押し出し棒、光る目、操縦席、後ろの羽根、排気管、黒黄の縞
	for z: float in [-0.45, 0.45]:
		_add(r, _box(Vector3(0.07, 0.07, 0.75)), Vector3(-0.6, 0.85, z), bar, Vector3(0, 90, 40))
	_add(r, _box(Vector3(0.08, 0.08, 1.0)), Vector3(1.62, 0.36, 0), _matx(STEEL, 0.8, 0.45))
	_eye(r, Vector3(1.2, 0.6, 0), Vector3(0.12, 0.06, 0.7))
	_add(r, _box(Vector3(0.6, 0.25, 0.55)), Vector3(0.2, 0.68, 0), _matx(DARK, 0.7, 0.5))
	_add(r, _box(Vector3(0.05, 0.2, 0.5)), Vector3(0.5, 0.75, 0), _matx(GLASS, 0.2, 0.3), Vector3(0, 0, 30))
	for z: float in [-0.35, 0.35]:
		_add(r, _box(Vector3(0.06, 0.35, 0.06)), Vector3(-1.1, 0.75, z), bar)
	_add(r, _box(Vector3(0.35, 0.05, 1.1)), Vector3(-1.12, 0.95, 0), _matx(RED, 0.5, 0.6), Vector3(0, 0, -8))
	for z: float in [-0.25, 0.25]:
		_exhaust(r, Vector3(-1.15, 0.5, z), 0.06, 0.35, -60.0)
	_hazard(r, Vector3(0.0, 0.45, 0.56), 1.6, 0.18, 6)
	_mount(r, "weapon_0", Vector3(1.7, 0.45, 0))
	_mount(r, "skill_0", Vector3(-0.8, 0.58, -0.3))
	_mount(r, "skill_1", Vector3(-0.8, 0.58, 0.3))
	_mount(r, "lamp_0", Vector3(1.25, 0.62, -0.42))
	_mount(r, "lamp_1", Vector3(1.25, 0.62, 0.42))
	_save(r, "frame_light")


## 標準：箱の車体に傾いた前の装甲板、4輪。横の装甲板と鋲、赤く光る細い目、屋根のハッチ、2本の排気管、アンテナ。武器2・スキル1
func _frame_standard() -> void:
	var r: Node3D = _new("frame_standard")
	var body: StandardMaterial3D = _mat(RUST, 0.6, 0.65)
	_add(r, _box(Vector3(2.4, 0.7, 1.5)), Vector3(-0.1, 0.75, 0), body)
	_add(r, _box(Vector3(0.12, 0.6, 1.5)), Vector3(1.15, 0.7, 0), _mat(DARK, 0.8, 0.5), Vector3(0, 0, 25))
	_add(r, _box(Vector3(0.9, 0.2, 1.0)), Vector3(-0.5, 1.2, 0), body)
	_wheel_set(r, [-0.85, 0.75], 0.85, 0.35, 0.25)
	var plate: StandardMaterial3D = _matx(Color(0.32, 0.3, 0.28), 0.7, 0.55)
	var rivet: StandardMaterial3D = _matx(STEEL, 0.9, 0.4)
	for z: float in [-1.0, 1.0]:
		_add(r, _box(Vector3(1.2, 0.4, 0.06)), Vector3(-0.1, 0.85, z * 0.78), plate)
		_rivets(r, Vector3(-0.6, 1.0, z * 0.82), Vector3(0.4, 1.0, z * 0.82), 5, rivet)
		_rivets(r, Vector3(-0.6, 0.7, z * 0.82), Vector3(0.4, 0.7, z * 0.82), 5, rivet)
	_eye(r, Vector3(1.24, 0.92, 0), Vector3(0.06, 0.07, 0.9))
	_add(r, _cyl(0.22, 0.22, 0.1, 8), Vector3(-0.5, 1.35, 0.15), _matx(DARK, 0.7, 0.5))
	_add(r, _box(Vector3(0.1, 0.08, 0.3)), Vector3(-0.32, 1.42, 0.15), rivet)
	for z: float in [-0.5, 0.5]:
		_exhaust(r, Vector3(-1.2, 1.0, z), 0.08, 0.55, 0.0)
	_antenna(r, Vector3(-1.0, 1.1, -0.55), 0.9)
	_hazard(r, Vector3(-1.32, 0.6, 0.0), 1.2, 0.16, 6, true)
	_mount(r, "weapon_0", Vector3(1.25, 0.6, -0.4))
	_mount(r, "weapon_1", Vector3(1.25, 0.6, 0.4))
	_mount(r, "skill_0", Vector3(-0.5, 1.3, 0))
	_mount(r, "lamp_0", Vector3(1.24, 1.02, -0.6))
	_mount(r, "lamp_1", Vector3(1.24, 1.02, 0.6))
	_save(r, "frame_standard")


## 重装甲：分厚い車体、横の装甲スカート、鋲。光る排気口、背の2本の煙突、のぞき窓、前の縞。武器2・スキル1
func _frame_heavy() -> void:
	var r: Node3D = _new("frame_heavy")
	var armor: StandardMaterial3D = _mat(Color(0.35, 0.36, 0.38), 0.7, 0.6)
	_add(r, _box(Vector3(2.6, 1.1, 1.8)), Vector3(0, 0.85, 0), armor)
	_add(r, _prism(Vector3(0.6, 1.1, 1.8), 0.0), Vector3(1.6, 0.85, 0), armor)
	for z: float in [-1.0, 1.0]:
		_add(r, _box(Vector3(2.8, 0.7, 0.15)), Vector3(0, 0.5, z), _mat(DARK, 0.7, 0.6))
		for x: float in [-1.0, -0.3, 0.4, 1.1]:
			_add(r, _sphere(0.06, 4), Vector3(x, 0.7, z * 1.08), _mat(STEEL, 0.9, 0.4))
	_add(r, _box(Vector3(1.0, 0.35, 1.2)), Vector3(-0.6, 1.55, 0), armor)
	# 飾り：横の光る排気口（格子）、背の煙突、のぞき窓、前の縞、上の手すり
	var dark: StandardMaterial3D = _matx(DARK, 0.7, 0.5)
	for z: float in [-1.0, 1.0]:
		_add(r, _box(Vector3(0.7, 0.22, 0.04)), Vector3(-0.6, 1.1, z * 0.91), _matx(EMBER, 0.0, 0.6, EMBER, 2.0))
		for k: int in 4:
			_add(r, _box(Vector3(0.04, 0.24, 0.06)), Vector3(-0.88 + k * 0.18, 1.1, z * 0.92), dark)
	for z: float in [-0.4, 0.4]:
		_exhaust(r, Vector3(-1.15, 1.4, z), 0.1, 0.75, 0.0)
	_eye(r, Vector3(-0.08, 1.6, 0), Vector3(0.05, 0.08, 0.8))
	_hazard(r, Vector3(1.38, 0.5, 0.0), 1.7, 0.18, 8, true)
	for z: float in [-0.5, 0.5]:
		_add(r, _box(Vector3(0.9, 0.05, 0.05)), Vector3(-0.6, 1.8, z), dark)
	_antenna(r, Vector3(-1.1, 1.7, 0.7), 0.8)
	_mount(r, "weapon_0", Vector3(1.75, 0.7, -0.45))
	_mount(r, "weapon_1", Vector3(1.75, 0.7, 0.45))
	_mount(r, "skill_0", Vector3(-0.6, 1.72, 0))
	_mount(r, "lamp_0", Vector3(1.28, 1.42, -0.72))
	_mount(r, "lamp_1", Vector3(1.28, 1.42, 0.72))
	_save(r, "frame_heavy")


## くさび型：前に向かって低くなる三角の車体。背びれ2枚、後ろの光る噴射口、横の縞、斜面の光る線。武器1・スキル1
func _frame_wedge() -> void:
	var r: Node3D = _new("frame_wedge")
	var body: StandardMaterial3D = _mat(RED, 0.5, 0.65)
	_add(r, _prism(Vector3(2.8, 0.9, 1.6), 0.0), Vector3(0, 0.55, 0), body)
	_add(r, _box(Vector3(2.8, 0.15, 1.6)), Vector3(0, 0.1, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _box(Vector3(0.15, 0.4, 1.0)), Vector3(-1.3, 1.0, 0), _mat(DARK, 0.7, 0.6))
	_wheel_set(r, [-0.9], 0.85, 0.3, 0.22)
	# 飾り：背びれ、噴射口（中が光る）、斜面に沿った光る線、横の縞、前の刃
	var dark: StandardMaterial3D = _matx(DARK, 0.7, 0.5)
	for z: float in [-0.55, 0.55]:
		_add(r, _prism(Vector3(0.6, 0.5, 0.06), 1.0), Vector3(-1.05, 1.15, z), dark)
	for z: float in [-0.3, 0.3]:
		_add(r, _cyl(0.13, 0.16, 0.25, 8), Vector3(-1.45, 0.45, z), dark, Vector3(0, 0, 90))
		_add(r, _cyl(0.1, 0.1, 0.05, 8), Vector3(-1.58, 0.45, z), _matx(EMBER, 0.0, 0.6, EMBER, 2.5), Vector3(0, 0, 90))
	for z: float in [-0.79, 0.79]:
		_add(r, _box(Vector3(2.6, 0.04, 0.04)), Vector3(0.05, 0.58, z), _matx(EYE, 0.0, 0.5, EYE, 2.0), Vector3(0, 0, -17))
	_hazard(r, Vector3(-0.2, 0.18, 0.81), 2.0, 0.12, 8)
	_add(r, _box(Vector3(0.25, 0.04, 1.5)), Vector3(1.38, 0.12, 0), _matx(STEEL, 0.9, 0.35))
	_mount(r, "weapon_0", Vector3(1.4, 0.25, 0))
	_mount(r, "skill_0", Vector3(-1.0, 1.0, 0))
	_mount(r, "lamp_0", Vector3(1.15, 0.32, -0.6))
	_mount(r, "lamp_1", Vector3(1.15, 0.32, 0.6))
	_save(r, "frame_wedge")


## 戦車：車体と砲塔、左右のキャタピラ（転輪が回る）。車長のハッチ、のぞき窓、アンテナ、後ろの排気管、横の鋲。武器3・スキル0
func _frame_tank() -> void:
	var r: Node3D = _new("frame_tank")
	var hull: StandardMaterial3D = _mat(OLIVE, 0.7, 0.6)
	var track: StandardMaterial3D = _mat(RUBBER, 0.0, 0.95)
	_add(r, _box(Vector3(6, 1.4, 3)), Vector3(0, 1.3, 0), hull)
	_add(r, _box(Vector3(3, 0.8, 2.2)), Vector3(-0.6, 2.4, 0), hull)
	var n: int = 0
	for z: float in [-1.8, 1.8]:
		_add(r, _box(Vector3(6.4, 1.2, 0.7)), Vector3(0, 0.6, z), track)
		for x: float in [-2.4, -1.2, 0.0, 1.2, 2.4]:  # 転輪（回る）
			var w: Node3D = _pivot(r, "wheel_%d" % n, Vector3(x, 0.55, z))
			n += 1
			_add_to(w, r, _cyl(0.4, 0.4, 0.75, 8), Vector3.ZERO, _mat(DARK, 0.6, 0.7), Vector3(90, 0, 0))
			_add_to(w, r, _box(Vector3(0.62, 0.1, 0.78)), Vector3.ZERO, _matx(STEEL, 0.8, 0.45))
	# 飾り：キャタピラの歯、車長のハッチ、のぞき窓、アンテナ、排気管、横の鋲、前の縞
	var dark: StandardMaterial3D = _matx(DARK, 0.7, 0.5)
	var rivet: StandardMaterial3D = _matx(STEEL, 0.9, 0.4)
	for z: float in [-1.8, 1.8]:
		for k: int in 12:
			_add(r, _box(Vector3(0.18, 0.1, 0.74)), Vector3(-2.9 + k * 0.53, 1.22, z), dark)
	_add(r, _cyl(0.45, 0.5, 0.35, 8), Vector3(-1.2, 3.0, -0.5), hull)
	_add(r, _cyl(0.42, 0.42, 0.08, 8), Vector3(-1.2, 3.2, -0.5), dark)
	_eye(r, Vector3(0.92, 2.5, 0), Vector3(0.05, 0.12, 1.4))
	_eye(r, Vector3(-0.78, 3.1, -0.5), Vector3(0.05, 0.08, 0.4))
	_antenna(r, Vector3(-1.9, 2.8, 0.8), 1.8)
	for z: float in [-0.8, 0.8]:
		_exhaust(r, Vector3(-3.0, 1.6, z), 0.16, 0.9, 0.0)
	for z: float in [-1.51, 1.51]:
		_rivets(r, Vector3(-2.6, 1.85, z), Vector3(2.6, 1.85, z), 9, rivet)
	_hazard(r, Vector3(3.01, 0.9, 0.0), 2.6, 0.25, 10, true)
	_mount(r, "weapon_0", Vector3(3.0, 1.3, 0))
	_mount(r, "weapon_1", Vector3(3.0, 1.3, 1.1))
	_mount(r, "weapon_2", Vector3(3.0, 1.3, -1.1))
	_mount(r, "lamp_0", Vector3(3.02, 1.8, -1.2))
	_mount(r, "lamp_1", Vector3(3.02, 1.8, 1.2))
	_save(r, "frame_tank")


## 多脚：丸い胴体に6本の脚（付け根で振れる）。前の顔に赤く光る目が6つ、背の光る腹、触角。武器2・スキル2
func _frame_spider() -> void:
	var r: Node3D = _new("frame_spider")
	var body: StandardMaterial3D = _mat(Color(0.3, 0.33, 0.3), 0.6, 0.6)
	var leg: StandardMaterial3D = _mat(DARK, 0.8, 0.55)
	_add(r, _sphere(0.8, 8), Vector3(0, 1.0, 0), body)
	_add(r, _box(Vector3(0.7, 0.35, 0.9)), Vector3(0.75, 0.95, 0), body)
	var n: int = 0
	for x: float in [-0.6, 0.0, 0.6]:
		for sz: float in [-1.0, 1.0]:
			# 付け根から外へ上がる節と、地面へ下りる節（付け根を中心に振れる）
			var p: Node3D = _pivot(r, "leg_%d" % n, Vector3(x, 1.15, sz * 0.4))
			n += 1
			_add_to(p, r, _box(Vector3(0.12, 0.12, 0.9)), Vector3(0, 0, sz * 0.35), leg, Vector3(sz * 25, 0, 0))
			_add_to(p, r, _box(Vector3(0.1, 1.1, 0.1)), Vector3(0, -0.55, sz * 0.85), leg, Vector3(sz * -15, 0, 0))
			_add_to(p, r, _sphere(0.09, 6), Vector3(0, 0.1, sz * 0.72), _matx(STEEL, 0.9, 0.4))
	# 飾り：目（前の顔に6つ）、背の光る腹、触角、胴の帯
	for k: int in 3:
		for sz: float in [-1.0, 1.0]:
			_add(r, _sphere(0.07 - k * 0.012, 6), Vector3(1.11, 1.05 - k * 0.08, sz * (0.12 + k * 0.1)), _matx(EYE, 0.0, 0.5, EYE, 1.0))
	_add(r, _sphere(0.42, 8), Vector3(-0.75, 1.25, 0), _matx(Color(0.22, 0.24, 0.22), 0.6, 0.6))
	_add(r, _box(Vector3(0.5, 0.06, 0.25)), Vector3(-0.8, 1.62, 0), _matx(TOXIC, 0.0, 0.6, TOXIC, 2.0))
	for sz: float in [-1.0, 1.0]:
		_add(r, _cyl(0.02, 0.01, 0.6, 4), Vector3(1.15, 1.35, sz * 0.25), leg, Vector3(sz * 20, 0, -45))
	_add(r, _torus(0.78, 0.84), Vector3(0, 1.0, 0), _matx(STEEL, 0.8, 0.5))
	_mount(r, "weapon_0", Vector3(1.1, 0.95, -0.3))
	_mount(r, "weapon_1", Vector3(1.1, 0.95, 0.3))
	_mount(r, "skill_0", Vector3(-0.2, 1.75, -0.25))
	_mount(r, "skill_1", Vector3(-0.2, 1.75, 0.25))
	_mount(r, "lamp_0", Vector3(1.11, 0.84, -0.32))
	_mount(r, "lamp_1", Vector3(1.11, 0.84, 0.32))
	_save(r, "frame_spider")


# ---- 武器（根元が原点、前 +X へ伸びる） ----

## ドリル：段々に細くなる円すいの刃と、後ろのモーター
func _weapon_drill() -> void:
	var r: Node3D = _new("weapon_drill")
	var bit: StandardMaterial3D = _mat(STEEL, 0.9, 0.45)
	_add(r, _box(Vector3(0.4, 0.4, 0.4)), Vector3(0.2, 0, 0), _mat(YELLOW, 0.5, 0.6))
	_add(r, _cyl(0.22, 0.16, 0.35, 8), Vector3(0.58, 0, 0), bit, Vector3(0, 0, -90))
	_add(r, _cyl(0.16, 0.1, 0.35, 8), Vector3(0.9, 0, 0), bit, Vector3(0, 45, -90))
	_add(r, _cyl(0.1, 0.0, 0.4, 8), Vector3(1.25, 0, 0), bit, Vector3(0, 0, -90))
	_save(r, "weapon_drill")


## 丸ノコ：縦に立てた円盤とまわりの歯、それを支える腕
func _weapon_saw() -> void:
	var r: Node3D = _new("weapon_saw")
	var blade: StandardMaterial3D = _mat(STEEL, 0.9, 0.4)
	_add(r, _box(Vector3(0.7, 0.12, 0.12)), Vector3(0.35, 0, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _cyl(0.5, 0.5, 0.05, 16), Vector3(0.9, 0, 0), blade, Vector3(90, 0, 0))
	for i: int in 12:
		var a: float = TAU * i / 12.0
		_add(r, _box(Vector3(0.1, 0.1, 0.05)), Vector3(0.9 + cos(a) * 0.53, sin(a) * 0.53, 0), blade, Vector3(0, 0, rad_to_deg(a) + 45))
	_add(r, _cyl(0.1, 0.1, 0.12, 6), Vector3(0.9, 0, 0), _mat(YELLOW, 0.5, 0.6), Vector3(90, 0, 0))
	_save(r, "weapon_saw")


## ハンマー：長い柄と、先の重い頭
func _weapon_hammer() -> void:
	var r: Node3D = _new("weapon_hammer")
	_add(r, _box(Vector3(0.3, 0.3, 0.3)), Vector3(0.15, 0, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _box(Vector3(1.0, 0.1, 0.1)), Vector3(0.75, 0.1, 0), _mat(STEEL, 0.8, 0.5))
	_add(r, _box(Vector3(0.35, 0.5, 0.4)), Vector3(1.3, 0.1, 0), _mat(Color(0.3, 0.3, 0.32), 0.8, 0.55))
	_add(r, _box(Vector3(0.1, 0.55, 0.45)), Vector3(1.5, 0.1, 0), _mat(RUST, 0.7, 0.6))
	_save(r, "weapon_hammer")


## スパイク：鋲を打った板から突き出す3本のとげ（真ん中が長い）
func _weapon_spike() -> void:
	var r: Node3D = _new("weapon_spike")
	var spike: StandardMaterial3D = _mat(STEEL, 0.9, 0.4)
	_add(r, _box(Vector3(0.15, 0.55, 0.7)), Vector3(0.07, 0, 0), _mat(RUST, 0.7, 0.6))
	for z: float in [-0.22, 0.0, 0.22]:
		var length: float = 0.9 if z == 0.0 else 0.6
		_add(r, _cyl(0.11, 0.0, length, 6), Vector3(0.15 + length * 0.5, 0, z), spike, Vector3(0, 0, -90))
	for y: float in [-0.2, 0.2]:
		for z: float in [-0.28, 0.28]:
			_add(r, _sphere(0.04, 4), Vector3(0.16, y, z), _mat(DARK, 0.9, 0.5))
	_save(r, "weapon_spike")


## リフター：前に向かって薄くなる板と、根元の太い蝶番
func _weapon_lifter() -> void:
	var r: Node3D = _new("weapon_lifter")
	_add(r, _cyl(0.12, 0.12, 0.8, 8), Vector3(0.12, 0, 0), _mat(DARK, 0.8, 0.5), Vector3(90, 0, 0))
	_add(r, _prism(Vector3(1.0, 0.25, 0.8), 0.0), Vector3(0.65, -0.05, 0), _mat(YELLOW, 0.6, 0.6))
	_add(r, _box(Vector3(0.6, 0.06, 0.06)), Vector3(0.4, 0.15, 0), _mat(STEEL, 0.8, 0.5), Vector3(0, 0, -15))
	_save(r, "weapon_lifter")


## バンパー：横に広い衝角と、それを支える2本の柱
func _weapon_bumper() -> void:
	var r: Node3D = _new("weapon_bumper")
	var frame: StandardMaterial3D = _mat(DARK, 0.7, 0.6)
	for z: float in [-0.3, 0.3]:
		_add(r, _box(Vector3(0.4, 0.12, 0.12)), Vector3(0.2, 0, z), frame)
	_add(r, _box(Vector3(0.2, 0.4, 1.2)), Vector3(0.5, 0, 0), _mat(RUBBER, 0.0, 0.95))
	for z: float in [-0.65, 0.65]:
		_add(r, _box(Vector3(0.15, 0.4, 0.3)), Vector3(0.45, 0, z), _mat(RUBBER, 0.0, 0.95), Vector3(0, z * 50, 0))
	_save(r, "weapon_bumper")


## 機関銃：機関部の箱、2本の銃身、横の弾倉
func _weapon_mg() -> void:
	var r: Node3D = _new("weapon_mg")
	var gun: StandardMaterial3D = _mat(DARK, 0.8, 0.5)
	_add(r, _box(Vector3(0.5, 0.3, 0.35)), Vector3(0.25, 0, 0), gun)
	for z: float in [-0.08, 0.08]:
		_add(r, _cyl(0.05, 0.05, 0.9, 6), Vector3(0.95, 0.05, z), _mat(STEEL, 0.9, 0.45), Vector3(0, 0, -90))
	_add(r, _box(Vector3(0.3, 0.25, 0.15)), Vector3(0.25, -0.05, 0.25), _mat(OLIVE, 0.4, 0.7))
	_save(r, "weapon_mg")


## ロケット：4本の発射筒を束ねた箱と、のぞく弾頭
func _weapon_rocket() -> void:
	var r: Node3D = _new("weapon_rocket")
	_add(r, _box(Vector3(0.9, 0.55, 0.55)), Vector3(0.45, 0, 0), _mat(OLIVE, 0.5, 0.65))
	for y: float in [-0.13, 0.13]:
		for z: float in [-0.13, 0.13]:
			_add(r, _cyl(0.1, 0.1, 0.2, 8), Vector3(0.95, y, z), _mat(DARK, 0.7, 0.6), Vector3(0, 0, -90))
			_add(r, _cyl(0.07, 0.0, 0.15, 6), Vector3(1.1, y, z), _mat(RED, 0.4, 0.6), Vector3(0, 0, -90))
	_save(r, "weapon_rocket")


# ---- スキル（底が原点、上 +Y へ伸びる。光る部品で何のスキルか分かるように） ----

## ブースター：後ろ向きの2本の噴射口（中が橙に光る）
func _skill_booster() -> void:
	var r: Node3D = _new("skill_booster")
	_add(r, _box(Vector3(0.4, 0.15, 0.5)), Vector3(0, 0.07, 0), _mat(DARK, 0.7, 0.6))
	for z: float in [-0.13, 0.13]:
		_add(r, _cyl(0.1, 0.15, 0.45, 8), Vector3(-0.05, 0.28, z), _mat(STEEL, 0.8, 0.5), Vector3(0, 0, 90))
		_add(r, _cyl(0.09, 0.09, 0.02, 8), Vector3(-0.29, 0.28, z), _mat(DARK, 0.0, 1.0, Color(1.0, 0.5, 0.1)),
			Vector3(0, 0, 90))
	_save(r, "skill_booster")


## シールド：柱の上の発生器（青く光る丸い板）
func _skill_shield() -> void:
	var r: Node3D = _new("skill_shield")
	_add(r, _cyl(0.06, 0.06, 0.4, 6), Vector3(0, 0.2, 0), _mat(DARK, 0.8, 0.5))
	_add(r, _cyl(0.28, 0.18, 0.08, 10), Vector3(0, 0.44, 0), _mat(STEEL, 0.7, 0.5))
	_add(r, _cyl(0.2, 0.2, 0.03, 10), Vector3(0, 0.5, 0), _mat(DARK, 0.0, 1.0, Color(0.3, 0.6, 1.0)))
	_save(r, "skill_shield")


## 応急修理：工具箱と、緑に光る十字
func _skill_repair() -> void:
	var r: Node3D = _new("skill_repair")
	var glow: StandardMaterial3D = _mat(DARK, 0.0, 1.0, Color(0.3, 1.0, 0.4))
	_add(r, _box(Vector3(0.5, 0.3, 0.4)), Vector3(0, 0.15, 0), _mat(Color(0.75, 0.72, 0.65), 0.3, 0.7))
	_add(r, _box(Vector3(0.3, 0.04, 0.08)), Vector3(0, 0.32, 0), glow)
	_add(r, _box(Vector3(0.08, 0.04, 0.3)), Vector3(0, 0.32, 0), glow)
	_save(r, "skill_repair")


## 衝撃波：積み重ねた3つの輪（コイル）と、光る芯
func _skill_shockwave() -> void:
	var r: Node3D = _new("skill_shockwave")
	_add(r, _cyl(0.07, 0.07, 0.55, 6), Vector3(0, 0.28, 0), _mat(DARK, 0.0, 1.0, Color(1.0, 0.85, 0.3)))
	for i: int in 3:
		_add(r, _torus(0.12, 0.24 - i * 0.03), Vector3(0, 0.1 + i * 0.18, 0), _mat(Color(0.6, 0.4, 0.2), 0.9, 0.45))
	_save(r, "skill_shockwave")


## EMP：細いアンテナと、先の光る玉
func _skill_emp() -> void:
	var r: Node3D = _new("skill_emp")
	_add(r, _box(Vector3(0.3, 0.12, 0.3)), Vector3(0, 0.06, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _cyl(0.03, 0.02, 0.6, 5), Vector3(0, 0.4, 0), _mat(STEEL, 0.8, 0.5))
	_add(r, _sphere(0.1, 8), Vector3(0, 0.75, 0), _mat(DARK, 0.0, 1.0, Color(0.5, 0.8, 1.0)))
	_save(r, "skill_emp")


## オーバークロック：放熱のひれを並べた箱（赤く光る）
func _skill_overclock() -> void:
	var r: Node3D = _new("skill_overclock")
	_add(r, _box(Vector3(0.45, 0.15, 0.4)), Vector3(0, 0.07, 0), _mat(DARK, 0.7, 0.6))
	for i: int in 5:
		_add(r, _box(Vector3(0.04, 0.3, 0.38)), Vector3(-0.16 + i * 0.08, 0.3, 0), _mat(STEEL, 0.8, 0.5))
	_add(r, _box(Vector3(0.4, 0.03, 0.05)), Vector3(0, 0.17, 0.21), _mat(DARK, 0.0, 1.0, Color(1.0, 0.25, 0.15)))
	_save(r, "skill_overclock")


## 自爆装置：赤い筒に黄色と黒の警告の帯、上に赤く光る警告灯
func _skill_self_destruct() -> void:
	var r: Node3D = _new("skill_self_destruct")
	_add(r, _box(Vector3(0.45, 0.1, 0.45)), Vector3(0, 0.05, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _cyl(0.18, 0.18, 0.45, 10), Vector3(0, 0.32, 0), _mat(RED, 0.5, 0.6))
	for k: int in 3:
		var stripe: Color = YELLOW if k % 2 == 0 else Color(0.08, 0.08, 0.08)
		_add(r, _cyl(0.19, 0.19, 0.05, 10), Vector3(0, 0.16 + k * 0.05, 0), _mat(stripe, 0.3, 0.7))
	_add(r, _cyl(0.06, 0.06, 0.06, 6), Vector3(0, 0.58, 0), _mat(DARK, 0.8, 0.5))
	_add(r, _sphere(0.07, 6), Vector3(0, 0.64, 0), _mat(DARK, 0.0, 1.0, Color(1.0, 0.15, 0.1)))
	_save(r, "skill_self_destruct")


## ハープーンガン：機関部と太い銃身、横に鎖を巻いた巻き取り機、銃口に装填された返しつきの釣り針（先が熱で赤い）
func _weapon_harpoon() -> void:
	var r: Node3D = _new("weapon_harpoon")
	var body: StandardMaterial3D = _mat(Color(0.28, 0.3, 0.27), 0.7, 0.6)
	var steel: StandardMaterial3D = _mat(STEEL, 0.9, 0.45)
	var hot: StandardMaterial3D = _mat(RED, 0.2, 0.6, Color(1.0, 0.35, 0.1))
	# 機関部と、上の照準の出っぱり
	_add(r, _box(Vector3(0.6, 0.34, 0.32)), Vector3(0.3, 0, 0), body)
	_add(r, _box(Vector3(0.3, 0.1, 0.1)), Vector3(0.35, 0.22, 0), _mat(DARK, 0.7, 0.6))
	# 太い銃身と、先の補強の輪
	_add(r, _cyl(0.1, 0.1, 0.95, 8), Vector3(1.05, 0.02, 0), steel, Vector3(0, 0, -90))
	for x: float in [0.75, 1.15, 1.5]:
		_add(r, _cyl(0.13, 0.13, 0.06, 8), Vector3(x, 0.02, 0), _mat(DARK, 0.8, 0.5), Vector3(0, 0, -90))
	# 横の巻き取り機：黄色い枠と、鎖を巻いた太鼓
	_add(r, _box(Vector3(0.36, 0.3, 0.06)), Vector3(0.45, -0.02, 0.22), _mat(YELLOW, 0.5, 0.6))
	_add(r, _cyl(0.13, 0.13, 0.16, 10), Vector3(0.45, -0.02, 0.3), _mat(DARK, 0.8, 0.5), Vector3(90, 0, 0))
	for k: int in 3:
		_add(r, _torus(0.1, 0.15), Vector3(0.45, -0.02, 0.25 + k * 0.05), steel, Vector3(90, 0, 0))
	# 装填された釣り針：軸、3本の返し、赤く光る先
	_add(r, _cyl(0.04, 0.04, 0.3, 6), Vector3(1.65, 0.02, 0), steel, Vector3(0, 0, -90))
	for k: int in 3:
		var a: float = TAU * k / 3.0
		_add(r, _box(Vector3(0.2, 0.04, 0.04)), Vector3(1.78, 0.02 + cos(a) * 0.09, sin(a) * 0.09), steel,
			Vector3(rad_to_deg(a), 0, 25))
	_add(r, _cyl(0.07, 0.0, 0.22, 6), Vector3(1.9, 0.02, 0), hot, Vector3(0, 0, -90))
	_save(r, "weapon_harpoon")


## 火炎放射器：本物の作りにならう。後ろに燃料タンク2本（くすんだ緑に黄色い帯）と、その間の赤い圧力タンク、
## タンクからホースで銃身へ。銃身には放熱の輪、先は少し広がったノズルで、下に点火器（青い種火の光）
func _weapon_flamethrower() -> void:
	var r: Node3D = _new("weapon_flamethrower")
	var tank: StandardMaterial3D = _mat(OLIVE, 0.5, 0.65)
	var band: StandardMaterial3D = _mat(YELLOW, 0.4, 0.6)
	var steel: StandardMaterial3D = _mat(DARK, 0.85, 0.5)
	var hose: StandardMaterial3D = _mat(RUBBER, 0.0, 0.95)
	# 燃料タンク2本（寝かせて前後向き）と、黄色い帯
	for z: float in [-0.13, 0.13]:
		_add(r, _cyl(0.11, 0.11, 0.55, 10), Vector3(0.3, 0.0, z), tank, Vector3(0, 0, -90))
		_add(r, _sphere(0.11, 8), Vector3(0.03, 0.0, z), tank)
		_add(r, _sphere(0.11, 8), Vector3(0.57, 0.0, z), tank)
		for x: float in [0.18, 0.42]:
			_add(r, _cyl(0.115, 0.115, 0.04, 10), Vector3(x, 0.0, z), band, Vector3(0, 0, -90))
	# 間の小さな圧力タンク（赤）と、上のバルブ
	_add(r, _cyl(0.07, 0.07, 0.4, 8), Vector3(0.3, 0.13, 0), _mat(RED, 0.5, 0.6), Vector3(0, 0, -90))
	_add(r, _cyl(0.025, 0.025, 0.08, 6), Vector3(0.45, 0.22, 0), steel)
	# ホース：タンクの前から銃身の根元へ
	for z: float in [-0.13, 0.13]:
		_add(r, _cyl(0.03, 0.03, 0.22, 6), Vector3(0.7, 0.03, z * 0.6), hose, Vector3(0, z * 120.0, -80))
	# 銃身と放熱の輪、広がったノズル
	_add(r, _box(Vector3(0.2, 0.16, 0.18)), Vector3(0.82, 0.04, 0), steel)
	_add(r, _cyl(0.05, 0.05, 0.75, 8), Vector3(1.28, 0.06, 0), steel, Vector3(0, 0, -90))
	for x: float in [1.05, 1.15, 1.25, 1.35, 1.45]:
		_add(r, _cyl(0.08, 0.08, 0.03, 8), Vector3(x, 0.06, 0), _mat(Color(0.35, 0.33, 0.3), 0.8, 0.5), Vector3(0, 0, -90))
	_add(r, _cyl(0.06, 0.09, 0.12, 8), Vector3(1.7, 0.06, 0), steel, Vector3(0, 0, -90))
	# ノズルの下の点火器（小さな箱と、青く光る種火の口）
	_add(r, _box(Vector3(0.12, 0.06, 0.07)), Vector3(1.62, -0.03, 0), _mat(Color(0.5, 0.42, 0.2), 0.7, 0.5))
	_add(r, _sphere(0.025, 4), Vector3(1.69, -0.03, 0), _mat(DARK, 0.0, 1.0, Color(0.3, 0.5, 1.0)))
	_save(r, "weapon_flamethrower")

