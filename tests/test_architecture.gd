# 設計上のルールを守っているかの検査。core/ と agent/ がシーンやノード、全体の乱数を使っていないかを調べる。
extends "res://tests/support/test_case.gd"

const PURE_DIRS: Array[String] = ["res://core", "res://agent"]

## 乱数の入口。ここだけは乱数まわりの検査から外す（同じ名前のメソッドを定義しているため）
const RNG_FILE: String = "res://core/rng.gd"

## [正規表現, 説明, 乱数まわりの検査か]
const FORBIDDEN: Array = [
	["get_tree\\s*\\(", "get_tree() を使っている", false],
	["\\bInput\\s*\\.", "Input を使っている", false],
	["get_node\\s*\\(", "ノードを参照している", false],
	["extends\\s+(Node|Node2D|Node3D|Control)\\b", "ノードを継承している", false],
	["(?<![\\w.])randomize\\s*\\(", "randomize() を使っている", true],
	["(?<![\\w.])randf\\s*\\(", "全体の randf() を使っている（core/rng.gd を通す）", true],
	["(?<![\\w.])randi\\s*\\(", "全体の randi() を使っている（core/rng.gd を通す）", true],
	["(?<![\\w.])randf_range\\s*\\(", "全体の randf_range() を使っている", true],
	["(?<![\\w.])randi_range\\s*\\(", "全体の randi_range() を使っている", true],
	["\\.shuffle\\s*\\(\\s*\\)", "Array.shuffle() を使っている（全体の乱数を使うため）", true],
	["\\.pick_random\\s*\\(", "pick_random() を使っている（全体の乱数を使うため）", true],
]


func _collect(dir: String, out: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(sub), out)


## コメント部分を取り除く（文字列中の # は今のところ想定しない）
static func _strip_comment(line: String) -> String:
	var i: int = line.find("#")
	return line if i < 0 else line.substr(0, i)


func test_core_and_agent_do_not_depend_on_scenes_or_global_random() -> void:
	var files: Array[String] = []
	for d: String in PURE_DIRS:
		_collect(d, files)
	check(not files.is_empty(), "検査するスクリプトがある")

	var patterns: Array = []
	for entry: Array in FORBIDDEN:
		var re := RegEx.new()
		check(re.compile(entry[0]) == OK, "正規表現が正しい：%s" % entry[0])
		patterns.append([re, entry[1], entry[2]])

	for path: String in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			var code: String = _strip_comment(lines[i])
			for p: Array in patterns:
				if p[2] and path == RNG_FILE:
					continue
				var re: RegEx = p[0]
				if re.search(code) != null:
					check(false, "%s:%d %s" % [path, i + 1, p[1]])


func test_core_does_not_depend_on_agent() -> void:
	# 頭脳とCPUの判断は外から渡す。core/ が agent/ を読み込むと差し替えられなくなる
	var files: Array[String] = []
	_collect("res://core", files)
	for path: String in files:
		var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
		for i: int in lines.size():
			if _strip_comment(lines[i]).contains("res://agent/"):
				check(false, "%s:%d core/ から agent/ を読み込んでいる" % [path, i + 1])


func test_each_script_has_header_comment() -> void:
	var files: Array[String] = []
	for d: String in PURE_DIRS + ["res://tests"]:
		_collect(d, files)
	for path: String in files:
		var first: String = FileAccess.get_file_as_string(path).get_slice("\n", 0)
		check(first.begins_with("#"), "%s の先頭に役割のコメントがある" % path)
