extends Node
## Profesyonel Ana Menü, Herkese Açık Lobi Tarayıcısı + Oda Kodu, Oyun İçi Duraklatma Menüsü,
## 5 Sekmeli Detaylı PC Ayarları (canlı tuş atama + mikrofon testi), Oyuncu Sustur/At,
## Başarımlar Galerisi, Özel Nişangâh ve FPS Sayacı.
## main.gd tarafından başlatılır ve tüm menü / ayar etkileşimlerini temizçe yönetir.

const PlayerScript := preload("res://player.gd")
const GOLD := Color(1.0, 0.76, 0.32)
const TERRA := Color(0.82, 0.34, 0.16)
const TERRA_HI := Color(0.92, 0.42, 0.20)
const CREAM := Color(1.0, 0.95, 0.85)
const INK := Color(0.08, 0.05, 0.04)
const GOOD := Color(0.45, 0.96, 0.56)
const BAD := Color(1.0, 0.42, 0.36)
const CARD_BG := Color(0.075, 0.052, 0.042, 0.94)
const SUB_BG := Color(0.125, 0.085, 0.068, 0.92)

var main: Node = null
var layer: CanvasLayer = null
var theme: Theme = null

# Menü sayfaları (ana menü root'u)
var menu_root: Control
var pages := {}
var page := "main"
var info_lbl: Label
var invite_box: VBoxContainer
var tip_lbl: Label
var _tip_t := 0.0
var _tip_i := 0
var _new_confirm := false

# Ana menü dinamik etiketleri
var _main_career_lbl: Label
var _main_ach_lbl: Label
var _steam_pill_lbl: Label

# Tek oyna
var solo_info: Label
var solo_continue_btn: Button
var solo_new_btn: Button

# Lobi
var lobby_name_edit: LineEdit
var lobby_vis_opt: OptionButton
var lobby_host_btn: Button
var lobby_start_btn: Button
var lobby_leave_btn: Button
var lobby_code_lbl: Label
var lobby_copy_btn: Button
var lobby_join_code_edit: LineEdit
var lobby_members_box: VBoxContainer
var lobby_pub_box: VBoxContainer
var lobby_friends_box: VBoxContainer
var lobby_lan_ip: LineEdit
var _lobby_subtabs: Array[Button] = []
var _lobby_subpages: Array[Control] = []

# Modallar (oyun içi + menü üstü)
var pause_wrap: ColorRect
var _pause_code_row: HBoxContainer
var _pause_code_lbl: Label
var _pause_players_btn: Button
var _pause_leave_btn: Button

var players_wrap: ColorRect
var _players_list_box: VBoxContainer

var settings_wrap: ColorRect
var _set_tab_btns: Array[Button] = []
var _set_tab_pages: Array[Control] = []
var _set_active_tab := 0
var _rebind_action := ""
var _rebind_btns: Dictionary = {} # action -> Button
var _mic_test_bar: ColorRect
var _mic_test_lbl: Label
var _mic_cap_test: AudioEffectCapture
var _mic_test_player: AudioStreamPlayer

var ach_wrap: ColorRect
var _ach_progress_lbl: Label
var _ach_grid: GridContainer

# HUD yardımcıları
var fps_panel: PanelContainer
var fps_lbl: Label
var _fps_t := 0.0
var crosshair_ctrl: Control


## Özel çizimli nişangâh (Nokta / Artı / Halka + hedef vurgusu).
class CrosshairDraw extends Control:
	var has_target := false

	func _draw() -> void:
		var c := size * 0.5
		var s := Settings.crosshair_scale
		var col := Color(1.0, 0.86, 0.28, 0.98) if has_target else Color(1.0, 0.96, 0.88, 0.84)
		var out_c := Color(0.05, 0.03, 0.02, 0.72)
		match Settings.crosshair_style:
			1: # Artı (+)
				var gap := (4.0 if not has_target else 6.0) * s
				var arm := 7.0 * s
				var w := 2.2 * s
				for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
					draw_line(c + dir * gap, c + dir * (gap + arm), out_c, w + 2.0, true)
					draw_line(c + dir * gap, c + dir * (gap + arm), col, w, true)
				draw_circle(c, 1.5 * s, col)
			2: # Halka (○)
				var rad := (6.5 if not has_target else 8.5) * s
				draw_arc(c, rad, 0.0, TAU, 24, out_c, 3.6 * s, true)
				draw_arc(c, rad, 0.0, TAU, 24, col, 1.8 * s, true)
				draw_circle(c, 1.4 * s, col)
			_: # Nokta
				var r := (3.2 if not has_target else 4.4) * s
				draw_circle(c, r + 1.3, out_c)
				draw_circle(c, r, col)


func setup(p_main: Node, p_layer: CanvasLayer, p_theme: Theme) -> void:
	main = p_main
	layer = p_layer
	theme = p_theme
	_enhance_theme()
	_build_all()
	L10n.lang_changed.connect(_on_lang_changed)
	Net.lobby_list_updated.connect(_on_public_lobbies)
	Settings.ui_prefs_changed.connect(_refresh_hud_prefs)
	SteamMgr.achievement_unlocked.connect(_on_achievement_unlocked)
	SteamMgr.overlay_changed.connect(_on_steam_overlay)


func _enhance_theme() -> void:
	var primary_n := _sb(TERRA, 10, 12)
	primary_n.set_border_width_all(2)
	primary_n.border_color = Color(GOLD, 0.85)
	var primary_h := _sb(TERRA_HI, 10, 12)
	primary_h.set_border_width_all(2)
	primary_h.border_color = Color(1.0, 0.92, 0.55)
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", primary_n)
	theme.set_stylebox("hover", "PrimaryButton", primary_h)
	theme.set_stylebox("pressed", "PrimaryButton", _sb(Color(0.62, 0.24, 0.10), 10, 12))
	theme.set_stylebox("disabled", "PrimaryButton", _sb(Color(0.18, 0.13, 0.11, 0.65), 10, 12))
	theme.set_color("font_color", "PrimaryButton", Color.WHITE)
	theme.set_color("font_hover_color", "PrimaryButton", Color.WHITE)

	theme.set_type_variation("TabPill", "Button")
	var tn := _sb(Color(0.14, 0.095, 0.075, 0.9), 8, 8)
	tn.set_border_width_all(1)
	tn.border_color = Color(GOLD, 0.28)
	var th := _sb(Color(0.24, 0.15, 0.11, 0.96), 8, 8)
	th.set_border_width_all(1)
	th.border_color = Color(GOLD, 0.7)
	theme.set_stylebox("normal", "TabPill", tn)
	theme.set_stylebox("hover", "TabPill", th)
	theme.set_stylebox("pressed", "TabPill", primary_n)

	var le := _sb(Color(0.11, 0.075, 0.06, 0.96), 8, 8)
	le.set_border_width_all(2)
	le.border_color = Color(GOLD, 0.42)
	var le_f := _sb(Color(0.14, 0.095, 0.075, 0.98), 8, 8)
	le_f.set_border_width_all(2)
	le_f.border_color = GOLD
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", le_f)
	theme.set_color("font_color", "LineEdit", CREAM)
	theme.set_color("font_placeholder_color", "LineEdit", Color(CREAM, 0.42))


func _sb(c: Color, radius := 10, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _card_style(border_a := 0.58, bg := CARD_BG, radius := 16, margin := 20) -> StyleBoxFlat:
	var s := _sb(bg, radius, margin)
	s.set_border_width_all(2)
	s.border_color = Color(GOLD, border_a)
	s.shadow_color = Color(0, 0, 0, 0.48)
	s.shadow_size = 18
	s.shadow_offset = Vector2(0, 6)
	return s


var _font_cache := {}

func _font(weight := 700) -> SystemFont:
	if _font_cache.has(weight):
		return _font_cache[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Segoe UI Symbol", "Segoe UI Emoji", "Arial", "Sans-Serif"])
	f.font_weight = weight
	_font_cache[weight] = f
	return f


func _lbl(parent: Node, text: String, size := 16, alpha := 0.92, col := CREAM, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.modulate.a = alpha
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.72))
	parent.add_child(l)
	return l


func _title(parent: Node, text: String, size := 42, col := GOLD) -> Label:
	var l := _lbl(parent, text, size, 1.0, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_override("font", _font(900))
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(size / 7, 4))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.52))
	l.add_theme_constant_override("shadow_offset_y", maxi(size / 14, 2))
	return l


