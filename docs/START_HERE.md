# プロンプトバトル 開発スタート用ファイル（Claude Code 向け）

このファイル1つに、開発に必要な情報がすべて入っている。Claude Code は次の手順で準備すること。

## 最初にやること

1. 下の「ファイル一覧」にある各ファイルを、書かれたパスにそのまま作る（中身は区切り線の間の内容を一字一句そのまま使う）
2. 作り終えたら、このファイル自体は `docs/START_HERE.md` に移す
3. `CLAUDE.md` の「Godot 4.x.x」の行について、使うGodotのバージョンを人間に確認して書き換える
4. `git init`（まだなら）と `git lfs install` を行い、最初のコミットを作る
5. ここで一度止まり、作ったファイルの一覧を報告する。実装（設計書の段階1）は人間の指示を待ってから始める

## ファイル一覧

| パス | 中身 |
| --- | --- |
| `CLAUDE.md` | 作業ルール（毎回読む） |
| `docs/game-rules.md` | ゲームのルール（企画メモ） |
| `docs/design.md` | 設計書（骨組みの作り方） |
| `docs/reference/demo-sim.js` | ブラウザ試作デモの戦闘計算（参考用） |
| `.gitignore` | Gitに入れないもの |
| `.gitattributes` | 改行と Git LFS の設定 |

各ファイルは `<<<<< FILE: パス` の行から `>>>>> END FILE` の行までが中身。この2行自体は含めない。

<<<<< FILE: CLAUDE.md
# プロンプトバトル（仮）

プレイヤーが配られたパーツで機体を組み、プロンプトを書くと、操縦士エージェント（小さいLLM）が試合中に考えて機体を操縦する、6人ラウンド制サバイバルの3D対戦ゲーム。Godot 4で作る。

## 先に読む文書

作業を始める前に、必ず次の文書を読むこと。

- `docs/game-rules.md`：企画メモ。ゲームのルール、パーツ、観戦、技術構成
- `docs/design.md`：設計書。骨組みの作り方、データの形、フォルダ構成、実装の順番、仮置きした値
- `docs/reference/demo-sim.js`：ブラウザで作った試作デモの戦闘計算。方針（インテント）ごとの動き方や衝突の処理の参考にする。そのまま移植する必要はない

文書とコードが食い違う場合は文書を優先し、食い違いを報告すること。

## 技術

- Godot 4.x.x（← チームで使うバージョンをここに書く。全員同じバージョンを使う）
- 言語は GDScript
- 描画方式は Compatibility（古いPCでも動かすため）

## 進め方

- `docs/design.md` の「実装の順番」を1段階ずつ進める
- 各段階の「完成の目安」を自動テストで確かめてから、次の段階に進む
- 1つの段階が終わるごとに止まり、できたこと・確かめたこと・気になったことを報告する
- 設計書と違う作り方をしたくなったら、作る前に相談する

## 設計上のルール（必ず守る）

- `core/` と `agent/` のスクリプトはシーンやノードに依存させない（`get_tree()`、`Input`、ノードの参照を使わない）。画面なしで動かせることが前提
- `view/` は試合の状態を読んで描くだけにする。状態を直接書き換えず、操作は `MatchSession` のメソッドを通す
- 数値（パーツの性能、ダメージの係数、制限時間など）はコードに直書きせず、`data/` のファイルに置く
- 乱数は `core/rng.gd` を通し、試合ごとの種から作る。`randf()` や `randi()` を直接使わない
- バトルの計算は 1/60 秒の固定刻みで行い、描画の速さに左右されないようにする
- 操縦エージェントは `agent/agent_brain.gd` の共通の入口（`begin` / `request` / `poll`）だけでバトルとやり取りする。答えを待たずに試合を進める
- 未決定の値は `docs/design.md` の「仮置きした値」に従い、勝手に変えない

## テスト

- 自動テストは `tests/` に置き、画面なしの Godot で実行できるようにする
- 実行コマンド：`godot --headless --path . -s tests/run_all.gd`（最初の段階でこの形で作る）
- 変更をコミットする前に、全テストが通ることを確かめる
- 最低限確かめること：試合が必ず決着する、同じ種なら同じ結果になる、数値が壊れない（NaNや範囲外にならない）

## コードの書き方

- GDScript には型注釈を付ける
- 各ファイルの先頭に、そのファイルの役割を1〜2行のコメントで書く
- 変数名・関数名は英語、コメントは日本語でよい

## チーム開発のルール

- `main` に直接プッシュしない。`feature/<内容>` のブランチを作り、プルリクエストで取り込む
- `.godot/` フォルダはコミットしない
- 3Dモデル・画像・音などの大きいファイル（`assets/`）は Git LFS で管理する
- 同じシーン（`.tscn`）を複数人で同時に大きく作り替えない。触る前に担当者を確認する
>>>>> END FILE

<<<<< FILE: docs/game-rules.md
# プロンプトバトル 企画メモ（ゲームのルール）

## 概要

プロンプトバトルは、CATS（Crash Arena Turbo Stars）風の3D対戦ゲーム。配られたパーツで機体を組み、プロンプトを書くと、AI操縦士がそのプロンプトをもとに試合中に考えて機体を操縦する。

**一言で言うと：** 6人のロビーで「組み立て → 1対1の自動バトル」を何ラウンドも繰り返し、体力を削り合って最後の1人を決める生き残り戦。ラウンドの合間に新しいパーツとパークを手に入れ、機体とプロンプトが試合の中で育っていく。

トーナメント（負けたら即終了）でも総当たり（勝ち数を競う）でもない、**ライフ制ラウンド・サバイバル**形式。

## 対戦方式

### 基本ルール

- 1試合は6人。ランダムマッチングまたはフレンド招待。
- 各プレイヤーは体力100でスタートする。
- 毎ラウンド、生き残っている人をシャッフルして1対1のペアを作り、3試合を同時に行う（同じ相手と連続で当たりにくくする）。
- 負けた人の体力が減る。減る量は「負けた人の現在の順位（残り体力での順位）による分」と「どれだけ差をつけられて負けたかによる分」の合計で決める。
- 体力が0になった人から脱落。順位は脱落した順で決まる（最後まで残った人が1位）。
- 負けてもすぐには終わらないので、序盤の負けを取り返せる。

### 試合開始時のパーツ選び

フレーム・武器・スキルをそれぞれランダムに5つずつ選び、全員に同じものを見せる。各プレイヤーはその中から、種類ごとに1つずつ選ぶ。

### 1ラウンドの流れ

1. **組み立て・プロンプト調整（30〜45秒）：** 手持ちのパーツで機体を組み、操縦士エージェントへのプロンプトを書き直す。プロンプトは毎ラウンド変更できる。
2. **1対1のバトル（60〜90秒）：** 操縦士エージェントがプロンプトをもとに、戦況を見ながらリアルタイムで機体を操縦する。試合中にプロンプトは追加できない。
3. **ダメージ処理：** 負けた側の体力が減り、0になったら脱落。
4. **パーツ配布：** 各プレイヤーにパーツが5つ配られる（フレーム・武器・スキルが各1つ以上）。中身はプレイヤーごとに異なる。
5. **パーク選択：** HP+5%などのステータス上昇（パーク）を選ぶ。

### 比較表

|  | トーナメント | 総当たり | 本作の方式 |
| --- | --- | --- | --- |
| 負けたら | 即終了 | 次の試合へ | 体力が減るだけ（0で脱落） |
| 順位の決め方 | 勝ち上がった段階 | 勝ち数 | 脱落した順 |
| 対戦相手 | 組み合わせ表で固定 | 全員と1回ずつ | ラウンドごとにランダム |

## パーツ

パーツはフレーム・武器・スキルの3種類。同じパーツでも、出てくるたびにステータスがランダムに決まる。

| 種類 | ランダムに決まるステータス |
| --- | --- |
| フレーム | HP、移動速度の低下（デバフ） |
| 武器 | ダメージ、ノックバック |
| スキル | スキルの性能 |

フレームによって、付けられる武器とスキルの数が違う。

## ローグライク強化

毎ラウンドの終わりに、新しいパーツ5つ（プレイヤーごとに違う）を受け取り、パーク（HP+5%などのステータス上昇）を選ぶ。手に入れたパーツとパークで、試合の中で機体が育っていく。

### パークの案

