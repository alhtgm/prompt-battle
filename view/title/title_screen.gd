# タイトル画面。遊び方を短く見せ、試合を始めるか、開発用の観戦画面を開く。
extends "res://view/screen_base.gd"

const HOW_TO_PLAY: Array[String] = [
	"1. 最初に、フレーム・武器・スキルを1つずつ選ぶ",
	"2. 手持ちのパーツで機体を組み、操縦士へのプロンプト（指示）を書く",
	"3. バトルは操縦士が自分で考えて戦う。あなたは見守るだけ",
	"4. 負けると体力が減る。ラウンドごとにパーツとパークが増えるので、機体とプロンプトを直して挑む",
	"5. 体力が0になったら脱落。6人のうち最後の1人になれば優勝",
]


func build_ui() -> void:
	add_title("プロンプトバトル（仮）")
	add_label("パーツで機体を組み、プロンプトを書くと、操縦士が試合中に考えて戦う。", 18, COL_DIM)
	add_label(" ", 8)
	add_label("遊び方", 22, COL_ACCENT)
	for line: String in HOW_TO_PLAY:
		add_label(line, 18)
	add_label(" ", 8)
	add_button("はじめる（ひとりでCPUと）", start)
	add_button("オンラインで遊ぶ", open_online)
	add_button("観戦画面（開発用）", open_debug_viewer)


func open_online() -> void:
	main.open_online()


func start() -> void:
	main.start_game()


func open_debug_viewer() -> void:
	get_tree().change_scene_to_file("res://view/debug/battle_viewer.tscn")
