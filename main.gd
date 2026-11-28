extends Node3D
## Menü (TEK OYNA solo + çoklu lobi), Pazar Günü, sürüşlü Ford Transit Toptancı, iki kapılı sakin NPC + kalabalık dalgaları,
## Arka sokaktaki dükkanlar (Tekel, Fırın, Kıraathane, Market, Nalbur, Telefoncu...; bkz. shops.gd), Envanter Hotbar (1-6) ve koşma hız çizgileri.

const PlayerScript := preload("res://player.gd")
const BazaarScript := preload("res://bazaar.gd")
const StallScript := preload("res://stall.gd")
const CustomerScript := preload("res://customer.gd")
const InspectorScript := preload("res://inspector.gd")
const WholesalerScript := preload("res://wholesaler.gd")
const Produce := preload("res://produce.gd")
const Items := preload("res://items.gd")
const Shops := preload("res://shops.gd")
const MenuUIScript := preload("res://menu_ui.gd")

const DAY_DURATION := 300.0
const GOLD := Color(1.0, 0.74, 0.3)
const INK := Color(0.09, 0.06, 0.05)
const CREAM := Color(1.0, 0.95, 0.84)
const GOOD := Color(0.5, 1.0, 0.6)
const BAD := Color(1.0, 0.42, 0.36)
const PANEL_BG := Color(0.08, 0.05, 0.04, 0.86)

const THIEF_PATH := "res://thief.gd"
const CAREER_PATH := "user://career.json"
const CAREER_VERSION := 1

## Hava durumu: ağırlık (host her gün zar atar) + HUD ikonu + müşteri akış çarpanı.
const WEATHER := {
	"clear": {"w": 55, "icon": "☀️", "name": "Güneşli", "rate": 1.0,
		"toast": "☀️ Pırıl pırıl bir pazar günü! Müşteri bol, kazanç bol!"},
	"cloudy": {"w": 25, "icon": "☁️", "name": "Bulutlu", "rate": 0.9,
		"toast": "☁️ Hava kapalı, pazar biraz sakin. Bağırmayı unutma!"},
	"rain": {"w": 20, "icon": "🌧️", "name": "Yağmurlu", "rate": 0.7,
		"toast": "🌧️ Yağmur bastı! Müşteri az ve aceleci — hızlı sat, tazeliği koru!"},
}

const MENU_TIPS := [
	"İpucu: Fiyatı adil fiyatın biraz altında tutarsan teyzeler sıraya girer.",
	"İpucu: Toptancı Ford Transit'ten alınan kasalar %22 daha ucuz!",
	"İpucu: Yağmurlu günlerde müşteri azdır ama acelecidir.",
	"İpucu: Kapkaççı görürsen ona bak ve [E] ile yakala: 30 TL ödül!",
	"İpucu: Bayatlayan ürünü 💦 Su Fısfısı ile tazele; Market'te satılıyor.",
	"İpucu: Arka sokaktaki dükkanların saatleri var: Fırın akşam kapanır, Tekel öğlen açılır.",
	"İpucu: Zabıta fahiş fiyata ve yerdeki kasalara ceza keser.",
	"İpucu: Müşteri çekmek için doğrudan mikrofona bağırabilirsin.",
]

const CONTROLS_TEXT := """WASD  yürü   •   Shift  koş   •   Boşluk  zıpla
Fare  bak   •   1–8  envanter   •   0  el boş
E  kasa al / sat / yakala / korna
Sol Tık  ürün diz (basılı tut) / eşya kullan
Q  kasayı fırlat   •   Tekerlek / Z-X  fiyat
B / Mikrofon  bağır   •   V  bas-konuş   •   R  pazarlığa "olmaz"
F  tezgah zili   •   T  çaycıyı çağır   •   Dükkan kapısına bak + E  alışveriş
Tab  skor tablosu   •   M  mikrofon aç/kapa
H  rehber adımını geç   •   ESC  menü"""

const MARKET_EVENTS := [
	{"item": "domates", "title": "🍅 DOMATES KITLIĞI! Talep & adil fiyat uçtu!"},
	{"item": "karpuz", "title": "🍉 SICAK BASTI! Karpuz Fırtınası başladı!"},
	{"item": "elma", "title": "🍏 ELMA ŞENLİĞİ! Herkes elma arıyor!"},
	{"item": "portakal", "title": "🍊 VİTAMİN GÜNLERİ! Portakala akın var!"},
	{"item": "muz", "title": "🍌 MUZ AKINI! Müşteriler muz için sıraya giriyor!"},
	{"item": "patlican", "title": "🍆 KÖZ PATLICAN GÜNÜ! Patlıcan revaçta!"},
	{"item": "sogan", "title": "🧅 SOĞAN KRİZİ! Soğan fiyatları fırladı!"},
]

var menu_ui: Node
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
var lid_top: ColorRect
var lid_bot: ColorRect
var money_pop: Label
var crosshair: Control
var interact_lbl: Label
var ingame_box: VBoxContainer

# HUD & Modallar
var speed_lines: Control
var hotbar_wrap: HBoxContainer
var hotbar_slots: Array = [] # [[PanelContainer, Label, Label, StyleBoxFlat], ...]
var item_hint_lbl: Label
var buff_box: HBoxContainer
var buff_pills: Dictionary = {} # "tea"/"simit"/"smoke" -> [PanelContainer, Label]
var day_hud: PanelContainer
var day_lbl: Label
var day_bar: ColorRect
var event_banner: PanelContainer
var event_lbl: Label
var truck_banner: PanelContainer
var truck_lbl: Label
var expand_row: Array = [] # [Button, Label]
var _toast_seen := {}
const EXPAND_COSTS := [150, 350]
var toast_box: VBoxContainer
var shop_wrap: ColorRect
var shop_wallet_lbl: Label
var shop_item_btns: Dictionary = {}
var upgrade_rows: Dictionary = {}
var shop_item_rows: Dictionary = {} # item_id -> satır paneli (dükkana göre gizlenir)
var shop_title_lbl: Label
var shop_left_col: Control
var shop_right_col: Control
var shop_empty_lbl: Label
var current_shop := ""
var shop_look_box: VBoxContainer
var scoreboard_wrap: ColorRect
var scoreboard_list: VBoxContainer
var summary_wrap: ColorRect
var summary_title: Label
var summary_list: VBoxContainer
var next_day_btn: Button

var world: Node3D
var bazaar_node: Node3D
var wholesaler_node: Node3D
var players: Node3D
var stalls: Node3D
var customers: Node3D
var _stall_spots := {}
var _cust_seq := 0
var _cust_cd := 2.2
var _crowd_timer := 0.0 # >0 iken kalabalık dalgası!
var _next_crowd_cd := 48.0
var _price_ui_cd := 0.0

# Gün ve ekonomi durumu
var day_num := 1
var day_time := 0.0
var day_ended := false
var wholesale_prices: Dictionary = {}
var deal_item := "domates"
var active_event_item := ""
var active_event_title := ""
var event_timer := 0.0
var next_event_cd := 40.0
var next_zabita_cd := 68.0
var rush_announced := false
var _day_sync_t := 0.0

var menu_bg: Node3D
var menu_cam: Camera3D
var walkers := []
var menu_t := 0.0

# v0.6: Hava, kapkaççı, zorluk
var weather := "clear"
var thieves: Node3D
var _thief_script: Script = null
var _thief_checked := false
var _thief_seq := 0
var _next_thief_cd := 150.0
var _thief_spawned_today := 0

var qstats := {} # yerel günlük sayaçlar
var _last_thief_look := -100.0

# v0.6: Kariyer (solo)
var career := {} # yüklü/aktif kariyer verisi (boş = kariyer yok / çoklu oyun)
var _career_active := false
var _pending_career := {}
var _new_records: Array = []

# v0.6: Rehber
var tut_step := -1 # -1 = kapalı
var _tut_prev_prices := {}
var _tut_prev_fresh := {}
var _tut_sold_base := 0
var _tut_cd := 0.0

# v0.6: HUD
var rep_lbl: Label
var _rep_shown := -1.0
var tut_panel: PanelContainer
var tut_title: Label
var tut_text: Label
var fade_rect: ColorRect
var solo_info: Label
var solo_continue_btn: Button
var solo_new_btn: Button
var _new_confirm := false
var tip_lbl: Label
var _tip_t := 0.0
var _tip_i := 0
var quality_chk: CheckButton
var tut_btn: Button
var _hint_cd := 0.0
var summary_side: VBoxContainer
var summary_panel: PanelContainer


func _ready() -> void:
	_setup_input()
	SteamMgr.cloud_restore_if_missing("career.json", CAREER_PATH)
	SteamMgr.cloud_restore_if_missing("gorunum.cfg", PlayerScript.LOOK_FILE)
	career = _load_career()
	_build_ui()
	Net.status.connect(func(m):
		if info: info.text = m)
	Net.lobby_changed.connect(_refresh)
	Net.left.connect(_back_to_menu)
	Net.invited.connect(_on_invited)
	Updater.status.connect(func(m):
		if info: info.text = m)
	multiplayer.peer_connected.connect(_on_peer_joined)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	Settings.quality_changed.connect(_apply_quality)
	Settings.graphics_changed.connect(_apply_graphics_settings)
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
		await get_tree().create_timer(1.2).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_menu.png")
		_start_solo()
		await get_tree().create_timer(1.2).timeout
		var st1 := stalls.get_node_or_null("Stall_1")
		if st1:
			st1.rpc_sync_slot(0, "domates", st1.max_slot_count(), 10)
			st1.rpc_sync_slot(1, "karpuz", 5, 26)
			st1.rpc_sync_slot(2, "muz", 2, 19, 0.22)
			st1.rpc_sync_slot(3, "patlican", 6, 17)
			st1.rpc_set_stall_radio(true, true)
		var me1 := players.get_node_or_null("1")
		if me1:
			me1.rpc_add_inventory_item("cay")
			me1.rpc_add_inventory_item("cay")
			if me1.inventory.filter(func(slot): return slot.get("id") == "cay").size() != 3:
				push_error("Two teas must occupy separate inventory slots")
				get_tree().quit(1)
				return
			me1.rpc_add_inventory_item("megafon")
			for second in 30:
				me1._spend_mega_battery()
			if me1.has_inventory_item("megafon") or me1.is_holding_item("megafon"):
				push_error("Depleted megaphone must be removed")
				get_tree().quit(1)
				return
			me1.rpc_add_inventory_item("megafon")
			if not me1.is_holding_item("megafon"):
				push_error("Megaphone must be available again after depletion")
				get_tree().quit(1)
				return
			me1.select_slot(0) # elinde yanan sigara!
		if wholesaler_node:
			wholesaler_node.position = Vector3(0.0, 0.0, WholesalerScript.PARK_Z)
			wholesaler_node.rpc_state_changed(WholesalerScript.State.PARKED, 48.0)
		# Teyze pop-up balonu + tezgah + Ford Transit görünümü
		rpc_spawn_customer("PreviewTeyze", 7, Vector3(-3.4, 0, -5.2), Vector3(0, 0, 20), {"domates": 2, "karpuz": 1}, CustomerScript.Archetype.BARGAINER)
		day_time = DAY_DURATION * 0.36
		if bazaar_node:
			bazaar_node.set_day_progress(0.36)
		await get_tree().create_timer(0.7).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_game.png")
		# Akşam Pazarı + Ford Transit "GARDAŞLAR SEBZE MEYVE" + Teyze görünümü
		day_time = DAY_DURATION * 0.80
		if bazaar_node:
			bazaar_node.set_day_progress(0.80)
		if me1:
			me1.global_position = Vector3(-3.2, 0.2, -5.5)
			me1.look_yaw = -2.55 # Ford Transit'e ve arka pankartına + sokağa bak!
			me1.look_pitch = -0.05
		await get_tree().create_timer(0.6).timeout
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/selftest_sunset.png")
		print("SELFTEST_OK stalls=", stalls.get_child_count() if stalls else 0, " customers=", customers.get_child_count() if customers else 0)
		rpc_start_next_day(day_num + 1)
		if st1.total_stock() != 0 or st1.has_radio:
			push_error("Day rollover left items on the stall")
			get_tree().quit(1)
			return
		print("DAY_ROLLOVER_OK")
		get_tree().quit()
		return
	if "--showcase" in args:
		var out_dir := OS.get_user_data_dir()
		await get_tree().create_timer(1.1).timeout
		# 1. Yeni Ana Menü + Profil Kartı + TR/EN
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_main_menu.png")
		# 2. 4 Sekmeli Çoklu Oyuncu / Açık Odalar + Oda Kodu
		_show_page("lobby")
		if menu_ui:
			menu_ui._select_lobby_subtab(1)
		await get_tree().create_timer(0.45).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_lobby_browser.png")
		# 3. 5 Sekmeli Detaylı Ayarlar — Görüntü & Grafik
		_show_page("main")
		if menu_ui:
			menu_ui.open_settings(0)
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_settings_display.png")
		# 4. Ayarlar — Ses, 5 Kanal & Mikrofon Testi
		if menu_ui:
			menu_ui._select_settings_tab(1)
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_settings_audio.png")
		# 5. Ayarlar — Kontroller, Tuş Atama & Gamepad
		if menu_ui:
			menu_ui._select_settings_tab(2)
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_settings_controls.png")
		# 6. Başarımlar Galerisi
		if menu_ui:
			menu_ui.close_settings()
			menu_ui.open_achievements()
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_achievements.png")
		if menu_ui:
			menu_ui.close_all_modals()
		# Oyun içi sahneler (Solo başlat)
		_start_solo()
		await get_tree().create_timer(1.1).timeout
		var st1 := stalls.get_node_or_null("Stall_1")
		if st1:
			st1.rpc_set_expansion(2)
			for uk in StallScript.UPGRADE_ORDER:
				st1.apply_upgrade_synced(uk)
			st1.rpc_sync_slot(0, "domates", 10, 12)
			st1.rpc_sync_slot(1, "karpuz", 6, 26)
			st1.rpc_sync_slot(2, "muz", 8, 19)
			st1.rpc_sync_slot(3, "cilek", 9, 22)
			st1.rpc_sync_slot(4, "portakal", 8, 14)
			st1.rpc_sync_slot(5, "salatalik", 8, 10)
			st1.rpc_sync_slot(6, "patlican", 8, 17)
			st1.rpc_sync_slot(7, "limon", 8, 15)
			st1.rpc_set_stall_radio(true, true)
		var me1 := players.get_node_or_null("1")
		day_time = DAY_DURATION * 0.40
		if bazaar_node:
			bazaar_node.set_day_progress(0.40)
			bazaar_node.set_weather("clear", true)
		# 7. Tam Geliştirilmiş Lv2 Tezgah (sıfır çakışma + PBR Megafon Hoparlör + Saksı/Zil/Terazi + Sarkan Brandalar)
		if me1:
			me1.select_slot(-1)
			me1.global_position = Vector3(-1.3, 0.05, -4.4)
			me1.look_yaw = 1.02
			me1.look_pitch = -0.05
		await get_tree().create_timer(2.3).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_stall_upgrades.png")
		# 8. Yeni Blender PBR Küba Purosu (1P)
		if me1:
			me1.global_position = Vector3(-2.6, 0.05, -7.0)
			me1.look_yaw = -0.35
			me1.look_pitch = -0.06
			me1.rpc_add_inventory_item("puro")
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_pbr_cigar.png")
		# 9. Yeni Blender PBR Türk Meyve Bıçağı (1P)
		if me1:
			me1.rpc_add_inventory_item("bicak")
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_pbr_knife.png")
		# 10. Yeni Blender PBR Beyzbol Sopası (1P)
		if me1:
			me1.rpc_add_inventory_item("sopa")
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_pbr_bat.png")
		# 11. Yağmurlu Akşam Pazarı — Opak SSR Su Birikintileri + Sokak & Tezgah Lambaları
		if me1:
			me1.select_slot(-1)
			me1.global_position = Vector3(-0.3, 0.05, -1.6)
			me1.look_yaw = 0.32
			me1.look_pitch = -0.22
		day_time = DAY_DURATION * 0.84
		if bazaar_node:
			bazaar_node.set_day_progress(0.84)
			bazaar_node.set_weather("rain", true)
		await get_tree().create_timer(0.75).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/v090_rain_ssr_evening.png")
		print("SHOWCASE_OK dir=", out_dir)
		get_tree().quit()
		return


