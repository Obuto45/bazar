extends Node
## Prosedürel ses efektleri (SFX), Türk kamyonet havalı kornası, Hicaz makamında Arabesk müzik ve pazar ambiyansı.
## v0.6: Hicaz menü müziği (bağlama + darbuka), hava durumu sesleri (yağmur / rüzgar / gök gürültüsü),
## zengin pazar ambiyansı (kalabalık uğultusu, uzak satıcı bağırışları, kuşlar, trafik) ve yeni oyun efektleri.
## Kısa efektler açılışta üretilir; uzun döngüler açılışı yavaşlatmasın diye arka plan iş parçacığında sentezlenir.

const RATE := 22050
const BUS_SFX := "SFX"
const BUS_AMB := "Ambience"
const BUS_MUSIC := "Music"

## Toptancı (manav) kamyoneti için rastgele çalınan 5 gerçek Hİ-DO havalı korna (mono 44.1 kHz OGG).
const TRUCK_HORN_NAMES: Array[String] = [
	"horn_01_islik",
	"horn_02_salyangoz",
	"horn_04_tekli_55cm",
	"horn_05_ikili_duz",
	"horn_08_arap",
]
const TRUCK_HORN_STREAMS: Array[AudioStream] = [
	preload("res://audio/horns/horn_01_islik.ogg"),
	preload("res://audio/horns/horn_02_salyangoz.ogg"),
	preload("res://audio/horns/horn_04_tekli_55cm.ogg"),
	preload("res://audio/horns/horn_05_ikili_duz.ogg"),
	preload("res://audio/horns/horn_08_arap.ogg"),
]

const AMB_VOL_DB := -26.0
const MENU_VOL_DB := -10.0
const RAIN_VOL_DB := -20.0
const WIND_VOL_DB := -22.0

## _build_all_clips() süresi (ms) ve arka plan sentezinin toplam süresi (ms) — ölçüm için.
var build_ms := 0
var bg_build_ms := 0

var _clips: Dictionary = {}
var _clip_us: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0
var _headless := false
var _amb_player: AudioStreamPlayer
var _amb_on := false
var _amb_timer := 4.0
var _menu_player: AudioStreamPlayer
var _menu_on := false
var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _weather := "clear"
var _thunder_timer := 20.0
## Radyo: Pixabay İçerik Lisanslı 10 arabesk parça (kaynaklar audio/radio/KAYNAKLAR.md). Her radyo kendi sırasıyla çalar.
const RADIO_TRACKS: Array[String] = [
	"res://audio/radio/askin_kaderi.ogg", "res://audio/radio/ayrilamam.ogg", "res://audio/radio/bilemezsin.ogg",
	"res://audio/radio/bu_sevda_degil.ogg", "res://audio/radio/dus_bahcesi.ogg", "res://audio/radio/goruyorum.ogg",
	"res://audio/radio/gulusum_var.ogg", "res://audio/radio/harap_oldum.ogg", "res://audio/radio/kirik_saatler.ogg",
	"res://audio/radio/yanimda_kal.ogg",
]
const RADIO_TITLES: Array[String] = [
	"Aşkın Kaderi", "Ayrılamam", "Bilemezsin", "Bu Sevda Değil", "Düş Bahçesi", "Görüyorum Acı Çektiğini",
	"Gülüşüm Var", "Harap Oldum", "Kırık Saatler", "Yanımda Kal",
]
var _radio_streams := {} # yol -> AudioStream (ilk kullanımda yüklenir)
var _gen_task := -1
var _gen_abort := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMB)
	_ensure_bus(BUS_MUSIC)
	var t0 := Time.get_ticks_msec()
	_build_all_clips()
	build_ms = Time.get_ticks_msec() - t0
	print_verbose("Sfx: %d klip %d ms içinde üretildi" % [_clips.size(), build_ms])
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.max_polyphony = 3
		add_child(p)
		_pool.append(p)
	set_process(false)
	# Ses çıkışı olmayan (headless / sunucu) süreçte uzun döngüleri hiç üretme.
	if not _headless:
		_gen_task = WorkerThreadPool.add_task(_bg_generate, false, "Sfx uzun döngü sentezi")


func _exit_tree() -> void:
	_gen_abort = true
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
	# Çıkışta çalan döngüleri durdur (ses sunucusunda askıda oynatma kalmasın).
	for c in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
			(c as AudioStreamPlayer).stream = null


## Arka planda (öncelik sırasıyla) üretilen klipler: [ad, üretici].
func _bg_jobs() -> Array:
	return [
		# v0.6 kısa efektleri (~birkaç yüz ms; hazır olmadan çağrılırsa play() sessizce atlar)
		["spray", _synth_spray],
		["combo", _synth_combo],
		["steal", _synth_steal],
		["catch", _synth_catch],
		["quest_done", _synth_quest_done],
		["rep_up", _synth_rep_up],
		["rep_down", _synth_rep_down],
		["cat", _synth_cat],
		["pigeon_flap", _synth_pigeon_flap],
		["tea", _synth_tea],
		["squelch", _synth_squelch],
		["cash_register", _synth_cash_register],
		["kid_laugh", _synth_kid_laugh],
		["whoosh_big", _synth_whoosh_big],
		["thunder", _synth_thunder],
		# uzun döngüler
		["menu_music", _synth_menu_music],
		["amb_bed", _synth_amb_bed],
		["amb_vendor1", _synth_vendor_call.bind(0)],
		["amb_vendor2", _synth_vendor_call.bind(1)],
		["amb_vendor3", _synth_vendor_call.bind(2)],
		["amb_bird1", _synth_bird.bind(0)],
		["amb_bird2", _synth_bird.bind(1)],
		["amb_bird3", _synth_bird.bind(2)],
		["amb_horn", _synth_far_horn],
		["amb_moped", _synth_moped],
		["rain_loop", _synth_rain_loop],
		["wind_loop", _synth_wind_loop],
	]


## Arka plan iş parçacığı: yalnızca veri üretir; sonuçlar call_deferred ile ana iş parçacığına teslim edilir.
func _bg_generate() -> void:
	var total0 := Time.get_ticks_msec()
	for j in _bg_jobs():
		if _gen_abort:
			return
		var t0 := Time.get_ticks_usec()
		var w: AudioStreamWAV = (j[1] as Callable).call()
		_on_bg_clip.call_deferred(String(j[0]), w, Time.get_ticks_usec() - t0)
	_on_bg_done.call_deferred(Time.get_ticks_msec() - total0)


func _on_bg_clip(clip_name: String, w: AudioStreamWAV, us: int) -> void:
	_clips[clip_name] = w
	_clip_us[clip_name] = us
	match clip_name:
		"menu_music":
			if _menu_on:
				set_menu_music(true)
		"amb_bed":
			if _amb_on and _amb_player:
				var pos := _amb_player.get_playback_position() if _amb_player.playing else 0.0
				_amb_player.stream = w
				_amb_player.play(fmod(pos, w.get_length()))
		"rain_loop", "wind_loop":
			if _weather != "clear":
				_apply_weather(false)


func _on_bg_done(total_ms: int) -> void:
	bg_build_ms = total_ms
	print_verbose("Sfx: arka plan döngüleri %d ms içinde üretildi" % total_ms)
	if _gen_task != -1:
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


## Klibi döndürür. Arka planda henüz üretilmemişse (veya headless süreçteyse) o anda üretir.
func get_clip(clip_name: String) -> AudioStream:
	if not _clips.has(clip_name):
		for j in _bg_jobs():
			if j[0] == clip_name:
				_clips[clip_name] = (j[1] as Callable).call()
				break
	return _clips.get(clip_name, null)


## Seçili 5 gerçek manav kornasından (0..4) istenen akışı döndürür.
func get_truck_horn_stream(idx: int) -> AudioStream:
	if TRUCK_HORN_STREAMS.is_empty():
		return _clips.get("air_horn", null)
	return TRUCK_HORN_STREAMS[posmod(idx, TRUCK_HORN_STREAMS.size())]


## Genel efekt kısma (~-6 dB) + klip başına ek kısma ve en kısa tekrar aralığı (sn).
const SFX_TRIM_DB := -6.0
const CLIP_TRIM_DB := {"pigeon_flap": -8.0, "tea_sip": -3.0, "tea_stir": -5.0, "bite_crunch": -3.0, "tea": -3.0, "amb_bird1": -6.0, "amb_bird2": -6.0, "amb_bird3": -6.0}
const CLIP_MIN_GAP := {"pigeon_flap": 1.2, "tea_sip": 0.5, "tea_stir": 0.6, "bite_crunch": 0.25, "tea": 0.6, "coin": 0.06, "step": 0.1, "ui_click": 0.04, "price_up": 0.04, "price_down": 0.04}
const DEFAULT_MIN_GAP := 0.05
var _last_play: Dictionary = {}


## true: bu klip çok yakın zamanda çalındı, atla.
func _throttled(clip_name: String) -> bool:
	var now := Time.get_ticks_msec() * 0.001
	var gap: float = CLIP_MIN_GAP.get(clip_name, DEFAULT_MIN_GAP)
	if now - float(_last_play.get(clip_name, -10.0)) < gap:
		return true
	_last_play[clip_name] = now
	return false


func play(clip_name: String, vol_db := -4.0, pitch := 1.0, pitch_jitter := 0.06) -> void:
	if DisplayServer.get_name() == "headless" or not _clips.has(clip_name) or _pool.is_empty():
		return
	if _throttled(clip_name):
		return
	vol_db += SFX_TRIM_DB + float(CLIP_TRIM_DB.get(clip_name, 0.0))
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
	if _throttled(clip_name):
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_SFX
	p.stream = _clips[clip_name]
	p.volume_db = vol_db + SFX_TRIM_DB + float(CLIP_TRIM_DB.get(clip_name, 0.0))
	p.pitch_scale = maxf(0.25, pitch + randf_range(-0.06, 0.06))
	p.unit_size = 5.5
	p.max_distance = max_dist
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	host.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


