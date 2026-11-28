extends Node
## TR + EN yerelleştirme motoru (Autoload: L10n).
## Dil değişince `lang_changed` sinyali yayılır; tüm menüler ve ayarlar anında güncellenir.

signal lang_changed(lang: String)

var lang := "tr" # "tr" | "en"

const STRINGS := {
	# Ana Menü
	"subtitle": {"tr": "TÜRK SEMT PAZARI SİMÜLATÖRÜ", "en": "TURKISH STREET BAZAAR SIMULATOR"},
	"tagline": {
		"tr": "Bağır, teyzelerle pazarlık yap, toptancıdan mal kap, zabıtadan kaç — Günün Esnafı ol!",
		"en": "Shout to draw crowds, haggle with aunties, grab crates, dodge inspectors — rule the bazaar!",
	},
	"btn_solo": {"tr": "TEK OYNA  •  Kariyer", "en": "PLAY SOLO  •  Career"},
	"btn_multi": {"tr": "ÇOKLU OYNA  •  Lobi & Odalar", "en": "MULTIPLAYER  •  Lobbies"},
	"btn_settings": {"tr": "AYARLAR", "en": "SETTINGS"},
	"btn_achievements": {"tr": "BAŞARIMLAR", "en": "ACHIEVEMENTS"},
	"btn_credits": {"tr": "EMEĞİ GEÇENLER & LİSANSLAR", "en": "CREDITS & LICENSES"},
	"btn_quit": {"tr": "ÇIKIŞ", "en": "QUIT"},
	"btn_back": {"tr": "◀  Geri", "en": "◀  Back"},
	"btn_close": {"tr": "Kapat  [ESC]", "en": "Close  [ESC]"},
	"btn_resume": {"tr": "▶  Oyuna Devam Et", "en": "▶  Resume Game"},
	"btn_players": {"tr": "👥  Oyuncular & Ses (Sustur / At)", "en": "👥  Players & Voice (Mute / Kick)"},
	"btn_restart_tut": {"tr": "🎓  Rehberi Baştan Göster", "en": "🎓  Restart Tutorial"},
	"btn_leave_menu": {"tr": "Ana Menüye / Lobiye Dön", "en": "Return to Main Menu / Lobby"},
	"btn_leave_career": {"tr": "Ana Menüye Dön (bugün kaydedilmez)", "en": "Return to Menu (today unsaved)"},
	"btn_quit_game": {"tr": "Oyunu Kapat", "en": "Exit Game"},
	"steam_ok": {"tr": "●  Steam Bağlı: %s", "en": "●  Steam Online: %s"},
	"steam_off": {
		"tr": "●  Steam kapalı (Tek Oyna veya Yerel Ağ ile oynayabilirsin)",
		"en": "●  Steam offline (Play Solo or Local LAN)",
	},
	"ver_label": {"tr": "sürüm %s  •  Büyük Pazar", "en": "v%s  •  Grand Bazaar"},

	# Tek Oyna
	"solo_title": {"tr": "TEK OYNA  (KARİYER)", "en": "SOLO CAREER"},
	"solo_sub": {
		"tr": "Kendi tezgâhını büyüt, itibarını yükselt — her gün sonunda otomatik kaydedilir.",
		"en": "Grow your stall and reputation — auto-saved at the end of every market day.",
	},
	"solo_continue": {"tr": "▶  Kariyere Devam Et", "en": "▶  Continue Career"},
	"solo_new": {"tr": "✚  Yeni Pazar Başlat", "en": "✚  Start New Bazaar"},
	"solo_new_confirm": {"tr": "⚠ Emin misin? Mevcut kayıt silinir — Tekrar Tıkla", "en": "⚠ Overwrite existing career? Click again"},
	"solo_no_save": {"tr": "Henüz kayıtlı kariyer yok. İlk gününe başla!", "en": "No saved career yet. Start your first day!"},

	# Lobi & Herkese Açık Oda Tarayıcısı
	"lobby_title": {"tr": "ÇOKLU OYNA  •  LOBİ", "en": "MULTIPLAYER  •  LOBBY"},
	"lobby_sub": {
		"tr": "Herkese açık veya arkadaşlara özel lobi kur, oda koduyla katıl ya da açık pazarlara gir.",
		"en": "Host a public or friends-only market, join by room code, or browse open lobbies.",
	},
	"lobby_tab_host": {"tr": "🏠 Lobi Kur / Mevcut", "en": "🏠 Host / Current"},
	"lobby_tab_browse": {"tr": "🌐 Açık Odalar", "en": "🌐 Public Lobbies"},
	"lobby_tab_friends": {"tr": "👥 Arkadaşlar", "en": "👥 Friends"},
	"lobby_tab_lan": {"tr": "💻 Yerel Test (LAN)", "en": "💻 Local / LAN"},
	"lobby_name_lbl": {"tr": "Pazar Adı:", "en": "Bazaar Name:"},
	"lobby_vis_lbl": {"tr": "Görünürlük:", "en": "Visibility:"},
	"lobby_vis_public": {"tr": "🌐 Herkese Açık (Public)", "en": "🌐 Public (Anyone)"},
	"lobby_vis_friends": {"tr": "🔒 Yalnızca Arkadaşlar", "en": "🔒 Friends Only"},
	"lobby_create": {"tr": "✚  Steam Lobisi Kur", "en": "✚  Create Steam Lobby"},
	"lobby_start": {"tr": "▶  Pazarı Aç", "en": "▶  Open the Bazaar"},
	"lobby_wait_host": {"tr": "Host pazarı açacak...", "en": "Waiting for host to start..."},
	"lobby_leave": {"tr": "Lobiden Çık", "en": "Leave Lobby"},
	"lobby_code_lbl": {"tr": "Oda Kodu: %s", "en": "Room Code: %s"},
	"lobby_copy_code": {"tr": "📋 Kodu Kopyala", "en": "📋 Copy Code"},
	"lobby_code_copied": {"tr": "Oda kodu panoya kopyalandı: %s", "en": "Room code copied: %s"},
	"lobby_join_code_ph": {"tr": "Oda Kodu (ör. A7K2)", "en": "Room Code (e.g. A7K2)"},
	"lobby_join_code_btn": {"tr": "▶ Koda Katıl", "en": "▶ Join Code"},
	"lobby_refresh": {"tr": "🔄 Listeyi Yenile", "en": "🔄 Refresh List"},
	"lobby_empty_pub": {"tr": "Şu an açık Pazar lobisi bulunamadı. İlk lobiyi sen kur!", "en": "No open Bazaar lobbies found. Host the first one!"},
	"lobby_empty_friends": {"tr": "Çevrimiçi Steam arkadaşı yok.", "en": "No online Steam friends."},
	"lobby_members_none": {"tr": "Henüz bir lobide değilsin.", "en": "Not in a lobby yet."},
	"lobby_members_hdr": {"tr": "Lobideki Esnaflar (%d/%d):", "en": "Vendors in Lobby (%d/%d):"},
	"lan_host": {"tr": "Yerel Host Aç", "en": "Host Local"},
	"lan_join": {"tr": "Yerel Hosta Katıl", "en": "Join Local"},
	"lan_ip_ph": {"tr": "Sunucu IP (127.0.0.1)", "en": "Server IP (127.0.0.1)"},

	# Pause & Oyuncular
	"pause_title": {"tr": "DURAKLATILDI", "en": "PAUSED"},
	"players_title": {"tr": "OYUNCULAR & SESLİ SOHBET", "en": "PLAYERS & VOICE CHAT"},
	"btn_mute": {"tr": "🔇 Sustur", "en": "🔇 Mute"},
	"btn_unmute": {"tr": "🔊 Sesi Aç", "en": "🔊 Unmute"},
	"btn_kick": {"tr": "⛔ Odadan At", "en": "⛔ Kick"},
	"you_badge": {"tr": "(Sen)", "en": "(You)"},
	"host_badge": {"tr": "★ Host", "en": "★ Host"},

	# Ayarlar Sekmeleri
	"set_title": {"tr": "AYARLAR", "en": "SETTINGS"},
	"tab_display": {"tr": "🖥 Ekran & Grafik", "en": "🖥 Display & Graphics"},
	"tab_audio": {"tr": "🔊 Ses & Mikrofon", "en": "🔊 Audio & Voice"},
	"tab_controls": {"tr": "⌨ Kontroller & Tuşlar", "en": "⌨ Controls & Keybinds"},
	"tab_gameplay": {"tr": "🎮 Oynanış & Dil", "en": "🎮 Gameplay & Language"},
	"tab_credits": {"tr": "📜 Hakkında & Lisanslar", "en": "📜 Credits & Licenses"},
	"btn_apply_close": {"tr": "✔  Kaydet & Kapat", "en": "✔  Save & Close"},
	"btn_reset_defaults": {"tr": "↺  Varsayılana Sıfırla", "en": "↺  Reset Defaults"},

	# Ekran & Grafik
	"sec_display": {"tr": "EKRAN", "en": "DISPLAY"},
	"sec_graphics": {"tr": "GRAFİK KALİTESİ", "en": "GRAPHICS QUALITY"},
	"sec_camera_acc": {"tr": "KAMERA & ERİŞİLEBİLİRLİK", "en": "CAMERA & ACCESSIBILITY"},
	"lbl_win_mode": {"tr": "Pencere Modu", "en": "Window Mode"},
	"lbl_res": {"tr": "Çözünürlük", "en": "Resolution"},
	"lbl_vsync": {"tr": "Dikey Eşitleme (V-Sync)", "en": "V-Sync"},
	"lbl_fps_cap": {"tr": "FPS Limiti", "en": "FPS Limit"},
	"lbl_preset": {"tr": "Grafik Ön Ayarı", "en": "Quality Preset"},
	"lbl_msaa": {"tr": "Kenar Yumuşatma (MSAA)", "en": "Anti-Aliasing (MSAA)"},
	"lbl_shadows": {"tr": "Gölge Kalitesi", "en": "Shadow Quality"},
	"lbl_render_scale": {"tr": "Çözünürlük Ölçeği", "en": "Render Scale"},
	"lbl_ssao": {"tr": "Ortam Gölgelemesi (SSAO / SSIL)", "en": "Ambient Occlusion (SSAO / SSIL)"},
	"lbl_glow": {"tr": "Işıma / Parlama (Glow)", "en": "Bloom / Glow"},
	"lbl_volfog": {"tr": "Hacimsel Sis & Su Yansımaları (SSR)", "en": "Volumetric Fog & Puddle SSR"},
	"lbl_fov": {"tr": "Görüş Açısı (FOV)", "en": "Field of View (FOV)"},
	"lbl_show_fps": {"tr": "Köşede FPS Sayacı Göster", "en": "Show FPS Counter"},
	"lbl_reduce_motion": {"tr": "Hareket & Sarhoşluk Sallantısını Azalt", "en": "Reduce Head Bob & Drunk Sway"},
	"opt_low": {"tr": "Düşük", "en": "Low"},
	"opt_med": {"tr": "Orta", "en": "Medium"},
	"opt_high": {"tr": "Yüksek", "en": "High"},
	"opt_off": {"tr": "Kapalı", "en": "Off"},
	"opt_on": {"tr": "Açık", "en": "On"},
	"opt_adaptive": {"tr": "Uyarlanabilir", "en": "Adaptive"},
	"opt_unlimited": {"tr": "Sınırsız", "en": "Unlimited"},
	"mode_windowed": {"tr": "Pencere", "en": "Windowed"},
	"mode_fullscreen": {"tr": "Tam Ekran", "en": "Exclusive Fullscreen"},
	"mode_borderless": {"tr": "Kenarlıksız Tam Ekran", "en": "Borderless Fullscreen"},

	# Ses & Mikrofon
	"sec_volumes": {"tr": "SES SEVİYELERİ", "en": "VOLUME MIXER"},
	"sec_voice": {"tr": "MİKROFON & PROXIMITY VOICE", "en": "MICROPHONE & PROXIMITY VOICE"},
	"lbl_master": {"tr": "Ana Ses", "en": "Master Volume"},
	"lbl_sfx": {"tr": "Ses Efektleri (SFX)", "en": "Sound Effects (SFX)"},
	"lbl_music": {"tr": "Müzik & Arabesk Radyo", "en": "Music & Radio"},
	"lbl_amb": {"tr": "Pazar Ambiyansı & Hava", "en": "Bazaar Ambience & Weather"},
	"lbl_voice": {"tr": "Sesli Sohbet (Diğer Oyuncular)", "en": "Voice Chat (Other Players)"},
	"lbl_mic_dev": {"tr": "Mikrofon Cihazı", "en": "Input Device"},
	"lbl_voice_mode": {"tr": "Konuşma Modu", "en": "Voice Mode"},
	"opt_vad": {"tr": "Ses Aktivasyonu (Otomatik)", "en": "Voice Activation (Auto)"},
	"opt_ptt": {"tr": "Bas-Konuş (Push-to-Talk)", "en": "Push-to-Talk"},
	"lbl_mic_gain": {"tr": "Mikrofon Kazancı", "en": "Microphone Gain"},
	"lbl_mic_gate": {"tr": "Gürültü Eşiği (dB)", "en": "Noise Gate (dB)"},
	"lbl_mic_test": {"tr": "Canlı Mikrofon Seviyesi", "en": "Live Mic Level"},

	# Kontroller
	"sec_mouse_pad": {"tr": "FARE & KONTROLCÜ", "en": "MOUSE & CONTROLLER"},
	"sec_keybinds": {"tr": "TUŞ ATAMALARI (Değiştirmek için tıkla, iptal için ESC)", "en": "KEYBINDINGS (Click to rebind, ESC to cancel)"},
	"lbl_mouse_sens": {"tr": "Fare Hassasiyeti", "en": "Mouse Sensitivity"},
	"lbl_invert_y": {"tr": "Y-Eksenini Ters Çevir", "en": "Invert Y-Axis"},
	"lbl_pad_sens": {"tr": "Kontrolcü Bakış Hassasiyeti", "en": "Controller Look Sensitivity"},
	"lbl_pad_dz": {"tr": "Analog Ölü Bölge (Deadzone)", "en": "Stick Deadzone"},
	"press_any_key": {"tr": "Bir tuşa bas...", "en": "Press any key..."},

	# Oynanış & Dil
	"sec_lang_hud": {"tr": "DİL & ARAYÜZ", "en": "LANGUAGE & HUD"},
	"lbl_lang": {"tr": "Oyun Dili", "en": "Language"},
	"lbl_crosshair": {"tr": "Nişangâh Stili", "en": "Crosshair Style"},
	"lbl_crosshair_sz": {"tr": "Nişangâh Boyutu", "en": "Crosshair Size"},
	"lbl_show_hints": {"tr": "Alt İpuçlarını Göster", "en": "Show Contextual Hints"},
	"ch_dot": {"tr": "Nokta", "en": "Dot"},
	"ch_cross": {"tr": "Artı (+)", "en": "Cross (+)"},
	"ch_ring": {"tr": "Halka (○)", "en": "Ring (○)"},

	# Başarımlar
	"ach_title": {"tr": "🏆 BAŞARIMLAR", "en": "🏆 ACHIEVEMENTS"},
	"ach_progress": {"tr": "Açılan: %d / %d", "en": "Unlocked: %d / %d"},
	"ach_unlocked_toast": {"tr": "🏆 Başarım Açıldı: %s", "en": "🏆 Achievement Unlocked: %s"},

	# Aksiyon Adları
	"act_fwd": {"tr": "İleri Yürü", "en": "Move Forward"},
	"act_back": {"tr": "Geri Yürü", "en": "Move Back"},
	"act_left": {"tr": "Sola Adım", "en": "Strafe Left"},
	"act_right": {"tr": "Sağa Adım", "en": "Strafe Right"},
	"act_run": {"tr": "Koş (Sprint)", "en": "Sprint"},
	"act_jump": {"tr": "Zıpla", "en": "Jump"},
	"act_interact": {"tr": "Etkileşim / Sat / Kasa Al", "en": "Interact / Sell / Grab Crate"},
	"act_throw_crate": {"tr": "Fırlat (Kasa / Sopa / Bira)", "en": "Throw (Crate / Bat / Beer)"},
	"act_shout": {"tr": "Bağır (Müşteri Çek)", "en": "Shout (Lure Shoppers)"},
	"act_ptt": {"tr": "Bas-Konuş (Push-to-Talk)", "en": "Push-to-Talk"},
	"act_mic_mute": {"tr": "Mikrofon Aç / Kapa", "en": "Toggle Mic Mute"},
	"act_refuse_offer": {"tr": "Pazarlığı Reddet / Radyo Al", "en": "Refuse Haggle / Pick Up Radio"},
	"act_ring_bell": {"tr": "Tezgâh Zilini Çal", "en": "Ring Stall Bell"},
	"act_call_tea": {"tr": "Çaycıyı Çağır", "en": "Call Tea Vendor"},
	"act_price_down": {"tr": "Fiyatı Düşür", "en": "Lower Price"},
	"act_price_up": {"tr": "Fiyatı Artır", "en": "Raise Price"},
	"act_radio_next": {"tr": "Radyo Sonraki Şarkı", "en": "Radio Next Track"},
	"act_scoreboard": {"tr": "Skor Tablosu", "en": "Scoreboard"},
	"act_tutorial_skip": {"tr": "Rehber Adımını Geç", "en": "Skip Tutorial Step"},
}


func set_lang(new_lang: String) -> void:
	var norm := "en" if new_lang.to_lower().begins_with("en") else "tr"
	if norm == lang:
		return
	lang = norm
	lang_changed.emit(lang)


func t(key: String, args := []) -> String:
	var row: Dictionary = STRINGS.get(key, {})
	var s := str(row.get(lang, row.get("tr", key)))
	if not args.is_empty():
		return s % args
	return s


func pick(tr_txt: String, en_txt: String) -> String:
	return en_txt if lang == "en" else tr_txt