func _setup_input() -> void:
	Settings.apply_keybinds()


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
	var p := _sb(Color(0.08, 0.05, 0.04, 0.92), 16, 20)
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
	t.set_font_size("font_size", "BigButton", 29)
	t.set_font("font", "BigButton", _font(900))
	t.set_constant("outline_size", "BigButton", 6)
	t.set_color("font_outline_color", "BigButton", Color(0, 0, 0, 0.6))
	# Kaydırıcı & onay kutusu: aynı sıcak pazar paleti
	var track := _sb(Color(0.22, 0.15, 0.11, 0.95), 4, 0)
	track.content_margin_top = 4; track.content_margin_bottom = 4
	var fill := _sb(Color(0.95, 0.62, 0.24), 4, 0)
	fill.content_margin_top = 4; fill.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	for k in ["normal", "hover", "pressed", "hover_pressed"]:
		t.set_stylebox(k, "CheckButton", _sb(Color(0, 0, 0, 0), 6, 6))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckButton", CREAM)
	t.set_color("font_hover_color", "CheckButton", Color.WHITE)
	t.set_color("font_pressed_color", "CheckButton", GOLD)
	t.set_color("font_color", "Label", CREAM)
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
	var b := _btn(parent, text, cb, 54)
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
	v.offset_left = 80; v.offset_right = 80 + 470
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	c.add_child(v)
	return v


## Koşarken ekran kenarlarında beliren dinamik hız çizgileri efekti.
class SpeedLines extends Control:
	var intensity := 0.0
	var _t := 0.0

	func _process(dt: float) -> void:
		if intensity > 0.01:
			_t += dt * 18.0
			queue_redraw()

	func _draw() -> void:
		if intensity <= 0.02:
			return
		var center := size * 0.5
		var max_r := center.length()
		var count := 28
		for i in count:
			var a := float(i) * TAU / float(count) + sin(_t + float(i) * 1.9) * 0.018
			var jitter := fmod(float(i) * 0.37 + _t * 0.45, 1.0)
			var r0 := max_r * lerpf(0.62, 0.80, jitter)
			var r1 := max_r * 1.08
			var dir := Vector2(cos(a), sin(a))
			var col := Color(1.0, 0.98, 0.92, intensity * lerpf(0.12, 0.34, 1.0 - jitter))
			draw_line(center + dir * r0, center + dir * r1, col, 1.8 + intensity * 1.4, true)


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


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var theme := _make_theme()

	# Koşma hız çizgileri (tüm HUD'un arkasında)
	speed_lines = SpeedLines.new()
	speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(speed_lines)

	# Bağlamsal kısa ipucu çizgisi
	hint = _lbl(layer, "", 12, 0.9)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 12; hint.offset_right = -12; hint.offset_top = -22; hint.offset_bottom = -4
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.add_theme_color_override("font_color", Color(1.0, 0.93, 0.8))
	hint.hide()

	_build_hotbar(layer, theme)
	_build_voice_hud(layer, theme)
	_build_market_hud(layer, theme)
	_build_meta_hud(layer, theme)
	_build_shop_panel(layer, theme)
	_build_scoreboard(layer, theme)
	_build_summary(layer, theme)

	# Yeni modüler Ana Menü, Açık Lobi Tarayıcısı, Pause Menüsü ve 5 Sekmeli Detaylı Ayarlar
	menu_ui = MenuUIScript.new()
	menu_ui.name = "MenuUI"
	add_child(menu_ui)
	menu_ui.setup(self, layer, theme)
	_sync_menu_refs()

	# Sahne geçişleri için tam ekran karartma (en üstte)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.05, 0.03, 0.02, 1.0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.modulate.a = 0.0
	layer.add_child(fade_rect)


func _sync_menu_refs() -> void:
	if menu_ui == null:
		return
	ui = menu_ui.menu_root
	pages = menu_ui.pages
	info = menu_ui.info_lbl
	invite_box = menu_ui.invite_box
	pause_wrap = menu_ui.pause_wrap
	solo_info = menu_ui.solo_info
	solo_continue_btn = menu_ui.solo_continue_btn
	solo_new_btn = menu_ui.solo_new_btn
	tip_lbl = menu_ui.tip_lbl
	crosshair = menu_ui.crosshair_ctrl


## Alt orta 8 yuvalı kişisel envanter çubuğu (1-8; meyve kasaları buraya alınmaz!).
func _build_hotbar(layer: CanvasLayer, theme: Theme) -> void:
	hotbar_wrap = HBoxContainer.new()
	hotbar_wrap.theme = theme
	hotbar_wrap.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_wrap.offset_left = -230; hotbar_wrap.offset_right = 230
	hotbar_wrap.offset_top = -82; hotbar_wrap.offset_bottom = -30
	hotbar_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	hotbar_wrap.add_theme_constant_override("separation", 4)
	hotbar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hotbar_wrap)
	hotbar_slots.clear()
	for i in PlayerScript.INV_SIZE:
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(50, 46)
		var sb := _sb(Color(0.08, 0.05, 0.04, 0.82), 8, 3)
		sb.set_border_width_all(2)
		sb.border_color = Color(GOLD, 0.32)
		p.add_theme_stylebox_override("panel", sb)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hotbar_wrap.add_child(p)
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 0)
		p.add_child(vb)
		var num := _lbl(vb, str(i + 1), 9, 0.65)
		var main_l := _lbl(vb, "—", 16, 0.95)
		main_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		hotbar_slots.append([p, num, main_l, sb])
	hotbar_wrap.hide()

	# Seçili eşyanın Sol / Sağ Tık aksiyon ipucu (hotbar'ın hemen üstünde)
	item_hint_lbl = _lbl(layer, "", 11, 0.95)
	item_hint_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	item_hint_lbl.offset_left = -240; item_hint_lbl.offset_right = 240
	item_hint_lbl.offset_top = -102; item_hint_lbl.offset_bottom = -86
	item_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	item_hint_lbl.add_theme_color_override("font_color", Color(1.0, 0.93, 0.68))
	item_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_hint_lbl.hide()

	# Aktif güçlendirme rozetleri (Çay, Simit, Keyif — sağ üstte para HUD'unun altında)
	buff_box = HBoxContainer.new()
	buff_box.theme = theme
	buff_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	buff_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	buff_box.offset_left = -400; buff_box.offset_right = -14
	buff_box.offset_top = 66; buff_box.offset_bottom = 90
	buff_box.alignment = BoxContainer.ALIGNMENT_END
	buff_box.add_theme_constant_override("separation", 6)
	buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(buff_box)
	buff_pills.clear()
	for spec: Array in [
		["tea", Color(0.95, 0.45, 0.22)],
		["simit", Color(1.0, 0.78, 0.28)],
		["smoke", Color(0.68, 0.84, 1.0)],
		["stink", Color(0.56, 0.90, 0.26)],
	]:
		var bp := PanelContainer.new()
		var bsb := _sb(Color(0.09, 0.06, 0.04, 0.86), 8, 3)
		bsb.set_border_width_all(2)
		bsb.border_color = Color(spec[1] as Color, 0.82)
		bp.add_theme_stylebox_override("panel", bsb)
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := _lbl(bp, "", 11, 1.0)
		bl.autowrap_mode = TextServer.AUTOWRAP_OFF
		bl.add_theme_color_override("font_color", Color(1.0, 0.96, 0.86))
		bp.hide()
		buff_box.add_child(bp)
		buff_pills[str(spec[0])] = [bp, bl]
	buff_box.hide()


func _refresh_hotbar() -> void:
	if players == null or hotbar_slots.is_empty():
		return
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	if me == null:
		return
	for i in hotbar_slots.size():
		var sl: Dictionary = me.inventory[i] if i < me.inventory.size() else {}
		var row: Array = hotbar_slots[i]
		var num_l: Label = row[1]
		var main_l: Label = row[2]
		var sb: StyleBoxFlat = row[3]
		var active: bool = (int(me.active_slot) == i and not bool(me.held_crate))
		sb.border_color = Color(1.0, 0.88, 0.25) if active else Color(GOLD, 0.28)
		sb.bg_color = Color(0.28, 0.16, 0.08, 0.94) if active else Color(0.08, 0.05, 0.04, 0.80)
		if sl.is_empty():
			num_l.text = str(i + 1)
			main_l.text = "—"
			main_l.modulate.a = 0.4
		else:
			var iid := str(sl.get("id", ""))
			var info_i: Dictionary = Items.CATALOG.get(iid, {"icon": "?", "short": iid, "consumable": false, "puffs_per_use": 1})
			var cnt := int(sl.get("uses", 1))
			var max_p := int(info_i.get("puffs_per_use", 1))
			var rem_p := maxi(max_p - int(sl.get("puffs", 0)), 1)
			var badge := ""
			if bool(info_i["consumable"]):
				if max_p > 1 and cnt == 1:
					badge = "%d/%d" % [rem_p, max_p]
				elif max_p > 1 and int(sl.get("puffs", 0)) > 0:
					badge = "x%d (%d)" % [cnt, rem_p]
				else:
					badge = "x%d" % cnt
			num_l.text = "%d  %s" % [i + 1, badge]
			main_l.text = str(info_i["icon"])
			main_l.modulate.a = 1.0


func _build_voice_hud(layer: CanvasLayer, theme: Theme) -> void:
	voice_hud = PanelContainer.new()
	voice_hud.theme = theme
	var box := _sb(Color(0.08, 0.05, 0.04, 0.82), 10, 5)
	box.set_border_width_all(2)
	box.border_color = Color(GOLD, 0.5)
	voice_hud.add_theme_stylebox_override("panel", box)
	voice_hud.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	voice_hud.offset_left = -60; voice_hud.offset_right = -14
	voice_hud.offset_top = -34; voice_hud.offset_bottom = 34
	voice_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(voice_hud)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 3)
	voice_hud.add_child(v)
	voice_icon = MicIcon.new()
	voice_icon.custom_minimum_size = Vector2(32, 28)
	v.add_child(voice_icon)
	var meter_bg := ColorRect.new()
	meter_bg.custom_minimum_size = Vector2(32, 5)
	meter_bg.color = Color(0.2, 0.15, 0.12, 0.9)
	v.add_child(meter_bg)
	voice_bar = ColorRect.new()
	voice_bar.color = Color(0.4, 0.95, 0.5)
	voice_bar.size = Vector2(0, 5)
	meter_bg.add_child(voice_bar)
	voice_lbl = _lbl(v, "🎤", 12, 0.85)
	voice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	voice_hud.hide()


func _build_market_hud(layer: CanvasLayer, theme: Theme) -> void:
	day_hud = PanelContainer.new()
	day_hud.theme = theme
	var dbox := _sb(Color(0.08, 0.05, 0.04, 0.84), 10, 5)
	dbox.set_border_width_all(2)
	dbox.border_color = Color(GOLD, 0.65)
	day_hud.add_theme_stylebox_override("panel", dbox)
	day_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	day_hud.offset_left = -130; day_hud.offset_right = 130
	day_hud.offset_top = 8; day_hud.offset_bottom = 44
	day_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(day_hud)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	day_hud.add_child(dv)
	day_lbl = _lbl(dv, "☀️ 1 • 08:00", 13, 1.0)
	day_lbl.add_theme_font_override("font", _font(800))
	day_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	day_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(240, 4)
	bar_bg.color = Color(0.22, 0.16, 0.12, 0.92)
	dv.add_child(bar_bg)
	day_bar = ColorRect.new()
	day_bar.color = GOLD
	day_bar.size = Vector2(0, 4)
	bar_bg.add_child(day_bar)
	day_hud.hide()

	event_banner = PanelContainer.new()
	event_banner.theme = theme
	var tbox := _sb(Color(0.1, 0.3, 0.14, 0.92), 10, 4)
	tbox.set_border_width_all(2)
	tbox.border_color = Color(0.55, 1.0, 0.62)
	truck_banner = PanelContainer.new()
	truck_banner.theme = theme
	truck_banner.add_theme_stylebox_override("panel", tbox)
	truck_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	truck_banner.offset_left = -95; truck_banner.offset_right = 95
	truck_banner.offset_top = 50; truck_banner.offset_bottom = 76
	truck_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(truck_banner)
	truck_lbl = _lbl(truck_banner, "", 13, 1.0)
	truck_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.88))
	truck_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	truck_banner.hide()

	var ebox := _sb(Color(0.56, 0.18, 0.08, 0.92), 10, 4)
	ebox.set_border_width_all(2)
	ebox.border_color = Color(1.0, 0.84, 0.3)
	event_banner.add_theme_stylebox_override("panel", ebox)
	event_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	event_banner.offset_left = -110; event_banner.offset_right = 110
	event_banner.offset_top = 80; event_banner.offset_bottom = 106
	event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(event_banner)
	event_lbl = _lbl(event_banner, "", 13, 1.0)
	event_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	event_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_banner.hide()

	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_box.offset_left = 12; toast_box.offset_right = 270
	toast_box.offset_top = 10; toast_box.offset_bottom = 70
	toast_box.add_theme_constant_override("separation", 3)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(toast_box)

	money_hud = PanelContainer.new()
	money_hud.theme = theme
	var box := _sb(Color(0.08, 0.05, 0.04, 0.85), 10, 6)
	box.set_border_width_all(2)
	box.border_color = Color(GOLD, 0.7)
	money_hud.add_theme_stylebox_override("panel", box)
	money_hud.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_hud.offset_left = -130; money_hud.offset_right = -14
	money_hud.offset_top = 10; money_hud.offset_bottom = 10
	money_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(money_hud)
	var mvb := VBoxContainer.new()
	mvb.add_theme_constant_override("separation", 0)
	mvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_hud.add_child(mvb)
	money_lbl = _lbl(mvb, "120 TL", 20, 1.0)
	money_lbl.add_theme_font_override("font", _font(900))
	money_lbl.add_theme_color_override("font_color", GOLD)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_lbl.pivot_offset = Vector2(100, 14)
	rep_lbl = _lbl(mvb, "", 12, 1.0)
	rep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rep_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.36))
	rep_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rep_lbl.hide()
	money_hud.hide()

	money_pop = _lbl(layer, "", 17, 1.0)
	money_pop.add_theme_font_override("font", _font(900))
	money_pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	money_pop.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	money_pop.offset_left = -200; money_pop.offset_right = -14
	money_pop.offset_top = 74; money_pop.offset_bottom = 100
	money_pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_pop.hide()

	interact_lbl = _lbl(layer, "", 14, 0.96)
	interact_lbl.set_anchors_preset(Control.PRESET_CENTER)
	interact_lbl.offset_left = -380; interact_lbl.offset_right = 380
	interact_lbl.offset_top = 24; interact_lbl.offset_bottom = 76
	interact_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interact_lbl.add_theme_color_override("font_outline_color", Color(0.05, 0.035, 0.02))
	interact_lbl.add_theme_constant_override("outline_size", 7)
	interact_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.78))
	interact_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_lbl.hide()


