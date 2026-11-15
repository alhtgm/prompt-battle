# パーツの実物（配られた1個1個）。型のIDと、その回に抽選したステータスを持つ。
extends RefCounted

## 試合の中で一意なID
var uid: int = 0
## 型（PartDef）のID
var def_id: String = ""
## frame / weapon / skill
var kind: String = ""
## ステータス名 → 値
var stats: Dictionary[String, float] = {}


func get_stat(stat_name: String, fallback: float = 0.0) -> float:
	return stats.get(stat_name, fallback)


## 比較・保存用の辞書（ステータスは名前順）
func to_dict() -> Dictionary:
	var names: Array[String] = []
	names.assign(stats.keys())
	names.sort()
	var s: Dictionary = {}
	for n: String in names:
		s[n] = stats[n]
	return {"uid": uid, "def_id": def_id, "kind": kind, "stats": s}