## Pazar ambiyansı: kalabalık uğultusu döngüsü + rastgele uzak olaylar (satıcı bağırışı, kuş, trafik, çay bardağı).
func set_ambience(on: bool) -> void:
	_amb_on = on
	if _headless:
		return
	if on:
		if _amb_player == null:
			_amb_player = AudioStreamPlayer.new()
			_amb_player.bus = BUS_AMB
			_amb_player.volume_db = -40.0
			add_child(_amb_player)
		var want: AudioStreamWAV = _clips.get("amb_bed", _clips["ambience"])
		if _amb_player.stream != want:
			_amb_player.stream = want
			_amb_player.stop()
		if not _amb_player.playing:
			_amb_player.volume_db = -40.0
			_amb_player.play()
		_fade(_amb_player, _amb_target_db(), 1.5)
		_amb_timer = randf_range(1.5, 4.0)
	elif _amb_player and _amb_player.playing:
		_fade(_amb_player, -50.0, 0.9, true)
	_update_process()


## Hava durumu sesi: "rain" → yağmur döngüsü (+ hafif rüzgar, ara sıra gök gürültüsü),
## "cloudy" → yumuşak rüzgar, "clear" → kapalı.
func set_weather_audio(kind: String) -> void:
	var was_rain := _weather == "rain"
	_weather = kind if kind in ["clear", "cloudy", "rain"] else "clear"
	if _weather == "rain" and not was_rain:
		_thunder_timer = randf_range(9.0, 20.0)
	if _headless:
		return
	_apply_weather(true)
	_update_process()


## Menü müziği: Hicaz makamında bağlama + darbuka döngüsü (yumuşak geçişli aç / kapa).
func set_menu_music(on: bool) -> void:
	_menu_on = on
	if _headless:
		return
	_menu_player = _set_loop(_menu_player, "menu_music", MENU_VOL_DB if on else -80.0, BUS_MUSIC, 2.0, 1.2)


func _apply_weather(fade_amb: bool) -> void:
	var rain_db := -80.0
	var wind_db := -80.0
	match _weather:
		"rain":
			rain_db = RAIN_VOL_DB
			wind_db = WIND_VOL_DB - 5.0
		"cloudy":
			wind_db = WIND_VOL_DB
	_rain_player = _set_loop(_rain_player, "rain_loop", rain_db, BUS_AMB, 3.0, 2.5)
	_wind_player = _set_loop(_wind_player, "wind_loop", wind_db, BUS_AMB, 3.0, 2.5)
	if fade_amb and _amb_on and _amb_player and _amb_player.playing:
		_fade(_amb_player, _amb_target_db(), 2.5)


func _amb_target_db() -> float:
	var db := AMB_VOL_DB if _clips.has("amb_bed") else -21.0
	if _weather == "rain":
		db -= 4.0 # yağmurda pazar tenhalaşır
	return db


## Döngülü bir oynatıcıyı yumuşakça açar / kapatır. db <= -79 → kapat. Klip henüz hazır değilse
## (arka planda üretiliyorsa) hazır olunca tekrar çağrılır.
func _set_loop(p: AudioStreamPlayer, clip: String, db: float, bus: String, fade_in: float, fade_out: float) -> AudioStreamPlayer:
	var on := db > -79.0
	if p == null:
		if not on or not _clips.has(clip):
			return null
		p = AudioStreamPlayer.new()
		p.bus = bus
		p.stream = _clips[clip]
		p.volume_db = -50.0
		add_child(p)
	if on:
		if not p.playing:
			p.volume_db = -50.0
			p.play()
		_fade(p, db, fade_in)
	elif p.playing:
		_fade(p, -50.0, fade_out, true)
	return p


