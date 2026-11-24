# AI sağlayıcıları, lisanslar ve sınırlar

PIXELSHIFT ücretsiz ve açık kaynaklı çözümleri önceliklendirir. Hiçbir sağlayıcı kullanıcıdan habersiz ücret oluşturamaz; API anahtarları kaynak koda gömülmez.

## 1. Yerel — klasik algoritma (varsayılan, çevrimdışı)

Yapay zekâ modeli **değildir**; tamamen PIXELSHIFT'in içinde, cihazda çalışır. Fotoğraf cihazdan çıkmaz, internet gerekmez, ücretsizdir.

| Görev | Yöntem | İyi çalıştığı durum |
|---|---|---|
| Arka plan kaldırma | Kenarlardan taşma (flood fill) + yumuşak kenar | Düz/stüdyo arka planlar |
| Arka plan değiştirme | Şeffaf alanları renk, geçiş veya görselle birleştirme | Kaldırma sonrası |
| Nesne silme | Çok ölçekli piramit + Jacobi difüzyonu + doku gürültüsü | Küçük/orta nesneler, düzgün zemin |
| İyileştirme | Histogram yüzdelikleri, gri dünya beyaz dengesi, netlik | Genel fotoğraflar |
| Çözünürlük yükseltme | Bikübik (Catmull-Rom) + keskinleştirme | Yeni ayrıntı üretmez |
| Portre / cilt | YCbCr ten maskesi + kenar koruyan yumuşatma | Yüz algılama yoktur |
| Restorasyon | Medyan gürültü azaltma + seviye/renk düzeltme | Tozlu, solmuş fotoğraflar |
| Stiller | Kuwahara (yağlı boya), renk soldurma (karakalem), posterize + Sobel (çizgi film), pop art | — |
| Metin komutu | Kural tabanlı Türkçe yorumlayıcı → tahribatsız ayarlar | Işık, renk, filtre, döndürme komutları |

## 2. Hugging Face (çevrimiçi, isteğe bağlı)

- **Gereken:** Ücretsiz Hugging Face hesabı ve "Read" yetkili erişim anahtarı (`hf_...`). Ayarlar › AI sağlayıcıları.
- **Uç nokta:** `https://router.huggingface.co/hf-inference/models/<model>`
- **Ücret / sınır:** Ücretsiz hesaplara aylık sınırlı çıkarım kredisi tanınır; miktarı Hugging Face belirler ve değişebilir. Kredi bitince istek `402` ile reddedilir ve PIXELSHIFT bunu "ücret oluşturulmadı" mesajıyla bildirir. Uygulama ücretli kullanımı kendiliğinden başlatmaz.
- **Gönderilen veri:** Katmanlar hariç düzenlenmiş görüntü, en fazla 1536 px'e (büyütmede 1024 px) küçültülerek; EXIF yok.
- **Saklama:** Sağlayıcının politikasına tabidir (huggingface.co/privacy). PIXELSHIFT bu bilgiyi doğrulayamaz ve izin penceresinde bunu açıkça belirtir.

| Görev | Varsayılan model | Lisans |
|---|---|---|
| Arka plan kaldırma | `briaai/RMBG-1.4` | bria-rmbg-1.4 — **yalnızca ticari olmayan kullanım** |
| Çözünürlük yükseltme (2×) | `caidas/swin2SR-classical-sr-x2-64` | Apache-2.0 |
| Sanatsal stil / metin komutu | `timbrooks/instruct-pix2pix` | MIT |

Modeller Ayarlar'dan değiştirilebilir (ör. MIT lisanslı `ZhengPeng7/BiRefNet`). Bir modelin hf-inference üzerinde sunulup sunulmadığı Hugging Face'e bağlıdır; sunulmuyorsa uygulama `404` için "başka bir model deneyin" mesajı verir.

## 3. remove.bg (çevrimiçi, isteğe bağlı)

- **Gereken:** remove.bg hesabı ve API anahtarı.
- **Varsayılan:** `size=preview` (en fazla ~0,25 MP). Ücretsiz hesaplarda aylık sınırlı sayıda ücretsiz istek hakkı vardır. Dönen maske tam çözünürlüklü fotoğrafa **cihazda** uygulanır.
- **Tam çözünürlük:** Ayarlar'da açıkça etkinleştirilirse her işlem kredi harcar; izin penceresinde kırmızı uyarı olarak gösterilir. Kredi yoksa istek `402` ile reddedilir.
- **Saklama:** remove.bg gizlilik politikasına tabidir (remove.bg/privacy).

## İzin akışı

1. Kullanıcı çevrimiçi bir görevi başlatır.
2. Pencere; sağlayıcıyı, adresi, modeli ve lisansını, ne gönderileceğini, saklama bilgisini, ücret/sınırları ve politika bağlantısını gösterir.
3. **Gönderme** → hiçbir ağ isteği yapılmaz (birim testi: `ai_test.dart › izin verilmezse ... HİÇ istek gitmez`).
4. **İzin ver ve gönder** → HTTPS isteği; ilerleme, geçen süre ve iptal düğmesi gösterilir.
5. Hata durumunda (bağlantı yok, anahtar geçersiz, kredi bitti, model yükleniyor, zaman aşımı) Türkçe açıklama gösterilir; uygulamanın geri kalanı etkilenmez. Yerel yöntemler her zaman kullanılabilir.

Gönderim bellekte yapılır, geçici dosya oluşturulmaz.
