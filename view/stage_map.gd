# ステージの見取り図（上から見た小さな図）。組み立ての画面で、そのラウンドのステージを見せる。
# ステージの辞書（data/stages.json の1つ）を読んで描くだけ。
extends Control

const COL_FLOOR := Color(0.2, 0.19, 0.17)
const COL_WALL := Color(0.55, 0.5, 0.42)
const COL_PIT := Color(0.0, 0.0, 0.0)
const COL_PIT_EDGE := Color(0.85, 0.65, 0.15)
const COL_PACK := Color(0.45, 0.85, 1.0)
const SPAWN_COLORS: Array[Color] = [Color(0.3, 0.6, 1.0), Color(1.0, 0.55, 0.2)]

var stage: Dictionary = {}


func set_stage(st: Dictionary) -> void:
	stage = st
	queue_redraw()


func _draw() -> void:
	if stage.is_empty():
		return
	var side: float = minf(size.x, size.y)
	var origin := Vector2((size.x - side) * 0.5, (size.y - side) * 0.5)
	var half: float = float(stage["half_size"])
	var k: float = side / (2.0 * half)
	var to_px := func(x: float, z: float) -> Vector2:
		return origin + Vector2(x + half, z + half) * k
	draw_rect(Rect2(origin, Vector2(side, side)), COL_FLOOR)
	draw_rect(Rect2(origin, Vector2(side, side)), COL_WALL, false, 2.0)
	for p: Dictionary in stage["packs"]:
		draw_circle(to_px.call(float(p["x"]), float(p["z"])), maxf(2.0, 0.6 * k), COL_PACK)
	for pit: Dictionary in stage["pits"]:
		var c: Vector2 = to_px.call(float(pit["x"]), float(pit["z"]))
		draw_circle(c, float(pit["r"]) * k, COL_PIT)
		draw_arc(c, float(pit["r"]) * k, 0.0, TAU, 32, COL_PIT_EDGE, 1.5)
	for i: int in stage["spawns"].size():
		var s: Dictionary = stage["spawns"][i]
		draw_circle(to_px.call(float(s["x"]), float(s["z"])), maxf(3.0, 1.0 * k), SPAWN_COLORS[i % 2])
