# 自動テストの入口。tests/ にある test_*.gd を順に実行し、失敗があれば終了コード 1 で終わる。
# 実行：godot --headless --path . -s tests/run_all.gd
# 一部だけ：godot --headless --path . -s tests/run_all.gd -- --only=test_match（ファイル名に含む文字で絞る）
extends SceneTree

const TEST_DIR: String = "res://tests"


## テスト中に出たエンジンのエラー（スクリプトの実行時エラーなど）を数える
class ErrorCounter extends Logger:
	var count: int = 0
	var last: String = ""
	var _mutex: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		count += 1
		last = "%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function]
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## シーンツリーが動き始めてからテストを始める（画面のテストが await でフレームを待てるように）
func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)

	var only: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(TEST_DIR):
		if f.begins_with("test_") and f.ends_with(".gd") and (only.is_empty() or f.contains(only)):
			files.append(f)
	files.sort()

	var passed: int = 0
	var failed: int = 0
	var start_ms: int = Time.get_ticks_msec()

	for f: String in files:
		var path: String = TEST_DIR.path_join(f)
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("[失敗] %s：読み込めない" % path)
			failed += 1
			continue
		var suite: RefCounted = script.new()
		for m: Dictionary in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures = PackedStringArray()
			var errors_before: int = counter.count
			var t0: int = Time.get_ticks_msec()
			await suite.call(name)  # await でフレームを待つテストも、待たないテストも同じに扱う
			var ms: int = Time.get_ticks_msec() - t0
			var fails: PackedStringArray = suite.failures
			if counter.count > errors_before:
				fails.append("実行中にエラー：%s" % counter.last)
			if fails.is_empty():
				passed += 1
				print("[成功] %s :: %s (%d ms)" % [f, name, ms])
			else:
				failed += 1
				print("[失敗] %s :: %s" % [f, name])
				for msg: String in fails:
					print("    - %s" % msg)

	print("")
	print("結果：成功 %d / 失敗 %d（%d ms）" % [passed, failed, Time.get_ticks_msec() - start_ms])
	OS.remove_logger(counter)
	quit(1 if failed > 0 or passed == 0 else 0)
