# 効果音をその場で作る係（音のファイルを使わない）。金属の部分音（倍音の並ばない高い音）とノイズを重ねて、鎖や鉄の音にする。
# 乱数は使わず、時刻から作る決まったノイズを使う。作った音は使い回す。値は view/look.gd。
extends RefCounted

const Look := preload("res://view/look.gd")

const RATE: int = 22050

static var _cache: Dictionary = {}


## 鎖を巻き上げながら、相手を床に引きずる音（くり返して鳴らす）。ガリガリこする音に、鎖の輪が当たるチャリチャリという音を重ねる
static func chain_drag() -> AudioStreamWAV:
	if _cache.has("chain_drag"):
		return _cache["chain_drag"]
	var n: int = int(RATE * 1.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var hp_prev: float = 0.0
	for k: int in n:
		var t: float = float(k) / RATE
		# こする音：細かいノイズを高い音だけ残し、ざらつきの強さを小刻みに変える
		var raw: float = _noise(k)
		lp += (raw - lp) * 0.35
		var hi: float = raw - lp
		var grit: float = 0.55 + 0.45 * absf(_noise(k / 37 + 9001))
		var scrape: float = (hi * 0.8 + (lp - hp_prev) * 2.0) * grit
		hp_prev = lp
		# 鉄が鳴る：高い部分音が、こすれに合わせてかすかに鳴り続ける
		var ring: float = (sin(TAU * 1870.0 * t) + 0.7 * sin(TAU * 2930.0 * t) + 0.5 * sin(TAU * 4410.0 * t)) \
			* 0.06 * grit
		# 鎖の輪が当たる音：だいたい 0.07 秒ごとに、少しずれて「チャリ」と鳴る
		var clink: float = 0.0
		var period: float = 0.071
		var idx: int = int(t / period)
		for back: int in 2:
			var j: int = idx - back
			var t0: float = j * period + 0.012 * _noise(j * 131 + 7)
			var dtc: float = t - t0
			if dtc >= 0.0:
				var pitch: float = 1.0 + 0.12 * _noise(j * 17 + 3)
				clink += exp(-dtc * 70.0) * (sin(TAU * 2600.0 * pitch * dtc) + 0.6 * sin(TAU * 4100.0 * pitch * dtc) \
					+ 0.4 * sin(TAU * 6300.0 * pitch * dtc)) * 0.35
		buf[k] = clampf(scrape * 0.45 + ring + clink, -1.0, 1.0) * Look.SFX_VOLUME
	# くり返したときの継ぎ目が鳴らないよう、端を短く重ね合わせる
	var fade: int = int(RATE * 0.02)
	for k: int in fade:
		var a: float = float(k) / fade
		buf[k] = buf[k] * a + buf[n - fade + k] * (1.0 - a)
	var s: AudioStreamWAV = _wav(buf.slice(0, n - fade), true)
	_cache["chain_drag"] = s
	return s


## 重い金属がぶつかる「ガキン」という音（釣り針が刺さったとき、引き寄せが終わったとき）
static func clank() -> AudioStreamWAV:
	if _cache.has("clank"):
		return _cache["clank"]
	var n: int = int(RATE * 0.45)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for k: int in n:
		var t: float = float(k) / RATE
		var body: float = exp(-t * 9.0) * (sin(TAU * 410.0 * t) + 0.8 * sin(TAU * 1130.0 * t) \
			+ 0.6 * sin(TAU * 2390.0 * t) + 0.4 * sin(TAU * 3720.0 * t))
		var hit: float = exp(-t * 80.0) * _noise(k) * 1.4
		buf[k] = clampf((body * 0.4 + hit) * Look.SFX_VOLUME, -1.0, 1.0)
	var s: AudioStreamWAV = _wav(buf, false)
	_cache["clank"] = s
	return s


## 釣り針を撃つ音：空気を切る短い音と、鎖が繰り出される音
static func launch() -> AudioStreamWAV:
	if _cache.has("launch"):
		return _cache["launch"]
	var n: int = int(RATE * 0.4)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	for k: int in n:
		var t: float = float(k) / RATE
		var raw: float = _noise(k + 5000)
		lp += (raw - lp) * 0.2
		var whoosh: float = lp * exp(-t * 12.0) * 2.0
		var thunk: float = exp(-t * 30.0) * sin(TAU * 180.0 * t) * 0.8
		var rattle: float = 0.0
		if t > 0.05:
			var dtc: float = fmod(t - 0.05, 0.03)
			rattle = exp(-dtc * 120.0) * sin(TAU * 3300.0 * dtc) * 0.3 * exp(-(t - 0.05) * 6.0)
		buf[k] = clampf((whoosh + thunk + rattle) * Look.SFX_VOLUME, -1.0, 1.0)
	var s: AudioStreamWAV = _wav(buf, false)
	_cache["launch"] = s
	return s


## -1〜1 の決まったノイズ（同じ番号なら同じ値）
static func _noise(i: int) -> float:
	var v: float = sin(float(i) * 12.9898 + 78.233) * 43758.5453
	return (v - floorf(v)) * 2.0 - 1.0


static func _wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for k: int in buf.size():
		data.encode_s16(k * 2, int(clampf(buf[k], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s