- **機体の強化：** パーツ性能アップ（車輪の速度+20%、装甲+1段階など）、パーツを置ける枠の追加。
- **操縦士の強化：** AIの性格や癖を変える特性。「操縦士はあえて頭が悪い」設定と相性がよい。例：被弾すると一瞬キレて突っ込む／段差を見つけるのがうまくなる／指示を1つだけ忘れなくなる。
- **プロンプトの強化：** 文字数上限アップ、「必ず守らせる命令」を1行書ける枠など。本作ならではの目玉。

### 設計のコツ

- **組み合わせで化ける強化を混ぜる：** 例：「電撃パーツ」＋「接近すると発動」の操縦士特性。取り方で毎回ビルドが変わり、繰り返し遊びたくなる。
- **ラウンド後の配布はプレイヤーごとに違う：** 開始時は全員が同じ候補から選ぶので公平で、ラウンド後のパーツ配布とパークの違いで個性が出る。
- **負けている人に少し良い選択肢を：** 体力が少ないほどレア強化が出やすくすると、一方的な展開を防げる。
- **何かを手放す強化を入れる：** 例：「攻撃力+50%、ただしプロンプト文字数−20」。悩む楽しさが生まれる。

## この形式の強み

- **プロンプトの扱いが決まる：** 試合中には追加せず、ラウンド間だけ書き直せる形にすると、「負けた理由を見て直す」ことがそのまま上達の手応えになる。
- **人数が奇数になっても困らない：** 生き残りが奇数のときは、誰かの「機体＋プロンプトの記録」をCPUとして戦わせればよい。操縦がAIなので、本人がいなくても同じ動きを再現できる。

## 懸念点と対策

- **試合時間が長くなる：** 6人で体力制にすると、6〜8ラウンドで12〜16分ほどかかる見込み。→ 4人ロビーにする／ダメージ量を大きくする。
- **操縦エージェントの処理の重さ：** 自分の試合と裏の試合でエージェントが同時に動き続ける。→ 各プレイヤーのPCで動かすのは自分の機体のエージェントだけにし、考える間隔を全員同じ2秒にする。
- **早く脱落した人が暇になる：** → 脱落後もほかの試合を観戦できるようにする。
- **準備時間の膨張：** パーク選択と組み立て・プロンプト書き直しが重なると間延びする。→ 制限時間を設ける。

## 観戦

自分の試合はエージェントが操縦するので、プレイヤーは試合中ずっと見守る。脱落した人に加えて、対戦していない外部の人も試合を観戦できるようにする。

見られる範囲は、見る人によって変える。

| 見る人 | 機体 | プロンプト |
| --- | --- | --- |
| 同じマッチで生き残っている人 | 見える | 見えない |
| 脱落した人 | 見える | 見える |
| 外部の観戦者 | 見える | 見える |

生き残っている人には、相手の機体から作戦を読む駆け引きを残し、プロンプトの中身は隠す。脱落者と外部の観戦者は、「この指示だからこう動いた」まで楽しめる。

カジュアル寄りのゲームなので、外部観戦や脱落した人を通じてプロンプトが生き残っている人に伝わることへの、厳しい対策（配信の遅延など）はしない。

### 観戦で決めること

- 同時に進む3試合を、カメラを切り替えて見られるようにするか（検討中）

## 技術構成

Godot 4でゲーム本体と対戦サーバーを作る。操縦エージェントは各プレイヤーのPCで小さいLLMを動かし、試合中に2秒おきに考えて機体を動かす。AIの継続費用がかからないので、サブスクにせず買い切りにできる。見た目はMike Klubnikaの作品（Buckshot Rouletteなど）のような、薄暗く汚れた質感を目指す。

選んだ基準は4つ：Claude Codeでできるだけ作れる、目標の質感を出せる、どんなPCでも動く、AIの継続費用がかからない。

| 担当 | 技術 | 理由 |
| --- | --- | --- |
| ゲーム本体 | Godot 4（GDScript）、軽い描画方式（Compatibility） | アプリとして書き出せる。テキストで書けてClaude Codeで作りやすい。古いPCでも動く |
| 見た目 | 低解像度で描いて拡大、暗い照明と限られた光、粗いテクスチャ、ノイズや霧の画面効果 | Mike Klubnika風の薄汚れた質感。処理が軽く、AI生成モデルの粗も目立ちにくい |
| 対戦サーバー | 画面なしのGodot。AIは動かさず、試合の進行と物理だけを担当 | 試合の結果はサーバーで決める。公開時の置き場所は未定（Edgegapなど） |
| 物理 | Godot内蔵の物理 | 押し合い・吹き飛ばし・穴落ち |
| 操縦エージェント | 各プレイヤーのPCのCPUで小さいLLMを動かす（llama.cppをGodotに組み込む）。全員2秒おきと出来事が起きたときに戦況を読んで方針を決め、方針の間はゲーム側が機体を動かす | AIの継続費用がゼロ。試合中にエージェントが考えて動かすコンセプトを保てる |
| モデル候補 | Qwen3.5-0.8B・2B（Apache 2.0）。比較用にLFM2.5-1.2B-JP | CPUだけで動き、日本語のプロンプトを扱える |
| 3Dモデル（背景・小物） | TRELLIS.2（DGX）で生成し、ポリゴンとテクスチャを減らしてそのまま使う | 動かない小物はAI生成が得意。量を作れる |
| 3Dモデル（機体パーツ） | TRELLIS.2で下地を作り、Blenderで汚しや機械部品を足して仕上げる | 質感の印象を決める部分なので、人の手を入れる |
| 開発 | Claude Code、GitHub、DGX（モデルの試験・追加学習、3Dモデル生成） |  |

### 操縦エージェントの工夫

- 変わらない部分（ルールとプレイヤーのプロンプト）は最初に一度だけ読ませ、毎回は変わった戦況だけを渡す
- 出力は「行動の番号と目標」の短い形に限り、llama.cppの出力形式の強制で崩れないようにする
- 考える間隔は全員同じにして、PCの性能差で有利不利が出ないようにする
- 小さいモデルの取り違えは「少し頭が悪い操縦士」の味として活かす。足りなければDGXでこのゲーム専用に追加学習する

### 作業の分担

- **AI生成（TRELLIS.2）：** 3Dモデルの下地と、背景・小物
- **人：** 入力画像の画風・角度・背景をそろえる、生成結果を選ぶ、機体パーツの仕上げ（Blender）、パーツの取り付け位置を決める
- **Claude Code：** ゲームのコード、シェーダーと画面効果、エージェントの組み込み、モデル変換の自動化スクリプト

### 技術面でまだ決めていないこと

- 使うモデル（候補を測って決める）
- 最低動作環境（目安は4コアCPU・メモリ8GB程度。測ってから決める）
- 対戦サーバーをどこで動かすか
- 3Dモデル1つあたりのポリゴン数とテクスチャの大きさの上限

## 未決定事項

- [ ] 1試合の長さ：5〜10分を守るか、15分程度まで許容するか（ロビー人数・ダメージ量に影響）
- [ ] ダメージ計算の具体的な値：順位による分と、負けた差による分（差を何で測るか）
- [ ] 開始時の選出で、同じパーツを複数人が選べるか（取り合いにするか）
- [ ] パーツのステータスの振れ幅と、フレームごとの武器・スキルの数
- [ ] 手持ちパーツの上限と、使わないパーツの扱い
- [ ] パークの選択肢の数と種類
- [ ] 強化の扱い：その試合の中だけで毎試合リセット（ローグライク）か、試合をまたいで残る成長要素もあるか（ローグライト）
- [ ] 対人戦とCPU戦の両方を用意するか

未決定の項目は、`docs/design.md` の「仮置きした値」で作り始める。
>>>>> END FILE

<<<<< FILE: docs/design.md
# プロンプトバトル 設計書（骨組み）

## 概要

骨組みのゴールは、「プレイヤー1人＋CPU5人の6人戦」が1台のPCだけで最初から最後まで通して遊べること。パーツ選び→組み立てとプロンプト→エージェントが操縦するバトル→ダメージ→配布とパーク→次のラウンド、を最後の1人が決まるまで回す。見た目は箱や円柱の仮のものでよい。

**骨組みに含めるもの**

- 6人のラウンド制サバイバル（体力100、脱落、順位）
- フレーム・武器・スキルの3種類のパーツと、出るたびに変わるステータス
- 開始時のパーツ選び、ラウンド後の配布とパーク
- 操縦エージェントが2秒おきに方針を決め、ゲームがその方針で機体を動かす仕組み
- 自分の試合の観戦（ほかの2試合は画面に出さず裏で計算する）

