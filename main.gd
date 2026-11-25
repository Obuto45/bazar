extends Node3D
## Menü, lobi ve oyun akışı. Arkada canlı pazar sahnesi döner; host "Pazarı Aç" deyince herkes pazara girer.

const PlayerScript := preload("res://player.gd")
const BazaarScript := preload("res://bazaar.gd")
const StallScript := preload("res://stall.gd")
const CustomerScript := preload("res://customer.gd")
const SPAWNS := [Vector3(0, 0.2, 6), Vector3(2, 0.2, 6), Vector3(-2, 0.2, 6), Vector3(0, 0.2, -6),
	Vector3(2, 0.2, -6), Vector3(-2, 0.2, -6), Vector3(6, 0.2, 0), Vector3(-6, 0.2, 0)]
const GOLD := Color(1.0, 0.74, 0.3)
const INK := Color(0.09, 0.06, 0.05)

var ui: Control
var pages := {}
var page := ""
var info: Label
var members: Label
var start_btn: Button
var host_btn: Button
var friends_box: VBoxContainer
var invite_box: VBoxContainer
var pause_wrap: ColorRect
var vol_lbl: Label
var hint: Label
var voice_hud: PanelContainer
var voice_icon: Control
var voice_bar: ColorRect
var voice_lbl: Label
var money_hud: PanelContainer
var money_lbl: Label
var money_pop: Label
var crosshair: ColorRect
var interact_lbl: Label
var ingame_box: VBoxContainer
var world: Node3D
var players: Node3D
var stalls: Node3D
var customers: Node3D
var _stall_count := 0
var _cust_seq := 0
var _cust_cd := 1.5
var menu_bg: Node3D
var menu_cam: Camera3D
var walkers := [] # menüde çeşme etrafında yürüyen figüranlar: [düğüm, yarıçap, açı, hız]
var menu_t := 0.0


func _ready() -> void:
	_setup_input()
	_build_ui()
	Net.status.connect(func(m): info.text = m)
	Net.lobby_changed.connect(_refresh)
	Net.left.connect(_back_to_menu)
	Net.invited.connect(_on_invited)
	Updater.status.connect(func(m): info.text = m)
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	_set_menu_bg(true)
	_show_page("main")
	_refresh()
	var args := OS.get_cmdline_user_args()
	if "--mptest" in args: # iki pencereli ağ testi: biri --mptest host, öteki --mptest join; 6 sn sonra kare kaydeder
		if "host" in args:
			Net.host_local()
			await get_tree().create_timer(2.5).timeout
			_on_start()
		else:
			await get_tree().create_timer(0.5).timeout
			Net.join_local()
		await get_tree().create_timer(3.5).timeout
		var me = players.get_node_or_null(str(multiplayer.get_unique_id())) if players else null
		if me and "host" in args:
			me.look_yaw += 1.0 # kafa döner, gövde sınır içinde yerinde kalmalı
		elif me and players.has_node("1"): # istemci host'a bakar
			var d: Vector3 = players.get_node("1").global_position - me.global_position
			me.look_yaw = atan2(-d.x, -d.z)
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mptest_%s.png" % ("host" if "host" in args else "join"))
		get_tree().quit()
		return
	if "--selftest" in OS.get_cmdline_user_args(): # hızlı kontrol: menü + pazar karesi kaydeder, çıkar
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_menu.png")
		Net.host_local()
		_on_start()
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_game.png")
		var me = players.get_node("1")
		me.look_pitch = -1.1 # aşağı bak: eller ve ayaklar görünmeli
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_down.png")
		get_tree().quit()


