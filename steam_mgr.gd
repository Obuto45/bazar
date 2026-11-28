extends Node
## Steamworks yöneticisi (Autoload: SteamMgr):
## - Steam dağıtımında restartAppIfNecessary koruması (`steam` feature tag'i varsa)
## - 20 Başarım (yerel user://achievements.json + Steam Achievement senkronu)
## - Steam Rich Presence (Menü / Lobi / Pazar Günü durumu)
## - Steam Cloud yedekleme (career.json & gorunum.cfg)
## - Steam Overlay açılınca otomatik duraklatma sinyali

signal achievement_unlocked(ach_id: String, title: String)
signal overlay_changed(active: bool)

const ACH_PATH := "user://achievements.json"

const ACHIEVEMENTS := [
	{"id": "ACH_FIRST_SALE", "icon": "🍅", "tr": "Siftah Yaptık!", "en": "First Sale!", "tr_d": "İlk satışını gerçekleştir.", "en_d": "Complete your very first sale."},
	{"id": "ACH_HAGGLE_WIN", "icon": "🤝", "tr": "Pazarlık Ustası", "en": "Master Haggler", "tr_d": "Bir pazarlıkta orta yolu bul.", "en_d": "Close a haggled deal."},
	{"id": "ACH_THIEF_CATCH", "icon": "🕵️", "tr": "Mahalle Bekçisi", "en": "Neighborhood Watch", "tr_d": "Bir kapkaççıyı yakala.", "en_d": "Catch a pickpocket."},
	{"id": "ACH_DAY_COMPLETE", "icon": "🌅", "tr": "Akşam Pazarı", "en": "Closing Time", "tr_d": "İlk pazar gününü tamamla.", "en_d": "Finish your first market day."},
	{"id": "ACH_PROFIT_300", "icon": "💰", "tr": "Bereketli Gün", "en": "Prosperous Day", "tr_d": "Tek günde 300 TL net kâr yap.", "en_d": "Earn 300 TL net profit in a single day."},
	{"id": "ACH_PROFIT_700", "icon": "👑", "tr": "Pazarın Kralı", "en": "King of the Bazaar", "tr_d": "Tek günde 700 TL net kâr yap.", "en_d": "Earn 700 TL net profit in a single day."},
	{"id": "ACH_CLEAN_DAY", "icon": "👮", "tr": "Temiz Esnaf", "en": "Spotless Vendor", "tr_d": "Hiç zabıta cezası yemeden bir gün bitir.", "en_d": "Finish a day with zero inspector fines."},
	{"id": "ACH_ZABITA_FINE", "icon": "🚨", "tr": "Tutanak Hatırası", "en": "Ticket Souvenir", "tr_d": "Zabıtadan ilk cezanı ye.", "en_d": "Receive your first fine from the inspector."},
	{"id": "ACH_MAX_REP", "icon": "⭐", "tr": "Beş Yıldızlı Tezgâh", "en": "Five-Star Stall", "tr_d": "Tezgâh itibarını 4.5 yıldızın üstüne çıkar.", "en_d": "Reach 4.5+ star stall reputation."},
	{"id": "ACH_FULL_EXPAND", "icon": "📏", "tr": "Büyük Tezgâh", "en": "Mega Stall", "tr_d": "Tezgâhını son seviyeye (8 yuva) genişlet.", "en_d": "Expand your stall to level 2 (8 slots)."},
	{"id": "ACH_DJ_ARABESK", "icon": "📻", "tr": "Arabesk DJ", "en": "Arabesk DJ", "tr_d": "Tezgâhına Arabesk Radyo kurup aç.", "en_d": "Place and play the Arabesk Radio on your stall."},
	{"id": "ACH_MEGA_VOICE", "icon": "📢", "tr": "Mahalle İnledi!", "en": "Whole Block Heard That", "tr_d": "El megafonuyla müşteri çek.", "en_d": "Use the megaphone to attract shoppers."},
	{"id": "ACH_BEER_FAINT", "icon": "🍺", "tr": "Üçüncü Şişe Fazlaydı", "en": "One Too Many", "tr_d": "3 bira içip pazarın ortasında bayıl.", "en_d": "Pass out in the bazaar after 3 beers."},
	{"id": "ACH_SABOTAGE_BEER", "icon": "💥", "tr": "Şişe Savaşı", "en": "Bottle Brawl", "tr_d": "Rakibine veya tezgâhına bira şişesi isabet ettir.", "en_d": "Hit a rival or their stall with a beer bottle."},
	{"id": "ACH_CAT_FRIEND", "icon": "🐱", "tr": "Kedi Dostu", "en": "Cat Whisperer", "tr_d": "Simit/açma atarak sokak kedisini besle.", "en_d": "Feed a stray cat with simit or acma."},
	{"id": "ACH_RAIN_DAY", "icon": "🌧️", "tr": "Yağmurda Pazar", "en": "Rainy Day Hustle", "tr_d": "Yağmurlu bir pazar gününü tamamla.", "en_d": "Complete a rainy bazaar day."},
	{"id": "ACH_TRUCK_HORN", "icon": "🚚", "tr": "Havalı Korna", "en": "Air Horn Salute", "tr_d": "Toptancı Ford Transit şoförüne korna çaldır.", "en_d": "Get the wholesaler truck driver to honk."},
	{"id": "ACH_FRESH_SPRAY", "icon": "💦", "tr": "Taptaze!", "en": "Fresh as Morning Dew", "tr_d": "Su fısfısıyla ürünlerini tazele.", "en_d": "Refresh your produce with the spray bottle."},
	{"id": "ACH_DAY_3", "icon": "📅", "tr": "Müdavim Esnaf", "en": "Seasoned Merchant", "tr_d": "Kariyerde 3. güne ulaş.", "en_d": "Reach Day 3 in career mode."},
	{"id": "ACH_MULTI_OPEN", "icon": "🌐", "tr": "Esnaf Dayanışması", "en": "Bazaar Crew", "tr_d": "Çok oyunculu bir pazar günü başlat.", "en_d": "Start a multiplayer market day."},
]

