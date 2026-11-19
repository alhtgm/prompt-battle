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

# ---- パーツの3Dモデル（view/arena/part_models.gd） ----
## 読み込んだモデルの大きさを機体に合わせて自動でそろえるか（false ならモデルの 1 = 1m のまま）
const MODEL_AUTO_FIT: bool = true
## フレームの一番長い辺（横から見た前後・左右）を、機体の当たり判定の直径の何倍にするか
const MODEL_FRAME_FOOTPRINT: float = 1.0
## 武器・撃つ武器・スキルのモデルの一番長い辺（m）
const MODEL_WEAPON_SIZE: float = 0.9
const MODEL_SHOOT_SIZE: float = 1.2
const MODEL_SKILL_SIZE: float = 0.6
## 荒い見た目になじませる：つやの最低値、金属らしさの最大値、陣営の色を混ぜる割合
const MODEL_ROUGHNESS_MIN: float = 0.75
const MODEL_METALLIC_MAX: float = 0.6
const MODEL_SIDE_TINT: float = 0.2
## モデルの機体の足もとに出す、陣営の色で光る輪の半径（当たり判定の半径の何倍か）
const MODEL_RING_RADIUS: float = 1.1

# ---- バリア（シールドのスキル。view/arena/shield_view.gd と view/shaders/shield.gdshader） ----
const SHIELD_COLOR := Color(0.35, 0.8, 1.0)
## 膜の横の半径（当たり判定の半径の何倍か）と、機体の高さに足す余り（m）
const SHIELD_RADIUS: float = 1.9
const SHIELD_HEIGHT_PAD: float = 0.7
## 横と縦に並べる六角形の数（低い解像度で潰れないよう粗め）
const SHIELD_CELLS := Vector2(10, 5)
## 展開と消滅にかける秒数、床の光の輪が広がりきる秒数
const SHIELD_OPEN_SEC: float = 0.35
const SHIELD_CLOSE_SEC: float = 0.45
const SHIELD_RING_SEC: float = 0.5
## 残り時間がこの割合を切ると、ちらついて不安定になる
const SHIELD_LOW_FRAC: float = 0.3
## 膜の明るさと、機体や床を照らす光の強さ
const SHIELD_INTENSITY: float = 1.0
const SHIELD_LIGHT_ENERGY: float = 1.2

# ---- 機体が壊されたときの爆発（view/arena/explosion_view.gd） ----
const EXPLOSION_FIRE := Color(1.0, 0.55, 0.15)
const EXPLOSION_CORE := Color(1.0, 0.95, 0.75)
const EXPLOSION_SMOKE := Color(0.12, 0.11, 0.1)
## 部品が外へ飛ぶ速さ・上へ飛ぶ速さ（m/秒の範囲）、回る速さ（ラジアン/秒）
const EXPLOSION_SPEED_MIN: float = 3.0
const EXPLOSION_SPEED_MAX: float = 9.0
const EXPLOSION_UP_MIN: float = 4.0
const EXPLOSION_UP_MAX: float = 10.0
const EXPLOSION_SPIN: float = 18.0
## 部品にかかる重力、床で跳ねたときに残る勢い（上下）と、こすれて残る勢い（水平と回転）
const EXPLOSION_GRAVITY: float = 20.0
const EXPLOSION_BOUNCE: float = 0.35
const EXPLOSION_FRICTION: float = 0.6
## 火の玉の大きさ（機体の大きさの何倍か）と消えるまでの秒数、閃光の強さ
const EXPLOSION_FIREBALL_SIZE: float = 1.2
const EXPLOSION_FIREBALL_SEC: float = 0.6
const EXPLOSION_FLASH_ENERGY: float = 9.0
## 床を広がる衝撃の輪の最後の半径（m）と秒数
const EXPLOSION_RING_RADIUS: float = 5.0
const EXPLOSION_RING_SEC: float = 0.35
## 爆発で画面を揺らす強さ
const EXPLOSION_SHAKE: float = 0.9

# ---- 演出 ----
const SPARK_COLOR := Color(1.0, 0.75, 0.3)
## この量以上のダメージで画面を揺らす
const SHAKE_DAMAGE: float = 8.0
const SHAKE_AMOUNT: float = 0.35
const SHAKE_DECAY: float = 6.0