func _fade(p: Node, to_db: float, time: float, stop_after := false) -> void:
	if p == null:
		return
	if p.has_meta("_fade_tw"):
		var old: Variant = p.get_meta("_fade_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, time)
	if stop_after:
		tw.tween_callback(Callable(p, "stop"))
	p.set_meta("_fade_tw", tw)


func _update_process() -> void:
	set_process(not _headless and (_amb_on or _weather == "rain"))


func _process(delta: float) -> void:
	if _amb_on:
		_amb_timer -= delta
		if _amb_timer <= 0.0:
			_amb_timer = randf_range(2.2, 6.0) * (1.6 if _weather == "rain" else 1.0)
			_play_amb_event()
	if _weather == "rain":
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = randf_range(22.0, 50.0)
			play("thunder", randf_range(-14.0, -7.0), randf_range(0.82, 1.05), 0.0)


## Rastgele bir uzak pazar olayı çalar (dinleyicinin çevresinde rastgele yönde, 3B konumlu).
func _play_amb_event() -> void:
	var rain := _weather == "rain"
	var w_vendor := 3.0
	var w_bird := 0.15 if rain else 0.8
	var w_traffic := 1.4
	var w_tea := 0.8
	var r := randf() * (w_vendor + w_bird + w_traffic + w_tea)
	if r < w_vendor:
		_play_amb_3d("amb_vendor%d" % randi_range(1, 3), randf_range(-24.0, -17.0), randf_range(0.9, 1.12), 0.0, false)
	elif r < w_vendor + w_bird:
		_play_amb_3d("amb_bird%d" % randi_range(1, 3), randf_range(-36.0, -30.0), randf_range(0.88, 1.18), randf_range(4.0, 9.0), false)
	elif r < w_vendor + w_bird + w_traffic:
		if randf() < 0.5:
			_play_amb_3d("amb_horn", randf_range(-28.0, -22.0), randf_range(0.85, 1.15), 0.0, false)
		else:
			_play_amb_3d("amb_moped", randf_range(-26.0, -20.0), randf_range(0.85, 1.15), 0.0, true)
	else:
		_play_amb_3d("tea", randf_range(-24.0, -18.0), randf_range(0.9, 1.1), 0.0, false)


func _play_amb_3d(clip: String, vol_db: float, pitch: float, height: float, sweep: bool) -> void:
	var w: AudioStreamWAV = _clips.get(clip, null)
	if w == null:
		return
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp else null
	var host := get_tree().current_scene
	if cam == null or host == null or not cam.is_inside_tree() or not host.is_inside_tree():
		play(clip, vol_db - 2.0, pitch, 0.0)
		return
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_AMB
	p.stream = w
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.max_distance = 0.0
	var ang := randf() * TAU
	var dist := randf_range(14.0, 24.0)
	var c := cam.global_position
	host.add_child(p)
	p.global_position = c + Vector3(cos(ang) * dist, height, sin(ang) * dist)
	if sweep:
		# Geçen motor: dinleyicinin bir yanından öbür yanına kayar.
		var tw := p.create_tween()
		tw.tween_property(p, "global_position", c + Vector3(cos(ang + PI * 0.8) * dist, height, sin(ang + PI * 0.8) * dist), w.get_length() / pitch)
	p.finished.connect(p.queue_free)
	p.play()


## Arabesk Radyo için 3D döngülü müzik oynatıcı oluşturur.
func make_radio_player() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = BUS_SFX
	var idx := randi() % RADIO_TRACKS.size()
	p.set_meta("radio_idx", idx)
	p.stream = _radio_stream(idx)
	p.finished.connect(radio_next.bind(p, true)) # parça bitince sıradakine geç
	p.volume_db = -5.0
	p.unit_size = 4.2
	p.max_distance = 19.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return p


func _radio_stream(idx: int) -> AudioStream:
	var path := RADIO_TRACKS[posmod(idx, RADIO_TRACKS.size())]
	if not _radio_streams.has(path):
		_radio_streams[path] = load(path)
	return _radio_streams[path]


## Radyoda sıradaki parçaya geç (aynı parça art arda gelmez). force_play: kapalıysa da çalmaya başla.
func radio_next(p: AudioStreamPlayer3D, force_play := false) -> void:
	if p == null or not is_instance_valid(p):
		return
	var n := RADIO_TRACKS.size()
	var idx := (int(p.get_meta("radio_idx", 0)) + 1 + randi() % maxi(n - 1, 1)) % n
	p.set_meta("radio_idx", idx)
	var was := p.playing
	p.stream = _radio_stream(idx)
	if (was or force_play) and DisplayServer.get_name() != "headless":
		p.play()


## Radyoyu listede dir kadar ileri/geri al; yeni sıra numarasını döndürür (tekerlek / sağ tık).
func radio_step_idx(p: AudioStreamPlayer3D, dir: int) -> int:
	return posmod(int(p.get_meta("radio_idx", 0)) + dir, RADIO_TRACKS.size()) if p else 0


## Radyoda belirli parçaya geç; radyo çalıyorsa yeni parça baştan çalar.
func radio_set(p: AudioStreamPlayer3D, idx: int) -> void:
	if p == null or not is_instance_valid(p):
		return
	idx = posmod(idx, RADIO_TRACKS.size())
	p.set_meta("radio_idx", idx)
	var was := p.playing
	p.stream = _radio_stream(idx)
	if was and DisplayServer.get_name() != "headless":
		p.play()


func radio_title(idx: int) -> String:
	return RADIO_TITLES[posmod(idx, RADIO_TITLES.size())]


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

func _make_wav(samples: PackedFloat32Array, loop := false, rate := RATE, gain := 1.0) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	var k := 32767.0 * gain
	var fi := mini(n / 2, 44) # ~2 ms giriş / ~8 ms çıkış: tık sesini önler (döngülerde yok)
	var fo := mini(n / 2, 176)
	for i in n:
		var e := 1.0
		if not loop:
			if i < fi:
				e = float(i) / float(fi)
			elif i >= n - fo:
				e = float(n - 1 - i) / float(fo)
		data.encode_s16(i * 2, int(clampf(samples[i] * k * e, -32767.0, 32767.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = n
	return w


func _add(clip_name: String, gen: Callable) -> void:
	var t0 := Time.get_ticks_usec()
	_clips[clip_name] = gen.call()
	_clip_us[clip_name] = Time.get_ticks_usec() - t0


func _build_all_clips() -> void:
	_add("coin", _synth_coin)
	_add("tip", _synth_tip)
	_add("place", _synth_place)
	_add("crate_pick", _synth_crate_pick)
	_add("crate_throw", _synth_whoosh)
	_add("crate_hit", _synth_wood_thud)
	_add("price_up", _synth_tick.bind(980.0))
	_add("price_down", _synth_tick.bind(660.0))
	_add("bell", _synth_bell)
	_add("haggle", _synth_haggle)
	_add("happy", _synth_happy)
	_add("angry", _synth_angry)
	_add("whistle", _synth_whistle)
	_add("event", _synth_fanfare)
	_add("upgrade", _synth_upgrade)
	_add("step", _synth_step)
	_add("day_end", _synth_day_end)
	_add("ui_click", _synth_tick.bind(820.0))
	_add("ambience", _synth_ambience_loop.bind(3.0))
	_add("silence", _synth_silence)
	# v0.5 efektleri + 5 gerçek Hİ-DO manav kornası
	for i in TRUCK_HORN_NAMES.size():
		_clips[TRUCK_HORN_NAMES[i]] = TRUCK_HORN_STREAMS[i]
	_add("air_horn", _synth_turkish_air_horn)
	_add("air_horn_short", _synth_air_horn_short)
	_add("truck_engine", _synth_truck_engine_loop.bind(1.6))
	_add("puff", _synth_smoke_puff)
	_add("smoke_inhale", _synth_smoke_inhale)
	_add("smoke_exhale", _synth_smoke_exhale)
	_add("ash_flick", _synth_ash_flick)
	_add("tea_sip", _synth_tea_sip)
	_add("tea_stir", _synth_tea_stir)
	_add("bite_crunch", _synth_bite_crunch)
	_add("bottle_shake", _synth_bottle_shake)
	_add("radio_tune", _synth_radio_tune)
	_add("mega_chirp", _synth_mega_chirp)
	_add("knife_spin", _synth_knife_spin)
	_add("megaphone_pop", _synth_megaphone_pop)
	_add("knife_swing", _synth_knife_swing)
	_add("knife_hit", _synth_knife_hit)
	# v0.6 efektleri arka planda üretilir (bkz. _bg_generate / make_radio_player).


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
				for hi in 5:
					var h := float(hi + 1)
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
	buf.resize(n - fade) # dikişsiz döngü: bindirilen kuyruğu at
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


## Sigara / puro derin nefes çekme: hava akışı + tütün kor çıtırtıları.
func _synth_smoke_inhale() -> AudioStreamWAV:
	var dur := 0.50
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 711
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		var env := sin(clampf(t / dur, 0.0, 1.0) * PI)
		lp += 0.24 * (w - lp)
		hp += 0.04 * (lp - hp)
		var crack := (rng.randf_range(-1.0, 1.0) * 0.95) if rng.randf() < (0.018 + 0.03 * env) else 0.0
		buf[i] = clampf(((lp - hp) * 0.42 + crack * 0.34) * env, -0.92, 0.92)
	return _make_wav(buf)


## Ağızdan duman üfleme: sıcak, yumuşak nefesli üfleme sesi.
func _synth_smoke_exhale() -> AudioStreamWAV:
	var dur := 0.76
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 719
	var lp1 := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var u := t / dur
		var w := rng.randf_range(-1.0, 1.0)
		var env := minf(u / 0.14, 1.0) * pow(maxf(1.0 - u, 0.0), 1.35)
		var cut := lerpf(0.16, 0.06, u)
		lp1 += cut * (w - lp1)
		lp2 += 0.025 * (lp1 - lp2)
		buf[i] = clampf((lp1 - lp2) * env * 0.85, -0.92, 0.92)
	return _make_wav(buf)


## Sigara / puro kül silkme: ince tırnak çıtırtısı.
func _synth_ash_flick() -> AudioStreamWAV:
	var dur := 0.14
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 733
	for i in n:
		var t := float(i) / float(RATE)
		var tap := sin(TAU * lerpf(920.0, 460.0, minf(t / 0.03, 1.0)) * t) * exp(-t * 85.0)
		var snap := rng.randf_range(-1.0, 1.0) * exp(-t * 140.0) * 0.55
		buf[i] = clampf((tap * 0.55 + snap) * 0.72, -0.9, 0.9)
	return _make_wav(buf)


## Sıcak Türk çayı yudumlama: hafif hüpürdetme + sıcak yutkunma.
func _synth_tea_sip() -> AudioStreamWAV:
	var dur := 0.4
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1938
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		if t < 0.2:
			# Yumuşak, alçak geçirilmiş hüpürtü
			var u := t / 0.2
			lp += 0.08 * (rng.randf_range(-1.0, 1.0) - lp)
			v += lp * sin(u * PI) * 1.6
		elif t >= 0.22:
			# Küçük yutkunma
			var dt := t - 0.22
			v += sin(TAU * lerpf(200.0, 130.0, minf(dt / 0.1, 1.0)) * dt) * exp(-dt * 20.0) * 0.3
		buf[i] = clampf(v * 0.6, -0.8, 0.8)
	return _make_wav(buf)


## İnce belli bardakta çay kaşığı şıngırdatarak karıştırma (6 hızlı cam-metal tınısı).
func _synth_tea_stir() -> AudioStreamWAV:
	var dur := 0.4
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hits := [[0.02, 0.8], [0.14, 0.6], [0.26, 0.7]]
	for h in hits:
		var s0 := int(float(h[0]) * RATE)
		var g: float = float(h[1])
		for k in int(0.12 * RATE):
			var j := s0 + k
			if j >= n:
				break
			var t := float(k) / float(RATE)
			# Tek yumuşak cam tınısı, sert üst harmonik yok
			buf[j] += sin(TAU * 1900.0 * t) * minf(t / 0.002, 1.0) * exp(-t * 40.0) * g * 0.3
	return _make_wav(buf)


## Çıtır susamlı simit ısırma: katmanlı kuru kabuk çıtırtısı!
func _synth_bite_crunch() -> AudioStreamWAV:
	var dur := 0.2
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var bursts := [[0.01, 0.07, 1.0], [0.09, 0.07, 0.7]]
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += 0.18 * (rng.randf_range(-1.0, 1.0) - lp) # alçak geçiren: tiz cızırtı yok
		var v := 0.0
		for b in bursts:
			var t0: float = float(b[0])
			var len_b: float = float(b[1])
			if t >= t0 and t < t0 + len_b:
				var dt := t - t0
				v += lp * sin((dt / len_b) * PI) * float(b[2])
		buf[i] = clampf(v * 1.1, -0.8, 0.8)
	return _make_wav(buf)


## Su fısfısı şişesi çalkalama: plastik içinde çalkalanan su sesi.
func _synth_bottle_shake() -> AudioStreamWAV:
	var dur := 0.48
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 616
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		var slosh := absf(sin(TAU * 4.5 * t))
		lp += lerpf(0.08, 0.24, slosh) * (w - lp)
		var glug := sin(TAU * lerpf(260.0, 520.0, slosh) * t) * 0.22 * slosh
		var env := sin(clampf(t / dur, 0.0, 1.0) * PI)
		buf[i] = clampf((lp * 0.75 + glug) * env * 0.78, -0.9, 0.9)
	return _make_wav(buf)


## Arabesk radyo frekans çevirme: kısa analog parazit + taşıyıcı ıslığı.
func _synth_radio_tune() -> AudioStreamWAV:
	var dur := 0.28
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var u := t / dur
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.35 * (w - lp)
		var env := sin(u * PI)
		var whistle := sin(TAU * lerpf(1850.0, 720.0, u) * t) * 0.35 * sin(u * PI)
		buf[i] = clampf(((w - lp) * 0.65 + whistle) * env * 0.7, -0.9, 0.9)
	return _make_wav(buf)


## El megafonu kısa çift-ton dikkat sireni.
func _synth_mega_chirp() -> AudioStreamWAV:
	var dur := 0.40
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		var f := lerpf(620.0, 1380.0, fmod(t * 5.0, 1.0))
		var env := minf(t / 0.02, 1.0) * minf((dur - t) / 0.04, 1.0)
		var sq := tanh((sin(TAU * f * t) + 0.45 * sin(TAU * f * 2.0 * t)) * 1.9)
		buf[i] = clampf(sq * env * 0.62, -0.92, 0.92)
	return _make_wav(buf)


## Meyve bıçağı pazarcı usulü hızlı çevirme vınlaması (çift metalik savurma).
func _synth_knife_spin() -> AudioStreamWAV:
	var dur := 0.32
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 414
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (w - lp)
		var pulse := pow(absf(sin(TAU * 3.2 * t)), 1.6)
		var ping := sin(TAU * lerpf(2100.0, 2900.0, t / dur) * t) * 0.18 * pulse
		var env := sin(clampf(t / dur, 0.0, 1.0) * PI)
		buf[i] = clampf(((w - lp) * 0.65 * pulse + ping) * env * 0.78, -0.9, 0.9)
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
	buf.resize(n - fade) # dikişsiz döngü: bindirilen kuyruğu at
	return _make_wav(buf, true)



func _synth_silence() -> AudioStreamWAV:
	return _make_wav(_zbuf(0.25), true)


# =====================================================================
# v0.6 — Sentez yardımcıları
# =====================================================================

func _zbuf(sec: float, rate := RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(maxi(1, int(float(rate) * sec)))
	b.fill(0.0)
	return b


## Tepe değerine normalize edip WAV yapar (asla kırpılmaz).
func _finish(buf: PackedFloat32Array, peak := 0.85, loop := false, rate := RATE) -> AudioStreamWAV:
	var m := 0.0
	for i in buf.size():
		var a := absf(buf[i])
		if a > m:
			m = a
	return _make_wav(buf, loop, rate, peak / m if m > 0.00001 else 1.0)


## Yumuşak doyum (tanh): ani tepeleri yuvarlar, müziği / ambiyansı "yapıştırır".
func _glue(buf: PackedFloat32Array, drive := 1.5) -> void:
	var m := 0.0
	for i in buf.size():
		m = maxf(m, absf(buf[i]))
	if m < 0.00001:
		return
	var k := drive / m
	for i in buf.size():
		buf[i] = tanh(buf[i] * k)


## Dikişsiz döngü: n örnekten sonraki fazlalık kuyruğu başa çapraz geçişle bindirir, sonra n'e kırpar.
func _loop_close(buf: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var fade := buf.size() - n
	for i in fade:
		var k := float(i) / float(fade)
		buf[i] = lerpf(buf[n + i], buf[i], k)
	buf.resize(n)
	return buf


## Tabloyu buf içine start örneğinden itibaren ekler; wrap=true ise taşan kuyruk başa sarılır (dikişsiz döngü).
func _mix(buf: PackedFloat32Array, table: PackedFloat32Array, start: int, gain: float, wrap := false) -> void:
	var n := buf.size()
	var j := posmod(start, n) if wrap else start
	for k in table.size():
		if j >= n:
			if not wrap:
				return
			j -= n
		if j >= 0:
			buf[j] += table[k] * gain
		j += 1


## Tabloyu perde oranıyla (ratio) yeniden örnekleyerek ekler; en fazla max_len örnek çalar, sonunda kısa sönüm.
func _mix_pitched(buf: PackedFloat32Array, table: PackedFloat32Array, start: int, gain: float, ratio: float, max_len: int, wrap := true) -> void:
	var n := buf.size()
	var count := mini(int(float(table.size() - 2) / ratio), max_len)
	if count <= 0:
		return
	var rel := mini(260, count)
	var rel_start := count - rel
	var j := posmod(start, n) if wrap else start
	var pos := 0.0
	for k in count:
		if j >= n:
			if not wrap:
				return
			j -= n
		var p := int(pos)
		var a := table[p]
		var v := a + (table[p + 1] - a) * (pos - float(p))
		if k > rel_start:
			v *= float(count - k) / float(rel)
		if j >= 0:
			buf[j] += v * gain
		j += 1
		pos += ratio


## Tek kutuplu alçak geçiren süzgeç (yerinde). wrap=true döngüler için durumu kuyruktan ısıtır.
func _lowpass(buf: PackedFloat32Array, a: float, wrap := false) -> void:
	var n := buf.size()
	var s := 0.0
	if wrap:
		for i in range(maxi(0, n - 2048), n):
			s += a * (buf[i] - s)
	for i in n:
		s += a * (buf[i] - s)
		buf[i] = s


## Geri beslemeli, sönümlü yankı (yerinde). wrap=true döngülerde başa sarılır.
func _echo(buf: PackedFloat32Array, delay: float, fb: float, wet: float, damp := 0.4, wrap := false) -> void:
	var n := buf.size()
	var d := maxi(1, int(delay * float(RATE)))
	var line := PackedFloat32Array()
	line.resize(n)
	line.fill(0.0)
	var lp := 0.0
	for i in n:
		var j := i - d
		var src := 0.0
		if j >= 0:
			src = buf[j] + fb * line[j]
		elif wrap:
			src = buf[j + n]
		lp += damp * (src - lp)
		line[i] = lp
	for i in n:
		buf[i] += line[i] * wet


## Karplus-Strong tel sentezi (bağlama / saz / pizzicato). [tablo, gerçek_frekans] döndürür;
## tam perde için _mix_pitched ile (hedef / gerçek) oranında çalınır.
func _ks(freq: float, dur: float, t60 := 1.2, bright := 0.6, pick := 0.18, sd := 1) -> Array:
	var L := maxi(4, int(float(RATE) / freq - 0.5))
	var actual := float(RATE) / (float(L) + 0.5)
	var decay := pow(0.001, 1.0 / maxf(actual * t60, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var ex := PackedFloat32Array()
	ex.resize(L)
	var lp := 0.0
	for i in L:
		lp += bright * (rng.randf_range(-1.0, 1.0) - lp)
		ex[i] = lp
	# Mızrap (tezene) konumu: tarak süzgeç → metalik, tınılı atak.
	var pd := maxi(1, int(float(L) * pick))
	var line := PackedFloat32Array()
	line.resize(L)
	var mean := 0.0
	for i in L:
		var v := ex[i] - (ex[i - pd] * 0.9 if i >= pd else 0.0)
		line[i] = v
		mean += v
	mean /= float(L)
	for i in L:
		line[i] -= mean
	var n := int(float(RATE) * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var idx := 0
	var prev := 0.0
	for i in n:
		var cur := line[idx]
		out[i] = cur
		line[idx] = decay * 0.5 * (cur + prev)
		prev = cur
		idx += 1
		if idx >= L:
			idx = 0
	return [out, actual]


## Tek periyotluk dalga tablosu (harmonik genliklerinden), tepe 1'e normalize.
func _wavetable(amps: PackedFloat32Array, size := 1024) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(size)
	t.fill(0.0)
	for h in amps.size():
		var a := amps[h]
		if a == 0.0:
			continue
		for i in size:
			t[i] += sin(TAU * float((h + 1) * i) / float(size)) * a
	var m := 0.0
	for i in size:
		m = maxf(m, absf(t[i]))
	if m > 0.0:
		for i in size:
			t[i] /= m
	return t


## Zurna tınısı: genizden, parlak çift kamışlı (1.4 kHz ve 2.9 kHz civarında formant).
func _zurna_table() -> PackedFloat32Array:
	var amps := PackedFloat32Array()
	for h in range(1, 13):
		var fh := float(h) * 560.0
		amps.append(pow(float(h), -0.75) * (0.35 + 1.4 * exp(-pow((fh - 1450.0) / 650.0, 2.0)) + 0.5 * exp(-pow((fh - 2900.0) / 500.0, 2.0))))
	return _wavetable(amps)


func _darbuka_dum() -> PackedFloat32Array:
	var b := _zbuf(0.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ph := 0.0
	var lp := 0.0
	for i in b.size():
		var t := float(i) / float(RATE)
		ph += (64.0 + 80.0 * exp(-t * 26.0)) / float(RATE)
		lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
		b[i] = sin(TAU * ph) * exp(-t * 8.5) + sin(TAU * ph * 2.32) * exp(-t * 16.0) * 0.18 + lp * exp(-t * 45.0) * 0.35
	return b


func _darbuka_tek(p: float) -> PackedFloat32Array:
	var b := _zbuf(0.16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in b.size():
		var t := float(i) / float(RATE)
		var ring := sin(TAU * 690.0 * p * t) * exp(-t * 32.0) + sin(TAU * 1130.0 * p * t) * exp(-t * 40.0) * 0.6 + sin(TAU * 1720.0 * p * t) * exp(-t * 52.0) * 0.35
		b[i] = ring * 0.7 + rng.randf_range(-1.0, 1.0) * exp(-t * 110.0) * 0.6
	return b


## Parmak zili (çarpare): çırpınan metalik kısmi tonlar.
func _zil() -> PackedFloat32Array:
	var b := _zbuf(0.7)
	for i in b.size():
		var t := float(i) / float(RATE)
		b[i] = (sin(TAU * 3150.0 * t) + sin(TAU * 3163.0 * t) * 0.8 + sin(TAU * 4470.0 * t) * 0.6 + sin(TAU * 6020.0 * t) * 0.4 + sin(TAU * 7890.0 * t) * 0.25) * exp(-t * 5.5) * minf(t / 0.002, 1.0) * 0.3
	return b


func _kf(keys: PackedVector2Array, t: float) -> float:
	var c := keys.size()
	if c == 0:
		return 0.0
	if t <= keys[0].x:
		return keys[0].y
	for k in range(1, c):
		var b := keys[k]
		if t <= b.x:
			var a := keys[k - 1]
			if b.x - a.x <= 0.000001:
				return b.y
			return lerpf(a.y, b.y, (t - a.x) / (b.x - a.x))
	return keys[c - 1].y


## Formant ses sentezi: testere dişi gırtlak kaynağı + nefes → iki rezonans süzgeci (F1, F2) + "s/t" gürültüsü.
## Anahtarlar (zaman sn, değer) çiftleridir: f0 Hz, f1/f2 Hz, ak sesli genlik, aspk nefes, frk sürtünme gürültüsü.
func _voice(dur: float, f0k: PackedVector2Array, f1k: PackedVector2Array, f2k: PackedVector2Array, ak: PackedVector2Array, aspk: PackedVector2Array, frk: PackedVector2Array, sd := 1, vib := 0.0) -> PackedFloat32Array:
	var n := int(dur * float(RATE))
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var inv := 1.0 / float(RATE)
	var ph := 0.0
	var gl := 0.0
	var l1 := 0.0
	var b1 := 0.0
	var l2 := 0.0
	var b2 := 0.0
	var nlp := 0.0
	var f0 := 100.0
	var c1 := 0.1
	var c2 := 0.3
	var amp := 0.0
	var asp := 0.0
	var fr := 0.0
	var vph := rng.randf() * TAU
	for i in n:
		if (i & 31) == 0:
			var t := float(i) * inv
			f0 = _kf(f0k, t) * (1.0 + vib * sin(TAU * 5.3 * t + vph))
			c1 = 2.0 * sin(PI * clampf(_kf(f1k, t), 80.0, 3000.0) * inv)
			c2 = 2.0 * sin(PI * clampf(_kf(f2k, t), 200.0, 3400.0) * inv)
			amp = _kf(ak, t)
			asp = _kf(aspk, t)
			fr = _kf(frk, t)
		ph += f0 * inv
		if ph >= 1.0:
			ph -= 1.0
		gl += 0.3 * ((1.0 - 2.0 * ph) - gl)
		var w := rng.randf_range(-1.0, 1.0)
		var x := gl * amp + w * (asp + 0.05 * amp)
		l1 += c1 * b1
		var h1 := x - l1 - 0.2 * b1
		b1 += c1 * h1
		l2 += c2 * b2
		var h2 := x - l2 - 0.12 * b2
		b2 += c2 * h2
		nlp += 0.45 * (w - nlp)
		out[i] = b1 * 0.2 + b2 * 0.14 + (w - nlp) * fr * 0.8
	return out


const _VOWELS := {
	"a": Vector2(730.0, 1090.0), "e": Vector2(530.0, 1840.0), "i": Vector2(300.0, 2250.0),
	"o": Vector2(570.0, 840.0), "u": Vector2(330.0, 900.0),
}


## Heceli konuşma taklidi. Her hece: [başlangıç, süre, ünlü, f0_baş_çarpanı, f0_son_çarpanı, ön_ünsüz, son_ünsüz].
func _speech(sylls: Array, f0_base: float, fscale: float, tail: float, sd: int, vib := 0.0) -> PackedFloat32Array:
	var f0k := PackedVector2Array()
	var f1k := PackedVector2Array()
	var f2k := PackedVector2Array()
	var ak := PackedVector2Array()
	var aspk := PackedVector2Array()
	var frk := PackedVector2Array()
	var end_t := 0.0
	for s in sylls:
		var t0: float = s[0]
		var d: float = s[1]
		var v: Vector2 = _VOWELS.get(s[2], Vector2(600.0, 1400.0)) * fscale
		var m0: float = s[3]
		var m1: float = s[4]
		var pre: String = s[5]
		var post: String = s[6]
		f0k.append(Vector2(t0, f0_base * m0))
		f0k.append(Vector2(t0 + d, f0_base * m1))
		f1k.append(Vector2(t0 + 0.03, v.x))
		f1k.append(Vector2(t0 + d - 0.02, v.x))
		f2k.append(Vector2(t0 + 0.03, v.y))
		f2k.append(Vector2(t0 + d - 0.02, v.y))
		var att := 0.035 if pre in ["m", "l", "r", "g", "d", "b", "c", "z"] else 0.014
		ak.append_array(PackedVector2Array([Vector2(t0, 0.0), Vector2(t0 + att, 1.0), Vector2(t0 + d * 0.75, 0.9), Vector2(t0 + d, 0.0)]))
		match pre:
			"s", "z", "c":
				frk.append_array(PackedVector2Array([Vector2(t0 - 0.09, 0.0), Vector2(t0 - 0.06, 0.8 if pre == "s" else 0.4), Vector2(t0 + 0.005, 0.0)]))
			"t", "k":
				frk.append_array(PackedVector2Array([Vector2(t0 - 0.022, 0.0), Vector2(t0 - 0.014, 1.0), Vector2(t0 + 0.008, 0.0)]))
			"h":
				aspk.append_array(PackedVector2Array([Vector2(t0 - 0.06, 0.0), Vector2(t0 - 0.015, 0.85), Vector2(t0 + 0.04, 0.3), Vector2(t0 + d, 0.12), Vector2(t0 + d + 0.02, 0.0)]))
		if post == "s":
			frk.append_array(PackedVector2Array([Vector2(t0 + d - 0.01, 0.0), Vector2(t0 + d + 0.03, 0.8), Vector2(t0 + d + 0.14, 0.0)]))
		end_t = maxf(end_t, t0 + d + (0.16 if post != "" else 0.02))
	f0k.sort()
	f1k.sort()
	f2k.sort()
	ak.sort()
	aspk.sort()
	frk.sort()
	return _voice(end_t + tail, f0k, f1k, f2k, ak, aspk, frk, sd, vib)


# =====================================================================
# v0.6 — Oyun efektleri
# =====================================================================

## Su fısfısı: iki pompa vuruşu (tetik tıkı + basınçlı ince sis tıslaması).
func _synth_spray() -> AudioStreamWAV:
	var buf := _zbuf(0.66)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	var lpa := 0.0
	var lpb := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lpa += 0.3 * (w - lpa)
		lpb += 0.75 * ((w - lpa) - lpb) # ~1.2 kHz üstü tıslama, en tiz uçları yuvarlanmış
		var v := 0.0
		for k in 2:
			var dt := t - 0.3 * float(k)
			if dt < 0.0:
				continue
			v += sin(TAU * 1500.0 * dt) * exp(-dt * 160.0) * 0.35 + sin(TAU * 170.0 * dt) * exp(-dt * 55.0) * 0.3
			var hd := dt - 0.012
			if hd > 0.0:
				v += lpb * minf(hd / 0.012, 1.0) * exp(-hd * 8.5) * (1.0 + 0.25 * sin(TAU * 31.0 * hd)) * 1.1
		buf[i] = v
	return _finish(buf, 0.65)


## Kombo: parlak yükselen arpej (Re majör) + ışıltı. Yüksek kombolarda pitch ile çalınabilir.
func _synth_combo() -> AudioStreamWAV:
	var buf := _zbuf(0.72)
	var notes := PackedFloat32Array([587.33, 739.99, 880.0, 1174.66, 1479.98])
	for i in buf.size():
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in 5:
			var dt := t - float(k) * 0.048
			if dt >= 0.0:
				var f := notes[k]
				v += (sin(TAU * f * dt) + 0.3 * sin(TAU * f * 2.0 * dt) + 0.12 * sin(TAU * f * 3.0 * dt)) * exp(-dt * (9.0 - float(k))) * (0.7 + 0.08 * float(k))
		var st := t - 0.24
		if st >= 0.0:
			v += (sin(TAU * 2349.3 * st) + 0.7 * sin(TAU * 2959.9 * st) + 0.5 * sin(TAU * 3520.0 * st)) * exp(-st * 7.0) * (0.55 + 0.45 * sin(TAU * 26.0 * st)) * 0.28
		buf[i] = v
	return _finish(buf, 0.65)


## Kapkaç: sinsi pizzicato (parmak ucunda yürüyüş) + kaçış vınlaması.
func _synth_steal() -> AudioStreamWAV:
	var buf := _zbuf(0.64)
	var seq := [[0.0, 164.81, 0.8], [0.1, 196.0, 0.7], [0.2, 233.08, 0.75], [0.34, 110.0, 0.95]]
	for s in seq:
		var f: float = s[1]
		var r: Array = _ks(f, 0.3, 0.22, 0.45, 0.12, int(f))
		_mix(buf, r[0], int(float(s[0]) * RATE), float(s[2]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4545
	var lp := 0.0
	var s0 := int(0.4 * RATE)
	for i in range(s0, buf.size()):
		var dt := float(i - s0) / float(RATE)
		lp += lerpf(0.4, 0.08, minf(dt / 0.2, 1.0)) * (rng.randf_range(-1.0, 1.0) - lp)
		buf[i] += lp * sin(minf(dt / 0.23, 1.0) * PI) * 0.4
	return _finish(buf, 0.9)


## Yakalama: hakem düdüğü + tok gövde darbesi.
func _synth_catch() -> AudioStreamWAV:
	var buf := _zbuf(0.78)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var ph := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var v := 0.0
		if t < 0.26:
			ph += (2950.0 + 160.0 * sin(TAU * 34.0 * t)) / float(RATE)
			var env := minf(t / 0.01, 1.0) * minf((0.26 - t) / 0.03, 1.0)
			v += (sin(TAU * ph) * 0.8 + sin(TAU * ph * 2.0) * 0.1) * env * (0.85 + 0.15 * sin(TAU * 34.0 * t)) * 0.55
		lp += 0.2 * (rng.randf_range(-1.0, 1.0) - lp)
		var dt := t - 0.27
		if dt >= 0.0:
			v += sin(TAU * (52.0 * dt + 3.2 * (1.0 - exp(-dt * 28.0)))) * exp(-dt * 10.0) * 0.95
			v += lp * exp(-dt * 32.0) * 0.6 + sin(TAU * 240.0 * dt) * exp(-dt * 40.0) * 0.25
		buf[i] = v
	return _finish(buf, 0.72)


## Görev tamam: Hicaz dörtlüsüyle zurna fanfarı (La-Si♭-Do♯-Re) + darbuka "düm-tek-tek-DÜM" + zil.
func _synth_quest_done() -> AudioStreamWAV:
	var buf := _zbuf(1.4)
	var n := buf.size()
	var wt := _zurna_table()
	var notes := [[0.0, 0.1, 440.0, 0.8], [0.11, 0.1, 466.16, 0.8], [0.22, 0.1, 554.37, 0.85], [0.33, 0.7, 587.33, 1.0], [0.33, 0.7, 440.0, 0.4]]
	for nd in notes:
		var t0: float = nd[0]
		var d: float = nd[1]
		var f: float = nd[2]
		var g: float = nd[3]
		var s0 := int(t0 * RATE)
		var cnt := int((d + 0.05) * RATE)
		var ph := 0.0
		for k in cnt:
			var j := s0 + k
			if j >= n:
				break
			var lt := float(k) / float(RATE)
			var vib := 1.0 + 0.009 * sin(TAU * 6.0 * lt) * clampf((lt - 0.15) / 0.2, 0.0, 1.0)
			ph += f * vib / float(RATE)
			ph -= floorf(ph)
			var env := minf(lt / 0.012, 1.0) * clampf((d + 0.05 - lt) / 0.05, 0.0, 1.0)
			buf[j] += wt[int(ph * 1024.0) & 1023] * env * g * 0.5
	var dum := _darbuka_dum()
	var tek := _darbuka_tek(1.0)
	_mix(buf, dum, 0, 0.7)
	_mix(buf, tek, int(0.165 * RATE), 0.35)
	_mix(buf, tek, int(0.25 * RATE), 0.3)
	_mix(buf, dum, int(0.33 * RATE), 0.9)
	_mix(buf, _zil(), int(0.33 * RATE), 0.35)
	return _finish(buf, 0.85)


## İtibar arttı: iki tonlu yükselen marimba + ışıltı.
func _synth_rep_up() -> AudioStreamWAV:
	var buf := _zbuf(0.6)
	for i in buf.size():
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in 2:
			var dt := t - 0.09 * float(k)
			if dt >= 0.0:
				var f := 783.99 if k == 0 else 1174.66
				v += (sin(TAU * f * dt) + 0.35 * sin(TAU * f * 4.0 * dt) * exp(-dt * 40.0)) * exp(-dt * 7.0)
		var st := t - 0.13
		if st >= 0.0:
			v += (sin(TAU * 2349.3 * st) * 0.5 + sin(TAU * 3135.9 * st) * 0.35) * exp(-st * 10.0) * 0.4
		buf[i] = v
	return _finish(buf, 0.6)


## İtibar düştü: sarkan, kırık iki nota.
func _synth_rep_down() -> AudioStreamWAV:
	var buf := _zbuf(0.7)
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var f := 523.25
		var env := 0.0
		if t < 0.15:
			env = minf(t / 0.01, 1.0) * (1.0 - maxf(t - 0.12, 0.0) / 0.03)
		else:
			var dt := t - 0.15
			f = 392.0 * (1.0 - 0.07 * minf(dt / 0.4, 1.0))
			env = minf(dt / 0.01, 1.0) * exp(-dt * 4.0)
		ph += f / float(RATE)
		ph -= floorf(ph)
		buf[i] = (sin(TAU * ph) + sin(TAU * ph * 2.0) * 0.2 + sin(TAU * ph * 3.0) * 0.12) * env
	return _finish(buf, 0.42)


## Kedi miyavlaması: formant kayması (i → a → u) ile "miyaav".
func _synth_cat() -> AudioStreamWAV:
	var f0k := PackedVector2Array([Vector2(0.0, 470.0), Vector2(0.12, 720.0), Vector2(0.38, 690.0), Vector2(0.62, 480.0), Vector2(0.78, 400.0)])
	var f1k := PackedVector2Array([Vector2(0.0, 520.0), Vector2(0.16, 1150.0), Vector2(0.45, 1050.0), Vector2(0.72, 650.0)])
	var f2k := PackedVector2Array([Vector2(0.0, 2500.0), Vector2(0.16, 1950.0), Vector2(0.45, 1550.0), Vector2(0.72, 1000.0)])
	var ak := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.05, 0.85), Vector2(0.16, 1.0), Vector2(0.55, 0.8), Vector2(0.78, 0.0)])
	var aspk := PackedVector2Array([Vector2(0.0, 0.25), Vector2(0.1, 0.1), Vector2(0.78, 0.12), Vector2(0.8, 0.0)])
	return _finish(_voice(0.85, f0k, f1k, f2k, ak, aspk, PackedVector2Array(), 77, 0.012), 0.6)


## Güvercin kanat çırpışı: hızlanıp seyrelen kanat vuruşları.
func _synth_pigeon_flap() -> AudioStreamWAV:
	# Yumuşak, alçak "gu-gurr" + hafif kanat hışırtısı (gürültü yok, kısa).
	var buf := _zbuf(0.5)
	for c in [[0.02, 0.13, 330.0, 280.0, 1.0], [0.2, 0.18, 300.0, 240.0, 0.8]]:
		var s0 := int(float(c[0]) * RATE)
		var cnt := int(float(c[1]) * RATE)
		var ph := 0.0
		for k in cnt:
			var x := float(k) / float(cnt)
			ph += lerpf(float(c[2]), float(c[3]), x) / float(RATE)
			buf[s0 + k] += (sin(TAU * ph) + 0.3 * sin(TAU * ph * 2.0)) * sin(PI * x) * float(c[4])
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var lp := 0.0
	for i in int(0.3 * RATE):
		lp += 0.05 * (rng.randf_range(-1.0, 1.0) - lp)
		buf[int(0.05 * RATE) + i] += lp * sin(float(i) / (0.3 * RATE) * PI) * 0.25
	_lowpass(buf, 0.25)
	return _finish(buf, 0.35)


## Çay: ince belli bardağın tabağa konması + kaşık şıngırtısı.
func _synth_tea() -> AudioStreamWAV:
	# Bardağın tabağa konması + iki hafif kaşık tınısı (kısa, yumuşak).
	var buf := _zbuf(0.5)
	for i in int(0.15 * RATE):
		var t := float(i) / float(RATE)
		buf[i] += (sin(TAU * 1180.0 * t) * exp(-t * 45.0) * 0.4 + sin(TAU * 190.0 * t) * exp(-t * 50.0) * 0.4) * minf(t / 0.002, 1.0)
	for h in [[0.15, 0.6], [0.27, 0.4]]:
		var s0 := int(float(h[0]) * RATE)
		for k in int(0.12 * RATE):
			var t := float(k) / float(RATE)
			buf[s0 + k] += sin(TAU * 1900.0 * t) * minf(t / 0.002, 1.0) * exp(-t * 40.0) * float(h[1]) * 0.3
	return _finish(buf, 0.5)


## Gök gürültüsü: keskin çatırtı + uzun, dalgalı uğultu.
func _synth_thunder() -> AudioStreamWAV:
	var buf := _zbuf(4.2)
	var n := buf.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1313
	var hp := 0.0
	var br := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		var v := 0.0
		if t < 0.5:
			hp += 0.45 * (w - hp)
			var crack := (w - hp) * exp(-t * 11.0)
			if rng.randf() < 0.02:
				crack += rng.randf_range(-1.0, 1.0) * exp(-t * 6.0)
			v += crack * 0.55
		br = br * 0.997 + w * 0.05
		lp1 += 0.05 * (br - lp1)
		lp2 += 0.012 * (lp1 - lp2)
		var swell := 0.6 + 0.25 * sin(TAU * 0.9 * t + p1) + 0.15 * sin(TAU * 1.7 * t + p2) + 0.12 * sin(TAU * 2.9 * t + p3)
		var env := minf(t / 0.12, 1.0) * exp(-maxf(t - 0.3, 0.0) * 0.85)
		v += (lp1 - lp2 * 0.5) * swell * env * 2.2
		buf[i] = v
	var fade := int(0.3 * RATE)
	for i in fade:
		buf[n - fade + i] *= 1.0 - float(i) / float(fade)
	return _finish(buf, 0.9)


## Ezilen çürük domates "vıcık" sesi.
func _synth_squelch() -> AudioStreamWAV:
	var buf := _zbuf(0.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var lo := 0.0
	var bd := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var c := 2.0 * sin(PI * (230.0 + 1000.0 * exp(-t * 6.0)) / float(RATE))
		lo += c * bd
		var hi := rng.randf_range(-1.0, 1.0) - lo - 0.3 * bd
		bd += c * hi
		var v := bd * minf(t / 0.012, 1.0) * exp(-t * 6.5) * (0.65 + 0.35 * sin(TAU * 27.0 * t)) * 0.5
		for k in 3:
			var dt := t - (0.04 + 0.11 * float(k))
			if dt >= 0.0 and dt < 0.06:
				v += sin(TAU * (380.0 * dt + 9000.0 * dt * dt)) * exp(-dt * 60.0) * 0.45
		buf[i] = v
	return _finish(buf, 0.8)


## Yazar kasa "ka-çing": kol / çekmece mekanizması + zil + bozuk para şıngırtısı.
func _synth_cash_register() -> AudioStreamWAV:
	var buf := _zbuf(1.2)
	var n := buf.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1453
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var w := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (w - lp)
		var v := 0.0
		for k in 2:
			var dt := t - 0.045 * float(k)
			if dt >= 0.0 and dt < 0.08:
				v += (w - lp) * exp(-dt * 120.0) * 0.7 + sin(TAU * 1650.0 * dt) * exp(-dt * 80.0) * 0.3
		var dd := t - 0.075
		if dd >= 0.0:
			v += sin(TAU * 92.0 * dd) * exp(-dd * 22.0) * 0.75 + lp * exp(-dd * 28.0) * 0.4
		var bt := t - 0.13
		if bt >= 0.0:
			v += (sin(TAU * 2093.0 * bt) * exp(-bt * 3.0) + sin(TAU * 2099.0 * bt) * exp(-bt * 3.2) * 0.75 \
				+ sin(TAU * 3136.0 * bt) * exp(-bt * 4.5) * 0.55 + sin(TAU * 4186.0 * bt) * exp(-bt * 6.5) * 0.35 \
				+ sin(TAU * 5274.0 * bt) * exp(-bt * 9.0) * 0.22) * minf(bt / 0.002, 1.0) * 0.55
		buf[i] = v
	for k in 6:
		var s0 := int(rng.randf_range(0.26, 0.62) * RATE)
		var f := rng.randf_range(3000.0, 5200.0)
		for m in int(0.1 * RATE):
			var j := s0 + m
			if j >= n:
				break
			var t := float(m) / float(RATE)
			buf[j] += sin(TAU * f * t) * exp(-t * 45.0) * 0.12
	return _finish(buf, 0.85)


## Çocuk kıkırdaması: "hi-hi-hi-hiii".
func _synth_kid_laugh() -> AudioStreamWAV:
	var sy := [
		[0.07, 0.09, "i", 1.18, 1.05, "h", ""],
		[0.21, 0.09, "i", 1.14, 1.0, "h", ""],
		[0.35, 0.09, "e", 1.1, 0.97, "h", ""],
		[0.49, 0.09, "e", 1.04, 0.93, "h", ""],
		[0.65, 0.24, "i", 1.12, 0.78, "h", ""],
	]
	return _finish(_speech(sy, 330.0, 1.35, 0.12, 606, 0.02), 0.65)


## Büyük vınlama (hızlı geçiş / fırlatma).
func _synth_whoosh_big() -> AudioStreamWAV:
	var dur := 0.85
	var buf := _zbuf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8086
	var lo := 0.0
	var bd := 0.0
	var lp := 0.0
	var c := 0.1
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var x := t / dur
		if (i & 15) == 0:
			c = 2.0 * sin(PI * (220.0 + 1900.0 * pow(sin(PI * minf(x * 1.15, 1.0)), 2.0)) / float(RATE))
		var w := rng.randf_range(-1.0, 1.0)
		lo += c * bd
		var hi := w - lo - 0.55 * bd
		bd += c * hi
		lp += 0.03 * (w - lp)
		ph += (70.0 - 30.0 * x) / float(RATE)
		var env := pow(sin(PI * x), 1.6)
		buf[i] = (bd * 0.6 + lp * 1.2 + sin(TAU * ph) * 0.15) * env
	return _finish(buf, 0.75)


# =====================================================================
# v0.6 — Uzun döngüler (arka plan iş parçacığında üretilir)
# =====================================================================

## Menü müziği: Hicaz makamında (Re-Mi♭-Fa♯-Sol-La-Si♭-Do-Re) çift telli bağlama melodisi (uzun notalarda
## tremolo, ara sıra çarpma süsü), dem telleri, bas, maksum ritimli darbuka ve zil — 12 ölçülük dikişsiz döngü.
func _synth_menu_music() -> AudioStreamWAV:
	var bpm := 116.0
	var s16 := 60.0 / bpm / 4.0
	var bars := 12
	var spb := float(RATE) * s16 # on altılık başına örnek
	var n := int(spb * 16.0 * float(bars))
	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)
	var hz := {-1: 261.63, 0: 293.66, 1: 311.13, 2: 369.99, 3: 392.0, 4: 440.0, 5: 466.16, 6: 523.25, 7: 587.33, 8: 622.25, 9: 739.99}
	# [derece, sekizlik süre] — A (1-4), A' (5-8), B (9-12)
	var melody := [
		[[4, 2], [5, 1], [4, 1], [3, 1], [2, 1], [3, 2]],
		[[2, 1], [1, 1], [2, 1], [3, 1], [2, 2], [1, 1], [0, 1]],
		[[0, 1], [1, 1], [2, 1], [3, 1], [4, 2], [5, 1], [4, 1]],
		[[3, 1], [2, 1], [1, 1], [2, 1], [0, 4]],
		[[7, 2], [6, 1], [5, 1], [4, 1], [5, 1], [4, 2]],
		[[3, 1], [4, 1], [5, 1], [4, 1], [3, 1], [2, 1], [3, 2]],
		[[4, 1], [3, 1], [2, 1], [1, 1], [2, 2], [3, 1], [2, 1]],
		[[1, 2], [2, 1], [1, 1], [0, 4]],
		[[7, 1], [7, 1], [8, 1], [7, 1], [6, 1], [7, 1], [5, 2]],
		[[6, 1], [6, 1], [7, 1], [6, 1], [5, 1], [6, 1], [4, 2]],
		[[5, 1], [4, 1], [3, 1], [4, 1], [5, 1], [6, 1], [7, 2]],
		[[5, 1], [4, 1], [3, 1], [2, 1], [1, 1], [2, 1], [0, 2]],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7771
	# 1) Melodi olayları: [16'lık konum, derece, şiddet]
	var ev: Array = []
	var pos := 0.0
	for bar in melody:
		for nt in bar:
			var deg: int = nt[0]
			var l16: int = int(nt[1]) * 2
			if l16 >= 6:
				for k in l16: # tezene tremolosu
					ev.append([pos + float(k), deg, 0.8 if k % 2 == 0 else 0.5])
			elif l16 == 4 and rng.randf() < 0.45 and hz.has(deg + 1):
				ev.append([pos, deg + 1, 0.55]) # çarpma süsü
				ev.append([pos + 0.35, deg, 0.95])
			else:
				ev.append([pos, deg, 1.0 if fmod(pos, 4.0) == 0.0 else 0.82])
			pos += float(l16)
	var total16 := pos
	var tabs := {}
	for e in ev:
		var deg: int = e[1]
		if not tabs.has(deg):
			tabs[deg] = _ks(hz[deg], 1.1, 1.5, 0.72, 0.13, 300 + deg)
	for idx in ev.size():
		var e: Array = ev[idx]
		var st: float = e[0]
		var nxt: float = ev[(idx + 1) % ev.size()][0]
		var l := nxt - st
		if l <= 0.0:
			l += total16
		var deg: int = e[1]
		var tb: Array = tabs[deg]
		var f: float = hz[deg]
		var act: float = tb[1]
		var g: float = e[2]
		var s0 := int(st * spb + rng.randf_range(-40.0, 40.0)) # insansı zamanlama
		var ml := int(l * spb) + 180
		_mix_pitched(buf, tb[0], s0, g, f / act, ml)
		_mix_pitched(buf, tb[0], s0 + 25, g * 0.55, f * 1.0045 / act, ml) # çift tel (hafif koro)
	_echo(buf, s16 * 3.0, 0.3, 0.28, 0.35, true)
	# 2) Dem telleri (Re3 vuruşta, La3 ara vuruşta)
	var d_lo: Array = _ks(146.83, 0.6, 0.9, 0.5, 0.2, 51)
	var d_hi: Array = _ks(220.0, 0.6, 0.9, 0.5, 0.2, 52)
	for k in bars * 8:
		var on_beat := k % 2 == 0
		var tb: Array = d_lo if on_beat else d_hi
		var f := 146.83 if on_beat else 220.0
		_mix_pitched(buf, tb[0], int(float(k) * 2.0 * spb + rng.randf_range(-30.0, 30.0)), 0.3 if on_beat else 0.18, f / float(tb[1]), int(2.0 * spb) + 150)
	# 3) Bas (ölçü başı ve ortası, darbuka düm'leriyle)
	var roots := [73.42, 73.42, 73.42, 73.42, 73.42, 98.0, 73.42, 73.42, 73.42, 65.41, 98.0, 73.42]
	var btabs := {}
	for b in bars:
		for half in 2:
			var f: float = roots[b]
			if half == 1 and b % 4 == 3:
				f = 110.0
			if not btabs.has(f):
				btabs[f] = _ks(f, 1.0, 1.4, 0.3, 0.3, int(f))
			var tb: Array = btabs[f]
			_mix_pitched(buf, tb[0], int((float(b) * 16.0 + float(half) * 8.0) * spb), 0.55, f / float(tb[1]), int(8.0 * spb) + 200)
	# 4) Darbuka (maksum: DÜM-tek-.-tek-DÜM-.-tek-.) + zil
	var dum := _darbuka_dum()
	var tek := _darbuka_tek(1.0)
	var ka := _darbuka_tek(0.86)
	var zil := _zil()
	for b in bars:
		var base := float(b) * 16.0
		var hits: Array = [[0, dum, 0.95], [2, tek, 0.5], [6, tek, 0.45], [8, dum, 0.85], [12, tek, 0.5], [4, ka, 0.16], [10, ka, 0.2]]
		if b % 4 == 3:
			hits.append_array([[13, ka, 0.35], [14, tek, 0.45], [15, ka, 0.42]])
		else:
			hits.append([14, ka, 0.22])
		if b >= 8:
			hits.append_array([[4, zil, 0.16], [12, zil, 0.16]])
		elif b % 4 == 0:
			hits.append([0, zil, 0.2])
		for h in hits:
			_mix(buf, h[1], int((base + float(h[0])) * spb + rng.randf_range(-35.0, 35.0)), float(h[2]) * rng.randf_range(0.88, 1.05), true)
	_glue(buf, 1.3)
	return _finish(buf, 0.85, true)


## Pazar kalabalığı döngüsü: yavaş dalgalanan uğultu yatağı + rastgele konuşma heceleri + uzak tahta
## kasa tıkırtıları (14 sn, dikişsiz).
func _synth_amb_bed() -> AudioStreamWAV:
	var sec := 14.0
	var n := int(sec * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + int(0.5 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	for i in buf.size():
		var u := TAU * float(i) / float(RATE) / sec
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += 0.1 * (w - lp1)
		lp2 += 0.022 * (lp1 - lp2)
		lp3 += 0.004 * (lp2 - lp3)
		var swell := 0.75 + 0.15 * sin(u + 0.3) + 0.1 * sin(3.0 * u + 1.7) + 0.06 * sin(7.0 * u + 0.5)
		buf[i] = (lp1 - lp2) * swell * 1.2 + (lp2 - lp3) * 0.8
	buf = _loop_close(buf, n)
	# Konuşma heceleri: farklı kişilerden (kadın / erkek) kısa "kelimeler"
	var vowels := ["a", "e", "i", "o", "u", "a", "e"]
	var cons := ["", "t", "k", "s", "m", "l", "d", "b"]
	var words: Array = []
	for wi in 14:
		var female := rng.randf() < 0.45
		var f0 := rng.randf_range(185.0, 250.0) if female else rng.randf_range(95.0, 150.0)
		var fs := rng.randf_range(1.12, 1.25) if female else rng.randf_range(0.95, 1.05)
		var sy: Array = []
		var t := 0.1
		for s in rng.randi_range(2, 4):
			var d := rng.randf_range(0.09, 0.2)
			var m0 := rng.randf_range(0.9, 1.25)
			sy.append([t, d, vowels[rng.randi() % vowels.size()], m0, m0 * rng.randf_range(0.85, 1.1), cons[rng.randi() % cons.size()], ""])
			t += d + rng.randf_range(0.03, 0.08)
		if _gen_abort:
			break
		words.append(_speech(sy, f0, fs, 0.05, 1000 + wi, 0.01))
	if not words.is_empty():
		for k in int(sec * 5.0):
			_mix(buf, words[rng.randi() % words.size()], rng.randi() % n, rng.randf_range(0.025, 0.11), true)
	var knock := _zbuf(0.09)
	var kf := rng.randf_range(260.0, 420.0)
	for i in knock.size():
		var t := float(i) / float(RATE)
		knock[i] = sin(TAU * kf * t) * exp(-t * 55.0) + rng.randf_range(-1.0, 1.0) * exp(-t * 200.0) * 0.3
	for k in int(sec * 1.2):
		_mix(buf, knock, rng.randi() % n, rng.randf_range(0.03, 0.09), true)
	_lowpass(buf, 0.5, true)
	_glue(buf, 1.2)
	return _finish(buf, 0.7, true)


## Uzak satıcı bağırışı (formant sentezli "Taaze domateees!" vb.), uzaklık için süzülüp yankılandırılır.
func _synth_vendor_call(kind: int) -> AudioStreamWAV:
	var sy: Array
	var base := 160.0
	match kind:
		0: # "Taaaze domateees!"
			base = 165.0
			sy = [[0.1, 0.34, "a", 1.0, 1.25, "t", ""], [0.48, 0.18, "e", 1.25, 1.2, "z", ""], [0.72, 0.13, "o", 1.12, 1.15, "d", ""],
				[0.88, 0.15, "a", 1.25, 1.3, "m", ""], [1.08, 0.62, "e", 1.42, 1.0, "t", "s"]]
		1: # "Gel gel gel, ucuzaaa!"
			base = 185.0
			sy = [[0.1, 0.15, "e", 1.2, 1.15, "g", ""], [0.33, 0.15, "e", 1.2, 1.15, "g", ""], [0.56, 0.24, "e", 1.35, 1.25, "g", ""],
				[0.98, 0.12, "u", 1.1, 1.15, "", ""], [1.14, 0.13, "u", 1.2, 1.25, "c", ""], [1.31, 0.55, "a", 1.45, 1.05, "z", ""]]
		_: # "Kilosu beş liraaa!"
			base = 150.0
			sy = [[0.12, 0.11, "i", 1.2, 1.2, "k", ""], [0.27, 0.11, "o", 1.2, 1.25, "l", ""], [0.5, 0.13, "u", 1.3, 1.3, "s", ""],
				[0.75, 0.2, "e", 1.35, 1.3, "b", "s"], [1.16, 0.12, "i", 1.3, 1.35, "l", ""], [1.31, 0.7, "a", 1.5, 1.1, "r", ""]]
	var buf := _speech(sy, base, 1.0, 0.6, 900 + kind, 0.018)
	_lowpass(buf, 0.42)
	_echo(buf, 0.19, 0.35, 0.4, 0.3)
	return _finish(buf, 0.8)


## Serçe cıvıltıları (3 çeşit).
func _synth_bird(kind: int) -> AudioStreamWAV:
	var buf := _zbuf(0.9)
	var chirps: Array = [] # [t0, süre, f_baş, f_son, kazanç]
	match kind:
		0:
			chirps = [[0.02, 0.07, 2900.0, 2300.0, 1.0], [0.2, 0.07, 2800.0, 2200.0, 0.8]]
		1:
			for k in 4:
				chirps.append([0.02 + float(k) * 0.09, 0.05, 2200.0, 2900.0, 0.6 + 0.4 * sin(float(k) / 3.0 * PI)])
		_:
			chirps = [[0.02, 0.2, 2200.0, 2800.0, 0.8], [0.3, 0.14, 2800.0, 2300.0, 0.6]]
	for c in chirps:
		var s0 := int(float(c[0]) * RATE)
		var d: float = c[1]
		var cnt := int(d * RATE)
		var ph := 0.0
		for k in cnt:
			var x := float(k) / float(cnt)
			ph += lerpf(float(c[2]), float(c[3]), x) / float(RATE)
			buf[s0 + k] += sin(TAU * ph) * sin(PI * x) * float(c[4])
	_echo(buf, 0.09, 0.15, 0.15, 0.6)
	return _finish(buf, 0.5)


## Uzak araba kornası (iki tonlu "düt-düüt"), süzülmüş ve yankılı.
func _synth_far_horn() -> AudioStreamWAV:
	var buf := _zbuf(1.5)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var on := 0.0
		if t < 0.17:
			on = minf(t / 0.01, 1.0) * minf((0.17 - t) / 0.02, 1.0)
		elif t > 0.26 and t < 0.78:
			on = minf((t - 0.26) / 0.01, 1.0) * minf((0.78 - t) / 0.03, 1.0)
		ph1 += 415.0 / float(RATE)
		ph2 += 523.0 / float(RATE)
		ph1 -= floorf(ph1)
		ph2 -= floorf(ph2)
		var s := sin(TAU * ph1) + sin(TAU * ph1 * 3.0) / 3.0 + sin(TAU * ph1 * 5.0) / 5.0
		s += sin(TAU * ph2) + sin(TAU * ph2 * 3.0) / 3.0 + sin(TAU * ph2 * 5.0) / 5.0
		buf[i] = s * on
	_lowpass(buf, 0.2)
	_echo(buf, 0.24, 0.35, 0.45, 0.25)
	return _finish(buf, 0.7)


## Uzaktan geçen mobilet (doppler kaymalı iki zamanlı vızıltı).
func _synth_moped() -> AudioStreamWAV:
	var dur := 3.2
	var buf := _zbuf(dur)
	var rng := RandomNumberGenerator.new()
	rng.seed = 125
	var ph := 0.0
	var lp := 0.0
	var lp2 := 0.0
	for i in buf.size():
		var t := float(i) / float(RATE)
		var x := (t - 1.6) / 0.55
		var dop := 1.0 - 0.07 * x / sqrt(1.0 + x * x) # yaklaşırken tiz, uzaklaşırken pes
		ph += 88.0 * dop * (1.0 + 0.03 * sin(TAU * 1.3 * t)) / float(RATE)
		ph -= floorf(ph)
		var pulse := 1.0 if ph < 0.28 else -0.38
		lp += 0.18 * (pulse + rng.randf_range(-1.0, 1.0) * 0.35 - lp)
		lp2 += 0.5 * (lp - lp2)
		buf[i] = lp2 / (1.0 + x * x) * minf(t / 0.3, 1.0) * minf((dur - t) / 0.3, 1.0)
	return _finish(buf, 0.65)


## Yağmur döngüsü: geniş bantlı sağanak + tek tek damla tıkırtıları + tente (branda) üzerine düşen tok damlalar.
func _synth_rain_loop() -> AudioStreamWAV:
	var sec := 6.0
	var n := int(sec * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + int(0.3 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 333
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	for i in buf.size():
		var u := TAU * float(i) / float(RATE) / sec
		var w := rng.randf_range(-1.0, 1.0)
		lp1 += 0.6 * (w - lp1)
		lp2 += 0.09 * (w - lp2)
		lp3 += 0.012 * (lp2 - lp3)
		var fl := 0.85 + 0.1 * sin(2.0 * u) + 0.05 * sin(5.0 * u + 1.0)
		buf[i] = ((w - lp1) * 0.3 + (lp1 - lp2) * 0.5 + (lp2 - lp3) * 0.9) * fl
	buf = _loop_close(buf, n)
	var drops: Array = []
	for k in 8:
		var d := _zbuf(0.03)
		var f := rng.randf_range(1800.0, 4500.0)
		for m in d.size():
			var t := float(m) / float(RATE)
			d[m] = sin(TAU * f * t * (1.0 + t * 12.0)) * exp(-t * 160.0) + rng.randf_range(-1.0, 1.0) * exp(-t * 600.0) * 0.3
		drops.append(d)
	var tarps: Array = []
	for k in 4:
		var d := _zbuf(0.07)
		var f := rng.randf_range(160.0, 380.0)
		var lp := 0.0
		for m in d.size():
			var t := float(m) / float(RATE)
			lp += 0.3 * (rng.randf_range(-1.0, 1.0) - lp)
			d[m] = sin(TAU * f * t) * exp(-t * 45.0) + lp * exp(-t * 80.0) * 0.6
		tarps.append(d)
	for k in int(sec * 90.0):
		_mix(buf, drops[rng.randi() % drops.size()], rng.randi() % n, pow(rng.randf(), 2.0) * 0.35, true)
	for k in int(sec * 16.0):
		_mix(buf, tarps[rng.randi() % tarps.size()], rng.randi() % n, rng.randf_range(0.1, 0.35), true)
	return _finish(buf, 0.75, true)


## Rüzgar döngüsü: yavaşça kayan bant geçiren gürültü + hafif ıslık, esinti dalgaları (8 sn, dikişsiz).
func _synth_wind_loop() -> AudioStreamWAV:
	var sec := 8.0
	var n := int(sec * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + int(0.4 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2020
	var lo := 0.0
	var bd := 0.0
	var lo2 := 0.0
	var bd2 := 0.0
	var lp := 0.0
	var c1 := 0.1
	var c2 := 0.2
	var gust := 0.6
	for i in buf.size():
		if (i & 31) == 0:
			var u := TAU * float(i) / float(RATE) / sec
			var fc := 330.0 + 150.0 * sin(u) + 80.0 * sin(3.0 * u + 1.1)
			c1 = 2.0 * sin(PI * fc / float(RATE))
			c2 = 2.0 * sin(PI * fc * 2.6 / float(RATE))
			gust = 0.55 + 0.25 * sin(2.0 * u + 0.4) + 0.12 * sin(5.0 * u + 2.0) + 0.08 * sin(7.0 * u)
		var w := rng.randf_range(-1.0, 1.0)
		lo += c1 * bd
		var hi := w - lo - 0.7 * bd
		bd += c1 * hi
		lo2 += c2 * bd2
		var hi2 := w - lo2 - 0.09 * bd2
		bd2 += c2 * hi2
		lp += 0.02 * (w - lp)
		buf[i] = (bd * 0.5 + bd2 * 0.035 * gust + lp * 1.5) * gust
	buf = _loop_close(buf, n)
	return _finish(buf, 0.7, true)
