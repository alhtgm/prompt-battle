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


## to_dict() の辞書から作り直す（通信で受け取ったとき）
static func from_dict(d: Dictionary) -> RefCounted:
	var p: RefCounted = (load("res://core/part_instance.gd") as GDScript).new()
	p.uid = int(d.get("uid", 0))
	p.def_id = str(d.get("def_id", ""))
	p.kind = str(d.get("kind", ""))
	var s: Dictionary = d.get("stats", {})
	for k: Variant in s:
		p.stats[str(k)] = float(s[k])
	return p


## 比較・保存用の辞書（ステータスは名前順）
func to_dict() -> Dictionary:
	var names: Array[String] = []
	names.assign(stats.keys())
	names.sort()
	var s: Dictionary = {}
	for n: String in names:
		s[n] = stats[n]
	return {"uid": uid, "def_id": def_id, "kind": kind, "stats": s}
