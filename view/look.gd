# 見た目の調整値をまとめた場所（照明・色・画面効果・演出）。ゲームの計算には関わらない値だけを置く。
# 目標は薄暗く汚れた質感（企画メモ「技術構成」）。雰囲気を変えたいときはここだけ触る。
extends RefCounted

# ---- 低解像度で描いて拡大 ----
## 3Dのアリーナを何分の1の解像度で描くか（3 なら 1280x720 の画面に 427x240 で描いて拡大）
const PIXEL_SHRINK: int = 3

# ---- 画面効果（view/shaders/post_grime.gdshader） ----
## アリーナに重ねる強い効果：ざらつき、色の段数（少ないほど荒い）、ディザの強さ、周辺の暗さ、色味
const ARENA_POST: Dictionary = {
	"grain": 0.05, "levels": 16.0, "dither": 1.0, "vignette": 0.7, "tint": Color(1.0, 0.93, 0.82),
	"cell": 3.0,
}
## 画面全体（メニューを含む）に薄く重ねる効果
const SCREEN_POST: Dictionary = {
	"grain": 0.035, "levels": 64.0, "dither": 0.0, "vignette": 0.45, "tint": Color(1.0, 0.97, 0.92),
	"cell": 2.0,
}

# ---- 照明と空気 ----
const BACKGROUND := Color(0.012, 0.012, 0.014)
const AMBIENT := Color(0.32, 0.34, 0.38)
const AMBIENT_ENERGY: float = 0.5
const FOG_COLOR := Color(0.035, 0.035, 0.04)
const FOG_DENSITY: float = 0.015
## 真上から吊った裸電球のようなスポットライト
const LAMP_COLOR := Color(1.0, 0.86, 0.62)
const LAMP_ENERGY: float = 22.0
const LAMP_HEIGHT: float = 10.0
const LAMP_ANGLE_DEG: float = 70.0
## 斜めから弱く当てる冷たい光（影なし）
const FILL_COLOR := Color(0.55, 0.65, 0.85)
const FILL_ENERGY: float = 0.55
## 穴の縁を照らす赤い光、修理ステーションの緑の光
const PIT_LIGHT := Color(1.0, 0.18, 0.08)
const PIT_LIGHT_ENERGY: float = 3.0
const PAD_LIGHT := Color(0.25, 1.0, 0.45)
const PAD_LIGHT_ENERGY: float = 1.2

# ---- 質感 ----
const FLOOR_COLOR := Color(0.36, 0.35, 0.33)
const WALL_COLOR := Color(0.42, 0.28, 0.18)
const PIT_RIM_COLOR := Color(0.75, 0.6, 0.12)
const PAD_COLOR := Color(0.15, 0.55, 0.25)
## 陣営の色（暗い中でも見分けられるよう、くすんだ地の色と光る目印の色）
const SIDE_BODY: Array[Color] = [Color(0.38, 0.52, 0.66), Color(0.72, 0.45, 0.26)]
const SIDE_GLOW: Array[Color] = [Color(0.35, 0.75, 1.0), Color(1.0, 0.55, 0.15)]

# ---- 演出 ----
const SPARK_COLOR := Color(1.0, 0.75, 0.3)
## この量以上のダメージで画面を揺らす
const SHAKE_DAMAGE: float = 8.0
const SHAKE_AMOUNT: float = 0.35
const SHAKE_DECAY: float = 6.0

# ---- 文字と板（画面の作り） ----
const UI_BG := Color(0.06, 0.06, 0.065)
const UI_PANEL := Color(0.09, 0.085, 0.08, 0.88)
const UI_BORDER := Color(0.42, 0.34, 0.2)
const UI_TEXT := Color(0.88, 0.85, 0.78)
const UI_ACCENT := Color(0.95, 0.72, 0.3)

# ---- タイトル画面（view/title/） ----
## タイトルの文字の色（鈍い金色）と、くすんだ影
const TITLE_COLOR := Color(0.93, 0.68, 0.24)
const TITLE_SHADOW := Color(0.12, 0.05, 0.02, 0.85)
## タイトルの文字がときどき瞬く（古い看板のような）間隔の秒数と、暗くなる量
const TITLE_FLICKER_PERIOD: float = 7.0
const TITLE_FLICKER_DIM: float = 0.45
## 機体を置いたショールーム（タイトル）。カメラの位置・見る点・画角。
## カメラと見る点を機体より左（x が負）にずらすと、機体は画面の右に寄る（左はメニューの場所）
const TITLE_STAGE: Dictionary = {
	"camera": Vector3(-2.4, 2.6, 8.0), "target": Vector3(-2.4, 0.5, 0), "fov": 42.0,
	"spin_deg_per_sec": 30.0, "floor": true,
}

