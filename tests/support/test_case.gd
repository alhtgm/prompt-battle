# テストの土台。各テストファイルはこれを継承し、test_ で始まるメソッドを書く。
# check 系のメソッドで失敗を記録する（止まらずに最後まで調べる）。
extends RefCounted

var failures: PackedStringArray = PackedStringArray()


func check(cond: bool, message: String) -> void:
	if not cond:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if not same(actual, expected):
		failures.append("%s（期待 %s / 実際 %s）" % [message, str(expected), str(actual)])


## 配列や辞書も中身で比べる（JSON文字列にして比べる）
static func same(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)
