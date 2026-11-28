extends Node3D
## Yapay zeka pazar müşterisi (v0.6 "Canlı Pazar"):
## - 6 tip: Normal, Pazar Teyzesi, Aceleci, VIP, Aile (yanında çocuk + balon) ve sohbetçi Emekli Amca.
## - Her tipe özel bol Türkçe replik (selam, pazarlık, mutlu, kızgın, solmuş ürün, yağmur, etkinlik ürünü).
## - Tazelik / itibar / hava durumu kancaları (stall.gd & main.gd yeni API'leri korumalı çağrılır).
## - Uzaktan okunabilir, kameraya göre büyüyen konuşma kartı + emote balonları + kart içi sabır çubuğu.
## - Bekleme animasyonları (etrafa bakma, telefon, ayak vurma, saat, ürün yoklama), yağmurda şemsiye,
##   beden/kıyafet/şapka/gözlük/çanta/pazar arabası çeşitliliği.

const MODEL_MAN := preload("res://models/char_musteri_erkek.glb")
const MODEL_WOMAN := preload("res://models/char_musteri_kadin.glb")
const MODEL_TEYZE := preload("res://models/char_teyze.glb")
const MODEL_EMEKLI := preload("res://models/char_emekli.glb")
const MODEL_KID := preload("res://models/char_cocuk.glb")
const LP := preload("res://lowpoly.gd")
const Produce := preload("res://produce.gd")
const StallScript := preload("res://stall.gd")
const VFX := preload("res://vfx.gd")

const PART_NAMES := ["Body", "Head", "HandL", "HandR", "FootL", "FootR"]

const HAIRS := [Color(0.2, 0.12, 0.07), Color(0.08, 0.06, 0.05), Color(0.75, 0.55, 0.25), Color(0.55, 0.22, 0.1),
	Color(0.4, 0.28, 0.18), Color(0.85, 0.8, 0.7)]
const GREY_HAIRS := [Color(0.82, 0.8, 0.78), Color(0.66, 0.64, 0.62), Color(0.92, 0.9, 0.86)]
const SHIRTS := [Color(0.82, 0.28, 0.24), Color(0.24, 0.52, 0.82), Color(0.92, 0.72, 0.2), Color(0.32, 0.7, 0.36),
	Color(0.62, 0.36, 0.78), Color(0.92, 0.48, 0.65), Color(0.18, 0.68, 0.68), Color(0.92, 0.54, 0.18),
	Color(0.95, 0.93, 0.88), Color(0.36, 0.38, 0.44), Color(0.55, 0.16, 0.22), Color(0.6, 0.72, 0.9)]
const PANTS := [Color(0.3, 0.42, 0.66), Color(0.16, 0.17, 0.2), Color(0.62, 0.55, 0.42), Color(0.42, 0.44, 0.46),
	Color(0.34, 0.38, 0.24), Color(0.22, 0.28, 0.48)]
const SKINS := [Color(0.96, 0.78, 0.62), Color(0.9, 0.7, 0.54), Color(0.78, 0.56, 0.4), Color(0.98, 0.85, 0.74),
	Color(0.66, 0.46, 0.32)]
const SCARF_COLORS := [
	Color(0.88, 0.24, 0.44), Color(0.18, 0.62, 0.66), Color(0.66, 0.26, 0.68),
	Color(0.92, 0.50, 0.20), Color(0.24, 0.52, 0.82), Color(0.24, 0.62, 0.34),
	Color(0.95, 0.9, 0.78), Color(0.5, 0.2, 0.26),
]
const HAT_COLORS := [Color(0.3734, 0.3424, 0.3171), Color(0.24, 0.22, 0.2), Color(0.42, 0.34, 0.24),
	Color(0.2, 0.24, 0.32), Color(0.5, 0.48, 0.44)]
const UMBRELLA_COLORS := [Color(0.86, 0.18, 0.2), Color(0.16, 0.36, 0.72), Color(0.12, 0.12, 0.14),
	Color(0.96, 0.78, 0.16), Color(0.24, 0.6, 0.36), Color(0.7, 0.3, 0.7), Color(0.95, 0.5, 0.2)]
const BAG_COLORS := [Color(0.96, 0.96, 0.94), Color(0.25, 0.45, 0.85), Color(0.14, 0.14, 0.16), Color(0.86, 0.76, 0.56),
	Color(0.92, 0.38, 0.22)]

enum State { STROLL, APPROACH, WAIT_BUY, LEAVE }
enum Archetype { NORMAL, BARGAINER, IMPATIENT, VIP, AILE, EMEKLI } # BARGAINER = İkonik Pazar Teyzesi!
## main.gd bu ağırlıklarla arketip seçer (yoksa eski 0..3 zarını kullanır).
const SPAWN_WEIGHTS := {0: 30, 1: 25, 2: 13, 3: 10, 4: 11, 5: 11}

enum Idle { BREATHE, LOOK, PHONE, TAP, WATCH, INSPECT, ARMS, SCRATCH }

const FRESH_WILTED := 0.45
const FRESH_ROTTEN := 0.2
const FRESH_GREAT := 0.85
const REP_HAPPY := 0.06
const REP_ANGRY := -0.12

## Replikler: durum -> [NORMAL, TEYZE, ACELECİ, VIP, AİLE, EMEKLİ]; boş liste NORMAL'e düşer.
const LINES := {
	"greet": [
		["Kolay gelsin usta!", "Merhaba, bir bakayım...", "Selamün aleyküm, hayırlı işler!", "Ooo maşallah, tezgah dolu!",
			"İyi günler, taze mi bunlar?", "Abi bunlar bugün mü geldi?"],
		["Evladım kolay gelsin!", "Oğlum bu mallar nereden?", "Kızım bir bakayım hele...", "Aman evladım, her şey ne pahalı!",
			"Allah bereket versin, bakalım...", "Geçen hafta daha ucuzdu bunlar!", "Yavrum seç bana güzelinden!"],
		["Hızlı olalım abi, acelem var!", "Çabuk çabuk, otobüsü kaçıracağım!", "Usta hızlı ver şunları!",
			"Vaktim yok, hemen alayım!", "Toplantım var, çabuk lütfen!"],
		["İyi günler, en iyisinden lütfen.", "Organik mi bunlar?", "Fiyat değil, kalite önemli.",
			"Bana en tazesini seçin lütfen.", "Şöyle premium bir şeyler?"],
		["Hadi bakalım, ne alıyoruz?", "Çocuk meyve istedi, bakalım...", "Kolay gelsin, ufaklığa da bir şey alalım.",
			"Oğlum dokunma, abi kızar!", "Kızım seç bakalım hangisi?"],
		["Hayırlı sabahlar evlat!", "Evlat, sen kimin oğlusun?", "Kırk yıl memurluk yaptım, malın iyisini bilirim!",
			"Ah gençlik... Ben de pazarcıydım bir zamanlar.", "Emekli maaşı yetmiyor evladım..."],
	],
	"wait_ok": [
		["Hmm, hangisini alsam...", "Fiyatlar fena değil.", "Akşama menemen yaparım.", "Şunlar da güzelmiş...",
			"Usta, sıra bende mi?"],
		["Elleme dedin ama bir yoklayayım...", "Akşama dolma yapacağım evladım.", "Gelinim domates istedi...",
			"Bizim zamanımızda kilosu 50 kuruştu!", "Şunun altındakini ver bana!", "Oğlum tartıyı göster bakayım."],
		["Hadi hadi hadi...", "Daha ne kadar?", "Saat kaç oldu ya!", "📱 Geliyorum, beş dakika!"],
		["Bekliyorum...", "Umarım tazedir.", "Sevgilim smoothie istedi.", "Brunch için meyve lazım."],
		["👧 Anneee, muz alalım!", "👦 Babaa, karpuz!", "👧 Ben taşıyacağım!", "Dur bakayım kızım, sabret.",
			"👦 Dondurma var mı burada?"],
		["Bizim zamanımızda domates domates gibiydi evlat...", "Seksenlerde bu pazar daha kalabalıktı.",
			"Torunlar gelecek bu akşam, karpuz şart.", "Benim bel ağrısı yine tuttu...",
			"Kahvede tavla oynayacağız birazdan.", "Bu muhtar da hiç iş yapmıyor evlat!",
			"Askerdeyken bir komutanımız vardı..."],
	],
	"wait_mid": [
		["Usta, bizi de gör!", "Hâlâ bekliyorum ama...", "Sırada mıyım?", "Pardon, burada müşteri var!"],
		["Evladım bana da bak hele!", "Oğlum ben burada köklendim!", "Yavrum, sıra bende değil mi?"],
		["Of of of...", "Hadi abi yaa!", "Bu ne yavaşlık!"],
		["Hizmet biraz yavaş...", "Beklemekten hoşlanmam."],
		["👧 Anne sıkıldım!", "Çocuk huzursuzlandı, hadi abi!"],
		["Acele yok evlat, ama ben de genç değilim.", "Evlat, beni unuttun galiba?"],
	],
	"wait_low": [
		["Gidiyorum bak ha!", "Son kez söylüyorum!", "Başka tezgah mı bulsam?"],
		["Ben öbür tezgaha giderim ha!", "Evladım bu ne iş!", "Annen bilir mi böyle yaptığını?"],
		["TAMAM GİDİYORUM!", "Yeter artık!"],
		["Bu kabul edilemez.", "Yöneticiniz kim?"],
		["👧 ANNEEE GİDELİİİM!", "Çocuk ağlayacak şimdi!"],
		["Ben bu yaşta ayakta duramam evlat...", "Eh, bizim zamanımızda böyle değildi!"],
	],
	"haggle": [
		["Abi %s %d lira olmaz mı?", "%s %d olsun, hemen alayım!", "Usta %s için %d diyelim?", "Hadi be abi, %s %d!"],
		["Evladım %s %d liraya ver hele!", "%s %d lira, son sözüm!", "Oğlum annen yaşındayım, %s %d olsun!",
			"Aaa %s o fiyata mı? %d ver!", "Komşu tezgah %s için %d diyor!"],
		["%s %d, hızlı karar ver!", "%d olsun %s, bekleyemem!"],
		["%s için %d makul olur."],
		["Abi çocuk için, %s %d olsun?", "%s %d lira olur mu? Okul masrafı çok..."],
		["Evlat, emekliye %s %d olsun.", "%s %d lira; emekli indirimi yok mu?"],
	],
	"wilted": [
		["Abi bu %s solmuş! %d lira ancak.", "Bu %s bayat abi, %d olur!", "%s pörsümüş! %d veririm, o kadar.",
			"Hiç taze değil bu %s... %d olsun."],
		["Evladım bu %s solmuş, %d ver de geçelim!", "Aman bu %s dünden kalma! %d olur ancak.",
			"Bu %s'e para mı verilir? %d, o kadar!"],
		["Bu %s solmuş! %d, hızlı!"],
		["Bu %s kalitesiz. %d, en fazla."],
		["Abi bu %s solmuş, çocuk yemez! %d olsun."],
		["Evlat bu %s bayatlamış, %d ver yeter."],
	],
	"rotten": [
		["Iyy, bu %s çürümüş!", "Abi bu %s'in üstünde sinek var!", "Bu %s çöpe gidecek abi!"],
		["Tövbe tövbe, bu %s çürük!", "Evladım bu %s'i kime satacaksın?"],
		["Çürük %s mi? Almam!"],
		["Bu %s kalitesinde ürün almam.", "Bu %s pek taze değil, kalsın."],
		["👧 Iyyy anne, kokuyor!"],
		["Evlat, bu %s çürümüş, yazık!"],
	],
	"fresh": [
		["Maşallah, %s taptaze!", "Oh, %s mis gibi!", "Bu %s bahçeden yeni gelmiş!"],
		["Bu %s bahçeden yeni toplanmış gibi evladım!", "Maşallah, %s ne güzel parlıyor!"],
		["%s taze, tamam alıyorum!"],
		["%s gerçekten taze, tebrikler."],
		["👦 Vay, ne güzel %s!"],
		["Eskisi gibi %s, maşallah evlat!"],
	],
	"happy": [
		["😊 Teşekkürler, bereketli olsun!", "😊 Hayırlı işler usta!", "😊 Eline sağlık!", "😊 Yine gelirim!"],
		["😊 Bereketli olsun evladım!", "😊 Allah razı olsun oğlum!", "😊 Hayırlı satışlar yavrum!",
			"😊 Sana dua edeceğim evladım!"],
		["⚡ Süper, hızlı oldu!", "⚡ İşte bu, teşekkürler!"],
		["⭐ Mükemmel servis!", "⭐ Çok memnun kaldım!"],
		["😊 Çocuk çok sevindi, sağ ol!", "😊 Bak oğlum, abiye teşekkür et!"],
		["😊 Eyvallah evlat, Allah bereket versin!", "😊 Sen iyi çocuksun, babana selam söyle!"],
	],
	"angry_wait": [
		["😕 Çok bekledim...", "😕 Kimse ilgilenmiyor...", "😕 Başka tezgaha gidiyorum."],
		["😤 Bu ne saygısızlık evladım!", "😤 Bir daha gelmem buraya!", "😤 Senin annen bilir mi bunu?"],
		["😤 Çok bekledim!", "😤 Zaman nakittir abi!", "😤 Otobüsü kaçırdım senin yüzünden!"],
		["😒 Böyle hizmet olmaz.", "😒 Hiç profesyonel değil."],
		["😢 Çocuk ağlamaya başladı, gidiyoruz!", "😕 Çocuk sıkıldı, hadi gidelim."],
		["😕 Eh, gençler hep aceleci... Ben gideyim.", "😕 Ne sohbet var ne alışveriş..."],
	],
	"angry_price": [
		["😤 Pahalıymış abi...", "😤 Bu fiyata almam!", "😤 Kazık bu, kazık!"],
		["😤 Çok pahalıymış, öbür tezgaha bakayım!", "😤 Vicdan yok sende evladım!",
			"😤 Emekli maaşım bu kadar değil evladım!"],
		["😤 Pazarlığa vaktim yok, gidiyorum!"],
		["😒 Bu fiyat/performans değil."],
		["😤 Bu fiyata çocuğa meyve mi alınır!"],
		["😤 Kırk yıl çalıştım, böyle fiyat görmedim!"],
	],
	"angry_rotten": [
		["😖 Hepsi çürük, kalsın!", "😖 Bu ne biçim mal abi!"],
		["😖 Tövbe! Hepsi çürük evladım!", "😖 Bunları satmaya utanmıyor musun?"],
		["😖 Çürük mal, vakit kaybı!"],
		["😒 Bu kaliteyle olmaz."],
		["😖 Çocuğa çürük meyve mi yedireceğim!"],
		["😖 Yazık, mal israf olmuş evlat."],
	],
	"moveon": [
		["🤷 Başka tezgaha bakayım...", "🤷 Kalanı başka yerden alırım."],
		["🤷 Kalanını öbür tezgahtan alırım evladım."],
		["🤷 Neyse, başka yere!"],
		["🤷 Başka bir tezgah deneyeyim."],
		["🤷 Hadi kızım, öbür tezgaha!"],
		["🤷 Ben biraz daha dolaşayım evlat."],
	],
	"stroll": [
		["🎵 Hmm hmm hmm...", "Bugün ne pişirsem?", "Akşama menemen yaparım.", "Pazar keyfi başka!",
			"Nerede o domatesçi?"],
		["Şu fiyatlara bak, tövbe!", "Akşama dolma yapacağım...", "Bizim zamanımızda kilosu 50 kuruştu!",
			"Gelin hanım yine bir şey almamış...", "Aman şu kalabalığa bak!"],
		["📱 Geliyorum geliyorum!", "Hızlı hızlı...", "Nerede bu tezgah?", "📱 Alo? Pazardayım!"],
		["Organik bir şey var mı acaba?", "Brunch için meyve lazım.", "📱 Bir story atayım."],
		["👧 Anneee muz alalım!", "👦 Babaa karpuz!", "👧 Ben de taşımak istiyorum!", "👦 Balonum uçmasın!"],
		["Kahveye uğrasam mı...", "Bizim zamanımızda...", "Tavla oynayacak adam lazım.",
			"Torunlar gelecek bu akşam.", "Ah dizlerim..."],
	],
	"lure": [
		["Aa, şuradan sesleniyorlar!", "Ne diyor, ne diyor?", "Şuraya bir bakayım!"],
		["Kim bağırıyor öyle evladım?", "Sesi güzel, malı da güzeldir!", "Dur bakayım ne satıyor!"],
		["Tamam tamam, geliyorum!"],
		["Hmm, ilginç bir tezgah."],
		["👧 Anne şuraya gidelim!", "👦 Baba bak orada karpuz var!"],
		["Ses bizim mahallenin pazarcısına benziyor...", "Evlat bağırma, geliyorum!"],
	],
	"rain": [
		["☔ Of bu yağmur da...", "☔ Islandık be!", "☔ Şemsiyeyi iyi ki aldım!", "☔ Yağmurda pazar başka güzel!"],
		["☔ Aman evladım, domatesler ıslanmasın!", "☔ Romatizmam azdı bu yağmurda!"],
		["☔ Bir de yağmur yağıyor, hızlı!"],
		["☔ Ayakkabılarım mahvoldu!"],
		["👧 Yağmurda zıplamak istiyorum!", "☔ Kızım su birikintisine basma!"],
		["☔ Bu yağmur tarlaya iyi gelir.", "☔ Eskiden yağmur daha bereketliydi."],
	],
	"cloudy": [
		["☁️ Hava kapalı, yağacak galiba.", "☁️ Şemsiye almadım ya..."],
		["☁️ Evladım çamaşırları toplasam mı?"],
		["☁️ Yağmur başlamadan bitireyim!"],
		[], [], ["☁️ Dizlerim sızlıyor, yağmur gelir."],
	],
	"event": [
		["🔥 %s bugün bereketliymiş, duydum!", "🔥 Herkes %s alıyor!"],
		["🔥 Komşu kızı %s kapış kapış dedi!", "🔥 %s indirimdeymiş evladım!"],
		["🔥 %s lazım, çabuk!"], ["🔥 Bugünün yıldızı %s!"], ["👧 Anne, %s! %s!"],
		["🔥 Radyoda söylediler, %s bereketliymiş."],
	],
	"drunk": [
		["Abi sen iyi misin?"],
		["😤 Utanmaz, sabah sabah!", "😤 Evladım bu ne hal!", "😤 Tövbe tövbe, içkili esnaftan alınmaz!",
			"😤 Annen görse ne der!"],
		[], [], [],
		["😤 Evlat, ayıp ayıp! Pazarda içilir mi?", "😤 Bizim zamanımızda esnaf ayık olurdu!",
			"😤 Kırk yıl memurluk yaptım, böyle esnaf görmedim!"],
	],
	"tip": [
		["😊 Al, bahşiş! +%d TL"], [], ["⚡ Süper hız! +%d TL Bahşiş!"], ["⭐ Harika servis! +%d TL Bahşiş!"],
		["😊 Çocuğu sevindirdin! +%d TL"], ["😊 Al evlat, çay paran! +%d TL"],
	],
}

