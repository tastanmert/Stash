<p align="center">
  <img src="docs/logo/icon-512.png" width="160" alt="Stash simgesi">
</p>

<h1 align="center">Stash</h1>

<p align="center">
  macOS için dosyalarına yüzen bir raf. Sürükle, sakla, işle.<br>
  <a href="README.md">English</a>
</p>

---

Stash, çalışırken dosyalarını geçici olarak koyabileceğin bir yer sunar. Sürüklerken imleci salla, bir raf açılsın; dosyaları bırak, uygulama değiştir, sonra gerektiği yere sürükleyip çıkar. Bu arada başka bir uygulama açmadan sıkıştırabilir, boyutlandırabilir, dönüştürebilir, yeniden adlandırabilir ya da paylaşabilirsin.

<p align="center">
  <img src="docs/screenshots/shelf.png" width="198" alt="Dört dosya tutan bir raf">
  &nbsp;&nbsp;
  <img src="docs/screenshots/detail.png" width="400" alt="Rafın dosya listesi">
</p>

## Özellikler

**Raflar**
- Rafı sürüklerken imleci sallayarak, bir değiştirici tuşa basılı tutarak, MacBook çentiğine bırakarak, klavye kısayoluyla ya da menü çubuğundan aç.
- Raflar diğer pencerelerin üstünde durur; taşınabilir, ekran kenarına yaslanabilir, sabitlenebilir, adlandırılabilir ve renklendirilebilir.
- Son ve sabit raflar sonradan yeniden açılabilir; çıkarken açık kalan raflar son raflara kaydedilir.
- Izgara ve liste görünümü, Quick Look, Birlikte Aç, yerinde yeniden adlandırma; dosyaların hepsini ya da bir kısmını sürükleyip çıkarma.

**Eylemler**
- Görseller: Metni Karart (akıllı algılama ya da elle), boyutlandır, biçim dönüştür, sıkıştır, meta verileri kaldır, metni çıkar, PDF'te birleştir, yan yana birleştir, masaüstü resmi yap.
- PDF'ler: birleştir, parolayla koru.
- Dosyalar: zip'le, yeniden adlandır ve toplu yeniden adlandır, şuraya kopyala / taşı, yolu kopyala, Bilgi Al, Çöp Sepeti'ne taşı.
- Paylaş: AirDrop, Mail, Mesajlar ve sistem paylaşım menüsü.
- **Anlık Eylemler**: dosyaları yeni rafın altındaki eylem karosuna doğrudan bırak.
- Kendi ayarlarınla **Özel Eylemler**, ayrıca kendi UNIX ya da Automator betiklerin.

**Otomasyon**
- Klasörleri kurallarla (ad, uzantı, tür, boyut) izle; yeni dosyaları bir rafta göster.
- Ekran görüntüsü rafı: yeni ekran görüntüleri bir rafta açılır.
- Kestirmeler eylemleri, Servisler menüsü ve Raycast, Alfred ya da terminal için `stash://` bağlantıları:
  ```sh
  open "stash://add?path=/dosya/yolu"
  open "stash://new"
  open "stash://clipboard"
  ```

**Diğer**
- Türkçe ve İngilizce; sistem dilini izler ya da Ayarlar'dan seçilir.
- Hesap yok, bulut yok, ağ erişimi yok: dosyaların Mac'inde kalır.

<p align="center">
  <img src="docs/screenshots/settings-activation.png" width="420" alt="Raf Açma ayarları">
  &nbsp;
  <img src="docs/screenshots/settings-instant.png" width="420" alt="Anlık Eylemler ayarları">
</p>

## Gereksinimler

- macOS 15 ya da üstü (Apple Silicon veya Intel)

## Kaynaktan derleme

Xcode 26 ya da üstü (Swift 6.2) ve [XcodeGen](https://github.com/yonaskolb/XcodeGen) gerekir:

```sh
brew install xcodegen
git clone https://github.com/tastanmert/Stash.git
cd Stash
./scripts/build-app.sh            # derler ve /Applications'a kurar
./scripts/build-app.sh ~/Desktop  # ya da başka bir klasöre
```

Betik, Xcode projesini `project.yml`'den üretir, evrensel (universal) uygulamayı derler, simgeyi çizer ve varsa Apple Development sertifikanla imzalar (yoksa ad-hoc). Kestirmeler eylemlerinin App Intents verisi yalnız Xcode derlemesinde üretildiği için düz SwiftPM yerine Xcode kullanılır.

Testleri çalıştırmak için:

```sh
swift test
```

## Proje yapısı

| Yol | İçerik |
| --- | --- |
| `Sources/StashCore` | Dosya işlemleri, sallama algılama, klasör kuralları, raf kayıtları: arayüzsüz, testli mantık |
| `Sources/Stash` | Uygulama: raflar, menüler, eylemler, ayarlar, otomasyon (SwiftUI içerikli AppKit pencereleri) |
| `Tests/StashCoreTests` | `StashCore` için Swift Testing testleri |
| `Localization` | İngilizce ve Türkçe metinler; `scripts/sync-strings.py` ikisinde de her anahtarın olduğunu denetler |
| `scripts` | Derleme betiği ve simge çizimi |

## Katkı

Hata bildirimleri ve pull request'ler memnuniyetle karşılanır. Lütfen değişiklikleri odaklı tut, `swift test` çalıştır; kullanıcıya görünen metin ekler ya da değiştirirsen `python3 scripts/sync-strings.py` ile denetle (her metnin İngilizce ve Türkçe karşılığı olmalı).

## Lisans

Telif hakkı © 2026 Mert Taştan.

Stash özgür yazılımdır ve [GNU Genel Kamu Lisansı v3.0](LICENSE) ile yayınlanır. Kullanabilir, inceleyebilir, değiştirebilir ve paylaşabilirsin; değiştirilmiş bir sürümü dağıtırsan o da GPL ile ve kaynak koduyla birlikte yayınlanmalıdır.
