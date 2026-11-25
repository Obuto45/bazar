# Bazar

Arkadaşlarla Steam üzerinden buluşulan low-poly pazar oyunu. Godot 4 + [GodotSteam](https://godotsteam.com) (KartopuTest'teki online sistemin aynısı).

## Çalıştırma

1. Godot 4.4+ (test: 4.7.2) ile `project.godot` dosyasını aç.
2. Steam açık olsun. Test için Spacewar App ID'si (`480`) kullanılıyor (`steam_appid.txt`, `net.gd` içinde `APP_ID`).
3. F5.

## Arkadaşla oynama

- **OYNA** → **Steam Lobisi Kur**
- **Arkadaşlar** → listeden **Davet et**. Arkadaş oyunu açıkken sağ üstte çıkan daveti kabul eder (ya da Steam sohbetinden katılır).
- Host **Pazarı Aç** der, herkes pazara girer. Pazar açıkken gelen arkadaş da doğrudan içeri düşer.
- Tek bilgisayarda test: iki pencere aç, birinde **Yerel Host**, ötekinde **Yerel Katıl**.

## Kontroller

WASD yürü • Shift koş • Boşluk zıpla • Fare bak • ESC menü

## Dosyalar

| Dosya | İş |
|---|---|
| `net.gd` | Steam lobi, davet, SteamMultiplayerPeer, ENet yedeği (autoload `Net`) |
| `main.gd` | Menü, lobi ekranı, ayarlar, oyunu başlatma, geç katılanlar |
| `player.gd` | Karakter: gövde, kafa, süzülen eller/ayaklar, hareket, ağ senkronu |
| `bazaar.gd` | Pazar mekanı: çeşme, tezgahlar, sur, ağaçlar, fenerler |
| `lowpoly.gd` | Düz gölgeli low-poly mesh yardımcıları |
| `settings.gd` | Ses ve ekran ayarları (autoload `Settings`) |

## Katkı

Depo herkese açık; sadece `Obuto45` ve `bagatarhansinan` doğrudan değişiklik yapabilir.