var unlocked: Dictionary = {} # ach_id -> unix_time
var _steam_obj: Object = null


func _ready() -> void:
	_steam_obj = Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null
	_load_local()
	if _steam_obj != null:
		# Yalnızca Steam sürümünde (custom_features="steam") Steam istemcisi üzerinden açılmayı zorunlu kıl.
		if OS.has_feature("steam") and _steam_obj.has_method("restartAppIfNecessary"):
			if bool(_steam_obj.call("restartAppIfNecessary", Net.APP_ID)):
				get_tree().quit()
				return
		if _steam_obj.has_signal("overlay_toggled"):
			_steam_obj.connect("overlay_toggled", _on_overlay_toggled)
	call_deferred("_post_ready_sync")


func _post_ready_sync() -> void:
	if is_steam_ready():
		set_presence_menu()
		_sync_local_to_steam()


func is_steam_ready() -> bool:
	return _steam_obj != null and Net.steam_ok


func _on_overlay_toggled(active: bool, _user_initiated := false, _app_id := 0) -> void:
	overlay_changed.emit(active)


# ---------- Başarımlar ----------

func unlock(ach_id: String) -> void:
	if unlocked.has(ach_id):
		return
	var meta := get_ach_meta(ach_id)
	if meta.is_empty():
		return
	unlocked[ach_id] = int(Time.get_unix_time_from_system())
	_save_local()
	if is_steam_ready() and _steam_obj.has_method("setAchievement"):
		_steam_obj.call("setAchievement", ach_id)
		if _steam_obj.has_method("storeStats"):
			_steam_obj.call("storeStats")
	var title := L10n.pick(str(meta["tr"]), str(meta["en"]))
	achievement_unlocked.emit(ach_id, title)


