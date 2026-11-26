# 画面の骨組みのテスト。段階4の完成の目安「プレイヤーが操作して段階が進む」を、画面のボタンと同じ操作で確かめる。
# 本物の main.tscn を画面なしで動かし、タイトルから最終順位まで遊び切る。
extends "res://tests/support/test_case.gd"

const MatchSession := preload("res://core/match_session.gd")
const TitleScreen := preload("res://view/title/title_screen.gd")
const DraftScreen := preload("res://view/draft/draft_screen.gd")
const LootScreen := preload("res://view/draft/loot_screen.gd")
const PartCard := preload("res://view/draft/part_card.gd")
const Loot := preload("res://core/loot.gd")
const Rng := preload("res://core/rng.gd")
const GarageScreen := preload("res://view/garage/garage_screen.gd")
const BattleScreen := preload("res://view/arena/battle_screen.gd")
const UiText := preload("res://view/ui_text.gd")
const Look := preload("res://view/look.gd")
const RoundResultScreen := preload("res://view/results/round_result_screen.gd")
const FinalScreen := preload("res://view/results/final_screen.gd")

const PHASE_SCREENS: Dictionary = {
	"draft": DraftScreen, "build": GarageScreen, "battle": BattleScreen,
	"round_result": RoundResultScreen, "loot": LootScreen, "finished": FinalScreen,
}


func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _is(screen: Node, script: GDScript) -> bool:
	return screen != null and screen.get_script() == script


## 画面の中身が、スクロールなしで画面（プロジェクトの基準の大きさ）に収まっているか
func _check_fits(screen: Control, what: String) -> void:
	var limit := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	var need: Vector2 = screen.get_combined_minimum_size()
	check(need.x <= limit.x + 0.5 and need.y <= limit.y + 0.5,
		"%s が画面に収まる（必要 %d×%d / 画面 %d×%d）" % [what, need.x, need.y, limit.x, limit.y])


## 段階5の完成の目安：自分の試合を3Dで観戦でき、操縦士の今の方針と一言が見える
func _check_battle_screen(b: Node, main: Node) -> void:
	var r: int = main.session.round_no
	check(b.header.text.contains("ラウンド %d" % r), "ラウンド %d：バトル画面にラウンドが出る" % r)
	# 上の見出し（操縦士の状態が長くても）は、左右の機体の板にかぶらない
	b.brain_label.text = "操縦士：仮の頭脳（llama-server が見つからない（tools/fetch_llm.ps1 で取れる））"
	var top_r: Rect2 = b.header.get_parent().get_parent().get_global_rect()
	for i: int in 2:
		var side_r: Rect2 = b.side_names[i].get_parent().get_parent().get_global_rect()
		check(not top_r.intersects(side_r), "ラウンド %d：見出しが機体 %d の板にかぶらない" % [r, i])
	var me_alive: bool = main.session.get_player(0).alive
	var mine: Variant = main.session.battle_of(0)
	if me_alive:
		check(b.watched_battle == mine, "ラウンド %d：自分の試合を映している" % r)
	var sim: Variant = b.watched_battle.sim
	for i: int in 2:
		var robot: Variant = sim.robots[i]
		var view: Node3D = b.arena.robot_views[i]
		check(view.position.distance_to(Vector3(robot.x, view.position.y, robot.z)) < 0.01,
			"ラウンド %d：3Dの機体 %d が計算上の位置にいる" % [r, i])
		if not robot.fell and robot.stun <= 0.0:
			var intent_label: String = UiText.INTENT_LABELS[robot.intent]
			check(b.side_intents[i].text.contains(intent_label), "ラウンド %d：機体 %d の方針「%s」が見える" % [r, i, intent_label])
		if not robot.say.is_empty():
			check(b.side_says[i].text.contains(robot.say), "ラウンド %d：機体 %d の一言が見える" % [r, i])
			check(view.label.text.contains(robot.say), "ラウンド %d：機体 %d の頭上に一言が出る" % [r, i])
	check(b.arena.camera.current, "ラウンド %d：アリーナのカメラが使われている" % r)
	# プロンプトの見せ方：生き残っている間は自分のものだけ、脱落したら両方
	var ids: Array = [b.watched_battle.a, b.watched_battle.b]
	for i: int in 2:
		var p: String = str(b.watched_battle.prompts[i])
		var shown: bool = not p.is_empty() and b.side_prompts[i].text.contains(p)
		if not me_alive or ids[i] == 0:
			check(p.is_empty() or shown, "ラウンド %d：見てよいプロンプト（機体 %d）が見える" % [r, i])
		else:
			check(not shown, "ラウンド %d：生き残っている間は相手のプロンプトが見えない" % r)


