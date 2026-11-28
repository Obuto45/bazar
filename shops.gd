extends RefCounted
## Arka sokaktaki gerçek dükkanlar: hangi tabela hangi dükkan, ne satar, ne zaman açıktır.
## Gün ilerlemesi (0..1): 0 = 08:00, 0.30 öğle, 0.62 ikindi, 0.80 akşam pazarı, 1 = 21:30.
## Kapıya bakıp [E] ile o dükkanın paneli açılır (bkz. main.gd open_shop, bazaar.gd vitrinleri).

const SHOPS := {
	"tekel": {"sign": "TEKEL BAYİ", "name": "Tekel Bayi", "icon": "🍺", "open": [0.30, 1.01],
		"items": ["bira", "sigara", "puro"], "upgrades": []},
	"firin": {"sign": "FIRIN", "name": "Fırın", "icon": "🥯", "open": [0.0, 0.72],
		"items": ["simit", "acma"], "upgrades": []},
	"kiraathane": {"sign": "KIRAATHANE", "name": "Kıraathane", "icon": "🍵", "open": [0.0, 1.01],
		"items": ["cay"], "upgrades": []},
	"market": {"sign": "MARKET", "name": "Market", "icon": "🛒", "open": [0.0, 1.01],
		"items": ["bicak", "sopa", "spray"], "upgrades": []},
	"nalbur": {"sign": "NALBUR", "name": "Nalbur", "icon": "🔧", "open": [0.0, 0.80],
		"items": [], "upgrades": ["megaphone", "lights", "big_crate", "nazar", "flama", "saksi", "tabela"], "expand": true},
	"telefoncu": {"sign": "TELEFONCU", "name": "Telefoncu", "icon": "📱", "open": [0.30, 0.85],
		"items": ["megafon", "radyo"], "upgrades": []},
	"berber": {"sign": "BERBER", "name": "Berber", "icon": "💈", "open": [0.0, 0.80],
		"items": [], "upgrades": [], "looks": ["hair", "hcol", "must"], "g": 0},
	"terzi": {"sign": "TERZİ", "name": "Terzi", "icon": "🧵", "open": [0.0, 0.80],
		"items": [], "upgrades": [], "looks": ["shirt", "pants", "vest", "hat"]},
	"bufe": {"sign": "BÜFE", "name": "Büfe", "icon": "🥤", "open": [0.0, 1.01],
		"items": ["sigara", "bira", "cay", "simit"], "upgrades": []},
	"bakkal": {"sign": "BAKKAL", "name": "Bakkal", "icon": "🧺", "open": [0.0, 0.90],
		"items": [], "upgrades": []},
	"borekci": {"sign": "BÖREKÇİ", "name": "Börekçi", "icon": "🥐", "open": [0.0, 0.62],
		"items": ["acma", "simit", "cay"], "upgrades": []},
	"kirtasiye": {"sign": "KIRTASİYE", "name": "Kırtasiye", "icon": "✏️", "open": [0.0, 0.80],
		"items": [], "upgrades": ["tabela", "flama"]},
	"cicekci": {"sign": "ÇİÇEKÇİ", "name": "Çiçekçi", "icon": "💐", "open": [0.0, 0.85],
		"items": [], "upgrades": ["saksi"]},
	"kasap": {"sign": "KASAP", "name": "Kasap", "icon": "🔪", "open": [0.0, 0.75],
		"items": ["bicak"], "upgrades": []},
	"eczane": {"sign": "ECZANE", "name": "Eczane", "icon": "💊", "open": [0.0, 1.01],
		"items": [], "upgrades": []},
	"kuafor": {"sign": "KUAFÖR", "name": "Kuaför", "icon": "💇", "open": [0.0, 0.85],
		"items": [], "upgrades": [], "looks": ["fhair", "hcol"], "g": 1},
}

## Berber / terzi görünüm seçenekleri: tür -> {başlık, fiyat, seçenekler}. Renk seçenekleri Color, diğerleri ad.
const LOOKS := {
	"hair": {"title": "✂️ Saç", "cost": 25, "g": 0, "opts": ["Kısa", "Kel", "Kıvırcık", "Jöleli Dik", "Yandan Ayrık"]},
	"fhair": {"title": "✂️ Saç", "cost": 25, "g": 1, "opts": ["Uzun", "Topuz", "At Kuyruğu", "Kısa Küt", "Örgü"]},
	"hcol": {"title": "🎨 Saç Rengi", "cost": 10, "opts": [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05),
		Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1), Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]},
	"must": {"title": "🥸 Bıyık", "cost": 15, "g": 0, "opts": ["Klasik", "İnce", "Pala", "Yok"]},
	"shirt": {"title": "👕 Gömlek Rengi", "cost": 20, "opts": [Color(0.85, 0.2, 0.18), Color(0.2, 0.5, 0.9),
		Color(0.98, 0.75, 0.15), Color(0.3, 0.75, 0.35), Color(0.65, 0.35, 0.85), Color(1.0, 0.5, 0.7),
		Color(0.15, 0.75, 0.75), Color(1.0, 0.55, 0.15), Color(0.95, 0.95, 0.93), Color(0.15, 0.15, 0.17)]},
	"pants": {"title": "👖 Pantolon Rengi", "cost": 20, "opts": [Color(0.16, 0.18, 0.24), Color(0.12, 0.12, 0.13),
		Color(0.42, 0.3, 0.2), Color(0.55, 0.52, 0.45), Color(0.22, 0.32, 0.55), Color(0.3, 0.36, 0.22)]},
	"vest": {"title": "🦺 Yelek / Ceket", "cost": 35, "opts": ["Yok", "Yelek", "Ceket"]},
	"hat": {"title": "🧢 Şapka", "cost": 30, "g": 0, "opts": ["Kasket", "Yok", "Takke", "Fötr"]},
}


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


## Saate göre fiyat çarpanı (şimdilik hepsi 1; ileride akşam zammı vb. için).
static func price_mult(_shop_id: String, _prog: float) -> float:
	return 1.0


static func display_name(shop_id: String, _prog: float) -> String:
	return str(SHOPS[shop_id]["name"])


## Büyük harfli tabela adı (Türkçe İ'yi korumak için to_upper yerine bunu kullan).
static func display_sign(shop_id: String, _prog: float) -> String:
	return str(SHOPS[shop_id]["sign"])