func _hud_box(border_a := 0.55, bg := PANEL_BG, radius := 14, margin := 10) -> StyleBoxFlat:
	var b := _sb(bg, radius, margin)
	b.set_border_width_all(2)
	b.border_color = Color(GOLD, border_a)
	b.shadow_color = Color(0, 0, 0, 0.35)
	b.shadow_size = 6
	b.shadow_offset = Vector2(0, 3)
	return b


## v0.6 HUD: ilk açılış rehberi kartı.
func _build_meta_hud(layer: CanvasLayer, theme: Theme) -> void:
	# Rehber kartı: hotbar'ın hemen üstünde
	tut_panel = PanelContainer.new()
	tut_panel.theme = theme
	var tb := _hud_box(0.9, Color(0.12, 0.07, 0.04, 0.92), 10, 6)
	tb.border_width_left = 4
	tut_panel.add_theme_stylebox_override("panel", tb)
	tut_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tut_panel.offset_left = -190; tut_panel.offset_right = 190
	tut_panel.offset_top = -126; tut_panel.offset_bottom = -94
	tut_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_panel.pivot_offset = Vector2(170, 20)
	layer.add_child(tut_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_panel.add_child(tv)
	tut_title = _lbl(tv, "", 10, 0.95)
	tut_title.add_theme_color_override("font_color", GOLD)
	tut_title.add_theme_font_override("font", _font(900))
	tut_text = _lbl(tv, "", 13, 1.0)
	tut_text.add_theme_color_override("font_color", CREAM)
	tut_panel.hide()


## P tuşu ile açılan PAZARCI DÜKKANI: Sol sütun Kişisel Eşyalar (Envanter), Sağ sütun Tezgah Geliştirmeleri.
func _build_shop_panel(layer: CanvasLayer, theme: Theme) -> void:
	shop_wrap = ColorRect.new()
	shop_wrap.color = Color(0, 0, 0, 0.62)
	shop_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_wrap.theme = theme
	layer.add_child(shop_wrap)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_wrap.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 720
	c.add_child(panel)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 6)
	panel.add_child(root_v)

	shop_title_lbl = _logo(root_v, "🛍️ DÜKKAN", 24)
	shop_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_wallet_lbl = _lbl(root_v, "💰 120 TL", 14, 1.0)
	shop_wallet_lbl.add_theme_color_override("font_color", GOLD)
	shop_wallet_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	root_v.add_child(cols)

	# Sol Sütun: Kişisel Envanter Eşyaları (kaydırılabilir, 720p'de taşmaz)
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 6)
	cols.add_child(left_col)
	shop_left_col = left_col
	var lh := _lbl(left_col, "🎒", 14, 1.0)
	lh.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(0, 330)
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(left_scroll)
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 4)
	left_scroll.add_child(left_v)
	for iid in Items.ORDER:
		var info_i: Dictionary = Items.CATALOG[iid]
		var rp := PanelContainer.new()
		var rsb := _sb(Color(0.14, 0.09, 0.07, 0.95), 6, 3)
		rsb.set_border_width_all(1)
		rsb.border_color = Color(GOLD, 0.3)
		rp.add_theme_stylebox_override("panel", rsb)
		left_v.add_child(rp)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		rp.add_child(hb)
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tx.add_theme_constant_override("separation", 0)
		hb.add_child(tx)
		var nl := _lbl(tx, "%s %s" % [str(info_i["icon"]), str(info_i["name"])], 12, 1.0)
		nl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
		_lbl(tx, str(info_i["desc"]), 9, 0.7)
		var btn := _btn(hb, "%d TL" % int(info_i["cost"]), _on_buy_item.bind(iid), 26)
		btn.custom_minimum_size.x = 76
		shop_item_btns[iid] = btn
		shop_item_rows[iid] = rp

	# Sağ Sütun: Tezgah Geliştirmeleri
	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 5)
	cols.add_child(right_v)
	shop_right_col = right_v
	var rh := _lbl(right_v, "⭐ TEZGAH", 14, 1.0)
	rh.add_theme_color_override("font_color", GOLD)
	for key in StallScript.UPGRADE_ORDER:
		var info_u: Dictionary = StallScript.UPGRADES[key]
		var rp := PanelContainer.new()
		var rsb := _sb(Color(0.14, 0.09, 0.07, 0.95), 8, 5)
		rsb.set_border_width_all(1)
		rsb.border_color = Color(GOLD, 0.3)
		rp.add_theme_stylebox_override("panel", rsb)
		right_v.add_child(rp)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		rp.add_child(hb)
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(tx)
		var nl := _lbl(tx, str(info_u["name"]), 13, 1.0)
		nl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
		var dl := _lbl(tx, str(info_u["desc"]), 10, 0.72)
		var btn := _btn(hb, "%d TL" % int(info_u["cost"]), _on_buy_upgrade.bind(key), 30)
		btn.custom_minimum_size.x = 84
		upgrade_rows[key] = [btn, dl, rp]
	# Tezgahı genişlet: 2 seviye (6 / 8 yuva)
	var xp := PanelContainer.new()
	var xsb := _sb(Color(0.14, 0.09, 0.07, 0.95), 8, 5)
	xsb.set_border_width_all(1)
	xsb.border_color = Color(GOLD, 0.3)
	xp.add_theme_stylebox_override("panel", xsb)
	right_v.add_child(xp)
	var xhb := HBoxContainer.new()
	xhb.add_theme_constant_override("separation", 8)
	xp.add_child(xhb)
	var xtx := VBoxContainer.new()
	xtx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xhb.add_child(xtx)
	var xnl := _lbl(xtx, "Tezgahı genişlet", 13, 1.0)
	xnl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.78))
	var xdl := _lbl(xtx, "📏 0/2", 10, 0.72)
	var xbtn := _btn(xhb, "%d TL" % int(EXPAND_COSTS[0]), _on_buy_expansion, 30)
	xbtn.custom_minimum_size.x = 84
	expand_row = [xbtn, xdl, xp]

	shop_look_box = VBoxContainer.new()
	shop_look_box.add_theme_constant_override("separation", 6)
	root_v.add_child(shop_look_box)
	shop_empty_lbl = _lbl(root_v, "🚧 Yakında", 14, 0.85)
	shop_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn(root_v, "✖  [ESC]", _close_shop, 30)
	shop_wrap.hide()


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
	panel.custom_minimum_size.x = 1000
	c.add_child(panel)
	summary_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	summary_title = _logo(v, "🏆 GÜN 1 SONU — GÜNÜN ESNAFI", 34)
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)
	summary_list = VBoxContainer.new()
	summary_list.add_theme_constant_override("separation", 6)
	summary_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_list.size_flags_stretch_ratio = 1.25
	cols.add_child(summary_list)
	summary_side = VBoxContainer.new()
	summary_side.add_theme_constant_override("separation", 5)
	summary_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(summary_side)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	v.add_child(bh)
	next_day_btn = _btn(bh, "▶  Yeni Günü Başlat", _on_next_day_pressed, 52)
	next_day_btn.add_theme_font_size_override("font_size", 22)
	next_day_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_day_btn.size_flags_stretch_ratio = 2.0
	var mb := _btn(bh, "Ana Menüye Dön", Net.leave, 52)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_wrap.hide()


func show_toast(msg: String, color := Color(1.0, 0.94, 0.78)) -> void:
	if toast_box == null:
		return
	# Aynı mesaj 4 sn içinde tekrar gösterilmez; ekranda en fazla 2 bildirim
	var now := Time.get_ticks_msec()
	if now - int(_toast_seen.get(msg, -100000)) < 4000:
		return
	_toast_seen[msg] = now
	while toast_box.get_child_count() >= 2:
		var old := toast_box.get_child(0)
		toast_box.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	var sb := _sb(Color(0.08, 0.05, 0.04, 0.88), 8, 5)
	sb.border_width_left = 3
	sb.border_color = color
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _lbl(p, msg, 12, 1.0)
	l.add_theme_color_override("font_color", color)
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


func _on_money_earned(amount: int, total: int, tip: int) -> void:
	money_lbl.text = "%d TL" % total
	var sale := amount - tip
	money_pop.text = ("+%d TL (⭐+%d)" % [amount, tip]) if tip > 0 else ("+%d TL" % amount)
	money_pop.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55))
	_animate_money_pop()
	_refresh_shop_panel()
	_track_income(sale, tip)
	if sale > 0:
		SteamMgr.unlock("ACH_FIRST_SALE")


func _on_money_spent(amount: int, total: int, reason: String) -> void:
	money_lbl.text = "%d TL" % total
	if amount > 0:
		money_pop.text = "-%d TL" % amount
		money_pop.add_theme_color_override("font_color", Color(1.0, 0.38, 0.34))
		_animate_money_pop()
	if "Ceza" in reason:
		show_toast("🚨 Ceza", Color(1.0, 0.38, 0.34))
		qstats["fined"] = true
		SteamMgr.unlock("ACH_ZABITA_FINE")
	_refresh_shop_panel()


