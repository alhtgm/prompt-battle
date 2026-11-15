# 画面の骨組みのテスト。段階4の完成の目安「プレイヤーが操作して段階が進む」を、画面のボタンと同じ操作で確かめる。
# 本物の main.tscn を画面なしで動かし、タイトルから最終順位まで遊び切る。
extends "res://tests/support/test_case.gd"

const MatchSession := preload("res://core/match_session.gd")
const TitleScreen := preload("res://view/title/title_screen.gd")
const DraftScreen := preload("res://view/draft/draft_screen.gd")
const LootScreen := preload("res://view/draft/loot_screen.gd")
const GarageScreen := preload("res://view/garage/garage_screen.gd")
const BattleTextScreen := preload("res://view/arena/battle_text_screen.gd")
const RoundResultScreen := preload("res://view/results/round_result_screen.gd")
const FinalScreen := preload("res://view/results/final_screen.gd")

const PHASE_SCREENS: Dictionary = {
	"draft": DraftScreen, "build": GarageScreen, "battle": BattleTextScreen,
	"round_result": RoundResultScreen, "loot": LootScreen, "finished": FinalScreen,
}


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _is(screen: Node, script: GDScript) -> bool:
	return screen != null and screen.get_script() == script


func test_play_through_from_title_to_final_ranking() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	tree.root.add_child(main)
	await _frame()
	check(_is(main.screen, TitleScreen), "最初はタイトル画面")

	main.start_game(31337)
	await _frame()
	check(_is(main.screen, DraftScreen), "はじめるとパーツ選び")
	var draft: Node = main.screen
	check(not draft.confirm().is_empty(), "全部選ぶ前は決定できない")
	for kind: String in ["frame", "weapon", "skill"]:
		draft.select(kind, main.session.draft_offer[kind][1].uid)
	check_eq(draft.confirm(), "", "種類ごとに1つ選ぶと決定できる")
	await _frame()
	check(_is(main.screen, GarageScreen), "パーツ選びの次は組み立て")

	var me: Variant = main.session.get_player(0)
	var visited: Dictionary = {}
	var guard: int = 0
	while main.session != null and main.session.phase != MatchSession.PHASE_FINISHED and guard < 200:
		guard += 1
		var phase: String = main.session.phase
		visited[phase] = true
		check(_is(main.screen, PHASE_SCREENS[phase]), "段階 %s に合う画面が出ている" % phase)
		match phase:
			MatchSession.PHASE_BUILD:
				if me.alive:
					var g: Node = main.screen
					var weapons: Array = []
					var frame: int = -1
					for p: Variant in me.hand:
						if p.kind == "frame" and frame < 0:
							frame = p.uid
						elif p.kind == "weapon" and weapons.size() < 4:
							weapons.append(p.uid)
					if weapons.size() > 3:
						g.set_selection(frame, weapons, [])
						check(not g.confirm().is_empty(), "枠を超える武器では出撃できない")
					g.set_selection(frame, weapons.slice(0, 1), [])
					g.set_prompt("相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ")
					check_eq(g.confirm(), "", "正しい機体なら出撃できる")
			MatchSession.PHASE_BATTLE:
				var b: Node = main.screen
				main.session.update(3.0)
				b._refresh()
				check(b._header.text.contains("ラウンド %d" % main.session.round_no), "バトル画面にラウンドが出る")
				b.skip()
			MatchSession.PHASE_ROUND_RESULT:
				main.screen.next()
			MatchSession.PHASE_LOOT:
				if me.alive:
					check(not main.screen.pick("perk_nothing").is_empty(), "候補にないパークは選べない")
					check_eq(main.screen.pick(me.perk_choices[0]), "", "候補のパークを選べる")
		await _frame()
		await _frame()

	check(main.session != null and main.session.phase == MatchSession.PHASE_FINISHED, "最終順位まで進む")
	for phase: String in ["build", "battle", "round_result", "loot"]:
		check(visited.has(phase), "段階 %s を通った" % phase)
	check(_is(main.screen, FinalScreen), "最後は最終順位の画面")
	check(me.place >= 1 and me.place <= 6, "自分の順位が決まる（%d位）" % me.place)
	main.screen.to_title()
	await _frame()
	check(_is(main.screen, TitleScreen), "タイトルへ戻れる")
	main.queue_free()
	await _frame()
