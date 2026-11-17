# タイトル画面。左に題名と始めるボタン、右に遊び方を短く見せる。開発用の観戦画面へも行ける。
extends "res://view/screen_base.gd"

const HOW_TO_PLAY: Array[String] = [
	"最初に、フレーム・武器・スキルを1つずつ選ぶ",
	"手持ちのパーツで機体を組み、操縦士へのプロンプト（指示）を書く",
	"バトルは操縦士が自分で考えて戦う。あなたは見守るだけ",
	"負けると体力が減る。ラウンドごとにパーツとパークが増えるので、機体とプロンプトを直して挑む",
	"体力が0になったら脱落。6人のうち最後の1人になれば優勝",
]

var _brain: Label


func build_ui() -> void:
	var cols: Array[VBoxContainer] = add_columns(1.0)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]

	# 左：題名とボタン
	add_label(" ", 40, COL_DIM, left)
	add_label("プロンプトバトル", 56, COL_ACCENT, left)
	add_label("（仮）", 20, COL_DIM, left)
	add_label("パーツで機体を組み、プロンプトを書くと、操縦士が試合中に考えて戦う。", 18, COL_DIM, left)
	add_label(" ", 16, COL_DIM, left)
	var start_btn: Button = add_button("ひとりで遊ぶ（CPUと）", start, left)
	start_btn.custom_minimum_size = Vector2(320, 60)
	start_btn.add_theme_font_size_override("font_size", 24)
	start_btn.call_deferred("grab_focus")
	var online_btn: Button = add_button("オンラインで遊ぶ", open_online, left)
	online_btn.custom_minimum_size = Vector2(320, 48)
	add_label(" ", 8, COL_DIM, left)
	var debug_btn: Button = add_button("観戦画面（開発用）", open_debug_viewer, left)
	debug_btn.custom_minimum_size = Vector2(200, 34)
	debug_btn.add_theme_font_size_override("font_size", 15)
	debug_btn.add_theme_color_override("font_color", COL_DIM)
	add_label(" ", 8, COL_DIM, left)
	_brain = add_label("", 15, COL_DIM, left)

	# 右：遊び方の板
	add_label(" ", 40, COL_DIM, right)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Look.UI_PANEL
	style.border_color = Look.UI_BORDER
	style.set_border_width_all(1)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	right.add_child(panel)
	var how := VBoxContainer.new()
	how.add_theme_constant_override("separation", 10)
	panel.add_child(how)
	add_label("遊び方", 24, COL_ACCENT, how)
	for i: int in HOW_TO_PLAY.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		how.add_child(row)
		var num: Label = add_label("%d" % (i + 1), 22, COL_ACCENT, row)
		num.custom_minimum_size = Vector2(22, 0)
		var text: Label = add_label(HOW_TO_PLAY[i], 17, COL_TEXT, row)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _process(_delta: float) -> void:
	if _brain != null and main != null and main.agents != null:
		_brain.text = main.agents.brain_status_text()


func open_online() -> void:
	main.open_online()


func start() -> void:
	main.start_game()


func open_debug_viewer() -> void:
	get_tree().change_scene_to_file("res://view/debug/battle_viewer.tscn")
