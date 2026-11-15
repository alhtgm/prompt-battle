# 画面の切り替え役。試合（MatchSession）の今の段階を読み、対応する画面を出す。
# 試合の状態は読むだけで、操作は MatchSession のメソッドだけを通す。プレイヤーが脱落したら、組み立てとパーク選びを飛ばして観戦を続ける。
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

## 人間のプレイヤーのID
const HUMAN_ID: int = 0

var data: GameData
var session: MatchSession = null
## 今出している画面
var screen: Control = null
## バトルを進める速さ（画面の「4倍」ボタン）
var battle_speed: float = 1.0
## 本番の頭脳（LLM）を使うか。テストでは画面に追加する前に false にする
var use_llm: bool = true
## 頭脳とCPUの判断。本番の頭脳のサーバーは起動時に1回だけ立ち上げ、試合をまたいで使い回す
var agents: DefaultAgents = null
var _shown_phase: String = ""
var _shown_round: int = -1


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
	data = GameData.new()
	if not data.load_dir():
		push_error("data/ が読めない：\n" + "\n".join(data.errors))
		return
	agents = DefaultAgents.new(use_llm)
	show_title()


## すべての画面に使う見た目（暗い板、鈍い金色の枠、くすんだ文字）
static func make_theme() -> Theme:
	var t := Theme.new()
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


func show_title() -> void:
	session = null
	_shown_phase = ""
	_show(TitleScreen.new())


## 新しい試合を始める。seed_value が 0 なら時刻から種を作る
func start_game(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = Time.get_ticks_usec() % 1000000 + 1
	var setup: Array = [{"name": "あなた", "is_human": true}]
	for i: int in range(1, int(data.rule("players"))):
		setup.append({"name": "CPU%d" % i, "is_human": false})
	session = MatchSession.new(data, seed_value, setup, agents)
	battle_speed = 1.0
	_shown_phase = ""
	_sync_screen()


func _process(delta: float) -> void:
	if session == null:
		return
	var me: Variant = session.get_player(HUMAN_ID)
	if not me.alive:  # 脱落したら自分の操作はないので、そのまま進める
		if session.phase == MatchSession.PHASE_BUILD:
			session.finish_build()
		elif session.phase == MatchSession.PHASE_LOOT:
			session.finish_loot()
	var speed: float = battle_speed if session.phase == MatchSession.PHASE_BATTLE else 1.0
	session.update(delta * speed)
	_sync_screen()


## 試合の段階が変わっていれば、対応する画面に切り替える
func _sync_screen() -> void:
	if session == null or (session.phase == _shown_phase and session.round_no == _shown_round):
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