var state: int = State.STROLL
var archetype: int = Archetype.NORMAL
var color_seed := 0
var wants: Dictionary = {}
var offers: Dictionary = {}
var bought_items: Array = []
var target_owner_id := 0
var target_pos := Vector3.ZERO
var exit_pos := Vector3(0, 0, 21.5)
var walk_speed := 1.72
var max_wait := 28.0
var wait_timer := 28.0
var eval_timer := 0.0
var mood_text := ""
var say_text := ""
var emote_text := ""
var _last_bubble_txt := ""

# Host AI zamanlayıcıları
var _say_t := 0.0
var _emote_t := 0.0
var _chat_cd := 6.0
var _pause_t := 0.0
var _switch_cd := 0.0 # daha yüksek sesli tezgaha geçiş soğuması
var _browse_cd := 8.0
var _bought_here := 0
var _patience_stage := 0
var _rng := RandomNumberGenerator.new()

# Görsel
var rig: Node3D
var head: Node3D
var parts := {}
var rest := {}
var _fem := false
var _lean_base := 0.0
var _sway_amt := 0.05
var _stride_len := 0.26
var _popup_pivot: Node3D
var _card_root: Node3D
var _popup_card: MeshInstance3D
var _popup_border: MeshInstance3D
var _popup_tail: MeshInstance3D
var _popup_border_mat: StandardMaterial3D
var _popup_bg_mat: StandardMaterial3D
var _popup_tw: Tween
var bubble: Label3D
var _icon_lbl: Label3D
var _emote_lbl: Label3D
var _emote_tw: Tween
var _bubble_base_y := 2.0
var _card_h := 0.3
var _bubble_refresh_t := 0.0
var _far_mode := false
var _bag_anchor: Node3D
var _bag_items_root: Node3D
var _trolley_wheels: Array[Node3D] = []
var _has_trolley := false
var _patience_root: Node3D
var _patience_fill: MeshInstance3D
var _patience_mat: StandardMaterial3D
var _phone: Node3D
var _umbrella: Node3D
var _umbrella_open := 0.0
var _raining := false
var _weather := "clear"
var _wx_t := 0.0
var _kid: Node3D
var _kid_parts := {}
var _kid_rest := {}
var _kid_hop := 0.0
var _balloon: Node3D
var _idle_kind: int = Idle.BREATHE
var _idle_t := 0.0
var _anim_off := 0.0
var _body_yaw := 0.0
var _phase := 0.0
var _spd := 0.0
var _react_jump := 0.0
var _react_shake := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_spd := 0.0
var _sync_t := 0.0
var _full_sync_t := 0.0
var _sync_dirty := true
var _life := 0.0
var _blink_t := 2.4
var _eyes: Array[Node3D] = []
var _mouth: Node3D
var _reserved_owner := 0

static var _mesh_cache := {}
static var _mat_cache := {}
static var _tint_cache := {}
static var _filtered_cache := {}


func init_customer(p_name: String, p_seed: int, start_pos: Vector3, p_exit: Vector3,
		p_wants: Dictionary, p_archetype: int = Archetype.NORMAL) -> void:
	name = p_name
	color_seed = p_seed
	archetype = clampi(p_archetype, 0, Archetype.size() - 1)
	position = start_pos
	_net_pos = start_pos
	exit_pos = p_exit
	target_pos = p_exit
	wants = p_wants.duplicate()
	_rng.seed = hash(p_name) ^ p_seed
	_anim_off = float(absi(p_seed) % 97) * 0.37
	_chat_cd = _rng.randf_range(2.0, 9.0)
	_browse_cd = _rng.randf_range(5.0, 12.0)
	# Sakin, doğal Türk pazarı gezinme temposu
	match archetype:
		Archetype.IMPATIENT:
			walk_speed = 2.45
			max_wait = 15.0
		Archetype.BARGAINER: # Pazar Teyzesi: ağır ağır gezer, sabırlı ama sıkı pazarlıkçı!
			walk_speed = 1.48
			max_wait = 32.0
		Archetype.VIP:
			walk_speed = 1.78
			max_wait = 26.0
		Archetype.AILE:
			walk_speed = 1.6
			max_wait = 22.0
		Archetype.EMEKLI: # Ağır ağır yürür, çok sabırlı, uzun uzun sohbet eder
			walk_speed = 1.22
			max_wait = 42.0
		_:
			walk_speed = 1.68 + float(absi(p_seed) % 4) * 0.08
			max_wait = 28.0
	wait_timer = max_wait


func _ready() -> void:
	match archetype:
		Archetype.BARGAINER:
			_build_teyze_visual()
		_:
			_build_visual()
	_build_popup_bubble_patience_and_area()
	_update_weather(true)
	_refresh_bag_visual()
	_refresh_bubble()
	_cache_face_nodes()


func _exit_tree() -> void:
	_release_spot()


func _cache_face_nodes() -> void:
	_eyes.clear()
	_mouth = null
	if head == null:
		return
	for en in ["EyeL", "EyeR"]:
		var e := head.find_child(en, true, false) as Node3D
		if e:
			_eyes.append(e)
	_mouth = head.find_child("Mouth", true, false) as Node3D


func _release_spot() -> void:
	if _reserved_owner != 0:
		var old_st := _find_stall(_reserved_owner)
		if old_st and old_st.has_method("release_customer_spot"):
			old_st.release_customer_spot(name)
		_reserved_owner = 0


# ---------------------------------------------------------------- mesh / materyal önbellekleri

static func _cm(key: String, builder: Callable) -> Mesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = builder.call()
	return _mesh_cache[key]


static func _cmat(c: Color, rough := 0.88, metal := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	if not _mat_cache.has(key):
		_mat_cache[key] = LP.mat(c, rough, metal)
	return _mat_cache[key]


static func _add(parent: Node, key: String, builder: Callable, pos: Vector3, c: Color, rot := Vector3.ZERO,
		rough := 0.88, metal := 0.0) -> MeshInstance3D:
	return LP.add_mat(parent, _cm(key, builder), pos, _cmat(c, rough, metal), rot)


static func _tinted(mat: BaseMaterial3D, c: Color) -> BaseMaterial3D:
	var key := mat.resource_name + "|" + c.to_html()
	if not _tint_cache.has(key):
		var d := mat.duplicate() as BaseMaterial3D
		d.albedo_color = c
		_tint_cache[key] = d
	return _tint_cache[key]


## GLB kafasından istenmeyen yüzeyleri (kasket, bıyık/saç) atan önbellekli mesh.
static func _filtered_mesh(src: Mesh, exclude: Array) -> Mesh:
	var key := str(src.get_instance_id()) + ":" + ",".join(exclude)
	if _filtered_cache.has(key):
		return _filtered_cache[key]
	var am := ArrayMesh.new()
	for i in src.get_surface_count():
		var m := src.surface_get_material(i)
		if m and m.resource_name in exclude:
			continue
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
		am.surface_set_material(am.get_surface_count() - 1, m)
	_filtered_cache[key] = am
	return am


func _pal(arr: Array, salt: int) -> Variant:
	return arr[absi(color_seed * 7 + salt * 13 + salt * salt) % arr.size()]


# ---------------------------------------------------------------- görseller

## GLB karakterini parça parça (Body/Head/eller/ayaklar) kurar, renkleri boyar.
func _build_figure(model: PackedScene, into_rig: Node3D, into_head: Node3D, cols: Dictionary, head_exclude: Array,
		out_parts: Dictionary, out_rest: Dictionary) -> void:
	var src := model.instantiate()
	for n in PART_NAMES:
		var m: Node3D = src.find_child(n, true, false)
		var w := Node3D.new()
		w.name = n
		out_rest[n] = m.position
		m.get_parent().remove_child(m)
		m.owner = null
		m.transform = Transform3D.IDENTITY
		w.add_child(m)
		if n == "Head" and m is MeshInstance3D and not head_exclude.is_empty():
			(m as MeshInstance3D).mesh = _filtered_mesh((m as MeshInstance3D).mesh, head_exclude)
		if n == "Head" and into_head:
			into_head.add_child(w)
			into_head.position = out_rest[n]
		else:
			into_rig.add_child(w)
			w.position = out_rest[n]
		out_parts[n] = w
		var meshes: Array = w.find_children("*", "MeshInstance3D", true, false)
		if m is MeshInstance3D:
			meshes.append(m)
		for mi: MeshInstance3D in meshes:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i) as BaseMaterial3D
				if mat and cols.has(mat.resource_name):
					mi.set_surface_override_material(i, _tinted(mat, cols[mat.resource_name]))
	src.free()


