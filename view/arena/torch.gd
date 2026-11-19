# 松明1本（アリーナの壁の外に立てる）。鉄の柱と受け皿、揺れる火、オレンジの光、ときどき上がる火の粉。
# 揺れは時間の関数（松明ごとに位相をずらす）で、乱数は使わない。影は付けない（古いPCで重いため）。値は view/look.gd。
extends Node3D

const Look := preload("res://view/look.gd")
const Grime := preload("res://view/grime.gd")

var light: OmniLight3D
var flame: MeshInstance3D
## 揺れの位相（松明ごとに違う値を渡し、全部が同時に揺れないようにする）
var phase: float = 0.0


func setup(phase_offset: float) -> void:
	phase = phase_offset
	var h: float = Look.TORCH_HEIGHT
	var iron: StandardMaterial3D = Grime.material(Color(0.16, 0.15, 0.14), 0.7, 0.7, 1.5)
	_box(Vector3(0.6, 0.15, 0.6), Vector3(0, 0.075, 0), iron)  # 台
	_box(Vector3(0.14, h, 0.14), Vector3(0, h * 0.5, 0), iron)  # 柱
	var bowl := MeshInstance3D.new()  # 受け皿（下すぼまり）
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.16
	cyl.height = 0.25
	cyl.radial_segments = 8
	bowl.mesh = cyl
	bowl.material_override = iron
	bowl.position = Vector3(0, h + 0.1, 0)
	add_child(bowl)
	# 火：光る縦長の玉（光の当たり方に関係なく明るく見える）
	flame = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.55
	sphere.radial_segments = 8
	sphere.rings = 4
	flame.mesh = sphere
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Look.TORCH_FLAME_COLOR
	fm.emission_enabled = true
	fm.emission = Look.TORCH_FLAME_COLOR
	fm.emission_energy_multiplier = 2.5
	flame.material_override = fm
	flame.position = Vector3(0, h + 0.42, 0)
	add_child(flame)
	# 光：火の少し上から、周りをほんのり照らす
	light = OmniLight3D.new()
	light.position = Vector3(0, h + 0.6, 0)
	light.light_color = Look.TORCH_LIGHT_COLOR
	light.light_energy = Look.TORCH_ENERGY
	light.omni_range = Look.TORCH_RANGE
	light.omni_attenuation = Look.TORCH_ATTENUATION
	light.shadow_enabled = false
	add_child(light)
	_add_embers(h + 0.5)
	flicker(0.0)


## 火を揺らす（明るさと火の形）。t は経過秒数
func flicker(t: float) -> void:
	var x: float = t + phase
	# 速さの違う揺れを重ねて、規則正しく見えないようにする（-1〜1）
	var n: float = sin(x * 7.3) * 0.5 + sin(x * 13.1 + 1.7) * 0.3 + sin(x * 23.7 + 0.4) * 0.2
	light.light_energy = Look.TORCH_ENERGY * (1.0 + Look.TORCH_FLICKER * n)
	flame.scale = Vector3(1.0 - 0.08 * n, 1.0 + 0.18 * n, 1.0 - 0.08 * n)


## ときどき上がる火の粉
func _add_embers(y: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = Look.TORCH_EMBERS
	p.lifetime = 1.4
	p.position = Vector3(0, y, 0)
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, 0.4, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = m
	p.mesh = mesh
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.35, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	p.color_ramp = g
	add_child(p)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
