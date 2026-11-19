# 本番の頭脳の設定（data/llm.json）を読み、サーバーとモデルの場所を探す。ノードには依存しない。
extends RefCounted

const PATH: String = "res://data/llm.json"
const LOCAL_PATH: String = "res://data/llm.local.json"

var values: Dictionary = {}
## 見つかったサーバーとモデルの絶対パス（見つからなければ空）
var server_path: String = ""
var model_path: String = ""
## 使えない理由（使えるなら空）
var problem: String = ""


## 設定を読み、場所を探す。override で一部の値を差し替えられる（測定ツールでモデルを替えるときなど）
func load_config(override: Dictionary = {}) -> bool:
	var text: String = FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		problem = "data/llm.json が読めない"
		return false
	values = parsed
	# 自分のPCだけの差し替え（Git に入れない）。測定ツールなどの override のほうが強い
	var local: Variant = JSON.parse_string(FileAccess.get_file_as_string(LOCAL_PATH)) \
		if FileAccess.file_exists(LOCAL_PATH) else null
	if local is Dictionary:
		values.merge(local, true)
	values.merge(override, true)
	for key: String in ["search_dirs", "server_exe", "model", "host", "port", "ctx_size", "threads",
			"temperature", "max_tokens", "say_max_chars", "startup_timeout_sec", "request_timeout_sec",
			"obs_style", "say_first", "describe"]:
		if not values.has(key):
			problem = "data/llm.json に %s がない" % key
			return false
	if not bool(values.get("enabled", true)):
		problem = "data/llm.json で無効になっている"
		return false
	if is_external():
		return true  # 起動はしない。host:port で動いているサーバーにつなぐだけ
	for dir: String in values["search_dirs"]:
		var base: String = resolve_dir(dir)
		var exe: String = base.path_join(str(values["server_exe"]))
		var model: String = base.path_join(str(values["model"]))
		if server_path.is_empty() and FileAccess.file_exists(exe):
			server_path = exe
		if model_path.is_empty() and FileAccess.file_exists(model):
			model_path = model
	if server_path.is_empty():
		problem = "llama-server が見つからない（tools/fetch_llm.ps1 で取れる）"
	elif model_path.is_empty():
		problem = "モデル %s が見つからない（tools/fetch_llm.ps1 で取れる）" % values["model"]
	return problem.is_empty()


func get_value(key: String) -> Variant:
	return values[key]


## 自分で起動せず、すでに動いている同じ形のサーバーにつなぐか（開発中に別のLLMを試すとき）
func is_external() -> bool:
	return bool(values.get("external_server", false))


## "~/x" はユーザーフォルダから、相対パスはプロジェクトのフォルダから
static func resolve_dir(dir: String) -> String:
	if dir.begins_with("~/"):
		var home: String = OS.get_environment("USERPROFILE")
		if home.is_empty():
			home = OS.get_environment("HOME")
		return home.path_join(dir.substr(2))
	if dir.is_absolute_path():
		return dir
	return ProjectSettings.globalize_path("res://").path_join(dir)