func is_unlocked(ach_id: String) -> bool:
	return unlocked.has(ach_id)


func unlocked_count() -> int:
	return unlocked.size()


func get_ach_meta(ach_id: String) -> Dictionary:
	for a: Dictionary in ACHIEVEMENTS:
		if str(a["id"]) == ach_id:
			return a
	return {}


func _sync_local_to_steam() -> void:
	if not is_steam_ready() or not _steam_obj.has_method("setAchievement"):
		return
	var any := false
	for aid: String in unlocked:
		_steam_obj.call("setAchievement", aid)
		any = true
	if any and _steam_obj.has_method("storeStats"):
		_steam_obj.call("storeStats")


func _load_local() -> void:
	if not FileAccess.file_exists(ACH_PATH):
		return
	var txt := FileAccess.get_file_as_string(ACH_PATH)
	var data = JSON.parse_string(txt)
	if data is Dictionary:
		unlocked = data


func _save_local() -> void:
	var f := FileAccess.open(ACH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(unlocked, "\t"))
		f.close()


# ---------- Steam Rich Presence ----------

func set_presence_menu() -> void:
	_set_rp("Ana Menüde" if L10n.lang == "tr" else "In Main Menu")


func set_presence_lobby(count: int, max_p: int) -> void:
	_set_rp(("Pazar Lobisinde (%d/%d)" if L10n.lang == "tr" else "In Bazaar Lobby (%d/%d)") % [count, max_p])


func set_presence_game(day_n: int, count := 1, online := false) -> void:
	if online:
		_set_rp(("Gün %d • Çoklu Pazar (%d Esnaf)" if L10n.lang == "tr" else "Day %d • Co-op Bazaar (%d Vendors)") % [day_n, count])
	else:
		_set_rp(("Gün %d • Solo Kariyer" if L10n.lang == "tr" else "Day %d • Solo Career") % day_n)


func _set_rp(txt: String) -> void:
	if not is_steam_ready() or not _steam_obj.has_method("setRichPresence"):
		return
	_steam_obj.call("setRichPresence", "status", txt)
	_steam_obj.call("setRichPresence", "steam_display", "#StatusFull")


# ---------- Steam Cloud Yedekleme ----------

func cloud_enabled() -> bool:
	if not is_steam_ready():
		return false
	if _steam_obj.has_method("isCloudEnabledForAccount") and _steam_obj.has_method("isCloudEnabledForApp"):
		return bool(_steam_obj.call("isCloudEnabledForAccount")) and bool(_steam_obj.call("isCloudEnabledForApp"))
	return false


func cloud_save_file(cloud_name: String, user_path: String) -> void:
	if not cloud_enabled() or not FileAccess.file_exists(user_path):
		return
	if not _steam_obj.has_method("fileWrite"):
		return
	var bytes := FileAccess.get_file_as_bytes(user_path)
	if not bytes.is_empty():
		_steam_obj.call("fileWrite", cloud_name, bytes, bytes.size())


func cloud_restore_if_missing(cloud_name: String, user_path: String) -> bool:
	if FileAccess.file_exists(user_path) or not cloud_enabled():
		return false
	if not _steam_obj.has_method("fileExists") or not _steam_obj.has_method("fileRead"):
		return false
	if not bool(_steam_obj.call("fileExists", cloud_name)):
		return false
	var sz := int(_steam_obj.call("getFileSize", cloud_name)) if _steam_obj.has_method("getFileSize") else 0
	if sz <= 0 or sz > 262144:
		return false
	var res = _steam_obj.call("fileRead", cloud_name, sz)
	if res is Dictionary and bool(res.get("ret", false)) and res.get("buf") is PackedByteArray:
		var f := FileAccess.open(user_path, FileAccess.WRITE)
		if f:
			f.store_buffer(res["buf"] as PackedByteArray)
			f.close()
			return true
	return false
