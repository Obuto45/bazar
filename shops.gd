extends RefCounted
## Arka sokaktaki gerçek dükkanlar: hangi tabela hangi dükkan, ne satar, ne zaman açıktır.
## Gün ilerlemesi (0..1): 0 = 08:00, 0.30 öğle, 0.62 ikindi, 0.80 akşam pazarı, 1 = 21:30.
## Kapıya bakıp [E] ile o dükkanın paneli açılır (bkz. main.gd open_shop, bazaar.gd vitrinleri).

const SHOPS := {
	"tekel": {"sign": "TEKEL BAYİ", "name": "Tekel Bayi", "icon": "🍺", "open": [0.30, 1.01],
		"items": ["sigara", "puro"], "upgrades": []},
	"firin": {"sign": "FIRIN", "name": "Fırın", "icon": "🥯", "open": [0.0, 0.72],
		"items": ["simit"], "upgrades": []},
	"kiraathane": {"sign": "KIRAATHANE", "name": "Kıraathane", "icon": "🍵", "open": [0.0, 1.01],
		"items": ["cay"], "upgrades": []},
	"market": {"sign": "MARKET", "name": "Market", "icon": "🛒", "open": [0.0, 1.01],
		"items": ["bicak", "sopa", "spray"], "upgrades": []},
	"nalbur": {"sign": "NALBUR", "name": "Nalbur", "icon": "🔧", "open": [0.0, 0.80],
		"items": [], "upgrades": ["megaphone", "lights", "big_crate", "bell"], "expand": true},
	"telefoncu": {"sign": "TELEFONCU", "name": "Telefoncu", "icon": "📱", "open": [0.30, 0.85],
		"items": ["megafon", "radyo"], "upgrades": []},
	"eczane": {"sign": "ECZANE", "name": "Eczane", "icon": "💊", "open": [0.0, 1.01],
		"items": [], "upgrades": []},
	"berber": {"sign": "BERBER", "name": "Berber", "icon": "💈", "open": [0.0, 0.80],
		"items": [], "upgrades": []},
	"terzi": {"sign": "TERZİ", "name": "Terzi", "icon": "🧵", "open": [0.0, 0.80],
		"items": [], "upgrades": []},
}

## Akşam pazarında (>= 0.80) eczane "nöbetçi" olur, fiyatlar bu kadar artar.
const NIGHT_PHARMACY_AT := 0.80
const NIGHT_PHARMACY_MULT := 1.5


static func id_for_sign(sign: String) -> String:
	for k in SHOPS:
		if str(SHOPS[k]["sign"]) == sign:
			return k
	return ""


static func is_open(shop_id: String, prog: float) -> bool:
	if not SHOPS.has(shop_id):
		return false
	var o: Array = SHOPS[shop_id]["open"]
	return prog >= float(o[0]) and prog < float(o[1])


## Gün ilerlemesini saate çevirir (HUD saatiyle aynı: 08:00 + prog * 810 dk).
static func clock_text(prog: float) -> String:
	var mins := int(480.0 + clampf(prog, 0.0, 1.0) * 810.0)
	return "%02d:%02d" % [mins / 60, mins % 60]


## Kapalıysa ne zaman açılacağını söyler ("Açılış 12:03" / "Bugün kapandı").
static func closed_text(shop_id: String, prog: float) -> String:
	var o: Array = SHOPS[shop_id]["open"]
	if prog < float(o[0]):
		return "Açılış %s" % clock_text(float(o[0]))
	return "Bugünlük kapandı"


static func price_mult(shop_id: String, prog: float) -> float:
	if shop_id == "eczane" and prog >= NIGHT_PHARMACY_AT:
		return NIGHT_PHARMACY_MULT
	return 1.0


static func display_name(shop_id: String, prog: float) -> String:
	if shop_id == "eczane" and prog >= NIGHT_PHARMACY_AT:
		return "Nöbetçi Eczane"
	return str(SHOPS[shop_id]["name"])


## Büyük harfli tabela adı (Türkçe İ'yi korumak için to_upper yerine bunu kullan).
static func display_sign(shop_id: String, prog: float) -> String:
	if shop_id == "eczane" and prog >= NIGHT_PHARMACY_AT:
		return "NÖBETÇİ ECZANE"
	return str(SHOPS[shop_id]["sign"])
