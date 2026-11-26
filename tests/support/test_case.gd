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


## 出撃のシャッター（view/main.gd）が開ききるまで待つ。シャッターが動いていなければ1フレームだけ待つ（最大 limit_sec 秒）
func wait_sortie(main: Node, limit_sec: float = 10.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	var until: int = Time.get_ticks_msec() + int(limit_sec * 1000.0)
	while main.sortie_active and Time.get_ticks_msec() < until:
		await tree.process_frame