# ---- 撃つ武器の弾（view/arena/shot_fx.gd） ----
## 弾の高さ（床から）
const SHOT_HEIGHT: float = 0.9
## ロケットの見た目にする武器（パーツID）。ほかの撃つ武器は曳光弾
const ROCKET_WEAPONS: Array[String] = ["weapon_rocket"]
## 曳光弾：太さ、明るい芯の長さ、後ろへ伸びる薄い尾の長さと濃さ、色（低い解像度でも1画素以上に見える太さ）
const TRACER_WIDTH: float = 0.09
const TRACER_LENGTH: float = 0.8
const TRACER_TAIL_LENGTH: float = 1.4
const TRACER_TAIL_ALPHA: float = 0.35
const TRACER_COLOR := Color(1.0, 0.85, 0.45)
## 銃口の光：色、大きさ（半径）、消えるまでの秒数
const MUZZLE_COLOR := Color(1.0, 0.92, 0.7)
const MUZZLE_SIZE: float = 0.22
const MUZZLE_LIFE: float = 0.07
## 機関銃の弾が当たった所：火花の数・消えるまでの秒数・速さ・散らばる角度、光の大きさ
const BULLET_SPARK_AMOUNT: int = 14
const BULLET_SPARK_LIFE: float = 0.4
const BULLET_SPARK_SPEED: float = 7.0
const BULLET_SPARK_SPREAD_DEG: float = 40.0
const BULLET_HIT_FLASH_SIZE: float = 0.28
## 当たったかの見分け：最後に見た位置から何秒前までの道のりを見るか、機体の半径に足すゆとり、壁までの距離のゆとり
const SHOT_HIT_LOOKBACK_SEC: float = 0.08
const SHOT_HIT_MARGIN: float = 0.35
const SHOT_WALL_MARGIN: float = 0.8
## ロケット：太さ（半径）・長さ、筒と先の色、噴射炎の長さ・色・伸び縮み（±の割合）
const ROCKET_RADIUS: float = 0.14
const ROCKET_LENGTH: float = 0.85
const ROCKET_BODY_COLOR := Color(0.42, 0.43, 0.4)
const ROCKET_NOSE_COLOR := Color(0.7, 0.16, 0.1)
const ROCKET_FLAME_LENGTH: float = 0.75
const ROCKET_FLAME_COLOR := Color(1.0, 0.6, 0.2)
const ROCKET_FLAME_FLICKER: float = 0.25
## ロケットの煙の尾：出し続ける煙の数・消えるまでの秒数。煙の色
const ROCKET_TRAIL_AMOUNT: int = 50
const ROCKET_TRAIL_LIFE: float = 1.0
const SHOT_SMOKE_COLOR := Color(0.2, 0.19, 0.18)
## ロケットを撃った瞬間：光の大きさ・秒数、煙のひと吹きの数
const ROCKET_MUZZLE_SIZE: float = 0.45
const ROCKET_MUZZLE_LIFE: float = 0.14
const ROCKET_MUZZLE_SMOKE: int = 8
## ロケットの爆発：火の玉の大きさ（半径）・秒数・色、火花の数、煙の数（火の玉と光は機体に隠れないよう手前に重ねて描く）
const ROCKET_BLAST_SIZE: float = 1.3
const ROCKET_BLAST_LIFE: float = 0.5
const ROCKET_FIRE_COLOR := Color(1.0, 0.5, 0.15)
## 爆発の芯の色（火の玉の内側に重ねる明るい黄色）
const ROCKET_CORE_COLOR := Color(1.0, 0.85, 0.45)
const ROCKET_BLAST_SPARKS: int = 36
const ROCKET_BLAST_SMOKE: int = 16

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

# ---- パーク選び（view/draft/perk_card.gd） ----
## パークの種類ごとの色。種類は効果の対象の先頭で決める（frame / weapon / skill / build は機体、prompt はプロンプト、pilot は操縦士）
const PERK_GROUP_COLORS: Dictionary = {
	"machine": Color(0.62, 0.66, 0.7), "prompt": Color(0.75, 0.55, 0.95), "pilot": Color(0.45, 0.85, 0.5),
}
const PERK_CARD_SIZE := Vector2(300, 250)
## 配られたパーツを1枚ずつめくる間隔（秒）とめくる速さ（秒）
const DEAL_STAGGER_SEC: float = 0.12
const DEAL_FLIP_SEC: float = 0.18
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
