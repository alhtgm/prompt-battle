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
## 壁の外に立てる松明（view/arena/torch.gd）。置く場所は四隅と各辺の真ん中（-1〜1 の割合 × 壁までの距離）
const TORCH_SPOTS: Array[Vector2] = [
	Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0),
	Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1),
]
## 壁の外側へどれだけ離すか、柱の高さ
const TORCH_OUTSET: float = 0.9
const TORCH_HEIGHT: float = 2.0
## 火の色と光の色・明るさ・届く距離・減り方（明るすぎないよう、真ん中の電球より弱く、壁ぎわ数メートルだけ照らす）
const TORCH_FLAME_COLOR := Color(1.0, 0.6, 0.2)
const TORCH_LIGHT_COLOR := Color(1.0, 0.55, 0.22)
const TORCH_ENERGY: float = 6.0
const TORCH_RANGE: float = 10.0
const TORCH_ATTENUATION: float = 1.2
## 明るさの揺れの大きさ（0.2 なら ±20%）と、火の粉の数
const TORCH_FLICKER: float = 0.2
const TORCH_EMBERS: int = 6
## 床を何メートル四方のタイルに分けるか（1つの物を照らせる光は8つまでなので、
## 床を分けて、どのタイルにも近くの光だけが当たるようにする。Compatibility の制限）
const FLOOR_TILE: float = 5.0

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
