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

## 人間のプレイヤーのID
const HUMAN_ID: int = 0
const COL_BG := Color(0.08, 0.08, 0.09)

var data: GameData
var session: MatchSession = null
## 今出している画面
var screen: Control = null
## バトルを進める速さ（画面の「4倍」ボタン）
var battle_speed: float = 1.0
var _shown_phase: String = ""
var _shown_round: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	data = GameData.new()
	if not data.load_dir():
		push_error("data/ が読めない：\n" + "\n".join(data.errors))
		return
	show_title()


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
	session = MatchSession.new(data, seed_value, setup, DefaultAgents.new())
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