func _btn(parent: Node, text: String, cb: Callable, h := 42, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = h
	if primary:
		b.theme_type_variation = "PrimaryButton"
		b.add_theme_font_override("font", _font(800))
	b.pressed.connect(func(): Sfx.play("ui_click", -8.0); cb.call())
	parent.add_child(b)
	return b


func _nav_btn(parent: Node, text: String, cb: Callable, primary := false) -> Button:
	var b := _btn(parent, text, cb, 50 if primary else 44, primary)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 21 if primary else 18)
	b.add_theme_font_override("font", _font(800 if primary else 700))
	return b


func _sep(parent: Node, text := "") -> void:
	if text != "":
		var l := _lbl(parent, text, 13, 0.95, GOLD)
		l.add_theme_font_override("font", _font(900))
	var hs := HSeparator.new()
	hs.modulate = Color(GOLD, 0.35)
	parent.add_child(hs)


func _clear_children(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


# ---------------------------------------------------------------------------
# Tüm Menü ve Modalları Kurma
# ---------------------------------------------------------------------------

func _build_all() -> void:
	# Menü kök katmanı
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.theme = theme
	layer.add_child(menu_root)

	# Sol taraf sinematik vinyet (sağda canlı 3D pazar net görünür!)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.05, 0.03, 0.02, 0.90))
	grad.set_color(1, Color(0.05, 0.03, 0.02, 0.08))
	grad.add_point(0.46, Color(0.05, 0.03, 0.02, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(shade)

	_build_main_page()
	_build_solo_page()
	_build_lobby_page()

	# Alt durum + sürüm çubuğu (çakışmasız!)
	info_lbl = _lbl(menu_root, "", 15, 0.9, Color(1.0, 0.9, 0.68))
	info_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	info_lbl.offset_left = 590
	info_lbl.offset_right = -290
	info_lbl.offset_top = -52
	info_lbl.offset_bottom = -18
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var ver := _lbl(menu_root, L10n.t("ver_label", [Updater.version()]), 13, 0.65)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -280; ver.offset_right = -20; ver.offset_top = -44; ver.offset_bottom = -18
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	invite_box = VBoxContainer.new()
	invite_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	invite_box.offset_left = -380; invite_box.offset_right = -24; invite_box.offset_top = 156
	menu_root.add_child(invite_box)

	# Modallar (oyun içi HUD'ların üstünde!)
	_build_pause_modal()
	_build_players_modal()
	_build_settings_modal()
	_build_achievements_modal()
	_build_fps_counter()
	_build_crosshair()
	_refresh_hud_prefs()


func _make_page_root(key: String) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.hide()
	menu_root.add_child(c)
	pages[key] = c
	return c


func _build_main_page() -> void:
	var root := _make_page_root("main")

	# Sol ana cam kart
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(0.62, Color(0.075, 0.05, 0.038, 0.90), 18, 24))
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.offset_left = 54; card.offset_right = 548
	card.offset_top = -315; card.offset_bottom = 315
	root.add_child(card)

	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 9)
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(mv)

	# Üst başlık + hızlı TR/EN dil değiştirici
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	mv.add_child(top_bar)
	var sub := _lbl(top_bar, L10n.t("subtitle"), 12, 1.0, Color(1.0, 0.62, 0.32))
	sub.add_theme_font_override("font", _font(900))
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lang_btn := _btn(top_bar, "🌐 TR / EN", func():
		Settings.set_language("en" if L10n.lang == "tr" else "tr"), 28)
	lang_btn.custom_minimum_size.x = 98
	lang_btn.add_theme_font_size_override("font_size", 12)

	var logo := _title(mv, "BAZAR", 86, GOLD)
	logo.pivot_offset = Vector2(140, 48)
	var ltw := logo.create_tween().set_loops()
	ltw.tween_property(logo, "rotation", 0.015, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ltw.tween_property(logo, "rotation", -0.015, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var tag := _lbl(mv, L10n.t("tagline"), 14, 0.85)
	tag.add_theme_constant_override("line_spacing", 2)

	var sp0 := Control.new(); sp0.custom_minimum_size.y = 6; mv.add_child(sp0)
	_nav_btn(mv, "▶  " + L10n.t("btn_solo"), func(): main._open_solo_page(), true)
	_nav_btn(mv, "🌐  " + L10n.t("btn_multi"), func(): show_page("lobby"))
	var g_btn := _btn(mv, "", func(): pass, 40)
	var g_set := func():
		g_btn.text = "🧍  " + L10n.pick("Karakter: ", "Character: ") + (L10n.pick("Kadın", "Female") if PlayerScript.saved_gender() == 1 else L10n.pick("Erkek", "Male"))
	g_set.call()
	g_btn.pressed.connect(func():
		PlayerScript.save_gender(1 - PlayerScript.saved_gender())
		g_set.call())
	_nav_btn(mv, "⚙  " + L10n.t("btn_settings"), func(): open_settings(0))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	mv.add_child(row2)
	var b_ach := _btn(row2, "🏆  " + L10n.t("btn_achievements"), open_achievements, 40)
	b_ach.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b_crd := _btn(row2, "📜  " + L10n.pick("Lisanslar", "Credits"), func(): open_settings(4), 40)
	b_crd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_btn(mv, "✖  " + L10n.t("btn_quit"), func(): get_tree().quit())

	var sp1 := Control.new(); sp1.custom_minimum_size.y = 4; mv.add_child(sp1)
	var st_txt := L10n.t("steam_ok", [Net.my_name()]) if Net.steam_ok else L10n.t("steam_off")
	_steam_pill_lbl = _lbl(mv, st_txt, 12, 0.92, GOOD if Net.steam_ok else Color(1.0, 0.72, 0.42))
	tip_lbl = _lbl(mv, main.MENU_TIPS[0], 12, 0.78, Color(1.0, 0.88, 0.62))

	# Sağ üst özet profil kartı (Kariyer + Başarım özeti)
	var prof := PanelContainer.new()
	prof.add_theme_stylebox_override("panel", _card_style(0.45, Color(0.075, 0.05, 0.038, 0.84), 14, 14))
	prof.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	prof.offset_left = -330; prof.offset_right = -24; prof.offset_top = 24; prof.offset_bottom = 138
	root.add_child(prof)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 4)
	prof.add_child(pv)
	var pn := _lbl(pv, "🏪  " + Net.my_name(), 16, 1.0, GOLD)
	pn.add_theme_font_override("font", _font(800))
	_main_career_lbl = _lbl(pv, "", 13, 0.9)
	_main_ach_lbl = _lbl(pv, "", 13, 0.85, Color(1.0, 0.86, 0.42))
	refresh_profile_card()


func _build_solo_page() -> void:
	var root := _make_page_root("solo")
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.offset_left = 54; card.offset_right = 574
	card.offset_top = -230; card.offset_bottom = 230
	root.add_child(card)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 12)
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(sv)
	_title(sv, L10n.t("solo_title"), 40)
	_lbl(sv, L10n.t("solo_sub"), 14, 0.82)
	var inner := PanelContainer.new()
	inner.add_theme_stylebox_override("panel", _sb(SUB_BG, 12, 14))
	sv.add_child(inner)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 10)
	inner.add_child(sbox)
	solo_info = _lbl(sbox, "", 15, 1.0)
	solo_continue_btn = _btn(sbox, L10n.t("solo_continue"), func(): main._continue_career(), 50, true)
	solo_continue_btn.add_theme_font_size_override("font_size", 20)
	solo_new_btn = _btn(sbox, L10n.t("solo_new"), func(): main._new_career(), 42)
	_btn(sv, L10n.t("btn_back"), func(): show_page("main"), 40)