func test_play_through_from_title_to_final_ranking() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false  # テストでは本番の頭脳のサーバーを起動しない
	tree.root.add_child(main)
	await _frame()
	check(_is(main.screen, TitleScreen), "最初はタイトル画面")
	_check_fits(main.screen, "タイトル画面")

	main.start_game(31337)
	await _frame()
	check(_is(main.screen, DraftScreen), "はじめるとパーツ選び")
	_check_fits(main.screen, "パーツ選びの画面")
	var draft: Node = main.screen
	check(not draft._confirm.disabled, "最初から各種類の1枚目が選ばれていて決定できる")
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
		await wait_sortie(main)  # 組み立てからバトルへは、出撃のシャッターが開ききってから
		var phase: String = main.session.phase
		visited[phase] = true
		check(_is(main.screen, PHASE_SCREENS[phase]), "段階 %s に合う画面が出ている" % phase)
		match phase:
			MatchSession.PHASE_BUILD:
				if me.alive:
					var g: Node = main.screen
					var weapons: Array = []
					var frame: int = -1
					var frame_slots: int = 0
					for p: Variant in me.hand:
						if p.kind == "frame" and frame < 0:
							frame = p.uid
							frame_slots = main.session.data.get_part(p.def_id).weapon_slots
					var limit: int = frame_slots + me.extra_weapon_slots(main.session.data)
					for p: Variant in me.hand:
						if p.kind == "weapon" and weapons.size() < limit + 1:
							weapons.append(p.uid)
					if weapons.size() > limit:
						g.set_selection(frame, weapons, [])
						check(not g.confirm().is_empty(), "枠を超える武器では出撃できない")
					g.set_selection(frame, weapons.slice(0, 1), [])
					check_eq(g.carousels["frame"].current_uid(), frame, "フレームの段の真ん中が選んだフレーム")
					check_eq(g.carousels["weapon:0"].current_uid(), weapons[0], "武器1の段の真ん中が選んだ武器")
					if g.carousels.has("weapon:1") and weapons.size() >= 2:
						# ほかの枠で付けている武器は、その段の候補に出ない（同じものを2つ付けられない）
						var uids_of := func(c: Node) -> Array:
							return c.parts.map(func(pp: Variant) -> int: return pp.uid if pp != null else -1)
						check(not uids_of.call(g.carousels["weapon:1"]).has(weapons[0]), "武器1で付けた武器は武器2の候補に出ない")
						g.carousels["weapon:1"].select_uid(weapons[1])
						g.carousels["weapon:1"].picked.emit("weapon", weapons[1])
						check(not uids_of.call(g.carousels["weapon:0"]).has(weapons[1]), "武器2で選ぶと武器1の候補から外れる")
						check_eq(g.carousels["weapon:0"].current_uid(), weapons[0], "武器1の選んだものはそのまま")
						check_eq(g.weapon_uids, [weapons[0], weapons[1]] as Array[int], "2つの枠に別々の武器が付く")
						g.set_selection(frame, weapons.slice(0, 1), [])
					g.set_prompt("相手が穴の近くに来たら穴に押し込め。それ以外は突撃しろ")
					check_eq(g.confirm(), "", "正しい機体なら出撃できる")
			MatchSession.PHASE_BATTLE:
				var b: Node = main.screen
				main.session.update(3.0)
				await _frame()
				b.refresh()
				_check_battle_screen(b, main)
				var mine_b: Variant = main.session.battle_of(0)
				if mine_b != null and b.watched_battle == mine_b:
					check(not b.finish_label.visible, "試合中は FINISH を出さない")
					mine_b.sim.run_to_end()
					b.refresh()
					check(b.finish_label.visible, "自分の試合が終わると FINISH が大きく出る")
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
	_check_fits(main.screen, "最終順位の画面")
	check(me.place >= 1 and me.place <= 6, "自分の順位が決まる（%d位）" % me.place)
	main.screen.play_again()
	await _frame()
	check(_is(main.screen, DraftScreen) and main.session.round_no == 0, "もう一度遊ぶと新しい試合のパーツ選びから")
	main.show_title()
	await _frame()
	check(_is(main.screen, TitleScreen), "タイトルに戻れる")
	main.start_game(1)
	await _frame()
	for k: int in 60:  # 2試合目は操作せず締め切りだけで最後まで進める
		if main.session.is_finished():
			break
		match main.session.phase:
			"draft": main.session.finish_draft()
			"build": main.session.finish_build()
			"battle": main.session.run_battles_to_end()
			"round_result": main.session.finish_round_result()
			"loot": main.session.finish_loot()
		await _frame()
	check(_is(main.screen, FinalScreen), "2試合目も最終順位まで進む")
	main.screen.to_title()
	await _frame()
	check(_is(main.screen, TitleScreen), "タイトルへ戻れる")
	main.queue_free()
	await _frame()


