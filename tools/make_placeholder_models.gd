# 仮のパーツモデル（全20種）を、箱・円柱・角柱などを組み合わせて作り、assets/models/parts/ に .glb で書き出す。
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

var _mats: Dictionary = {}
var _seed: int = 1
var _written: int = 0


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
	print("書き出したモデル：%d 個（%s）" % [_written, OUT_DIR])
	quit()


# ---- 材質と形の部品 ----

## 汚れた材質：色むら（大きなノイズ）と、こすれ・さびの斑点（細かいノイズ）を焼き込んだ小さな画像
func _mat(col: Color, metal: float = 0.6, rough: float = 0.7, glow: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var key: String = "%s/%.2f/%.2f/%s" % [col.to_html(), metal, rough, glow.to_html()]
	if _mats.has(key):
		return _mats[key]
	_seed += 1
	var big := FastNoiseLite.new()
	big.seed = _seed
	big.frequency = 0.03
	big.fractal_octaves = 4
	var small := FastNoiseLite.new()
	small.seed = _seed * 7
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
	if glow.a > 0.0:
		m.emission_enabled = true
		m.emission = glow
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
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


## 4つの車輪（横向きの円柱）
func _wheels(root: Node3D, xs: Array, z: float, radius: float, width: float) -> void:
	for x: float in xs:
		for sz: float in [-1.0, 1.0]:
			_add(root, _cyl(radius, radius, width, 8), Vector3(x, radius, z * sz), _mat(RUBBER, 0.0, 0.95), Vector3(90, 0, 0))
			_add(root, _cyl(radius * 0.45, radius * 0.45, width + 0.02, 6), Vector3(x, radius, z * sz),
				_mat(STEEL, 0.8, 0.5), Vector3(90, 0, 0))


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


# ---- フレーム（前 +X、上 +Y。武器の目印は前の面、スキルの目印は上） ----

## 軽量：低く薄い車台にむき出しの車輪と転倒よけの枠。武器1・スキル2
func _frame_light() -> void:
	var r: Node3D = _new("frame_light")
	var body: StandardMaterial3D = _mat(YELLOW, 0.5, 0.6)
	_add(r, _box(Vector3(2.4, 0.25, 1.1)), Vector3(0, 0.45, 0), body)
	_add(r, _prism(Vector3(0.5, 0.25, 1.1), 0.0), Vector3(1.45, 0.45, 0), body)
	_wheels(r, [-0.8, 0.8], 0.75, 0.32, 0.22)
	var bar: StandardMaterial3D = _mat(DARK, 0.8, 0.5)
	for z: float in [-0.45, 0.45]:
		_add(r, _box(Vector3(0.08, 0.6, 0.08)), Vector3(-0.3, 0.85, z), bar)
	_add(r, _box(Vector3(0.08, 0.08, 0.98)), Vector3(-0.3, 1.15, 0), bar)
	_mount(r, "weapon_0", Vector3(1.7, 0.45, 0))
	_mount(r, "skill_0", Vector3(-0.8, 0.58, -0.3))
	_mount(r, "skill_1", Vector3(-0.8, 0.58, 0.3))
	_save(r, "frame_light")


## 標準：箱の車体に傾いた前の装甲板、4輪。武器2・スキル1
func _frame_standard() -> void:
	var r: Node3D = _new("frame_standard")
	var body: StandardMaterial3D = _mat(RUST, 0.6, 0.65)
	_add(r, _box(Vector3(2.4, 0.7, 1.5)), Vector3(-0.1, 0.75, 0), body)
	_add(r, _box(Vector3(0.12, 0.6, 1.5)), Vector3(1.15, 0.7, 0), _mat(DARK, 0.8, 0.5), Vector3(0, 0, 25))
	_add(r, _box(Vector3(0.9, 0.2, 1.0)), Vector3(-0.5, 1.2, 0), body)
	_wheels(r, [-0.85, 0.75], 0.85, 0.35, 0.25)
	_mount(r, "weapon_0", Vector3(1.25, 0.6, -0.4))
	_mount(r, "weapon_1", Vector3(1.25, 0.6, 0.4))
	_mount(r, "skill_0", Vector3(-0.5, 1.3, 0))
	_save(r, "frame_standard")


## 重装甲：分厚い車体、横の装甲スカート、鋲。武器2・スキル1
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
	_mount(r, "weapon_0", Vector3(1.75, 0.7, -0.45))
	_mount(r, "weapon_1", Vector3(1.75, 0.7, 0.45))
	_mount(r, "skill_0", Vector3(-0.6, 1.72, 0))
	_save(r, "frame_heavy")


## くさび型：前に向かって低くなる三角の車体。武器1・スキル1
func _frame_wedge() -> void:
	var r: Node3D = _new("frame_wedge")
	var body: StandardMaterial3D = _mat(RED, 0.5, 0.65)
	_add(r, _prism(Vector3(2.8, 0.9, 1.6), 0.0), Vector3(0, 0.55, 0), body)
	_add(r, _box(Vector3(2.8, 0.15, 1.6)), Vector3(0, 0.1, 0), _mat(DARK, 0.7, 0.6))
	_add(r, _box(Vector3(0.15, 0.4, 1.0)), Vector3(-1.3, 1.0, 0), _mat(DARK, 0.7, 0.6))
	_wheels(r, [-0.9], 0.85, 0.3, 0.22)
	_mount(r, "weapon_0", Vector3(1.4, 0.25, 0))
	_mount(r, "skill_0", Vector3(-1.0, 1.0, 0))
	_save(r, "frame_wedge")


## 戦車：車体と砲塔、左右のキャタピラ。武器3・スキル0
func _frame_tank() -> void:
	var r: Node3D = _new("frame_tank")
	var hull: StandardMaterial3D = _mat(OLIVE, 0.7, 0.6)
	var track: StandardMaterial3D = _mat(RUBBER, 0.0, 0.95)
	_add(r, _box(Vector3(6, 1.4, 3)), Vector3(0, 1.3, 0), hull)
	_add(r, _box(Vector3(3, 0.8, 2.2)), Vector3(-0.6, 2.4, 0), hull)
	for z: float in [-1.8, 1.8]:
		_add(r, _box(Vector3(6.4, 1.2, 0.7)), Vector3(0, 0.6, z), track)
		for x: float in [-2.4, -1.2, 0.0, 1.2, 2.4]:  # 転輪
			_add(r, _cyl(0.4, 0.4, 0.75, 8), Vector3(x, 0.55, z), _mat(DARK, 0.6, 0.7), Vector3(90, 0, 0))
	_mount(r, "weapon_0", Vector3(3.0, 1.3, 0))
	_mount(r, "weapon_1", Vector3(3.0, 1.3, 1.1))
	_mount(r, "weapon_2", Vector3(3.0, 1.3, -1.1))
	_save(r, "frame_tank")


## 多脚：丸い胴体に6本の脚（付け根と先の2節）。武器2・スキル2
func _frame_spider() -> void:
	var r: Node3D = _new("frame_spider")
	var body: StandardMaterial3D = _mat(Color(0.3, 0.33, 0.3), 0.6, 0.6)
	var leg: StandardMaterial3D = _mat(DARK, 0.8, 0.55)
	_add(r, _sphere(0.8, 8), Vector3(0, 1.0, 0), body)
	_add(r, _box(Vector3(0.7, 0.35, 0.9)), Vector3(0.75, 0.95, 0), body)
	for x: float in [-0.6, 0.0, 0.6]:
		for sz: float in [-1.0, 1.0]:
			# 付け根から外へ上がる節と、地面へ下りる節
			_add(r, _box(Vector3(0.12, 0.12, 0.9)), Vector3(x, 1.15, sz * 0.75), leg, Vector3(sz * 25, 0, 0))
			_add(r, _box(Vector3(0.1, 1.1, 0.1)), Vector3(x, 0.6, sz * 1.25), leg, Vector3(sz * -15, 0, 0))
	_mount(r, "weapon_0", Vector3(1.1, 0.95, -0.3))
	_mount(r, "weapon_1", Vector3(1.1, 0.95, 0.3))
	_mount(r, "skill_0", Vector3(-0.2, 1.75, -0.25))
	_mount(r, "skill_1", Vector3(-0.2, 1.75, 0.25))
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