# ---- パーツの吹き出し（view/draft/part_tooltip.gd） ----
## 武器とスキルの見本を載せる台の機体（フレームの型のID）と、その地の色
const PREVIEW_BASE_FRAME: String = "frame_standard"
const PREVIEW_BASE_COLOR := Color(0.2, 0.2, 0.21)
## 見本のカメラ（機体を真ん中に大きく映す）
const PREVIEW_STAGE: Dictionary = {
	"camera": Vector3(0, 2.4, 4.4), "target": Vector3(0, 0.55, 0), "fov": 40.0,
	"spin_deg_per_sec": 40.0, "floor": false,
}
## 見本の大きさ（画面上の点）と、何分の1の解像度で描くか
const PREVIEW_SIZE := Vector2(300, 170)
const PREVIEW_SHRINK: int = 2
# ---- パーツ選び（view/draft/part_carousel.gd・build_preview.gd） ----
## 真ん中のカードの大きさ、両脇のカードの縮み具合と真ん中からのずれ（点）、暗さ
const DRAFT_CARD_SIZE := Vector2(300, 150)
## 組み立て画面の段のカード（段が多くても1画面に収まるよう、パーツ選びより小さくする）と見出しの文字の大きさ
const GARAGE_CARD_SIZE := Vector2(260, 112)
const GARAGE_HEADER_FONT: int = 18
## 組み立て画面の下の帯に、付けたパーツの詳しい性能を横に何個並べるか
const GARAGE_DETAIL_COLUMNS: int = 4
const DRAFT_SIDE_SCALE: float = 0.8
const DRAFT_SIDE_OFFSET: float = 210.0
const DRAFT_SIDE_DIM: float = 0.45
## カードを送るときに滑らせる秒数
const DRAFT_SLIDE_SEC: float = 0.18
## 種類の段を開く・閉じるのにかける秒数
const DRAFT_EXPAND_SEC: float = 0.22
## ◀▶の色と、ボタンの幅
const DRAFT_ARROW_COLOR := Color(0.75, 0.36, 0.05)
const DRAFT_ARROW_WIDTH: float = 44.0
## 右側の組んだ機体の見本：大きさ（点）・何分の1で描くか・カメラ
const DRAFT_PREVIEW_SIZE := Vector2(480, 180)
const DRAFT_PREVIEW_SHRINK: int = 2
const DRAFT_PREVIEW_STAGE: Dictionary = {
	"camera": Vector3(0, 2.0, 4.6), "target": Vector3(0, 0.55, 0), "fov": 38.0,
	"spin_deg_per_sec": 30.0, "floor": true,
}

## パーツの種類ごとの目印の色（カードの帯と吹き出しの札）
const KIND_COLORS: Dictionary = {
	"frame": Color(0.62, 0.66, 0.7), "weapon": Color(0.95, 0.45, 0.28), "skill": Color(0.35, 0.85, 0.95),
}

# ---- ラウンド結果（view/results/round_result_screen.gd） ----
## 勝ち負けのスタンプの色と、押したあとの傾き（度）・最初の大きさ・押し込む秒数。
## まっすぐ押し込み、少し置いてから傾く（STAMP_TILT_DELAY 秒待って、STAMP_TILT_SEC 秒で傾く）
const STAMP_WIN := Color(0.95, 0.72, 0.3)
const STAMP_LOSE := Color(0.92, 0.32, 0.25)
const STAMP_DRAW := Color(0.7, 0.68, 0.62)
const STAMP_TILT_DEG: float = -8.0
const STAMP_START_SCALE: float = 2.4
const STAMP_SEC: float = 0.25
const STAMP_TILT_DELAY: float = 0.15
const STAMP_TILT_SEC: float = 0.18
## WIN のスタンプの押したあとの動き："bounce"（弾む）か "shine"（光る）。見比べて決める
const WIN_STAMP_STYLE: String = "bounce"
## 弾む：ふくらむ大きさ（1回目。2回目からは小さくなる）、1回の秒数、回数
const STAMP_BOUNCE_SCALE: float = 1.15
const STAMP_BOUNCE_SEC: float = 0.13
const STAMP_BOUNCE_COUNT: int = 2
## 光る：光の筋が走る秒数と、パッと光る明るさ（1 より大きいほど白っぽく光る）
const STAMP_SHINE_SEC: float = 0.45
const STAMP_FLASH: float = 1.8
## 体力バー：減った分を赤く残す時間、縮む秒数、バーごとにずらす秒数
const HP_BAR_HOLD_SEC: float = 0.6
const HP_BAR_DRAIN_SEC: float = 0.8
const HP_BAR_STAGGER_SEC: float = 0.08
const HP_BAR_FILL := Color(0.78, 0.6, 0.28)
const HP_BAR_FILL_ME := Color(0.95, 0.75, 0.3)
const HP_BAR_LOST := Color(0.9, 0.25, 0.2)
const HP_BAR_BACK := Color(0.05, 0.05, 0.05)
const HP_BAR_OUT := Color(0.3, 0.29, 0.27)