func _setup_input() -> void:
	var keys := {
		"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"jump": KEY_SPACE, "run": KEY_SHIFT, "mic_mute": KEY_M,
		"interact": KEY_E, "throw_crate": KEY_Q, "price_down": KEY_Z, "price_up": KEY_X, "shout": KEY_B,
	}
	for a in keys:
		InputMap.add_action(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[a]
		InputMap.action_add_event(a, ev)


# ---------- Arayüz ----------

func _sb(c: Color, radius := 10, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _font(weight := 800) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Arial", "Sans-Serif"])
	f.font_weight = weight
	return f


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(600)
	t.default_font_size = 18
	var normal := _sb(Color(0.16, 0.1, 0.08, 0.9))
	normal.set_border_width_all(2)
	normal.border_color = Color(GOLD, 0.35)
	var hover := _sb(Color(0.78, 0.33, 0.16))
	hover.set_border_width_all(2)
	hover.border_color = GOLD
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", _sb(Color(0.55, 0.22, 0.1)))
	t.set_stylebox("disabled", "Button", _sb(Color(0.12, 0.09, 0.08, 0.55)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(1.0, 0.95, 0.86))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.45))
	for k in ["normal", "hover", "pressed"]:
		t.set_stylebox(k, "OptionButton", t.get_stylebox(k, "Button"))
	var p := _sb(Color(0.08, 0.05, 0.04, 0.88), 16, 24)
	p.set_border_width_all(2)
	p.border_color = Color(GOLD, 0.5)
	t.set_stylebox("panel", "PanelContainer", p)
	# Büyük menü düğmesi: sola yaslı, üstüne gelince altın şerit ve içeri kayma
	t.set_type_variation("BigButton", "Button")
	var bn := _sb(Color(0, 0, 0, 0), 6, 0)
	bn.content_margin_left = 20
	var bh := _sb(Color(0.78, 0.33, 0.16, 0.92), 6, 0)
	bh.content_margin_left = 38
	bh.border_width_left = 6
	bh.border_color = GOLD
	for k in ["normal", "disabled"]:
		t.set_stylebox(k, "BigButton", bn)
	for k in ["hover", "pressed"]:
		t.set_stylebox(k, "BigButton", bh)
	t.set_font_size("font_size", "BigButton", 30)
	t.set_font("font", "BigButton", _font(900))
	t.set_constant("outline_size", "BigButton", 6)
	t.set_color("font_outline_color", "BigButton", Color(0, 0, 0, 0.6))
	return t


func _lbl(parent: Node, text: String, size: int, alpha := 0.9) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate.a = alpha
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	parent.add_child(l)
	return l


func _logo(parent: Node, text: String, size: int, c := GOLD) -> Label:
	var l := _lbl(parent, text, size, 1.0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("font", _font(900))
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	l.add_theme_constant_override("shadow_offset_y", maxi(size / 14, 2))
	return l


func _btn(parent: Node, text: String, cb: Callable, h := 42) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = h
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _big(parent: Node, text: String, cb: Callable) -> Button:
	var b := _btn(parent, text, cb, 58)
	b.theme_type_variation = "BigButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func _gap(parent: Node, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	parent.add_child(c)


func _page(n: String) -> VBoxContainer:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.hide()
	ui.add_child(c)
	pages[n] = c
	var v := VBoxContainer.new() # sol sütun, sağ taraf sahneye kalır
	v.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	v.offset_left = 80; v.offset_right = 80 + 460
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	c.add_child(v)
	return v


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := _make_theme()
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = theme
	layer.add_child(ui)
	var shade := TextureRect.new() # soldan kararma: yazılar okunsun
	var grad := Gradient.new()
	grad.set_color(0, Color(0.06, 0.03, 0.02, 0.92))
	grad.set_color(1, Color(0.06, 0.03, 0.02, 0.0))
	grad.add_point(0.45, Color(0.06, 0.03, 0.02, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)

	# Ana menü
	var mv := _page("main")
	_logo(mv, "BAZAR", 120)
	_lbl(mv, "Arkadaşlarınla pazarda buluş.", 20, 0.8)
	_gap(mv, 30)
	_big(mv, "OYNA", _show_page.bind("lobby"))
	_big(mv, "AYARLAR", _open_pause)
	_big(mv, "ÇIKIŞ", get_tree().quit)
	_gap(mv, 24)
	var st := _lbl(mv, ("●  Steam: " + Net.my_name()) if Net.steam_ok else "●  Steam bağlı değil (Steam açık mı?)", 15, 0.8)
	st.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55) if Net.steam_ok else Color(1.0, 0.6, 0.5))

	# Lobi
	var lv := _page("lobby")
	_logo(lv, "LOBİ", 72)
	_lbl(lv, "Lobi kur, arkadaşlarını çağır, pazarı aç.", 17, 0.75)
	_gap(lv, 10)
	var panel := PanelContainer.new()
	lv.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	panel.add_child(v)
	host_btn = _btn(v, "Steam Lobisi Kur", Net.host_steam)
	_btn(v, "Arkadaşlar  (davet et / lobisine katıl)", _show_friends)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	friends_box = VBoxContainer.new()
	friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(friends_box)
	v.add_child(scroll)
	members = _lbl(v, "", 16)
	start_btn = _btn(v, "▶  Pazarı Aç", _on_start, 52)
	start_btn.add_theme_font_size_override("font_size", 22)
	_btn(v, "Lobiden Çık", Net.leave)
	var test := HBoxContainer.new()
	test.add_theme_constant_override("separation", 8)
	v.add_child(test)
	var tl := _lbl(test, "Tek PC testi:", 14, 0.6)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	for b in [_btn(test, "Yerel Host", Net.host_local, 34), _btn(test, "Yerel Katıl", Net.join_local, 34)]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gap(lv, 6)
	_btn(lv, "◀  Geri", _show_page.bind("main"))

	info = _lbl(ui, "", 15, 0.85)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_left = 80; info.offset_right = -230; info.offset_top = -60; info.offset_bottom = -24
	var ver := _lbl(ui, "sürüm " + Updater.version(), 14, 0.55)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -200; ver.offset_right = -24; ver.offset_top = -50; ver.offset_bottom = -24
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	invite_box = VBoxContainer.new() # gelen davet sağ üstte
	invite_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	invite_box.offset_left = -380; invite_box.offset_right = -30; invite_box.offset_top = 30
	ui.add_child(invite_box)

	hint = _lbl(layer, "WASD yürü  •  E kasa al/sat  •  Sol Tık diz  •  Q fırlat  •  Tekerlek / Z-X fiyat  •  B/Mikrofon bağır  •  M mikrofon  •  ESC", 14, 0.78)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 20; hint.offset_top = -38; hint.offset_bottom = -12
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.hide()
	_build_voice_hud(layer, theme)
	_build_market_hud(layer, theme)
	_build_pause(layer, theme)


## Ekranın sağ tarafında sesli konuşma simgesi ve canlı dB seviye göstergesi.
class MicIcon extends Control:
	var level := 0.0
	var muted := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.95, 0.3, 0.25) if muted else (Color(0.42, 0.96, 0.52) if level > 0.05 else Color(1.0, 0.92, 0.78, 0.85))
		# Konuşurken dış ses halkası (dB ile büyür)
		if not muted and level > 0.04:
			draw_arc(c + Vector2(0, -3), 16.0 + level * 8.0, 0, TAU, 28, Color(col.r, col.g, col.b, 0.35 + level * 0.45), 2.5, true)
		# Mikrofon kapsülü
		draw_circle(c + Vector2(0, -10), 6.5, col)
		draw_rect(Rect2(c + Vector2(-6.5, -10), Vector2(13.0, 10.0)), col)
		draw_circle(c + Vector2(0, 0), 6.5, col)
		# U-çerçeve ve ayak
		draw_arc(c + Vector2(0, -1), 11.5, 0.15, PI - 0.15, 18, col, 2.5, true)
		draw_line(c + Vector2(0, 10.5), c + Vector2(0, 16.0), col, 2.5, true)
		draw_line(c + Vector2(-7.0, 16.0), c + Vector2(7.0, 16.0), col, 2.5, true)
		# Susturulmuşsa çapraz çizgi
		if muted:
			draw_line(c + Vector2(-14, -14), c + Vector2(14, 14), Color(1.0, 0.28, 0.22), 3.2, true)


