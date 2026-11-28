extends Node
## Detaylı PC Oyun Ayarları (Autoload: Settings):
## Ekran, 3 kademeli grafik + gelişmiş efektler, 5 ses kanalı, mikrofon/PTT,
## fare/kontrolcü + canlı tuş atama (InputMap + Gamepad), dil (TR/EN) ve erişilebilirlik.
## Tüm ayarlar user://settings.cfg dosyasına kaydedilir.

signal quality_changed(high: bool)
signal graphics_changed()
signal audio_changed()
signal controls_changed()
signal ui_prefs_changed()

const PATH := "user://settings.cfg"
const MODES := ["Pencere", "Tam ekran", "Kenarlıksız tam ekran"]
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const FPS_CAPS := [0, 60, 120, 144, 240]

const DEFAULT_KEYS := {
	"fwd": KEY_W,
	"back": KEY_S,
	"left": KEY_A,
	"right": KEY_D,
	"run": KEY_SHIFT,
	"jump": KEY_SPACE,
	"interact": KEY_E,
	"throw_crate": KEY_Q,
	"shout": KEY_B,
	"ptt": KEY_V,
	"mic_mute": KEY_M,
	"refuse_offer": KEY_R,
	"ring_bell": KEY_F,
	"call_tea": KEY_T,
	"price_down": KEY_Z,
	"price_up": KEY_X,
	"radio_next": KEY_N,
	"scoreboard": KEY_TAB,
	"tutorial_skip": KEY_H,
}

const KEYBIND_ORDER := [
	"fwd", "back", "left", "right", "run", "jump",
	"interact", "throw_crate", "shout", "ptt", "mic_mute",
	"refuse_offer", "ring_bell", "call_tea",
	"price_down", "price_up", "radio_next", "scoreboard", "tutorial_skip",
]

# --- Ekran & Grafik ---
var mode := 0 # 0 pencere, 1 tam ekran, 2 kenarlıksız
var resolution := 0 # RESOLUTIONS indeksi
var vsync := 1 # 0 kapalı, 1 açık, 2 adaptive
var fps_cap_idx := 0 # FPS_CAPS indeksi (0 = sınırsız)
var quality_level := 2 # 0 Düşük, 1 Orta, 2 Yüksek
var quality_high := true # eski kod uyumluluğu
var msaa := 1 # 0 kapalı, 1 2x, 2 4x
var shadows_level := 2 # 0 düşük, 1 orta, 2 yüksek
var render_scale := 1.0 # 0.75 .. 1.0
var ssao_enabled := true
var glow_enabled := true
var vol_fog_enabled := true
var fov := 78.0 # 65 .. 105
var show_fps := false
var reduce_motion := false

# --- Ses & Mikrofon ---
var volume := 0.85 # Master (eski ad uyumlu)
var sfx_vol := 0.90
var music_vol := 0.75
var ambience_vol := 0.80
var voice_vol := 1.00
var mic_device := "Default"
var voice_mode := 0 # 0 = Ses Aktivasyonu, 1 = Bas-Konuş (PTT)
var mic_gain := 1.0 # 0.5 .. 2.5
var mic_threshold_db := -42.0 # -55 .. -20
var muted_peers: Dictionary = {} # peer_id (int) -> bool (oturum içi)

# --- Kontroller & Tuşlar ---
var mouse_sens := 1.0 # 0.2 .. 3.0
var invert_y := false
var gamepad_sens := 1.2 # 0.5 .. 3.0
var gamepad_deadzone := 0.15 # 0.08 .. 0.35
var keybinds: Dictionary = {}

# --- Oynanış & Dil ---
var lang := "tr"
var crosshair_style := 0 # 0 Nokta, 1 Artı, 2 Halka
var crosshair_scale := 1.0 # 0.7 .. 1.6
var show_hints := true
var tutorial_done := false


func _ready() -> void:
	keybinds = DEFAULT_KEYS.duplicate()
	_load()
	L10n.set_lang(lang)
	_ensure_audio_buses()
	apply_audio()
	apply_display()
	apply_graphics()
	apply_keybinds()


