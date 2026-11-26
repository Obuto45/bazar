extends Node
## Prosedürel ses efektleri (SFX), Türk kamyonet havalı kornası, Hicaz makamında Arabesk müzik ve pazar ambiyansı.

const RATE := 22050
const BUS_SFX := "SFX"
const BUS_AMB := "Ambience"

var _clips: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _amb_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMB)
	_build_all_clips()
	for i in 12:
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


func get_clip(clip_name: String) -> AudioStreamWAV:
	return _clips.get(clip_name, null)


func play(clip_name: String, vol_db := -4.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if DisplayServer.get_name() == "headless" or not _clips.has(clip_name) or _pool.is_empty():
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = _clips[clip_name]
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.25, pitch + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


func play_3d(clip_name: String, world_pos: Vector3, parent: Node = null, vol_db := -2.0, pitch := 1.0, max_dist := 26.0) -> void:
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
	p.pitch_scale = maxf(0.25, pitch + randf_range(-0.04, 0.04))
	p.unit_size = 5.5
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


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


## Arabesk Radyo için 3D döngülü müzik oynatıcı oluşturur.
func make_radio_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_SFX
	p.stream = _clips["arabesk"]
	p.volume_db = -5.0
	p.unit_size = 4.2
	p.max_distance = 19.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return p


## Ford Transit dizel motor rölanti / sürüş sesi.
func make_truck_engine_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_AMB
	p.stream = _clips["truck_engine"]
	p.volume_db = -14.0
	p.unit_size = 4.5
	p.max_distance = 22.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
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
	_clips["ambience"] = _synth_ambience_loop(3.0)
	# Yeni v0.5 efektleri
	_clips["air_horn"] = _synth_turkish_air_horn()
	_clips["air_horn_short"] = _synth_air_horn_short()
	_clips["truck_engine"] = _synth_truck_engine_loop(1.6)
	_clips["puff"] = _synth_smoke_puff()
	_clips["megaphone_pop"] = _synth_megaphone_pop()
	_clips["knife_swing"] = _synth_knife_swing()
	_clips["knife_hit"] = _synth_knife_hit()
	_clips["arabesk"] = _synth_arabesk_loop()


## İkonik Türk kamyonet / toptancı 5-borulu havalı korna (melodik brass akor fanfarı!).
func _synth_turkish_air_horn() -> AudioStreamWAV:
	# Klasik Türk kamyonet havalı korna ritmi: DA-DA-DA-DAAA — DAAA! (F4-F4-F4-A4-C5 + armonik boru)
	var dur := 1.65
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [
		[0.00, 0.13, 349.23],
		[0.16, 0.29, 349.23],
		[0.32, 0.45, 349.23],
		[0.48, 0.92, 440.00],
		[0.98, 1.56, 523.25],
	]
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var raw := 0.0
		for nd in notes:
			var t0: float = nd[0]; var t1: float = nd[1]; var f: float = nd[2]
			if t >= t0 and t <= t1 + 0.06:
				var lt := t - t0
				var atk := clampf(lt / 0.018, 0.0, 1.0)
				var rel := clampf((t1 + 0.06 - t) / 0.06, 0.0, 1.0) if t > t1 else 1.0
				var env := atk * rel
				# Çift borulu hafif detune brass + 5'li destek
				var f2 := f * 1.007
				var f3 := f * 1.498
				var horn := 0.0
				for h in [1.0, 2.0, 3.0, 4.0, 5.0]:
					var amp: float = 1.0 / (h * 0.85)
					horn += (sin(TAU * f * h * t) + 0.8 * sin(TAU * f2 * h * t)) * amp
				horn += (sin(TAU * f3 * t) + 0.45 * sin(TAU * f3 * 2.0 * t)) * 0.35
				raw += tanh(horn * 0.55) * env
		lp += 0.42 * (raw - lp)
		buf[i] = clampf(lp * 0.78, -0.96, 0.96)
	return _make_wav(buf)


## Kısa çift vuruşlu havalı korna ("DÜT-DÜÜÜT!").
func _synth_air_horn_short() -> AudioStreamWAV:
	var dur := 0.85
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var blasts := [[0.0, 0.16, 392.0], [0.24, 0.74, 493.88]]
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var raw := 0.0
		for b in blasts:
			var t0: float = b[0]; var t1: float = b[1]; var f: float = b[2]
			if t >= t0 and t <= t1 + 0.06:
				var env := clampf((t - t0) / 0.015, 0.0, 1.0) * (clampf((t1 + 0.06 - t) / 0.06, 0.0, 1.0) if t > t1 else 1.0)
				var h := sin(TAU * f * t) + 0.7 * sin(TAU * f * 2.0 * t) + 0.45 * sin(TAU * f * 3.0 * t) + 0.5 * sin(TAU * f * 1.25 * t)
				raw += tanh(h * 0.65) * env
		lp += 0.45 * (raw - lp)
		buf[i] = clampf(lp * 0.75, -0.96, 0.96)
	return _make_wav(buf)


## Dizel Ford Transit motor rölanti sesi (döngülü).
func _synth_truck_engine_loop(sec: float) -> AudioStreamWAV:
	var n := int(RATE * sec)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var lp := 0.0
	var base_f := 42.0 / sec * sec
	for i in n:
		var t := float(i) / float(RATE)
		var chug := sin(TAU * 15.0 * t) * 0.3 + 0.7
		var rumble := sin(TAU * base_f * t) * 0.55 + sin(TAU * base_f * 2.0 * t) * 0.32 + sin(TAU * base_f * 3.0 * t) * 0.16
		var clatter := rng.randf_range(-1.0, 1.0) * 0.25 * chug
		lp += 0.09 * ((rumble * chug + clatter) - lp)
		buf[i] = clampf(lp * 0.62, -0.9, 0.9)
	var fade := mini(int(RATE * 0.08), n / 4)
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = lerpf(buf[n - fade + i], buf[i], k)
	return _make_wav(buf, true)


## Sigara / puro nefes çekme çıtırtısı + duman üfleme sesi.
func _synth_smoke_puff() -> AudioStreamWAV:
	var dur := 0.72
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 707
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		if t < 0.26:
			# İçe çekme + ince kor çıtırtısı
			var env := sin((t / 0.26) * PI)
			lp1 += 0.28 * (w - lp1)
			var crackle := (rng.randf_range(-1.0, 1.0) * 0.7) if rng.randf() < 0.025 else 0.0
			buf[i] = (lp1 * 0.35 + crackle * 0.3) * env
		elif t >= 0.32:
			# Yumuşak duman üfleme
			var dt := (t - 0.32) / 0.40
			var env := sin(clampf(dt, 0.0, 1.0) * PI)
			lp1 += 0.14 * (w - lp1)
			lp2 += 0.03 * (lp1 - lp2)
			buf[i] = (lp1 - lp2) * env * 0.55
		else:
			buf[i] = 0.0
	return _make_wav(buf)


## Megafon açma / anons bip + hafif parazit.
func _synth_megaphone_pop() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	for i in n:
		var t := float(i) / float(RATE)
		var chirp := sin(TAU * lerpf(1650.0, 2350.0, minf(t / 0.08, 1.0)) * t) * exp(-t * 22.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.35
		buf[i] = clampf((chirp * 0.55 + click) * 0.7, -0.9, 0.9)
	return _make_wav(buf)


## Meyve bıçağı savurma vınlaması.
func _synth_knife_swing() -> AudioStreamWAV:
	var n := int(RATE * 0.18)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 616
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var env := sin(minf(t / 0.18, 1.0) * PI)
		lp += lerpf(0.55, 0.14, t / 0.18) * (rng.randf_range(-1.0, 1.0) - lp)
		var ring := sin(TAU * 2900.0 * t) * exp(-t * 28.0) * 0.18
		buf[i] = clampf(lp * env * 0.65 + ring, -0.95, 0.95)
	return _make_wav(buf)


## Saldırı isabet sesi (komik tokat/darbe + kısa uyarı).
func _synth_knife_hit() -> AudioStreamWAV:
	var n := int(RATE * 0.32)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 617
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		var punch := sin(TAU * lerpf(210.0, 68.0, minf(t / 0.18, 1.0)) * t) * exp(-t * 14.0)
		var sting := sin(TAU * 980.0 * t) * exp(-t * 24.0) * 0.28
		buf[i] = clampf((punch * 0.72 + lp * exp(-t * 20.0) * 0.4 + sting) * 0.85, -0.95, 0.95)
	return _make_wav(buf)


## Hicaz makamında (D - Eb - F# - G - A - Bb - C# - D) duygulu Arabesk yaylı + bağlama + darbuka döngüsü (8 sn)!
func _synth_arabesk_loop() -> AudioStreamWAV:
	var bpm := 100.0
	var beat := 60.0 / bpm # 0.60 sn
	var total_beats := 16.0 # 9.6 sn pürüzsüz tam cümle
	var dur := total_beats * beat
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Hicaz notaları (Hz): D4=293.66, Eb4=311.13, F#4=369.99, G4=392.00, A4=440.00, Bb4=466.16, C#5=554.37, D5=587.33
	# [başlangıç_vuruş, süre_vuruş, frekans]
	var melody := [
		[0.0, 1.5, 440.00], [1.5, 0.5, 466.16], [2.0, 1.0, 440.00], [3.0, 1.0, 392.00],
		[4.0, 1.5, 369.99], [5.5, 0.5, 392.00], [6.0, 1.0, 369.99], [7.0, 1.0, 311.13],
		[8.0, 1.5, 587.33], [9.5, 0.5, 554.37], [10.0, 1.0, 466.16], [11.0, 1.0, 440.00],
		[12.0, 1.0, 392.00], [13.0, 0.5, 369.99], [13.5, 0.5, 311.13], [14.0, 2.0, 293.66],
	]
	var baglama := [293.66, 440.0, 369.99, 440.0, 311.13, 440.0, 369.99, 311.13]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1984
	var lp_str := 0.0
	var lead_phase := 0.0
	var prev_freq := 440.0

	for i in n:
		var t := float(i) / float(RATE)
		var b_pos := t / beat

		# 1) Arabesk yaylı (keman/viyola) vibrato + glissando melodi
		var target_f := 293.66
		var m_env := 0.0
		for nd in melody:
			var b0: float = nd[0]; var bl: float = nd[1]; var f: float = nd[2]
			if b_pos >= b0 and b_pos < b0 + bl:
				target_f = f
				var lt := (b_pos - b0) / bl
				m_env = sin(clampf(lt / 0.14, 0.0, 1.0) * PI * 0.5) * (1.0 - maxf(lt - 0.86, 0.0) / 0.14)
				break
		prev_freq = lerpf(prev_freq, target_f, 0.0045) # duygulu yaylı kaydırma (glissando)
		var vib := 1.0 + 0.013 * sin(TAU * 5.6 * t) # yoğun arabesk vibrato
		lead_phase += TAU * (prev_freq * vib) / float(RATE)
		var saw := sin(lead_phase) * 0.55 + sin(lead_phase * 2.0) * 0.28 + sin(lead_phase * 3.0) * 0.16 + sin(lead_phase * 4.0) * 0.08
		lp_str += 0.24 * (saw * m_env - lp_str)

		# 2) Bağlama / Ud arpeji (her yarım vuruşta)
		var step8 := int(floor(b_pos * 2.0))
		var st_dt := (b_pos * 2.0 - float(step8)) * (beat * 0.5)
		var bf: float = baglama[step8 % baglama.size()] * 0.5
		var pluck := (sin(TAU * bf * st_dt) * 0.6 + sin(TAU * bf * 2.0 * st_dt) * 0.35 + sin(TAU * bf * 3.0 * st_dt) * 0.15) * exp(-st_dt * 9.5)

		# 3) Darbuka ritmi (4 vuruşluk Düm - Tek - Tek - Düm - Tek)
		var bar_b := fmod(b_pos, 4.0)
		var perc := 0.0
		# Düm (0.0 ve 2.5)
		for db: float in [0.0, 2.5]:
			var dt_d := (bar_b - db) * beat
			if dt_d >= 0.0 and dt_d < 0.22:
				perc += sin(TAU * lerpf(130.0, 68.0, dt_d / 0.16) * dt_d) * exp(-dt_d * 18.0) * 0.55
		# Tek (1.0, 1.5, 3.0, 3.5)
		for tb: float in [1.0, 1.5, 3.0, 3.5]:
			var dt_t := (bar_b - tb) * beat
			if dt_t >= 0.0 and dt_t < 0.09:
				perc += (sin(TAU * 480.0 * dt_t) * 0.4 + rng.randf_range(-1.0, 1.0) * 0.35) * exp(-dt_t * 44.0) * 0.35

		# 4) Derin D2 bas dem (drone)
		var bass := sin(TAU * 73.42 * t) * 0.18 + sin(TAU * 146.83 * t) * 0.10

		buf[i] = clampf(lp_str * 0.52 + pluck * 0.28 + perc * 0.34 + bass * 0.25, -0.92, 0.92)
	var fade := mini(int(RATE * 0.08), n / 8)
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = lerpf(buf[n - fade + i], buf[i], k)
	return _make_wav(buf, true)


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
		lp += lerpf(0.08, 0.35, env) * (rng.randf_range(-1.0, 1.0) - lp)
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