**骨組みに含めないもの**：通信対戦、外部観戦、本番の3Dモデルと画面効果、本番のLLM（最初はルールで動く仮の頭脳で代用する）

**設計の方針**

1. **試合の計算と画面を分ける。** 試合の計算は画面を一切知らない純粋なコードにし、画面は計算結果を読んで描くだけにする。後で計算部分だけを画面なしのサーバーに移せば、通信対戦になる。
2. **操縦エージェントは差し替えできる部品にする。** 「戦況を受け取って方針を返す」という入出力だけを決め、中身は仮の頭脳→本番のLLMと入れ替える。
3. **数値はコードに書かず、データファイルに分ける。** パーツの性能やダメージの式は未決定が多いので、調整しやすくしておく。
4. **同じ種からは同じ結果になるようにする。** 乱数は試合ごとの種から作り、バグの再現と自動テストをしやすくする。

## 全体構成

4つの層に分ける。

```text
┌──────────── 画面（view/）─────────────┐
│ Godotのシーン。状態を読んで描くだけ        │
└──────┬─────────────────▲───────────┘
       │ 操作                │ 状態とイベント
       ▼                    │
┌ ─ ─ ─ ─ 試合の計算（core/）─ ─ ─ ─ ─ ┐  ← 点線の範囲は、そのまま
│ MatchSession / BattleSim など        │     画面なしのサーバーへ移せる
└ ─ ─┬─────────────────▲─ ─ ─ ─ ─ ─ ┘
     │ 観測（戦況）          │ 方針（インテント）
     ▼                    │
┌──── 操縦エージェント（agent/）────────┐
│ AgentBrain の下で MockBrain / LlmBrain │
│ / ReplayBrain を差し替える             │
└────────────────────────────────┘

データ（data/）：parts.json / perks.json / rules.json を core が読む
```

画面と試合の計算は「操作」と「状態とイベント」だけでつながり、エージェントは観測を受けて方針を返すだけにする。

## 画面と状態の流れ

```text
タイトル
  → 開始時のパーツ選び（全員同じ候補から種類ごとに1つ）
  → [ラウンド開始]
     組み立てとプロンプト入力（45秒）
  → バトル（自分の試合を観戦。ほかの2試合は裏で計算）
  → ラウンド結果（ダメージ、脱落）
  → 生き残りが1人？ ─はい→ 最終順位
       │いいえ
       ▼
     自分は生きている？ ─いいえ→ 観戦だけ続けて次のバトルへ
       │はい
       ▼
     パーツ配布（5つ）とパーク選択 → [次のラウンド開始] へ戻る
```

1つの段階が、試合（MatchSession）の1つの段階にあたる。画面は今の段階を読んで対応する画面を出すだけ。プレイヤーが先に脱落した場合は、組み立てとパーク選択を飛ばして観戦だけを続け、最終順位まで進む。

## データの形

データは「型（どんなパーツがあるか）」と「実物（配られた1個1個）」を分ける。同じパーツでも出るたびにステータスが変わるので、実物は「どの型か」と「その回のステータス」を持つ。

| データ | 持つ情報 | 備考 |
| --- | --- | --- |
| パーツの型（PartDef） | ID、名前、種類（フレーム／武器／スキル）、各ステータスの最小値と最大値、見た目（モデルの場所） | データファイルに書く。フレームは武器とスキルの枚数も持つ |
| パーツの実物（PartInstance） | 固有ID、型のID、その回のステータス | 配られるときに範囲内で抽選する |
| ステータスの中身 | フレーム：HP、移動速度の低下。武器：ダメージ、ノックバック。スキル：スキルごとの性能値 | `docs/game-rules.md` の「パーツ」の節のとおり |
| 機体（Build） | フレーム1つ、武器のリスト、スキルのリスト | 武器とスキルの数はフレームの枚数まで |
| パーク（PerkDef） | ID、名前、効果（例：HP+5%） | データファイルに書く |
| プレイヤー（Player） | ID、名前、人間かCPUか、体力（初期100）、手持ちパーツ、取ったパーク、今の機体、今のプロンプト、生存か、順位 | CPUも同じ形。違うのはプロンプトと組み立てを自動で決めることだけ |
| 試合（MatchSession） | 6人のプレイヤー、今のラウンド番号、今の段階、過去の対戦履歴、乱数の種 | ゲーム全体の状態はここに集める |
| ラウンド（Round） | ペアの一覧、各バトルの結果、各人へのダメージ | 終わったら履歴に残す |
| バトルの状態（BattleState） | 経過時間、機体2体の位置・向き・速度・HP・状態、弾、今の方針 | 1刻みごとに更新。画面はこれを読んで描く |
| バトルの結果（BattleResult） | 勝った人、決着のつき方（破壊／穴／時間切れ）、残りHPの割合、与えたダメージ | ダメージ計算の「差」に使う |

画面に届ける瞬間的な出来事（命中、穴に落ちた、方針を変えたなど）は、状態とは別に「イベント」として流す。実況や火花の演出はイベントを見て出す。

## バトルの仕組み

バトルは毎秒60回の固定刻みで計算し、画面の描画速度とは切り離す。操縦は2段構えで、エージェントが「方針（インテント）」を決め、ゲーム側の「実行役」がその方針を毎刻みのハンドルとアクセルに直す。

**1刻みでやること（この順番）**

1. 考える時刻かどうかを確かめる。前回から2秒たったか、考え直す切っ掛けになる出来事が起きていれば、各機体のエージェントに戦況を渡す
2. エージェントの答えが届いていれば、その機体の方針を入れ替える。届いていなければ前の方針を続ける
3. 実行役が、今の方針から目標地点と向きを決め、ハンドル・アクセル・武器・スキルの使い方を出す
4. 物理を進める（移動、衝突、押し合い、吹き飛ばし）
5. 武器とスキルの当たり判定とダメージを処理する
6. 穴、修理ステーション、場外を処理する
7. 決着したかを判定し、この刻みで起きた出来事をイベントとして流す

**考え直す切っ掛けになる出来事**：大きく被弾した、ひっくり返された、弾が切れた、相手が穴の近くに来た、HPが半分を切った。ただし連続して呼ばないよう、前回から最低0.5秒は空ける。

**決着のつき方**

- 相手のHPが0になる（破壊）
- 相手が穴に落ちる
- 制限時間（仮に75秒）が終わる。残りHPの割合が高い方の勝ち。ほぼ同じなら引き分け

自分の試合は画面に出して実時間で進める。ほかの2試合は同じ計算を画面なしで回す。仮の頭脳なら一瞬で終わるが、本番のLLMでは実時間でしか考えられないので、最初から「3試合とも実時間で並んで進む」前提で作る。

## 操縦エージェントの入出力

エージェントは「戦況（観測）を受け取り、方針を返す」だけの部品にする。中身を仮の頭脳から本番のLLMに入れ替えても、バトル側は何も変えない。

**共通の入口（AgentBrain）**

- `begin(prompt, build, rules)`：ラウンドの始めに1回だけ呼ぶ。プレイヤーのプロンプト、機体、ルール説明など、試合中に変わらないものを渡す
- `request(observation)`：考えるたびに呼ぶ。すぐに戻り、答えは後から届く（非同期）
- `poll()`：答えが届いていれば方針を返し、まだなら空を返す

答えを待たずに試合を進めるのが大事。遅いPCで答えが間に合わなくても、機体は前の方針で動き続ける。

**渡す戦況の例**（毎回はこの程度の小ささに収める）

```json
{"t": 31.5, "me": {"hp": 62, "pos": [-4, 3], "facing": 90, "ammo": 12, "stunned": false},
 "enemy": {"hp": 80, "dist": 6.2, "dir": "前方やや右", "near_pit": true, "behind_me": false},
 "repair": {"dist": 9.0, "left": 30}, "events": ["被弾:ハンマー:18"]}
```

**返す方針の例**

```json
{"intent": "push_to_pit", "skill": null, "say": "穴に寄せるっす！"}
```

**方針の種類（仮）**

| 方針 | 実行役がやること |
| --- | --- |
| charge | 相手にまっすぐ突っ込む |
| flank | 相手の後ろに回り込んでから攻める |
| keep_distance | 相手を向いたまま距離を保つ（射撃向き） |
| retreat | 相手から逃げる |
| push_to_pit | 相手をはさんで穴の反対側に回り、穴へ押す |
| go_repair | 修理ステーションへ行って止まる |
| circle | 相手の周りを回る |
| hold | その場で相手を向いて待つ |

