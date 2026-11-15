# 操縦エージェントの共通の入口。バトルとはこの3つのメソッドだけでやり取りする。
# 中身（仮の頭脳・本番のLLM・記録の再生）はこれを継承して差し替える。
extends RefCounted


## ラウンドの始めに1回だけ呼ぶ。試合中に変わらないもの（プロンプト、機体の説明、ルール）を渡す
## build は機体の説明の辞書（BattleSim.build_summary の形）、rules は data/rules.json の中身
func begin(_prompt: String, _build: Dictionary, _rules: Dictionary) -> void:
	pass


## 考えるたびに呼ぶ。すぐに戻り、答えは後から poll() で受け取る
func request(_observation: Dictionary) -> void:
	pass


## 答えが届いていれば方針の辞書を返し、まだなら空の辞書を返す
## now は今の試合時間（秒）。仮の頭脳は試合時間で遅れを数える。本番のLLMは無視してよい
## 方針の形：{"intent": "charge", "skill": 0 または null, "say": "一言"}
func poll(_now: float) -> Dictionary:
	return {}