func _build_visual() -> void:
	rig = Node3D.new()
	add_child(rig)
	head = Node3D.new()
	add_child(head)

	var skin: Color = _pal(SKINS, 1)
	var hair: Color = _pal(HAIRS, 2)
	var shirt: Color = _pal(SHIRTS, 3)
	var pants: Color = _pal(PANTS, 4)
	var hat_c: Color = _pal(HAT_COLORS, 5)
	var v := absi(color_seed * 31 + 7)
	_fem = (v % 2) == 0
	var keep_hat := false
	var keep_hair := true
	match archetype:
		Archetype.VIP:
			shirt = Color(0.18, 0.14, 0.24) if not _fem else Color(0.95, 0.93, 0.88)
			pants = Color(0.14, 0.13, 0.16)
		Archetype.IMPATIENT:
			shirt = [Color(0.96, 0.42, 0.12), Color(0.14, 0.5, 0.9), Color(0.85, 0.15, 0.2)][v % 3]
			pants = Color(0.16, 0.17, 0.2)
			_fem = (v % 3) == 0
		Archetype.EMEKLI:
			_fem = false
			hair = _pal(GREY_HAIRS, 2)
			shirt = [Color(0.55, 0.48, 0.38), Color(0.36, 0.4, 0.34), Color(0.5, 0.36, 0.28), Color(0.62, 0.62, 0.6)][v % 4]
			pants = Color(0.34, 0.32, 0.3)
			keep_hat = true
		Archetype.AILE:
			pass
		_:
			keep_hat = not _fem and (v % 5) < 2
	# Kadın saç stili: 0 = başörtülü (modelin saçı atılır), 2 = topuz, 3 = at kuyruğu
	var fem_style := v % 4
	if archetype == Archetype.VIP:
		fem_style = 1
	var scarf := _fem and (fem_style == 0 or (archetype == Archetype.AILE and v % 3 == 0))
	if _fem:
		keep_hat = false
		keep_hair = not scarf
	elif not keep_hat and (v % 7) == 3:
		keep_hair = false # sinekkaydı tıraşlı genç: bıyıksız
	var excl := []
	if not keep_hat:
		excl.append_array(["Hat", "HatDetail"])
	if not keep_hair:
		excl.append("Hair" if _fem else "Mustache")
	var cols := {
		"Skin": skin, "Lid": skin.darkened(0.06), "SkinLid": skin.darkened(0.03),
		"Hair": hair, "Mustache": hair, "Brow": hair.darkened(0.15), "Shirt": shirt, "Pants": pants,
		"Hat": hat_c, "HatDetail": hat_c.darkened(0.2),
	}
	var model: PackedScene = MODEL_WOMAN if _fem else MODEL_MAN
	if archetype == Archetype.EMEKLI:
		model = MODEL_EMEKLI
	_build_figure(model, rig, head, cols, excl, parts, rest)

	# Beden çeşitliliği: tombul/zayıf, uzun/kısa
	var wfac := 0.9 + float(absi(color_seed * 17) % 7) * 0.05
	var hfac := 0.94 + float(absi(color_seed * 23) % 5) * 0.03
	if archetype == Archetype.VIP:
		wfac = minf(wfac, 1.0)
	elif archetype == Archetype.EMEKLI:
		wfac = maxf(wfac, 1.05)
	(parts["Body"] as Node3D).scale = Vector3(wfac, hfac, wfac)
	for hn in ["HandL", "HandR"]:
		rest[hn] = Vector3(rest[hn].x * (0.55 + wfac * 0.45), rest[hn].y * hfac, rest[hn].z)
	rest["Head"] = rest["Head"] + Vector3(0, (hfac - 1.0) * 0.55, 0)
	head.position = rest["Head"]
	for n in ["HandL", "HandR"]:
		parts[n].position = rest[n]

	var h := parts["Head"] as Node3D
	# Saç / başörtüsü / şapka (saç modelde; burada yalnızca ekler)
	if _fem:
		if scarf:
			_add_headscarf(h, _pal(SCARF_COLORS, 6), 1.36)
		elif fem_style == 2:
			_add(h, "hair_bun", func(): return LP.sphere(0.13, 8, 5), Vector3(0, 0.3, -0.24), hair)
		elif fem_style == 3:
			_add(h, "hair_tail", func(): return LP.ellipsoid(0.09, 0.2, 0.09, 6, 4), Vector3(0, -0.12, -0.38), hair, Vector3(0.5, 0, 0))
	elif not keep_hat:
		if archetype == Archetype.NORMAL and v % 4 == 1:
			# ters kep
			var cap_c: Color = _pal(SHIRTS, 9)
			_add(h, "cap_dome", func(): return LP.ellipsoid(0.34, 0.2, 0.35, 10, 5), Vector3(0, 0.2, -0.02), cap_c)
			_add(h, "cap_bill", func(): return LP.box(Vector3(0.3, 0.03, 0.24)), Vector3(0, 0.22, -0.4), cap_c.darkened(0.2))

	match archetype:
		Archetype.VIP:
			if _fem:
				var hat_col := Color(0.96, 0.9, 0.72)
				_add(h, "sunhat_brim", func(): return LP.cyl(0.62, 0.62, 0.03, 14), Vector3(0, 0.26, -0.02), hat_col)
				_add(h, "sunhat_crown", func(): return LP.cyl(0.26, 0.32, 0.2, 12), Vector3(0, 0.36, -0.02), hat_col)
				_add(h, "sunhat_band", func(): return LP.cyl(0.325, 0.325, 0.05, 12), Vector3(0, 0.29, -0.02), Color(0.7, 0.16, 0.24))
			else:
				_add(h, "top_brim", func(): return LP.cyl(0.38, 0.38, 0.04, 12), Vector3(0, 0.3, 0), Color(0.12, 0.11, 0.15))
				_add(h, "top_crown", func(): return LP.cyl(0.25, 0.24, 0.34, 12), Vector3(0, 0.48, 0), Color(0.12, 0.11, 0.15))
				_add(h, "top_band", func(): return LP.cyl(0.255, 0.255, 0.06, 12), Vector3(0, 0.35, 0), Color(0.95, 0.78, 0.2), Vector3.ZERO, 0.25, 0.85)
			_add_glasses(h, true)
		Archetype.IMPATIENT:
			_add(h, "band", func(): return LP.torus(0.31, 0.36, 12, 5), Vector3(0, 0.16, 0), Color(1.0, 0.76, 0.14))
			_add_phone()
		Archetype.EMEKLI:
			# gözlük ve kamburluk modelde; baston
			var hl := parts["HandL"] as Node3D
			_add(hl, "cane", func(): return LP.cyl(0.018, 0.018, 0.56, 5), Vector3(0, -0.26, 0.02), Color(0.36, 0.22, 0.12))
			_add(hl, "cane_top", func(): return LP.torus(0.03, 0.05, 8, 4), Vector3(0, 0.02, 0.06), Color(0.36, 0.22, 0.12), Vector3(0, PI / 2, 0))
			_lean_base = 0.04
			_stride_len = 0.2
		Archetype.AILE:
			_build_kid()
		_:
			if v % 4 == 2:
				_add_glasses(h, v % 8 == 6)
			if v % 3 == 0:
				_add_phone()
	if archetype in [Archetype.NORMAL, Archetype.AILE] and not _fem and v % 3 == 1:
		_add_glasses(h, false)

	# Kadınlarda etek
	if _fem and archetype != Archetype.IMPATIENT and v % 3 != 1:
		_add(parts["Body"], "skirt", func(): return LP.cyl(0.25, 0.33, 0.3, 10), Vector3(0, -0.16, 0), _pal(SHIRTS, 11).darkened(0.15))

	# Çanta tipi: poşet, file, bez çanta, sepet ya da pazar arabası
	var bag_kind := absi(color_seed * 11 + 3) % 6
	if archetype == Archetype.VIP:
		bag_kind = 6
	elif archetype == Archetype.IMPATIENT:
		bag_kind = 0
	elif archetype == Archetype.EMEKLI:
		bag_kind = 1
	if bag_kind == 5 and archetype == Archetype.NORMAL:
		_build_trolley(_pal(SCARF_COLORS, 8))
	else:
		_build_hand_bag(bag_kind % 5 if bag_kind != 6 else 6)

	var sc := 0.94 + float(absi(color_seed) % 5) * 0.03
	if archetype == Archetype.VIP:
		sc = 1.06
	elif archetype == Archetype.EMEKLI:
		sc = 0.95
	scale = Vector3(sc, sc, sc)
	_bubble_base_y = 1.95 + float(absi(color_seed) % 3) * 0.12


func _add_headscarf(h: Node3D, c: Color, k: float) -> void:
	# Arka kabuk + alın bandı + çene altı düğümü; yüzü açık bırakır
	_add(h, "scarf_back_%.2f" % k, func(): return LP.ellipsoid(0.272 * k, 0.28 * k, 0.24 * k, 10, 6),
		Vector3(0, 0.03 * k, -0.1 * k), c)
	_add(h, "scarf_top_%.2f" % k, func(): return LP.ellipsoid(0.262 * k, 0.13 * k, 0.24 * k, 10, 5),
		Vector3(0, 0.17 * k, -0.01 * k), c.lightened(0.06))
	_add(h, "scarf_chin_%.2f" % k, func(): return LP.cyl(0.19 * k, 0.24 * k, 0.16 * k, 9),
		Vector3(0, -0.17 * k, -0.06 * k), c.darkened(0.08))


func _add_glasses(h: Node3D, sun: bool) -> void:
	var frame := Color(0.1, 0.09, 0.1) if not sun else Color(0.85, 0.7, 0.25)
	for sx: float in [-0.094, 0.094]:
		if sun:
			_add(h, "sun_lens", func(): return LP.cyl(0.066, 0.066, 0.012, 10), Vector3(sx, 0.045, 0.3), Color(0.05, 0.05, 0.07), Vector3(PI / 2, 0, 0), 0.15, 0.4)
		_add(h, "glass_ring", func(): return LP.torus(0.06, 0.072, 12, 4), Vector3(sx, 0.045, 0.302), frame, Vector3(PI / 2, 0, 0), 0.3, 0.6)
	_add(h, "glass_bridge", func(): return LP.box(Vector3(0.07, 0.014, 0.014)), Vector3(0, 0.055, 0.31), frame, Vector3.ZERO, 0.3, 0.6)


func _add_phone() -> void:
	_phone = Node3D.new()
	_phone.position = Vector3(0.0, 0.02, 0.07)
	(parts["HandR"] as Node3D).add_child(_phone)
	_add(_phone, "phone", func(): return LP.box(Vector3(0.075, 0.14, 0.014)), Vector3.ZERO, Color(0.08, 0.08, 0.1), Vector3.ZERO, 0.3, 0.3)
	_add(_phone, "phone_scr", func(): return LP.box(Vector3(0.062, 0.12, 0.004)), Vector3(0, 0, 0.009), Color(0.45, 0.75, 1.0))
	_phone.hide()


func _build_hand_bag(kind: int) -> void:
	_bag_anchor = Node3D.new()
	_bag_anchor.position = Vector3(0.0, -0.24, 0.06)
	(parts["HandR"] as Node3D).add_child(_bag_anchor)
	var c: Color = _pal(BAG_COLORS, 7)
	var top := 0.11
	match kind:
		0: # naylon poşet
			_add(_bag_anchor, "bag_poset", func(): return LP.box(Vector3(0.24, 0.28, 0.1)), Vector3(0, -0.02, 0), c)
			_add(_bag_anchor, "bag_poset_h", func(): return LP.torus(0.05, 0.065, 8, 4), Vector3(0, 0.15, 0), c.darkened(0.1), Vector3(0, 0, 0))
		1: # file (fileli pazar çantası)
			var fc := Color(0.2, 0.62, 0.3) if color_seed % 2 == 0 else Color(0.92, 0.45, 0.15)
			_add(_bag_anchor, "bag_file", func(): return LP.cyl(0.13, 0.09, 0.26, 6), Vector3(0, -0.02, 0), fc, Vector3.ZERO, 0.6)
			_add(_bag_anchor, "bag_file_h", func(): return LP.torus(0.07, 0.085, 8, 4), Vector3(0, 0.15, 0), fc.darkened(0.25), Vector3(PI / 2, 0, 0))
			top = 0.09
		2: # bez çanta
			_add(_bag_anchor, "bag_tote", func(): return LP.box(Vector3(0.26, 0.26, 0.08)), Vector3(0, -0.02, 0), Color(0.9, 0.84, 0.7))
			_add(_bag_anchor, "bag_tote_p", func(): return LP.box(Vector3(0.12, 0.08, 0.01)), Vector3(0, -0.02, 0.045), c)
			_add(_bag_anchor, "bag_tote_h", func(): return LP.torus(0.06, 0.075, 8, 4), Vector3(0, 0.15, 0), Color(0.8, 0.72, 0.58), Vector3(PI / 2, 0, 0))
		3: # hasır sepet
			_add(_bag_anchor, "basket", func(): return LP.cyl(0.15, 0.12, 0.18, 8), Vector3(0, -0.04, 0), Color(0.72, 0.52, 0.28))
			_add(_bag_anchor, "basket_h", func(): return LP.torus(0.12, 0.14, 10, 4), Vector3(0, 0.08, 0), Color(0.6, 0.42, 0.22), Vector3(0, 0, PI / 2))
			top = 0.04
		6: # VIP deri el çantası
			_add(_bag_anchor, "bag_vip", func(): return LP.box(Vector3(0.22, 0.22, 0.14)), Vector3.ZERO, Color(0.24, 0.18, 0.32))
			_add(_bag_anchor, "bag_vip_c", func(): return LP.box(Vector3(0.06, 0.03, 0.02)), Vector3(0, 0.04, 0.075), Color(0.95, 0.78, 0.2), Vector3.ZERO, 0.25, 0.85)
			_add(_bag_anchor, "bag_vip_h", func(): return LP.torus(0.055, 0.072, 8, 4), Vector3(0, 0.15, 0), Color(0.16, 0.12, 0.22), Vector3(PI / 2, 0, 0))
		_: # kese kağıdı
			_add(_bag_anchor, "bag_paper", func(): return LP.box(Vector3(0.22, 0.26, 0.16)), Vector3(0, -0.01, 0), Color(0.78, 0.62, 0.42))
	_bag_items_root = Node3D.new()
	_bag_items_root.position = Vector3(0, top, 0)
	_bag_anchor.add_child(_bag_items_root)