func _build_lobby_page() -> void:
	var root := _make_page_root("lobby")
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style(0.62, CARD_BG, 18, 20))
	card.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	card.custom_minimum_size = Vector2(690, 620)
	card.offset_left = 48; card.offset_right = 738
	card.offset_top = -310; card.offset_bottom = 310
	root.add_child(card)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	card.add_child(lv)
	_title(lv, L10n.t("lobby_title"), 34)
	_lbl(lv, L10n.t("lobby_sub"), 13, 0.80, CREAM, false)

	# 4 Alt Sekme: Lobi Kur / Açık Odalar / Arkadaşlar / Yerel LAN
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	lv.add_child(tab_row)
	_lobby_subtabs.clear()
	_lobby_subpages.clear()
	var tab_keys := ["lobby_tab_host", "lobby_tab_browse", "lobby_tab_friends", "lobby_tab_lan"]
	for i in tab_keys.size():
		var tb := _btn(tab_row, L10n.t(tab_keys[i]), _select_lobby_subtab.bind(i), 36)
		tb.theme_type_variation = "TabPill"
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 14)
		_lobby_subtabs.append(tb)

	# --- Subpage 0: Lobi Kur / Mevcut ---
	var p0 := VBoxContainer.new()
	p0.add_theme_constant_override("separation", 8)
	p0.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(p0)
	_lobby_subpages.append(p0)

	var cfg_row := HBoxContainer.new()
	cfg_row.add_theme_constant_override("separation", 8)
	p0.add_child(cfg_row)
	lobby_name_edit = LineEdit.new()
	lobby_name_edit.placeholder_text = Net.my_name() + L10n.pick(" Pazarı", "'s Bazaar")
	lobby_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cfg_row.add_child(lobby_name_edit)
	lobby_vis_opt = OptionButton.new()
	lobby_vis_opt.add_item(L10n.t("lobby_vis_public"))
	lobby_vis_opt.add_item(L10n.t("lobby_vis_friends"))
	lobby_vis_opt.custom_minimum_size.x = 220
	cfg_row.add_child(lobby_vis_opt)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	p0.add_child(act_row)
	lobby_host_btn = _btn(act_row, L10n.t("lobby_create"), func():
		Net.host_steam(lobby_vis_opt.selected == 0, lobby_name_edit.text), 42, true)
	lobby_host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_join_code_edit = LineEdit.new()
	lobby_join_code_edit.placeholder_text = L10n.t("lobby_join_code_ph")
	lobby_join_code_edit.max_length = 6
	lobby_join_code_edit.custom_minimum_size.x = 175
	act_row.add_child(lobby_join_code_edit)
	_btn(act_row, L10n.t("lobby_join_code_btn"), func(): Net.join_by_code(lobby_join_code_edit.text), 42)

	# Oda Kodu şeridi
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	p0.add_child(code_row)
	lobby_code_lbl = _lbl(code_row, "", 15, 1.0, GOLD)
	lobby_code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_copy_btn = _btn(code_row, L10n.t("lobby_copy_code"), func():
		if Net.lobby_code != "":
			DisplayServer.clipboard_set(Net.lobby_code)
			info_lbl.text = L10n.t("lobby_code_copied", [Net.lobby_code]), 32)
	lobby_copy_btn.hide()

	# Üye listesi kartı
	var mem_card := PanelContainer.new()
	mem_card.add_theme_stylebox_override("panel", _sb(SUB_BG, 10, 10))
	mem_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p0.add_child(mem_card)
	var mem_hold := Control.new()
	mem_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mem_hold.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mem_card.add_child(mem_hold)
	lobby_members_box = _make_tab_scroll(mem_hold)

	var bot0 := HBoxContainer.new()
	bot0.add_theme_constant_override("separation", 8)
	p0.add_child(bot0)
	lobby_start_btn = _btn(bot0, L10n.t("lobby_start"), func(): main._on_start(), 46, true)
	lobby_start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_start_btn.size_flags_stretch_ratio = 2.0
	lobby_leave_btn = _btn(bot0, L10n.t("lobby_leave"), func(): Net.leave(), 46)
	lobby_leave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Subpage 1: Herkese Açık Odalar ---
	var p1 := VBoxContainer.new()
	p1.add_theme_constant_override("separation", 8)
	p1.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p1.hide()
	lv.add_child(p1)
	_lobby_subpages.append(p1)
	_btn(p1, L10n.t("lobby_refresh"), func(): Net.request_public_lobbies(), 38, true)
	var pub_card := PanelContainer.new()
	pub_card.add_theme_stylebox_override("panel", _sb(SUB_BG, 10, 10))
	pub_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p1.add_child(pub_card)
	var pub_hold := Control.new()
	pub_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub_hold.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pub_card.add_child(pub_hold)
	lobby_pub_box = _make_tab_scroll(pub_hold)
	_lbl(lobby_pub_box, L10n.t("lobby_empty_pub"), 14, 0.72)

	# --- Subpage 2: Arkadaşlar ---
	var p2 := VBoxContainer.new()
	p2.add_theme_constant_override("separation", 8)
	p2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p2.hide()
	lv.add_child(p2)
	_lobby_subpages.append(p2)
	_btn(p2, L10n.t("lobby_refresh"), _refresh_friends_list, 38)
	var fr_card := PanelContainer.new()
	fr_card.add_theme_stylebox_override("panel", _sb(SUB_BG, 10, 10))
	fr_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p2.add_child(fr_card)
	var fr_hold := Control.new()
	fr_hold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fr_hold.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fr_card.add_child(fr_hold)
	lobby_friends_box = _make_tab_scroll(fr_hold)

	# --- Subpage 3: Yerel / LAN ---
	var p3 := VBoxContainer.new()
	p3.add_theme_constant_override("separation", 10)
	p3.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p3.hide()
	lv.add_child(p3)
	_lobby_subpages.append(p3)
	_lbl(p3, L10n.pick("Aynı bilgisayarda veya yerel ağda (LAN) port %d üzerinden doğrudan bağlan." % Net.local_port(),
		"Connect directly on the same PC or LAN over port %d." % Net.local_port()), 14, 0.82, CREAM, false)
	lobby_lan_ip = LineEdit.new()
	lobby_lan_ip.text = "127.0.0.1"
	lobby_lan_ip.placeholder_text = L10n.t("lan_ip_ph")
	p3.add_child(lobby_lan_ip)
	var lan_row := HBoxContainer.new()
	lan_row.add_theme_constant_override("separation", 10)
	p3.add_child(lan_row)
	var lh := _btn(lan_row, "🏠  " + L10n.t("lan_host"), func(): Net.host_local(); _select_lobby_subtab(0), 44, true)
	lh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lj := _btn(lan_row, "▶  " + L10n.t("lan_join"), func(): Net.join_local(lobby_lan_ip.text); _select_lobby_subtab(0), 44)
	lj.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_select_lobby_subtab(0)
	_btn(lv, L10n.t("btn_back"), func(): show_page("main"), 38)
	card.offset_top = -310; card.offset_bottom = 310
	card.set_deferred("size", Vector2(690, 620))


func _select_lobby_subtab(idx: int) -> void:
	for i in _lobby_subpages.size():
		_lobby_subpages[i].visible = i == idx
		_lobby_subtabs[i].theme_type_variation = "PrimaryButton" if i == idx else "TabPill"
	if idx == 1 and Net.steam_ok:
		Net.request_public_lobbies()
	elif idx == 2:
		_refresh_friends_list()


