extends Node3D
## Menü, lobi ve oyun akışı. Arkada canlı pazar sahnesi döner; host "Pazarı Aç" deyince herkes pazara girer.

const PlayerScript := preload("res://player.gd")
const BazaarScript := preload("res://bazaar.gd")
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
var ingame_box: VBoxContainer
var world: Node3D
var players: Node3D
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
		await get_tree().create_timer(5.0).timeout
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
		get_tree().quit()


func _setup_input() -> void:
	var keys := {"fwd": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "run": KEY_SHIFT}
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

	hint = _lbl(layer, "WASD yürü  •  Shift koş  •  Boşluk zıpla  •  Fare bak  •  ESC menü", 15, 0.7)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 20; hint.offset_top = -40; hint.offset_bottom = -14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.hide()
	_build_pause(layer, theme)


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
	if players: # geç gelen adlar isim etiketlerine yansısın
		for p in players.get_children():
			p.tag.text = Net.display_name(p.name.to_int())
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
		walkers.append([p, randf_range(3.6, 5.5), randf() * TAU, randf_range(0.25, 0.4) * (1 if i % 2 == 0 else -1)])


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
		p.rig.rotation.y = atan2(tangent.x, tangent.z)
		p.spd = 4.2 * absf(w[3]) * 3.0


func _process(dt: float) -> void:
	if menu_bg:
		_menu_anim(dt)


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
	world.add_child(BazaarScript.new())
	players = Node3D.new()
	players.name = "Players"
	world.add_child(players)
	for id in ids:
		_spawn(id)
	ui.hide()
	hint.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn(id: int) -> void:
	if players == null or players.has_node(str(id)):
		return
	var p: CharacterBody3D = PlayerScript.new()
	p.name = str(id)
	p.set_multiplayer_authority(id)
	p.spawn_pos = SPAWNS[id % SPAWNS.size()] # her makinede aynı nokta
	players.add_child(p)


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


func _back_to_menu() -> void:
	_clear_world()
	pause_wrap.hide()
	hint.hide()
	ui.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if menu_bg == null:
		_set_menu_bg(true)
	_show_page("lobby" if Net.online() else "main")
	_refresh()
