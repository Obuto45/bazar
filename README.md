# Bazar

Arkadaşlarla Steam üzerinden buluşulan low-poly Türk pazarı oyunu. Godot 4.7 + [GodotSteam](https://godotsteam.com).

## Oyna (indir)

[Son sürümü indir](https://github.com/Obuto45/bazar/releases/latest) → zip'i bir klasöre aç → Steam açıkken `Bazar.exe`.
Oyun her açılışta yeni sürüm var mı bakar; varsa kendini günceller ve yeniden başlar.

## Geliştirme

1. Godot 4.4+ (test: 4.7.2) ile `project.godot` dosyasını aç.
2. Steam açık olsun. Test için Spacewar App ID'si (`480`) kullanılıyor (`steam_appid.txt`, `net.gd` içinde `APP_ID`).
3. F5.

## Yeni sürüm yayınlama

Değişiklikleri commit et, sonra:

```powershell
./release.ps1 0.4 "Değişiklik notları"
```

Betik sürümü `project.godot`'a yazar, exe'yi dışa aktarır, `Bazar_v0.4_Windows.zip` yapar, push eder ve GitHub Release açar. Godot 4.7.2 export şablonları kurulu olmalı. Godot PATH'te değilse önce `$env:GODOT` ile console exe yolunu ver.

## Arkadaşla oynama

- **OYNA** → **Steam Lobisi Kur**
- **Arkadaşlar** → listeden **Davet et**. Arkadaş oyunu açıkken sağ üstte çıkan daveti kabul eder (ya da Steam sohbetinden katılır).
- Host **Pazarı Aç** der, herkes pazara girer. Pazar açıkken gelen arkadaş mevcut tüm tezgah stokları, yükseltmeleri ve müşterilerle doğrudan içeri düşer.
- Tek bilgisayarda test: iki pencere aç, birinde **Yerel Host**, ötekinde **Yerel Katıl**.

## Kontroller

WASD yürü • Shift koş • Boşluk zıpla • Fare bak • E kasa satın al / sat / zil / geliştirme panosu • Sol tık diz • Q kasayı fırlat • Tekerlek veya Z/X fiyat • B veya mikrofon bağır • R pazarlığa "olmaz" de • U tezgah geliştir • F tezgah zili • Tab skor tablosu • M mikrofon • ESC menü

## Oynanış

- **Ekonomi & Toptancı Hali:** 120 TL sermayeyle başlarsın. Tezgah arkasında 4 temel ürün (Domates, Elma, Soğan, Portakal), Batı meydanındaki **Toptancı Kamyonunda** ise tüm 7 ürün (Patlıcan, Muz, Karpuz dahil) %12 daha ucuza ve anlık **🔥 FIRSAT (%28 indirim)** etiketiyle satılır. Paran biter ve tezgahın boşalırsa arka depoda **Acil Veresiye Soğan Kasası (0 TL)** açılır.
- **Pazar Günü & Akşam Pazarı:** 5 dakikalık dinamik gün (08:00 Sabah → Öğle → Gün Batımı → 21:30 Akşam Pazarı). Akşam fenerler yanar, müşteri akını başlar; gün sonunda **Günün Esnafı** seçilir ve yeni güne geçilir.
- **Bağırma & Pazarlık:** Mikrofona bağır (veya **B**); ses yükseldikçe müşteri çekimin ve 3D ses halkaların büyür. Fiyatlar pazardaki diğer tezgahlarla karşılaştırılır; renkli fiyat etiketleri (yeşil: ucuz, krem: normal, turuncu: pahalı, kırmızı: Zabıta riski) anlık ipucu verir.
- **Özel Müşteri Tipleri:** *Pazarlıkçı Teyze* (sert indirim ister ama çok alır), *Aceleci Müşteri* (hızlı servise bahşiş verir), *VIP Müşteri* (pazarlık etmez, büyük sepete yüksek bahşiş bırakır). Müşterilerin elindeki pazar filesi aldıkça dolar ve başlarında sabır çubuğu görünür.
- **Zabıta & Rastgele Olaylar:** Caddede devriye gezen **Zabıta** fahiş fiyata (-25 TL) ve sokağa atılmış kasalara (-15 TL) düdük çalıp ceza keser; dürüst esnafa +10 TL ödül verir. Anlık talep patlaması olayları ("Domates Kıtlığı", "Karpuz Fırtınası" vb.) fiyatları ve talebi yükseltir.
- **Tezgah Geliştirmeleri (`U`):** *Megafon* (80 TL), *Süslü Tente & Işıklar* (100 TL), *Geniş Kasa & Hızlı Dizim* (120 TL), *Pirinç Tezgah Zili* (90 TL).

## Dosyalar

| Dosya | İş |
|---|---|
| `net.gd` | Steam lobi, davet, SteamMultiplayerPeer, ENet yedeği (autoload `Net`) |
| `sfx.gd` | Prosedürel 20+ SFX ve 3D çeşme + pazar ambiyansı (autoload `Sfx`) |
| `main.gd` | Menü, lobi, Pazar Günü döngüsü, Toptancı ekonomisi, olaylar, HUD, skor tablosu, geç katılım senkronu |
| `player.gd` | Karakter, hareket, ayak sesi, hedef vurgusu, proximity sesli sohbet, bağırma dalgaları, satış |
| `stall.gd` | Oyuncu tezgahı, çift taraflı renkli fiyat etiketleri, pirinç terazi, 3D yükseltmeler |
| `produce.gd` | 7 meyve/sebze kataloğu ve özgün low-poly 3D ürün modelleri |
| `customer.gd` | 4 müşteri tipi, dolan 3D pazar filesi, sabır çubuğu, tepkiler, pazarlık ve bahşiş |
| `inspector.gd` | Zabıta AI: cadde devriyesi, fahiş fiyat / sokak kirliliği cezası ve temiz esnaf ödülü |
| `bazaar.gd` | AgX ışıklandırma, gün döngüsü, shader çeşme, kasaba silueti, flamalar, Toptancı Kamyonu |
| `vfx.gd` | 3D partiküller (altın para, toz, duygu, çeşme fıskiyesi, ses halkaları, uçan yazılar) |
| `lowpoly.gd` | Düz gölgeli low-poly mesh ve çarpıştırıcı yardımcıları |
| `updater.gd` | GitHub Release'ten otomatik güncelleme (autoload `Updater`) |
| `settings.gd` | Ses ve ekran ayarları (autoload `Settings`) |

## Katkı

Depo herkese açık; sadece `Obuto45` ve `bagatarhansinan` doğrudan değişiklik yapabilir.