## Tekerlekli ekose PAZAR ARABASI (aldıkça içi meyve dolar!)
func _build_trolley(t_col: Color) -> void:
	_has_trolley = true
	var trolley := Node3D.new()
	trolley.position = Vector3(-0.38, 0.0, -0.44)
	rig.add_child(trolley)
	_add(trolley, "tr_body", func(): return LP.box(Vector3(0.30, 0.44, 0.24)), Vector3(0, 0.34, 0), t_col)
	_add(trolley, "tr_stripe", func(): return LP.box(Vector3(0.31, 0.06, 0.25)), Vector3(0, 0.44, 0), Color(0.95, 0.90, 0.80))
	_add(trolley, "tr_stripe", func(): return LP.box(Vector3(0.31, 0.06, 0.25)), Vector3(0, 0.24, 0), Color(0.95, 0.90, 0.80))
	_add(trolley, "tr_stripe_v", func(): return LP.box(Vector3(0.05, 0.45, 0.25)), Vector3(0.06, 0.34, 0), t_col.darkened(0.25))
	_add(trolley, "tr_pole", func(): return LP.cyl(0.012, 0.012, 0.68, 5), Vector3(0, 0.48, 0.15), Color(0.65, 0.66, 0.68), Vector3(0.32, 0, 0), 0.4, 0.6)
	_add(trolley, "tr_grip", func(): return LP.box(Vector3(0.22, 0.03, 0.03)), Vector3(0, 0.78, 0.26), Color(0.18, 0.18, 0.2))
	_trolley_wheels.clear()
	for wx: float in [-0.17, 0.17]:
		var wh := _add(trolley, "tr_wheel", func(): return LP.cyl(0.095, 0.095, 0.035, 8), Vector3(wx, 0.095, -0.02), Color(0.16, 0.16, 0.18), Vector3(0, 0, PI / 2))
		_trolley_wheels.append(wh)
	_bag_items_root = Node3D.new()
	_bag_items_root.position = Vector3(0, 0.56, 0)
	trolley.add_child(_bag_items_root)


## Ailenin yanındaki çocuk (kozmetik; ebeveynle birlikte yürür, sıkılınca zıplar, bazen balonu var).
func _build_kid() -> void:
	_kid = Node3D.new()
	_kid.position = Vector3(0.66, 0.0, 0.08)
	_kid.scale = Vector3(0.62, 0.62, 0.62)
	rig.add_child(_kid)
	var kv := absi(color_seed * 5 + 1)
	var kid_shirt: Color = [Color(1.0, 0.82, 0.2), Color(0.95, 0.35, 0.55), Color(0.3, 0.75, 0.95), Color(0.45, 0.85, 0.4)][kv % 4]
	var kid_skin: Color = _pal(SKINS, 1)
	var kid_hair: Color = _pal(HAIRS, 12)
	var cols := {"Skin": kid_skin, "Lid": kid_skin.darkened(0.06), "SkinLid": kid_skin.darkened(0.03),
		"Shirt": kid_shirt, "Pants": Color(0.25, 0.35, 0.6), "Hair": kid_hair, "Brow": kid_hair.darkened(0.1)}
	_build_figure(MODEL_KID, _kid, null, cols, [], _kid_parts, _kid_rest)
	var kh := _kid_parts["Head"] as Node3D
	if kv % 2 == 0:
		# iki yandan örgülü kız çocuğu
		for sx: float in [-0.3, 0.3]:
			_add(kh, "kid_pig", func(): return LP.sphere(0.1, 6, 4), Vector3(sx, 0.0, -0.12), kid_hair)
	if kv % 3 != 2:
		_balloon = Node3D.new()
		_balloon.position = Vector3(0, 0.0, 0.0)
		(_kid_parts["HandL"] as Node3D).add_child(_balloon)
		var bc: Color = [Color(0.95, 0.2, 0.25), Color(0.2, 0.55, 0.95), Color(1.0, 0.8, 0.15)][kv % 3]
		_add(_balloon, "bal_str", func(): return LP.cyl(0.006, 0.006, 1.6, 3), Vector3(0, 0.8, 0), Color(0.9, 0.9, 0.9))
		_add(_balloon, "bal_ball", func(): return LP.ellipsoid(0.24, 0.29, 0.24, 9, 6), Vector3(0, 1.82, 0), bc, Vector3.ZERO, 0.3)


## Bıyıksız, kasketsiz, başörtülü, gözlüklü, çiçekli hırkalı ve tekerlekli pazar arabalı İKONİK PAZAR TEYZESİ!
func _build_teyze_visual() -> void:
	rig = Node3D.new()
	add_child(rig)
	head = Node3D.new()
	add_child(head)
	_fem = true

	var scarf_col: Color = SCARF_COLORS[absi(color_seed) % SCARF_COLORS.size()]
	var cardigan_col: Color = SHIRTS[absi(color_seed * 5 + 2) % SHIRTS.size()]
	var skirt_col := cardigan_col.darkened(0.32)
	var skin_col: Color = [Color(0.93, 0.78, 0.66), Color(0.86, 0.68, 0.54), Color(0.96, 0.84, 0.74)][absi(color_seed) % 3]
	var wfac := 1.0 + float(absi(color_seed * 3) % 4) * 0.06 # teyzeler biraz tombul olur

	# Model: yemeni + oyalar, al yanak, hırka, uzun etek, çiçekli önlük (char_teyze.glb)
	var cols := {"Skin": skin_col, "Lid": skin_col.darkened(0.06), "SkinLid": skin_col.darkened(0.03),
		"Hat": scarf_col, "Shirt": cardigan_col, "Pants": skirt_col}
	var excl := [] if absi(color_seed) % 4 != 3 else ["Glasses"] # her teyze gözlüklü değil
	_build_figure(MODEL_TEYZE, rig, head, cols, excl, parts, rest)
	(parts["Body"] as Node3D).scale = Vector3(wfac, 1.0, wfac)
	for hn in ["HandL", "HandR"]:
		rest[hn] = Vector3(rest[hn].x * (0.7 + wfac * 0.3), rest[hn].y, rest[hn].z)
		(parts[hn] as Node3D).position = rest[hn]

	_build_trolley(Color(0.76, 0.18, 0.24) if (color_seed % 2 == 0) else Color(0.18, 0.38, 0.66))
	_sway_amt = 0.1 # teyze yürüyüşü: hafif paytak
	_stride_len = 0.22
	scale = Vector3(0.96, 0.96, 0.96)
	_bubble_base_y = 1.78 + float(absi(color_seed) % 3) * 0.12


func _build_umbrella() -> void:
	_umbrella = Node3D.new()
	_umbrella.position = Vector3(0.22, 0.0, 0.04)
	rig.add_child(_umbrella)
	var uc: Color = _pal(UMBRELLA_COLORS, 14)
	var top_y := 1.92 if archetype != Archetype.BARGAINER else 1.62
	if archetype == Archetype.VIP:
		top_y += 0.18
	_add(_umbrella, "umb_pole", func(): return LP.cyl(0.014, 0.014, 1.2, 5), Vector3(0, top_y - 0.6, 0), Color(0.2, 0.2, 0.22), Vector3.ZERO, 0.4, 0.5)
	_add(_umbrella, "umb_canopy", func(): return LP.cyl(0.03, 0.78, 0.3, 8), Vector3(0, top_y + 0.02, 0), uc, Vector3.ZERO, 0.35)
	_add(_umbrella, "umb_rim", func(): return LP.cyl(0.78, 0.8, 0.03, 8), Vector3(0, top_y - 0.14, 0), uc.darkened(0.2), Vector3.ZERO, 0.35)
	_add(_umbrella, "umb_tip", func(): return LP.sphere(0.03, 5, 3), Vector3(0, top_y + 0.19, 0), Color(0.2, 0.2, 0.22))
	_umbrella.scale = Vector3(0.05, 0.05, 0.05)
	_umbrella.hide()


func _refresh_bag_visual() -> void:
	if _bag_items_root == null:
		return
	for c in _bag_items_root.get_children():
		c.queue_free()
	for i in mini(bought_items.size(), 6):
		var item_id: String = str(bought_items[i])
		var ox := -0.055 + float(i % 2) * 0.11
		var oy := float(int(i / 2)) * 0.068
		var oz := -0.035 + float((i + 1) % 2) * 0.07
		Produce.build_mesh(_bag_items_root, item_id, Vector3(ox, oy, oz), 0.052)


# ---------------------------------------------------------------- konuşma kartı

## Kameraya dönen, uzaklıkla büyüyen, opak (okunaklı) konuşma kartı + emote + kart içi sabır çubuğu.
func _build_popup_bubble_patience_and_area() -> void:
	_popup_pivot = Node3D.new()
	_popup_pivot.position = Vector3(0, _bubble_base_y, 0)
	add_child(_popup_pivot)
	_card_root = Node3D.new()
	_popup_pivot.add_child(_card_root)

	_popup_border_mat = StandardMaterial3D.new()
	_popup_border_mat.albedo_color = Color(0.16, 0.11, 0.08)
	_popup_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_popup_border_mat.disable_fog = true
	_popup_bg_mat = StandardMaterial3D.new()
	_popup_bg_mat.albedo_color = Color(1.0, 0.98, 0.92)
	_popup_bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_popup_bg_mat.disable_fog = true

	_popup_border = MeshInstance3D.new()
	_popup_border.mesh = QuadMesh.new()
	_popup_border.position = Vector3(0, 0, -0.012)
	_popup_border.material_override = _popup_border_mat
	_popup_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card_root.add_child(_popup_border)

	_popup_card = MeshInstance3D.new()
	_popup_card.mesh = QuadMesh.new()
	_popup_card.position = Vector3(0, 0, -0.004)
	_popup_card.material_override = _popup_bg_mat
	_popup_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card_root.add_child(_popup_card)

	# Konuşma balonu alt ok ucu (çerçeveli)
	var tail_b := MeshInstance3D.new()
	var tbq := QuadMesh.new()
	tbq.size = Vector2(0.2, 0.2)
	tail_b.mesh = tbq
	tail_b.position = Vector3(0, 0.1, -0.014)
	tail_b.rotation.z = PI / 4.0
	tail_b.material_override = _popup_border_mat
	tail_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card_root.add_child(tail_b)
	_popup_tail = MeshInstance3D.new()
	var tq := QuadMesh.new()
	tq.size = Vector2(0.15, 0.15)
	_popup_tail.mesh = tq
	_popup_tail.position = Vector3(0, 0.12, -0.006)
	_popup_tail.rotation.z = PI / 4.0
	_popup_tail.material_override = _popup_bg_mat
	_popup_tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card_root.add_child(_popup_tail)

	bubble = Label3D.new()
	bubble.position = Vector3(0, 0, 0.012)
	bubble.font_size = 42
	bubble.pixel_size = 0.0032
	bubble.outline_size = 6
	bubble.double_sided = false
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.width = 660.0
	bubble.modulate = Color(0.10, 0.07, 0.05)
	bubble.outline_modulate = Color(1.0, 0.98, 0.92)
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_card_root.add_child(bubble)
	_icon_lbl = Label3D.new()
	_icon_lbl.font_size = bubble.font_size
	_icon_lbl.pixel_size = bubble.pixel_size
	_icon_lbl.outline_size = 0
	_icon_lbl.modulate = Color.WHITE
	_icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_icon_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_card_root.add_child(_icon_lbl)

	# Kart altında sabır çubuğu
	_patience_root = Node3D.new()
	var bg := MeshInstance3D.new()
	var bg_m := QuadMesh.new()
	bg_m.size = Vector2(1.0, 0.075)
	bg.mesh = bg_m
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.16, 0.13)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.disable_fog = true
	bg.material_override = bg_mat
	_patience_root.add_child(bg)
	_patience_fill = MeshInstance3D.new()
	var fg_m := QuadMesh.new()
	fg_m.size = Vector2(1.0, 0.05)
	_patience_fill.mesh = fg_m
	_patience_fill.position = Vector3(0, 0, 0.004)
	_patience_mat = StandardMaterial3D.new()
	_patience_mat.albedo_color = Color(0.35, 0.95, 0.42)
	_patience_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_patience_mat.disable_fog = true
	_patience_fill.material_override = _patience_mat
	_patience_root.add_child(_patience_fill)
	_patience_root.hide()
	_card_root.add_child(_patience_root)

	_emote_lbl = Label3D.new()
	_emote_lbl.font_size = 80
	_emote_lbl.pixel_size = 0.0042
	_emote_lbl.outline_size = 14
	_emote_lbl.outline_modulate = Color(0.1, 0.07, 0.05)
	_emote_lbl.modulate = Color.WHITE
	_emote_lbl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_emote_lbl.hide()
	_popup_pivot.add_child(_emote_lbl)

	var area := Area3D.new()
	area.name = "CustomerArea"
	area.collision_layer = 4
	area.collision_mask = 0
	area.set_meta("kind", "customer")
	area.set_meta("customer_name", name)
	area.set_meta("hl_size", Vector3(0.88, 1.55, 0.88))
	area.position = Vector3(0, 0.85, 0)
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.45; sh.height = 1.65
	cs.shape = sh
	area.add_child(cs)
	add_child(area)