func _on_public_lobbies(lobbies: Array) -> void:
	if lobby_pub_box == null:
		return
	_clear_children(lobby_pub_box)
	if lobbies.is_empty():
		_lbl(lobby_pub_box, L10n.t("lobby_empty_pub"), 14, 0.72)
		return
	for d: Dictionary in lobbies:
		var rp := PanelContainer.new()
		rp.add_theme_stylebox_override("panel", _sb(Color(0.16, 0.11, 0.085, 0.95), 8, 8))
		lobby_pub_box.add_child(rp)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		rp.add_child(hb)
		var name_l := _lbl(hb, "🏪 %s  [%s]" % [str(d["name"]), str(d["code"])], 15, 1.0, CREAM)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cnt_l := _lbl(hb, "👥 %d/%d" % [int(d["players"]), int(d["max"])], 14, 0.9, GOLD)
		cnt_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		var jb := _btn(hb, L10n.pick("▶ Katıl", "▶ Join"), func(): Net.join_lobby(int(d["id"])), 32, true)
		jb.custom_minimum_size.x = 92


func _refresh_friends_list() -> void:
	if lobby_friends_box == null:
		return
	_clear_children(lobby_friends_box)
	if not Net.steam_ok:
		_lbl(lobby_friends_box, L10n.pick("Steam bağlı değil.", "Steam is offline."), 14, 0.75)
		return
	var list := Net.online_friends()
	if list.is_empty():
		_lbl(lobby_friends_box, L10n.t("lobby_empty_friends"), 14, 0.75)
		return
	for f in list:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		lobby_friends_box.add_child(hb)
		var nl := _lbl(hb, "● " + str(f[1]), 15, 1.0, GOOD)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if int(f[2]) != 0 and int(f[2]) != Net.lobby_id:
			_btn(hb, L10n.pick("▶ Katıl", "▶ Join"), Net.join_lobby.bind(int(f[2])), 32, true)
		if Net.lobby_id != 0:
			_btn(hb, L10n.pick("✉ Davet Et", "✉ Invite"), Net.invite_friend.bind(int(f[0]), str(f[1])), 32)


# ---------------------------------------------------------------------------
# Oyun İçi Duraklatma Menüsü (Ayarlardan Ayrı, Temiz!)
# ---------------------------------------------------------------------------

func _build_pause_modal() -> void:
	pause_wrap = ColorRect.new()
	pause_wrap.color = Color(0.02, 0.015, 0.012, 0.66)
	pause_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_wrap.theme = theme
	layer.add_child(pause_wrap)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_wrap.add_child(cc)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(430, 0)
	card.add_theme_stylebox_override("panel", _card_style(0.7, CARD_BG, 18, 24))
	cc.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var t := _title(v, L10n.t("pause_title"), 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_pause_code_row = HBoxContainer.new()
	_pause_code_row.add_theme_constant_override("separation", 8)
	v.add_child(_pause_code_row)
	_pause_code_lbl = _lbl(_pause_code_row, "", 14, 0.95, GOLD)
	_pause_code_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(_pause_code_row, L10n.t("lobby_copy_code"), func():
		if Net.lobby_code != "":
			DisplayServer.clipboard_set(Net.lobby_code)
			main.show_toast(L10n.t("lobby_code_copied", [Net.lobby_code]), GOLD), 30)

	_btn(v, L10n.t("btn_resume"), close_all_modals, 48, true)
	_btn(v, "⚙  " + L10n.t("btn_settings"), func(): open_settings(0), 44)
	_pause_players_btn = _btn(v, L10n.t("btn_players"), open_players_modal, 42)
	_btn(v, L10n.t("btn_restart_tut"), func(): main._restart_tutorial(), 40)
	var hs := HSeparator.new(); hs.modulate = Color(GOLD, 0.3); v.add_child(hs)
	_pause_leave_btn = _btn(v, L10n.t("btn_leave_menu"), func(): Net.leave(), 40)
	_btn(v, L10n.t("btn_quit_game"), func(): get_tree().quit(), 38)
	pause_wrap.hide()


# ---------------------------------------------------------------------------
# Oyuncular & Sesli Sohbet Modalı (Mute / Kick)
# ---------------------------------------------------------------------------

func _build_players_modal() -> void:
	players_wrap = ColorRect.new()
	players_wrap.color = Color(0.02, 0.015, 0.012, 0.72)
	players_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	players_wrap.theme = theme
	layer.add_child(players_wrap)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	players_wrap.add_child(cc)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 400)
	card.add_theme_stylebox_override("panel", _card_style())
	cc.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var tl := _title(v, L10n.t("players_title"), 26)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_players_list_box = VBoxContainer.new()
	_players_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_players_list_box.add_theme_constant_override("separation", 8)
	sc.add_child(_players_list_box)
	_btn(v, L10n.t("btn_back"), func(): players_wrap.hide(); pause_wrap.show(), 40)
	players_wrap.hide()


func open_players_modal() -> void:
	pause_wrap.hide()
	_refresh_players_modal()
	players_wrap.show()
	_pop_in(players_wrap)


func _refresh_players_modal() -> void:
	_clear_children(_players_list_box)
	var my_id := multiplayer.get_unique_id() if Net.online() else 1
	var am_host := (not Net.online()) or multiplayer.is_server()
	var ids: Array = Net.names.keys() if not Net.names.is_empty() else [1]
	ids.sort()
	for pid_v in ids:
		var pid := int(pid_v)
		var rp := PanelContainer.new()
		rp.add_theme_stylebox_override("panel", _sb(SUB_BG, 8, 8))
		_players_list_box.add_child(rp)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		rp.add_child(hb)
		var tag := (" " + L10n.t("host_badge") if pid == 1 else "") + (" " + L10n.t("you_badge") if pid == my_id else "")
		var nl := _lbl(hb, Net.display_name(pid) + tag, 16, 1.0, GOLD if pid == 1 else CREAM)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if pid != my_id:
			var muted := Settings.is_peer_muted(pid)
			_btn(hb, L10n.t("btn_unmute") if muted else L10n.t("btn_mute"), func():
				Settings.set_peer_muted(pid, not Settings.is_peer_muted(pid))
				_refresh_players_modal(), 34)
			if am_host and Net.online():
				_btn(hb, L10n.t("btn_kick"), func():
					Net.kick_peer(pid)
					_refresh_players_modal(), 34)


# ---------------------------------------------------------------------------
# 5 Sekmeli Detaylı PC Ayarları
# ---------------------------------------------------------------------------

func _build_settings_modal() -> void:
	settings_wrap = ColorRect.new()
	settings_wrap.color = Color(0.02, 0.015, 0.012, 0.76)
	settings_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_wrap.theme = theme
	layer.add_child(settings_wrap)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_wrap.add_child(cc)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(960, 610)
	card.add_theme_stylebox_override("panel", _card_style(0.7, CARD_BG, 18, 22))
	cc.add_child(card)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 12)
	card.add_child(root_v)

	var hdr := HBoxContainer.new()
	root_v.add_child(hdr)
	var st := _title(hdr, "⚙  " + L10n.t("set_title"), 30)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Sekme çubuğu
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	root_v.add_child(tabs)
	_set_tab_btns.clear()
	_set_tab_pages.clear()
	_rebind_btns.clear()
	var tkeys := ["tab_display", "tab_audio", "tab_controls", "tab_gameplay", "tab_credits"]
	for i in tkeys.size():
		var tb := _btn(tabs, L10n.t(tkeys[i]), _select_settings_tab.bind(i), 38)
		tb.theme_type_variation = "TabPill"
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_font_size_override("font_size", 14)
		_set_tab_btns.append(tb)

	# İçerik alanı (kaydırılabilir)
	var body_card := PanelContainer.new()
	body_card.add_theme_stylebox_override("panel", _sb(SUB_BG, 12, 16))
	body_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(body_card)

	var body_stack := Control.new()
	body_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_card.add_child(body_stack)

	_set_tab_pages.append(_build_tab_display(body_stack))
	_set_tab_pages.append(_build_tab_audio(body_stack))
	_set_tab_pages.append(_build_tab_controls(body_stack))
	_set_tab_pages.append(_build_tab_gameplay(body_stack))
	_set_tab_pages.append(_build_tab_credits(body_stack))

	# Alt butonlar
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root_v.add_child(footer)
	_btn(footer, L10n.t("btn_reset_defaults"), _reset_current_tab_defaults, 42)
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; footer.add_child(spacer)
	var save_b := _btn(footer, L10n.t("btn_apply_close"), close_settings, 44, true)
	save_b.custom_minimum_size.x = 220

	_select_settings_tab(0)
	settings_wrap.hide()


