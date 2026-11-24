# Mimari

## Katmanlar ve modüller

| Modül | Klasör | Sorumluluk |
|---|---|---|
| app | `lib/app` | Kök widget, tema (yalnızca koyu), Türkçe yerelleştirme, ortak bileşenler, kapanış koruması |
| editor | `lib/editor` | `EditDocument` (değişmez belge), `History` (geri al/yinele), `EditorController`, tuval ve paneller |
| image_engine | `lib/image_engine` | Saf Dart `Raster` (RGBA8), kod çözme/kodlama, geometri, detay işlemleri, renk matrisi, WebP VP8L kodlayıcı, klasik algoritmalar, isolate giriş noktaları |
| layers | `lib/layers` | Katman modelleri (metin/görsel/şekil), maske darbeleri, `LayerPainter` |
| filters | `lib/filters` | `Adjustments` (tahribatsız ayarlar), hazır filtreler |
| ai | `lib/ai` | Sağlayıcı arayüzü, yerel/çevrimiçi adaptörler, izin kapısı (`AiService`), Türkçe komut yorumlayıcı |
| templates | `lib/templates` | Tuval ön ayarları, tasarım şablonları |
| collage | `lib/collage` | Kolaj düzenleri ve oluşturucu |
| projects | `lib/projects` | SQLite dizini, proje klasörü deposu, proje fabrikası, ana ekran |
| export | `lib/export` | Tam çözünürlüklü dışa aktarma (isolate + GPU karoları), dışa aktarma penceresi |
| batch_processing | `lib/batch_processing` | Toplu işlem servisi ve ekranı |
| platform_services | `lib/platform_services` | Dosya seçici, galeri, paylaşım, SVG rasterleştirme, veri klasörleri |

## Tahribatsız düzenleme

```
EditDocument
 ├─ sourceFile (source.jpg | source_<id>.png)   ← orijinal asla değişmez
 ├─ geometry   (90° döndürme, çevirme, düzleştirme, normalize kırpma)
 ├─ adjustments(renk + detay + filtre)
 └─ layers     (metin / görsel / şekil + maske darbeleri)
```

Her değişiklik yeni bir belge üretir; `History` bu belgeleri yığında tutar (en fazla 100 adım, projede son 40 adım saklanır). AI ve klasik "piksel" işlemleri sonuçlarını yeni bir kaynak sürümü olarak kaydeder; eski sürüm projede kaldığı için bu işlemler de geri alınabilir. Kayıtta, geçmişte artık başvurulmayan türetilmiş dosyalar temizlenir.

## İşleme hattı

```
kaynak ──çöz──► [geometri] ──► [detay: gölge/açık ton → netlik → keskinlik → bulanıklık → vinyet → gren] ──► [renk matrisi] ──► [katmanlar] ──► kodla
            önizleme: isolate (küçültülmüş)              önizleme: GPU ColorFilter        önizleme: Canvas
            dışa aktarma: isolate (tam çözünürlük)       dışa aktarma: Dart               dışa aktarma: GPU, 2048 px karolar
```

- **Renk ayarları** (pozlama, parlaklık, kontrast, sıcaklık, ton, doygunluk, gri tonlama, filtre) tek bir 5×4 matrise birleştirilir. Ekranda `ColorFilter.matrix` ile anında, dışa aktarmada aynı katsayılarla Dart'ta uygulanır.
- **Detay ayarları** komşu piksellere bağlı olduğu için arka plan isolate'inde hesaplanır; yarıçaplar görüntü boyutuna oranlıdır (önizleme ve çıktı aynı görünür).
- **Büyük JPEG'ler** önizleme için DCT ölçekli (1/2, 1/4, 1/8) çözülür; tam çözünürlük yalnızca dışa aktarma ve AI işlemlerinde belleğe alınır.

## Proje dosya biçimi

```
Projeler/<id>/
  project.json   {"format":"pixelshift-project","formatVersion":1,"history":[...],"historyIndex":n}
  source.jpg     orijinal (JPG/PNG/WEBP/BMP/TIFF/GIF aynen; PSD/RAW/SVG PNG'ye dönüştürülür)
  source_*.png   AI/klasik işlem sonuçları
  assets/*.png   görsel katmanları
  thumb.png      ana ekran küçük resmi
```

`project.json` önce geçici dosyaya yazılıp yeniden adlandırılır (yarım kayıt oluşmaz). SQLite yalnızca dizin (ad, tarih, boyut) ve ayarlar içindir; dizin kaydı kaybolsa bile klasör taranarak proje geri alınır.

## AI sağlayıcı adaptörleri

```dart
abstract class AiProvider {
  bool get isOnline;            // true → her işlemden önce izin
  Set<AiTask> get supportedTasks;
  ProviderPrivacy? get privacy; // adres, saklama bilgisi, politika, ücret/sınır
  Future<AiResult> run(AiRequest, {progress, cancel});
}
```

`AiService.run` gizlilik kuralını merkezi olarak uygular: çevrimiçi sağlayıcı çağrılmadan önce `ConsentRequest` gösterilir; reddedilirse `OperationCancelled` fırlatılır ve sağlayıcı hiç çağrılmaz. Her sağlayıcı bağımsızdır; biri çalışmazsa diğerleri ve uygulamanın geri kalanı etkilenmez.

## Platform farkları

| | Windows | Android |
|---|---|---|
| Düzen | Menü çubuğu, sol araç paneli, sağ özellik/katman paneli, durum çubuğu | Üst çubuk, alt araç şeridi, açılır panel |
| Açma | Dosya penceresi | Fotoğraf Seçici (galeri) + dosyalar |
| Kaydetme | Farklı Kaydet penceresi | Galeri › PIXELSHIFT albümü + Paylaş |
| Veritabanı | sqflite_common_ffi + paketli sqlite3.dll | sqflite (sistem SQLite) |
| Kapanış uyarısı | Pencere kapatma isteği (`AppLifecycleListener`) | Geri tuşu (`PopScope`) |
| Taşınabilir mod | `portable.txt` varsa veriler exe yanında | — |
