extends Node3D
## Menü, lobi, Pazar Günü döngüsü, Toptancı ekonomisi, rastgele olaylar, Zabıta,
## Tezgah Geliştirme mağazası, Skor Tablosu, Gün Sonu özeti ve tam multiplayer senkronu.

const PlayerScript := preload("res://player.gd")
const BazaarScript := preload("res://bazaar.gd")
const StallScript := preload("res://stall.gd")
const CustomerScript := preload("res://customer.gd")
const InspectorScript := preload("res://inspector.gd")
const Produce := preload("res://produce.gd")

const DAY_DURATION := 300.0 # 5 dakikalık Pazar Günü (08:00 -> 21:30)
const GOLD := Color(1.0, 0.74, 0.3)
const INK := Color(0.09, 0.06, 0.05)

const MARKET_EVENTS := [
	{"item": "domates", "title": "🍅 DOMATES KITLIĞI! Talep & adil fiyat uçtu!"},
	{"item": "karpuz", "title": "🍉 SICAK BASTI! Karpuz Fırtınası başladı!"},
	{"item": "elma", "title": "🍏 ELMA ŞENLİĞİ! Herkes elma arıyor!"},
	{"item": "portakal", "title": "🍊 VİTAMİN GÜNLERİ! Portakala akın var!"},
	{"item": "muz", "title": "🍌 MUZ AKINI! Müşteriler muz için sıraya giriyor!"},
	{"item": "patlican", "title": "🍆 KÖZ PATLICAN GÜNÜ! Patlıcan revaçta!"},
	{"item": "sogan", "title": "🧅 SOĞAN KRİZİ! Soğan fiyatları fırladı!"},
]

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

# Yeni HUD & modal paneller
var day_hud: PanelContainer
var day_lbl: Label
var day_bar: ColorRect
var event_banner: PanelContainer
var event_lbl: Label
var toast_box: VBoxContainer
var upgrade_wrap: ColorRect
var upgrade_rows: Dictionary = {} # key -> [Button, Label]
var upgrade_wallet_lbl: Label
var scoreboard_wrap: ColorRect
var scoreboard_list: VBoxContainer
var summary_wrap: ColorRect
var summary_title: Label
var summary_list: VBoxContainer
var next_day_btn: Button

var world: Node3D
var bazaar_node: Node3D
var players: Node3D
var stalls: Node3D
var customers: Node3D
var _stall_spots := {} # peer_id -> spot_idx (0..7)
var _cust_seq := 0
var _cust_cd := 1.5
var _price_ui_cd := 0.0

# Gün ve ekonomi durumu (Host otoritesi)
var day_num := 1
var day_time := 0.0
var day_ended := false
var wholesale_prices: Dictionary = {}
var deal_item := "domates"
var active_event_item := ""
var active_event_title := ""
var event_timer := 0.0
var next_event_cd := 38.0
var next_zabita_cd := 62.0
var next_price_shift_cd := 75.0
var rush_announced := false
var _day_sync_t := 0.0

var menu_bg: Node3D
var menu_cam: Camera3D
var walkers := []
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
	if "--mptest" in args:
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
			me.look_yaw += 1.0
		elif me and players.has_node("1"):
			var d: Vector3 = players.get_node("1").global_position - me.global_position
			me.look_yaw = atan2(-d.x, -d.z)
		await get_tree().create_timer(1.5).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mptest_%s.png" % ("host" if "host" in args else "join"))
		print("MPTEST_OK ", "host" if "host" in args else "join", " players=", players.get_child_count() if players else 0, " stalls=", stalls.get_child_count() if stalls else 0)
		get_tree().quit()
		return
	if "--selftest" in args:
		await get_tree().create_timer(1.4).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_menu.png")
		Net.host_local()
		_on_start()
		await get_tree().create_timer(1.4).timeout
		# Tezgahı ürün ve yükseltmelerle doldurup gerçekçi görünüm test et
		var st1 := stalls.get_node_or_null("Stall_1")
		if st1:
			st1.rpc_sync_slot(0, "domates", 8, 10)
			st1.rpc_sync_slot(1, "karpuz", 5, 26)
			st1.rpc_sync_slot(2, "muz", 7, 19)
			st1.rpc_sync_slot(3, "patlican", 6, 17)
			st1.rpc_apply_upgrade("lights")
			st1.rpc_apply_upgrade("bell")
		day_time = DAY_DURATION * 0.35 # parlak öğle
		if bazaar_node:
			bazaar_node.set_day_progress(0.35)
		await get_tree().create_timer(0.6).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_game.png")
		# Gün batımı + yanan fenerler + tezgah ışıkları + Toptancı Kamyonu önizlemesi
		day_time = DAY_DURATION * 0.82
		if bazaar_node:
			bazaar_node.set_day_progress(0.82)
		var me1 := players.get_node_or_null("1")
		if me1:
			me1.global_position = Vector3(-4.5, 0.2, 1.5)
			me1.look_yaw = 1.35 # Batıdaki Toptancı Kamyonu ve çeşmeye bak
			me1.look_pitch = -0.05
		await get_tree().create_timer(0.6).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_sunset.png")
		print("SELFTEST_OK stalls=", stalls.get_child_count() if stalls else 0, " customers=", customers.get_child_count() if customers else 0)
		get_tree().quit()