func _build_voice_hud(layer: CanvasLayer, theme: Theme) -> void:
	voice_hud = PanelContainer.new()
	voice_hud.theme = theme
	var box := _sb(Color(0.08, 0.05, 0.04, 0.82), 14, 10)
	box.set_border_width_all(2)
	box.border_color = Color(GOLD, 0.5)
	voice_hud.add_theme_stylebox_override("panel", box)
	voice_hud.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	voice_hud.offset_left = -94; voice_hud.offset_right = -20
	voice_hud.offset_top = -56; voice_hud.offset_bottom = 56
	voice_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(voice_hud)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	voice_hud.add_child(v)
	voice_icon = MicIcon.new()
	voice_icon.custom_minimum_size = Vector2(52, 46)
	v.add_child(voice_icon)
	var meter_bg := ColorRect.new()
	meter_bg.custom_minimum_size = Vector2(52, 7)
	meter_bg.color = Color(0.2, 0.15, 0.12, 0.9)
	v.add_child(meter_bg)
	voice_bar = ColorRect.new()
	voice_bar.color = Color(0.4, 0.95, 0.5)
	voice_bar.size = Vector2(0, 7)
	meter_bg.add_child(voice_bar)
	voice_lbl = _lbl(v, "M: AÇIK", 12, 0.85)
	voice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_hud.hide()


