# 画面の切り替え役。試合（MatchSession）の今の段階を読み、対応する画面を出す。
# 試合の状態は読むだけで、操作は MatchSession のメソッドだけを通す。プレイヤーが脱落したら、組み立てとパーク選びを飛ばして観戦を続ける。
# 組み立てからバトルへは出撃のシャッター（view/shutter.gd）を通す。閉じている間に画面を切り替え、開ききったらバトルを進める。
extends Control

const GameData := preload("res://core/game_data.gd")
const MatchSession := preload("res://core/match_session.gd")
const DefaultAgents := preload("res://agent/default_agents.gd")
const TitleScreen := preload("res://view/title/title_screen.gd")
const DraftScreen := preload("res://view/draft/draft_screen.gd")
const LootScreen := preload("res://view/draft/loot_screen.gd")
const GarageScreen := preload("res://view/garage/garage_screen.gd")
const BattleScreen := preload("res://view/arena/battle_screen.gd")
const RoundResultScreen := preload("res://view/results/round_result_screen.gd")
const FinalScreen := preload("res://view/results/final_screen.gd")
const Look := preload("res://view/look.gd")
const PostOverlay := preload("res://view/post_overlay.gd")
const GameClient := preload("res://net/game_client.gd")
const OnlineScreen := preload("res://view/online/online_screen.gd")
const Shutter := preload("res://view/shutter.gd")

## 通信対戦でほかのプレイヤーを待つ間に、閉じたシャッターに出す文字
const SORTIE_WAIT_TEXT: String = "出撃準備OK。ほかのプレイヤーを待っています"

## ひとりで遊ぶときの、人間のプレイヤーのID
const HUMAN_ID: int = 0

var data: GameData
## 試合。ひとりで遊ぶときは MatchSession、通信対戦では写し（net/remote_session.gd）
var session: RefCounted = null
## 自分のプレイヤーID（通信対戦ではサーバーが決める）
var human_id: int = HUMAN_ID
## 通信対戦のクライアント（ひとりで遊ぶときは null）
var online: GameClient = null
var _server_pid: int = -1
## 今出している画面
var screen: Control = null
## バトルを進める速さ（画面の「4倍」ボタン）
var battle_speed: float = 1.0
## 本番の頭脳（LLM）を使うか。テストでは画面に追加する前に false にする
var use_llm: bool = true
## 頭脳とCPUの判断。本番の頭脳のサーバーは起動時に1回だけ立ち上げ、試合をまたいで使い回す
var agents: DefaultAgents = null
var _shown_phase: String = ""
## 開発用：どの画面からでもすぐタイトルへ戻るボタン（タイトル画面と、製品の書き出しでは出さない）
var dev_title_button: Button
## 開発用の一時停止（ひとりで遊ぶときだけ。どの段階でも、試合を1刻みも進めない）。Space で切り替え、止めている間は . で1コマ送り
var dev_paused: bool = false
var dev_pause_label: Label
var _step_pending: int = 0
var _shown_round: int = -1
## 出撃のシャッター（画面を切り替えても残す）
var shutter: Shutter
## 出撃の一連（閉じる → 待つ → 画面を切り替える → 開く）の途中か。1人用では、この間バトルを進めない
var sortie_active: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = make_theme()
	var bg := ColorRect.new()
	bg.color = Look.UI_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# 画面全体（メニューを含む）に薄いざらつきと周辺の暗さを重ねる
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var post := PostOverlay.new()
	layer.add_child(post)
	post.setup(Look.SCREEN_POST)
	# 出撃のシャッター：画面全体の一番手前。ただし、ざらつきの重ね（10）よりは奥
	var shutter_layer := CanvasLayer.new()
	shutter_layer.layer = 9
	add_child(shutter_layer)
	shutter = Shutter.new()
	shutter_layer.add_child(shutter)
	shutter.cancel_requested.connect(cancel_sortie)
	_add_dev_title_button()
	data = GameData.new()
	if not data.load_dir():
		push_error("data/ が読めない：\n" + "\n".join(data.errors))
		return
	agents = DefaultAgents.new(use_llm)
	show_title()


