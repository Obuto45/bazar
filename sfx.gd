extends Node
## Prosedürel ses efektleri (SFX) ve pazar ambiyansı (autoload Sfx).
## Harici ses dosyası gerekmez: tüm efektler açılışta bellekte 22 kHz 16-bit WAV olarak üretilir.

const RATE := 22050
const BUS_SFX := "SFX"
const BUS_AMB := "Ambience"

var _clips: Dictionary = {} # ad -> AudioStreamWAV
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _amb_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMB)
	_build_all_clips()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.max_polyphony = 3
		add_child(p)
		_pool.append(p)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func play(clip_name: String, vol_db := -4.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if DisplayServer.get_name() == "headless" or not _clips.has(clip_name) or _pool.is_empty():
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = _clips[clip_name]
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.25, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func play_3d(clip_name: String, world_pos: Vector3, parent: Node = null, vol_db := -2.0, pitch := 1.0, max_dist := 24.0) -> void:
	if DisplayServer.get_name() == "headless" or not _clips.has(clip_name):
		return
	var host := parent if parent else get_tree().current_scene
	if host == null or not host.is_inside_tree():
		play(clip_name, vol_db, pitch)
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_SFX
	p.stream = _clips[clip_name]
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.25, pitch + randf_range(-0.05, 0.05))
	p.unit_size = 5.0
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


