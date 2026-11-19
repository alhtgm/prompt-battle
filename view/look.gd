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

# ---- 文字と板（画面の作り） ----
const UI_BG := Color(0.06, 0.06, 0.065)
const UI_PANEL := Color(0.09, 0.085, 0.08, 0.88)
const UI_BORDER := Color(0.42, 0.34, 0.2)
const UI_TEXT := Color(0.88, 0.85, 0.78)
const UI_ACCENT := Color(0.95, 0.72, 0.3)