## すべての画面に使う見た目（暗い板、鈍い金色の枠、くすんだ文字）
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = load(Look.UI_FONT_PATH)
	t.default_font_size = 18
	t.set_color("font_color", "Label", Look.UI_TEXT)
	for cls: String in ["Button", "CheckBox"]:
		t.set_color("font_color", cls, Look.UI_TEXT)
		t.set_color("font_hover_color", cls, Look.UI_ACCENT)
		t.set_color("font_pressed_color", cls, Look.UI_ACCENT)
		t.set_color("font_focus_color", cls, Look.UI_TEXT)
		t.set_color("font_disabled_color", cls, Color(0.4, 0.38, 0.35))
	t.set_stylebox("normal", "Button", _box(Color(0.11, 0.1, 0.09), Look.UI_BORDER))
	t.set_stylebox("hover", "Button", _box(Color(0.15, 0.13, 0.1), Look.UI_ACCENT))
	t.set_stylebox("pressed", "Button", _box(Color(0.07, 0.065, 0.06), Look.UI_ACCENT))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Look.UI_ACCENT.darkened(0.3)))
	t.set_stylebox("disabled", "Button", _box(Color(0.08, 0.08, 0.075), Color(0.25, 0.22, 0.18)))
	t.set_stylebox("normal", "TextEdit", _box(Color(0.03, 0.03, 0.03), Look.UI_BORDER))
	t.set_stylebox("focus", "TextEdit", _box(Color(0.03, 0.03, 0.03), Look.UI_ACCENT))
	t.set_color("font_color", "TextEdit", Look.UI_TEXT)
	t.set_color("caret_color", "TextEdit", Look.UI_ACCENT)
	t.set_stylebox("background", "ProgressBar", _box(Color(0.05, 0.05, 0.05), Color(0.2, 0.18, 0.15)))
	t.set_stylebox("fill", "ProgressBar", _box(Look.UI_ACCENT.darkened(0.15), Color(0, 0, 0, 0)))
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.0 else 0)
	s.set_content_margin_all(6)
	return s


## ウィンドウを閉じたときや画面を外したときに、裏のサーバーを止める
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if agents != null:
			agents.shutdown()
		leave_online()


## 開発用のタイトルへ戻るボタンを、画面の下の真ん中（ほかの板と重ならない場所）に置く
func _add_dev_title_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11  # 画面効果の上に出す
	add_child(layer)
	dev_title_button = Button.new()
	dev_title_button.text = "[開発] タイトルへ"
	dev_title_button.add_theme_font_size_override("font_size", 14)
	dev_title_button.modulate.a = 0.75
	dev_title_button.focus_mode = Control.FOCUS_NONE  # 画面の操作（キーボード）の邪魔をしない
	dev_title_button.pressed.connect(show_title)
	dev_title_button.visible = false
	layer.add_child(dev_title_button)
	dev_title_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 4)
	dev_title_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dev_title_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 一時停止中の札（開発用の戻るボタンのすぐ上）
	dev_pause_label = Label.new()
	dev_pause_label.text = "一時停止中（Space で再開、. で1コマ送り）"
	dev_pause_label.add_theme_font_size_override("font_size", 18)
	dev_pause_label.add_theme_color_override("font_color", Look.UI_ACCENT)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0.75)
	ps.border_color = Look.UI_ACCENT
	ps.set_border_width_all(1)
	ps.set_content_margin_all(8)
	dev_pause_label.add_theme_stylebox_override("normal", ps)
	dev_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_pause_label.visible = false
	layer.add_child(dev_pause_label)
	dev_pause_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 44)
	dev_pause_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dev_pause_label.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 開発用の一時停止ができるか（開発用の実行で、ひとりで遊んでいる試合があるとき。通信対戦は進めるのがサーバーなので止められない）
func can_dev_pause() -> bool:
	return OS.is_debug_build() and session != null and not session.is_online()


## 一時停止を切り替える（止められないときは解くだけ）
func toggle_dev_pause() -> void:
	set_dev_paused(not dev_paused and can_dev_pause())


func set_dev_paused(on: bool) -> void:
	dev_paused = on
	_step_pending = 0
	if dev_pause_label != null:
		dev_pause_label.visible = on


## 止めている間に1コマ（1刻み）だけ進める
func dev_step() -> void:
	if dev_paused:
		_step_pending += 1


## 一時停止のキー（Space と .）は、画面のボタンより先に受け取る（Space がボタンを押してしまわないように）。
## ただし文字の欄に入力しているときは、ふつうの文字として扱う
func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not OS.is_debug_build():
		return
	if k.keycode != KEY_SPACE and k.keycode != KEY_PERIOD:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is TextEdit or focus is LineEdit:
		return
	if k.keycode == KEY_SPACE:
		if not can_dev_pause():
			return
		toggle_dev_pause()
	else:
		if not dev_paused:
			return
		dev_step()
	get_viewport().set_input_as_handled()