## パーツ選びの画面：種類ごとの段を◀▶で送ると選ばれる、開く段は1つ、右に組んだ機体と性能が出る、タイトルへ戻れる
func test_draft_screen_carousel_preview_and_back() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	check(main.screen.menu_buttons.size() >= 3, "タイトルにメニューのボタンが並ぶ")
	check(main.screen.stage.robot != null, "タイトルに回る機体がある")
	main.start_game(4242)
	await _frame()
	var draft: Node = main.screen
	check(_is(draft, DraftScreen), "パーツ選びの画面")
	var offer: Dictionary = main.session.draft_offer
	for kind: String in ["frame", "weapon", "skill"]:
		check_eq(draft.carousels[kind].cards.size(), offer[kind].size(), "%s：候補ごとにカードがある" % kind)
		check_eq(draft.picks.get(kind, -1), offer[kind][0].uid, "%s：最初は1枚目が選ばれている" % kind)
	# 開いている段は1つだけ
	check(draft.carousels["frame"].expanded and not draft.carousels["weapon"].expanded and not draft.carousels["skill"].expanded,
		"最初はフレームの段だけ開いている")
	draft.carousels["weapon"].header.mouse_entered.emit()  # 武器の見出しにマウスを合わせたのと同じ
	check_eq(draft.active_kind, "weapon", "見出しに合わせるとその段が開く")
	check(draft.carousels["weapon"].expanded and not draft.carousels["frame"].expanded and not draft.carousels["skill"].expanded,
		"開いている段は武器だけ")
	check(draft.carousels["weapon"].stage.visible and draft.carousels["weapon"].stage.custom_minimum_size.y < Look.DRAFT_CARD_SIZE.y,
		"開くときは一瞬ではなく、少しずつ開く")
	await tree.create_timer(Look.DRAFT_EXPAND_SEC + 0.15).timeout
	check(not draft.carousels["frame"].stage.visible and draft.carousels["frame"].header.visible, "閉じた段は見出しの文字だけ見える")
	check(draft.carousels["weapon"].stage.custom_minimum_size.y >= Look.DRAFT_CARD_SIZE.y, "開き終わるとカードの高さまで開く")
	# ◀▶で送ると、真ん中に来たものが選ばれる（端は輪になる）
	var weapons: Array = offer["weapon"]
	var wc: Node = draft.carousels["weapon"]
	wc.next_button.pressed.emit()
	check_eq(draft.picks["weapon"], weapons[1].uid, "▶で次の武器が選ばれる")
	var weapon_name: String = main.data.get_part(weapons[1].def_id).name
	check(wc.header.text.contains(weapon_name), "見出しに選んだ武器の名前が出る")
	check(draft.build_preview.name_labels["weapon"].text == weapon_name, "右の一覧に選んだ武器の名前が出る")
	check(not draft.build_preview.desc_labels["weapon"].text.is_empty(), "右の一覧に効果の説明が出る")
	check(draft.build_preview.stats_boxes["weapon"].get_child_count() > 0, "右の一覧にステータスが出る")
	wc.prev_button.pressed.emit()
	wc.prev_button.pressed.emit()
	check_eq(draft.picks["weapon"], weapons[weapons.size() - 1].uid, "1枚目で◀を押すと最後の武器になる")
	wc.next_button.pressed.emit()
	check_eq(draft.picks["weapon"], weapons[0].uid, "最後で▶を押すと1枚目に戻る")
	for i: int in 7:
		wc.next_button.pressed.emit()  # 動きの途中で何度も送る
	check_eq(draft.picks["weapon"], weapons[7 % weapons.size()].uid, "続けて送っても選択がずれない")
	wc.cards[posmod(wc.index - 1, weapons.size())].pressed.emit()
	check_eq(draft.picks["weapon"], weapons[6 % weapons.size()].uid, "左にのぞくカードを押すと1つ戻る")
	# キーボード：→で送る、↓で次の段が開く
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	draft._input(key)
	check_eq(draft.picks["weapon"], weapons[7 % weapons.size()].uid, "→キーで送れる")
	key.keycode = KEY_DOWN
	draft._input(key)
	check_eq(draft.active_kind, "skill", "↓キーで次の段が開く")
	draft._input(key)
	check_eq(draft.active_kind, "skill", "いちばん下で↓を押しても段は替わらない")
	# 見本の機体は選んだ構成で、フレームの枠を超えるパーツは付けない
	for f: Variant in offer["frame"]:
		draft.select("frame", f.uid)
		var fdef: Variant = main.data.get_part(f.def_id)
		var b: Variant = draft.build_preview.build
		check_eq(b.frame.def_id, f.def_id, "%s：見本は選んだフレーム" % fdef.name)
		check_eq(b.validate(main.data), "", "%s：見本はフレームの枠に収まっている" % fdef.name)
		check_eq(b.skills.size(), mini(1, fdef.skill_slots), "%s：スキルは枠があるときだけ付く" % fdef.name)
		check_eq(draft.build_preview.note_labels["skill"].visible, fdef.skill_slots == 0, "%s：スキルの枠がないと注意書きが出る" % fdef.name)
		if fdef.weapon_slots > 0:
			check_eq(b.weapons[0].def_id, main.data.get_part(draft.carousels["weapon"].current().def_id).id, "%s：見本に選んだ武器が付く" % fdef.name)
	check(draft.build_preview.preview.robot != null, "右に見本の機体がある")
	draft.back_button.pressed.emit()
	await _frame()
	check(_is(main.screen, TitleScreen) and main.session == null, "戻るボタンでタイトルに戻る")
	check(not main.dev_title_button.visible, "タイトル画面では開発用の戻るボタンを出さない")
	main.start_game(4243)
	await _frame()
	check(main.dev_title_button.visible, "タイトル以外では開発用の戻るボタンが出る")
	main.dev_title_button.pressed.emit()
	await _frame()
	check(_is(main.screen, TitleScreen) and main.session == null, "開発用の戻るボタンでタイトルに戻る")
	main.queue_free()
	await _frame()


