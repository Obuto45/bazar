extends Node
## Oyun ayarları (ses, ekran, grafik kalitesi, rehber durumu). user://settings.cfg dosyasına kaydedilir.

signal quality_changed(high: bool)

const PATH := "user://settings.cfg"
const MODES := ["Pencere", "Tam ekran", "Kenarlıksız tam ekran"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

var volume := 0.8 # 0..1
var mode := 0 # MODES indeksi
var resolution := 0 # RESOLUTIONS indeksi
var quality_high := true # Yüksek grafik (SSAO/glow/hacimsel sis, MSAA)
var tutorial_done := false # İlk açılış rehberi bitti / geçildi mi?


func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK: # dosya elle bozulmuş olabilir: sınırla
		volume = clampf(float(c.get_value("audio", "volume", volume)), 0.0, 1.0)
		mode = clampi(int(c.get_value("display", "mode", mode)), 0, MODES.size() - 1)
		resolution = clampi(int(c.get_value("display", "resolution", resolution)), 0, RESOLUTIONS.size() - 1)
		quality_high = bool(c.get_value("graphics", "quality_high", quality_high))
		tutorial_done = bool(c.get_value("game", "tutorial_done", tutorial_done))
	apply_audio()
	apply_display()
	apply_graphics()


func apply_audio() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(bus, volume <= 0.001)


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match mode:
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = RESOLUTIONS[resolution]
			var screen := DisplayServer.screen_get_usable_rect()
			size = size.min(screen.size) # ekrandan büyük olmasın
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


## Görüntü kalitesi: viewport tarafı burada (MSAA), ortam efektleri bazaar.gd set_quality() ile (main çağırır).
func apply_graphics() -> void:
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_2X if quality_high else Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if quality_high else Viewport.SCREEN_SPACE_AA_FXAA


func set_quality(high: bool) -> void:
	if high == quality_high:
		return
	quality_high = high
	apply_graphics()
	quality_changed.emit(high)
	save()


func save() -> void:
	var c := ConfigFile.new()
	c.set_value("audio", "volume", volume)
	c.set_value("display", "mode", mode)
	c.set_value("display", "resolution", resolution)
	c.set_value("graphics", "quality_high", quality_high)
	c.set_value("game", "tutorial_done", tutorial_done)
	c.save(PATH)