func show_title() -> void:
	set_dev_paused(false)
	end_sortie()
	leave_online()
	session = null
	_shown_phase = ""
	_show(TitleScreen.new())


## 通信対戦の画面（つなぐ・待合室）を出す
func open_online() -> void:
	_show(OnlineScreen.new())


## 通信対戦につなぐ。host_server なら、このPCで画面なしのサーバーを裏で起動してから自分もつなぐ。問題があれば理由を返す
func start_online(host: String, port: int, player_name: String, host_server: bool) -> String:
	leave_online()
	if host_server:
		var args: PackedStringArray = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://net/server_main.tscn", "--", "--port=%d" % port]
		_server_pid = OS.create_process(OS.get_executable_path(), args, false)
		if _server_pid <= 0:
			return "サーバーを起動できない"
		host = "127.0.0.1"
	online = GameClient.new()
	online.name = "GameClient"
	add_child(online)
	if online.connect_to(data, agents, host, port, player_name) != OK:
		return online.reason
	return ""


## 通信対戦を抜ける（自分で立てたサーバーも止める）
func leave_online() -> void:
	if online != null:
		if is_instance_valid(online):
			online.close()
			online.queue_free()
		online = null
	if _server_pid > 0:
		if OS.is_process_running(_server_pid):
			OS.kill(_server_pid)
		_server_pid = -1
	human_id = HUMAN_ID
	if session != null and session.is_online():
		session = null


func is_hosting() -> bool:
	return _server_pid > 0