func archetype_tag() -> String:
	match archetype:
		Archetype.BARGAINER:
			return "🧣 Teyze"
		Archetype.IMPATIENT:
			return "⚡ Aceleci"
		Archetype.VIP:
			return "⭐ VIP"
		Archetype.AILE:
			return "🎈 Aile"
		Archetype.EMEKLI:
			return "👴 Emekli"
		_:
			return ""


func _lines(sit: String) -> Array:
	var per: Array = LINES.get(sit, [])
	if per.is_empty():
		return []
	var a: Array = per[archetype] if archetype < per.size() else []
	if a.is_empty():
		a = per[0]
	return a


## Tüm eşlerde aynı sonucu veren deterministik replik seçimi.
func _pick(sit: String, salt := 0) -> String:
	var a := _lines(sit)
	if a.is_empty():
		return ""
	return str(a[absi(hash(name) + salt * 7919) % a.size()])


func _rand_line(sit: String) -> String:
	var a := _lines(sit)
	if a.is_empty():
		return ""
	return str(a[_rng.randi() % a.size()])


static func _fmt_item(fmt: String, item_name: String, price := -1) -> String:
	var n := fmt.count("%s")
	var has_d := fmt.contains("%d")
	var args := []
	for i in n:
		args.append(item_name)
	if has_d:
		args.append(price)
	if args.is_empty():
		return fmt
	# Sıra: tüm %s'ler önce gelmeyebilir — her iki sırayı destekle
	if has_d and fmt.find("%d") < fmt.find("%s"):
		args = [price]
		for i in n:
			args.append(item_name)
	return fmt % args


static func _is_emoji_token(tok: String) -> bool:
	if tok == "" or tok.length() > 4:
		return false
	for i in tok.length():
		var cp := tok.unicode_at(i)
		if cp < 0x2190 and cp != 0x200D:
			return false
	return true


static func _is_happy_mood(s: String) -> bool:
	return s.begins_with("😊") or s.begins_with("⭐") or s.begins_with("⚡") or "Bereketli" in s


func _item_fresh(st, item_id: String) -> float:
	if st and item_id != "" and st.has_method("get_item_freshness"):
		return float(st.get_item_freshness(item_id))
	return 1.0


func _wants_line() -> String:
	var segs := PackedStringArray()
	for k in wants:
		var cnt: int = int(wants[k])
		if cnt > 0 and StallScript.ITEMS.has(k):
			segs.append("%dx %s" % [cnt, StallScript.ITEMS[k]["name"]])
	if segs.is_empty():
		return ""
	return ", ".join(segs)


## Kart metni + renkleri: [metin, çerçeve, zemin]
func _compose_bubble() -> Array:
	var border_c := Color(0.22, 0.16, 0.12)
	var bg_c := Color(1.0, 0.98, 0.92)
	if mood_text != "":
		if _is_happy_mood(mood_text):
			return [mood_text, Color(0.18, 0.68, 0.28), Color(0.9, 1.0, 0.92)]
		if mood_text.begins_with("🤷"):
			return [mood_text, Color(0.45, 0.45, 0.5), Color(0.95, 0.95, 0.97)]
		return [mood_text, Color(0.82, 0.22, 0.18), Color(1.0, 0.9, 0.88)]
	var wl := _wants_line()
	if wl == "":
		return [say_text, border_c, bg_c] if say_text != "" else ["", border_c, bg_c]
	var line1 := ""
	var tag := archetype_tag()
	var icon := (tag.get_slice(" ", 0) + " ") if tag != "" else "💬 "
	if state == State.WAIT_BUY:
		icon = (tag + ": ") if tag != "" else "🛒 "
		border_c = Color(0.88, 0.64, 0.10)
		bg_c = Color(1.0, 0.97, 0.86)
		var st: Node3D = _find_stall(target_owner_id)
		var cur := _current_item(st) if st else ""
		if offers.has(cur):
			var nm: String = StallScript.ITEMS[cur]["name"]
			var wilted := _item_fresh(st, cur) < FRESH_WILTED
			line1 = "🤔 " + _fmt_item(_pick("wilted" if wilted else "haggle", hash(cur)), nm, int(offers[cur]))
			border_c = Color(0.92, 0.48, 0.12) if not wilted else Color(0.55, 0.42, 0.18)
			bg_c = Color(1.0, 0.95, 0.84) if not wilted else Color(0.96, 0.93, 0.8)
		elif say_text != "":
			line1 = say_text
		else:
			var ratio := clampf(wait_timer / maxf(max_wait, 1.0), 0.0, 1.0)
			var elapsed := max_wait - wait_timer
			var step := int(elapsed / (6.0 if archetype == Archetype.EMEKLI else 4.5))
			if ratio < 0.25:
				line1 = _pick("wait_low", step)
			elif ratio < 0.55:
				line1 = _pick("wait_mid", step)
			elif step == 0:
				line1 = _pick("greet", 1)
			else:
				line1 = _pick("wait_ok", step)
			if ratio < 0.25:
				border_c = Color(0.86, 0.3, 0.16)
	else:
		line1 = say_text
	if _far_mode and not line1.begins_with("🤔"):
		line1 = ""
	var txt := (line1 + "\n" + icon + wl) if line1 != "" else (icon + wl)
	return [txt, border_c, bg_c]


func _refresh_bubble() -> void:
	if bubble == null or _popup_pivot == null:
		return
	var comp := _compose_bubble()
	var txt: String = comp[0]
	if txt == "":
		_card_root.hide()
		_last_bubble_txt = ""
		return
	_card_root.show()
	_popup_border_mat.albedo_color = comp[1]
	_popup_bg_mat.albedo_color = comp[2]
	bubble.outline_modulate = comp[2]
	if txt == _last_bubble_txt:
		return
	# Renkli emojiler koyu yazı rengine boyanmasın: satır başı emojileri ayrı beyaz ikon sütununa al
	var icons := PackedStringArray()
	var body := PackedStringArray()
	var any_icon := false
	for ln in txt.split("\n"):
		var tok := ln.get_slice(" ", 0)
		if ln.contains(" ") and _is_emoji_token(tok):
			icons.append(tok)
			body.append(ln.substr(tok.length() + 1))
			any_icon = true
		else:
			icons.append("")
			body.append(ln)
	var body_txt := "\n".join(body)
	bubble.text = body_txt
	_icon_lbl.text = "\n".join(icons) if any_icon else ""
	# Gerçek metin ölçüsüyle kart boyutu
	var font := bubble.font if bubble.font else ThemeDB.fallback_font
	var sz := font.get_multiline_string_size(body_txt, HORIZONTAL_ALIGNMENT_CENTER, bubble.width, bubble.font_size)
	var icon_w := 0.2 if any_icon else 0.0
	var w := clampf(sz.x * bubble.pixel_size + 0.24 + icon_w, 0.7, bubble.width * bubble.pixel_size + 0.3 + icon_w)
	var h := maxf(sz.y * bubble.pixel_size + 0.14, 0.28)
	var bar_h := 0.0
	if state == State.WAIT_BUY and mood_text == "":
		bar_h = 0.09
	_card_h = h + bar_h
	var cy := 0.16 + _card_h * 0.5
	(_popup_card.mesh as QuadMesh).size = Vector2(w, _card_h)
	(_popup_border.mesh as QuadMesh).size = Vector2(w + 0.07, _card_h + 0.07)
	_popup_card.position.y = cy
	_popup_border.position.y = cy
	var top_y := 0.16 + _card_h - 0.07
	bubble.position = Vector3(icon_w * 0.5, top_y, 0.012)
	_icon_lbl.position = Vector3(-w * 0.5 + 0.15, top_y, 0.012)
	_patience_root.position = Vector3(0, 0.16 + 0.065, 0.002)
	_patience_root.scale = Vector3(w - 0.16, 1.0, 1.0)
	_emote_lbl.position = Vector3(-w * 0.5 - 0.12, cy + _card_h * 0.5 + 0.06, 0.03)
	var changed_kind := _last_bubble_txt.get_slice("\n", 0) != txt.get_slice("\n", 0)
	_last_bubble_txt = txt
	if changed_kind:
		if _popup_tw and _popup_tw.is_valid():
			_popup_tw.kill()
		_card_root.scale = Vector3(0.55, 0.55, 0.55)
		_popup_tw = create_tween()
		_popup_tw.tween_property(_card_root, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop_emote(e: String) -> void:
	if _emote_lbl == null or e == "":
		return
	_emote_lbl.text = e
	_emote_lbl.show()
	_emote_lbl.modulate.a = 1.0
	_emote_lbl.outline_modulate.a = 1.0
	if _emote_tw and _emote_tw.is_valid():
		_emote_tw.kill()
	_emote_lbl.scale = Vector3(0.2, 0.2, 0.2)
	_emote_tw = create_tween()
	_emote_tw.tween_property(_emote_lbl, "scale", Vector3(1.25, 1.25, 1.25), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_emote_tw.tween_property(_emote_lbl, "scale", Vector3.ONE, 0.12)
	_emote_tw.tween_interval(1.3)
	_emote_tw.tween_property(_emote_lbl, "modulate:a", 0.0, 0.35)
	_emote_tw.parallel().tween_property(_emote_lbl, "outline_modulate:a", 0.0, 0.35)
	_emote_tw.tween_callback(_emote_lbl.hide)


func _update_patience_bar() -> void:
	if _patience_root == null:
		return
	if state != State.WAIT_BUY or mood_text != "":
		_patience_root.hide()
		return
	_patience_root.show()
	var ratio := clampf(wait_timer / maxf(max_wait, 1.0), 0.0, 1.0)
	_patience_fill.scale = Vector3(maxf(ratio, 0.02) * 0.96, 1.0, 1.0)
	_patience_fill.position.x = -(1.0 - maxf(ratio, 0.02) * 0.96) * 0.5
	if ratio > 0.55:
		_patience_mat.albedo_color = Color(0.35, 0.95, 0.42)
	elif ratio > 0.25:
		_patience_mat.albedo_color = Color(1.0, 0.82, 0.22)
	else:
		var pulse := 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.018)
		_patience_mat.albedo_color = Color(1.0 * pulse, 0.22, 0.18)


func _process(dt: float) -> void:
	# Konuşma kartı daima kameraya baksın + uzaklıkla büyüsün (uzaktan okunur!)
	if _popup_pivot == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - _popup_pivot.global_position
	var d := to_cam.length()
	var hide_far := d > 24.0
	_popup_pivot.visible = not hide_far
	if hide_far:
		return
	to_cam.y = 0.0
	if to_cam.length_squared() > 0.001:
		_popup_pivot.global_rotation = Vector3(0, atan2(to_cam.x, to_cam.z), 0)
	var s := clampf(d / 8.5, 0.85, 1.45) / maxf(scale.x, 0.5)
	_popup_pivot.scale = Vector3(s, s, s)
	var py := _bubble_base_y + (0.34 if _umbrella and _umbrella.visible else 0.0)
	_popup_pivot.position.y = lerpf(_popup_pivot.position.y, py, minf(dt * 6.0, 1.0))
	var far := d > 14.0
	_bubble_refresh_t -= dt
	if far != _far_mode or _bubble_refresh_t <= 0.0:
		_far_mode = far
		_bubble_refresh_t = 0.4
		_refresh_bubble()


# ---------------------------------------------------------------- ana döngü

func _physics_process(dt: float) -> void:
	var is_host := (not Net.online()) or multiplayer.is_server()
	_wx_t -= dt
	if _wx_t <= 0.0:
		_wx_t = 1.0
		_update_weather(false)
	if is_host:
		_life += dt
		if _drunk_scold_cd > 0.0:
			_drunk_scold_cd = maxf(_drunk_scold_cd - dt, 0.0)
		if _life > 160.0 and state != State.LEAVE:
			_go_leave(_rand_line("moveon"))
		_tick_ai(dt)
		_tick_talk(dt)
		_sync_t += dt
		_full_sync_t += dt
		if Net.online() and _sync_t >= 0.1:
			_sync_t = 0.0
			if _sync_dirty or _full_sync_t >= 1.0:
				_sync_dirty = false
				_full_sync_t = 0.0
				rpc_sync_state.rpc(position, _body_yaw, _spd, state, target_owner_id, wants, offers, mood_text, wait_timer, say_text, emote_text)
			else:
				rpc_sync_pose.rpc(position, _body_yaw, _spd, wait_timer)
	else:
		# Hız tabanlı öngörü + yumuşak takip (ağ gecikmesinde kayma/titreme yok)
		var lead := _net_pos + Vector3(sin(_net_yaw), 0.0, cos(_net_yaw)) * (_net_spd * 0.06)
		if position.distance_squared_to(lead) > 16.0:
			position = _net_pos
			reset_physics_interpolation() # ışınlanmada eski konumdan kayarak gelmesin
		else:
			position = position.lerp(lead, minf(dt * 12.0, 1.0))
		_body_yaw = lerp_angle(_body_yaw, _net_yaw, minf(dt * 12.0, 1.0))
		_spd = lerpf(_spd, _net_spd, minf(dt * 10.0, 1.0))
	_update_patience_bar()
	_animate(dt)


func _world() -> Node:
	var n: Node = get_parent()
	while n:
		if n.name == "World":
			return n
		n = n.get_parent()
	return get_parent().get_parent() if get_parent() else null


func _update_weather(instant: bool) -> void:
	var w := _world()
	_weather = str(w.get_meta("weather", "clear")) if w else "clear"
	var rain := _weather == "rain"
	if rain == _raining and not instant:
		return
	_raining = rain
	if rain and _umbrella == null:
		_build_umbrella()
	if _umbrella:
		if rain:
			_umbrella.show()
		var tw := create_tween()
		tw.tween_property(_umbrella, "scale", Vector3.ONE if rain else Vector3(0.05, 0.05, 0.05), 0.35 if not instant else 0.01) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if not rain:
			tw.tween_callback(_umbrella.hide)


func _speed_mult() -> float:
	return (1.15 if _raining else 1.0) * 0.92 # sakin tempo


var _drunk_scold_cd := 0.0


func _evening() -> bool:
	var sc := get_tree().current_scene
	return sc != null and sc.has_method("_day_prog") and float(sc.call("_day_prog")) >= 0.80


func _say(txt: String, dur := 3.2) -> void:
	if txt == "":
		return
	say_text = txt
	_say_t = dur
	_sync_dirty = true
	_refresh_bubble()


func _emote(e: String, dur := 1.8) -> void:
	emote_text = e
	_emote_t = dur
	_sync_dirty = true
	_pop_emote(e)


## Host: sohbet balonları, emote'lar ve sabır eşikleri.
func _tick_talk(dt: float) -> void:
	if _say_t > 0.0:
		_say_t -= dt
		if _say_t <= 0.0:
			say_text = ""
			_refresh_bubble()
	if _emote_t > 0.0:
		_emote_t -= dt
		if _emote_t <= 0.0:
			emote_text = ""
	if state == State.STROLL or state == State.APPROACH:
		_chat_cd -= dt
		if _chat_cd <= 0.0:
			var chatty := archetype == Archetype.EMEKLI or archetype == Archetype.AILE
			_chat_cd = _rng.randf_range(5.0, 10.0) if chatty else _rng.randf_range(8.0, 17.0)
			if say_text == "" and _rng.randf() < (0.8 if chatty else 0.55):
				_say(_chatter_line(), 5.0 if archetype == Archetype.EMEKLI else 3.4)
				if archetype == Archetype.AILE and _rng.randf() < 0.4:
					_emote("🎈" if _balloon else "😄")
				elif archetype == Archetype.NORMAL and _rng.randf() < 0.25:
					_emote("🎵")
	elif state == State.WAIT_BUY and mood_text == "":
		var ratio := wait_timer / maxf(max_wait, 1.0)
		var stage := 0 if ratio > 0.3 else (1 if ratio > 0.12 else 2)
		if stage > _patience_stage:
			_patience_stage = stage
			_emote("💢" if stage == 1 else "😤")


func _chatter_line() -> String:
	var ev := _active_event_item()
	if ev != "" and wants.has(ev) and StallScript.ITEMS.has(ev) and _rng.randf() < 0.5:
		return _fmt_item(_rand_line("event"), StallScript.ITEMS[ev]["name"])
	if _weather == "rain" and _rng.randf() < 0.6:
		return _rand_line("rain")
	if _weather == "cloudy" and _rng.randf() < 0.3:
		return _rand_line("cloudy")
	return _rand_line("stroll")


func _go_leave(mood: String) -> void:
	_release_spot()
	mood_text = mood
	state = State.LEAVE
	target_owner_id = 0
	target_pos = exit_pos
	say_text = ""
	_sync_dirty = true
	_refresh_bubble()


func _rep(owner_id: int, delta: float) -> void:
	var st := _find_stall(owner_id)
	if st and st.has_method("add_reputation"):
		st.add_reputation(delta)


func _tick_ai(dt: float) -> void:
	var sm := _speed_mult()
	_switch_cd = maxf(_switch_cd - dt, 0.0)
	match state:
		State.STROLL:
			if _pause_t > 0.0:
				# Vitrin bakışı: bir an durup tezgahlara göz atar
				_pause_t -= dt
				_spd = 0.0
			else:
				_move_toward_target(dt, walk_speed * sm)
				_browse_cd -= dt
				if _browse_cd <= 0.0:
					_browse_cd = _rng.randf_range(7.0, 14.0)
					if not _raining and _rng.randf() < (0.5 if archetype in [Archetype.BARGAINER, Archetype.EMEKLI] else 0.3):
						_pause_t = _rng.randf_range(1.4, 3.0)
						if archetype != Archetype.IMPATIENT and _rng.randf() < 0.4:
							_emote("👀")
			eval_timer -= dt
			if eval_timer <= 0.0:
				eval_timer = 0.35
				_evaluate_stalls(false)
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.3:
				queue_free()
		State.APPROACH:
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st):
				state = State.STROLL
				target_owner_id = 0
				target_pos = exit_pos
				_refresh_bubble()
				return
			# Yürürken başka bir pazarcı ÇOK DAHA GÜÇLÜ bağırırsa ona dön!
			eval_timer -= dt
			if eval_timer <= 0.0:
				eval_timer = 0.65
				_evaluate_stalls(true)
			_move_toward_target(dt, walk_speed * 1.15 * sm)
			if Vector2(position.x - target_pos.x, position.z - target_pos.z).length() < 0.38:
				_arrive_at_stall(st)
		State.WAIT_BUY:
			_spd = 0.0
			var drain := 1.0
			if archetype == Archetype.AILE and wait_timer < max_wait * 0.5:
				drain = 1.25 # çocuk sıkılıyor!
			wait_timer -= dt * drain
			# Başka tezgahtan çok daha yüksek bağıran varsa ona dönebilir
			if _bought_here == 0 and wait_timer > 3.0:
				eval_timer -= dt
				if eval_timer <= 0.0:
					eval_timer = 1.2
					_evaluate_stalls(true)
					if state == State.APPROACH:
						return
			var st := _find_stall(target_owner_id)
			if st == null or not _stall_has_any_want(st) or _total_wants() <= 0 or wait_timer <= 0.0:
				var owner := target_owner_id
				if _total_wants() <= 0:
					_go_leave(_rand_line("happy"))
					_trigger_reaction(true)
					if _bought_here > 0:
						_rep(owner, REP_HAPPY)
				elif wait_timer <= 0.0:
					_go_leave(_rand_line("angry_wait"))
					_rep(owner, REP_ANGRY)
					if Net.online():
						rpc_on_angry.rpc(mood_text)
					else:
						_trigger_reaction(false)
				else:
					# Bu tezgahta kalmadı: aldıysa memnun, kalanlar için başka tezgaha bakar
					if _bought_here > 0:
						_rep(owner, REP_HAPPY)
					state = State.STROLL
					target_owner_id = 0
					target_pos = exit_pos
					eval_timer = 1.5
					_say(_rand_line("moveon"), 2.6)
				_bought_here = 0
		State.LEAVE:
			_move_toward_target(dt, walk_speed * 1.08 * sm)
			if Vector2(position.x - exit_pos.x, position.z - exit_pos.z).length() < 1.3:
				queue_free()