`skill` はその場で使うスキルの番号、`say` は操縦士の一言（実況や吹き出しに使う）。種類はバトルを作りながら増減させる。

**頭脳の種類**

| 頭脳 | 中身 | 使う場面 |
| --- | --- | --- |
| 仮の頭脳（MockBrain） | プロンプトのキーワードと戦況から、決まった規則で方針を選ぶ。わざと0.3〜1.5秒遅らせて答え、本番の遅さを真似る | 骨組みの開発中。CPUプレイヤー |
| 本番の頭脳（LlmBrain） | llama.cppで小さいLLMを動かす。変わらない部分は最初に読ませておき、出力は方針の形に強制する | 骨組みの後で差し替える |
| 記録の再生（ReplayBrain） | 保存しておいた他人の機体とプロンプトで動かす | 生き残りが奇数のときの相手（後で足す） |

本番の頭脳が壊れた答えを返したときは、前の方針を続け、操縦士に「えっと…」と言わせる。失敗もポンコツらしさとして見せる。

## ラウンドの進行

ラウンドの進行はすべて「試合（MatchSession）」が受け持つ。画面は「今はどの段階か」を読んで対応する画面を出し、プレイヤーの操作（パーツを選んだ、プロンプトを確定したなど）を試合に伝えるだけにする。

**開始時のパーツ選び**：フレーム・武器・スキルをそれぞれ5つずつ抽選し、全員に同じものを見せる。各自が種類ごとに1つずつ選ぶ。骨組みでは同じパーツを複数人が選べる形にしておき、取り合いにするかは後で決める。

**ペア作り**

1. 生き残っている人を並べ替え、直前に当たった相手と組まない組み合わせを乱数で探す
2. そういう組み合わせがなければ、条件を外して組む
3. 生き残りが奇数のときは、余った1人を、脱落した人の最後の機体とプロンプト（記録の再生）と戦わせる。この試合は勝っても負けても、記録側はダメージを受けない

**ダメージ計算**

負けた人のダメージは、`docs/game-rules.md` のとおり「順位による分」と「差による分」の合計にする。具体的な値は未決定なので、仮の式で作ってデータファイルから変えられるようにする。

```text
damage = A × rank + B × margin
```

- rank：負けた人の、残り体力での今の順位（1が最上位）。上位ほど重くするか軽くするかは後で決める
- margin：勝った側の機体の残りHPの割合（0〜1）。大差で負けるほど大きい
- A、Bの仮の値は「仮置きした値」の節を参照

**ラウンド後の配布とパーク**

- 各プレイヤーにパーツを5つ配る。フレーム・武器・スキルを各1つ以上含め、中身は人ごとに変える
- パークを選ばせる（骨組みでは3つの候補から1つ）。パークの効果はその試合の間ずっと積み重なる
- 脱落した人には配らない

**脱落と順位**：体力が0になった人から脱落し、脱落した順に下の順位が決まる。同じラウンドで複数人が脱落したら、残り体力がよりマイナスになった人を下にする。生き残りが1人になったら試合終了。プレイヤーが先に脱落しても、残りのCPU同士の試合を観戦しながら最後まで進める。

## フォルダ構成

「試合の計算（core）」「エージェント（agent）」「画面（view）」をフォルダで分ける。coreとagentはシーンやノードに依存しない純粋なスクリプトにし、viewだけがGodotのシーンを持つ。

```text
prompt-battle/
├─ project.godot
├─ data/                  数値と定義（ここだけ触ればバランス調整できる）
│  ├─ parts.json          パーツの型とステータスの範囲
│  ├─ perks.json          パークの定義
│  └─ rules.json          体力、制限時間、ダメージの係数など
├─ core/                  試合の計算（画面を知らない）
│  ├─ match_session.gd    試合全体の状態と段階の進行
│  ├─ pairing.gd          ペア作り
│  ├─ damage.gd           ダメージ計算
│  ├─ loot.gd             パーツの抽選、配布、パーク候補
│  ├─ battle_sim.gd       バトル1試合の計算（固定刻み）
│  ├─ robot_driver.gd     方針をハンドルとアクセルに直す実行役
│  ├─ observation.gd      エージェントに渡す戦況を作る
│  └─ rng.gd              種から作る乱数
├─ agent/                 操縦エージェント
│  ├─ agent_brain.gd      共通の入口
│  ├─ mock_brain.gd       仮の頭脳
│  ├─ llm_brain.gd        本番の頭脳（骨組みでは中身なし）
│  └─ cpu_planner.gd      CPUプレイヤーの組み立てとプロンプトを決める
├─ view/                  画面（Godotのシーン）
│  ├─ main.tscn           段階に合わせて画面を切り替える
│  ├─ title/              タイトル
│  ├─ draft/              開始時のパーツ選び、配布、パーク選び
│  ├─ garage/             組み立てとプロンプト入力
│  ├─ arena/              3Dのアリーナ、機体の表示、実況
│  └─ results/            ラウンド結果、最終順位
├─ assets/                3Dモデル、音、シェーダー（骨組みでは仮）
└─ tests/                 自動テスト（画面なしで試合を丸ごと回す）
```

`tests/` では、画面なしのGodotでCPU6人の試合を何百回も回し、「必ず決着する」「同じ種なら同じ結果になる」「数値が壊れない」を確かめる。Claude Codeが自分で動作を確かめられるようにするための仕組み。

## 実装の順番

画面より先に試合の計算を作り、自動テストで「CPU6人の試合が最後まで回る」ことを確かめてから、画面をかぶせる。各段階の完成の目安を満たしたら次に進む。

1. **データと乱数**：`data/` の3ファイルと読み込み、種から作る乱数。完成の目安：同じ種で同じパーツが同じステータスで出る
2. **バトル1試合（画面なし）**：固定刻みの計算、実行役、決着判定。頭脳は仮の頭脳。完成の目安：ランダムな機体同士で数百試合回して、必ず決着し、勝ち方が偏りすぎない
3. **ラウンドの進行（画面なし）**：ペア作り、ダメージ、配布、パーク、脱落。完成の目安：CPU6人の試合が最後の1人まで進み、何ラウンドかかるかが測れる
4. **画面の骨組み**：タイトル、パーツ選び、組み立てとプロンプト、結果。完成の目安：プレイヤーが操作して段階が進む（バトルはまだ文字だけでよい）
5. **アリーナの3D表示**：箱の機体、穴、修理ステーション、実況の文字。完成の目安：自分の試合を観戦でき、操縦士の今の方針と一言が見える
6. **通しで遊ぶ**：タイトルから最終順位まで。完成の目安：メンバーが説明なしで1試合遊べる

ここまでで骨組みは完成。次は「本番の頭脳への差し替え」「見た目（照明と画面効果）」「通信対戦」を、それぞれ独立して進められる。

## 仮置きした値

まだ決まっていない項目は、以下の仮の値で作り始める。どれも `data/rules.json` か `data/parts.json` で変えられるようにし、遊んでみて調整する。

| 項目 | 仮の値 | 決まり具合 |
| --- | --- | --- |
| 初期体力 | 100 | 決定 |
| エージェントが考える間隔 | 2秒（出来事のときは追加で考える。ただし前回から最低0.5秒空ける） | 決定（間隔は試験で微調整） |
| バトルの制限時間 | 75秒 | 仮 |
| 組み立てとプロンプトの制限時間 | 45秒 | 仮 |
| プロンプトの文字数 | 120文字 | 仮 |
| ダメージの係数 | A = 2（順位1なら2、6なら12）、B = 20（大差で負けると最大20） | 仮。順位の向きも未定 |
| パーツの型の数 | フレーム6、武器8、スキル6 | 仮（将来は数十種類） |
| ステータスの振れ幅 | 型の基準値の±20% | 仮 |
| フレームの枚数 | 武器1〜3、スキル0〜2 | 仮 |
| 開始時の選出 | 各種類5つ、同じパーツを複数人が選べる | 仮（取り合いにするか未定） |
| ラウンド後の配布 | 5つ、各種類1つ以上 | 決定 |
| パークの候補数 | 3つから1つ | 仮 |
| 手持ちパーツの上限 | なし | 仮 |
| 奇数のときの相手 | 直前に脱落した人の記録 | 仮 |
| 仮の頭脳の応答時間 | 0.3〜1.5秒 | 骨組み専用 |
>>>>> END FILE