func _load() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) != OK:
		return
	# Ses
	volume = clampf(float(c.get_value("audio", "volume", volume)), 0.0, 1.0)
	sfx_vol = clampf(float(c.get_value("audio", "sfx_vol", sfx_vol)), 0.0, 1.0)
	music_vol = clampf(float(c.get_value("audio", "music_vol", music_vol)), 0.0, 1.0)
	ambience_vol = clampf(float(c.get_value("audio", "ambience_vol", ambience_vol)), 0.0, 1.0)
	voice_vol = clampf(float(c.get_value("audio", "voice_vol", voice_vol)), 0.0, 1.0)
	mic_device = str(c.get_value("audio", "mic_device", mic_device))
	voice_mode = clampi(int(c.get_value("audio", "voice_mode", voice_mode)), 0, 1)
	mic_gain = clampf(float(c.get_value("audio", "mic_gain", mic_gain)), 0.5, 2.5)
	mic_threshold_db = clampf(float(c.get_value("audio", "mic_threshold_db", mic_threshold_db)), -55.0, -20.0)
	# Ekran & Grafik
	mode = clampi(int(c.get_value("display", "mode", mode)), 0, MODES.size() - 1)
	resolution = clampi(int(c.get_value("display", "resolution", resolution)), 0, RESOLUTIONS.size() - 1)
	vsync = clampi(int(c.get_value("display", "vsync", vsync)), 0, 2)
	fps_cap_idx = clampi(int(c.get_value("display", "fps_cap_idx", fps_cap_idx)), 0, FPS_CAPS.size() - 1)
	var old_high := bool(c.get_value("graphics", "quality_high", true))
	quality_level = clampi(int(c.get_value("graphics", "quality_level", 2 if old_high else 0)), 0, 2)
	quality_high = quality_level >= 2
	msaa = clampi(int(c.get_value("graphics", "msaa", 1 if quality_level >= 1 else 0)), 0, 2)
	shadows_level = clampi(int(c.get_value("graphics", "shadows_level", quality_level)), 0, 2)
	render_scale = clampf(float(c.get_value("graphics", "render_scale", render_scale)), 0.75, 1.0)
	ssao_enabled = bool(c.get_value("graphics", "ssao_enabled", quality_level >= 2))
	glow_enabled = bool(c.get_value("graphics", "glow_enabled", quality_level >= 1))
	vol_fog_enabled = bool(c.get_value("graphics", "vol_fog_enabled", quality_level >= 2))
	fov = clampf(float(c.get_value("graphics", "fov", fov)), 65.0, 105.0)
	show_fps = bool(c.get_value("graphics", "show_fps", show_fps))
	reduce_motion = bool(c.get_value("graphics", "reduce_motion", reduce_motion))
	# Kontroller
	mouse_sens = clampf(float(c.get_value("controls", "mouse_sens", mouse_sens)), 0.2, 3.0)
	invert_y = bool(c.get_value("controls", "invert_y", invert_y))
	gamepad_sens = clampf(float(c.get_value("controls", "gamepad_sens", gamepad_sens)), 0.5, 3.0)
	gamepad_deadzone = clampf(float(c.get_value("controls", "gamepad_deadzone", gamepad_deadzone)), 0.08, 0.35)
	for act: String in DEFAULT_KEYS:
		var kc := int(c.get_value("keybinds", act, DEFAULT_KEYS[act]))
		if kc > 0:
			keybinds[act] = kc
	# Oynanış
	lang = "en" if str(c.get_value("game", "lang", lang)) == "en" else "tr"
	crosshair_style = clampi(int(c.get_value("game", "crosshair_style", crosshair_style)), 0, 2)
	crosshair_scale = clampf(float(c.get_value("game", "crosshair_scale", crosshair_scale)), 0.7, 1.6)
	show_hints = bool(c.get_value("game", "show_hints", show_hints))
	tutorial_done = bool(c.get_value("game", "tutorial_done", tutorial_done))


func _ensure_audio_buses() -> void:
	for bname: String in ["SFX", "Music", "Ambience", "Voice", "VoiceMega"]:
		if AudioServer.get_bus_index(bname) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bname)
			AudioServer.set_bus_send(idx, "Voice" if bname == "VoiceMega" else "Master")
	# Megafon DSP kanalı: bant geçiren hoparlör filtresi + hafif sertlik
	var mb := AudioServer.get_bus_index("VoiceMega")
	if mb != -1 and AudioServer.get_bus_effect_count(mb) == 0:
		var bp := AudioEffectBandPassFilter.new()
		bp.cutoff_hz = 1650.0
		bp.resonance = 0.72
		AudioServer.add_bus_effect(mb, bp, 0)
		var dist := AudioEffectDistortion.new()
		dist.mode = AudioEffectDistortion.MODE_OVERDRIVE
		dist.drive = 0.32
		dist.post_gain = 1.8
		AudioServer.add_bus_effect(mb, dist, 1)