func _arrive_at_stall(st: Node3D) -> void:
	state = State.WAIT_BUY
	_spd = 0.0
	wait_timer = max_wait
	_patience_stage = 0
	_bought_here = 0
	var look_dir: Vector3 = st.global_position - global_position
	_body_yaw = atan2(look_dir.x, look_dir.z)
	# Çürük ürünleri istemez (VIP solmuşu bile istemez!)
	var reject_lim := FRESH_WILTED if archetype == Archetype.VIP else FRESH_ROTTEN
	var rotten_item := ""
	for k in wants.keys():
		if int(wants[k]) > 0 and st.has_item(k) and _item_fresh(st, k) < reject_lim:
			wants.erase(k)
			rotten_item = k
	if rotten_item != "" and (_total_wants() <= 0 or not _stall_has_any_want(st)):
		var owner := target_owner_id
		if _total_wants() <= 0:
			_go_leave(_rand_line("angry_rotten"))
			_rep(owner, REP_ANGRY)
			if Net.online():
				rpc_on_angry.rpc(mood_text)
			else:
				_trigger_reaction(false)
		else:
			_rep(owner, REP_ANGRY * 0.5)
			state = State.STROLL
			target_owner_id = 0
			target_pos = exit_pos
			_emote("🤢")
			_say(_fmt_item(_rand_line("rotten"), StallScript.ITEMS[rotten_item]["name"]), 3.0)
		return
	_make_offers(st)
	var cur := _current_item(st)
	if rotten_item != "":
		_emote("🤢")
		_say(_fmt_item(_rand_line("rotten"), StallScript.ITEMS[rotten_item]["name"]), 3.0)
	elif cur != "" and not offers.has(cur) and _item_fresh(st, cur) > FRESH_GREAT and _rng.randf() < 0.5:
		_emote("😍")
		_say(_fmt_item(_rand_line("fresh"), StallScript.ITEMS[cur]["name"]), 3.0)
	else:
		say_text = ""
	_refresh_bubble()
	if not offers.is_empty():
		Sfx.play_3d("haggle", global_position + Vector3(0, 1.3, 0), self, -6.0)
		_emote("🤔", 1.4)


func _move_toward_target(dt: float, speed: float) -> void:
	var diff := Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	var dist := diff.length()
	if dist < 0.05:
		_spd = 0.0
		return
	var dir := diff / dist
	# Yakındaki diğer müşterilerden yumuşakça ayrıl (iç içe geçme önlenir)
	if get_parent():
		var sep := Vector3.ZERO
		for other in get_parent().get_children():
			if other == self or not (other is Node3D):
				continue
			var dv := Vector3(position.x - (other as Node3D).position.x, 0.0, position.z - (other as Node3D).position.z)
			var d2 := dv.length_squared()
			if d2 > 0.0004 and d2 < 0.42:
				sep += dv.normalized() * (0.65 - sqrt(d2))
		if sep.length_squared() > 0.001:
			dir = (dir + sep * 1.1).normalized()
	dir = StallScript.world_steer_all(self, position, dir, dist - 0.2)
	var next_p := StallScript.world_keepout_all(self, position + dir * minf(speed * dt, dist))
	# Kaldırım yüksekliği (x > 4.25 iken yumuşak 4 cm çıkış)
	var tgt_y := 0.04 if absf(next_p.x) > 4.25 else 0.0
	next_p.y = lerpf(position.y, tgt_y, minf(dt * 12.0, 1.0))
	position = next_p
	_body_yaw = lerp_angle(_body_yaw, atan2(dir.x, dir.z), minf(dt * 8.0, 1.0))
	_spd = speed


## Güçlendirilmiş bağırma odaklı tezgah seçimi: daha yüksek bağıran (veya Megafon kullanan) pazarcı müşteriyi kazanır!
## v0.6: ürün tazeliği ve tezgah itibarı da hesaba katılır.
func _evaluate_stalls(only_louder_override: bool) -> void:
	var stalls := _all_stalls()
	if stalls.is_empty():
		return
	var ev := _active_event_item()
	var cur_shout := 0.0
	if only_louder_override and target_owner_id != 0:
		var cur_owner := _find_player(target_owner_id)
		if cur_owner and cur_owner.has_method("get_effective_shout"):
			cur_shout = cur_owner.get_effective_shout()

	var best_stall = null
	var best_score := 0.0
	var best_shout := 0.0
	var reject_lim := FRESH_WILTED if archetype == Archetype.VIP else FRESH_ROTTEN

	for st in stalls:
		var owner := _find_player(st.owner_id)
		# Teyze ve emekli amca sarhoş pazarcıdan almaz, laf sokar
		if owner and int(owner.get("drunk_level") if owner.get("drunk_level") != null else 0) >= 1 \
				and archetype in [Archetype.BARGAINER, Archetype.EMEKLI]:
			if _drunk_scold_cd <= 0.0 and global_position.distance_to(owner.global_position) < 9.0:
				_drunk_scold_cd = 14.0
				_say(_rand_line("drunk"), 3.2)
			continue
		var eff_shout := 0.0
		var hearing_range := 35.0 # 22 x 1.6
		if owner and owner.global_position.distance_to(st.global_position) < 9.6:
			eff_shout = owner.get_effective_shout() if owner.has_method("get_effective_shout") else float(owner.shout_power)
			if owner.has_method("is_holding_item") and owner.is_holding_item("megafon"):
				hearing_range = 54.0
		var dist := global_position.distance_to(st.global_position)
		if dist > hearing_range:
			continue
		var matched := 0
		var price_sum := 0.0
		for k in wants:
			if int(wants[k]) > 0 and st.has_item(k):
				var fr := _item_fresh(st, k)
				if fr < reject_lim:
					continue
				var ps := StallScript.relative_price_score(k, st.get_item_price(k), stalls, ev)
				if fr < FRESH_WILTED:
					ps *= 0.5 # solmuş mal: çok daha isteksiz
				elif fr > FRESH_GREAT:
					ps *= 1.1 # taptaze: küçük bonus
				matched += 1
				price_sum += ps
		if matched == 0:
			continue
		var avg_price_score := price_sum / float(matched)
		if avg_price_score < 0.14:
			continue

		# Bağırma dominansı: daha yüksek dB / Megafon doğrusal değil üstel avantaj sağlar!
		var shout_score := 0.0
		if owner and eff_shout > 0.08:
			var heard := global_position.distance_to(owner.global_position)
			var falloff := 0.028 if hearing_range > 40.0 else 0.05
			shout_score = clampf(pow(eff_shout, 1.3) / (1.0 + heard * falloff), 0.0, 2.4)
		if st.bell_boost > 0.0:
			shout_score = maxf(shout_score, clampf(1.55 / (1.0 + dist * 0.05), 0.45, 1.6))

		# Ek çekicilik bonusları: Süslü Işıklar, Arabesk Radyo, Küba Purosu Prestiji!
		var charm := 0.0
		if st.has_upgrade("lights") and _evening():
			charm += 0.10 # ampuller akşam pazarında yanar
		if st.has_radio and st.radio_playing:
			charm += 0.18 if archetype != Archetype.EMEKLI else 0.3 # amca arabeske bayılır
		if owner and owner.has_method("has_prestige_aura") and owner.has_prestige_aura():
			charm += 0.18 if archetype == Archetype.VIP else 0.10
		# Bira dökülen tezgah veya bira kokan pazarcı müşterileri kaçırır!
		var st_stink: float = float(st.get("stink_t")) if st.get("stink_t") != null else 0.0
		if st_stink > 0.0:
			charm -= 0.42
			if _drunk_scold_cd <= 0.0 and dist < 8.5:
				_drunk_scold_cd = 10.0
				_emote("🤢")
				_say("🤢 Iyy! Bu tezgah leş gibi bira kokuyor!", 2.8)
		var own_stink: float = float(owner.get("stink_t")) if (owner and owner.get("stink_t") != null) else 0.0
		if own_stink > 0.0:
			charm -= 0.26
			if _drunk_scold_cd <= 0.0 and dist < 7.5:
				_drunk_scold_cd = 10.0
				_emote("🤢")
				_say("🤢 Pazarcı leş gibi bira kokuyor, uzak dur!", 2.8)

		var variety := clampf(float(matched) / float(maxi(wants.size(), 1)), 0.0, 1.0)
		var proximity := clampf(1.0 - dist / hearing_range, 0.0, 1.0)
		var busy := _count_customers_at(st.owner_id)
		# Bağırma ağırlığı %62 (baskın!), fiyat %28, çeşit/yakınlık %10 + tezgah cazibesi
		var score := shout_score * 0.62 * clampf(avg_price_score, 0.45, 1.15) \
			+ avg_price_score * 0.28 + (variety * 0.55 + proximity * 0.45) * 0.10 \
			+ charm - float(busy) * (0.20 if archetype != Archetype.IMPATIENT else 0.32)
		# Tezgah itibarı (⭐) çarpanı
		if st.has_method("reputation_mult"):
			score *= float(st.reputation_mult())

		if score > best_score:
			best_score = score
			best_stall = st
			best_shout = eff_shout

	if best_stall == null:
		return
	if only_louder_override:
		# Başka bir pazarcı açık ara daha güçlü bağırıyorsa ona çevril!
		# Soğuma süresi + olasılık: titrek davranmasın
		if _switch_cd <= 0.0 and best_stall.owner_id != target_owner_id and best_shout > cur_shout + 0.35 and best_shout >= 0.55 \
				and _rng.randf() < 0.55:
			_release_spot()
			_switch_cd = 7.0
			target_owner_id = best_stall.owner_id
			_reserved_owner = target_owner_id
			state = State.APPROACH
			_pause_t = 0.0
			_bought_here = 0
			_sync_dirty = true
			target_pos = best_stall.reserve_customer_spot(name) if best_stall.has_method("reserve_customer_spot") else best_stall.customer_spot(best_stall.spot_offset(_count_customers_at(target_owner_id)))
			_emote("❗")
			_say(_rand_line("lure"), 2.2)
		return

	var lure_prob := clampf(best_score * 0.85 + (0.28 if best_shout >= 0.5 else 0.0), 0.14, 0.97)
	if best_score > 0.24 and _rng.randf() < lure_prob:
		_release_spot()
		target_owner_id = best_stall.owner_id
		_reserved_owner = target_owner_id
		target_pos = best_stall.reserve_customer_spot(name) if best_stall.has_method("reserve_customer_spot") else best_stall.customer_spot(best_stall.spot_offset(_count_customers_at(target_owner_id)))
		state = State.APPROACH
		_pause_t = 0.0
		_sync_dirty = true
		if best_shout >= 0.5:
			_emote("❗")
			_say(_rand_line("lure"), 2.2)
		_refresh_bubble()