## 新しい試合を始める。seed_value が 0 なら時刻から種を作る
func start_game(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = Time.get_ticks_usec() % 1000000 + 1
	var setup: Array = [{"name": "あなた", "is_human": true}]
	for i: int in range(1, int(data.rule("players"))):
		setup.append({"name": "CPU%d" % i, "is_human": false})
	session = MatchSession.new(data, seed_value, setup, agents)
	battle_speed = 1.0
	end_sortie()
	set_dev_paused(false)
	_shown_phase = ""
	_sync_screen()


func _process(delta: float) -> void:
	if online != null:
		# 通信対戦：試合の写しが届いていれば試合として扱う。待合室に戻ったら待合室の画面へ
		if online.session != session:
			session = online.session
			_shown_phase = ""
		if session == null:
			end_sortie()  # 通信が切れた・待合室に戻ったら、シャッターを残さない
			if screen == null or screen.get_script() != OnlineScreen:
				_show(OnlineScreen.new())
			return
		human_id = session.my_id
	if session == null:
		return
	var me: Variant = session.get_player(human_id)
	if me == null:
		return
	if dev_paused:
		if not can_dev_pause():
			set_dev_paused(false)
		else:
			# 止めている間は進めない。1コマ送りのときだけ、1刻み分（速さの倍率はかけない）進める
			if _step_pending > 0:
				_step_pending -= 1
				session.update(0.0 if _holding_battle() else 1.0 / float(data.rule("tick_rate")))
			# 止めていても、操作（出撃ボタンなど）で段階が変わったら画面は切り替える
			_update_sortie(me)
			_sync_screen()
			_apply_shake()
			return
	if not me.alive:  # 脱落したら自分の操作はないので、そのまま進める
		if session.phase == MatchSession.PHASE_BUILD:
			session.finish_build()
		elif session.phase == MatchSession.PHASE_LOOT:
			session.finish_loot()
	var speed: float = battle_speed if session.phase == MatchSession.PHASE_BATTLE else 1.0
	if _holding_battle():
		speed = 0.0  # シャッターが開ききるまでバトルを始めない
	session.update(delta * speed)
	_update_sortie(me)
	_sync_screen()
	_apply_shake()


# ---- 出撃のシャッター ----

## 出撃した（組み立て画面の「出撃」で、機体が正しいと確かめたあと）。シャッターを閉じ始める
func begin_sortie() -> void:
	if sortie_active or shutter == null:
		return
	sortie_active = true
	get_viewport().gui_release_focus()  # 閉じている間に、下の画面の欄へ文字が入らないように
	shutter.close()


## 待っている間のキャンセル：出撃を取り消し、シャッターを開いて組み立て画面に戻る（バトルに移ったあとは何もしない）
func cancel_sortie() -> void:
	if not sortie_active or session == null or session.phase != MatchSession.PHASE_BUILD:
		return
	session.cancel_build(human_id)
	sortie_active = false
	shutter.open()
	if screen != null and screen.has_method("on_sortie_cancelled"):
		screen.call("on_sortie_cancelled")


## シャッターをすぐに片付ける（タイトルへ戻る・試合が飛んだ・通信が切れたとき）
func end_sortie() -> void:
	sortie_active = false
	if shutter != null:
		shutter.reset()
	if screen != null:
		screen.position = Vector2.ZERO


## 1人用で、シャッターのためにバトルを止めておく間か（組み立ての段階は止めない）
func _holding_battle() -> bool:
	return sortie_active and session != null and not session.is_online() 		and session.phase == MatchSession.PHASE_BATTLE


## 出撃の一連を進める。締め切りで自動出撃したときもここで閉じ始める
func _update_sortie(me: Variant) -> void:
	if session == null:
		end_sortie()
		return
	var ph: String = session.phase
	if not sortie_active:
		# 組み立て画面のままバトルに移った（制限時間切れの自動出撃、バトルに移ったあとの取り消し）。脱落して観戦中は出さない
		if ph == MatchSession.PHASE_BATTLE and _shown_phase == MatchSession.PHASE_BUILD and me.alive:
			begin_sortie()
		else:
			return
	if ph != MatchSession.PHASE_BUILD and ph != MatchSession.PHASE_BATTLE:
		end_sortie()  # 「最後まで飛ばす」などでバトルを飛ばした
		return
	if ph == MatchSession.PHASE_BUILD:
		# 通信対戦でほかのプレイヤーを待っている間（1人用は出撃するとすぐバトルに移るので、ここには来ない）
		var waiting: bool = shutter.is_closed()
		shutter.set_waiting(SORTIE_WAIT_TEXT if waiting else "", waiting)
		return
	shutter.set_waiting("", false)
	var start_left: float = session.battle_start_left if session.is_online() else -1.0
	if shutter.state == Shutter.State.CLOSING or shutter.shaking:
		# 通信対戦：閉じる＋開くが開始に間に合わなければ速める
		if start_left >= 0.0:
			var need: float = shutter.time_to_closed() + Look.SHUTTER_OPEN_SEC
			if start_left < need:
				shutter.set_speed(need / maxf(start_left, 0.01))
		return
	if shutter.is_closed():
		if _shown_phase != MatchSession.PHASE_BATTLE:
			_sync_screen(true)  # シャッターの裏でバトル画面に切り替える
		if start_left >= 0.0:
			# 開ききるのがちょうど開始の時刻になるように待ってから開く
			if start_left > Look.SHUTTER_OPEN_SEC:
				return
			shutter.set_speed(Look.SHUTTER_OPEN_SEC / maxf(start_left, 0.01))
		elif shutter.closed_time < Look.SHUTTER_CLOSED_HOLD_SEC:
			return  # 1人用：閉じたまま少し待ってから開く
		shutter.open()
	elif shutter.is_open():
		sortie_active = false  # 開ききった。次の刻みからバトルが進む


## シャッターの揺れを画面全体にもかける
func _apply_shake() -> void:
	if screen != null and shutter != null and (shutter.shaking or screen.position != Vector2.ZERO):
		screen.position = shutter.shake_offset()


## 試合の段階が変わっていれば、対応する画面に切り替える
func _sync_screen(force_battle: bool = false) -> void:
	if session == null or (session.phase == _shown_phase and session.round_no == _shown_round):
		return
	# 出撃のシャッターが閉じきるまでは、バトル画面に切り替えない
	if sortie_active and session.phase == MatchSession.PHASE_BATTLE and not force_battle and not shutter.is_closed():
		return
	_shown_phase = session.phase
	_shown_round = session.round_no
	match session.phase:
		MatchSession.PHASE_DRAFT: _show(DraftScreen.new())
		MatchSession.PHASE_BUILD: _show(GarageScreen.new())
		MatchSession.PHASE_BATTLE: _show(BattleScreen.new())
		MatchSession.PHASE_ROUND_RESULT: _show(RoundResultScreen.new())
		MatchSession.PHASE_LOOT: _show(LootScreen.new())
		MatchSession.PHASE_FINISHED: _show(FinalScreen.new())


func _show(next: Control) -> void:
	if screen != null:
		screen.queue_free()
	screen = next
	screen.set("main", self)
	add_child(screen)
	screen.call("build_ui")
	if dev_title_button != null:
		dev_title_button.visible = OS.is_debug_build() and screen.get_script() != TitleScreen
