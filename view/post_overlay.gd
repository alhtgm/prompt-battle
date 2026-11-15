# 画面効果を重ねる板。これより先（下）に描かれたものに、ざらつき・ディザ・周辺の暗さをかける。操作の邪魔はしない。
extends ColorRect

const SHADER := preload("res://view/shaders/post_grime.gdshader")


## params は view/look.gd の ARENA_POST か SCREEN_POST
func setup(params: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	material = mat