func _setup_input() -> void:
	var keys := {
		"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D,
		"jump": KEY_SPACE, "run": KEY_SHIFT, "mic_mute": KEY_M,
		"interact": KEY_E, "throw_crate": KEY_Q, "price_down": KEY_Z, "price_up": KEY_X, "shout": KEY_B,
		"refuse_offer": KEY_R, "upgrade_shop": KEY_U, "ring_bell": KEY_F, "scoreboard": KEY_TAB,
	}
	for a in keys:
		if not InputMap.has_action(a):
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
	f.font_names = PackedStringArray(["Segoe UI", "Segoe UI Emoji", "Arial", "Sans-Serif"])
	f.font_weight = weight
	return f


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(600)
	t.default_font_size = 18
	var normal := _sb(Color(0.16, 0.1, 0.08, 0.92))
	normal.set_border_width_all(2)
	normal.border_color = Color(GOLD, 0.38)
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
	var p := _sb(Color(0.08, 0.05, 0.04, 0.90), 16, 22)
	p.set_border_width_all(2)
	p.border_color = Color(GOLD, 0.55)
	t.set_stylebox("panel", "PanelContainer", p)
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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.78))
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
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0); cb.call())
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
	var v := VBoxContainer.new()
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
	var shade := TextureRect.new()
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
	_lbl(mv, "Arkadaşlarınla pazarda buluş, bağır, pazarlık yap, kazan!", 19, 0.85)
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
	invite_box = VBoxContainer.new()
	invite_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	invite_box.offset_left = -380; invite_box.offset_right = -30; invite_box.offset_top = 30
	ui.add_child(invite_box)

	hint = _lbl(layer, "WASD yürü • E kasa al/sat • Sol Tık diz • Q fırlat • Tekerlek/Z-X fiyat • B/Mik bağır • R olmaz • U geliştir • F zil • Tab skor • ESC", 13, 0.8)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 16; hint.offset_right = -16; hint.offset_top = -34; hint.offset_bottom = -10
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.hide()
	_build_voice_hud(layer, theme)
	_build_market_hud(layer, theme)
	_build_upgrade_panel(layer, theme)
	_build_scoreboard(layer, theme)
	_build_summary(layer, theme)
	_build_pause(layer, theme)


class MicIcon extends Control:
	var level := 0.0
	var muted := false

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.95, 0.3, 0.25) if muted else (Color(0.42, 0.96, 0.52) if level > 0.05 else Color(1.0, 0.92, 0.78, 0.85))
		if not muted and level > 0.04:
			draw_arc(c + Vector2(0, -3), 16.0 + level * 8.0, 0, TAU, 28, Color(col.r, col.g, col.b, 0.35 + level * 0.45), 2.5, true)
		draw_circle(c + Vector2(0, -10), 6.5, col)
		draw_rect(Rect2(c + Vector2(-6.5, -10), Vector2(13.0, 10.0)), col)
		draw_circle(c + Vector2(0, 0), 6.5, col)
		draw_arc(c + Vector2(0, -1), 11.5, 0.15, PI - 0.15, 18, col, 2.5, true)
		draw_line(c + Vector2(0, 10.5), c + Vector2(0, 16.0), col, 2.5, true)
		draw_line(c + Vector2(-7.0, 16.0), c + Vector2(7.0, 16.0), col, 2.5, true)
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


func _build_market_hud(layer: CanvasLayer, theme: Theme) -> void:
	# Üst orta: Gün saati ve ilerleme çubuğu
	day_hud = PanelContainer.new()
	day_hud.theme = theme
	var dbox := _sb(Color(0.08, 0.05, 0.04, 0.84), 14, 10)
	dbox.set_border_width_all(2)
	dbox.border_color = Color(GOLD, 0.65)
	day_hud.add_theme_stylebox_override("panel", dbox)
	day_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	day_hud.offset_left = -175; day_hud.offset_right = 175
	day_hud.offset_top = 16; day_hud.offset_bottom = 74
	day_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(day_hud)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 5)
	day_hud.add_child(dv)
	day_lbl = _lbl(dv, "GÜN 1  •  ☀️ 08:00  •  SABAH", 17, 1.0)
	day_lbl.add_theme_font_override("font", _font(800))
	day_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(310, 7)
	bar_bg.color = Color(0.22, 0.16, 0.12, 0.92)
	dv.add_child(bar_bg)
	day_bar = ColorRect.new()
	day_bar.color = GOLD
	day_bar.size = Vector2(0, 7)
	bar_bg.add_child(day_bar)
	day_hud.hide()

	# Üst orta altı: Aktif Pazar Olayı / Rush Hour şeridi
	event_banner = PanelContainer.new()
	event_banner.theme = theme
	var ebox := _sb(Color(0.56, 0.18, 0.08, 0.92), 12, 8)
	ebox.set_border_width_all(2)
	ebox.border_color = Color(1.0, 0.84, 0.3)
	event_banner.add_theme_stylebox_override("panel", ebox)
	event_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_banner.offset_left = -255; event_banner.offset_right = 255
	event_banner.offset_top = 80; event_banner.offset_bottom = 116
	event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(event_banner)
	event_lbl = _lbl(event_banner, "", 15, 1.0)
	event_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	event_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_banner.hide()

	# Sol üst: Bildirim akışı (Toast)
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_box.offset_left = 20; toast_box.offset_right = 430
	toast_box.offset_top = 20; toast_box.offset_bottom = 260
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_box)

	# Sağ üst: Cüzdan
	money_hud = PanelContainer.new()
	money_hud.theme = theme
	var box := _sb(Color(0.08, 0.05, 0.04, 0.85), 14, 12)
	box.set_border_width_all(2)
	box.border_color = Color(GOLD, 0.7)
	money_hud.add_theme_stylebox_override("panel", box)
	money_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_hud.offset_left = -220; money_hud.offset_right = -20
	money_hud.offset_top = 18; money_hud.offset_bottom = 72
	money_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(money_hud)
	money_lbl = _lbl(money_hud, "120 TL", 26, 1.0)
	money_lbl.add_theme_font_override("font", _font(900))
	money_lbl.add_theme_color_override("font_color", GOLD)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_hud.hide()

	money_pop = _lbl(layer, "", 24, 1.0)
	money_pop.add_theme_font_override("font", _font(900))
	money_pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	money_pop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_pop.offset_left = -260; money_pop.offset_right = -24
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
	interact_lbl.offset_left = -360; interact_lbl.offset_right = 360
	interact_lbl.offset_top = 24; interact_lbl.offset_bottom = 60
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	interact_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_lbl.hide()


