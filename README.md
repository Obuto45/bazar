# Bazar

Arkadaşlarla veya tek başına oynanan low-poly Türk semt pazarı oyunu. Godot 4.7 + [GodotSteam](https://godotsteam.com).

## Oyna (indir)

[Son sürümü indir](https://github.com/Obuto45/bazar/releases/latest) → zip'i bir klasöre aç → `Bazar.exe`.
- **Tek başına:** Ana menüden **TEK OYNA (Solo)** ile anında pazara gir.
- **Arkadaşla:** Steam açıkken **ÇOKLU OYNA (Lobi)** → **Steam Lobisi Kur** → **Arkadaşlar** → **Davet et** → **Pazarı Aç**.
Oyun her açılışta yeni sürüm var mı bakar; varsa kendini günceller ve yeniden başlar.

## Geliştirme

1. Godot 4.4+ (test: 4.7.2) ile `project.godot` dosyasını aç.
2. Test için Spacewar App ID'si (`480`) kullanılıyor (`steam_appid.txt`, `net.gd` içinde `APP_ID`).
3. F5.

## Yeni sürüm yayınlama

```powershell
./release.ps1 0.5 "Değişiklik notları"
```

## Kontroller

WASD yürü • Shift koş (hız çizgileri + FOV) • Boşluk zıpla • Fare bak • **1–6** kişisel envanter (`0` el boş) • **P** Pazarcı Dükkanı • **E** kasa al / sat / korna / radyo koy • **Sol Tık** ürün diz / eldeki eşyayı kullan • **Q** kasayı fırlat • Tekerlek / Z-X fiyat • **B** veya mikrofon bağır • **R** pazarlığa "olmaz" de / radyoyu geri al • **F** tezgah zili • **Tab** skor • **M** mikrofon • **ESC** menü

## Oynanış

- **Gerçekçi Türk Semt Pazarı:** Dokulu asfalt cadde, kaldırım bordürleri, demir iskele üstü mavi/yeşil/çizgili brandalar, sallanan ampuller, plastik hal kasaları, Türk mahalle apartmanları ve Kuzey/Güney Giriş-Çıkış kapıları.
- **Ford Transit Toptancı ("GARDAŞLAR SEBZE MEYVE"):** Havalı korna çalarak Kuzey Kapısından pazara girer, dörtlülerini yakıp park eder, 7 çeşit taze meyve/sebze kasası tedarik eder (`Domates, Elma, Soğan, Portakal, Patlıcan, Muz, Karpuz`), süresi dolunca korna çalıp Güney Kapısından çıkar ve yeni fırsat fiyatlarıyla geri gelir! Kabine `[E]` ile korna çaldırabilirsin.
- **Kişisel Envanter (`1–6`) & Pazarcı Dükkanı (`P`):** Meyve kasaları elde taşınır, envantere girmez. Her pazarcı 1 paket **Sigara** ile başlar. Kazandığın parayla `P` mağazasından alabileceklerin:
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
| `main.gd` | Solo/Çoklu menü, `P` Dükkanı, Hotbar, koşma hız çizgileri, gün döngüsü, olaylar, MP senkronu |
| `player.gd` | Envanter (`1–6`), sigara/puro/megafon/bıçak/radyo mekaniği, bağırma, düşük sarsıntı, koşma FOV |
| `items.gd` | Kişisel envanter eşyaları kataloğu ve 3D modelleri |
| `wholesaler.gd` | Sürüşlü Ford Transit Toptancı AI, dörtlüler, havalı korna ve 7 çeşit kasa tedariği |
| `stall.gd` | Dokulu oyuncu tezgahı, çift taraflı fiyat etiketi, terazi, tezgah radyosu ve 3D yükseltmeler |
| `produce.gd` | 7 meyve/sebze kataloğu ve özgün low-poly 3D modeller |
| `customer.gd` | Pazar Teyzesi + 3 müşteri tipi, pop-up konuşma kartları, güçlü bağırma çekimi, pazarlık, bahşiş |
| `inspector.gd` | Zabıta AI: cadde devriyesi ve bıçak saldırısında acil kovalama müdahalesi |
| `bazaar.gd` | Fıskiyesiz Türk semt pazarı: asfalt, branda, iskele, ampuller, mahalle apartmanları, gün ışığı |
| `vfx.gd` | 3D partiküller (sigara/puro dumanı, kor, müzik notaları, altın para, toz, darbe, ses halkaları) |
| `lowpoly.gd` | Düz gölgeli mesh + prosedürel yüzey dokuları (asfalt, beton, branda, ahşap, sıva) |
| `updater.gd` | GitHub Release'ten otomatik güncelleme (autoload `Updater`) |
| `settings.gd` | Ses ve ekran ayarları (autoload `Settings`) |
