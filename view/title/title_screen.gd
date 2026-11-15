# タイトル画面。試合を始めるか、開発用の観戦画面を開く。
extends "res://view/screen_base.gd"


func build_ui() -> void:
	add_title("プロンプトバトル（仮）")
	add_label("パーツで機体を組み、プロンプトを書くと、操縦士が試合中に考えて戦う。6人で最後の1人を目指す。", 18, COL_DIM)
	add_label(" ")
	add_button("はじめる", start)
	add_button("観戦画面（開発用）", open_debug_viewer)


func start() -> void:
	main.start_game()


func open_debug_viewer() -> void:
	get_tree().change_scene_to_file("res://view/debug/battle_viewer.tscn")
