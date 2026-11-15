# 試合ごとの種から作る乱数。ゲーム内の乱数はすべてこのクラスを通す。
# fork() で用途ごとの子の乱数を作れる。子の種は親の種と名前だけで決まるので、呼ぶ順番に左右されない。
extends RefCounted

const MASK32: int = 0xFFFFFFFF
const FNV_PRIME: int = 16777619
const FNV_BASIS_LO: int = 2166136261
const FNV_BASIS_HI: int = 0x811C9DC5 ^ 0x5BD1E995

var _seed: int
var _rng: RandomNumberGenerator


func _init(seed_value: int) -> void:
	_seed = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value


## 作ったときの種
func get_seed() -> int:
	return _seed


## 今の内部状態（保存と再現用）
func get_state() -> int:
	return _rng.state


func set_state(value: int) -> void:
	_rng.state = value


## 名前つきの子の乱数を作る。同じ種・同じ名前なら必ず同じ子になる
func fork(label: String) -> RefCounted:
	var script: GDScript = get_script()
	return script.new(derive_seed(_seed, label))


## 0 以上 1 未満
func randf() -> float:
	return _rng.randf()


## from 以上 to 以下
func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## from 以上 to 以下の整数
func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## 確率 p で true
func chance(p: float) -> bool:
	return _rng.randf() < p


## 配列から1つ選ぶ。空なら null
func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]


## 配列をその場で並べ替える（Array.shuffle() は全体の乱数を使うので使わない）
func shuffle(items: Array) -> void:
	for i: int in range(items.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


## 重複なしで count 個選んだ新しい配列を返す。元の配列は変えない
func sample(items: Array, count: int) -> Array:
	var copy: Array = items.duplicate()
	shuffle(copy)
	return copy.slice(0, mini(count, copy.size()))


## 親の種と名前から子の種を作る（FNV-1a を2本使って64ビットにする）
static func derive_seed(parent_seed: int, label: String) -> int:
	var bytes: PackedByteArray = ("%d/%s" % [parent_seed, label]).to_utf8_buffer()
	var lo: int = _fnv1a32(bytes, FNV_BASIS_LO)
	var hi: int = _fnv1a32(bytes, FNV_BASIS_HI & MASK32)
	return (hi << 32) | lo


static func _fnv1a32(bytes: PackedByteArray, basis: int) -> int:
	var h: int = basis
	for b: int in bytes:
		h = ((h ^ b) * FNV_PRIME) & MASK32
	return h
