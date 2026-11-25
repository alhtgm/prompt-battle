# パーツ選び画面：矢印で送る選び方と機体の見本 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** パーツ選び画面を、種類ごとの◀▶で送る段と、右側の回る機体＋性能一覧に作り替える。

**Architecture:** 1種類分の段を `PartCarousel`、右側を `BuildPreview` として部品にし、`draft_screen.gd` はそれらを並べて `picks` を持ち、操作は今までどおり `MatchSession.draft_pick / finish_draft` だけを通す。

**Tech Stack:** Godot 4.5.1 / GDScript（型注釈つき）

**Spec:** `docs/superpowers/specs/2026-11-25-draft-carousel-design.md`

## Global Constraints
- view/ は状態を読んで描くだけ。操作は MatchSession のメソッドを通す
- 見た目の数値（カードの大きさ・送る秒数・見本の大きさとカメラ）は view/look.gd に置く
- 各ファイルの先頭に役割のコメント、型注釈を付ける
- テスト：`godot --headless --path . -s tests/run_all.gd` が全部通る

## Review Focus
- 5枚目で▶を押すと1枚目に戻る（輪になる）／1枚目で◀は5枚目
- スキル0の戦車フレームを選んだとき、見本にスキルが付かず、一覧に「付けられない」と出る
- 同じ方向に素早く何度も送っても、選択とカードの位置がずれない（動きの途中で次の送りが来る）
- 決定後（通信対戦の待ち）でも画面が壊れない
- 開いている段は常に1つだけ

---

### Task 1: 段の部品 PartCarousel と右の見本 BuildPreview
**Files:**
- Create: `view/draft/part_carousel.gd`, `view/draft/build_preview.gd`
- Modify: `view/draft/part_tooltip.gd`（ステータスの行を作る処理を static にして共用）, `view/look.gd`（DRAFT_* の値）

**Interfaces（Produces）:**
- `PartCarousel extends VBoxContainer`
  - `signal picked(kind: String, uid: int)` / `signal activated(kind: String)`
  - `setup(data: GameData, kind: String, parts: Array) -> void`、`step(dir: int) -> void`、`select_uid(uid: int) -> void`、`set_expanded(on: bool) -> void`
  - `var index: int`、`var expanded: bool`、`var header: Button`、`var cards: Array[Button]`、`var prev_button / next_button: Button`、`func current() -> PartInstance`
- `BuildPreview extends VBoxContainer`
  - `setup(data: GameData) -> void`、`show_parts(picks: Dictionary) -> void`（kind → PartInstance）
  - `var preview: Showroom`、`var build: Build`、`var name_labels: Dictionary`、`var note_labels: Dictionary`
- `PartTooltip.add_stat_rows(grid: GridContainer, data: GameData, p: PartInstance, font_px: int) -> void`（static）

### Task 2: draft_screen を作り直し、テストを書き直す
**Files:** Modify `view/draft/draft_screen.gd`, `tests/test_ui_flow.gd`
- `draft_screen`：`carousels: Dictionary`、`active_kind: String`、`build_preview: BuildPreview`、`activate(kind)`、`move(dir)`、`switch_section(dir)`、`select(kind, uid)`、`confirm()`、`_input` で ←→↑↓
- テスト `test_draft_screen_carousel_preview_and_back`：
  - 最初から各種類の1枚目が選ばれ、決定できる状態
  - 開いている段はフレームだけ、`activate("weapon")` で武器だけ開く（見出しの mouse_entered でも）
  - ▶で次、1枚目で◀なら最後（輪）、選択と見出しの文字が変わる
  - 見本の `build` が選んだフレーム・武器・スキル（枠0のときは付かず、注意書きが出る）
  - 右キーの入力で送れる、下キーで次の段が開く
  - 戻るボタンでタイトル（既存の確かめを残す）
- 通しのテストの「全部選ぶ前は決定できない」は「最初から決定できる」に変える
