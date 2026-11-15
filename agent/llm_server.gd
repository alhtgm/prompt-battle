# 本番の頭脳のサーバー（llama.cpp の llama-server）を裏で起動し、使えるようになったかを確かめ、終わるときに止める。
# 1つのサーバーを試合の間ずっと使い回す。ゲームを止めないよう、確認は update() を呼ぶたびに少しずつ進める。
extends RefCounted

const LlmConfig := preload("res://agent/llm_config.gd")
const HttpJob := preload("res://agent/http_job.gd")

enum Status { OFF, STARTING, READY, FAILED }

var config: LlmConfig
var status: Status = Status.OFF
var pid: int = -1
## 使えない理由（使えるなら空）
var problem: String = ""
## 先読みさせ終えた指示文（prewarm を参照）
var warmed_prompt: String = ""

var _health: HttpJob = null
var _warm: HttpJob = null
var _warm_text: String = ""
var _deadline_ms: int = 0


func _init(cfg: LlmConfig) -> void:
	config = cfg


## モデルの名前（画面の表示用）
func model_name() -> String:
	return config.model_path.get_file().get_basename()


func start() -> void:
	if status == Status.STARTING or status == Status.READY:
		return
	if not config.problem.is_empty():
		_set_failed(config.problem)
		return
	var args: PackedStringArray = [
		"-m", config.model_path,
		"--host", str(config.get_value("host")),
		"--port", str(int(config.get_value("port"))),
		"-c", str(int(config.get_value("ctx_size"))),
		"-np", "1",
	]
	if int(config.get_value("threads")) > 0:
		args.append_array(["-t", str(int(config.get_value("threads")))])
	pid = OS.create_process(config.server_path, args, false)
	if pid <= 0:
		_set_failed("llama-server を起動できない")
		return
	status = Status.STARTING
	_deadline_ms = Time.get_ticks_msec() + int(float(config.get_value("startup_timeout_sec")) * 1000.0)


## 起動の確認を少し進める。返すのは今の状態
func update() -> Status:
	if _warm != null and _warm.poll() != HttpJob.State.RUNNING:
		if _warm.state == HttpJob.State.DONE and _warm.status_code == 200:
			warmed_prompt = _warm_text
		_warm = null
	if status != Status.STARTING:
		return status
	if Time.get_ticks_msec() > _deadline_ms:
		_set_failed("llama-server が時間内に使えるようにならなかった")
		stop_process()
		return status
	if pid > 0 and not OS.is_process_running(pid):
		_set_failed("llama-server が途中で終わった（ポート %d が使用中の可能性）" % int(config.get_value("port")))
		return status
	if _health == null:
		_health = HttpJob.new()
		_health.start(str(config.get_value("host")), int(config.get_value("port")), HTTPClient.METHOD_GET, "/health", "", 1.0)
	match _health.poll():
		HttpJob.State.DONE:
			if _health.status_code == 200:
				status = Status.READY
			_health = null
		HttpJob.State.FAILED:
			_health = null  # まだ準備中。次の update でまた確かめる
	return status


func is_ready() -> bool:
	return update() == Status.READY


func is_failed() -> bool:
	return update() == Status.FAILED


## サーバーを止める（ゲームを終えるとき）
func stop() -> void:
	stop_process()
	status = Status.OFF


func stop_process() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1


## 指示文を先読みさせる：1トークンだけ答えさせ、その計算をサーバーに残させる。
## このモデル（Qwen3.5）は指示文がまるごと同じときだけ計算を使い回せるので、バトルで使う指示文そのものを渡す。
## 先読み中・同じ指示文を先読み済み・まだ使えないときは何もしない。先読みしたら true
func prewarm(system_prompt: String) -> bool:
	if update() != Status.READY or _warm != null or system_prompt == warmed_prompt or system_prompt.is_empty():
		return false
	_warm_text = system_prompt
	var payload: Dictionary = {
		"messages": [{"role": "system", "content": system_prompt}, {"role": "user", "content": "準備"}],
		"max_tokens": 1,
		"cache_prompt": true,
		"chat_template_kwargs": {"enable_thinking": false},
	}
	_warm = HttpJob.new()
	_warm.start(str(config.get_value("host")), int(config.get_value("port")), HTTPClient.METHOD_POST,
		"/v1/chat/completions", JSON.stringify(payload), float(config.get_value("startup_timeout_sec")))
	return true


func _set_failed(message: String) -> void:
	problem = message
	status = Status.FAILED