## Tezgah Geliştirmeleri (U veya tezgah panosu) modal ekranı.
func _build_upgrade_panel(layer: CanvasLayer, theme: Theme) -> void:
	upgrade_wrap = ColorRect.new()
	upgrade_wrap.color = Color(0, 0, 0, 0.58)
	upgrade_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_wrap.theme = theme
	layer.add_child(upgrade_wrap)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_wrap.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 580
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_logo(v, "TEZGAH GELİŞTİRMELERİ", 34).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_wallet_lbl = _lbl(v, "Cüzdan: 120 TL", 18, 1.0)
	upgrade_wallet_lbl.add_theme_color_override("font_color", GOLD)
	upgrade_wallet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for key in StallScript.UPGRADE_ORDER:
		var info_u: Dictionary = StallScript.UPGRADES[key]
		var row_p := PanelContainer.new()
		var rsb := _sb(Color(0.14, 0.09, 0.07, 0.95), 10, 12)
		rsb.set_border_width_all(1)
		rsb.border_color = Color(GOLD, 0.3)
		row_p.add_theme_stylebox_override("panel", rsb)
		v.add_child(row_p)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		row_p.add_child(hb)
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(tx)
		var nl := _lbl(tx, str(info_u["name"]), 19, 1.0)
		nl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
		var dl := _lbl(tx, str(info_u["desc"]), 14, 0.78)
		var btn := _btn(hb, "%d TL" % int(info_u["cost"]), _on_buy_upgrade.bind(key), 44)
		btn.custom_minimum_size.x = 128
		upgrade_rows[key] = [btn, dl]
	_btn(v, "Kapat  [U / ESC]", _close_upgrade_shop, 44)
	upgrade_wrap.hide()


## Tab ile açılan canlı Esnaf Skor Tablosu.
func _build_scoreboard(layer: CanvasLayer, theme: Theme) -> void:
	scoreboard_wrap = ColorRect.new()
	scoreboard_wrap.color = Color(0, 0, 0, 0.48)
	scoreboard_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	scoreboard_wrap.theme = theme
	scoreboard_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(scoreboard_wrap)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_wrap.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_logo(v, "PAZAR SKOR TABLOSU", 32).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scoreboard_list = VBoxContainer.new()
	scoreboard_list.add_theme_constant_override("separation", 6)
	v.add_child(scoreboard_list)
	scoreboard_wrap.hide()


## Gün sonu "Günün Esnafı" ödül ekranı.
func _build_summary(layer: CanvasLayer, theme: Theme) -> void:
	summary_wrap = ColorRect.new()
	summary_wrap.color = Color(0.03, 0.02, 0.02, 0.74)
	summary_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_wrap.theme = theme
	layer.add_child(summary_wrap)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_wrap.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 660
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	summary_title = _logo(v, "🏆 GÜN 1 SONU — GÜNÜN ESNAFI", 34)
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_list = VBoxContainer.new()
	summary_list.add_theme_constant_override("separation", 8)
	v.add_child(summary_list)
	next_day_btn = _btn(v, "▶  Yeni Günü Başlat", _on_next_day_pressed, 52)
	next_day_btn.add_theme_font_size_override("font_size", 22)
	_btn(v, "Lobiye Dön", Net.leave, 40)
	summary_wrap.hide()


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