func _make_tab_scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	sc.add_child(vb)
	return vb


func _setting_row(parent: Node, label_txt: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	parent.add_child(hb)
	var l := _lbl(hb, label_txt, 15, 0.94)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return hb


func _slider_row(parent: Node, label_txt: String, min_v: float, max_v: float, step: float, cur_v: float, fmt: Callable, cb: Callable) -> HSlider:
	var hb := _setting_row(parent, label_txt)
	var val_l := _lbl(hb, str(fmt.call(cur_v)), 14, 1.0, GOLD)
	val_l.custom_minimum_size.x = 68
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	var sl := HSlider.new()
	sl.min_value = min_v; sl.max_value = max_v; sl.step = step; sl.value = cur_v
	sl.custom_minimum_size.x = 260
	sl.value_changed.connect(func(v: float):
		val_l.text = str(fmt.call(v))
		cb.call(v))
	hb.add_child(sl)
	return sl


func _opt_row(parent: Node, label_txt: String, items: Array, cur_idx: int, cb: Callable) -> OptionButton:
	var hb := _setting_row(parent, label_txt)
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(280, 36)
	for it in items:
		opt.add_item(str(it))
	opt.selected = clampi(cur_idx, 0, maxi(items.size() - 1, 0))
	opt.item_selected.connect(func(i: int): Sfx.play("ui_click", -10.0); cb.call(i))
	hb.add_child(opt)
	return opt


func _chk_row(parent: Node, label_txt: String, cur_v: bool, cb: Callable) -> CheckButton:
	var hb := _setting_row(parent, label_txt)
	var chk := CheckButton.new()
	chk.button_pressed = cur_v
	chk.toggled.connect(func(on: bool): Sfx.play("ui_click", -10.0); cb.call(on))
	hb.add_child(chk)
	return chk


func _build_tab_display(parent: Control) -> Control:
	var vb := _make_tab_scroll(parent)
	_sep(vb, L10n.t("sec_display"))
	_opt_row(vb, L10n.t("lbl_win_mode"), [L10n.t("mode_windowed"), L10n.t("mode_fullscreen"), L10n.t("mode_borderless")], Settings.mode, func(i):
		Settings.mode = i; Settings.apply_display(); Settings.save())
	var res_names := []
	for r: Vector2i in Settings.RESOLUTIONS:
		res_names.append("%d × %d" % [r.x, r.y])
	_opt_row(vb, L10n.t("lbl_res"), res_names, Settings.resolution, func(i):
		Settings.resolution = i; Settings.apply_display(); Settings.save())
	_opt_row(vb, L10n.t("lbl_vsync"), [L10n.t("opt_off"), L10n.t("opt_on"), L10n.t("opt_adaptive")], Settings.vsync, func(i):
		Settings.vsync = i; Settings.apply_display(); Settings.save())
	var fps_names := [L10n.t("opt_unlimited"), "60 FPS", "120 FPS", "144 FPS", "240 FPS"]
	_opt_row(vb, L10n.t("lbl_fps_cap"), fps_names, Settings.fps_cap_idx, func(i):
		Settings.fps_cap_idx = i; Settings.apply_display(); Settings.save())

	_sep(vb, L10n.t("sec_graphics"))
	_opt_row(vb, L10n.t("lbl_preset"), [L10n.t("opt_low"), L10n.t("opt_med"), L10n.t("opt_high")], Settings.quality_level, func(i):
		Settings.set_quality_preset(i)
		_rebuild_settings_only())
	_opt_row(vb, L10n.t("lbl_msaa"), [L10n.t("opt_off") + " (FXAA)", "2x MSAA", "4x MSAA"], Settings.msaa, func(i):
		Settings.msaa = i; Settings.apply_graphics(); Settings.save())
	_opt_row(vb, L10n.t("lbl_shadows"), [L10n.t("opt_low"), L10n.t("opt_med"), L10n.t("opt_high")], Settings.shadows_level, func(i):
		Settings.shadows_level = i; Settings.apply_graphics(); Settings.save())
	_slider_row(vb, L10n.t("lbl_render_scale"), 0.75, 1.0, 0.05, Settings.render_scale,
		func(v): return "%d%%" % roundi(v * 100.0),
		func(v): Settings.render_scale = v; Settings.apply_graphics(); Settings.save())
	_chk_row(vb, L10n.t("lbl_ssao"), Settings.ssao_enabled, func(on):
		Settings.ssao_enabled = on; Settings.apply_graphics(); Settings.save())
	_chk_row(vb, L10n.t("lbl_glow"), Settings.glow_enabled, func(on):
		Settings.glow_enabled = on; Settings.apply_graphics(); Settings.save())
	_chk_row(vb, L10n.t("lbl_volfog"), Settings.vol_fog_enabled, func(on):
		Settings.vol_fog_enabled = on; Settings.apply_graphics(); Settings.save())

	_sep(vb, L10n.t("sec_camera_acc"))
	_slider_row(vb, L10n.t("lbl_fov"), 65.0, 105.0, 1.0, Settings.fov,
		func(v): return "%d°" % roundi(v),
		func(v): Settings.fov = v; Settings.save())
	_chk_row(vb, L10n.t("lbl_show_fps"), Settings.show_fps, func(on):
		Settings.show_fps = on; Settings.ui_prefs_changed.emit(); Settings.save())
	_chk_row(vb, L10n.t("lbl_reduce_motion"), Settings.reduce_motion, func(on):
		Settings.reduce_motion = on; Settings.save())
	return vb.get_parent() as Control


func _build_tab_audio(parent: Control) -> Control:
	var vb := _make_tab_scroll(parent)
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	_sep(vb, L10n.t("sec_volumes"))
	_slider_row(vb, L10n.t("lbl_master"), 0.0, 1.0, 0.02, Settings.volume, pct, func(v): Settings.volume = v; Settings.apply_audio(); Settings.save())
	_slider_row(vb, L10n.t("lbl_sfx"), 0.0, 1.0, 0.02, Settings.sfx_vol, pct, func(v): Settings.sfx_vol = v; Settings.apply_audio(); Settings.save())
	_slider_row(vb, L10n.t("lbl_music"), 0.0, 1.0, 0.02, Settings.music_vol, pct, func(v): Settings.music_vol = v; Settings.apply_audio(); Settings.save())
	_slider_row(vb, L10n.t("lbl_amb"), 0.0, 1.0, 0.02, Settings.ambience_vol, pct, func(v): Settings.ambience_vol = v; Settings.apply_audio(); Settings.save())
	_slider_row(vb, L10n.t("lbl_voice"), 0.0, 1.0, 0.02, Settings.voice_vol, pct, func(v): Settings.voice_vol = v; Settings.apply_audio(); Settings.save())

	_sep(vb, L10n.t("sec_voice"))
	var devs := Array(AudioServer.get_input_device_list()) if DisplayServer.get_name() != "headless" else ["Default"]
	if devs.is_empty():
		devs = ["Default"]
	var cur_dev := maxi(devs.find(Settings.mic_device), 0)
	_opt_row(vb, L10n.t("lbl_mic_dev"), devs, cur_dev, func(i):
		Settings.mic_device = str(devs[i]); Settings.apply_audio(); Settings.save())
	_opt_row(vb, L10n.t("lbl_voice_mode"), [L10n.t("opt_vad"), L10n.t("opt_ptt") + " [%s]" % Settings.key_label("ptt")], Settings.voice_mode, func(i):
		Settings.voice_mode = i; Settings.audio_changed.emit(); Settings.save())
	_slider_row(vb, L10n.t("lbl_mic_gain"), 0.5, 2.5, 0.05, Settings.mic_gain, pct, func(v): Settings.mic_gain = v; Settings.save())
	_slider_row(vb, L10n.t("lbl_mic_gate"), -55.0, -20.0, 1.0, Settings.mic_threshold_db,
		func(v): return "%d dB" % roundi(v),
		func(v): Settings.mic_threshold_db = v; Settings.save())

	# Canlı mikrofon seviye çubuğu
	var mrow := _setting_row(vb, L10n.t("lbl_mic_test"))
	_mic_test_lbl = _lbl(mrow, "-60 dB", 13, 0.85, GOLD)
	_mic_test_lbl.custom_minimum_size.x = 64
	_mic_test_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bg := ColorRect.new()
	bg.custom_minimum_size = Vector2(260, 18)
	bg.color = Color(0.06, 0.04, 0.035, 0.96)
	mrow.add_child(bg)
	_mic_test_bar = ColorRect.new()
	_mic_test_bar.color = GOOD
	_mic_test_bar.size = Vector2(0, 18)
	bg.add_child(_mic_test_bar)
	return vb.get_parent() as Control


func _build_tab_controls(parent: Control) -> Control:
	var vb := _make_tab_scroll(parent)
	_sep(vb, L10n.t("sec_mouse_pad"))
	_slider_row(vb, L10n.t("lbl_mouse_sens"), 0.2, 3.0, 0.05, Settings.mouse_sens,
		func(v): return "%.2fx" % v,
		func(v): Settings.mouse_sens = v; Settings.save())
	_chk_row(vb, L10n.t("lbl_invert_y"), Settings.invert_y, func(on):
		Settings.invert_y = on; Settings.save())
	_slider_row(vb, L10n.t("lbl_pad_sens"), 0.5, 3.0, 0.05, Settings.gamepad_sens,
		func(v): return "%.2fx" % v,
		func(v): Settings.gamepad_sens = v; Settings.save())
	_slider_row(vb, L10n.t("lbl_pad_dz"), 0.08, 0.35, 0.01, Settings.gamepad_deadzone,
		func(v): return "%d%%" % roundi(v * 100.0),
		func(v): Settings.gamepad_deadzone = v; Settings.apply_keybinds(); Settings.save())

	_sep(vb, L10n.t("sec_keybinds"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for act: String in Settings.KEYBIND_ORDER:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 8)
		grid.add_child(cell)
		var al := _lbl(cell, L10n.t("act_" + act), 14, 0.92)
		al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kb := _btn(cell, Settings.key_label(act), _begin_rebind.bind(act), 32)
		kb.custom_minimum_size.x = 120
		kb.add_theme_font_size_override("font_size", 13)
		_rebind_btns[act] = kb
	return vb.get_parent() as Control


func _begin_rebind(act: String) -> void:
	_cancel_rebind()
	_rebind_action = act
	var b: Button = _rebind_btns.get(act)
	if b:
		b.text = L10n.t("press_any_key")
		b.theme_type_variation = "PrimaryButton"


func _cancel_rebind() -> void:
	if _rebind_action == "":
		return
	var b: Button = _rebind_btns.get(_rebind_action)
	if b:
		b.text = Settings.key_label(_rebind_action)
		b.theme_type_variation = ""
	_rebind_action = ""


func _refresh_rebind_labels() -> void:
	for act: String in _rebind_btns:
		var b: Button = _rebind_btns[act]
		if is_instance_valid(b):
			b.text = Settings.key_label(act)
			b.theme_type_variation = ""


func _build_tab_gameplay(parent: Control) -> Control:
	var vb := _make_tab_scroll(parent)
	_sep(vb, L10n.t("sec_lang_hud"))
	_opt_row(vb, L10n.t("lbl_lang"), ["🇹🇷 Türkçe", "🇬🇧 English"], 1 if Settings.lang == "en" else 0, func(i):
		Settings.set_language("en" if i == 1 else "tr"))
	_opt_row(vb, L10n.t("lbl_crosshair"), [L10n.t("ch_dot"), L10n.t("ch_cross"), L10n.t("ch_ring")], Settings.crosshair_style, func(i):
		Settings.crosshair_style = i; Settings.ui_prefs_changed.emit(); Settings.save())
	_slider_row(vb, L10n.t("lbl_crosshair_sz"), 0.7, 1.6, 0.05, Settings.crosshair_scale,
		func(v): return "%d%%" % roundi(v * 100.0),
		func(v): Settings.crosshair_scale = v; Settings.ui_prefs_changed.emit(); Settings.save())
	_chk_row(vb, L10n.t("lbl_show_hints"), Settings.show_hints, func(on):
		Settings.show_hints = on; Settings.ui_prefs_changed.emit(); Settings.save())
	var row_t := _setting_row(vb, L10n.t("btn_restart_tut"))
	_btn(row_t, "🎓  " + L10n.pick("Sıfırla", "Reset"), func(): main._restart_tutorial(), 36)
	return vb.get_parent() as Control


func _build_tab_credits(parent: Control) -> Control:
	var vb := _make_tab_scroll(parent)
	_sep(vb, L10n.pick("BAZAR — TÜRK SEMT PAZARI", "BAZAR — TURKISH STREET BAZAAR"))
	_lbl(vb, L10n.pick("Geliştirici & Tasarım:", "Developers & Design:"), 14, 0.94)
	for dev: Array in [["bagatarhansinan", "https://github.com/bagatarhansinan"], ["Obuto45", "https://github.com/Obuto45"]]:
		var lb := LinkButton.new()
		lb.text = "%s — %s" % dev
		lb.uri = str(dev[1])
		lb.add_theme_font_size_override("font_size", 14)
		vb.add_child(lb)
	_lbl(vb, L10n.pick(
		"Oyun Motoru: Godot Engine 4.7 (MIT License) + Jolt Physics (MIT License)
Çok Oyunculu Ağ: GodotSteam (MIT License) & Valve Steamworks SDK",
		"Engine: Godot Engine 4.7 (MIT License) + Jolt Physics (MIT License)
Networking: GodotSteam (MIT License) & Valve Steamworks SDK"
	), 14, 0.94)
	_sep(vb, L10n.pick("SES & MÜZİK LİSANSLARI (ATIFLAR)", "AUDIO & MUSIC LICENSES (ATTRIBUTIONS)"))
	_lbl(vb,
		"• Breaking Bottle (audio/sfx/glass_shatter.ogg)\n" +
		"  Author: spookymodem — CC-BY 3.0 (https://creativecommons.org/licenses/by/3.0/)\n" +
		"  Source: https://opengameart.org/content/breaking-bottle\n\n" +
		"• Arabesk Radio Tracks (audio/radio/*.ogg)\n" +
		"  Pixabay Content License (KeopsRa, _yamanmp_)\n" +
		"  See audio/radio/KAYNAKLAR.md for full track list & sources.\n\n" +
		"• Procedural SFX & Synth Ambience\n" +
		"  Generated in-engine via sfx.gd; 3D Props crafted in Blender 5.3.",
		13, 0.88)
	return vb.get_parent() as Control


func _select_settings_tab(idx: int) -> void:
	_cancel_rebind()
	_set_active_tab = clampi(idx, 0, _set_tab_pages.size() - 1)
	for i in _set_tab_pages.size():
		_set_tab_pages[i].visible = i == _set_active_tab
		_set_tab_btns[i].theme_type_variation = "PrimaryButton" if i == _set_active_tab else "TabPill"
	_ensure_mic_test(_set_active_tab == 1 and settings_wrap.visible)


func _reset_current_tab_defaults() -> void:
	match _set_active_tab:
		0:
			Settings.mode = 0; Settings.resolution = 0; Settings.vsync = 1; Settings.fps_cap_idx = 0
			Settings.fov = 78.0; Settings.show_fps = false; Settings.reduce_motion = false
			Settings.set_quality_preset(2)
			Settings.apply_display()
		1:
			Settings.volume = 0.85; Settings.sfx_vol = 0.90; Settings.music_vol = 0.75
			Settings.ambience_vol = 0.80; Settings.voice_vol = 1.0
			Settings.voice_mode = 0; Settings.mic_gain = 1.0; Settings.mic_threshold_db = -42.0
			Settings.apply_audio()
		2:
			Settings.reset_controls_defaults()
		3:
			Settings.crosshair_style = 0; Settings.crosshair_scale = 1.0; Settings.show_hints = true
			Settings.ui_prefs_changed.emit()
	Settings.save()
	_rebuild_settings_only()


func _rebuild_settings_only() -> void:
	var keep_tab := _set_active_tab
	var was_vis := settings_wrap.visible
	_ensure_mic_test(false)
	settings_wrap.queue_free()
	_build_settings_modal()
	_select_settings_tab(keep_tab)
	if was_vis:
		settings_wrap.show()
		_ensure_mic_test(keep_tab == 1)


# ---------------------------------------------------------------------------
# Başarımlar Galerisi
# ---------------------------------------------------------------------------

func _build_achievements_modal() -> void:
	ach_wrap = ColorRect.new()
	ach_wrap.color = Color(0.02, 0.015, 0.012, 0.76)
	ach_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	ach_wrap.theme = theme
	layer.add_child(ach_wrap)

	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	ach_wrap.add_child(cc)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(880, 560)
	card.add_theme_stylebox_override("panel", _card_style())
	cc.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var tl := _title(v, L10n.t("ach_title"), 32)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_progress_lbl = _lbl(v, "", 15, 0.92, GOLD)
	_ach_progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_ach_grid = GridContainer.new()
	_ach_grid.columns = 2
	_ach_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_grid.add_theme_constant_override("h_separation", 10)
	_ach_grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(_ach_grid)
	_btn(v, L10n.t("btn_close"), func(): ach_wrap.hide(), 42)
	ach_wrap.hide()


func open_achievements() -> void:
	_clear_children(_ach_grid)
	_ach_progress_lbl.text = L10n.t("ach_progress", [SteamMgr.unlocked_count(), SteamMgr.ACHIEVEMENTS.size()])
	for a: Dictionary in SteamMgr.ACHIEVEMENTS:
		var got := SteamMgr.is_unlocked(str(a["id"]))
		var rp := PanelContainer.new()
		rp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := _sb(Color(0.20, 0.14, 0.08, 0.96) if got else Color(0.10, 0.075, 0.065, 0.72), 10, 10)
		sb.set_border_width_all(2 if got else 1)
		sb.border_color = GOLD if got else Color(GOLD, 0.18)
		rp.add_theme_stylebox_override("panel", sb)
		_ach_grid.add_child(rp)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		rp.add_child(hb)
		var ic := _lbl(hb, str(a["icon"]) if got else "🔒", 26, 1.0 if got else 0.45)
		ic.autowrap_mode = TextServer.AUTOWRAP_OFF
		var tx := VBoxContainer.new()
		tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(tx)
		var nm := _lbl(tx, L10n.pick(str(a["tr"]), str(a["en"])), 15, 1.0 if got else 0.55, GOLD if got else CREAM)
		nm.add_theme_font_override("font", _font(800))
		_lbl(tx, L10n.pick(str(a["tr_d"]), str(a["en_d"])), 12, 0.85 if got else 0.45)
	ach_wrap.show()
	_pop_in(ach_wrap)


func _on_achievement_unlocked(_id: String, title: String) -> void:
	if main and main.has_method("show_toast"):
		main.show_toast(L10n.t("ach_unlocked_toast", [title]), GOLD)
	Sfx.play("quest_done", -3.0)
	refresh_profile_card()


func _on_steam_overlay(active: bool) -> void:
	if active and main.world != null and not main.day_ended and not Net.online() and not is_any_modal_open():
		open_pause()


# ---------------------------------------------------------------------------
# FPS Sayacı & Özel Nişangâh
# ---------------------------------------------------------------------------

func _build_fps_counter() -> void:
	fps_panel = PanelContainer.new()
	fps_panel.theme = theme
	var sb := _sb(Color(0.06, 0.04, 0.03, 0.72), 6, 4)
	sb.set_border_width_all(1)
	sb.border_color = Color(GOLD, 0.35)
	fps_panel.add_theme_stylebox_override("panel", sb)
	fps_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	fps_panel.offset_left = 10; fps_panel.offset_top = 10
	fps_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_lbl = _lbl(fps_panel, "60 FPS", 12, 0.95, GOOD)
	fps_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	layer.add_child(fps_panel)


func _build_crosshair() -> void:
	crosshair_ctrl = CrosshairDraw.new()
	crosshair_ctrl.set_anchors_preset(Control.PRESET_CENTER)
	crosshair_ctrl.offset_left = -24; crosshair_ctrl.offset_right = 24
	crosshair_ctrl.offset_top = -24; crosshair_ctrl.offset_bottom = 24
	crosshair_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_ctrl.hide()
	layer.add_child(crosshair_ctrl)


func _refresh_hud_prefs() -> void:
	if fps_panel:
		fps_panel.visible = Settings.show_fps
	if crosshair_ctrl:
		crosshair_ctrl.queue_redraw()
	if main and main.hint:
		if not Settings.show_hints:
			main.hint.hide()


func update_crosshair(show_it: bool, targeting: bool) -> void:
	if crosshair_ctrl == null:
		return
	crosshair_ctrl.visible = show_it
	if show_it and crosshair_ctrl.has_target != targeting:
		crosshair_ctrl.has_target = targeting
		crosshair_ctrl.queue_redraw()


# ---------------------------------------------------------------------------
# Genel Akış & Durum Güncelleme
# ---------------------------------------------------------------------------

func show_page(n: String) -> void:
	page = n
	for k in pages:
		pages[k].visible = k == n
	if pages.has(n) and pages[n].get_child_count() > 0:
		var col: Control = pages[n].get_child(0)
		if n == "lobby":
			col.offset_top = -310; col.offset_bottom = 310
			col.size = Vector2(690, 620)
		col.modulate.a = 0.0
		var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(col, "modulate:a", 1.0, 0.28)
		tw.tween_property(col, "position:x", col.position.x, 0.32).from(col.position.x - 36)
	if n == "main":
		refresh_profile_card()


func refresh_profile_card() -> void:
	if _main_career_lbl == null:
		return
	var c: Dictionary = main.career if main else {}
	if c.is_empty():
		_main_career_lbl.text = L10n.pick("Kariyer: Henüz başlanmadı", "Career: Not started yet")
	else:
		_main_career_lbl.text = L10n.pick(
			"Kariyer: Gün %d  •  %d TL  •  ⭐ %.1f",
			"Career: Day %d  •  %d TL  •  ⭐ %.1f"
		) % [int(c.get("day_num", 1)), int(c.get("money", 120)), float(c.get("reputation", 2.5))]
	if _main_ach_lbl:
		_main_ach_lbl.text = "🏆 " + L10n.t("ach_progress", [SteamMgr.unlocked_count(), SteamMgr.ACHIEVEMENTS.size()])


func refresh_lobby() -> void:
	if lobby_members_box == null:
		return
	_clear_children(lobby_members_box)
	var online := Net.online()
	var is_host := (not online) or multiplayer.is_server()
	if online:
		var hdr := _lbl(lobby_members_box, L10n.t("lobby_members_hdr", [Net.names.size(), Net.MAX_PLAYERS]), 13, 0.9, GOLD)
		hdr.add_theme_font_override("font", _font(800))
		for id_v in Net.names:
			var id := int(id_v)
			var row := HBoxContainer.new()
			lobby_members_box.add_child(row)
			var nm := _lbl(row, ("★ " if id == 1 else "• ") + str(Net.names[id]), 15, 1.0, GOLD if id == 1 else CREAM)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if is_host and id != 1:
				_btn(row, L10n.t("btn_kick"), Net.kick_peer.bind(id), 26)
	else:
		_lbl(lobby_members_box, L10n.t("lobby_members_none"), 14, 0.72)

	lobby_code_lbl.text = L10n.t("lobby_code_lbl", [Net.lobby_code]) if Net.lobby_code != "" else ""
	lobby_copy_btn.visible = Net.lobby_code != "" and Net.lobby_code != "LAN"
	lobby_start_btn.disabled = not (online and is_host)
	lobby_start_btn.text = L10n.t("lobby_start") if (not online or is_host) else L10n.t("lobby_wait_host")
	lobby_host_btn.disabled = Net.lobby_id != 0
	lobby_leave_btn.disabled = not online and Net.lobby_id == 0


func open_pause() -> void:
	if main.shop_wrap:
		main.shop_wrap.hide()
	settings_wrap.hide()
	players_wrap.hide()
	ach_wrap.hide()
	if main.world == null:
		open_settings(0)
		return
	_pause_code_row.visible = Net.lobby_code != "" and Net.lobby_code != "LAN"
	_pause_code_lbl.text = L10n.t("lobby_code_lbl", [Net.lobby_code])
	_pause_players_btn.visible = Net.online()
	_pause_leave_btn.text = L10n.t("btn_leave_career") if main._career_active else L10n.t("btn_leave_menu")
	pause_wrap.show()
	_pop_in(pause_wrap)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_settings(tab := 0) -> void:
	pause_wrap.hide()
	players_wrap.hide()
	ach_wrap.hide()
	settings_wrap.show()
	_select_settings_tab(tab)
	_pop_in(settings_wrap)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	_cancel_rebind()
	_ensure_mic_test(false)
	settings_wrap.hide()
	Settings.save()
	if main.world != null and not main.day_ended:
		pause_wrap.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_all_modals() -> void:
	_cancel_rebind()
	_ensure_mic_test(false)
	pause_wrap.hide()
	players_wrap.hide()
	settings_wrap.hide()
	ach_wrap.hide()
	Settings.save()
	if main.world != null and not main.day_ended:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_any_modal_open() -> bool:
	return (pause_wrap and pause_wrap.visible) or (players_wrap and players_wrap.visible) \
		or (settings_wrap and settings_wrap.visible) or (ach_wrap and ach_wrap.visible)


func handle_cancel() -> bool:
	if _rebind_action != "":
		_cancel_rebind()
		return true
	if settings_wrap.visible:
		close_settings()
		return true
	if players_wrap.visible:
		players_wrap.hide()
		pause_wrap.show()
		return true
	if ach_wrap.visible:
		ach_wrap.hide()
		return true
	if pause_wrap.visible:
		close_all_modals()
		return true
	return false


func _input(e: InputEvent) -> void:
	if _rebind_action != "" and e is InputEventKey and e.pressed and not e.echo:
		var kc := (e as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE:
			_cancel_rebind()
		elif kc > 0:
			Settings.rebind_action(_rebind_action, kc)
			_rebind_action = ""
			_refresh_rebind_labels()
			Sfx.play("ui_click", -8.0, 1.15)
		get_viewport().set_input_as_handled()


func _ensure_mic_test(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not on:
		if _mic_test_player and is_instance_valid(_mic_test_player):
			_mic_test_player.queue_free()
			_mic_test_player = null
		_mic_cap_test = null
		return
	var bus := AudioServer.get_bus_index("VoiceRecord")
	if bus == -1:
		bus = AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "VoiceRecord")
		AudioServer.set_bus_mute(bus, true)
		AudioServer.add_bus_effect(bus, AudioEffectCapture.new(), 0)
	for i in AudioServer.get_bus_effect_count(bus):
		var ef := AudioServer.get_bus_effect(bus, i)
		if ef is AudioEffectCapture:
			_mic_cap_test = ef
			break
	if main.world == null and _mic_test_player == null:
		_mic_test_player = AudioStreamPlayer.new()
		_mic_test_player.stream = AudioStreamMicrophone.new()
		_mic_test_player.bus = "VoiceRecord"
		_mic_test_player.autoplay = true
		add_child(_mic_test_player)


func _process(dt: float) -> void:
	if Settings.show_fps and fps_lbl:
		_fps_t += dt
		if _fps_t >= 0.35:
			_fps_t = 0.0
			var fps := Engine.get_frames_per_second()
			fps_lbl.text = "%d FPS" % fps
			fps_lbl.add_theme_color_override("font_color", GOOD if fps >= 55 else (GOLD if fps >= 35 else BAD))
	# Canlı mikrofon test çubuğu (Ses sekmesi açıkken)
	if settings_wrap and settings_wrap.visible and _set_active_tab == 1 and _mic_test_bar:
		var db := -60.0
		var me = main._my_player() if main and main.world else null
		if me != null:
			db = float(me.get("talk_db"))
		elif _mic_cap_test != null:
			var avail := _mic_cap_test.get_frames_available()
			if avail > 0:
				var buf := _mic_cap_test.get_buffer(avail)
				var s2 := 0.0
				for v in buf:
					var m := 0.5 * (v.x + v.y) * Settings.mic_gain
					s2 += m * m
				db = linear_to_db(maxf(sqrt(s2 / float(buf.size())), 0.00001))
		var norm := clampf((db + 60.0) / 52.0, 0.0, 1.0)
		_mic_test_bar.size.x = lerpf(_mic_test_bar.size.x, 260.0 * norm, minf(dt * 14.0, 1.0))
		_mic_test_bar.color = GOOD if db >= Settings.mic_threshold_db else Color(0.55, 0.52, 0.48)
		_mic_test_lbl.text = "%d dB" % roundi(db)


func _pop_in(wrap: Control) -> void:
	wrap.modulate.a = 0.0
	var tw := wrap.create_tween().set_parallel()
	tw.tween_property(wrap, "modulate:a", 1.0, 0.16)
	if wrap.get_child_count() > 0 and wrap.get_child(0).get_child_count() > 0:
		var panel := wrap.get_child(0).get_child(0) as Control
		if panel:
			panel.pivot_offset = panel.size * 0.5
			panel.scale = Vector2(0.95, 0.95)
			tw.tween_property(panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_lang_changed(_new_lang: String) -> void:
	# Tüm menü ve ayarları yeni dille anında yeniden kur (oyun durumunu koru!)
	var was_menu_vis := menu_root.visible
	var cur_page := page
	var was_pause := pause_wrap.visible
	var was_settings := settings_wrap.visible
	var keep_tab := _set_active_tab
	var was_ach := ach_wrap.visible
	_ensure_mic_test(false)
	for n in [menu_root, pause_wrap, players_wrap, settings_wrap, ach_wrap, fps_panel, crosshair_ctrl]:
		if is_instance_valid(n):
			n.queue_free()
	pages.clear()
	_build_all()
	menu_root.visible = was_menu_vis
	if was_menu_vis:
		show_page(cur_page)
	if was_pause:
		open_pause()
	if was_settings:
		open_settings(keep_tab)
	if was_ach:
		open_achievements()
	if main and main.has_method("_sync_menu_refs"):
		main._sync_menu_refs()
	refresh_lobby()
	if main and main.world != null:
		update_crosshair(true, false)
		SteamMgr.set_presence_game(main.day_num, Net.names.size() if Net.online() else 1, Net.online())
	else:
		SteamMgr.set_presence_menu()