func _make_offers(st) -> void:
	offers.clear()
	var stalls := _all_stalls()
	var ev := _active_event_item()
	for k in wants:
		if int(wants[k]) <= 0 or not st.has_item(k):
			continue
		var price: int = st.get_item_price(k)
		var fr := _item_fresh(st, k)
		if archetype == Archetype.VIP:
			continue # VIP pazarlık etmez (solmuşu zaten reddetti)
		var score := StallScript.relative_price_score(k, price, stalls, ev)
		var prob := clampf(1.15 - score, 0.15, 0.85)
		var discount := 0.80
		match archetype:
			Archetype.BARGAINER:
				prob = clampf(prob + 0.42, 0.55, 0.96)
				discount = 0.74
			Archetype.IMPATIENT:
				prob *= 0.45
			Archetype.EMEKLI:
				prob = clampf(prob * 0.6 + 0.12, 0.12, 0.5)
				discount = 0.85
			Archetype.AILE:
				prob = clampf(prob + 0.1, 0.2, 0.9)
		var wants_offer := (score <= 1.06 or archetype == Archetype.BARGAINER) and _rng.randf() < prob
		if fr < FRESH_WILTED:
			# Solmuş mal: neredeyse herkes indirim ister, hem de derin!
			wants_offer = _rng.randf() < 0.92
			discount = 0.6 if archetype == Archetype.BARGAINER else 0.66
		if price >= 2 and wants_offer:
			offers[k] = clampi(roundi(price * discount), 1, price - 1)


func try_sell_one_from(seller_id: int, insist := false) -> Dictionary:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return {}
	var st := _find_stall(seller_id)
	var k := _current_item(st) if st else ""
	if k == "":
		return {}
	var ev := _active_event_item()
	var offer: int = int(offers.get(k, 0))
	var was_haggle := offer > 0
	var fr := _item_fresh(st, k)
	if insist:
		if offer <= 0:
			return {}
		offers.erase(k)
		var base_ch := StallScript.relative_price_score(k, st.get_item_price(k), _all_stalls(), ev) * 0.8
		if archetype == Archetype.BARGAINER:
			base_ch *= 0.72
		elif archetype == Archetype.EMEKLI:
			base_ch *= 1.1
		if fr < FRESH_WILTED:
			base_ch *= 0.55 # solmuş malda tam fiyat ısrarı pek tutmaz
		var chance := clampf(base_ch, 0.1, 0.9)
		if _rng.randf() >= chance:
			var owner := target_owner_id
			_go_leave(_rand_line("angry_price"))
			_rep(owner, REP_ANGRY)
			if Net.online():
				rpc_on_angry.rpc(mood_text)
			else:
				_trigger_reaction(false)
			return {}
		offer = 0
		was_haggle = false
	var price: int = st.consume_for_sale(k)
	if price <= 0:
		return {}
	if offer > 0:
		price = mini(price, offer)
	wants[k] = int(wants[k]) - 1
	if int(wants[k]) <= 0:
		wants.erase(k)
		offers.erase(k)
	bought_items.append(k)
	_bought_here += 1

	var tip := 0
	if archetype == Archetype.IMPATIENT and wait_timer / maxf(max_wait, 1.0) >= 0.55:
		tip += _rng.randi_range(4, 7)
	if fr > FRESH_GREAT and offer <= 0:
		tip += maxi(1, roundi(float(price) * 0.08)) # taze mal küçük bonus
	wait_timer = minf(wait_timer + 6.0, max_wait)
	_patience_stage = 0
	var done := _total_wants() <= 0 or not _stall_has_any_want(st)
	say_text = ""
	if done:
		var all_done := _total_wants() <= 0
		var happy_line := _rand_line("happy")
		if archetype == Archetype.VIP and all_done:
			tip += _rng.randi_range(12, 20)
			happy_line = _fmt_item(_rand_line("tip"), "", tip)
		elif archetype == Archetype.AILE and all_done:
			tip += _rng.randi_range(3, 6)
			happy_line = _fmt_item(_rand_line("tip"), "", tip)
			Sfx.play_3d("kid_laugh", global_position + Vector3(0, 1.0, 0), self, -4.0)
		elif archetype == Archetype.EMEKLI and all_done and _rng.randf() < 0.6:
			tip += _rng.randi_range(2, 5)
			happy_line = _fmt_item(_rand_line("tip"), "", tip)
		elif archetype == Archetype.IMPATIENT and tip > 0:
			happy_line = _fmt_item(_rand_line("tip"), "", tip)
		if all_done:
			_rep(seller_id, REP_HAPPY)
			mood_text = happy_line
			state = State.LEAVE
			target_owner_id = 0
			target_pos = exit_pos
		else:
			# Bu tezgahta istediği kalmadı; kalanlar için başka tezgaha
			_rep(seller_id, REP_HAPPY)
			state = State.STROLL
			target_owner_id = 0
			target_pos = exit_pos
			eval_timer = 1.5
			say_text = _rand_line("moveon")
			_say_t = 2.6
		_bought_here = 0
	_refresh_bubble()
	if Net.online():
		rpc_on_sold.rpc(k, price, tip, wants, offers, bought_items, state, mood_text)
	else:
		_apply_sold_fx(k, price, tip)
	return {"item": k, "price": price, "tip": tip, "haggle": was_haggle}


@rpc("any_peer", "call_local", "reliable")
func rpc_request_sell(seller_id: int, insist: bool) -> void:
	if Net.online() and not multiplayer.is_server():
		return
	var res := try_sell_one_from(seller_id, insist)
	if not res.is_empty():
		var p := _find_player(seller_id)
		if p:
			p.award_money(int(res["price"]), int(res.get("tip", 0)), bool(res.get("haggle", false)))


@rpc("authority", "call_local", "reliable")
func rpc_on_sold(item_id: String, price: int, tip: int, new_wants: Dictionary, new_offers: Dictionary, new_bought: Array, new_state: int, new_mood: String) -> void:
	wants = new_wants
	offers = new_offers
	bought_items = new_bought
	state = new_state
	mood_text = new_mood
	_refresh_bubble()
	_apply_sold_fx(item_id, price, tip)


@rpc("authority", "call_local", "reliable")
func rpc_on_angry(new_mood: String) -> void:
	mood_text = new_mood
	state = State.LEAVE
	_refresh_bubble()
	_trigger_reaction(false)


func _apply_sold_fx(_item_id: String, price: int, tip: int) -> void:
	_refresh_bag_visual()
	_trigger_reaction(true)
	var pos := global_position + Vector3(0, 1.9, 0)
	VFX.burst_coins(self, global_position + Vector3(0, 1.3, 0), 12 if tip > 0 else 8)
	VFX.spawn_floating_text(self, pos, "+%d TL" % price, Color(1.0, 0.86, 0.22), 46)
	Sfx.play_3d("coin", pos, self, -2.0)
	if tip > 0:
		VFX.spawn_floating_text(self, pos + Vector3(0, 0.42, 0), "⭐ +%d TL BAHŞİŞ!" % tip, Color(0.42, 1.0, 0.62), 40)
		Sfx.play_3d("tip", pos, self, -1.5)
	if _kid:
		_kid_hop = 0.5


func _trigger_reaction(happy: bool) -> void:
	if happy:
		_react_jump = 0.34
		VFX.burst_mood(self, global_position + Vector3(0, 1.5, 0), true)
		if state == State.LEAVE:
			Sfx.play_3d("happy", global_position + Vector3(0, 1.4, 0), self, -4.0)
			_pop_emote("❤️" if archetype != Archetype.VIP else "⭐")
	else:
		_react_shake = 0.55
		VFX.burst_mood(self, global_position + Vector3(0, 1.5, 0), false)
		Sfx.play_3d("angry", global_position + Vector3(0, 1.4, 0), self, -3.5)
		_pop_emote("💢")


@rpc("authority", "unreliable_ordered")
func rpc_sync_pose(p: Vector3, yaw: float, s: float, wt := 28.0) -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	wait_timer = wt


@rpc("authority", "unreliable_ordered")
func rpc_sync_state(p: Vector3, yaw: float, s: float, st: int, own: int, w: Dictionary, off: Dictionary, mood: String,
		wt := 28.0, say := "", emo := "") -> void:
	_net_pos = p
	_net_yaw = yaw
	_net_spd = s
	wait_timer = wt
	if emo != emote_text:
		emote_text = emo
		if emo != "":
			_pop_emote(emo)
	if state != st or wants != w or offers != off or mood_text != mood or target_owner_id != own or say_text != say:
		state = st
		target_owner_id = own
		wants = w
		offers = off
		mood_text = mood
		say_text = say
		_refresh_bubble()


func export_snapshot() -> Dictionary:
	return {
		"name": name, "seed": color_seed, "archetype": archetype,
		"pos": position, "yaw": _body_yaw, "exit": exit_pos,
		"target_pos": target_pos, "target_owner": target_owner_id,
		"state": state, "wants": wants.duplicate(), "offers": offers.duplicate(),
		"bought": bought_items.duplicate(), "mood": mood_text, "wait": wait_timer,
	}


func apply_snapshot(d: Dictionary) -> void:
	position = d.get("pos", position)
	_net_pos = position
	_body_yaw = float(d.get("yaw", 0.0))
	_net_yaw = _body_yaw
	target_pos = d.get("target_pos", exit_pos)
	target_owner_id = int(d.get("target_owner", 0))
	state = int(d.get("state", State.STROLL))
	wants = d.get("wants", {}).duplicate()
	offers = d.get("offers", {}).duplicate()
	bought_items = d.get("bought", []).duplicate()
	mood_text = str(d.get("mood", ""))
	wait_timer = float(d.get("wait", max_wait))
	_refresh_bag_visual()
	_refresh_bubble()


func get_next_sell_hint(seller_id: int) -> String:
	if state != State.WAIT_BUY or target_owner_id != seller_id:
		return ""
	var st := _find_stall(seller_id)
	var k := _current_item(st) if st else ""
	if k == "":
		return ""
	var nm: String = StallScript.ITEMS[k]["name"]
	var p: int = st.get_item_price(k)
	var tag := ""
	var who := (archetype_tag() + "  •  ") if archetype != Archetype.NORMAL else ""
	var fr := _item_fresh(st, k)
	if fr < FRESH_WILTED:
		tag = "  •  🥀 Solmuş!"
	elif fr > FRESH_GREAT:
		tag = "  •  ✨ Taze"
	if offers.has(k):
		return "%s[E] Olur: %s %d TL  •  [R] Olmaz, %d TL  •  Kalan: %d%s" % [who, nm, mini(p, int(offers[k])), p, _total_wants(), tag]
	return "%s[E] Sat: %s (%d TL)  •  Kalan: %d%s" % [who, nm, p, _total_wants(), tag]