## タイトルの機体：背を向けるたびに載せ替わり、組み合わせはフレームの枠の数に収まっている
func test_title_robot_swaps_each_turn() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	var title: Node = main.screen
	check(_is(title, TitleScreen), "タイトル画面")
	var first: Node3D = title.stage.robot
	var swaps_before: int = title.swaps
	title.stage.turned_away.emit()  # 一回転して背を向けたのと同じ
	check_eq(title.swaps, swaps_before + 1, "背を向けると載せ替わる")
	check(title.stage.robot != first and is_instance_valid(title.stage.robot), "新しい機体が載っている")
	var Showroom: GDScript = load("res://view/showroom.gd")
	var Rng: GDScript = load("res://core/rng.gd")
	var rng: RefCounted = Rng.new(99)
	for i: int in 30:
		var b: Variant = Showroom.random_build(main.data, rng)
		check_eq(b.validate(main.data), "", "組んだ機体が正しい（%d回目）" % i)
	main.queue_free()
	await _frame()


## ラウンド結果・パーク選び・最終順位の画面：スタンプと内訳、体力バー、パークのカードと効き方、配られたパーツのカード、表彰台
func test_result_loot_and_final_screens() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	main.start_game(777)
	await _frame()
	var offer: Dictionary = main.session.draft_offer
	for kind: String in ["frame", "weapon", "skill"]:
		main.screen.select(kind, offer[kind][0].uid)
	main.screen.confirm()
	await _frame()
	var saw_lose: bool = false
	var saw_loot: bool = false
	var fitted: Dictionary = {}
	for k: int in 80:
		var s: Variant = main.session
		if s.phase == "finished":
			break
		if main.screen is Control:
			_check_fits(main.screen, "段階 %s（ラウンド %d）の画面" % [s.phase, s.round_no])
		match s.phase:
			"build":
				var g: Node = main.screen
				check(_is(g, GarageScreen), "組み立ての画面")
				var me_g: Variant = s.get_player(0)
				if me_g.alive:
					# 手持ちのどのフレームにしても（枠が多くて段が増えても）画面に収まる
					for part: Variant in me_g.hand:
						if part.kind == "frame" and not fitted.has(part.def_id):
							fitted[part.def_id] = true
							g.set_selection(part.uid, [], [])
							g._fill_empty_slots()
							g._build_sections()
							g._update_info()
							await _frame()
							_check_fits(g, "組み立ての画面（%s）" % part.def_id)
							check(g.weapon_uids.size() <= g._max_slots().x and g.skill_uids.size() <= g._max_slots().y,
								"空いた枠は手持ちで埋めるが、枠は超えない")
					# 段でフレームを替えていくと、武器・スキルの段は枠の数だけ出る（枠が0なら出ない）。付けている数も枠を超えない
					for part: Variant in me_g.hand:
						if part.kind != "frame":
							continue
						g.carousels["frame"].select_uid(part.uid)
						g.carousels["frame"].picked.emit("frame", part.uid)
						var slots: Vector2i = g._max_slots()
						var n_w: int = g.carousels.keys().filter(func(k: String) -> bool: return k.begins_with("weapon:")).size()
						var n_s: int = g.carousels.keys().filter(func(k: String) -> bool: return k.begins_with("skill:")).size()
						check(n_w == slots.x and n_s == slots.y,
							"%s：段は武器 %d・スキル %d（枠 %d・%d）" % [part.def_id, n_w, n_s, slots.x, slots.y])
						check(g.weapon_uids.size() <= slots.x and g.skill_uids.size() <= slots.y,
							"%s：付けている数が枠を超えない" % part.def_id)
				check(g.fuse.visible and g.fuse.left > 0.0, "ひとりで遊ぶときも組み立てに残り時間のバーが出る")
				var me_b: Variant = s.get_player(0)
				if s.round_no >= 2 and me_b.alive:
					check(not me_b.new_parts.is_empty(), "組み立ての段階でも配られたパーツが分かる")
					check_eq(g.new_tags.size(), me_b.new_parts.size(), "配られたパーツに NEW の札が付く")
				s.finish_build()
			"battle": s.run_battles_to_end()
			"round_result":
				var r: Node = main.screen
				var real_word: String = r.stamp.text if r.stamp != null else ""  # 試し押しで変わる前の本当の結果
				if r.stamp != null:
					check(absf(r.stamp.rotation) < 0.001, "スタンプは最初まっすぐ押される")
					# 動きを最後まで早送りして、終わったときの形を見る：傾くのは LOSE だけ
					for spec: Array in [["WIN", "bounce"], ["WIN", "shine"], ["DRAW", ""], ["LOSE", ""]]:
						r.play_stamp(spec[0], spec[1])
						check(absf(r.stamp.rotation) < 0.001, "%s %s：最初はまっすぐ" % spec)
						r.stamp_tween.custom_step(10.0)
						var want: float = deg_to_rad(Look.STAMP_TILT_DEG) if spec[0] == "LOSE" else 0.0
						check(absf(r.stamp.rotation - want) < 0.001, "%s %s：終わったときの傾き" % spec)
						check(r.stamp.scale.is_equal_approx(Vector2.ONE), "%s %s：終わったら元の大きさ" % spec)
						check(r.stamp.modulate.is_equal_approx(Color(1, 1, 1, 1)), "%s %s：終わったら元の明るさ" % spec)
				check(_is(r, RoundResultScreen), "ラウンド結果の画面")
				var h: Dictionary = s.history[s.history.size() - 1]
				check_eq(r.bars.size(), s.players.size(), "全員の体力バーがある")
				for id: Variant in r.bars:
					var bar: Control = r.bars[id]
					check(bar.to_value >= 0.0 and bar.to_value <= bar.max_value and bar.from_value >= bar.to_value,
						"体力バーの値が範囲内で、減る向き（%s）" % str(id))
				var me: Variant = s.get_player(0)
				var fought: bool = s.history[s.history.size() - 1]["health"].has(0) and (me.alive or h["eliminated"].has(0))
				if fought and r.stamp != null:
					check(real_word in ["WIN", "LOSE", "DRAW"], "スタンプは WIN / LOSE / DRAW")
					if real_word == "LOSE":
						saw_lose = true
						var dmg: int = int(h["damage"].get(0, 0))
						check(r.breakdown_lines.size() >= 3 and r.breakdown_lines[0].text.contains("−%d" % dmg),
							"負けたらダメージの合計と内訳が出る")
				r.next()
			"loot":
				var l: Node = main.screen
				check(_is(l, LootScreen), "パーク選びの画面")
				var me: Variant = s.get_player(0)
				check_eq(l.part_cards.size(), me.new_parts.size(), "配られたパーツごとにカードがある")
				check_eq(l.perk_cards.size(), me.perk_choices.size(), "パークの候補ごとにカードがある")
				for pc: Variant in l.perk_cards:
					check(not pc.effect_lines.is_empty(), "パークのカードに効き方が出る（%s）" % pc.perk_id)
				check(not l.fuse.visible, "ひとりで遊ぶときは残り時間のバーを出さない")
				if not saw_loot:
					saw_loot = true
					if not l.part_cards.is_empty():
						await _frame()
						check(l.showcase != null, "配られたパーツを中央に大きく見せる演出が始まる")
						check(l.part_cards.all(func(c: Control) -> bool: return c.modulate.a < 0.01),
							"演出の間は列のカードを隠しておく")
						var skip := InputEventKey.new()
						skip.keycode = KEY_SPACE
						skip.pressed = true
						l._unhandled_input(skip)
						check(l.showcase == null and l.part_cards.all(func(c: Control) -> bool: return c.modulate.a > 0.99),
							"キーで演出を飛ばすと、全部のカードが列に並ぶ")
					l.part_cards[0].mouse_entered.emit()
					check(l.tooltip.visible, "配られたパーツに合わせると吹き出しが出る")
					var key := InputEventKey.new()
					key.keycode = KEY_2
					key.pressed = true
					var want: String = l.perk_cards[1].perk_id
					var before: int = me.perks.size()
					check(l.confirm_button.disabled, "選ぶ前は決定できない")
					for pc: Variant in l.perk_cards:
						check(not pc.button_pressed, "最初はどのパークも選ばれていない")
					l.perk_cards[0].button_pressed = true  # 1枚目を押したのと同じ
					check(l.selected_perk == l.perk_cards[0].perk_id and me.perks.size() == before, "押すと選ばれるが、まだ確定しない")
					l._unhandled_input(key)
					check(l.selected_perk == want and l.perk_cards[1].button_pressed and not l.perk_cards[0].button_pressed,
						"2キーで2枚目に選び直せる（金枠は1枚だけ）")
					check(me.perks.size() == before, "キーでもまだ確定しない")
					check_eq(l.confirm(), "", "決定で確定できる")
					check(me.perks.size() == before + 1 and me.perks[me.perks.size() - 1] == want, "選んだパークが確定する")
				else:
					l.pick(me.perk_choices[0])
		await _frame()
	check(saw_lose, "負けたラウンドの結果を確かめた")
	check(saw_loot, "パーク選びを確かめた")
	var f: Node = main.screen
	check(_is(f, FinalScreen), "最終順位の画面")
	check_eq(f.podium_robots.size(), 3, "表彰台に3体")
	check_eq(f.ranking_labels.size(), main.session.players.size(), "全員の順位が並ぶ")
	check(f.headline.text.contains("%d位" % main.session.get_player(0).place), "自分の順位が出る")
	main.queue_free()
	await _frame()