func _set_bus_linear(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)


func apply_audio() -> void:
	_ensure_audio_buses()
	_set_bus_linear("Master", volume)
	_set_bus_linear("SFX", sfx_vol)
	_set_bus_linear("Music", music_vol)
	_set_bus_linear("Ambience", ambience_vol)
	_set_bus_linear("Voice", voice_vol)
	if DisplayServer.get_name() != "headless" and mic_device != "":
		var devs := AudioServer.get_input_device_list()
		if mic_device in devs and AudioServer.input_device != mic_device:
			AudioServer.input_device = mic_device
	audio_changed.emit()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match vsync:
		0: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		2: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)
		_: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = int(FPS_CAPS[clampi(fps_cap_idx, 0, FPS_CAPS.size() - 1)])
	match mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = RESOLUTIONS[clampi(resolution, 0, RESOLUTIONS.size() - 1)]
			var screen := DisplayServer.screen_get_usable_rect()
			size = size.min(screen.size)
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func apply_graphics() -> void:
	quality_high = quality_level >= 2
	var vp := get_viewport()
	if vp:
		match msaa:
			2:
				vp.msaa_3d = Viewport.MSAA_4X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			1:
				vp.msaa_3d = Viewport.MSAA_2X
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			_:
				vp.msaa_3d = Viewport.MSAA_DISABLED
				vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		vp.scaling_3d_scale = clampf(render_scale, 0.75, 1.0)
	graphics_changed.emit()
	quality_changed.emit(quality_high)


func set_quality_preset(level: int) -> void:
	quality_level = clampi(level, 0, 2)
	quality_high = quality_level >= 2
	match quality_level:
		0: # Düşük
			msaa = 0
			shadows_level = 0
			ssao_enabled = false
			glow_enabled = false
			vol_fog_enabled = false
			render_scale = 0.85
		1: # Orta
			msaa = 1
			shadows_level = 1
			ssao_enabled = false
			glow_enabled = true
			vol_fog_enabled = false
			render_scale = 1.0
		_: # Yüksek
			msaa = 1
			shadows_level = 2
			ssao_enabled = true
			glow_enabled = true
			vol_fog_enabled = true
			render_scale = 1.0
	apply_graphics()
	save()


func set_quality(high: bool) -> void:
	set_quality_preset(2 if high else 0)


func set_language(new_lang: String) -> void:
	lang = "en" if new_lang == "en" else "tr"
	L10n.set_lang(lang)
	save()
	ui_prefs_changed.emit()