func _current_item(st) -> String:
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			return k
	return ""


func _total_wants() -> int:
	var t := 0
	for k in wants:
		t += int(wants[k])
	return t


func _stall_has_any_want(st) -> bool:
	for k in wants:
		if int(wants[k]) > 0 and st.has_item(k):
			return true
	return false


func _active_event_item() -> String:
	var w := _world()
	return str(w.get_meta("event_item", "")) if w else ""


func _all_stalls() -> Array:
	var world := _world()
	var sg := world.get_node_or_null("Stalls") if world else null
	return sg.get_children() if sg else []


func _find_stall(owner_id: int) -> Node3D:
	var world := _world()
	var sg := world.get_node_or_null("Stalls") if world else null
	return sg.get_node_or_null("Stall_%d" % owner_id) as Node3D if sg else null


func _find_player(pid: int) -> Node3D:
	var world := _world()
	var pg := world.get_node_or_null("Players") if world else null
	return pg.get_node_or_null(str(pid)) as Node3D if pg else null


func _count_customers_at(owner_id: int) -> int:
	var n := 0
	if get_parent():
		for c in get_parent().get_children():
			if c != self and "target_owner_id" in c and c.target_owner_id == owner_id and c.state in [State.APPROACH, State.WAIT_BUY]:
				n += 1
	return n


# ---------------------------------------------------------------- animasyon

func _pick_idle() -> void:
	var pool: Array
	match archetype:
		Archetype.BARGAINER:
			pool = [Idle.INSPECT, Idle.INSPECT, Idle.INSPECT, Idle.LOOK, Idle.ARMS, Idle.BREATHE]
		Archetype.IMPATIENT:
			pool = [Idle.WATCH, Idle.WATCH, Idle.PHONE, Idle.PHONE, Idle.TAP, Idle.TAP]
		Archetype.VIP:
			pool = [Idle.PHONE, Idle.PHONE, Idle.LOOK, Idle.ARMS, Idle.BREATHE]
		Archetype.AILE:
			pool = [Idle.LOOK, Idle.LOOK, Idle.INSPECT, Idle.ARMS, Idle.BREATHE]
		Archetype.EMEKLI:
			pool = [Idle.LOOK, Idle.INSPECT, Idle.SCRATCH, Idle.BREATHE, Idle.BREATHE]
		_:
			pool = [Idle.LOOK, Idle.TAP, Idle.INSPECT, Idle.ARMS, Idle.BREATHE, Idle.SCRATCH]
			if _phone:
				pool.append_array([Idle.PHONE, Idle.PHONE])
	if pool.has(Idle.PHONE) and _phone == null:
		pool.erase(Idle.PHONE)
		pool.erase(Idle.PHONE)
	var ratio := wait_timer / maxf(max_wait, 1.0)
	if state == State.WAIT_BUY and ratio < 0.3:
		pool = [Idle.TAP, Idle.ARMS, Idle.WATCH] if archetype != Archetype.BARGAINER else [Idle.ARMS, Idle.INSPECT]
	_idle_kind = pool[randi() % pool.size()]
	_idle_t = randf_range(2.2, 4.6)


func _animate(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001 + _anim_off
	var kw := clampf(_spd / 2.2, 0.0, 1.0)
	var moving := _spd > 0.08
	if moving:
		_phase = wrapf(_phase + dt * (_spd / _stride_len) * 1.15, 0.0, TAU)
		for wh in _trolley_wheels:
			wh.rotation.x += _spd * dt / 0.095
		_idle_kind = Idle.BREATHE
		_idle_t = randf_range(0.6, 1.4)
	else:
		_idle_t -= dt
		if _idle_t <= 0.0:
			_pick_idle()
	var still := 1.0 - kw
	var f := minf(dt * 10.0, 1.0)
	var hop := 0.0
	if _react_jump > 0.0:
		_react_jump = maxf(_react_jump - dt, 0.0)
		hop = sin((_react_jump / 0.34) * PI) * 0.24
	var shake_y := 0.0
	if _react_shake > 0.0:
		_react_shake = maxf(_react_shake - dt, 0.0)
		shake_y = sin(_react_shake * 34.0) * 0.42 * (_react_shake / 0.55)

	var stride := 0.26 * kw * (_stride_len / 0.26)
	var lift := 0.1 * kw
	var lean := _lean_base + kw * (0.07 if archetype != Archetype.IMPATIENT else 0.14)
	var sway := sin(_phase) * _sway_amt * kw
	var head_yaw := 0.0
	var head_pitch := 0.0
	var head_roll := -sway * 0.6
	var umb := _umbrella != null and _umbrella.visible
	var behind_back := archetype == Archetype.EMEKLI and moving and _has_trolley

	var tgt := {}
	var trot := {}
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = _phase + (0.0 if side < 0 else PI)
		tgt[fn] = rest[fn] + Vector3(0, maxf(0.0, sin(c)) * lift + hop * 0.5, -cos(c) * stride)
		trot[fn] = Vector3(-sin(c) * 0.4 * kw, 0, 0)
		var swing := 0.2 * kw
		if hn == "HandR" and _has_trolley:
			swing *= 0.25
		tgt[hn] = rest[hn] + Vector3(-side * 0.02 * kw, maxf(0.0, cos(c)) * 0.04 * kw + hop * 1.1, cos(c) * swing)
		trot[hn] = Vector3(-cos(c) * 0.45 * kw, 0, side * 0.1 * kw)
		if behind_back and hn == "HandR":
			tgt[hn] = Vector3(rest[hn].x * 0.45, rest[hn].y + 0.04, -0.26)
			trot[hn] = Vector3.ZERO

	# Bekleme / durma animasyonları
	var breathe := sin(t * 2.1) * 0.012
	match _idle_kind:
		Idle.LOOK:
			head_yaw = sin(t * 1.15) * 0.75 * still
			head_pitch = -0.05 * still
		Idle.PHONE:
			if _phone:
				tgt["HandR"] = tgt["HandR"].lerp(Vector3(-0.1, 0.84, 0.32), still)
				trot["HandR"] = trot["HandR"].lerp(Vector3(-1.1, 0.3, 0), still)
				head_pitch = 0.32 * still
				head_yaw = -0.18 * still
		Idle.TAP:
			var rate := 9.0 if wait_timer / maxf(max_wait, 1.0) > 0.3 else 15.0
			var tap := absf(sin(t * rate)) * still
			trot["FootL"] = Vector3(-0.35 * tap, 0, 0)
			tgt["FootL"] = rest["FootL"] + Vector3(0, 0.03 * tap, 0.03)
		Idle.WATCH:
			tgt["HandL"] = tgt["HandL"].lerp(Vector3(0.12, 0.8, 0.3), still)
			trot["HandL"] = trot["HandL"].lerp(Vector3(-1.2, -0.4, 0), still)
			head_pitch = 0.3 * still
			head_yaw = 0.25 * still
		Idle.INSPECT:
			lean += 0.16 * still
			var reach := (sin(t * 1.6) * 0.5 + 0.5)
			tgt["HandR"] = tgt["HandR"].lerp(Vector3(-0.16, 0.66 + reach * 0.06, 0.42 + reach * 0.06), still)
			trot["HandR"] = trot["HandR"].lerp(Vector3(-0.9, 0, 0), still)
			head_pitch = 0.28 * still
			head_yaw = sin(t * 0.8) * 0.2 * still
		Idle.ARMS:
			var low := wait_timer / maxf(max_wait, 1.0) < 0.3 and state == State.WAIT_BUY
			if low: # eller belde, kızgın
				tgt["HandL"] = tgt["HandL"].lerp(Vector3(rest["HandL"].x + 0.06, 0.5, -0.04), still)
				tgt["HandR"] = tgt["HandR"].lerp(Vector3(rest["HandR"].x - 0.06, 0.5, -0.04), still)
				head_yaw = sin(t * 3.0) * 0.08 * still
			else: # kollar kavuşturulmuş
				tgt["HandL"] = tgt["HandL"].lerp(Vector3(-0.08, 0.62, 0.26), still)
				tgt["HandR"] = tgt["HandR"].lerp(Vector3(0.08, 0.66, 0.27), still)
				head_pitch = -0.06 * still
		Idle.SCRATCH:
			tgt["HandL"] = tgt["HandL"].lerp(Vector3(0.24, 1.18 + sin(t * 12.0) * 0.02, 0.06), still)
			trot["HandL"] = trot["HandL"].lerp(Vector3(-0.4, 0, 0.6), still)
			head_roll += 0.12 * still
			head_pitch = 0.1 * still
	if umb:
		tgt["HandL"] = Vector3(0.24, 0.98, 0.1)
		trot["HandL"] = Vector3(-0.3, 0, 0)
		head_pitch -= 0.04

	for n in ["FootL", "FootR", "HandL", "HandR"]:
		parts[n].position = parts[n].position.lerp(tgt[n], f)
		parts[n].rotation = parts[n].rotation.lerp(trot[n], f)
	var bob := absf(sin(_phase)) * 0.035 * kw
	var bp: Vector3 = rest["Body"] + Vector3(0, bob + hop + breathe * still, 0)
	parts["Body"].position = parts["Body"].position.lerp(bp, f)
	parts["Body"].rotation.y = lerpf(parts["Body"].rotation.y, sin(_phase) * 0.12 * kw, f)
	rig.rotation = Vector3(lerpf(rig.rotation.x, lean, f), _body_yaw, lerpf(rig.rotation.z, sway, f))
	var fwd := Vector3(sin(_body_yaw), 0, cos(_body_yaw))
	var head_target: Vector3 = rest["Head"] + Vector3(0, (parts["Body"].position.y - rest["Body"].y) * 1.1, 0) + fwd * (lean * 0.55)
	head.position = head.position.lerp(head_target, f)
	var hy := lerp_angle(head.rotation.y, _body_yaw + head_yaw + shake_y, minf(dt * 8.0, 1.0))
	head.rotation = Vector3(lerpf(head.rotation.x, head_pitch + lean * 0.3 + sin(_phase * 2.0) * 0.03 * kw, f), hy, lerpf(head.rotation.z, head_roll, f))
	if _phone:
		_phone.visible = _idle_kind == Idle.PHONE and not moving
	if _umbrella:
		_umbrella.rotation.z = lerpf(_umbrella.rotation.z, -sway * 0.8 + sin(t * 1.3) * 0.03, f)
	# Göz kırpma + konuşurken hafif ağız hareketi
	if not _eyes.is_empty():
		_blink_t -= dt
		if _blink_t <= -0.11:
			_blink_t = randf_range(2.6, 5.4)
		var ey := 0.14 if _blink_t <= 0.0 else 1.0
		for e in _eyes:
			e.scale.y = ey
	if _mouth:
		var talking := say_text != "" or mood_text != ""
		_mouth.scale.y = (0.8 + absf(sin(t * 14.0)) * 0.85) if talking else 1.0
	if _kid:
		_animate_kid(dt, t, kw, moving)


func _animate_kid(dt: float, t: float, kw: float, moving: bool) -> void:
	var f := minf(dt * 12.0, 1.0)
	var kph := _phase * 1.35 + 0.7
	var hop := 0.0
	if _kid_hop > 0.0:
		_kid_hop = maxf(_kid_hop - dt, 0.0)
		hop = absf(sin(_kid_hop * TAU * 2.0)) * 0.28
	elif not moving:
		# sıkılan çocuk: arada bir zıplar, sallanır
		var bored := 1.0 - clampf(wait_timer / maxf(max_wait, 1.0), 0.0, 1.0) if state == State.WAIT_BUY else 0.3
		if sin(t * 2.3) > 0.85 - bored * 0.4:
			hop = absf(sin(t * 9.0)) * 0.16
	for side: float in [-1.0, 1.0]:
		var fn := "FootR" if side < 0 else "FootL"
		var hn := "HandR" if side < 0 else "HandL"
		var c: float = kph + (0.0 if side < 0 else PI)
		_kid_parts[fn].position = _kid_parts[fn].position.lerp(_kid_rest[fn] + Vector3(0, maxf(0.0, sin(c)) * 0.12 * kw + hop, -cos(c) * 0.24 * kw), f)
		_kid_parts[fn].rotation.x = lerpf(_kid_parts[fn].rotation.x, -sin(c) * 0.5 * kw, f)
		var hp: Vector3 = _kid_rest[hn] + Vector3(0, hop * 1.2, cos(c) * 0.2 * kw)
		if hn == "HandR":
			hp = Vector3(-0.42, 0.95, 0.0) # ebeveynin elini tutar
		elif _balloon:
			hp = _kid_rest[hn] + Vector3(0.05, 0.3 + hop, 0.05)
		_kid_parts[hn].position = _kid_parts[hn].position.lerp(hp, f)
	_kid_parts["Body"].position = _kid_parts["Body"].position.lerp(_kid_rest["Body"] + Vector3(0, absf(sin(kph)) * 0.05 * kw + hop, 0), f)
	var kh := _kid_parts["Head"] as Node3D
	kh.position = kh.position.lerp(_kid_rest["Head"] + Vector3(0, absf(sin(kph)) * 0.05 * kw + hop, 0), f)
	kh.rotation.y = lerpf(kh.rotation.y, sin(t * 0.9) * 0.6 * (1.0 - kw), f)
	kh.rotation.x = lerpf(kh.rotation.x, -0.25 * (1.0 - kw), f) # yukarı, ebeveyne bakar
	if _balloon:
		_balloon.rotation = Vector3(sin(t * 1.7) * 0.12 - kw * 0.25, 0, sin(t * 1.3) * 0.15)