func show_toast(msg: String, color := Color(1.0, 0.94, 0.78)) -> void:
	if toast_box == null:
		return
	while toast_box.get_child_count() >= 4:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	var sb := _sb(Color(0.08, 0.05, 0.04, 0.88), 10, 9)
	sb.border_width_left = 4
	sb.border_color = color
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _lbl(p, msg, 15, 1.0)
	l.add_theme_color_override("font_color", color)
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.22)
	tw.tween_interval(4.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _on_money_earned(amount: int, total: int, tip: int) -> void:
	money_lbl.text = "%d TL" % total
	money_pop.text = ("+%d TL (⭐+%d)" % [amount, tip]) if tip > 0 else ("+%d TL" % amount)
	money_pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	_animate_money_pop()
	_refresh_upgrade_panel()


func _on_money_spent(amount: int, total: int, reason: String) -> void:
	money_lbl.text = "%d TL" % total
	if amount > 0:
		money_pop.text = "-%d TL" % amount
		money_pop.add_theme_color_override("font_color", Color(1.0, 0.38, 0.34))
		_animate_money_pop()
	if "Ceza" in reason:
		show_toast("🚨 " + reason + " (-%d TL)" % amount, Color(1.0, 0.38, 0.34))
	_refresh_upgrade_panel()


func _animate_money_pop() -> void:
	money_pop.modulate.a = 1.0
	money_pop.offset_top = 82
	money_pop.show()
	var tw := create_tween().set_parallel()
	tw.tween_property(money_pop, "offset_top", 56.0, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(money_pop, "modulate:a", 0.0, 0.95).set_delay(0.25)
	tw.chain().tween_callback(money_pop.hide)


func _toggle_upgrade_shop() -> void:
	if world == null or day_ended or pause_wrap.visible:
		return
	if upgrade_wrap.visible:
		_close_upgrade_shop()
	else:
		_refresh_upgrade_panel()
		upgrade_wrap.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_upgrade_shop() -> void:
	upgrade_wrap.hide()
	if world and not pause_wrap.visible and not day_ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_upgrade_panel() -> void:
	if players == null or stalls == null:
		return
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	var st := stalls.get_node_or_null("Stall_%d" % my_id)
	if me == null or st == null:
		return
	upgrade_wallet_lbl.text = "Cüzdanın: %d TL" % int(me.money)
	for key in upgrade_rows:
		var btn: Button = upgrade_rows[key][0]
		var cost: int = int(StallScript.UPGRADES[key]["cost"])
		if st.has_upgrade(key):
			btn.text = "✔ ALINDI"
			btn.disabled = true
		else:
			btn.text = "%d TL" % cost
			btn.disabled = int(me.money) < cost


func _on_buy_upgrade(key: String) -> void:
	if Net.online():
		rpc_request_buy_upgrade.rpc_id(1, key)
	else:
		rpc_request_buy_upgrade(key)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_buy_upgrade(key: String) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if not StallScript.UPGRADES.has(key) or players == null or stalls == null:
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	var st := stalls.get_node_or_null("Stall_%d" % pid)
	if p == null or st == null or st.has_upgrade(key):
		return
	var cost: int = int(StallScript.UPGRADES[key]["cost"])
	if int(p.money) < cost:
		_notify_peer(pid, "Yetersiz bakiye! (%d TL gerekli)" % cost, Color(1.0, 0.45, 0.4))
		return
	p.spend_money(cost, str(StallScript.UPGRADES[key]["name"]))
	st.apply_upgrade_synced(key)
	_broadcast_toast("⭐ %s tezgahına %s ekledi!" % [Net.display_name(pid), str(StallScript.UPGRADES[key]["name"])], Color(0.58, 1.0, 0.65))


func _refresh_scoreboard_rows(target_box: VBoxContainer, show_crown: bool) -> void:
	for c in target_box.get_children():
		c.queue_free()
	if players == null:
		return
	var rows := []
	for p in players.get_children():
		var pid := p.name.to_int()
		rows.append({
			"id": pid,
			"name": Net.display_name(pid),
			"money": int(p.money),
			"profit": int(p.net_profit()),
			"sold": int(p.daily_sold),
			"tips": int(p.daily_tips),
			"fines": int(p.daily_fines),
		})
	rows.sort_custom(func(a, b): return a["profit"] > b["profit"] if a["profit"] != b["profit"] else a["money"] > b["money"])
	var hdr := _lbl(target_box, "ESNAF                 | CÜZDAN  | NET KÂR | SATIŞ | BAHŞİŞ | CEZA", 14, 0.68)
	hdr.autowrap_mode = TextServer.AUTOWRAP_OFF
	for i in rows.size():
		var r: Dictionary = rows[i]
		var medal := ("👑 " if show_crown else "#1 ") if i == 0 else ("#%d " % (i + 1))
		var line := "%s%-16s | %4d TL | %+5d TL |  %3d  | %3d TL | %3d TL" % [
			medal, str(r["name"]).left(16), r["money"], r["profit"], r["sold"], r["tips"], r["fines"]
		]
		var lbl := _lbl(target_box, line, 17 if i == 0 else 15, 1.0)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.add_theme_color_override("font_color", GOLD if i == 0 else Color(0.95, 0.92, 0.86))


func _on_volume(x: float) -> void:
	Settings.volume = x
	Settings.apply_audio()
	vol_lbl.text = "Ses: %d%%" % roundi(x * 100)


func _open_pause() -> void:
	upgrade_wrap.hide()
	ingame_box.visible = world != null
	pause_wrap.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause() -> void:
	pause_wrap.hide()
	Settings.save()
	if world and not day_ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _show_page(n: String) -> void:
	page = n
	for k in pages:
		pages[k].visible = k == n
	var col: Control = pages[n].get_child(0)
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
	if players:
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
	var bz := BazaarScript.new()
	menu_bg.add_child(bz)
	bz.set_day_progress(0.42) # menüde canlı güneşli Akdeniz öğleden sonrası
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
		walkers.append([p, randf_range(3.8, 5.6), randf() * TAU, randf_range(0.6, 0.85) * (1 if i % 2 == 0 else -1)])


func _menu_anim(dt: float) -> void:
	menu_t += dt
	var a := menu_t * 0.05
	menu_cam.position = Vector3(sin(a) * 15.0, 5.5 + sin(menu_t * 0.2) * 0.5, cos(a) * 15.0)
	menu_cam.look_at(Vector3(sin(a + 0.6) * 2.0, 1.2, cos(a + 0.6) * 2.0))
	for w in walkers:
		var p: Node3D = w[0]
		w[2] += w[3] * dt * 4.2 / w[1]
		p.position = Vector3(cos(w[2]) * w[1], 0, sin(w[2]) * w[1])
		var tangent := Vector3(-sin(w[2]), 0, cos(w[2])) * signf(w[3])
		p.body_yaw = atan2(tangent.x, tangent.z)
		p.look_yaw = p.body_yaw + sin(menu_t * 0.7 + w[1]) * 0.5 - PI
		p.spd = 4.2 * absf(w[3])


func _process(dt: float) -> void:
	if menu_bg:
		_menu_anim(dt)
	if world and players:
		_update_hud_frame(dt)
		var is_host := (not Net.online()) or multiplayer.is_server()
		if is_host and not day_ended:
			_tick_day_and_events(dt)
			if customers:
				_tick_customers(dt)
		elif bazaar_node:
			bazaar_node.set_day_progress(clampf(day_time / DAY_DURATION, 0.0, 1.0))


func _update_hud_frame(dt: float) -> void:
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	if me and voice_hud.visible:
		var lvl: float = me.talk_smooth
		var muted: bool = me.mic_muted
		voice_icon.level = lvl
		voice_icon.muted = muted
		voice_icon.queue_redraw()
		voice_bar.size.x = 0.0 if muted else 52.0 * lvl
		voice_bar.color = Color(0.95, 0.3, 0.25) if muted else (Color(1.0, 0.72, 0.2) if lvl > 0.7 else Color(0.4, 0.95, 0.5))
		voice_lbl.text = "M: KAPALI" if muted else ("BAĞIRIYOR!" if me.shout_power > 0.55 else ("KONUŞUYOR" if lvl > 0.06 else "M: AÇIK"))
		var hide_interact := pause_wrap.visible or upgrade_wrap.visible or day_ended
		interact_lbl.text = me.interact_hint
		interact_lbl.visible = me.interact_hint != "" and not hide_interact
		# Nişangah dinamik vurgu
		if me.has_target and not hide_interact:
			crosshair.color = Color(1.0, 0.85, 0.25, 0.98)
			crosshair.offset_left = -4; crosshair.offset_right = 4
			crosshair.offset_top = -4; crosshair.offset_bottom = 4
		else:
			crosshair.color = Color(1.0, 0.96, 0.88, 0.82)
			crosshair.offset_left = -3; crosshair.offset_right = 3
			crosshair.offset_top = -3; crosshair.offset_bottom = 3

	# Gün saati HUD'u (08:00 -> 21:30 = 810 dakika)
	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	var mins := int(480.0 + prog * 810.0)
	var hh := int(mins / 60)
	var mm := int(mins % 60)
	var phase_txt := "☀️ SABAH" if prog < 0.30 else ("🌤️ ÖĞLE" if prog < 0.62 else ("🌅 İKİNDİ" if prog < 0.80 else "🌙 AKŞAM PAZARI"))
	day_lbl.text = "GÜN %d  •  %02d:%02d  •  %s" % [day_num, hh, mm, phase_txt]
	day_bar.size.x = 310.0 * prog
	day_bar.color = Color(1.0, 0.78, 0.32) if prog < 0.72 else Color(1.0, 0.45, 0.22)

	# Aktif olay şeridi
	if active_event_item != "" and event_timer > 0.0:
		event_banner.show()
		event_lbl.text = "%s  (%d sn)" % [active_event_title, ceili(event_timer)]
	elif prog >= 0.72 and not day_ended:
		event_banner.show()
		event_lbl.text = "🌆 AKŞAM PAZARI AKINI! Müşteri yoğunluğu zirvede!"
	else:
		event_banner.hide()

	# Tab skor tablosu
	var show_sb := Input.is_action_pressed("scoreboard") and not pause_wrap.visible and not upgrade_wrap.visible and not day_ended
	scoreboard_wrap.visible = show_sb
	if show_sb:
		_refresh_scoreboard_rows(scoreboard_list, false)

	# Fiyat renkleri + arka depo acil veresiye etiketlerini saniyede 1 güncelle
	_price_ui_cd -= dt
	if _price_ui_cd <= 0.0:
		_price_ui_cd = 1.0
		_refresh_stall_visual_prices()


func _refresh_stall_visual_prices() -> void:
	if stalls == null or players == null:
		return
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	for st in stalls.get_children():
		st.refresh_all_price_colors()
		var p := players.get_node_or_null(str(st.owner_id))
		var emerg := _is_emergency_credit(st.owner_id) if p else false
		st.update_crate_prices(wholesale_prices, emerg and st.owner_id == my_id)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		if upgrade_wrap.visible:
			_close_upgrade_shop()
		elif pause_wrap.visible:
			_close_pause()
		elif world and not day_ended:
			_open_pause()
		elif page == "lobby":
			_show_page("main")
		return
	if world and not pause_wrap.visible and not upgrade_wrap.visible and not day_ended and e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- Ekonomi & Gün Döngüsü ----------

func _roll_wholesale_prices() -> void:
	wholesale_prices.clear()
	for item_id in Produce.ITEM_ORDER:
		var base_c: float = float(Produce.ITEMS[item_id]["crate_cost"])
		wholesale_prices[item_id] = maxi(20, roundi(base_c * randf_range(0.84, 1.16)))
	deal_item = Produce.ITEM_ORDER.pick_random()
	# Toptancı fırsat ürünü ek %28 ucuz
	wholesale_prices[deal_item] = maxi(18, roundi(float(Produce.ITEMS[deal_item]["crate_cost"]) * 0.72))
	_sync_economy_state()


func _sync_economy_state() -> void:
	if Net.online():
		rpc_sync_economy.rpc(wholesale_prices, deal_item, active_event_item, active_event_title, event_timer)
	else:
		rpc_sync_economy(wholesale_prices, deal_item, active_event_item, active_event_title, event_timer)


@rpc("authority", "call_local", "reliable")
func rpc_sync_economy(prices: Dictionary, deal: String, ev_item: String, ev_title: String, ev_t: float) -> void:
	wholesale_prices = prices.duplicate()
	deal_item = deal
	active_event_item = ev_item
	active_event_title = ev_title
	event_timer = ev_t
	if world:
		world.set_meta("event_item", ev_item)
	if bazaar_node:
		bazaar_node.update_wholesale_board(wholesale_prices, deal_item, active_event_item)
	_refresh_stall_visual_prices()


func _is_emergency_credit(peer_id: int) -> bool:
	if players == null or stalls == null:
		return false
	var p := players.get_node_or_null(str(peer_id))
	var st := stalls.get_node_or_null("Stall_%d" % peer_id)
	if p == null or st == null:
		return false
	var min_cost := int(wholesale_prices.get("sogan", Produce.ITEMS["sogan"]["crate_cost"]))
	return int(p.money) < min_cost and st.total_stock() == 0 and not bool(p.held_crate)


## Kasa maliyetini hesaplar (Toptancı Kamyonu temel ürünlerde %12 daha ucuz + fırsat ürünü indirimi).
func get_crate_cost(peer_id: int, item_id: String, from_truck: bool) -> int:
	if not Produce.ITEMS.has(item_id):
		return 50
	if not from_truck and item_id == "sogan" and _is_emergency_credit(peer_id):
		return 0
	var base := int(wholesale_prices.get(item_id, Produce.ITEMS[item_id]["crate_cost"]))
	if from_truck and item_id != deal_item:
		return maxi(18, roundi(float(base) * 0.88))
	return base


func request_buy_crate(item_id: String, from_truck: bool) -> void:
	if Net.online():
		rpc_request_buy_crate.rpc_id(1, item_id, from_truck)
	else:
		rpc_request_buy_crate(item_id, from_truck)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_buy_crate(item_id: String, from_truck: bool) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if not Produce.ITEMS.has(item_id) or players == null or stalls == null or day_ended:
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	var st := stalls.get_node_or_null("Stall_%d" % pid)
	if p == null or st == null or bool(p.held_crate):
		return
	var cost := get_crate_cost(pid, item_id, from_truck)
	if int(p.money) < cost:
		_notify_peer(pid, "Yetersiz bakiye! %s kasası %d TL." % [Produce.ITEMS[item_id]["name"], cost], Color(1.0, 0.45, 0.38))
		return
	if cost > 0:
		p.spend_money(cost, Produce.ITEMS[item_id]["name"] + " Kasası")
	else:
		_notify_peer(pid, "🤝 Acil Veresiye Soğan Kasası verildi!", Color(0.55, 1.0, 0.6))
	p.give_crate_synced(item_id, st.crate_capacity())


func _tick_day_and_events(dt: float) -> void:
	day_time += dt
	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	if bazaar_node:
		bazaar_node.set_day_progress(prog)

	# Akşam Pazarı Rush Hour duyurusu
	if prog >= 0.72 and not rush_announced:
		rush_announced = true
		Sfx.play("event", -3.0)
		_broadcast_toast("🌆 AKŞAM PAZARI BAŞLADI! Müşteriler akın ediyor!", Color(1.0, 0.68, 0.3))

	# Rastgele Pazar Olayı (kıtlık / talep patlaması)
	if event_timer > 0.0:
		event_timer -= dt
		if event_timer <= 0.0:
			active_event_item = ""
			active_event_title = ""
			_sync_economy_state()
			_broadcast_toast("Pazar normale döndü.", Color(0.88, 0.86, 0.78))
	else:
		next_event_cd -= dt
		if next_event_cd <= 0.0 and prog < 0.88:
			next_event_cd = randf_range(58.0, 82.0)
			var ev: Dictionary = MARKET_EVENTS.pick_random()
			active_event_item = str(ev["item"])
			active_event_title = str(ev["title"])
			event_timer = 44.0
			_sync_economy_state()
			_broadcast_event_sfx("event")
			_broadcast_toast(active_event_title, Color(1.0, 0.84, 0.28))

	# Periyodik Toptancı fiyat dalgalanması
	next_price_shift_cd -= dt
	if next_price_shift_cd <= 0.0:
		next_price_shift_cd = 78.0
		_roll_wholesale_prices()
		_broadcast_toast("🚚 Toptancı Halinde yeni fırsat: %s (%d TL)!" % [
			Produce.ITEMS[deal_item]["name"], int(wholesale_prices[deal_item])
		], Color(0.52, 1.0, 0.6))

	# Zabıta devriyesi
	next_zabita_cd -= dt
	if next_zabita_cd <= 0.0 and prog < 0.90 and world and not world.has_node("Zabita"):
		next_zabita_cd = randf_range(68.0, 92.0)
		var from_n := randf() < 0.5
		if Net.online():
			rpc_spawn_zabita.rpc(from_n)
		else:
			rpc_spawn_zabita(from_n)
		_broadcast_toast("🚨 ZABITA DENETİME ÇIKTI! Fahiş fiyat & yerdeki kasalara dikkat!", Color(0.58, 0.84, 1.0))

	# İstemcilere gün saatini senkronize et
	_day_sync_t += dt
	if Net.online() and _day_sync_t >= 0.5:
		_day_sync_t = 0.0
		rpc_sync_day_time.rpc(day_num, day_time, event_timer)

	# Gün sonu!
	if day_time >= DAY_DURATION:
		day_ended = true
		if Net.online():
			rpc_day_ended.rpc(day_num)
		else:
			rpc_day_ended(day_num)


@rpc("authority", "unreliable_ordered")
func rpc_sync_day_time(d_num: int, d_time: float, ev_t: float) -> void:
	day_num = d_num
	day_time = d_time
	event_timer = ev_t
	if bazaar_node:
		bazaar_node.set_day_progress(clampf(day_time / DAY_DURATION, 0.0, 1.0))


@rpc("authority", "call_local", "reliable")
func rpc_spawn_zabita(from_north: bool) -> void:
	if world == null or world.has_node("Zabita"):
		return
	var z := InspectorScript.new()
	z.init_inspector(from_north)
	world.add_child(z)


@rpc("authority", "call_local", "reliable")
func rpc_day_ended(finished_day: int) -> void:
	day_ended = true
	day_num = finished_day
	upgrade_wrap.hide()
	scoreboard_wrap.hide()
	pause_wrap.hide()
	Sfx.play("day_end", -2.0)
	summary_title.text = "🏆 GÜN %d SONU — GÜNÜN ESNAFI" % day_num
	_refresh_scoreboard_rows(summary_list, true)
	var can_start := (not Net.online()) or multiplayer.is_server()
	next_day_btn.disabled = not can_start
	next_day_btn.text = ("▶  Gün %d'yi Başlat" % (day_num + 1)) if can_start else "Host yeni günü başlatacak..."
	summary_wrap.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_next_day_pressed() -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if Net.online():
		rpc_start_next_day.rpc(day_num + 1)
	else:
		rpc_start_next_day(day_num + 1)


@rpc("authority", "call_local", "reliable")
func rpc_start_next_day(new_day: int) -> void:
	day_num = new_day
	day_time = 0.0
	day_ended = false
	rush_announced = false
	active_event_item = ""
	active_event_title = ""
	event_timer = 0.0
	next_event_cd = 36.0
	next_zabita_cd = 58.0
	next_price_shift_cd = 75.0
	summary_wrap.hide()
	if customers:
		for c in customers.get_children():
			c.queue_free()
	if world and world.has_node("Zabita"):
		world.get_node("Zabita").queue_free()
	if (not Net.online()) or multiplayer.is_server():
		if players:
			for p in players.get_children():
				p.reset_daily_stats_synced()
		_roll_wholesale_prices()
	if bazaar_node:
		bazaar_node.set_day_progress(0.0)
	Sfx.play("event", -4.0)
	show_toast("☀️ GÜN %d BAŞLADI! Bol kazançlar!" % day_num, GOLD)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _notify_peer(peer_id: int, msg: String, col: Color) -> void:
	if Net.online() and peer_id != 1:
		rpc_toast.rpc_id(peer_id, msg, col)
	else:
		show_toast(msg, col)


func _broadcast_toast(msg: String, col: Color) -> void:
	if Net.online():
		rpc_toast.rpc(msg, col)
	else:
		show_toast(msg, col)


@rpc("authority", "call_local", "reliable")
func rpc_toast(msg: String, col: Color) -> void:
	show_toast(msg, col)


func _broadcast_event_sfx(clip: String) -> void:
	if Net.online():
		rpc_play_sfx.rpc(clip)
	else:
		Sfx.play(clip, -3.0)


@rpc("authority", "call_local", "reliable")
func rpc_play_sfx(clip: String) -> void:
	Sfx.play(clip, -3.0)


# ---------- Oyun akışı ve Multiplayer Senkronu ----------

func _player_ids() -> Array:
	var ids := [1]
	ids.append_array(Array(multiplayer.get_peers()))
	ids.sort()
	return ids


func _alloc_spot(peer_id: int) -> int:
	if _stall_spots.has(peer_id):
		return int(_stall_spots[peer_id])
	var used := _stall_spots.values()
	for i in BazaarScript.PLAYER_STALL_SPOTS.size():
		if not (i in used):
			_stall_spots[peer_id] = i
			return i
	var fallback := peer_id % BazaarScript.PLAYER_STALL_SPOTS.size()
	_stall_spots[peer_id] = fallback
	return fallback


func _on_start() -> void:
	if multiplayer.is_server():
		_stall_spots.clear()
		var ids := _player_ids()
		var spot_map := {}
		for id in ids:
			spot_map[id] = _alloc_spot(id)
		start_game.rpc(ids, spot_map, {})


@rpc("authority", "call_local", "reliable")
func start_game(ids: Array, spot_map := {}, snapshot := {}) -> void:
	_clear_world()
	_set_menu_bg(false)
	world = Node3D.new()
	world.name = "World"
	world.set_meta("event_item", "")
	add_child(world)
	bazaar_node = BazaarScript.new()
	bazaar_node.interactive = true
	world.add_child(bazaar_node)
	stalls = Node3D.new()
	stalls.name = "Stalls"
	world.add_child(stalls)
	customers = Node3D.new()
	customers.name = "Customers"
	world.add_child(customers)
	players = Node3D.new()
	players.name = "Players"
	world.add_child(players)

	_stall_spots.clear()
	_cust_seq = 0
	_cust_cd = 1.5
	day_num = 1
	day_time = 0.0
	day_ended = false
	rush_announced = false
	active_event_item = ""
	active_event_title = ""
	event_timer = 0.0
	next_event_cd = 38.0
	next_zabita_cd = 62.0
	next_price_shift_cd = 75.0

	for id in ids:
		var sp := int(spot_map.get(id, _alloc_spot(id)))
		_spawn(id, sp)

	if not snapshot.is_empty():
		_apply_world_snapshot(snapshot)
	elif (not Net.online()) or multiplayer.is_server():
		_roll_wholesale_prices()
	bazaar_node.set_day_progress(clampf(day_time / DAY_DURATION, 0.0, 1.0))

	ui.hide()
	summary_wrap.hide()
	upgrade_wrap.hide()
	scoreboard_wrap.hide()
	hint.show()
	voice_hud.show()
	day_hud.show()
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	money_lbl.text = "%d TL" % (int(me.money) if me else PlayerScript.STARTING_MONEY)
	money_hud.show()
	crosshair.show()
	Sfx.set_ambience(true)
	show_toast("☀️ Pazara hoş geldin! Arka depodan veya Batıdaki Toptancı Kamyonundan kasa al!", GOLD)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn(id: int, spot_idx := -1) -> void:
	if players == null or players.has_node(str(id)):
		return
	var idx := spot_idx if spot_idx >= 0 else _alloc_spot(id)
	_stall_spots[id] = idx
	var spot: Array = BazaarScript.PLAYER_STALL_SPOTS[idx % BazaarScript.PLAYER_STALL_SPOTS.size()]
	var st := StallScript.new()
	st.setup(id, Net.display_name(id), id, idx)
	st.position = spot[0]
	st.rotation.y = spot[1]
	stalls.add_child(st)

	var p: CharacterBody3D = PlayerScript.new()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.spawn_pos = st.owner_spawn_pos()
	p.look_yaw = spot[1] + PI
	players.add_child(p)
	if p.is_multiplayer_authority():
		p.money_earned.connect(_on_money_earned)
		p.money_spent.connect(_on_money_spent)
		p.open_upgrade_shop.connect(_toggle_upgrade_shop)


func _tick_customers(dt: float) -> void:
	_cust_cd -= dt
	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	var rush := prog >= 0.72
	var max_cust := 11 if rush else 8
	if _cust_cd > 0.0 or customers.get_child_count() >= max_cust:
		return
	_cust_cd = randf_range(1.5, 2.5) if rush else randf_range(2.8, 4.6)
	_cust_seq += 1
	var from_north := randf() < 0.5
	var x_lane := randf_range(-2.5, 2.5)
	var start_p := Vector3(x_lane, 0.0, -19.5 if from_north else 19.5)
	var exit_p := Vector3(randf_range(-2.4, 2.4), 0.0, 19.5 if from_north else -19.5)

	# Müşteri tipi seçimi
	var r := randf()
	var arch: int = CustomerScript.Archetype.NORMAL
	if r < 0.14 + (0.06 if rush else 0.0):
		arch = CustomerScript.Archetype.VIP
	elif r < 0.34:
		arch = CustomerScript.Archetype.BARGAINER
	elif r < 0.52:
		arch = CustomerScript.Archetype.IMPATIENT

	# Talep havuzu: temel 4 ürün + herhangi bir tezgahta stoklu egzotik ürünler + aktif olay ürünü
	var item_pool := Produce.BASIC_ORDER.duplicate()
	if stalls:
		for ex in Produce.EXOTIC_ORDER:
			for st in stalls.get_children():
				if st.has_item(ex) and not (ex in item_pool):
					item_pool.append(ex)
					break
	if arch == CustomerScript.Archetype.VIP:
		for ex in Produce.EXOTIC_ORDER:
			if not (ex in item_pool):
				item_pool.append(ex)
	if active_event_item != "" and not (active_event_item in item_pool):
		item_pool.append(active_event_item)
	item_pool.shuffle()

	var n_types := 1 if randf() < 0.42 else (2 if randf() < 0.8 else 3)
	if arch == CustomerScript.Archetype.VIP or arch == CustomerScript.Archetype.BARGAINER:
		n_types = mini(maxi(n_types, 2), item_pool.size())
	var wants := {}
	if active_event_item != "" and randf() < 0.65:
		wants[active_event_item] = randi_range(1, 2)
	for i in mini(n_types, item_pool.size()):
		if not wants.has(item_pool[i]):
			wants[item_pool[i]] = randi_range(1, 2)
	var cname := "Cust_%d" % _cust_seq
	var seed_val := randi_range(1, 9999)
	if Net.online():
		rpc_spawn_customer.rpc(cname, seed_val, start_p, exit_p, wants, arch)
	else:
		rpc_spawn_customer(cname, seed_val, start_p, exit_p, wants, arch)


@rpc("authority", "call_local", "reliable")
func rpc_spawn_customer(cname: String, seed_val: int, start_p: Vector3, exit_p: Vector3, wants: Dictionary, arch := 0) -> void:
	if customers == null or customers.has_node(cname):
		return
	var c := CustomerScript.new()
	c.init_customer(cname, seed_val, start_p, exit_p, wants, arch)
	customers.add_child(c)


## Geç katılan oyuncu için tam dünya fotoğrafı (tezgahlar, yükseltmeler, cüzdanlar, müşteriler, ekonomi, gün).
func _build_world_snapshot() -> Dictionary:
	var st_snaps := []
	if stalls:
		for st in stalls.get_children():
			st_snaps.append(st.export_snapshot())
	var pl_snaps := []
	if players:
		for p in players.get_children():
			pl_snaps.append(p.export_snapshot())
	var cu_snaps := []
	if customers:
		for c in customers.get_children():
			cu_snaps.append(c.export_snapshot())
	return {
		"day_num": day_num,
		"day_time": day_time,
		"day_ended": day_ended,
		"prices": wholesale_prices.duplicate(),
		"deal": deal_item,
		"event_item": active_event_item,
		"event_title": active_event_title,
		"event_timer": event_timer,
		"stalls": st_snaps,
		"players": pl_snaps,
		"customers": cu_snaps,
	}


func _apply_world_snapshot(snap: Dictionary) -> void:
	day_num = int(snap.get("day_num", 1))
	day_time = float(snap.get("day_time", 0.0))
	day_ended = bool(snap.get("day_ended", false))
	wholesale_prices = snap.get("prices", {}).duplicate()
	deal_item = str(snap.get("deal", "domates"))
	active_event_item = str(snap.get("event_item", ""))
	active_event_title = str(snap.get("event_title", ""))
	event_timer = float(snap.get("event_timer", 0.0))
	if world:
		world.set_meta("event_item", active_event_item)
	if bazaar_node:
		bazaar_node.update_wholesale_board(wholesale_prices, deal_item, active_event_item)
	for sd: Dictionary in snap.get("stalls", []):
		var st := stalls.get_node_or_null("Stall_%d" % int(sd.get("owner_id", -1)))
		if st:
			st.apply_snapshot(sd)
	for pd: Dictionary in snap.get("players", []):
		var p := players.get_node_or_null(str(int(pd.get("id", -1))))
		if p:
			p.apply_snapshot(pd)
	for cd: Dictionary in snap.get("customers", []):
		var cn := str(cd.get("name", ""))
		if cn != "" and not customers.has_node(cn):
			var c := CustomerScript.new()
			c.init_customer(cn, int(cd.get("seed", 1)), cd.get("pos", Vector3.ZERO),
				cd.get("exit", Vector3(0, 0, 20)), cd.get("wants", {}), int(cd.get("archetype", 0)))
			customers.add_child(c)
			c.apply_snapshot(cd)
	if day_ended:
		rpc_day_ended(day_num)


## Pazar açıkken gelen arkadaş: ona tam dünya durumunu gönder, herkese yeni oyuncuyu ve tezgahını ekle.
func _on_peer_joined(id: int) -> void:
	if not multiplayer.is_server() or world == null:
		return
	var w := world
	await get_tree().create_timer(0.5).timeout
	if world != w or not id in multiplayer.get_peers():
		return
	var new_spot := _alloc_spot(id)
	var ids := _player_ids()
	var spot_map := {}
	for pid in ids:
		spot_map[pid] = _alloc_spot(pid)
	var snap := _build_world_snapshot()
	start_game.rpc_id(id, ids, spot_map, snap)
	add_player.rpc(id, new_spot)


@rpc("authority", "call_local", "reliable")
func add_player(id: int, spot_idx := -1) -> void:
	_spawn(id, spot_idx)
	_refresh_stall_visual_prices()


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server() and world:
		rpc_remove_player.rpc(id)
	else:
		_remove_player_local(id)


@rpc("authority", "call_local", "reliable")
func rpc_remove_player(id: int) -> void:
	_remove_player_local(id)


func _remove_player_local(id: int) -> void:
	_stall_spots.erase(id)
	if players:
		var n := players.get_node_or_null(str(id))
		if n:
			players.remove_child(n)
			n.queue_free()
	if stalls:
		var st := stalls.get_node_or_null("Stall_%d" % id)
		if st:
			stalls.remove_child(st)
			st.queue_free()


func _clear_world() -> void:
	if world:
		remove_child(world)
		world.queue_free()
	world = null
	bazaar_node = null
	players = null
	stalls = null
	customers = null
	_stall_spots.clear()


func _back_to_menu() -> void:
	_clear_world()
	Sfx.set_ambience(false)
	pause_wrap.hide()
	upgrade_wrap.hide()
	scoreboard_wrap.hide()
	summary_wrap.hide()
	hint.hide()
	voice_hud.hide()
	day_hud.hide()
	event_banner.hide()
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