## スクラップの画面：組み立ての整備（解体・再抽選の結果の板）、パーク選びの解体と引き直し、使えないラウンドの表示
func test_scrap_screens() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	main.start_game(777)
	await _frame()
	var s: Variant = main.session
	s.finish_draft()
	await _frame()
	var g: Node = main.screen
	check(_is(g, GarageScreen), "組み立ての画面")
	check(g.scrap_label.text.contains("ラウンド目から"), "使えないラウンドは、使えるラウンドを出す")
	for uid: Variant in g.rows:
		check(not g.rows[uid]["scrap"].visible and not g.rows[uid]["reroll"].visible, "使えないラウンドはボタンを出さない")
	var guard: int = 0
	while guard < 200 and not (s.phase == "build" and s.scrap_unlocked()):
		guard += 1
		s.get_player(0).health = 1000.0
		match s.phase:
			"build": s.finish_build()
			"battle": s.run_battles_to_end()
			"round_result": s.finish_round_result()
			"loot": s.finish_loot()
		await _frame()
	g = main.screen
	check(_is(g, GarageScreen) and s.scrap_unlocked(), "使えるラウンドの組み立て")
	var me: Variant = s.get_player(0)
	me.scrap = 7
	await _frame()
	check(g.scrap_label.text.contains("7"), "スクラップの量が出る")
	# 解体：チェックを外していて、機体にも付けていないパーツ
	var target: int = -1
	for uid: Variant in g.rows:
		if g.rows[uid]["scrap"].visible:
			target = int(uid)
			break
	check(target >= 0, "解体のボタンがあるパーツがある")
	var before: int = me.scrap
	g.rows[target]["scrap"].pressed.emit()
	await _frame()
	check(me.find_part(target) == null and me.scrap > before, "解体するとスクラップが増える")
	check(not g.rows.has(target), "解体したパーツの行は消える")
	# 再抽選：使っているパーツ。結果の板で新しい性能を選ぶ
	var frame_uid: int = me.build.frame.uid
	check(g.rows[frame_uid]["reroll"].visible and not g.rows[frame_uid]["scrap"].visible, "使っているパーツには再抽選のボタン")
	g.rows[frame_uid]["reroll"].pressed.emit()
	await _frame()
	check(g.reroll_overlay.visible, "再抽選すると結果の板が出る")
	var new_stats: Dictionary = me.pending_reroll["stats"].duplicate()
	g.resolve_reroll(true)
	await _frame()
	check(not g.reroll_overlay.visible, "選ぶと板が消える")
	for k: Variant in new_stats:
		check_eq(me.build.frame.stats[str(k)], float(new_stats[k]), "新しい性能になる（%s）" % str(k))
	# パーク選び
	s.finish_build()
	s.run_battles_to_end()
	me.health = 1000.0
	await _frame()
	s.finish_round_result()
	await _frame()
	var l: Node = main.screen
	check(_is(l, LootScreen), "パーク選びの画面")
	me.scrap = 5
	await _frame()
	var card_count: int = l.part_cards.size()
	var first_uid: int = l.part_cards[0].part.uid
	l.scrap_buttons[first_uid].pressed.emit()
	await _frame()
	check_eq(l.part_cards.size(), card_count - 1, "配られたパーツを解体するとカードが消える")
	check(me.find_part(first_uid) == null, "手持ちからも消える")
	l.perk_cards[0].button_pressed = true
	var used: int = me.perk_rerolls_used
	l.reroll_perks_button.pressed.emit()
	await _frame()
	check_eq(me.perk_rerolls_used, used + 1, "引き直せる")
	check(l.selected_perk.is_empty() and l.confirm_button.disabled, "引き直すと選んでいたパークは外れる")
	check_eq(l.perk_cards.size(), me.perk_choices.size(), "新しい候補のカードが並ぶ")
	for i: int in me.perk_choices.size():
		check_eq(l.perk_cards[i].perk_id, me.perk_choices[i], "カードは新しい候補（%d）" % i)
	main.queue_free()
	await _frame()