## Tüm klavye + varsayılan Gamepad/Steam Deck tuşlarını InputMap'e yükler.
func apply_keybinds() -> void:
	for act: String in DEFAULT_KEYS:
		if not InputMap.has_action(act):
			InputMap.add_action(act, gamepad_deadzone)
		else:
			InputMap.action_set_deadzone(act, gamepad_deadzone)
		InputMap.action_erase_events(act)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(keybinds.get(act, DEFAULT_KEYS[act]))
		InputMap.action_add_event(act, ev)
	# Varsayılan Xbox / Steam Deck kontrolcü atamaları
	for la: String in ["look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(la):
			InputMap.add_action(la, gamepad_deadzone)
		else:
			InputMap.action_set_deadzone(la, gamepad_deadzone)
		InputMap.action_erase_events(la)
	_add_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis("fwd", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("back", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_btn("jump", JOY_BUTTON_A)
	_add_joy_btn("interact", JOY_BUTTON_X)
	_add_joy_btn("refuse_offer", JOY_BUTTON_B)
	_add_joy_btn("throw_crate", JOY_BUTTON_Y)
	_add_joy_btn("run", JOY_BUTTON_LEFT_STICK)
	_add_joy_btn("shout", JOY_BUTTON_LEFT_SHOULDER)
	_add_joy_btn("ring_bell", JOY_BUTTON_DPAD_UP)
	_add_joy_btn("call_tea", JOY_BUTTON_DPAD_DOWN)
	_add_joy_btn("price_down", JOY_BUTTON_DPAD_LEFT)
	_add_joy_btn("price_up", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_btn("scoreboard", JOY_BUTTON_BACK)
	_add_joy_btn("ui_cancel", JOY_BUTTON_START)
	controls_changed.emit()


func _add_joy_axis(act: String, axis: JoyAxis, val: float) -> void:
	if not InputMap.has_action(act):
		return
	var j := InputEventJoypadMotion.new()
	j.axis = axis
	j.axis_value = val
	InputMap.action_add_event(act, j)


func _add_joy_btn(act: String, btn: JoyButton) -> void:
	if not InputMap.has_action(act):
		return
	var j := InputEventJoypadButton.new()
	j.button_index = btn
	InputMap.action_add_event(act, j)


func rebind_action(act: String, physical_kc: int) -> void:
	if not DEFAULT_KEYS.has(act) or physical_kc <= 0:
		return
	# Başka bir aksiyonda aynı tuş varsa eski aksiyonla takas et (çakışma önlenir)
	var old_kc: int = int(keybinds.get(act, DEFAULT_KEYS[act]))
	for other: String in keybinds:
		if other != act and int(keybinds[other]) == physical_kc:
			keybinds[other] = old_kc
	keybinds[act] = physical_kc
	apply_keybinds()
	save()


func key_label(act: String) -> String:
	var kc := int(keybinds.get(act, DEFAULT_KEYS.get(act, 0)))
	if kc <= 0:
		return "—"
	if DisplayServer.get_name() == "headless":
		return OS.get_keycode_string(kc)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(kc))


func reset_controls_defaults() -> void:
	mouse_sens = 1.0
	invert_y = false
	gamepad_sens = 1.2
	gamepad_deadzone = 0.15
	keybinds = DEFAULT_KEYS.duplicate()
	apply_keybinds()
	save()


func is_peer_muted(peer_id: int) -> bool:
	return bool(muted_peers.get(peer_id, false))


func set_peer_muted(peer_id: int, muted: bool) -> void:
	muted_peers[peer_id] = muted
	audio_changed.emit()


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "volume", volume)
	c.set_value("audio", "sfx_vol", sfx_vol)
	c.set_value("audio", "music_vol", music_vol)
	c.set_value("audio", "ambience_vol", ambience_vol)
	c.set_value("audio", "voice_vol", voice_vol)
	c.set_value("audio", "mic_device", mic_device)
	c.set_value("audio", "voice_mode", voice_mode)
	c.set_value("audio", "mic_gain", mic_gain)
	c.set_value("audio", "mic_threshold_db", mic_threshold_db)
	c.set_value("display", "mode", mode)
	c.set_value("display", "resolution", resolution)
	c.set_value("display", "vsync", vsync)
	c.set_value("display", "fps_cap_idx", fps_cap_idx)
	c.set_value("graphics", "quality_level", quality_level)
	c.set_value("graphics", "quality_high", quality_high)
	c.set_value("graphics", "msaa", msaa)
	c.set_value("graphics", "shadows_level", shadows_level)
	c.set_value("graphics", "render_scale", render_scale)
	c.set_value("graphics", "ssao_enabled", ssao_enabled)
	c.set_value("graphics", "glow_enabled", glow_enabled)
	c.set_value("graphics", "vol_fog_enabled", vol_fog_enabled)
	c.set_value("graphics", "fov", fov)
	c.set_value("graphics", "show_fps", show_fps)
	c.set_value("graphics", "reduce_motion", reduce_motion)
	c.set_value("controls", "mouse_sens", mouse_sens)
	c.set_value("controls", "invert_y", invert_y)
	c.set_value("controls", "gamepad_sens", gamepad_sens)
	c.set_value("controls", "gamepad_deadzone", gamepad_deadzone)
	for act: String in keybinds:
		c.set_value("keybinds", act, int(keybinds[act]))
	c.set_value("game", "lang", lang)
	c.set_value("game", "crosshair_style", crosshair_style)
	c.set_value("game", "crosshair_scale", crosshair_scale)
	c.set_value("game", "show_hints", show_hints)
	c.set_value("game", "tutorial_done", tutorial_done)
	c.save(PATH)