# ---- バトル中のHPバー（view/arena/battle_hp_bar.gd） ----
## 大きさ（点）
const BATTLE_HP_SIZE := Vector2(340, 26)
## 削られた直後に白く光る秒数、赤い部分を残す秒数、赤い部分が満タン分を縮むのにかかる秒数
const BATTLE_HP_FLASH_SEC: float = 0.08
const BATTLE_HP_LAG_HOLD_SEC: float = 0.45
const BATTLE_HP_LAG_DRAIN_SEC: float = 1.2
## 揺れの最大の強さ（点）と、最大から止まるまでの秒数
const BATTLE_HP_SHAKE_MAX: float = 7.0
const BATTLE_HP_SHAKE_SEC: float = 0.35
## 残りがこの割合を切ると赤く脈打つ（1秒に何回）
const BATTLE_HP_LOW: float = 0.3
const BATTLE_HP_LOW_PULSE_HZ: float = 2.5
## 減った・増えた数を飛ばす秒数と文字の大きさ
const BATTLE_HP_POP_SEC: float = 0.9
const BATTLE_HP_POP_FONT: int = 20
const BATTLE_HP_LOST := Color(0.95, 0.22, 0.16)
const BATTLE_HP_HEAL := Color(0.45, 0.95, 0.45)
## 減った数の色（赤い部分の上に重ねても読めるよう明るくする）
const BATTLE_HP_POP_DAMAGE := Color(1.0, 0.96, 0.88)
## バトル画面の上の見出しの幅（左右の機体の板にかぶらない幅）
const BATTLE_HEADER_WIDTH: float = 480.0
## 自分の試合が終わったときの「FINISH」：文字の大きさと色、押し込む前の大きさ（倍）、押し込む・見せておく・消える秒数
const FINISH_FONT: int = 140
const FINISH_COLOR := Color(1.0, 0.82, 0.35)
const FINISH_START_SCALE: float = 3.0
const FINISH_SLAM_SEC: float = 0.3
const FINISH_HOLD_SEC: float = 1.6
const FINISH_FADE_SEC: float = 0.5

# ---- パーク選び（view/draft/perk_card.gd） ----
## パークの種類ごとの色。種類は効果の対象の先頭で決める（frame / weapon / skill / build は機体、prompt はプロンプト、pilot は操縦士）
const PERK_GROUP_COLORS: Dictionary = {
	"machine": Color(0.62, 0.66, 0.7), "prompt": Color(0.75, 0.55, 0.95), "pilot": Color(0.45, 0.85, 0.5),
}
const PERK_CARD_SIZE := Vector2(300, 250)
## 配られたパーツを1枚ずつ画面の中央に大きく見せてから、下の列の場所へ縮めて送る（view/draft/loot_screen.gd）
## 中央での大きさ（倍）、現れる・見せておく・列へ飛ぶ時間（秒）、後ろを暗くする濃さ
const LOOT_SHOW_SCALE: float = 1.8
const LOOT_POP_SEC: float = 0.25
const LOOT_HOLD_SEC: float = 0.5
const LOOT_FLY_SEC: float = 0.3
const LOOT_DIM_ALPHA: float = 0.6
## 残り時間の導火線（view/fuse_bar.gd）。この秒数を切ったら、先端が赤くなり、火花が増え、縄が震える
const FUSE_WARN_SEC: float = 5.0
## 縄の太さ（点）、縄の地の色と縞の色、焦げ跡の色
const FUSE_HEIGHT: float = 10.0
const FUSE_ROPE := Color(0.62, 0.48, 0.3)
const FUSE_ROPE_STRIPE := Color(0.4, 0.29, 0.17)
const FUSE_BURNT := Color(0.22, 0.18, 0.15)
## 先端の火の色（ふだん・残りわずか）と光の大きさ、火花の数、震えの大きさ（点）
const FUSE_TIP := Color(1.0, 0.62, 0.2)
const FUSE_TIP_WARN := Color(1.0, 0.3, 0.18)
const FUSE_GLOW_RADIUS: float = 11.0
const FUSE_SPARK_AMOUNT: int = 14
const FUSE_SHAKE_PX: float = 1.6

# ---- 最終順位の表彰台（view/results/final_screen.gd） ----
## 台の位置（x）と高さ（1位・2位・3位の順）
const PODIUM_X: Array[float] = [0.0, -3.7, 3.7]
const PODIUM_HEIGHT: Array[float] = [1.5, 1.0, 0.6]
const PODIUM_COLOR := Color(0.32, 0.27, 0.2)
const PODIUM_STAGE: Dictionary = {
	"camera": Vector3(0, 4.6, 11.0), "target": Vector3(0, 2.1, 0), "fov": 42.0,
	"spin_deg_per_sec": 30.0, "floor": true, "turntable": false,
}
## 順位が分からない（通信対戦で相手の機体が届かない）ときの機体の色
const PODIUM_UNKNOWN_BODY := Color(0.18, 0.18, 0.19)