## Pazar arka plan ambiyansı (hafif tatlı pazar uğultusu + rüzgar).
func set_ambience(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if on:
		if _amb_player == null:
			_amb_player = AudioStreamPlayer.new()
			_amb_player.bus = BUS_AMB
			_amb_player.stream = _clips["ambience"]
			_amb_player.volume_db = -21.0
			add_child(_amb_player)
		if not _amb_player.playing:
			_amb_player.play()
	elif _amb_player and _amb_player.playing:
		_amb_player.stop()


## Çeşme için 3D döngülü su şırıltısı kaynağı döndürür.
func make_fountain_audio() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_AMB
	p.stream = _clips["fountain"]
	p.volume_db = -14.0
	p.unit_size = 3.2
	p.max_distance = 16.0
	p.autoplay = DisplayServer.get_name() != "headless"
	return p


# ---------- Prosedürel WAV Sentezleyici ----------

func _make_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s := clampf(samples[i], -1.0, 1.0)
		data.encode_s16(i * 2, clampi(int(s * 32767.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _build_all_clips() -> void:
	_clips["coin"] = _synth_coin()
	_clips["tip"] = _synth_tip()
	_clips["place"] = _synth_place()
	_clips["crate_pick"] = _synth_crate_pick()
	_clips["crate_throw"] = _synth_whoosh()
	_clips["crate_hit"] = _synth_wood_thud()
	_clips["price_up"] = _synth_tick(980.0)
	_clips["price_down"] = _synth_tick(660.0)
	_clips["bell"] = _synth_bell()
	_clips["haggle"] = _synth_haggle()
	_clips["happy"] = _synth_happy()
	_clips["angry"] = _synth_angry()
	_clips["whistle"] = _synth_whistle()
	_clips["event"] = _synth_fanfare()
	_clips["upgrade"] = _synth_upgrade()
	_clips["step"] = _synth_step()
	_clips["day_end"] = _synth_day_end()
	_clips["ui_click"] = _synth_tick(820.0)
	_clips["fountain"] = _synth_water_loop(2.2)
	_clips["ambience"] = _synth_ambience_loop(3.2)


func _synth_coin() -> AudioStreamWAV:
	var n := int(RATE * 0.36)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var env1 := exp(-t * 18.0)
		var s1 := (sin(TAU * 1318.5 * t) * 0.55 + sin(TAU * 2637.0 * t) * 0.25) * env1
		var t2 := maxf(t - 0.065, 0.0)
		var env2 := exp(-t2 * 11.0) if t >= 0.065 else 0.0
		var s2 := (sin(TAU * 1760.0 * t2) * 0.6 + sin(TAU * 3520.0 * t2) * 0.28) * env2
		buf[i] = (s1 + s2) * 0.58
	return _make_wav(buf)


func _synth_tip() -> AudioStreamWAV:
	var n := int(RATE * 0.48)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [1046.5, 1318.5, 1568.0, 2093.0]
	for i in n:
		var t := float(i) / float(RATE)
		var val := 0.0
		for k in notes.size():
			var dt := t - k * 0.055
			if dt >= 0.0:
				val += (sin(TAU * notes[k] * dt) * 0.6 + sin(TAU * notes[k] * 2.0 * dt) * 0.2) * exp(-dt * 12.0)
		buf[i] = val * 0.36
	return _make_wav(buf)


func _synth_place() -> AudioStreamWAV:
	var n := int(RATE * 0.13)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var freq := lerpf(320.0, 620.0, minf(t / 0.06, 1.0))
		phase += TAU * freq / float(RATE)
		var env := sin(minf(t / 0.01, 1.0) * PI * 0.5) * exp(-t * 32.0)
		buf[i] = sin(phase) * env * 0.65
	return _make_wav(buf)


func _synth_crate_pick() -> AudioStreamWAV:
	var n := int(RATE * 0.20)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var thud := sin(TAU * (150.0 - t * 240.0) * t) * exp(-t * 24.0) * 0.7
		var clack := sin(TAU * 420.0 * maxf(t - 0.045, 0.0)) * (exp(-maxf(t - 0.045, 0.0) * 34.0) if t > 0.045 else 0.0) * 0.4
		lp += 0.22 * (rng.randf_range(-1.0, 1.0) - lp)
		buf[i] = (thud + clack + lp * exp(-t * 28.0) * 0.25) * 0.72
	return _make_wav(buf)


func _synth_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.24)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var env := sin(minf(t / 0.24, 1.0) * PI)
		var cut := lerpf(0.08, 0.35, env)
		lp += cut * (rng.randf_range(-1.0, 1.0) - lp)
		buf[i] = lp * env * 0.6
	return _make_wav(buf)


func _synth_wood_thud() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.25 * (rng.randf_range(-1.0, 1.0) - lp)
		var tone := (sin(TAU * 135.0 * t) * 0.65 + sin(TAU * 285.0 * t) * 0.35) * exp(-t * 20.0)
		var bounce := sin(TAU * 195.0 * maxf(t - 0.09, 0.0)) * (exp(-maxf(t - 0.09, 0.0) * 28.0) if t > 0.09 else 0.0) * 0.35
		buf[i] = (tone + bounce + lp * exp(-t * 32.0) * 0.3) * 0.72
	return _make_wav(buf)


func _synth_tick(freq: float) -> AudioStreamWAV:
	var n := int(RATE * 0.065)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		buf[i] = (sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 1.5 * t) * 0.25) * exp(-t * 58.0) * 0.55
	return _make_wav(buf)


func _synth_bell() -> AudioStreamWAV:
	var n := int(RATE * 1.05)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var partials := [[1180.0, 0.55, 3.8], [2360.0, 0.32, 5.5], [3515.0, 0.22, 8.2], [4920.0, 0.14, 12.0]]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for p in partials:
			v += sin(TAU * float(p[0]) * t) * float(p[1]) * exp(-t * float(p[2]))
		# İkinci hafif şıngırtı
		if t > 0.18:
			var t2 := t - 0.18
			v += (sin(TAU * 1180.0 * t2) * 0.35 + sin(TAU * 2360.0 * t2) * 0.18) * exp(-t2 * 4.5)
		buf[i] = clampf(v * 0.55, -0.95, 0.95)
	return _make_wav(buf)


func _synth_haggle() -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var f := lerpf(320.0, 440.0, clampf(t / 0.22, 0.0, 1.0))
		phase += TAU * f / float(RATE)
		var env := sin(minf(t / 0.28, 1.0) * PI)
		buf[i] = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.2) * env * 0.45
	return _make_wav(buf)


func _synth_happy() -> AudioStreamWAV:
	var n := int(RATE * 0.30)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var freqs := [523.25, 659.25, 783.99]
	for i in n:
		var t := float(i) / float(RATE)
		var idx := mini(int(t / 0.08), 2)
		var dt := t - idx * 0.08
		buf[i] = sin(TAU * freqs[idx] * dt) * exp(-dt * 14.0) * 0.45
	return _make_wav(buf)


func _synth_angry() -> AudioStreamWAV:
	var n := int(RATE * 0.36)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var f := lerpf(240.0, 125.0, minf(t / 0.36, 1.0))
		phase += TAU * f / float(RATE)
		var saw := sin(phase) * 0.6 + sin(phase * 2.0) * 0.28 + sin(phase * 3.0) * 0.14
		buf[i] = saw * exp(-t * 5.2) * 0.45
	return _make_wav(buf)


func _synth_whistle() -> AudioStreamWAV:
	# İki vuruşlu zabıta düdüğü (trill modülasyonlu)
	var n := int(RATE * 0.62)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var gate := 1.0 if (t < 0.22 or (t >= 0.29 and t < 0.56)) else 0.0
		var trill := 0.8 + 0.2 * sin(TAU * 36.0 * t)
		var freq := 2720.0 + 115.0 * sin(TAU * 36.0 * t)
		phase += TAU * freq / float(RATE)
		var env := gate * minf(t / 0.015, 1.0) * minf(maxf(0.62 - t, 0.0) / 0.05, 1.0)
		buf[i] = (sin(phase) * 0.72 + sin(phase * 2.0) * 0.14) * trill * env * 0.45
	return _make_wav(buf)


func _synth_fanfare() -> AudioStreamWAV:
	var n := int(RATE * 0.68)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [[523.25, 0.0], [659.25, 0.11], [783.99, 0.22], [1046.5, 0.34]]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for nd in notes:
			var dt := t - float(nd[1])
			if dt >= 0.0:
				var f := float(nd[0])
				v += (sin(TAU * f * dt) * 0.6 + sin(TAU * f * 2.0 * dt) * 0.22) * exp(-dt * 5.5)
		buf[i] = v * 0.36
	return _make_wav(buf)


func _synth_upgrade() -> AudioStreamWAV:
	var n := int(RATE * 0.58)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [587.33, 739.99, 880.0, 1174.66]
	for i in n:
		var t := float(i) / float(RATE)
		var knock := sin(TAU * 180.0 * t) * exp(-t * 32.0) * 0.5
		var v := knock
		for k in notes.size():
			var dt := t - (0.06 + k * 0.07)
			if dt >= 0.0:
				v += (sin(TAU * notes[k] * dt) * 0.55 + sin(TAU * notes[k] * 2.0 * dt) * 0.2) * exp(-dt * 7.5)
		buf[i] = clampf(v * 0.45, -0.95, 0.95)
	return _make_wav(buf)


func _synth_step() -> AudioStreamWAV:
	var n := int(RATE * 0.085)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.14 * (rng.randf_range(-1.0, 1.0) - lp)
		var th := sin(TAU * (110.0 - t * 400.0) * t) * exp(-t * 48.0) * 0.55
		buf[i] = (th + lp * exp(-t * 42.0) * 0.35) * 0.48
	return _make_wav(buf)


func _synth_day_end() -> AudioStreamWAV:
	var n := int(RATE * 1.45)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var freqs := [440.0, 659.25, 880.0, 1318.5]
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in freqs.size():
			v += sin(TAU * freqs[k] * t) * (0.42 / float(k + 1)) * exp(-t * (1.8 + k * 0.7))
		buf[i] = v * 0.65
	return _make_wav(buf)


func _synth_water_loop(sec: float) -> AudioStreamWAV:
	var n := int(RATE * sec)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += 0.24 * (w - lp1)
		lp2 += 0.06 * (lp1 - lp2)
		var band := lp1 - lp2 # yumuşak su şırıltısı bandı
		var mod := 0.75 + 0.25 * sin(TAU * 2.0 * t / sec) * sin(TAU * 5.0 * t / sec + 0.7)
		buf[i] = band * mod * 0.42
	# Kesintisiz döngü için baş/son çapraz geçiş
	var fade := mini(int(RATE * 0.12), n / 4)
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = lerpf(buf[n - fade + i], buf[i], k)
	return _make_wav(buf, true)


func _synth_ambience_loop(sec: float) -> AudioStreamWAV:
	var n := int(RATE * sec)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += 0.07 * (w - lp1)
		lp2 += 0.018 * (lp1 - lp2)
		var murmur := (lp1 - lp2) * (0.7 + 0.3 * sin(TAU * 3.0 * t / sec))
		var breeze := lp2 * (0.8 + 0.2 * cos(TAU * 1.0 * t / sec))
		buf[i] = (murmur * 0.55 + breeze * 0.45) * 0.45
	var fade := mini(int(RATE * 0.18), n / 4)
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = lerpf(buf[n - fade + i], buf[i], k)
	return _make_wav(buf, true)
