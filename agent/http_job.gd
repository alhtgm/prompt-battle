# PC内のサーバーへのHTTPの問い合わせを1つ、待たずに進める。poll() を呼ぶたびに少しずつ進み、終わったら結果を持つ。
# ゲームを止めないために使う（HTTPClient を自分で回す。ノードには依存しない）。
extends RefCounted

enum State { RUNNING, DONE, FAILED }

var state: State = State.RUNNING
var status_code: int = 0
var body: PackedByteArray = PackedByteArray()
var error: String = ""
## 始めてから終わるまでの実時間（ミリ秒）
var elapsed_ms: int = 0

var _http: HTTPClient = HTTPClient.new()
var _method: HTTPClient.Method = HTTPClient.METHOD_GET
var _path: String = ""
var _payload: String = ""
var _sent: bool = false
var _start_ms: int = 0
var _deadline_ms: int = 0


func start(host: String, port: int, method: HTTPClient.Method, path: String, payload: String, timeout_sec: float) -> void:
	_method = method
	_path = path
	_payload = payload
	_start_ms = Time.get_ticks_msec()
	_deadline_ms = _start_ms + int(timeout_sec * 1000.0)
	var err: Error = _http.connect_to_host(host, port)
	if err != OK:
		_fail("接続を始められない（%d）" % err)


func text() -> String:
	return body.get_string_from_utf8()


func is_running() -> bool:
	return state == State.RUNNING


## 少し進める。返すのは今の状態
func poll() -> State:
	if state != State.RUNNING:
		return state
	if Time.get_ticks_msec() > _deadline_ms:
		_fail("時間切れ")
		return state
	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			pass
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				var headers: PackedStringArray = ["Content-Type: application/json"]
				var err: Error = _http.request(_method, _path, headers, _payload)
				if err != OK:
					_fail("送れない（%d）" % err)
				_sent = true
			elif _http.has_response():
				_finish()
		HTTPClient.STATUS_BODY:
			status_code = _http.get_response_code()
			body.append_array(_http.read_response_body_chunk())
		HTTPClient.STATUS_DISCONNECTED:
			if _sent and _http.has_response():
				_finish()
			else:
				_fail("接続が切れた")
		_:
			_fail("つながらない（状態 %d）" % _http.get_status())
	return state


func cancel() -> void:
	if state == State.RUNNING:
		_fail("取り消し")


func _finish() -> void:
	status_code = _http.get_response_code()
	elapsed_ms = Time.get_ticks_msec() - _start_ms
	state = State.DONE
	_http.close()


func _fail(message: String) -> void:
	error = message
	elapsed_ms = Time.get_ticks_msec() - _start_ms
	state = State.FAILED
	_http.close()