## Sağ üst Para UI + ekran ortası nişangah ve etkileşim ipucu.
func _build_market_hud(layer: CanvasLayer, theme: Theme) -> void:
	money_hud = PanelContainer.new()
	money_hud.theme = theme
	var box := _sb(Color(0.08, 0.05, 0.04, 0.85), 14, 12)
	box.set_border_width_all(2)
	box.border_color = Color(GOLD, 0.7)
	money_hud.add_theme_stylebox_override("panel", box)
	money_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_hud.offset_left = -210; money_hud.offset_right = -20
	money_hud.offset_top = 20; money_hud.offset_bottom = 74
	money_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(money_hud)
	money_lbl = _lbl(money_hud, "0 TL", 26, 1.0)
	money_lbl.add_theme_font_override("font", _font(900))
	money_lbl.add_theme_color_override("font_color", GOLD)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_hud.hide()

	money_pop = _lbl(layer, "", 24, 1.0)
	money_pop.add_theme_font_override("font", _font(900))
	money_pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	money_pop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_pop.offset_left = -210; money_pop.offset_right = -24
	money_pop.offset_top = 78; money_pop.offset_bottom = 112
	money_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_pop.hide()

	crosshair = ColorRect.new()
	crosshair.color = Color(1.0, 0.96, 0.88, 0.85)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -3; crosshair.offset_right = 3
	crosshair.offset_top = -3; crosshair.offset_bottom = 3
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(crosshair)
	crosshair.hide()

	interact_lbl = _lbl(layer, "", 18, 0.95)
	interact_lbl.set_anchors_preset(Control.PRESET_CENTER)
	interact_lbl.offset_left = -320; interact_lbl.offset_right = 320
	interact_lbl.offset_top = 22; interact_lbl.offset_bottom = 56
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	interact_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_lbl.hide()


