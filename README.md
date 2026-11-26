# Bazar

Arkadaşlarla veya tek başına oynanan low-poly Türk semt pazarı oyunu. Godot 4.7 + [GodotSteam](https://godotsteam.com).

## Oyna (indir)

[Son sürümü indir](https://github.com/Obuto45/bazar/releases/latest) → zip'i bir klasöre aç → `Bazar.exe`.
- **Tek başına:** Ana menüden **TEK OYNA (Kariyer)** → **Yeni Pazar** ya da kayıtlıysa **Devam Et (Gün N)**.
- **Arkadaşla:** Steam açıkken **ÇOKLU OYNA (Lobi)** → **Steam Lobisi Kur** → **Arkadaşlar** → **Davet et** → **Pazarı Aç**.
Oyun her açılışta yeni sürüm var mı bakar; varsa kendini günceller ve yeniden başlar.

## Geliştirme

1. Godot 4.4+ (test: 4.7.2) ile `project.godot` dosyasını aç.
2. Test için Spacewar App ID'si (`480`) kullanılıyor (`steam_appid.txt`, `net.gd` içinde `APP_ID`).
3. F5.

## Yeni sürüm yayınlama

```powershell
./release.ps1 0.6 "Değişiklik notları"
```

## Kontroller

| Tuş | İş |
|---|---|
| WASD / Shift / Boşluk / Fare | yürü / koş (hız çizgileri + FOV) / zıpla / bak |
| **1–6**, `0` | kişisel envanter, el boş |
| **E** | kasa al / müşteriye sat / kapkaççıyı yakala / korna / radyo koy |
| **Sol Tık** (basılı) | ürün diz / eldeki eşyayı kullan (sigara, megafon, 💦 fısfıs...); 🏏 sopa elindeyken sol tık = savur |
| **Q** | kasayı / eldeki eşyayı fırlat (sopa dahil) |
| Tekerlek / **Z**-**X** | fiyat düşür / artır |
| **B** veya mikrofon | bağır (müşteri çek) |
| **R** | pazarlığa "olmaz" de / radyoyu geri al |
| **F** | tezgah zili |
| **E** (dükkan kapısına bakarak) | arka sokaktaki dükkandan alışveriş |
| **Tab** | skor tablosu |
| **M** | mikrofon aç/kapa |
| **H** | rehber adımını geç |
| **ESC** | menü: ayarlar + tam tuş listesi |

Oyun içinde alttaki ipucu satırı duruma göre değişir (kasa elde, tezgah boş, kapkaççı var...); tam tuş listesi ESC menüsündedir.

## v0.6 Büyük Pazar Güncellemesi

- **Kariyer (Tek Oyna):** Her gün sonunda `user://career.json` dosyasına kaydedilir (gün, para, envanter, tezgah geliştirmeleri, itibar, rekorlar). Menüde **Devam Et (Gün N)** veya **Yeni Pazar**. Kayıt atomik yazılır, bozuk dosya yok sayılır.
- **Hava Durumu:** Her gün güneşli / bulutlu / yağmurlu (çoklu oyunda herkes için aynı). Yağmurda müşteri az ama acelecidir.
- **Kapkaççılar:** Kapüşonlu yaramaz çocuklar tezgahlardan ürün aşırır; bak ve **E** ile yakala, 30 TL ödül!
- **Tazelik & İtibar:** Ürünler gün içinde bayatlar (💦 Su Fısfısı ile tazele); mutlu müşteri tezgah itibarını (★) yükseltir, itibar müşteri çeker.
- **Sopa 🏏 (60 TL):** Sol tıkla savur, **Q** ile fırlat; vurulan oyuncu 2 sn boyunca ragdoll olup yere yığılır.
- **Zorluk eğrisi:** 1. gün sakin (güneşli, geç zabıta, tek kapkaççı); sonraki günler daha kalabalık, daha seçici müşteriler, daha sık zabıta ve kapkaççı.
- **İlk açılış rehberi:** Kasayı al → diz → fiyatla → bağır → sat → toptancıdan al → fısfısla; her adım oyun durumundan algılanır, **H** ile geçilebilir, ESC menüsünden baştan gösterilebilir.
- **Gün sonu özeti:** Skor tablosu, günün istatistikleri, kariyer rekorları (🆕 YENİ REKOR!).
- **Ayarlar:** Yüksek/düşük grafik kalitesi, menü müziği, ekran ölçeklemesi (UI her çözünürlükte okunur).
- Paralel yerel test için: `-- --mptest host port=7791` (varsayılan port 7777), hava zorlama: `weather=rain`.

## Oynanış

- **Gerçekçi Türk Semt Pazarı:** Dokulu asfalt cadde, kaldırım bordürleri, demir iskele üstü mavi/yeşil/çizgili brandalar, sallanan ampuller, plastik hal kasaları, Türk mahalle apartmanları ve Kuzey/Güney Giriş-Çıkış kapıları.
- **Ford Transit Toptancı ("GARDAŞLAR SEBZE MEYVE"):** Havalı korna çalarak Kuzey Kapısından pazara girer, dörtlülerini yakıp park eder ve oyun başına bir kez gelir (geri sayım HUD'da). Her çeşitten **tek kasa** satar; fiyatlar farklıdır (ucuz / pahalı), bazıları **%20-40 indirimli** etiketlidir. İlk gelen alır, stok sınırlıdır. Kabine `[E]` ile korna çaldırabilirsin.
- **Arka Sokaktaki Dükkanlar:** Pazarın iki yanındaki gerçek dükkanların kapısına bakıp `[E]` ile alışveriş yapılır; her dükkanın açılış saati vardır (kapalıyken kepenk iner). **Tekel Bayi** (sigara, puro; öğlen açılır), **Fırın** (simit; akşam kapanır), **Kıraathane** (çay), **Market** (meyve bıçağı, su fısfısı), **Nalbur** (tezgah geliştirmeleri; akşam pazarında kapanır), **Telefoncu** (megafon, radyo), **Eczane** (akşam nöbetçi, %50 pahalı), **Berber**, **Terzi**. Dükkana gitmek tezgahı sahipsiz bırakmak demek!
- **Kişisel Envanter (`1–6`):** Meyve kasaları elde taşınır, envantere girmez. Her pazarcı 1 paket **Sigara** ile başlar. Dükkanlardan alabileceklerin:
  - **🚬 Sigara Paketi (15 TL):** Sol tıkla nefes çek; ucu korlanır, yanarak kısalır ve 3D duman çıkarır.
  - **🪵 Küba Purosu (45 TL):** Kalın altın bantlı, uzun yanan, yoğun dumanlı puro + Ağır Abi prestiji.
  - **📢 El Megafonu (75 TL):** Mikrofon/bağırma dB'ini +12 dB (1.85x) yükseltir; daha çok bağıran pazarcı müşterileri kendine çeker!
  - **🔪 Meyve Bıçağı (60 TL):** Rakip pazarcıya saldırabilirsin; ama Zabıta anında koşup **-50 TL ceza** keser ve bıçağa el koyar!
  - **📻 Arabesk Radyo (90 TL):** Hicaz makamında 3D Arabesk müzik çalar; elde veya tezgahın üstüne koyarak tüm sokağı inletebilirsin!
- **Pazar Teyzesi & Müşteriler:** Başörtülü, gözlüklü, pazar arabalı **Pazar Teyzesi**, *Aceleci* ve *VIP* müşteriler iki kapıdan sakin tempoda gelir, arada bir **Kalabalık Dalgası** basar; konuşmaları belirgin **pop-up** balonlarla açılır.
- **Pazar Günü & Zabıta:** 5 dakikalık dinamik sabah→akşam pazarı döngüsü, fahiş fiyat/sokak kirliliği/saldırı denetleyen Zabıta, anlık talep olayları ve **Günün Esnafı** finali.

## Dosyalar

| Dosya | İş |
|---|---|
| `net.gd` | Steam lobi, davet, SteamMultiplayerPeer, ENet yedeği (autoload `Net`) |
| `sfx.gd` | Prosedürel SFX, Türk kamyonet havalı kornası, Hicaz Arabesk müzik ve ambiyans (autoload `Sfx`) |
| `main.gd` | Menü, kariyer kaydı, dükkan paneli, HUD (itibar, rehber), gün döngüsü, hava, kapkaççı, zorluk, MP senkronu |
| `player.gd` | Envanter (`1–6`), sigara/puro/megafon/bıçak/radyo mekaniği, bağırma, düşük sarsıntı, koşma FOV |
| `items.gd` | Kişisel envanter eşyaları kataloğu ve 3D modelleri |
| `shops.gd` | Arka sokaktaki dükkanlar: tabela, ürünler, açılış saatleri |
| `wholesaler.gd` | Sürüşlü Ford Transit Toptancı AI, dörtlüler, havalı korna, her çeşitten tek kasa (farklı fiyat / indirim) |
| `stall.gd` | Dokulu oyuncu tezgahı, çift taraflı fiyat etiketi, terazi, tezgah radyosu ve 3D yükseltmeler |
| `produce.gd` | 11 meyve/sebze kataloğu ve özgün low-poly 3D modeller |
| `customer.gd` | Pazar Teyzesi + 3 müşteri tipi, pop-up konuşma kartları, güçlü bağırma çekimi, pazarlık, bahşiş |
| `inspector.gd` | Zabıta AI: cadde devriyesi ve bıçak saldırısında acil kovalama müdahalesi |
| `bazaar.gd` | Fıskiyesiz Türk semt pazarı: asfalt, branda, iskele, ampuller, mahalle apartmanları, gün ışığı |
| `vfx.gd` | 3D partiküller (sigara/puro dumanı, kor, müzik notaları, altın para, toz, darbe, ses halkaları) |
| `lowpoly.gd` | Düz gölgeli mesh + prosedürel yüzey dokuları (asfalt, beton, branda, ahşap, sıva) |
| `updater.gd` | GitHub Release'ten otomatik güncelleme (autoload `Updater`) |
| `settings.gd` | Ses, ekran, grafik kalitesi ve rehber durumu (autoload `Settings`) |