## 長い文が枠や画面からはみ出さない：組み立て画面の下の帯（説明がいちばん長い組み合わせ）と、配られたパーツのカードのステータス
func test_long_texts_stay_inside() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://view/main.tscn").instantiate()
	main.use_llm = false
	tree.root.add_child(main)
	await _frame()
	main.start_game(777)
	await _frame()
	var offer: Dictionary = main.session.draft_offer
	for kind: String in ["frame", "weapon", "skill"]:
		main.screen.select(kind, offer[kind][0].uid)
	main.screen.confirm()
	await _frame()
	var g: Node = main.screen
	check(_is(g, GarageScreen), "組み立ての画面")
	var me: Variant = main.session.get_player(0)
	var rng := Rng.new(5)
	var uids: Array[int] = []
	var ids: Array[String] = ["frame_heavy", "weapon_drill", "weapon_harpoon", "skill_shockwave"]
	for i: int in ids.size():
		var part: Variant = Loot.roll_part(main.data.get_part(ids[i]), rng, 9000 + i)
		me.hand.append(part)
		uids.append(part.uid)
	g.set_selection(uids[0], [uids[1], uids[2]], [uids[3]])
	g._build_sections()
	g._update_info()
	await _frame()
	_check_fits(g, "組み立ての画面（説明の長いハープーンガンを付けたとき）")
	# 配られたパーツのカード：比べる印が付いてステータスが長くなっても、カードの中に収まり、右下の札に重ならない
	var holder := Control.new()
	tree.root.add_child(holder)
	for def: Variant in main.data.parts:
		var def_id: String = def.id
		var p: Variant = Loot.roll_part(def, rng, 9500)
		var other: Variant = Loot.roll_part(def, rng, 9501)
		var card: Variant = PartCard.new()
		holder.add_child(card)
		card.setup(main.data, p, null, "NEW", other)
		card.size = PartCard.CARD_SIZE
		await _frame()
		var card_r := Rect2(Vector2.ZERO, card.size)
		var sl: RichTextLabel = card.stats_label
		var stats_r := Rect2(sl.position + sl.get_parent().position, Vector2(sl.get_content_width(), sl.get_content_height()))
		check(card_r.encloses(stats_r), "配られたパーツのカードのステータスが枠に収まる（%s）" % def_id)
		check(not stats_r.intersects(card._mark.get_rect()), "ステータスが右下の札に重ならない（%s）" % def_id)
		card.queue_free()
	holder.queue_free()
	main.queue_free()
	await _frame()