func _on_money_earned(amount: int, total: int) -> void:
	money_lbl.text = "%d TL" % total
	money_pop.text = "+%d TL" % amount
	money_pop.modulate.a = 1.0
	money_pop.offset_top = 82
	money_pop.show()
	var tw := create_tween().set_parallel()
	tw.tween_property(money_pop, "offset_top", 56.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(money_pop, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(money_pop.hide)


## Ayarlar / duraklat paneli: menüde ayarlar, oyunda ayrıca devam ve lobiye dön.
func _build_pause(layer: CanvasLayer, theme: Theme) -> void:
	pause_wrap = ColorRect.new()
	pause_wrap.color = Color(0, 0, 0, 0.55)
	pause_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_wrap.theme = theme
	layer.add_child(pause_wrap)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_wrap.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 420
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_logo(v, "AYARLAR", 40).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vol_lbl = _lbl(v, "", 17)
	var vol := HSlider.new()
	vol.min_value = 0; vol.max_value = 1; vol.step = 0.05
	vol.value = Settings.volume
	vol.value_changed.connect(_on_volume)
	v.add_child(vol)
	_on_volume(Settings.volume)
	_lbl(v, "Ekran", 17)
	var mode := OptionButton.new()
	for m in Settings.MODES:
		mode.add_item(m)
	mode.selected = Settings.mode
	mode.item_selected.connect(func(i): Settings.mode = i; Settings.apply_display(); Settings.save())
	v.add_child(mode)
	_gap(v, 6)
	ingame_box = VBoxContainer.new()
	ingame_box.add_theme_constant_override("separation", 10)
	v.add_child(ingame_box)
	_btn(ingame_box, "Lobiye Dön (oyundan çık)", Net.leave)
	_btn(ingame_box, "Oyunu Kapat", get_tree().quit)
	_btn(v, "Kapat", _close_pause, 46)
	pause_wrap.hide()


func _on_volume(x: float) -> void:
	Settings.volume = x
	Settings.apply_audio()
	vol_lbl.text = "Ses: %d%%" % roundi(x * 100)


func _open_pause() -> void:
	ingame_box.visible = world != null
	pause_wrap.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause() -> void:
	pause_wrap.hide()
	Settings.save()
	if world:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_page(n: String) -> void:
	page = n
	for k in pages:
		pages[k].visible = k == n
	var col: Control = pages[n].get_child(0) # içerik soldan kayarak gelsin
	col.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "modulate:a", 1.0, 0.35)
	tw.tween_property(col, "position:x", col.position.x, 0.4).from(col.position.x - 50)


func _show_friends() -> void:
	for c in friends_box.get_children():
		c.queue_free()
	var list := Net.online_friends()
	var n := 0
	for f in list:
		if f[2] != 0 and f[2] != Net.lobby_id:
			_btn(friends_box, "▶ Lobisine katıl: " + f[1], Net.join_lobby.bind(f[2]), 36)
			n += 1
		if Net.lobby_id != 0:
			_btn(friends_box, "✉ Davet et: " + f[1], Net.invite_friend.bind(f[0], f[1]), 36)
			n += 1
	if not Net.steam_ok:
		info.text = "Steam bağlı değil."
	elif list.is_empty():
		info.text = "Çevrimiçi Steam arkadaşı yok."
	elif Net.lobby_id == 0:
		info.text = "Davet için önce 'Steam Lobisi Kur'a bas. Lobisi olan arkadaşa ▶ ile katılabilirsin."
	(friends_box.get_parent() as Control).custom_minimum_size.y = mini(n, 5) * 41


func _on_invited(from_name: String, lobby: int) -> void:
	for c in invite_box.get_children():
		c.queue_free()
	var panel := PanelContainer.new()
	invite_box.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_lbl(v, "%s seni pazarına davet etti!" % from_name, 18, 1.0)
	_btn(v, "✔ Kabul Et", func():
		for c in invite_box.get_children():
			c.queue_free()
		Net.join_lobby(lobby))
	_btn(v, "✖ Reddet", func():
		for c in invite_box.get_children():
			c.queue_free())


func _refresh() -> void:
	var lines := PackedStringArray()
	for id in Net.names:
		lines.append(("★ " if id == 1 else "• ") + str(Net.names[id]))
	members.text = ("Lobidekiler:\n" + "\n".join(lines)) if Net.online() else "Henüz lobide değilsin."
	start_btn.disabled = not (Net.online() and multiplayer.is_server())
	start_btn.text = "▶  Pazarı Aç" if not Net.online() or multiplayer.is_server() else "Host pazarı açacak..."
	host_btn.disabled = Net.lobby_id != 0
	if players: # geç gelen adlar isim etiketlerine ve tezgah tabelalarına yansısın
		for p in players.get_children():
			var pid := p.name.to_int()
			var dn := Net.display_name(pid)
			p.set_display_name(dn)
			if stalls:
				var st := stalls.get_node_or_null("Stall_%d" % pid)
				if st:
					st.set_owner_display_name(dn)
	if Net.online() and world == null and page == "main":
		_show_page("lobby")


# ---------- Menü sahnesi ----------

func _set_menu_bg(on: bool) -> void:
	if menu_bg:
		remove_child(menu_bg)
		menu_bg.queue_free()
		menu_bg = null
		walkers.clear()
	if not on:
		return
	menu_bg = Node3D.new()
	add_child(menu_bg)
	menu_bg.add_child(BazaarScript.new())
	menu_cam = Camera3D.new()
	menu_cam.fov = 60
	menu_bg.add_child(menu_cam)
	menu_cam.current = true
	for i in 7:
		var p: Node3D = PlayerScript.new()
		p.npc = true
		p.color_id = i * 3 + 1
		p.name = "Npc%d" % i
		menu_bg.add_child(p)
		walkers.append([p, randf_range(3.6, 5.5), randf() * TAU, randf_range(0.6, 0.85) * (1 if i % 2 == 0 else -1)])


func _menu_anim(dt: float) -> void:
	menu_t += dt
	var a := menu_t * 0.05
	menu_cam.position = Vector3(sin(a) * 15.0, 5.5 + sin(menu_t * 0.2) * 0.5, cos(a) * 15.0)
	menu_cam.look_at(Vector3(sin(a + 0.6) * 2.0, 1.2, cos(a + 0.6) * 2.0))
	for w in walkers: # çeşmenin etrafında tur atan figüranlar
		var p: Node3D = w[0]
		w[2] += w[3] * dt * 4.2 / w[1]
		p.position = Vector3(cos(w[2]) * w[1], 0, sin(w[2]) * w[1])
		var tangent := Vector3(-sin(w[2]), 0, cos(w[2])) * signf(w[3])
		p.body_yaw = atan2(tangent.x, tangent.z)
		p.look_yaw = p.body_yaw + sin(menu_t * 0.7 + w[1]) * 0.5 - PI # kafa ara ara etrafa bakar
		p.spd = 4.2 * absf(w[3]) # açısal hızla aynı: ayak kaymaz


func _process(dt: float) -> void:
	if menu_bg:
		_menu_anim(dt)
	if world and players and voice_hud.visible:
		var me := players.get_node_or_null(str(multiplayer.get_unique_id()))
		if me:
			var lvl: float = me.talk_smooth
			var muted: bool = me.mic_muted
			voice_icon.level = lvl
			voice_icon.muted = muted
			voice_icon.queue_redraw()
			voice_bar.size.x = 0.0 if muted else 52.0 * lvl
			voice_bar.color = Color(0.95, 0.3, 0.25) if muted else (Color(1.0, 0.72, 0.2) if lvl > 0.7 else Color(0.4, 0.95, 0.5))
			voice_lbl.text = "M: KAPALI" if muted else ("BAĞIRIYOR!" if me.shout_power > 0.55 else ("KONUŞUYOR" if lvl > 0.06 else "M: AÇIK"))
			interact_lbl.text = me.interact_hint
			interact_lbl.visible = me.interact_hint != "" and not pause_wrap.visible
	if world and customers and ((not Net.online()) or multiplayer.is_server()):
		_tick_customers(dt)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if pause_wrap.visible:
			_close_pause()
		elif world:
			_open_pause()
		elif page == "lobby":
			_show_page("main")
		return
	if world and not pause_wrap.visible and e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- Oyun akışı ----------

func _player_ids() -> Array:
	var ids := [1]
	ids.append_array(Array(multiplayer.get_peers()))
	ids.sort()
	return ids


func _on_start() -> void:
	if multiplayer.is_server():
		start_game.rpc(_player_ids())


@rpc("authority", "call_local", "reliable")
func start_game(ids: Array) -> void:
	_clear_world()
	_set_menu_bg(false)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	var bz := BazaarScript.new()
	bz.interactive = true
	world.add_child(bz)
	stalls = Node3D.new()
	stalls.name = "Stalls"
	world.add_child(stalls)
	customers = Node3D.new()
	customers.name = "Customers"
	world.add_child(customers)
	players = Node3D.new()
	players.name = "Players"
	world.add_child(players)
	_stall_count = 0
	_cust_seq = 0
	_cust_cd = 1.5
	for id in ids:
		_spawn(id)
	ui.hide()
	hint.show()
	voice_hud.show()
	money_lbl.text = "0 TL"
	money_hud.show()
	crosshair.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn(id: int) -> void:
	if players == null or players.has_node(str(id)):
		return
	# Her oyuncuya kendine ait bir tezgah (başta boş, arkasında depo kasaları)
	var spot_idx := _stall_count % BazaarScript.PLAYER_STALL_SPOTS.size()
	_stall_count += 1
	var spot: Array = BazaarScript.PLAYER_STALL_SPOTS[spot_idx]
	var st := StallScript.new()
	st.setup(id, Net.display_name(id), id)
	st.position = spot[0]
	st.rotation.y = spot[1]
	stalls.add_child(st)

	var p: CharacterBody3D = PlayerScript.new()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.spawn_pos = st.owner_spawn_pos()
	p.look_yaw = spot[1] + PI # tezgahın önüne (caddeye) bakarak başla
	players.add_child(p)
	if p.is_multiplayer_authority():
		p.money_earned.connect(_on_money_earned)


func _tick_customers(dt: float) -> void:
	_cust_cd -= dt
	if _cust_cd > 0.0 or customers.get_child_count() >= 7:
		return
	_cust_cd = randf_range(3.0, 5.2)
	_cust_seq += 1
	var from_north := randf() < 0.5
	var x_lane := randf_range(-2.6, 2.6)
	var start_p := Vector3(x_lane, 0.0, -19.5 if from_north else 19.5)
	var exit_p := Vector3(randf_range(-2.4, 2.4), 0.0, 19.5 if from_north else -19.5)
	# 1 ila 3 farklı ürün çeşidi, her birinden 1-2 adet
	var item_pool := StallScript.ITEM_ORDER.duplicate()
	item_pool.shuffle()
	var n_types := 1 if randf() < 0.45 else (2 if randf() < 0.8 else 3)
	var wants := {}
	for i in n_types:
		wants[item_pool[i]] = randi_range(1, 2)
	var cname := "Cust_%d" % _cust_seq
	var seed_val := randi_range(1, 9999)
	if Net.online():
		rpc_spawn_customer.rpc(cname, seed_val, start_p, exit_p, wants)
	else:
		rpc_spawn_customer(cname, seed_val, start_p, exit_p, wants)


@rpc("authority", "call_local", "reliable")
func rpc_spawn_customer(cname: String, seed_val: int, start_p: Vector3, exit_p: Vector3, wants: Dictionary) -> void:
	if customers == null or customers.has_node(cname):
		return
	var c := CustomerScript.new()
	c.init_customer(cname, seed_val, start_p, exit_p, wants)
	customers.add_child(c)


## Pazar açıkken gelen arkadaş: ona pazarı aç, herkese yeni oyuncuyu ekle.
func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server() or world == null:
		return
	var w := world
	await get_tree().create_timer(0.5).timeout # adı kaydolsun
	if world != w or not id in multiplayer.get_peers():
		return
	start_game.rpc_id(id, _player_ids())
	add_player.rpc(id)


@rpc("authority", "call_local", "reliable")
func add_player(id: int) -> void:
	_spawn(id)


func _on_peer_left(id: int) -> void:
	if players:
		var n := players.get_node_or_null(str(id))
		if n:
			players.remove_child(n) # isim hemen boşalsın, yeniden katılırsa oluşabilsin
			n.queue_free()


func _clear_world() -> void:
	if world:
		remove_child(world) # isim hemen boşalsın, RPC yolları eşleşsin
		world.queue_free()
	world = null
	players = null
	stalls = null
	customers = null


func _back_to_menu() -> void:
	_clear_world()
	pause_wrap.hide()
	hint.hide()
	voice_hud.hide()
	money_hud.hide()
	money_pop.hide()
	crosshair.hide()
	interact_lbl.hide()
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu_bg == null:
		_set_menu_bg(true)
	_show_page("lobby" if Net.online() else "main")
	_refresh()