func _animate_money_pop() -> void:
	money_pop.modulate.a = 1.0
	money_pop.offset_top = 74
	money_pop.offset_bottom = 100
	money_pop.show()
	money_lbl.scale = Vector2(1.12, 1.12)
	var tw := create_tween().set_parallel()
	tw.tween_property(money_lbl, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(money_pop, "offset_top", 54.0, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(money_pop, "modulate:a", 0.0, 0.95).set_delay(0.25)
	tw.chain().tween_callback(money_pop.hide)


func _day_prog() -> float:
	return clampf(day_time / DAY_DURATION, 0.0, 1.0)


## Oyuncu bir dükkanın kapısında [E]'ye bastı: açıksa o dükkanın paneli açılır.
func open_shop(shop_id: String) -> void:
	if world == null or day_ended or _is_pause_or_modal_open() or not Shops.SHOPS.has(shop_id):
		return
	if shop_wrap.visible:
		_close_shop()
		return
	var prog := _day_prog()
	if not Shops.is_open(shop_id, prog):
		show_toast("🔒 %s kapalı — %s" % [Shops.display_name(shop_id, prog), Shops.closed_text(shop_id, prog)], Color(1.0, 0.7, 0.4))
		return
	current_shop = shop_id
	var info: Dictionary = Shops.SHOPS[shop_id]
	shop_title_lbl.text = "%s %s" % [str(info["icon"]), Shops.display_sign(shop_id, prog)]
	var items: Array = info["items"]
	var ups: Array = info["upgrades"]
	for iid in shop_item_rows:
		(shop_item_rows[iid] as Control).visible = iid in items
	for key in upgrade_rows:
		(upgrade_rows[key][2] as Control).visible = key in ups
	var looks: Array = info.get("looks", [])
	shop_look_box.visible = not looks.is_empty()
	var can_expand := bool(info.get("expand", false))
	if expand_row.size() > 2:
		(expand_row[2] as Control).visible = can_expand
	shop_left_col.visible = not items.is_empty()
	shop_right_col.visible = not ups.is_empty() or can_expand
	shop_empty_lbl.visible = items.is_empty() and ups.is_empty() and not can_expand and looks.is_empty()
	_refresh_shop_panel()
	shop_wrap.show()
	_pop_in(shop_wrap)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_shop() -> void:
	shop_wrap.hide()
	current_shop = ""
	if world and not _is_pause_or_modal_open() and not day_ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_shop_panel() -> void:
	if players == null or stalls == null:
		return
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	var st := stalls.get_node_or_null("Stall_%d" % my_id)
	if me == null or st == null:
		return
	shop_wallet_lbl.text = "💰 %d TL" % int(me.money)
	_refresh_look_rows(me)
	var mult := Shops.price_mult(current_shop, _day_prog()) if current_shop != "" else 1.0
	for iid in shop_item_btns:
		var btn: Button = shop_item_btns[iid]
		var info_i: Dictionary = Items.CATALOG[iid]
		var cost: int = int(ceil(float(info_i["cost"]) * mult))
		var cons: bool = bool(info_i["consumable"])
		var owned: bool = me.has_inventory_item(iid) or (iid == "radyo" and st.has_radio)
		if not cons and owned:
			btn.text = "✔ VAR"
			btn.disabled = true
		else:
			btn.text = "%d TL" % cost
			btn.disabled = int(me.money) < cost
	for key in upgrade_rows:
		var btn: Button = upgrade_rows[key][0]
		var cost: int = int(StallScript.UPGRADES[key]["cost"])
		if st.has_upgrade(key):
			btn.text = "✔ ALINDI"
			btn.disabled = true
		else:
			btn.text = "%d TL" % cost
			btn.disabled = int(me.money) < cost
	if not expand_row.is_empty():
		var xb: Button = expand_row[0]
		var lv := _expansion_level(st)
		(expand_row[1] as Label).text = "📏 %d/%d  →  %d yuva" % [lv, EXPAND_COSTS.size(), 4 + 2 * mini(lv + 1, EXPAND_COSTS.size())]
		if lv >= EXPAND_COSTS.size():
			xb.text = "✔ MAX"
			xb.disabled = true
		else:
			xb.text = "%d TL" % int(EXPAND_COSTS[lv])
			xb.disabled = int(me.money) < int(EXPAND_COSTS[lv])


func _expansion_level(st: Node) -> int:
	return int(st.get("expansion_level")) if st and "expansion_level" in st else 0


## 3. biradan sonra gözler kapanır: üstten ve alttan inen siyah göz kapakları.
func _update_eyelids(me: Node) -> void:
	var k := float(me.get("eyelid")) if me.get("eyelid") != null else 0.0
	if lid_top == null:
		if k <= 0.001 or money_hud == null:
			return
		var layer := money_hud.get_parent()
		lid_top = ColorRect.new()
		lid_bot = ColorRect.new()
		for r: ColorRect in [lid_top, lid_bot]:
			r.color = Color(0.02, 0.01, 0.01)
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			layer.add_child(r)
	var vs := get_viewport().get_visible_rect().size
	var h := vs.y * 0.5 * clampf(k, 0.0, 1.0) * 1.02
	lid_top.visible = k > 0.001
	lid_bot.visible = k > 0.001
	lid_top.position = Vector2.ZERO
	lid_top.size = Vector2(vs.x, h)
	lid_bot.position = Vector2(0.0, vs.y - h)
	lid_bot.size = Vector2(vs.x, h)


## Berber / terzi: her tür için bir satır seçenek düğmesi; mevcut seçim işaretli.
func _refresh_look_rows(me: Node) -> void:
	if shop_look_box == null:
		return
	for c in shop_look_box.get_children():
		c.queue_free()
	if current_shop == "" or not Shops.SHOPS.has(current_shop):
		return
	var cur: Dictionary = me.get("look") if me.get("look") != null else {}
	for kind in Shops.SHOPS[current_shop].get("looks", []):
		var info: Dictionary = Shops.LOOKS[kind]
		var t := _lbl(shop_look_box, "%s  •  %d TL" % [str(info["title"]), int(info["cost"])], 14, 1.0)
		t.add_theme_color_override("font_color", GOLD)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		shop_look_box.add_child(row)
		var opts: Array = info["opts"]
		for i in opts.size():
			var sel: bool = int(cur.get(kind, -1)) == i or (int(cur.get(kind, -1)) == -1 and kind in ["hair", "must", "hat"] and i == 0)
			var o = opts[i]
			var b: Button
			if o is Color:
				b = _btn(row, "✔" if sel else " ", _on_buy_look.bind(kind, i), 30)
				b.custom_minimum_size = Vector2(44, 30)
				var sb := _sb(o, 6, 2)
				sb.set_border_width_all(3 if sel else 1)
				sb.border_color = GOLD if sel else Color(0, 0, 0, 0.6)
				for st_name in ["normal", "hover", "pressed", "disabled"]:
					b.add_theme_stylebox_override(st_name, sb)
			else:
				b = _btn(row, ("✔ " if sel else "") + str(o), _on_buy_look.bind(kind, i), 30)
				b.custom_minimum_size.x = 96
			b.disabled = sel or int(me.money) < int(info["cost"])


func _on_buy_look(kind: String, idx: int) -> void:
	if Net.online():
		rpc_request_look.rpc_id(1, kind, idx, current_shop)
	else:
		rpc_request_look(kind, idx, current_shop)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_look(kind: String, idx: int, shop_id := "") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if not Shops.LOOKS.has(kind) or players == null or not Shops.SHOPS.has(shop_id):
		return
	if not kind in (Shops.SHOPS[shop_id].get("looks", []) as Array) or not Shops.is_open(shop_id, _day_prog()):
		return
	if idx < 0 or idx >= (Shops.LOOKS[kind]["opts"] as Array).size():
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	if p == null:
		return
	var cost := int(Shops.LOOKS[kind]["cost"])
	if int(p.money) < cost:
		_notify_peer(pid, "💸 %d TL gerek" % cost, Color(1.0, 0.45, 0.4))
		return
	p.spend_money(cost, str(Shops.LOOKS[kind]["title"]))
	p.set_look_synced(kind, idx)
	if Net.online() and pid != 1:
		rpc_look_done.rpc_id(pid)
	else:
		rpc_look_done()


## Alıcının ekranında: panel kapanır ve 3.5 sn aynada yeni görünüm.
@rpc("authority", "call_local", "reliable")
func rpc_look_done() -> void:
	_close_shop()
	var me := players.get_node_or_null(str(multiplayer.get_unique_id() if Net.online() else 1)) if players else null
	if me and me.has_method("show_mirror"):
		me.show_mirror()
	show_toast("🪞 Yakıştı!", Color(1.0, 0.9, 0.6))


func _on_buy_expansion() -> void:
	if Net.online():
		rpc_request_buy_expansion.rpc_id(1, current_shop)
	else:
		rpc_request_buy_expansion(current_shop)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_buy_expansion(shop_id := "") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or stalls == null:
		return
	if not Shops.SHOPS.has(shop_id) or not bool(Shops.SHOPS[shop_id].get("expand", false)) or not Shops.is_open(shop_id, _day_prog()):
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	var st := stalls.get_node_or_null("Stall_%d" % pid)
	if p == null or st == null or not st.has_method("rpc_set_expansion"):
		return
	var lv := _expansion_level(st)
	if lv >= EXPAND_COSTS.size():
		return
	var cost: int = int(EXPAND_COSTS[lv])
	if int(p.money) < cost:
		_notify_peer(pid, "💸 %d TL gerek" % cost, Color(1.0, 0.45, 0.4))
		return
	p.spend_money(cost, "Tezgah Genişletme")
	if Net.online():
		st.rpc("rpc_set_expansion", lv + 1)
	else:
		st.call("rpc_set_expansion", lv + 1)
	if lv + 1 >= EXPAND_COSTS.size() and pid == _my_id():
		SteamMgr.unlock("ACH_FULL_EXPAND")
	_broadcast_toast("📏 %s: %d/%d" % [Net.display_name(pid), lv + 1, EXPAND_COSTS.size()], Color(0.58, 1.0, 0.65))


func _on_buy_item(item_id: String) -> void:
	if Net.online():
		rpc_request_buy_item.rpc_id(1, item_id, current_shop)
	else:
		rpc_request_buy_item(item_id, current_shop)


## Host doğrular: dükkan açık mı, bu dükkan bunu satıyor mu.
func _shop_sells(shop_id: String, list_key: String, what: String) -> bool:
	if not Shops.SHOPS.has(shop_id) or not Shops.is_open(shop_id, _day_prog()):
		return false
	return what in (Shops.SHOPS[shop_id][list_key] as Array)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_buy_item(item_id: String, shop_id := "") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if not Items.CATALOG.has(item_id) or players == null or stalls == null:
		return
	if not _shop_sells(shop_id, "items", item_id):
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	var st := stalls.get_node_or_null("Stall_%d" % pid)
	if p == null or st == null:
		return
	var info_i: Dictionary = Items.CATALOG[item_id]
	var cons: bool = bool(info_i["consumable"])
	if not cons and (p.has_inventory_item(item_id) or (item_id == "radyo" and st.has_radio)):
		return
	if not p.can_add_inventory_item(item_id):
		_notify_peer(pid, L10n.pick("Envanter dolu", "Inventory is full"), Color(1.0, 0.45, 0.4))
		return
	var cost: int = int(ceil(float(info_i["cost"]) * Shops.price_mult(shop_id, _day_prog())))
	if int(p.money) < cost:
		_notify_peer(pid, "💸 %d TL gerek" % cost, Color(1.0, 0.45, 0.4))
		return
	p.spend_money(cost, str(info_i["name"]))
	p.add_inventory_item_synced(item_id)
	Sfx.play("upgrade", -4.0)


func _on_buy_upgrade(key: String) -> void:
	if Net.online():
		rpc_request_buy_upgrade.rpc_id(1, key, current_shop)
	else:
		rpc_request_buy_upgrade(key, current_shop)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_buy_upgrade(key: String, shop_id := "") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if not StallScript.UPGRADES.has(key) or players == null or stalls == null:
		return
	if not _shop_sells(shop_id, "upgrades", key):
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
		_notify_peer(pid, "💸 %d TL gerek" % cost, Color(1.0, 0.45, 0.4))
		return
	p.spend_money(cost, str(StallScript.UPGRADES[key]["name"]))
	st.apply_upgrade_synced(key)
	_broadcast_toast("⭐ %s: %s" % [Net.display_name(pid), str(StallScript.UPGRADES[key]["name"])], Color(0.58, 1.0, 0.65))


## Zabıta acil müdahale sevk yardımcısı (host çağırır): varsa yönlendirir, yoksa en yakın kapıdan koşturur!
func _dispatch_zabita(att: Node3D, attacker_id: int, weapon: String, fine: int, reason: String) -> void:
	if world == null:
		return
	var existing_z := world.get_node_or_null("Zabita")
	if existing_z:
		if Net.online():
			rpc_redirect_zabita.rpc(attacker_id, weapon, fine, reason)
		else:
			rpc_redirect_zabita(attacker_id, weapon, fine, reason)
	else:
		var from_n := att.global_position.z < 0.0 if att else true
		if Net.online():
			rpc_spawn_zabita.rpc(from_n, attacker_id, weapon, fine, reason)
		else:
			rpc_spawn_zabita(from_n, attacker_id, weapon, fine, reason)


## Meyve Bıçağı saldırısı -> Sunucu doğrular ve Zabıta anında saldırganın peşine koşar!
func request_knife_attack(target_id: int) -> void:
	if Net.online():
		rpc_request_knife_attack.rpc_id(1, target_id)
	else:
		rpc_request_knife_attack(target_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_knife_attack(target_id: int) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or world == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id() if Net.online() else 1
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == target_id:
		return
	var att := players.get_node_or_null(str(attacker_id)) as Node3D
	var vic := players.get_node_or_null(str(target_id)) as Node3D
	if att == null or vic == null or not att.has_inventory_item("bicak"):
		return
	if att.global_position.distance_to(vic.global_position) > 3.2:
		return
	var knock := (vic.global_position - att.global_position)
	knock.y = 0.0
	knock = knock.normalized() if knock.length_squared() > 0.01 else Vector3(1, 0, 0)
	vic.apply_knife_hit_synced(knock)
	_broadcast_toast("🔪 %s → %s 🚨 Zabıta geliyor!" % [Net.display_name(attacker_id), Net.display_name(target_id)], Color(1.0, 0.32, 0.26))
	_dispatch_zabita(att, attacker_id, "bicak", 50, "Bıçaklı Saldırı Cezası!")


## Sopa saldırısı ihbarı -> Zabıta koşup ceza yazar ve sopaya el koyar!
func request_assault_report(target_id: int, weapon := "sopa") -> void:
	if Net.online():
		rpc_request_assault_report.rpc_id(1, target_id, weapon)
	else:
		rpc_request_assault_report(target_id, weapon)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_assault_report(target_id: int, weapon := "sopa") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or world == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id() if Net.online() else 1
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == target_id:
		return
	var att := players.get_node_or_null(str(attacker_id)) as Node3D
	var vic := players.get_node_or_null(str(target_id)) as Node3D
	if att == null or vic == null:
		return
	_broadcast_toast("🏏 %s → %s sopayla vurdu! 🚨 Zabıta geliyor!" % [Net.display_name(attacker_id), Net.display_name(target_id)], Color(1.0, 0.38, 0.26))
	_dispatch_zabita(att, attacker_id, weapon, 50, "Sopayla Saldırı Cezası!")


## Fırlatılan bira şişesi rakip oyuncuya isabet etti -> Yere serer + kötü kokutur + Zabıta gelir!
func request_beer_hit_player(target_id: int, knock_dir: Vector3) -> void:
	if Net.online():
		rpc_request_beer_hit_player.rpc_id(1, target_id, knock_dir)
	else:
		rpc_request_beer_hit_player(target_id, knock_dir)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_beer_hit_player(target_id: int, knock_dir: Vector3) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or world == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id() if Net.online() else 1
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == target_id:
		return
	var att := players.get_node_or_null(str(attacker_id)) as Node3D
	var vic := players.get_node_or_null(str(target_id)) as Node3D
	if att == null or vic == null:
		return
	if att.global_position.distance_to(vic.global_position) > 16.0:
		return
	var kd := Vector3(knock_dir.x, 0.0, knock_dir.z)
	if kd.length_squared() < 0.01:
		kd = vic.global_position - att.global_position
		kd.y = 0.0
	kd = kd.normalized() if kd.length_squared() > 0.01 else Vector3(0, 0, 1)
	if vic.has_method("apply_beer_hit_synced"):
		vic.apply_beer_hit_synced(kd, 25.0)
	_broadcast_toast("🍺💥 %s → %s'e bira şişesi attı! 🚨 Zabıta geliyor!" % [Net.display_name(attacker_id), Net.display_name(target_id)], Color(0.86, 0.94, 0.28))
	_dispatch_zabita(att, attacker_id, "bira", 45, "Bira Şişesiyle Saldırı!")


## Fırlatılan bira şişesi rakip tezgaha isabet etti -> Kötü koku + 4x çürüme + Zabıta gelir!
func request_beer_hit_stall(stall_owner_id: int) -> void:
	if Net.online():
		rpc_request_beer_hit_stall.rpc_id(1, stall_owner_id)
	else:
		rpc_request_beer_hit_stall(stall_owner_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_beer_hit_stall(stall_owner_id: int) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or stalls == null or world == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id() if Net.online() else 1
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == stall_owner_id:
		return
	var att := players.get_node_or_null(str(attacker_id)) as Node3D
	var st := stalls.get_node_or_null("Stall_%d" % stall_owner_id)
	if att == null or st == null:
		return
	if att.global_position.distance_to((st as Node3D).global_position) > 16.0:
		return
	if st.has_method("apply_beer_sabotage"):
		st.apply_beer_sabotage(35.0, 0.15)
	_broadcast_toast("🍺🤢 %s, %s'in tezgahına bira attı! (4x çürüme) 🚨" % [Net.display_name(attacker_id), Net.display_name(stall_owner_id)], Color(0.76, 0.94, 0.28))
	_dispatch_zabita(att, attacker_id, "bira", 40, "Tezgaha Bira Sabotajı!")


## Sigara/Puro dumanı rakip tezgaha üflendi -> Tüm ürünlerde -%10 tazelik + Zabıta gelir!
func request_smoke_sabotage(stall_owner_id: int, weapon := "sigara") -> void:
	if Net.online():
		rpc_request_smoke_sabotage.rpc_id(1, stall_owner_id, weapon)
	else:
		rpc_request_smoke_sabotage(stall_owner_id, weapon)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_smoke_sabotage(stall_owner_id: int, weapon := "sigara") -> void:
	if Net.online() and not multiplayer.is_server():
		return
	if players == null or stalls == null or world == null:
		return
	var attacker_id := multiplayer.get_remote_sender_id() if Net.online() else 1
	if attacker_id == 0:
		attacker_id = 1
	if attacker_id == stall_owner_id:
		return
	var att := players.get_node_or_null(str(attacker_id)) as Node3D
	var st := stalls.get_node_or_null("Stall_%d" % stall_owner_id)
	if att == null or st == null:
		return
	if att.global_position.distance_to((st as Node3D).global_position) > 4.8:
		return
	if st.total_stock() <= 0:
		return
	if st.has_method("apply_smoke_rot"):
		st.apply_smoke_rot(0.10)
	var w_id := weapon if weapon in ["sigara", "puro"] else "sigara"
	_broadcast_toast("🚬💨 %s, %s'in tezgahına duman üfledi (-%%10 tazelik)! 🚨" % [Net.display_name(attacker_id), Net.display_name(stall_owner_id)], Color(0.86, 0.84, 0.78))
	_dispatch_zabita(att, attacker_id, w_id, 30, "Tezgaha Duman Sabotajı!")


func _refresh_scoreboard_rows(target_box: VBoxContainer, show_crown: bool) -> void:
	for c in target_box.get_children():
		c.queue_free()
	if players == null:
		return
	var rows := []
	for p in players.get_children():
		var pid := p.name.to_int()
		rows.append({
			"id": pid, "name": Net.display_name(pid), "money": int(p.money),
			"profit": int(p.net_profit()), "sold": int(p.daily_sold),
			"tips": int(p.daily_tips), "fines": int(p.daily_fines),
		})
	rows.sort_custom(func(a, b): return a["profit"] > b["profit"] if a["profit"] != b["profit"] else a["money"] > b["money"])
	# Hizalı tablo (orantılı yazı tipinde boşluklarla hizalama kayıyordu)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_box.add_child(grid)
	var cell := func(text: String, size: int, col: Color, right: bool) -> void:
		var l := _lbl(grid, text, size, 1.0)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.add_theme_color_override("font_color", col)
		if right:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var hc := Color(GOLD, 0.75)
	for h in ["ESNAF", "CÜZDAN", "NET KÂR", "SATIŞ", "BONUS", "CEZA"]:
		cell.call(h, 13, hc, h != "ESNAF")
	for i in rows.size():
		var r: Dictionary = rows[i]
		var medal := ("👑 " if show_crown else "#1 ") if i == 0 else ("#%d " % (i + 1))
		var sz := 17 if i == 0 else 15
		var col := GOLD if i == 0 else Color(0.95, 0.92, 0.86)
		cell.call(medal + str(r["name"]).left(18), sz, col, false)
		cell.call("%d TL" % r["money"], sz, col, true)
		cell.call("%+d TL" % r["profit"], sz, GOOD if int(r["profit"]) > 0 else (BAD if int(r["profit"]) < 0 else col), true)
		cell.call(str(r["sold"]), sz, col, true)
		cell.call("%d TL" % r["tips"], sz, col, true)
		cell.call("%d TL" % r["fines"], sz, BAD if int(r["fines"]) > 0 else col, true)


func _is_pause_or_modal_open() -> bool:
	return menu_ui != null and menu_ui.is_any_modal_open()


func _open_pause() -> void:
	if menu_ui:
		menu_ui.open_pause()


func _close_pause() -> void:
	if menu_ui:
		menu_ui.close_all_modals()


func _show_page(n: String) -> void:
	page = n
	if menu_ui:
		menu_ui.show_page(n)


func _on_invited(from_name: String, lobby: int) -> void:
	if invite_box == null:
		return
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
	if menu_ui:
		menu_ui.refresh_lobby()
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
	bz.set_day_progress(0.40)
	if bz.has_method("apply_graphics_settings"):
		bz.call("apply_graphics_settings")
	elif bz.has_method("set_quality"):
		bz.call("set_quality", Settings.quality_high)
	_menu_music(true)
	menu_cam = Camera3D.new()
	menu_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # _process içinde sürülüyor
	menu_cam.fov = 60
	menu_bg.add_child(menu_cam)
	menu_cam.current = true
	for i in 6:
		var p: Node3D = PlayerScript.new()
		p.npc = true
		p.color_id = i * 3 + 1
		p.name = "Npc%d" % i
		menu_bg.add_child(p)
		walkers.append([p, -1.8 + float(i % 3) * 1.8, -14.0 + float(i) * 5.2, 1.5 * (1.0 if i % 2 == 0 else -1.0)])


func _menu_anim(dt: float) -> void:
	menu_t += dt
	var a := menu_t * 0.14
	# Brandaların altından canlı Türk semt pazarı caddesine bakan sinematik kamera
	menu_cam.position = Vector3(sin(a) * 2.2, 2.55 + sin(menu_t * 0.35) * 0.15, 11.5 + cos(a * 0.7) * 2.5)
	menu_cam.look_at(Vector3(0.0, 1.45, -6.0))
	for w in walkers:
		var p: Node3D = w[0]
		w[2] += float(w[3]) * dt
		if w[2] > 17.0:
			w[2] = -17.0
		elif w[2] < -17.0:
			w[2] = 17.0
		p.position = Vector3(float(w[1]), 0.0, float(w[2]))
		p.body_yaw = 0.0 if float(w[3]) > 0 else PI
		p.look_yaw = p.body_yaw + sin(menu_t * 0.7 + float(w[1])) * 0.4 - PI
		p.spd = absf(float(w[3]))


func _process(dt: float) -> void:
	if menu_bg:
		_menu_anim(dt)
		_rotate_menu_tip(dt)
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
	var modal_open := _is_pause_or_modal_open()
	if me and voice_hud.visible:
		var lvl: float = me.talk_smooth
		var muted: bool = me.mic_muted
		var eff_sh: float = me.get_effective_shout()
		voice_icon.level = lvl
		voice_icon.muted = muted
		voice_icon.queue_redraw()
		voice_bar.size.x = 0.0 if muted else 32.0 * lvl
		voice_bar.color = Color(0.95, 0.3, 0.25) if muted else (Color(1.0, 0.72, 0.2) if eff_sh > 0.7 else Color(0.4, 0.95, 0.5))
		voice_lbl.text = "🔇" if muted else ("📢" if (eff_sh > 0.85 and me.is_holding_item("megafon")) else ("🗣️" if eff_sh > 0.45 else ("🎙️" if lvl > 0.06 else "🎤")))
		var hide_interact := modal_open or shop_wrap.visible or day_ended
		interact_lbl.text = me.interact_hint
		interact_lbl.visible = me.interact_hint != "" and not hide_interact
		var motion_k := 0.22 if Settings.reduce_motion else 1.0
		speed_lines.intensity = 0.0 if hide_interact else float(me.sprint_k) * motion_k
		if menu_ui:
			menu_ui.update_crosshair(not hide_interact, me.has_target)
		if hint:
			hint.visible = Settings.show_hints and not hide_interact

	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	var mins := int(480.0 + prog * 810.0)
	var hh := int(mins / 60)
	var mm := int(mins % 60)
	var phase_txt := "🌅" if prog < 0.30 else ("☀️" if prog < 0.62 else ("🌇" if prog < 0.80 else "🌆"))
	var wi: Dictionary = WEATHER.get(weather, WEATHER["clear"])
	day_lbl.text = "%s %d  •  %02d:%02d  %s" % [str(wi["icon"]), day_num, hh, mm, phase_txt]
	day_bar.size.x = 240.0 * prog
	day_bar.color = Color(1.0, 0.78, 0.32) if prog < 0.72 else Color(1.0, 0.45, 0.22)

	if active_event_item != "" and event_timer > 0.0:
		event_banner.show()
		event_lbl.text = "🔥 %s  %d" % [WholesalerScript.ITEM_EMOJI.get(active_event_item, "⭐"), ceili(event_timer)]
	elif _crowd_timer > 0.0:
		event_banner.show()
		event_lbl.text = "👥 Kalabalık!"
	elif prog >= 0.72 and not day_ended:
		event_banner.show()
		event_lbl.text = "🌆 Akşam akını!"
	else:
		event_banner.hide()

	# Toptancı: geliş geri sayımı / park halinde kalan kasa
	var tl: float = wholesaler_node.countdown_left() if wholesaler_node and not day_ended else 0.0
	if tl > 0.0:
		truck_banner.show()
		truck_lbl.text = "🚚 Toptancı geliyor  %d:%02d" % [ceili(tl) / 60, ceili(tl) % 60]
	elif wholesaler_node and wholesaler_node.is_parked() and not day_ended:
		truck_banner.show()
		truck_lbl.text = "🚚 %d kasa  ⏱ %d" % [wholesaler_node.total_left(), ceili(wholesaler_node.state_timer)]
	else:
		truck_banner.hide()

	var show_sb := Input.is_action_pressed("scoreboard") and not modal_open and not shop_wrap.visible and not day_ended
	scoreboard_wrap.visible = show_sb
	if show_sb:
		_refresh_scoreboard_rows(scoreboard_list, false)

	_price_ui_cd -= dt
	if _price_ui_cd <= 0.0:
		_price_ui_cd = 1.0
		_refresh_stall_visual_prices()

	_update_meta_hud(dt, me)


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
		if shop_wrap.visible:
			_close_shop()
		elif menu_ui and menu_ui.handle_cancel():
			return
		elif world and not day_ended:
			_open_pause()
		elif page == "lobby" or page == "solo":
			_show_page("main")
		return
	var modal_open := _is_pause_or_modal_open()
	if e.is_action_pressed("tutorial_skip") and world and tut_step >= 0 and not modal_open and not shop_wrap.visible:
		_tut_advance(true)
		return
	if world and not modal_open and not shop_wrap.visible and not day_ended and e is InputEventMouseButton and e.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------- Ekonomi & Gün Döngüsü ----------

func _roll_wholesale_prices() -> void:
	wholesale_prices.clear()
	for item_id in Produce.ITEM_ORDER:
		var base_c: float = float(Produce.ITEMS[item_id]["crate_cost"])
		wholesale_prices[item_id] = maxi(20, roundi(base_c * randf_range(0.84, 1.16)))
	deal_item = Produce.ITEM_ORDER.pick_random()
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
	if wholesaler_node:
		wholesaler_node.update_prices(wholesale_prices, deal_item, active_event_item)
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


func get_crate_cost(peer_id: int, item_id: String, from_truck: bool) -> int:
	if not Produce.ITEMS.has(item_id):
		return 50
	# Toptancı: kendi sınırlı stok fiyatı
	if from_truck and wholesaler_node:
		return wholesaler_node.price_of(item_id)
	# Tezgah arkası kasalar kalktı: beş parasız kalana toptancıdan veresiye soğan
	if item_id == "sogan" and _is_emergency_credit(peer_id):
		return 0
	return int(wholesale_prices.get(item_id, Produce.ITEMS[item_id]["crate_cost"]))


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
	if from_truck and (wholesaler_node == null or not wholesaler_node.is_parked()):
		return
	var pid := multiplayer.get_remote_sender_id() if Net.online() else 1
	if pid == 0:
		pid = 1
	var p := players.get_node_or_null(str(pid))
	var st := stalls.get_node_or_null("Stall_%d" % pid)
	if p == null or st == null or bool(p.held_crate):
		return
	if from_truck and wholesaler_node.stock_left(item_id) <= 0:
		_notify_peer(pid, "😕 %s bitti!" % WholesalerScript.ITEM_EMOJI.get(item_id, "📦"), Color(1.0, 0.6, 0.4))
		return
	var cost := get_crate_cost(pid, item_id, from_truck)
	if int(p.money) < cost:
		_notify_peer(pid, "💸 %s %d TL" % [WholesalerScript.ITEM_EMOJI.get(item_id, "📦"), cost], Color(1.0, 0.45, 0.38))
		return
	# İlk gelen alır: stok düşümü host'ta tek seferde yapılır
	if from_truck and not wholesaler_node.take_stock(item_id):
		return
	if cost > 0:
		p.spend_money(cost, Produce.ITEMS[item_id]["name"] + " Kasası")
	else:
		_notify_peer(pid, "🤝 🧅 veresiye", Color(0.55, 1.0, 0.6))
	p.give_crate_synced(item_id, st.crate_capacity())


func _tick_day_and_events(dt: float) -> void:
	day_time += dt
	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	if bazaar_node:
		bazaar_node.set_day_progress(prog)

	if prog >= 0.72 and not rush_announced:
		rush_announced = true
		Sfx.play("event", -3.0)
		_broadcast_toast("🌆 Akşam pazarı!", Color(1.0, 0.68, 0.3))

	# Arada bir gelen Kalabalık Dalgası (18 sn sürer)
	if _crowd_timer > 0.0:
		_crowd_timer = maxf(_crowd_timer - dt, 0.0)
	else:
		_next_crowd_cd -= dt
		if _next_crowd_cd <= 0.0 and prog < 0.88:
			_next_crowd_cd = randf_range(54.0, 78.0)
			_crowd_timer = 18.0

	if event_timer > 0.0:
		event_timer -= dt
		if event_timer <= 0.0:
			active_event_item = ""
			active_event_title = ""
			_sync_economy_state()
	else:
		next_event_cd -= dt
		if next_event_cd <= 0.0 and prog < 0.88:
			next_event_cd = randf_range(60.0, 86.0)
			var ev: Dictionary = MARKET_EVENTS.pick_random()
			active_event_item = str(ev["item"])
			active_event_title = str(ev["title"])
			event_timer = 44.0
			_sync_economy_state()
			_broadcast_event_sfx("event")

	_tick_thieves(dt, prog)

	next_zabita_cd -= dt
	if next_zabita_cd <= 0.0 and prog < 0.90 and world and not world.has_node("Zabita"):
		next_zabita_cd = randf_range(72.0, 96.0) * lerpf(1.3 if day_num == 1 else 1.0, 0.72, _difficulty())
		var from_n := randf() < 0.5
		if Net.online():
			rpc_spawn_zabita.rpc(from_n, 0)
		else:
			rpc_spawn_zabita(from_n, 0)
		_broadcast_toast("🚨 Zabıta!", Color(0.58, 0.84, 1.0))

	_day_sync_t += dt
	if Net.online() and _day_sync_t >= 0.5:
		_day_sync_t = 0.0
		Net.rpc_ready(rpc_sync_day_time, [day_num, day_time, event_timer, _crowd_timer])

	if day_time >= DAY_DURATION:
		day_ended = true
		if Net.online():
			rpc_day_ended.rpc(day_num)
		else:
			rpc_day_ended(day_num)


@rpc("authority", "unreliable_ordered")
func rpc_sync_day_time(d_num: int, d_time: float, ev_t: float, crowd_t := 0.0) -> void:
	day_num = d_num
	day_time = d_time
	event_timer = ev_t
	_crowd_timer = crowd_t
	if bazaar_node:
		bazaar_node.set_day_progress(clampf(day_time / DAY_DURATION, 0.0, 1.0))


@rpc("authority", "call_local", "reliable")
func rpc_spawn_zabita(from_north: bool, attacker_id := 0, weapon := "bicak", fine := 50, reason := "Saldırı Cezası!") -> void:
	if world == null:
		return
	var ex := world.get_node_or_null("Zabita")
	if ex:
		if attacker_id > 0:
			ex.start_chase(attacker_id, weapon, fine, reason)
		return
	var z := InspectorScript.new()
	z.init_inspector(from_north, attacker_id, weapon, fine, reason)
	world.add_child(z)


@rpc("authority", "call_local", "reliable")
func rpc_redirect_zabita(attacker_id: int, weapon := "bicak", fine := 50, reason := "Saldırı Cezası!") -> void:
	if world == null:
		return
	var ex := world.get_node_or_null("Zabita")
	if ex:
		ex.start_chase(attacker_id, weapon, fine, reason)


@rpc("authority", "call_local", "reliable")
func rpc_day_ended(finished_day: int) -> void:
	day_ended = true
	day_num = finished_day
	shop_wrap.hide()
	scoreboard_wrap.hide()
	if menu_ui:
		menu_ui.close_all_modals()
		menu_ui.update_crosshair(false, false)
	Sfx.play("day_end", -2.0)
	_evaluate_end_fines()
	_save_career_day_end()
	# Başarımlar
	var me := _my_player()
	SteamMgr.unlock("ACH_DAY_COMPLETE")
	if me:
		var prof := int(me.net_profit())
		if prof >= 300:
			SteamMgr.unlock("ACH_PROFIT_300")
		if prof >= 700:
			SteamMgr.unlock("ACH_PROFIT_700")
		if not bool(qstats.get("fined", false)) and int(me.daily_fines) == 0:
			SteamMgr.unlock("ACH_CLEAN_DAY")
	if weather == "rain":
		SteamMgr.unlock("ACH_RAIN_DAY")
	if _my_reputation() >= 4.5:
		SteamMgr.unlock("ACH_MAX_REP")
	summary_title.text = "🏆 GÜN %d SONU — GÜNÜN ESNAFI" % day_num
	_refresh_scoreboard_rows(summary_list, true)
	_build_summary_side()
	var can_start := (not Net.online()) or multiplayer.is_server()
	next_day_btn.disabled = not can_start
	next_day_btn.text = ("▶  Gün %d'yi Başlat" % (day_num + 1)) if can_start else "Host yeni günü başlatacak..."
	summary_wrap.show()
	_pop_in(summary_wrap)
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
	for st in stalls.get_children():
		st.clear_day_stock()
	day_num = new_day
	day_time = 0.0
	day_ended = false
	rush_announced = false
	_crowd_timer = 0.0
	_next_crowd_cd = 45.0
	active_event_item = ""
	active_event_title = ""
	event_timer = 0.0
	next_event_cd = 38.0
	next_zabita_cd = 62.0
	summary_wrap.hide()
	if customers:
		for c in customers.get_children():
			c.queue_free()
	_clear_thieves()
	if world and world.has_node("Zabita"):
		world.get_node("Zabita").queue_free()
	if wholesaler_node and wholesaler_node.has_method("reset_for_new_day"):
		wholesaler_node.reset_for_new_day()
	_reset_local_day_stats()
	if (not Net.online()) or multiplayer.is_server():
		if players:
			for p in players.get_children():
				p.reset_daily_stats_synced()
		_roll_wholesale_prices()
		_begin_day_host()
	if bazaar_node:
		bazaar_node.set_day_progress(0.0)
	if day_num >= 3:
		SteamMgr.unlock("ACH_DAY_3")
	SteamMgr.set_presence_game(day_num, Net.names.size() if Net.online() else 1, Net.online())
	Sfx.play("event", -4.0)
	show_toast("☀️ Gün %d" % day_num, GOLD)
	_fade_in(0.5)
	if menu_ui:
		menu_ui.update_crosshair(true, false)
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


# ---------- Tek Oyna + Çoklu Oyun Akışı ----------

## Anında tek kişilik solo oyun başlat (Steam/lobi beklemeden test & oyun!).
func _start_solo() -> void:
	if Net.online():
		Net.leave()
	_stall_spots.clear()
	start_game([1], {1: 0}, {})


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

	# Ford Transit Toptancı ("GARDAŞLAR SEBZE MEYVE")
	wholesaler_node = WholesalerScript.new()
	world.add_child(wholesaler_node)
	if (not Net.online()) or multiplayer.is_server():
		wholesaler_node.arrived.connect(func():
			_broadcast_toast("🚚 Geldi! Sınırlı stok", Color(0.55, 1.0, 0.62)))

	stalls = Node3D.new()
	stalls.name = "Stalls"
	world.add_child(stalls)
	customers = Node3D.new()
	customers.name = "Customers"
	world.add_child(customers)
	thieves = Node3D.new()
	thieves.name = "Thieves"
	world.add_child(thieves)
	players = Node3D.new()
	players.name = "Players"
	world.add_child(players)

	_stall_spots.clear()
	_cust_seq = 0
	_cust_cd = 2.0
	_crowd_timer = 0.0
	_next_crowd_cd = 48.0
	day_num = 1
	day_time = 0.0
	day_ended = false
	rush_announced = false
	active_event_item = ""
	active_event_title = ""
	event_timer = 0.0
	next_event_cd = 40.0
	next_zabita_cd = 68.0
	weather = "clear"
	world.set_meta("weather", weather)
	world.set_meta("difficulty", 0.0)
	_thief_seq = 0
	_reset_local_day_stats()
	_apply_graphics_settings()
	_menu_music(false)

	for id in ids:
		var sp := int(spot_map.get(id, _alloc_spot(id)))
		_spawn(id, sp)

	_career_active = false
	if not snapshot.is_empty():
		_apply_world_snapshot(snapshot)
	elif (not Net.online()) or multiplayer.is_server():
		if not Net.online():
			if not _pending_career.is_empty():
				_apply_career(_pending_career)
			else:
				career = _fresh_career()
			_career_active = not _is_test_run()
		_pending_career = {}
		_roll_wholesale_prices()
		_begin_day_host()
	bazaar_node.set_day_progress(clampf(day_time / DAY_DURATION, 0.0, 1.0))

	ui.hide()
	summary_wrap.hide()
	shop_wrap.hide()
	scoreboard_wrap.hide()
	if menu_ui:
		menu_ui.close_all_modals()
	hint.visible = Settings.show_hints
	hotbar_wrap.show()
	voice_hud.show()
	day_hud.show()
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var me := players.get_node_or_null(str(my_id))
	money_lbl.text = "%d TL" % (int(me.money) if me else PlayerScript.STARTING_MONEY)
	money_hud.show()
	if menu_ui:
		menu_ui.update_crosshair(true, false)
	_refresh_hotbar()
	Sfx.set_ambience(true)
	SteamMgr.set_presence_game(day_num, ids.size(), Net.online())
	if Net.online() and ids.size() >= 2:
		SteamMgr.unlock("ACH_MULTI_OPEN")
	if Net.online():
		if multiplayer.is_server():
			Net.ready_peers.clear() # yeniden kurulumda istemciler tekrar hazır bildirir
		else:
			Net.rpc_peer_ready.rpc_id(1)
	if day_num <= 1:
		show_toast("☀️ Hoş geldin! [ESC] menü", GOLD)
	_fade_in(0.7)
	_tut_start_if_needed()
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
		p.open_shop.connect(open_shop)
		p.inventory_changed.connect(_refresh_hotbar)


## İki kapıdan (Kuzey & Güney) sakin tempoyla gelen NPC'ler + arada bir Kalabalık Dalgası + bolca Teyze!
func _tick_customers(dt: float) -> void:
	_cust_cd -= dt
	var prog := clampf(day_time / DAY_DURATION, 0.0, 1.0)
	var crowded := (_crowd_timer > 0.0) or (prog >= 0.72)
	var d := _difficulty()
	var rate: float = float(WEATHER.get(weather, WEATHER["clear"])["rate"])
	var base_max := (10 + roundi(3.0 * d)) if crowded else (5 + roundi(2.0 * d))
	var max_cust := maxi(2, roundi(float(base_max) * 0.62 * (0.85 + 0.15 * rate))) # kalabalık/kaos azaltıldı
	if _cust_cd > 0.0 or customers.get_child_count() >= max_cust:
		return
	_cust_cd = (randf_range(3.0, 4.6) if crowded else randf_range(6.5, 9.5)) * 1.6 * lerpf(1.0, 0.8, d) / maxf(rate, 0.3)
	var batch := randi_range(1, 2) if crowded else 1
	for _b in batch:
		if customers.get_child_count() >= max_cust:
			break
		_spawn_one_customer(crowded)


func _spawn_one_customer(crowded: bool) -> void:
	_cust_seq += 1
	# Rastgele Kuzey Kapısı veya Güney Kapısı (giriş/çıkış iki yönlü!)
	var from_north := randf() < 0.5
	var x_lane := randf_range(-3.1, -1.7) if randf() < 0.5 else randf_range(1.7, 3.1)
	var start_p := Vector3(x_lane, 0.0, -21.2 if from_north else 21.2)
	var exit_p := Vector3(randf_range(-3.0, 3.0), 0.0, 21.2 if from_north else -21.2)

	var arch := _roll_archetype(crowded)

	var item_pool := Produce.BASIC_ORDER.duplicate()
	if stalls:
		for ex in Produce.EXOTIC_ORDER:
			for st in stalls.get_children():
				if st.has_item(ex) and not (ex in item_pool):
					item_pool.append(ex)
					break
	if arch == CustomerScript.Archetype.VIP or arch == CustomerScript.Archetype.BARGAINER:
		for ex in Produce.EXOTIC_ORDER:
			if not (ex in item_pool):
				item_pool.append(ex)
	if active_event_item != "" and not (active_event_item in item_pool):
		item_pool.append(active_event_item)
	item_pool.shuffle()

	# İleriki günlerde müşteriler daha çok çeşit ister (daha seçici)
	var d := _difficulty()
	var n_types := 1 if randf() < 0.42 - 0.18 * d else (2 if randf() < 0.8 - 0.15 * d else 3)
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
		"day_num": day_num, "day_time": day_time, "day_ended": day_ended,
		"prices": wholesale_prices.duplicate(), "deal": deal_item,
		"event_item": active_event_item, "event_title": active_event_title, "event_timer": event_timer,
		"truck": wholesaler_node.export_snapshot() if wholesaler_node else {},
		"stalls": st_snaps, "players": pl_snaps, "customers": cu_snaps,
		"weather": weather, "thieves": _export_thieves(),
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
	if wholesaler_node:
		if snap.has("truck") and not (snap["truck"] as Dictionary).is_empty():
			wholesaler_node.apply_snapshot(snap["truck"])
		wholesaler_node.update_prices(wholesale_prices, deal_item, active_event_item)
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
				cd.get("exit", Vector3(0, 0, 21.2)), cd.get("wants", {}), int(cd.get("archetype", 0)))
			customers.add_child(c)
			c.apply_snapshot(cd)
	_apply_weather(str(snap.get("weather", "clear")), false)
	var ts = snap.get("thieves", [])
	if ts is Array:
		for td in ts:
			if td is Dictionary:
				var tn := str(td.get("name", ""))
				rpc_spawn_thief(tn, int(td.get("seed", 1)), td.get("pos", Vector3.ZERO),
					td.get("exit", Vector3(0, 0, 21.2)), int(td.get("target", 0)), false)
				var tnode := thieves.get_node_or_null(tn) if thieves else null
				if tnode and tnode.has_method("apply_snapshot"):
					tnode.call("apply_snapshot", td)
	if day_ended:
		rpc_day_ended(day_num)


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
	wholesaler_node = null
	players = null
	stalls = null
	customers = null
	thieves = null
	_stall_spots.clear()


func _back_to_menu() -> void:
	_clear_world()
	Sfx.set_ambience(false)
	if Sfx.has_method("set_weather_audio"):
		Sfx.call("set_weather_audio", "clear")
	_career_active = false
	tut_step = -1
	tut_panel.hide()
	rep_lbl.hide()
	career = _load_career()
	for t in toast_box.get_children():
		t.queue_free()
	_fade_in(0.5)
	speed_lines.intensity = 0.0
	if menu_ui:
		menu_ui.close_all_modals()
		menu_ui.update_crosshair(false, false)
	shop_wrap.hide()
	scoreboard_wrap.hide()
	summary_wrap.hide()
	hint.hide()
	hotbar_wrap.hide()
	if item_hint_lbl:
		item_hint_lbl.hide()
	if buff_box:
		buff_box.hide()
	voice_hud.hide()
	day_hud.hide()
	event_banner.hide()
	truck_banner.hide()
	money_hud.hide()
	money_pop.hide()
	interact_lbl.hide()
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu_bg == null:
		_set_menu_bg(true)
	SteamMgr.set_presence_menu()
	_show_page("lobby" if Net.online() else "main")
	if menu_ui:
		menu_ui.refresh_profile_card()
	_refresh()


# =====================================================================
# v0.6 BÜYÜK PAZAR: hava, kapkaççı, zorluk, kariyer, rehber
# =====================================================================

const TUT_STEPS := [
	["crate", "🚚 → 📦  Toptancıdan kasa al [E]"],
	["place", "🍅 Rafa bak, [Sol Tık] basılı tut: diz"],
	["price", "🏷️ Fiyat: [Tekerlek] ya da [Z] [X]"],
	["shout", "📣 Mikrofona bağır (mikrofon yoksa [B])"],
	["sell", "🤝 Müşteriye bak, [E]: sat"],
	["spray", "💦 🛒 Market → fısfıs, rafa [Sol Tık]"],
]


func _is_test_run() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--selftest" in args or "--mptest" in args or "--showcase" in args


func _is_host() -> bool:
	return (not Net.online()) or multiplayer.is_server()


func _my_id() -> int:
	return multiplayer.get_unique_id() if Net.online() else 1


func _my_player() -> Node:
	return players.get_node_or_null(str(_my_id())) if players else null


func _my_stall() -> Node:
	return stalls.get_node_or_null("Stall_%d" % _my_id()) if stalls else null


## 0.0 (Gün 1, yumuşak) .. 1.0 (Gün 7+, kalabalık & seçici & bol zabıta/kapkaççı)
func _difficulty() -> float:
	return clampf(float(day_num - 1) / 6.0, 0.0, 1.0)


func _day_flavor() -> String:
	var d := _difficulty()
	if day_num <= 1:
		return "Sakin bir gün: alışmak için birebir."
	if d < 0.5:
		return "Pazar ısınıyor: müşteriler biraz daha seçici!"
	return "Büyük pazar günü: kalabalık, kapkaççı ve zabıta bol!"


func _pop_in(wrap: Control) -> void:
	wrap.modulate.a = 0.0
	var tw := wrap.create_tween().set_parallel()
	tw.tween_property(wrap, "modulate:a", 1.0, 0.18)
	if wrap.get_child_count() > 0 and wrap.get_child(0).get_child_count() > 0:
		var panel := wrap.get_child(0).get_child(0) as Control
		if panel:
			panel.pivot_offset = panel.size * 0.5
			panel.scale = Vector2(0.94, 0.94)
			tw.tween_property(panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade_in(t: float) -> void:
	if fade_rect == null:
		return
	fade_rect.modulate.a = 1.0
	var tw := fade_rect.create_tween()
	tw.tween_property(fade_rect, "modulate:a", 0.0, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_quality(high: bool) -> void:
	for bz in [bazaar_node, menu_bg.get_child(0) if menu_bg and menu_bg.get_child_count() > 0 else null]:
		if bz and is_instance_valid(bz):
			if bz.has_method("apply_graphics_settings"):
				bz.call("apply_graphics_settings")
			elif bz.has_method("set_quality"):
				bz.call("set_quality", high)


func _apply_graphics_settings() -> void:
	_apply_quality(Settings.quality_high)


func _menu_music(on: bool) -> void:
	if Sfx.has_method("set_menu_music"):
		Sfx.call("set_menu_music", on)


func _rotate_menu_tip(dt: float) -> void:
	if tip_lbl == null or not ui.visible:
		return
	_tip_t += dt
	if _tip_t < 7.0:
		return
	_tip_t = 0.0
	_tip_i = (_tip_i + 1) % MENU_TIPS.size()
	var tw := tip_lbl.create_tween()
	tw.tween_property(tip_lbl, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): tip_lbl.text = MENU_TIPS[_tip_i])
	tw.tween_property(tip_lbl, "modulate:a", 0.75, 0.45)


# ---------- Gün başı (host) ----------

func _begin_day_host() -> void:
	if not _is_host():
		return
	var d := _difficulty()
	next_zabita_cd = (115.0 if day_num == 1 else lerpf(72.0, 48.0, d)) + randf_range(-6.0, 6.0)
	_next_thief_cd = randf_range(0.0, 20.0)
	_thief_spawned_today = 0
	var w := _roll_weather()
	if Net.online():
		rpc_set_weather.rpc(w, d)
	else:
		rpc_set_weather(w, d)


# ---------- Hava durumu ----------

func _roll_weather() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("weather=") and WEATHER.has(a.substr(8)):
			return a.substr(8)
	if day_num <= 1:
		return "clear" # ilk gün: ışıl ışıl, yumuşak başlangıç
	var total := 0
	for k in WEATHER:
		total += int(WEATHER[k]["w"])
	var r := randi_range(1, total)
	for k in WEATHER:
		r -= int(WEATHER[k]["w"])
		if r <= 0:
			return k
	return "clear"


@rpc("authority", "call_local", "reliable")
func rpc_set_weather(kind: String, diff := 0.0) -> void:
	if world:
		world.set_meta("difficulty", clampf(diff, 0.0, 1.0))
	_apply_weather(kind, true)


func _apply_weather(kind: String, announce: bool) -> void:
	if not WEATHER.has(kind):
		kind = "clear"
	weather = kind
	if world:
		world.set_meta("weather", kind)
	if bazaar_node and bazaar_node.has_method("set_weather"):
		bazaar_node.call("set_weather", kind)
	if Sfx.has_method("set_weather_audio"):
		Sfx.call("set_weather_audio", kind)
	# Hava durumu bildirimi kaldırıldı: HUD ikonu yeterli


# ---------- Müşteri tipi ----------

func _roll_archetype(crowded: bool) -> int:
	var d := _difficulty()
	var cs: Script = CustomerScript
	var cmap := cs.get_script_constant_map()
	var sw = cmap.get("SPAWN_WEIGHTS", null)
	if sw is Dictionary and not (sw as Dictionary).is_empty():
		var weights := {}
		var total := 0.0
		for k in sw:
			var w := maxf(float(sw[k]), 0.0)
			var a := int(k)
			if a == CustomerScript.Archetype.VIP and crowded:
				w *= 1.3
			elif a == CustomerScript.Archetype.IMPATIENT:
				w *= 1.0 + 0.35 * d
			elif a == CustomerScript.Archetype.BARGAINER:
				w *= 1.0 + 0.25 * d
			weights[a] = w
			total += w
		if total > 0.0:
			var r := randf() * total
			for a in weights:
				r -= float(weights[a])
				if r <= 0.0:
					return int(a)
	# Eski dağılım: %30 Teyze, %16 Aceleci, %12 VIP, %42 Normal (ileriki günler daha zorlu)
	var r2 := randf()
	if r2 < 0.30 + 0.06 * d:
		return CustomerScript.Archetype.BARGAINER # Pazar Teyzesi!
	elif r2 < 0.46 + 0.12 * d:
		return CustomerScript.Archetype.IMPATIENT
	elif r2 < 0.58 + 0.12 * d + (0.05 if crowded else 0.0):
		return CustomerScript.Archetype.VIP
	return CustomerScript.Archetype.NORMAL


# ---------- Kapkaççı ----------

func _get_thief_script() -> Script:
	if not _thief_checked:
		_thief_checked = true
		if ResourceLoader.exists(THIEF_PATH):
			var s = load(THIEF_PATH)
			if s is Script and (s as Script).can_instantiate():
				_thief_script = s
	return _thief_script


func _tick_thieves(dt: float, prog: float) -> void:
	if thieves == null or stalls == null or prog >= 0.9 or _get_thief_script() == null:
		return
	var d := _difficulty()
	if day_time < (120.0 if day_num == 1 else 30.0):
		return
	if day_num == 1 and _thief_spawned_today >= 1:
		return # ilk gün en fazla bir yaramaz çocuk
	_next_thief_cd -= dt
	if _next_thief_cd > 0.0:
		return
	var max_th := 1 if d < 0.5 else 2
	if thieves.get_child_count() >= max_th:
		_next_thief_cd = 8.0
		return
	var targets := []
	for st in stalls.get_children():
		if st.total_stock() > 0:
			targets.append(int(st.owner_id))
	if targets.is_empty():
		_next_thief_cd = 10.0
		return
	_next_thief_cd = randf_range(70.0, 110.0) * lerpf(1.0, 0.72, d)
	_thief_spawned_today += 1
	_thief_seq += 1
	var from_north := randf() < 0.5
	var start_p := Vector3(randf_range(-2.6, 2.6), 0.0, -21.2 if from_north else 21.2)
	var exit_p := Vector3(randf_range(-2.8, 2.8), 0.0, (21.2 if randf() < 0.6 else -21.2) * (1.0 if from_north else -1.0))
	var tname := "Thief_%d_%d" % [day_num, _thief_seq]
	var seed_val := randi_range(1, 9999)
	var target: int = targets.pick_random()
	if Net.online():
		rpc_spawn_thief.rpc(tname, seed_val, start_p, exit_p, target)
	else:
		rpc_spawn_thief(tname, seed_val, start_p, exit_p, target)


@rpc("authority", "call_local", "reliable")
func rpc_spawn_thief(tname: String, seed_val: int, start_p: Vector3, exit_p: Vector3, target_owner: int, announce := true) -> void:
	if thieves == null or tname == "" or thieves.has_node(tname):
		return
	var s := _get_thief_script()
	if s == null:
		return
	var t = s.new()
	if not (t is Node3D):
		if t is Node:
			t.free()
		return
	t.name = tname
	if t.has_method("init_thief"):
		t.call("init_thief", tname, seed_val, start_p, exit_p, target_owner)
	else:
		t.position = start_p
	t.set_meta("spawn_info", {"seed": seed_val, "exit": exit_p, "target": target_owner})
	thieves.add_child(t)
	if announce:
		show_toast("🕵️ Kapkaççı!" + (" Seni hedefliyor!" if target_owner == _my_id() else ""), Color(1.0, 0.55, 0.38))
		Sfx.play("whistle", -6.0)


func _export_thieves() -> Array:
	var out := []
	if thieves == null:
		return out
	for t in thieves.get_children():
		if t.is_queued_for_deletion():
			continue
		var info: Dictionary = t.get_meta("spawn_info", {})
		out.append({
			"name": str(t.name), "seed": int(info.get("seed", 1)), "pos": (t as Node3D).global_position,
			"exit": info.get("exit", Vector3(0, 0, 21.2)), "target": int(info.get("target", 0)),
			"state": int(t.get("thief_state")) if "thief_state" in t else 0,
			"carried": str(t.get("carried_item")) if "carried_item" in t else "",
		})
	return out


func _clear_thieves() -> void:
	if thieves:
		for t in thieves.get_children():
			t.queue_free()


func _reset_local_day_stats() -> void:
	qstats = {"earned": 0, "sold": 0, "catches": 0, "fined": false, "tips": 0}


func _my_reputation() -> float:
	var st := _my_stall()
	if st and "reputation" in st:
		return float(st.get("reputation"))
	return -1.0


func _evaluate_end_fines() -> void:
	var me := _my_player()
	if me and int(me.daily_fines) > 0:
		qstats["fined"] = true


## thief.gd rpc_on_caught her peer'da çağırır; yakalayan bensem sayaç artar.
func on_thief_caught_by(catcher_id: int) -> void:
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	if catcher_id != my_id:
		return
	qstats["catches"] = int(qstats.get("catches", 0)) + 1
	SteamMgr.unlock("ACH_THIEF_CATCH")
	show_toast("🕵️ Yakaladın!", GOOD)


## Para geliri geldiğinde yerel istatistikler.
func _track_income(sale: int, tip: int) -> void:
	if sale <= 0 and tip <= 0:
		return
	qstats["earned"] = int(qstats.get("earned", 0)) + sale + tip
	qstats["tips"] = int(qstats.get("tips", 0)) + tip
	if sale <= 0:
		return
	qstats["sold"] = int(qstats.get("sold", 0)) + 1


func _stock_map(st: Node) -> Dictionary:
	var m := {}
	if st == null or not ("slots" in st):
		return m
	for sl in st.slots:
		var it := str(sl.get("item", ""))
		if it != "":
			m[it] = int(m.get(it, 0)) + int(sl.get("count", 0))
	return m


# ---------- HUD (itibar, ipucu, rehber) ----------

func _stars(r: float) -> String:
	var n := clampi(roundi(r), 0, 5)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _update_meta_hud(dt: float, me: Node) -> void:
	if me == null:
		return
	_update_eyelids(me)
	var st := _my_stall()
	# Kapkaççıya bakış (yakalama ödülü tanıma)
	if me.has_method("_ray_target"):
		var area = me.call("_ray_target")
		if area is Area3D and str(area.get_meta("kind", "")) == "thief" \
				and (me as Node3D).global_position.distance_to((area as Area3D).global_position) < 3.8:
			_last_thief_look = Time.get_ticks_msec() / 1000.0
	# İtibar yıldızları
	var rep := _my_reputation()
	if rep >= 0.0:
		rep_lbl.show()
		rep_lbl.text = "%s  %.1f" % [_stars(rep), rep]
		rep_lbl.add_theme_color_override("font_color", GOOD if rep >= 4.0 else (BAD if rep < 1.5 else Color(1.0, 0.86, 0.36)))
		if _rep_shown >= 0.0 and roundi(rep) != roundi(_rep_shown):
			var up := rep > _rep_shown
			Sfx.play("rep_up" if up else "rep_down", -4.0)
			rep_lbl.pivot_offset = rep_lbl.size * Vector2(1.0, 0.5)
			rep_lbl.scale = Vector2(1.25, 1.25)
			rep_lbl.create_tween().tween_property(rep_lbl, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)
			show_toast("⭐ %s %s" % ["▲" if up else "▼", _stars(rep)], GOOD if up else BAD)
		_rep_shown = rep
	else:
		rep_lbl.hide()
	# Rehber
	if tut_step >= 0:
		_tut_cd -= dt
		if _tut_cd <= 0.0:
			_tut_cd = 0.15
			_tut_check(me, st)
	# Seçili eşya aksiyon ipucu + aktif Çay / Simit / Keyif güçlendirme rozetleri
	var hide_ui := _is_pause_or_modal_open() or shop_wrap.visible or day_ended
	if item_hint_lbl:
		var eq_id: String = str(me.equipped_item_id()) if me.has_method("equipped_item_id") else ""
		if eq_id != "" and Items.CATALOG.has(eq_id) and not hide_ui:
			var ci: Dictionary = Items.CATALOG[eq_id]
			var lh_t := str(ci.get("left_hint", ""))
			var rh_t := str(ci.get("right_hint", ""))
			item_hint_lbl.text = "[Sol] %s  •  [Sağ] %s  •  [0] cebe" % [lh_t, rh_t]
			item_hint_lbl.show()
		else:
			item_hint_lbl.hide()
	if buff_box and not buff_pills.is_empty():
		var tea_s := float(me.get("tea_buff")) if me.get("tea_buff") != null else 0.0
		var sim_s := float(me.get("simit_buff")) if me.get("simit_buff") != null else 0.0
		var smk_s := float(me.get("smoke_buff")) if me.get("smoke_buff") != null else 0.0
		var stk_s := float(me.get("stink_t")) if me.get("stink_t") != null else 0.0
		var any_b := false
		for entry: Array in [
			["tea", tea_s, "🍵 %d"],
			["simit", sim_s, "🥯 %d"],
			["smoke", smk_s, "🚬 %d"],
			["stink", stk_s, "🤢 %dsn"],
		]:
			var row: Array = buff_pills[str(entry[0])]
			var p: PanelContainer = row[0]
			var l: Label = row[1]
			var secs: float = float(entry[1])
			if secs > 0.1 and not hide_ui:
				l.text = str(entry[2]) % ceili(secs)
				p.show()
				any_b = true
			else:
				p.hide()
		buff_box.visible = any_b

	# Bağlamsal ipucu
	_hint_cd -= dt
	if _hint_cd <= 0.0:
		_hint_cd = 0.3
		var h := _context_hint(me, st)
		if h != hint.text:
			hint.text = h
			hint.modulate.a = 0.0
			hint.create_tween().tween_property(hint, "modulate:a", 0.9, 0.25)


func _context_hint(me: Node, st: Node) -> String:
	if tut_step >= 0:
		return "[H] geç  •  [ESC] ayarlar"
	if thieves and thieves.get_child_count() > 0:
		return "🕵️ Kapkaççı! [E] yakala"
	if bool(me.held_crate):
		return "Rafa [Sol Tık] diz  •  [Q] fırlat"
	if wholesaler_node and wholesaler_node.is_parked():
		return "🚚 %d kasa kaldı, çabuk ol!" % wholesaler_node.total_left()
	if st and st.total_stock() == 0:
		return "📦 Tezgah boş! 🚚 bekle"
	if st and st.has_method("get_item_freshness"):
		for it in _stock_map(st):
			if float(st.call("get_item_freshness", it)) < 0.45:
				return "🥀 Bayat → 💦 🛒 Market"
	return "🏪 Dükkanlar arka sokakta  •  [Tab] Skor  •  [ESC]"


# ---------- İlk açılış rehberi ----------

func _tut_start_if_needed() -> void:
	tut_step = -1
	tut_panel.hide()
	if Settings.tutorial_done or _is_test_run():
		return
	tut_step = 0
	_tut_enter()


func _restart_tutorial() -> void:
	Settings.tutorial_done = false
	Settings.save()
	_close_pause()
	if world:
		tut_step = 0
		_tut_enter()


func _tut_key() -> String:
	return str(TUT_STEPS[tut_step][0]) if tut_step >= 0 and tut_step < TUT_STEPS.size() else ""


func _tut_enter() -> void:
	# Su Fısfısı henüz yoksa (diğer modül) o adımı atla
	while _tut_key() == "spray" and not Items.CATALOG.has("spray"):
		tut_step += 1
	if tut_step >= TUT_STEPS.size():
		_tut_finish()
		return
	var st := _my_stall()
	var me := _my_player()
	_tut_prev_prices = _slot_prices(st)
	_tut_prev_fresh = _slot_fresh(st)
	_tut_sold_base = int(qstats.get("sold", 0))
	if me:
		me.set_meta("tut_prev_held", bool(me.held_crate))
	var total := TUT_STEPS.size() - (0 if Items.CATALOG.has("spray") else 1)
	tut_title.text = "🎓 %d/%d   [H] geç" % [tut_step + 1, total]
	tut_text.text = str(TUT_STEPS[tut_step][1])
	tut_panel.show()
	tut_panel.modulate.a = 0.0
	tut_panel.scale = Vector2(0.92, 0.92)
	var tw := tut_panel.create_tween().set_parallel()
	tw.tween_property(tut_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(tut_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _tut_advance(skipped: bool) -> void:
	if tut_step < 0:
		return
	Sfx.play("ui_click" if skipped else "quest_done", -6.0 if skipped else -4.0)
	tut_step += 1
	if tut_step >= TUT_STEPS.size():
		_tut_finish()
	else:
		_tut_enter()


func _tut_finish() -> void:
	tut_step = -1
	var tw := tut_panel.create_tween()
	tw.tween_property(tut_panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(tut_panel.hide)
	Settings.tutorial_done = true
	Settings.save()
	if not career.is_empty():
		career["tutorial_done"] = true
	show_toast("🎓 ✔", GOOD)


func _slot_prices(st: Node) -> Dictionary:
	var m := {}
	if st and "slots" in st:
		for i in st.slots.size():
			m[i] = [str(st.slots[i].get("item", "")), int(st.slots[i].get("price", 0))]
	return m


func _slot_fresh(st: Node) -> Dictionary:
	var m := {}
	if st and "slots" in st:
		for i in st.slots.size():
			m[i] = float(st.slots[i].get("fresh", 1.0))
	return m


func _tut_check(me: Node, st: Node) -> void:
	var ok := false
	match _tut_key():
		"crate":
			ok = bool(me.held_crate)
		"place":
			ok = st != null and st.total_stock() > 0
		"price":
			var cur := _slot_prices(st)
			for i in cur:
				if _tut_prev_prices.has(i):
					var a: Array = cur[i]
					var b: Array = _tut_prev_prices[i]
					if a[0] != "" and a[0] == b[0] and a[1] != b[1]:
						ok = true
			_tut_prev_prices = cur
		"shout":
			ok = float(me.get("shout_power")) > 0.4
		"sell":
			ok = int(qstats.get("sold", 0)) > _tut_sold_base
		"truck":
			var held := bool(me.held_crate)
			var was := bool(me.get_meta("tut_prev_held", false))
			me.set_meta("tut_prev_held", held)
			if held and not was and wholesaler_node and wholesaler_node.is_parked():
				ok = (me as Node3D).global_position.distance_to(wholesaler_node.global_position) < 9.0
		"spray":
			var cur_f := _slot_fresh(st)
			for i in cur_f:
				if float(cur_f[i]) > float(_tut_prev_fresh.get(i, 1.0)) + 0.08:
					ok = true
			_tut_prev_fresh = cur_f
	if ok:
		_tut_advance(false)


# ---------- Kariyer kaydı (solo) ----------

func _fresh_career() -> Dictionary:
	return {
		"version": CAREER_VERSION, "day_num": 0, "money": PlayerScript.STARTING_MONEY,
		"inventory": [], "upgrades": [], "expansion_level": 0, "has_radio": false, "reputation": 2.5,
		"best_day_profit": 0, "total_earned": 0, "tutorial_done": Settings.tutorial_done,
		"best_day_sold": 0, "thieves_caught": 0,
	}


static func _is_num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))


## Bozuk/elle oynanmış dosya: tür ve aralık kontrolü; geçersizse {} (yok say).
static func validate_career(d) -> Dictionary:
	if not (d is Dictionary):
		return {}
	for k in ["version", "day_num", "money"]:
		if not d.has(k) or not _is_num(d[k]):
			return {}
	if int(d["version"]) != CAREER_VERSION:
		return {}
	var day := int(d["day_num"])
	var money := int(d["money"])
	if day < 1 or day > 100000 or money < 0 or money > 10000000:
		return {}
	var out := {"version": CAREER_VERSION, "day_num": day, "money": money}
	# Envanter
	var inv := []
	var raw_inv = d.get("inventory", [])
	if not (raw_inv is Array) or (raw_inv as Array).size() > PlayerScript.INV_SIZE:
		return {}
	for sl in raw_inv:
		if not (sl is Dictionary):
			return {}
		if (sl as Dictionary).is_empty():
			inv.append({})
			continue
		var iid = sl.get("id", "")
		if not (iid is String) or not Items.CATALOG.has(iid):
			return {}
		if not _is_num(sl.get("uses", 1)) or not _is_num(sl.get("puffs", 0)):
			return {}
		var uses := int(sl.get("uses", 1))
		var puffs := int(sl.get("puffs", 0))
		if uses < 1 or uses > 999 or puffs < 0 or puffs > 999:
			return {}
		inv.append({"id": iid, "uses": uses, "puffs": puffs})
	out["inventory"] = inv
	# Tezgah geliştirmeleri
	var ups := []
	var raw_up = d.get("upgrades", [])
	if not (raw_up is Array):
		return {}
	for u in raw_up:
		if not (u is String) or not StallScript.UPGRADES.has(u):
			return {}
		if not (u in ups):
			ups.append(u)
	out["upgrades"] = ups
	var exp_lv = d.get("expansion_level", 0)
	if not _is_num(exp_lv):
		return {}
	out["expansion_level"] = clampi(int(exp_lv), 0, 2)
	for k in ["has_radio", "tutorial_done"]:
		var b = d.get(k, false)
		if typeof(b) != TYPE_BOOL:
			return {}
		out[k] = b
	var rep = d.get("reputation", 2.5)
	if not _is_num(rep) or float(rep) < 0.0 or float(rep) > 5.0:
		return {}
	out["reputation"] = float(rep)
	for k in ["best_day_profit", "total_earned", "best_day_sold", "thieves_caught"]:
		var v = d.get(k, 0)
		if not _is_num(v) or absf(float(v)) > 1.0e9:
			return {}
		out[k] = int(v)
	return out


static func read_career_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	if txt.is_empty() or txt.length() > 200000:
		return {}
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	return validate_career(j.data)


## Atomik yazım: önce .tmp, sonra yerine taşı. Taşıma yarıda kalırsa .tmp yüklemede kurtarılır.
static func write_career_file(path: String, d: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.flush()
	f.close()
	if validate_career(JSON.parse_string(FileAccess.get_file_as_string(tmp))).is_empty():
		return false
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	var abs_path := ProjectSettings.globalize_path(path)
	if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
		DirAccess.remove_absolute(abs_path)
		if DirAccess.rename_absolute(abs_tmp, abs_path) != OK:
			return false
	return true


func _load_career() -> Dictionary:
	var c := read_career_file(CAREER_PATH)
	if c.is_empty():
		c = read_career_file(CAREER_PATH + ".tmp") # yarıda kalmış kayıt kurtarma
	return c


func _apply_career(c: Dictionary) -> void:
	career = c.duplicate(true)
	day_num = int(c["day_num"]) + 1
	var me := players.get_node_or_null("1") if players else null
	var st := stalls.get_node_or_null("Stall_1") if stalls else null
	if me:
		me.money = int(c["money"])
		var inv: Array = c.get("inventory", [])
		for i in PlayerScript.INV_SIZE:
			if i < me.inventory.size():
				me.inventory[i] = (inv[i] as Dictionary).duplicate() if i < inv.size() else {}
		me.active_slot = -1
		if me.has_method("_refresh_equipped_visual"):
			me.call("_refresh_equipped_visual")
		me.inventory_changed.emit()
	if st:
		var ups := {}
		for u in c.get("upgrades", []):
			ups[u] = true
		var rep := float(c.get("reputation", 2.5))
		st.apply_snapshot({
			"expansion_level": int(c.get("expansion_level", 0)),
			"upgrades": ups, "has_radio": false,
			"radio_playing": false, "reputation": rep,
		})
		if st.has_method("set_reputation"):
			st.call("set_reputation", rep)
		elif "reputation" in st:
			st.set("reputation", rep)
	if bool(c.get("tutorial_done", false)) and not Settings.tutorial_done:
		Settings.tutorial_done = true
		Settings.save()


func _save_career_day_end() -> void:
	_new_records.clear()
	if not _career_active or Net.online() or career.is_empty():
		return
	var me := players.get_node_or_null("1") if players else null
	var st := stalls.get_node_or_null("Stall_1") if stalls else null
	if me == null or st == null:
		return
	var had_prev := int(career.get("day_num", 0)) > 0
	var c := career.duplicate(true)
	c["version"] = CAREER_VERSION
	c["day_num"] = day_num
	c["money"] = clampi(int(me.money), 0, 10000000)
	var inv := []
	for sl in me.inventory:
		if (sl as Dictionary).is_empty() or not Items.CATALOG.has(str(sl.get("id", ""))) or int(sl.get("uses", 0)) <= 0:
			inv.append({})
		else:
			inv.append({"id": str(sl["id"]), "uses": clampi(int(sl.get("uses", 1)), 1, 999), "puffs": clampi(int(sl.get("puffs", 0)), 0, 999)})
	c["inventory"] = inv
	var ups := []
	for k in StallScript.UPGRADE_ORDER:
		if st.has_upgrade(k):
			ups.append(k)
	c["upgrades"] = ups
	c["expansion_level"] = _expansion_level(st)
	c.erase("has_radio")
	var rep := _my_reputation()
	c["reputation"] = clampf(rep, 0.0, 5.0) if rep >= 0.0 else float(c.get("reputation", 2.5))
	c["total_earned"] = int(c.get("total_earned", 0)) + maxi(int(me.daily_revenue), 0)
	var profit := int(me.net_profit())
	var sold := int(me.daily_sold)
	if profit > int(c.get("best_day_profit", 0)):
		c["best_day_profit"] = profit
		if had_prev:
			_new_records.append("profit")
	if sold > int(c.get("best_day_sold", 0)):
		c["best_day_sold"] = sold
		if had_prev:
			_new_records.append("sold")
	c["thieves_caught"] = int(c.get("thieves_caught", 0)) + int(qstats.get("catches", 0))
	c["tutorial_done"] = Settings.tutorial_done
	if write_career_file(CAREER_PATH, c):
		career = c
		SteamMgr.cloud_save_file("career.json", CAREER_PATH)
	else:
		push_warning("Kariyer kaydedilemedi: " + CAREER_PATH)


# ---------- Tek Oyna sayfası ----------

func _open_solo_page() -> void:
	career = _load_career()
	_new_confirm = false
	if career.is_empty():
		solo_info.text = L10n.t("solo_no_save")
		solo_continue_btn.hide()
		solo_new_btn.text = L10n.t("solo_start_new")
	else:
		solo_info.text = L10n.t("solo_save_info", [
			int(career["day_num"]), int(career["money"]), int(career["best_day_profit"]), int(career["total_earned"]),
			float(career["reputation"]), int(career["thieves_caught"])])
		solo_continue_btn.show()
		solo_continue_btn.text = L10n.t("solo_continue", [int(career["day_num"]) + 1])
		solo_new_btn.text = L10n.t("solo_new")
	_show_page("solo")


func _continue_career() -> void:
	if career.is_empty():
		return
	_pending_career = career.duplicate(true)
	_start_solo()


func _new_career() -> void:
	if not career.is_empty() and not _new_confirm:
		_new_confirm = true
		solo_new_btn.text = L10n.t("solo_new_confirm")
		return
	_pending_career = {}
	_start_solo()


# ---------- Gün sonu özeti (sağ sütun) ----------

func _sum_line(text: String, size := 15, col := CREAM) -> Label:
	var l := _lbl(summary_side, text, size, 1.0)
	l.add_theme_color_override("font_color", col)
	return l


func _sum_head(text: String) -> void:
	var l := _sum_line(text, 16, GOLD)
	l.add_theme_font_override("font", _font(900))


func _build_summary_side() -> void:
	for c in summary_side.get_children():
		c.queue_free()
	var me := _my_player()
	if me == null:
		return
	var wi: Dictionary = WEATHER.get(weather, WEATHER["clear"])
	_sum_head("📊 SENİN GÜNÜN   %s %s" % [str(wi["icon"]), str(wi["name"])])
	_sum_line("💰 Ciro %d TL   •   Net kâr %+d TL" % [int(me.daily_revenue), int(me.net_profit())])
	_sum_line("📦 %d satış   •   ⭐ %d TL bahşiş   •   🚨 %d TL ceza" % [int(me.daily_sold), int(qstats.get("tips", 0)), int(me.daily_fines)])
	var extra := ""
	if _get_thief_script() != null:
		extra += "🕵️ %d kapkaççı" % int(qstats.get("catches", 0))
	var rep := _my_reputation()
	if rep >= 0.0:
		extra += ("   •   " if extra != "" else "") + _stars(rep)
	if extra != "":
		_sum_line(extra)
	if _career_active and not career.is_empty():
		_sum_head("🏅 REKORLAR")
		var rec := func(key: String, text: String):
			var nr: bool = key in _new_records
			_sum_line(("🆕 YENİ REKOR!  " if nr else "") + text, 15, GOLD if nr else CREAM)
		rec.call("profit", "En iyi gün kârı: %d TL" % int(career.get("best_day_profit", 0)))
		rec.call("sold", "En çok satış: %d" % int(career.get("best_day_sold", 0)))
		_sum_line("Toplam ciro: %d TL   •   💾 Gün %d kaydedildi" % [int(career.get("total_earned", 0)), int(career.get("day_num", day_num))], 14, Color(CREAM, 0.7))
		if not _new_records.is_empty():
			Sfx.play("cash_register", -3.0)
	var nd := day_num + 1
	var dn := clampf(float(nd - 1) / 6.0, 0.0, 1.0)
	var preview := "Yarın: biraz daha kalabalık ve seçici müşteriler." if dn < 0.5 else "Yarın: büyük pazar! Kapkaççı ve zabıta daha sık."
	_sum_line("➡ Gün %d — %s" % [nd, preview], 14, Color(1.0, 0.72, 0.42))