<<<<< FILE: docs/reference/demo-sim.js
/* プロンプトバトル デモ：戦闘シミュレーション（描画に依存しない） */
(function (root) {
  'use strict';

  /* 端末やブラウザが違っても計算結果が一致するよう、四則演算と平方根だけで作った関数 */
  var PI = Math.PI, TAU = Math.PI * 2;
  function hyp(a, b) { return Math.sqrt(a * a + b * b); }
  function dsin(x) {
    x = x - TAU * Math.floor(x / TAU + 0.5);
    if (x > PI / 2) x = PI - x; else if (x < -PI / 2) x = -PI - x;
    var x2 = x * x;
    return x * (1 + x2 * (-1 / 6 + x2 * (1 / 120 + x2 * (-1 / 5040 + x2 * (1 / 362880 + x2 * (-1 / 39916800))))));
  }
  function dcos(x) { return dsin(x + PI / 2); }
  function datanUnit(z) {
    var z2 = z * z;
    return z * (0.99997726 + z2 * (-0.33262347 + z2 * (0.19354346 + z2 * (-0.11643287 + z2 * (0.05265332 + z2 * -0.0117212)))));
  }
  function datan2(y, x) {
    if (x === 0 && y === 0) return 0;
    var ax = x < 0 ? -x : x, ay = y < 0 ? -y : y;
    var a = ax >= ay ? datanUnit(ay / ax) : PI / 2 - datanUnit(ax / ay);
    if (x < 0) a = PI - a;
    return y < 0 ? -a : a;
  }
  function makeRng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  var PARTS = {
    // 車体
    light:   { slot: 'body', name: '軽量フレーム', hp: 90,  mass: 0.8, speedMul: 1.2, desc: '軽くて速い。押されやすく、もろい' },
    standard:{ slot: 'body', name: '標準ボディ',   hp: 120, mass: 1.0, speedMul: 1.0, desc: 'くせのない標準型' },
    heavy:   { slot: 'body', name: '重装甲ボディ', hp: 160, mass: 1.5, speedMul: 0.8, desc: '硬くて重い。遅いが押し負けない' },
    // 足回り
    small:   { slot: 'wheels', name: '小径タイヤ', speed: 9.0, turn: 3.2, grip: 0.8, desc: '最速で小回りがきく。踏ん張りは弱い' },
    big:     { slot: 'wheels', name: '大径タイヤ', speed: 7.5, turn: 2.4, grip: 1.0, desc: '速さと踏ん張りのバランス型' },
    tracks:  { slot: 'wheels', name: 'キャタピラ', speed: 5.5, turn: 1.8, grip: 1.6, desc: '遅くて曲がりにくい。押し合いに強い' },
    // 前面パーツ
    drill:   { slot: 'front', name: 'ドリル',   desc: '前で触れている間ずっと削る（毎秒13）' },
    hammer:  { slot: 'front', name: 'ハンマー', desc: '前の相手を1.5秒ごとに叩く（20ダメージ＋吹き飛ばし）' },
    lifter:  { slot: 'front', name: 'リフター', desc: '前の相手をひっくり返して1.6秒動けなくする' },
    bumper:  { slot: 'front', name: 'バンパー', desc: '体当たりの威力と吹き飛ばしが大きい。穴落とし向き' },
    // 上部パーツ
    mg:      { slot: 'top', name: '機関銃',     desc: '正面にしか撃てない。射程15、弾150発' },
    rocket:  { slot: 'top', name: 'ロケット',   desc: '正面に発射。17ダメージ＋吹き飛ばし、弾は6発だけ' },
    booster: { slot: 'top', name: 'ブースター', desc: '1秒間だけ2倍速。5秒ごとに使える' },
    shield:  { slot: 'top', name: 'シールド',   desc: '正面から受けるダメージを半分にする' }
  };
  var SLOTS = ['body', 'wheels', 'front', 'top'];
  var SLOT_NAMES = { body: '車体', wheels: '足回り', front: '前面パーツ', top: '上部パーツ' };

  var ARENA = {
    half: 15,
    pits: [{ x: -4, z: -7, r: 2.4 }, { x: 4, z: 7, r: 2.4 }],
    pads: [{ x: -11.5, z: 10.5, r: 2.0 }, { x: 11.5, z: -10.5, r: 2.0 }],
    time: 75
  };

  var ACTIONS = {
    charge: '突撃', flank: '回り込み', keep_distance: '距離を取る', retreat: '逃げる',
    push_to_pit: '穴へ押し込む', go_repair: '修理に向かう', circle: '周りを回る', hold: 'その場で待つ'
  };
  var CONDS = {
    always: function () { return 'いつでも'; },
    enemy_dist_lt: function (v) { return '相手との距離が' + v + 'より近い'; },
    enemy_dist_gt: function (v) { return '相手との距離が' + v + 'より遠い'; },
    my_hp_lt: function (v) { return '自分のHPが' + v + '%未満'; },
    my_hp_gt: function (v) { return '自分のHPが' + v + '%以上'; },
    enemy_hp_lt: function (v) { return '相手のHPが' + v + '%未満'; },
    time_left_lt: function (v) { return '残り時間が' + v + '秒未満'; },
    ammo_empty: function () { return '弾が切れた'; },
    enemy_near_pit: function (v) { return '相手が穴の近く（' + v + '以内）にいる'; },
    enemy_stunned: function () { return '相手がひっくり返っている'; },
    behind_enemy: function () { return '自分が相手の後ろ側にいる'; }
  };
  var COND_DEFAULT = { enemy_dist_lt: 6, enemy_dist_gt: 8, my_hp_lt: 40, my_hp_gt: 60, enemy_hp_lt: 40, time_left_lt: 20, enemy_near_pit: 5 };
  var BOOST_MODES = { never: '使わない', always: '使えるときは常に使う', on_charge: '突撃・押し込みのとき使う', on_retreat: '逃げるとき使う' };

  /* ---------- 作戦（プラン）の検証 ---------- */
  function sanitizePlan(raw) {
    var plan = { avoid_pits: false, use_boost: 'never', rules: [], pilot_comment: '' };
    if (!raw || typeof raw !== 'object') return plan;
    plan.avoid_pits = raw.avoid_pits === true;
    if (BOOST_MODES[raw.use_boost]) plan.use_boost = raw.use_boost;
    if (typeof raw.pilot_comment === 'string') plan.pilot_comment = raw.pilot_comment.slice(0, 80);
    var rules = Array.isArray(raw.rules) ? raw.rules : [];
    for (var i = 0; i < rules.length && plan.rules.length < 5; i++) {
      var r = rules[i];
      if (!r || !ACTIONS[r['do']]) continue;
      var conds = r['if'];
      if (!Array.isArray(conds)) conds = conds ? [conds] : [];
      var out = [];
      for (var j = 0; j < conds.length && out.length < 3; j++) {
        var c = conds[j];
        if (typeof c === 'string') c = { type: c };
        if (!c || !CONDS[c.type] || c.type === 'always') continue;
        var v = Number(c.value);
        if (!isFinite(v)) v = COND_DEFAULT[c.type];
        if (v !== undefined) v = Math.max(1, Math.min(100, Math.round(v)));
        out.push({ type: c.type, value: v });
      }
      var rule = { 'if': out, 'do': r['do'] };
      var d = Number(r.distance);
      if (isFinite(d)) rule.distance = Math.max(3, Math.min(14, d));
      plan.rules.push(rule);
    }
    return plan;
  }

  function describeRule(rule) {
    var cs = rule['if'].length
      ? rule['if'].map(function (c) { return CONDS[c.type](c.value); }).join(' かつ ')
      : 'いつでも';
    var act = ACTIONS[rule['do']];
    if ((rule['do'] === 'keep_distance' || rule['do'] === 'circle') && rule.distance) act += '（距離' + rule.distance + '）';
    return { when: cs, act: act };
  }

  /* ---------- 機体 ---------- */
  function makeBot(id, name, build, plan, x, z, th) {
    var b = PARTS[build.body], w = PARTS[build.wheels];
    return {
      id: id, name: name, build: build, plan: sanitizePlan(plan),
      x: x, z: z, th: th, vx: 0, vz: 0,
      hp: b.hp, maxHp: b.hp, mass: b.mass, eff: b.mass * w.grip,
      maxSpeed: w.speed * b.speedMul, turn: w.turn, radius: 1.25,
      ammo: build.top === 'mg' ? 150 : build.top === 'rocket' ? 6 : 0,
      cdFront: 0.5, cdTop: 0.5, cdBoost: 1, boostT: 0, stun: 0, ramCd: 0,
      repairLeft: 40, alive: true, falling: 0,
      action: 'hold', ruleIndex: -1, swing: 0, thinkT: 0, side: id === 0 ? 1 : -1, dealt: 0
    };
  }

  function createMatch(buildA, planA, buildB, planB, names, seed) {
    names = names || ['あなた', 'CPU'];
    return {
      t: 0, timeLeft: ARENA.time, over: null, steps: 0,
      rng: makeRng(seed === undefined ? Math.floor(Math.random() * 4294967296) : seed),
      bots: [
        makeBot(0, names[0], buildA, planA, -11, 0, 0),
        makeBot(1, names[1], buildB, planB, 11, 0, Math.PI)
      ],
      shots: [], events: []
    };
  }

  function angDiff(a, b) {
    var d = a - b;
    while (d > Math.PI) d -= 2 * Math.PI;
    while (d < -Math.PI) d += 2 * Math.PI;
    return d;
  }
  function dist(a, b) { return hyp(a.x - b.x, a.z - b.z); }
  function inFront(me, target, arc) {
    return Math.abs(angDiff(datan2(target.z - me.z, target.x - me.x), me.th)) <= arc;
  }
  function nearestPit(p) {
    var best = null, bd = 1e9;
    ARENA.pits.forEach(function (pit) {
      var d = hyp(p.x - pit.x, p.z - pit.z);
      if (d < bd) { bd = d; best = pit; }
    });
    return { pit: best, d: bd };
  }

  /* ---------- 条件判定 ---------- */
  function test(c, me, en, m) {
    var v = c.value;
    switch (c.type) {
      case 'enemy_dist_lt': return dist(me, en) < v;
      case 'enemy_dist_gt': return dist(me, en) > v;
      case 'my_hp_lt': return me.hp / me.maxHp * 100 < v;
      case 'my_hp_gt': return me.hp / me.maxHp * 100 >= v;
      case 'enemy_hp_lt': return en.hp / en.maxHp * 100 < v;
      case 'time_left_lt': return m.timeLeft < v;
      case 'ammo_empty': return (me.build.top === 'mg' || me.build.top === 'rocket') && me.ammo <= 0;
      case 'enemy_near_pit': return nearestPit(en).d < v;
      case 'enemy_stunned': return en.stun > 0;
      case 'behind_enemy': return Math.abs(angDiff(datan2(me.z - en.z, me.x - en.x), en.th)) > 1.75;
    }
    return false;
  }

  function think(me, en, m) {
    var rules = me.plan.rules, idx = -1;
    for (var i = 0; i < rules.length; i++) {
      var ok = true;
      for (var j = 0; j < rules[i]['if'].length; j++) {
        if (!test(rules[i]['if'][j], me, en, m)) { ok = false; break; }
      }
      if (ok) { idx = i; break; }
    }
    var act = idx >= 0 ? rules[idx]['do'] : 'idle';
    if (act !== me.action || idx !== me.ruleIndex) {
      m.events.push({ type: 'action', bot: me.id, action: act, fallback: idx < 0 });
    }
    me.action = act; me.ruleIndex = idx;
  }

  /* ---------- 行動 → 目標地点 ---------- */
  function decide(me, en, m) {
    var rule = me.ruleIndex >= 0 ? me.plan.rules[me.ruleIndex] : null;
    var d = dist(me, en);
    var ux = (en.x - me.x) / (d || 1), uz = (en.z - me.z) / (d || 1);
    var out = { tx: en.x, tz: en.z, throttle: 1, reverse: false, face: null };
    var want;
    switch (me.action) {
      case 'charge':
        break;
      case 'idle': // 当てはまる指示がないときは、その場でうろうろする
        out.face = me.th + 1; out.throttle = 0.3;
        break;
      case 'flank': {
        var rel = Math.abs(angDiff(datan2(me.z - en.z, me.x - en.x), en.th));
        if (rel < 1.9) { // まだ相手の正面〜横にいる → 後ろへ回る
          var hx = dcos(en.th), hz = dsin(en.th);
          var px = -hz * me.side, pz = hx * me.side;
          var off = rel < 1.0 ? 4.5 : 3.0;
          out.tx = en.x + px * off - hx * (rel < 1.0 ? 0 : 3);
          out.tz = en.z + pz * off - hz * (rel < 1.0 ? 0 : 3);
        }
        break;
      }
      case 'keep_distance':
        want = (rule && rule.distance) || 9;
        out.face = datan2(uz, ux);
        if (d < want - 1.5) { out.reverse = true; out.throttle = 1; }
        else if (d > want + 1.5) { out.throttle = 0.8; }
        else out.throttle = 0;
        break;
      case 'retreat':
        out.tx = me.x - ux * 8; out.tz = me.z - uz * 8;
        // 壁際では横へ流れる
        if (Math.abs(out.tx) > ARENA.half - 2 || Math.abs(out.tz) > ARENA.half - 2) {
          out.tx = me.x - uz * 8 * me.side; out.tz = me.z + ux * 8 * me.side;
        }
        break;
      case 'push_to_pit': {
        var np = nearestPit(en).pit;
        var ex = en.x - np.x, ez = en.z - np.z, el = hyp(ex, ez) || 1;
        ex /= el; ez /= el;
        // 相手をはさんで穴の反対側に立つ
        var sx = en.x + ex * 3.2, sz = en.z + ez * 3.2;
        var lined = (ux * -ex + uz * -ez) > 0.8;
        if (!lined && hyp(sx - me.x, sz - me.z) > 1.2) { out.tx = sx; out.tz = sz; }
        break;
      }
      case 'go_repair': {
        var pad = ARENA.pads[0], pd = 1e9;
        ARENA.pads.forEach(function (p) {
          var q = hyp(p.x - me.x, p.z - me.z);
          if (q < pd) { pd = q; pad = p; }
        });
        out.tx = pad.x; out.tz = pad.z;
        if (pd < 0.8) out.throttle = 0;
        break;
      }
      case 'circle':
        want = (rule && rule.distance) || 7;
        out.tx = en.x - ux * want - uz * 4 * me.side;
        out.tz = en.z - uz * want + ux * 4 * me.side;
        break;
      case 'hold':
        out.face = datan2(uz, ux); out.throttle = 0;
        break;
    }
    return out;
  }

  function damage(m, victim, amount, fx, fz, kind, attacker) {
    if (!victim.alive || amount <= 0) return 0;
    var a = Math.abs(angDiff(datan2(fz - victim.z, fx - victim.x), victim.th));
    var mod = 1, tag = '';
    if (victim.build.top === 'shield' && a < 1.22) { mod = 0.5; tag = 'shield'; }
    else if (a > 2.1) { mod = 1.5; tag = 'back'; }
    var dmg = amount * mod;
    victim.hp = Math.max(0, victim.hp - dmg);
    if (attacker) attacker.dealt += dmg;
    if (kind !== 'drill' && kind !== 'mg') {
      m.events.push({ type: 'hit', bot: victim.id, kind: kind, dmg: dmg, tag: tag, x: victim.x, z: victim.z });
    } else if (m.rng() < 0.25) {
      m.events.push({ type: 'spark', bot: victim.id, kind: kind, tag: tag, x: victim.x, z: victim.z });
    }
    return dmg;
  }
  function knock(victim, nx, nz, power) {
    victim.vx += nx * power / victim.eff;
    victim.vz += nz * power / victim.eff;
  }

  /* ---------- 1ステップ ---------- */
  function step(m, dt) {
    if (m.over) {
      m.bots.forEach(function (b) { if (b.falling > 0) b.falling += dt; });
      return;
    }
    m.steps++; m.t += dt; m.timeLeft = Math.max(0, ARENA.time - m.t);
    var bots = m.bots, i;

    for (i = 0; i < 2; i++) {
      var me = bots[i], en = bots[1 - i];
      me.cdFront -= dt; me.cdTop -= dt; me.cdBoost -= dt; me.ramCd -= dt;
      me.boostT -= dt; me.swing = Math.max(0, me.swing - dt);
      me.thinkT -= dt;
      if (me.stun > 0) {
        me.stun -= dt;
        me.vx -= me.vx * Math.min(1, 3 * dt); me.vz -= me.vz * Math.min(1, 3 * dt);
        continue;
      }
      if (me.thinkT <= 0) { think(me, en, m); me.thinkT = 0.25; }
      var cmd = decide(me, en, m);

      // 進みたい向き
      var dx = cmd.tx - me.x, dz = cmd.tz - me.z, dl = hyp(dx, dz) || 1;
      dx /= dl; dz /= dl;
      if (me.plan.avoid_pits && !cmd.reverse) {
        var ox = dx, oz = dz;
        ARENA.pits.forEach(function (pit) {
          var ax = me.x - pit.x, az = me.z - pit.z, ad = hyp(ax, az) || 1;
          var reach = pit.r + 3.2;
          if (ad < reach) {
            ax /= ad; az /= ad;
            var w = (reach - ad) / 3.2;
            var tx = -az, tz = ax;
            if (tx * ox + tz * oz < 0) { tx = -tx; tz = -tz; }
            dx += ax * w * 1.8 + tx * w * 1.0;
            dz += az * w * 1.8 + tz * w * 1.0;
          }
        });
      }
      var wantTh = cmd.face !== null ? cmd.face : datan2(dz, dx);
      var diff = angDiff(wantTh, me.th);
      var maxTurn = me.turn * dt;
      me.th += Math.max(-maxTurn, Math.min(maxTurn, diff));

      var thr = cmd.throttle;
      if (!cmd.reverse && cmd.face === null && Math.abs(diff) > 1.2) thr *= 0.25;
      if (dl < 0.6 && cmd.face === null && me.action !== 'charge') thr = 0;

      // ブースター
      if (me.build.top === 'booster' && me.cdBoost <= 0 && thr > 0.5 && Math.abs(diff) < 0.5) {
        var mode = me.plan.use_boost;
        var go = mode === 'always'
          || (mode === 'on_charge' && (me.action === 'charge' || me.action === 'push_to_pit') && dist(me, en) < 9)
          || (mode === 'on_retreat' && me.action === 'retreat');
        if (go) { me.boostT = 1.0; me.cdBoost = 5; m.events.push({ type: 'boost', bot: me.id }); }
      }
      var sp = me.maxSpeed * (me.boostT > 0 ? 2.0 : 1) * thr * (cmd.reverse ? -0.6 : 1);
      var tvx = dcos(me.th) * sp, tvz = dsin(me.th) * sp;
      var k = Math.min(1, 5 * dt);
      me.vx += (tvx - me.vx) * k; me.vz += (tvz - me.vz) * k;

      // 武器
      var d = dist(me, en);
      var contact = d < me.radius + en.radius + 0.7 && inFront(me, en, 0.7);
      var nx = (en.x - me.x) / (d || 1), nz = (en.z - me.z) / (d || 1);
      if (contact && en.alive) {
        if (me.build.front === 'drill') damage(m, en, 13 * dt, me.x, me.z, 'drill', me);
        else if (me.build.front === 'hammer' && me.cdFront <= 0) {
          me.cdFront = 1.5; me.swing = 0.35;
          damage(m, en, 20, me.x, me.z, 'hammer', me); knock(en, nx, nz, 6);
        } else if (me.build.front === 'lifter' && me.cdFront <= 0 && en.stun <= 0) {
          me.cdFront = 4.5; me.swing = 0.5;
          damage(m, en, 6, me.x, me.z, 'lifter', me); knock(en, nx, nz, 3);
          en.stun = 1.6;
          m.events.push({ type: 'flip', bot: en.id });
        }
      }
      if (me.build.top === 'mg' && me.ammo > 0 && me.cdTop <= 0 && d < 15 && inFront(me, en, 0.17)) {
        me.cdTop = 0.18; me.ammo--;
        var sa = me.th + (m.rng() - 0.5) * 0.08;
        m.shots.push({ x: me.x + dcos(me.th) * 1.3, z: me.z + dsin(me.th) * 1.3, vx: dcos(sa) * 32, vz: dsin(sa) * 32, owner: me.id, dmg: 1.5, knock: 0, life: 0.6, kind: 'mg' });
        if (me.ammo === 0) m.events.push({ type: 'ammo_out', bot: me.id });
      }
      if (me.build.top === 'rocket' && me.ammo > 0 && me.cdTop <= 0 && d < 18 && inFront(me, en, 0.14)) {
        me.cdTop = 2.6; me.ammo--;
        m.shots.push({ x: me.x + dcos(me.th) * 1.3, z: me.z + dsin(me.th) * 1.3, vx: dcos(me.th) * 16, vz: dsin(me.th) * 16, owner: me.id, dmg: 17, knock: 7, life: 1.4, kind: 'rocket' });
        m.events.push({ type: 'launch', bot: me.id });
        if (me.ammo === 0) m.events.push({ type: 'ammo_out', bot: me.id });
      }
    }

    // 移動
    for (i = 0; i < 2; i++) {
      var b = bots[i];
      b.x += b.vx * dt; b.z += b.vz * dt;
      var lim = ARENA.half - b.radius;
      if (b.x > lim) { b.x = lim; if (b.vx > 0) b.vx = 0; }
      if (b.x < -lim) { b.x = -lim; if (b.vx < 0) b.vx = 0; }
      if (b.z > lim) { b.z = lim; if (b.vz > 0) b.vz = 0; }
      if (b.z < -lim) { b.z = -lim; if (b.vz < 0) b.vz = 0; }
    }

    // 機体どうしの衝突
    var A = bots[0], B = bots[1];
    var dd = dist(A, B), minD = A.radius + B.radius;
    if (dd < minD) {
      var cx = (B.x - A.x) / (dd || 1), cz = (B.z - A.z) / (dd || 1);
      if (!dd) { cx = 1; cz = 0; }
      var over = minD - dd, tot = A.eff + B.eff;
      A.x -= cx * over * (B.eff / tot); A.z -= cz * over * (B.eff / tot);
      B.x += cx * over * (A.eff / tot); B.z += cz * over * (A.eff / tot);
      var vrel = (A.vx - B.vx) * cx + (A.vz - B.vz) * cz;
      if (vrel > 0) {
        var red = A.eff * B.eff / tot;
        var aB = A.build.front === 'bumper' && inFront(A, B, 0.9);
        var bB = B.build.front === 'bumper' && inFront(B, A, 0.9);
        var j = vrel * 1.3 * red;
        A.vx -= cx * j / A.eff * (bB ? 2 : 1); A.vz -= cz * j / A.eff * (bB ? 2 : 1);
        B.vx += cx * j / B.eff * (aB ? 2 : 1); B.vz += cz * j / B.eff * (aB ? 2 : 1);
        if (vrel > 5 && A.ramCd <= 0 && B.ramCd <= 0) {
          A.ramCd = B.ramCd = 0.7;
          var base = (vrel - 5) * 2.2;
          damage(m, B, base * (A.eff / tot) * 2 * (aB ? 2.5 : 1) * (bB ? 0.3 : 1), A.x, A.z, 'ram', A);
          damage(m, A, base * (B.eff / tot) * 2 * (bB ? 2.5 : 1) * (aB ? 0.3 : 1), B.x, B.z, 'ram', B);
        }
      }
    }

    // 弾
    for (i = m.shots.length - 1; i >= 0; i--) {
      var s = m.shots[i];
      s.x += s.vx * dt; s.z += s.vz * dt; s.life -= dt;
      var tgt = bots[1 - s.owner], gone = s.life <= 0 || Math.abs(s.x) > ARENA.half || Math.abs(s.z) > ARENA.half;
      if (!gone && tgt.alive && hyp(s.x - tgt.x, s.z - tgt.z) < tgt.radius) {
        var sl = hyp(s.vx, s.vz);
        damage(m, tgt, s.dmg, s.x - s.vx / sl, s.z - s.vz / sl, s.kind, bots[s.owner]);
        if (s.knock) knock(tgt, s.vx / sl, s.vz / sl, s.knock);
        gone = true;
      }
      if (gone) m.shots.splice(i, 1);
    }

    // 修理と穴
    for (i = 0; i < 2; i++) {
      var r = bots[i];
      ARENA.pads.forEach(function (p) {
        if (r.repairLeft > 0 && r.hp < r.maxHp && r.stun <= 0 &&
            hyp(r.x - p.x, r.z - p.z) < p.r && hyp(r.vx, r.vz) < 1.5) {
          var h = Math.min(10 * dt, r.repairLeft, r.maxHp - r.hp);
          r.hp += h; r.repairLeft -= h; r.repairing = true;
        }
      });
      if (r.repairing && !r.wasRepairing) m.events.push({ type: 'repair', bot: r.id });
      r.wasRepairing = r.repairing; r.repairing = false;
      var np = nearestPit(r);
      if (r.alive && np.d < np.pit.r - 0.35) {
        r.alive = false; r.falling = 0.001; r.vx = r.vz = 0;
        r.x += (np.pit.x - r.x) * 0.5; r.z += (np.pit.z - r.z) * 0.5;
        m.events.push({ type: 'fall', bot: r.id });
      }
    }

    // 決着
    var a0 = bots[0], b0 = bots[1];
    if (!a0.alive || !b0.alive) {
      m.over = { winner: a0.alive ? 0 : b0.alive ? 1 : -1, reason: 'pit' };
    } else if (a0.hp <= 0 || b0.hp <= 0) {
      m.over = { winner: a0.hp > 0 ? 0 : b0.hp > 0 ? 1 : -1, reason: 'ko' };
    } else if (m.timeLeft <= 0) {
      var ra = a0.hp / a0.maxHp, rb = b0.hp / b0.maxHp;
      m.over = { winner: Math.abs(ra - rb) < 0.01 ? -1 : ra > rb ? 0 : 1, reason: 'time' };
    }
    if (m.over) m.events.push({ type: 'over', winner: m.over.winner, reason: m.over.reason });
  }

  /* ---------- パーツ配布とCPU ---------- */
  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1)), t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }
  function deal() {
    var out = {};
    SLOTS.forEach(function (slot) {
      var ids = Object.keys(PARTS).filter(function (k) { return PARTS[k].slot === slot; });
      out[slot] = shuffle(ids).slice(0, 2);
    });
    return out;
  }
  function validHand(h) {
    if (!h || typeof h !== 'object') return false;
    return SLOTS.every(function (slot) {
      var a = h[slot];
      return Array.isArray(a) && a.length === 2 && a[0] !== a[1] &&
        a.every(function (id) { return typeof id === 'string' && PARTS.hasOwnProperty(id) && PARTS[id].slot === slot; });
    });
  }
  function validBuild(b, hand) {
    if (!b || typeof b !== 'object') return false;
    return SLOTS.every(function (slot) { return hand[slot].indexOf(b[slot]) >= 0; });
  }
  function cpuSetup(hand) {
    function pick(slot) { return hand[slot][Math.floor(Math.random() * 2)]; }
    var build = { body: pick('body'), wheels: pick('wheels'), front: pick('front'), top: pick('top') };
    var ranged = build.top === 'mg' || build.top === 'rocket';
    var styles = ['brawler', 'pusher'];
    if (ranged) styles.push('gunner', 'gunner');
    if (build.front === 'bumper') styles.push('pusher');
    var style = styles[Math.floor(Math.random() * styles.length)];
    var plan, label;
    if (style === 'gunner') {
      label = '射撃型';
      plan = { avoid_pits: true, use_boost: 'never', rules: [
        { 'if': [{ type: 'ammo_empty' }], 'do': 'charge' },
        { 'if': [{ type: 'my_hp_lt', value: 35 }, { type: 'enemy_dist_gt', value: 9 }], 'do': 'go_repair' },
        { 'if': [], 'do': 'keep_distance', distance: 9 }
      ] };
    } else if (style === 'pusher') {
      label = '穴落とし型';
      plan = { avoid_pits: true, use_boost: 'on_charge', rules: [
        { 'if': [{ type: 'enemy_near_pit', value: 7 }], 'do': 'push_to_pit' },
        { 'if': [], 'do': 'flank' }
      ] };
    } else {
      label = '突撃型';
      plan = { avoid_pits: Math.random() < 0.7, use_boost: 'on_charge', rules: [
        { 'if': [{ type: 'my_hp_lt', value: 30 }, { type: 'enemy_dist_gt', value: 8 }], 'do': 'go_repair' },
        { 'if': [], 'do': 'charge' }
      ] };
    }
    return { build: build, plan: plan, label: label };
  }

  /* ---------- AIが使えないときの簡易解釈 ---------- */
  function localParse(text) {
    var plan = { avoid_pits: false, use_boost: 'never', rules: [], pilot_comment: 'キーワードだけ拾って動くっす！' };
    if (/穴.{0,6}(避|よけ|気をつけ|注意|落ちるな|近づくな|近寄るな)/.test(text)) plan.avoid_pits = true;
    if (/ブースト|ブースター|加速/.test(text)) plan.use_boost = /逃|退/.test(text) ? 'on_retreat' : 'on_charge';
    var segs = text.split(/[。\n、,．.!！]/);
    segs.forEach(function (s) {
      if (!s.trim() || /ブースト|ブースター/.test(s)) return;
      var conds = [], mm;
      if ((mm = s.match(/(?:HP|体力).{0,4}?(\d+)\s*[%％]/i)) && !/相手|敵/.test(s)) conds.push({ type: 'my_hp_lt', value: +mm[1] });
      else if (/(HP|体力).{0,6}(半分|減|少な|やば|ピンチ)/i.test(s)) conds.push({ type: /相手|敵/.test(s) ? 'enemy_hp_lt' : 'my_hp_lt', value: 50 });
      if (/弾.{0,6}(切れ|なくな|尽き)/.test(s)) conds.push({ type: 'ammo_empty' });
      if (/(相手|敵).{0,8}穴.{0,4}(近|そば)/.test(s)) conds.push({ type: 'enemy_near_pit', value: 6 });
      if (/近(づかれ|い|寄られ)/.test(s) && /たら|とき|時|なら/.test(s)) conds.push({ type: 'enemy_dist_lt', value: 6 });
      if (/ひっくり返|動けな/.test(s)) conds.push({ type: 'enemy_stunned' });
      var act = null;
      if (/穴.{0,8}(落と|押し|突き)/.test(s)) act = 'push_to_pit';
      else if (/突撃|突っ込|体当たり/.test(s)) act = 'charge';
      else if (/修理|回復|直し/.test(s)) act = 'go_repair';
      else if (/回り込|背後|後ろから|横から|側面/.test(s)) act = 'flank';
      else if (/逃げ|下がれ|退|離れろ/.test(s)) act = 'retreat';
      else if (/距離|離れて|遠くから|撃|射/.test(s)) act = 'keep_distance';
      else if (/回(れ|って)|ぐるぐる|周り/.test(s)) act = 'circle';
      else if (/待|止ま|動くな/.test(s)) act = 'hold';
      else if (/突撃|突っ込|体当たり|攻め|近づ|殴|叩|削|ぶつか|押せ/.test(s)) act = 'charge';
      if (act) plan.rules.push({ 'if': conds, 'do': act });
    });
    // 条件つきの指示を先に調べる
    plan.rules = plan.rules.filter(function (r) { return r['if'].length; })
      .concat(plan.rules.filter(function (r) { return !r['if'].length; }));
    return sanitizePlan(plan);
  }

  var api = {
    PARTS: PARTS, SLOTS: SLOTS, SLOT_NAMES: SLOT_NAMES, ARENA: ARENA, ACTIONS: ACTIONS,
    BOOST_MODES: BOOST_MODES, CONDS: CONDS,
    actionLabel: function (a) { return a === 'idle' ? '指示待ちでうろうろ' : ACTIONS[a]; },
    sanitizePlan: sanitizePlan, describeRule: describeRule, createMatch: createMatch, step: step,
    deal: deal, cpuSetup: cpuSetup, localParse: localParse,
    validHand: validHand, validBuild: validBuild
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.PBSim = api;
})(typeof window !== 'undefined' ? window : this);
>>>>> END FILE

<<<<< FILE: .gitignore
# Godot 4
.godot/
/android/

# ビルド成果物
/build/
*.tmp

# OS
.DS_Store
Thumbs.db

# 操縦エージェントのモデル（大きいので別配布）
*.gguf
>>>>> END FILE

<<<<< FILE: .gitattributes
# 改行コードをそろえる
* text=auto eol=lf

# 大きいファイルは Git LFS
*.glb filter=lfs diff=lfs merge=lfs -text
*.gltf filter=lfs diff=lfs merge=lfs -text
*.blend filter=lfs diff=lfs merge=lfs -text
*.fbx filter=lfs diff=lfs merge=lfs -text
*.png filter=lfs diff=lfs merge=lfs -text
*.jpg filter=lfs diff=lfs merge=lfs -text
*.exr filter=lfs diff=lfs merge=lfs -text
*.wav filter=lfs diff=lfs merge=lfs -text
*.ogg filter=lfs diff=lfs merge=lfs -text
*.mp3 filter=lfs diff=lfs merge=lfs -text
>>>>> END FILE
