# Kurulum

## Windows (10 / 11, 64 bit)

**Kurulum paketi**
1. `PIXELSHIFT-Setup-1.0.0.exe` dosyasını çalıştırın.
2. "Bilgisayarınızı korudu" (SmartScreen) uyarısı görürseniz **Ek bilgi → Yine de çalıştır** seçin. Uyarı, paketin kod imzalama sertifikası olmamasından kaynaklanır.
3. Kurulum yerini onaylayın; isterseniz masaüstü kısayolu ekleyin.
4. Veriler `%APPDATA%\Furkan\PIXELSHIFT\` klasöründe saklanır (konum Ayarlar ekranında da görünür).

**Taşınabilir sürüm**
1. `PIXELSHIFT-Portable-1.0.0-win-x64.zip` dosyasını istediğiniz klasöre (ör. USB bellek) çıkarın.
2. `pixelshift.exe` dosyasını çalıştırın. Kurulum gerekmez.
3. Klasörde `portable.txt` olduğu sürece veriler aynı klasördeki `PIXELSHIFT-Veri` dizininde tutulur. Klasör yazılamazsa (ör. Program Files) veriler kullanıcı klasörüne yazılır.

**Kaldırma:** Ayarlar → Uygulamalar → PIXELSHIFT → Kaldır. Uygulama verileri kullanıcı klasöründe kalır; tamamen silmek için yukarıdaki veri klasörünü silin.

## Android (5.0 ve üzeri)

1. `PIXELSHIFT-1.0.0*.apk` dosyasını telefona aktarın.
2. Dosyaya dokunun; istenirse **Bilinmeyen kaynaklardan yüklemeye izin ver** seçeneğini bu işlem için açın.
3. Kurun ve açın. Galeriden seçim için Android 13+ sistem fotoğraf seçicisi kullanılır (ek izin gerekmez). İnternet izni yalnızca sizin onayınızla çalışan AI işlemleri içindir; projeler yalnızca telefonda saklanır.

> Uygulama kaldırıldığında veya uygulama verileri temizlendiğinde projeler silinir. Dışa aktardığınız fotoğraflar galeride (PIXELSHIFT albümü) kalır.

## Kaynaktan derleme

Gereksinimler: Flutter 3.27.x, Windows için Visual Studio 2022 (C++ masaüstü geliştirme), Android için Android Studio / SDK ve Java 17.

```bash
git clone https://github.com/furkantr1923/pixelshift.git
cd pixelshift
flutter pub get
dart run tool/setup.dart

flutter build windows --release   # build\windows\x64\runner\Release\
flutter build apk --release       # build\app\outputs\flutter-apk\app-release.apk
```

Windows kurulum paketi için [Inno Setup 6.3+](https://jrsoftware.org/isinfo.php):

```bash
iscc /DAppVersion=1.0.0 installer\pixelshift.iss   # çıktı: dist\PIXELSHIFT-Setup-1.0.0.exe
```

## GitHub Actions ile otomatik derleme

Depoya her `push` işleminde `.github/workflows/build.yml` çalışır:

| İş | Ne yapar | Çıktı |
|---|---|---|
| Analiz ve testler | `flutter analyze`, `flutter test` | `test-sonuclari` |
| Windows | Release derleme, paket doğrulama, gerçek çalıştırma testi, Setup.exe, ZIP, uçtan uca test | `PIXELSHIFT-Windows`, `ekran-goruntuleri`, `windows-test-sonuclari` |
| Android | Release APK, imzalama, imza doğrulama | `PIXELSHIFT-Android` |
| Android emülatör testi | Android 14 emülatöründe uçtan uca test | `android-test-sonuclari` |
| GitHub Release | `v*` etiketi gönderilince paketleri sürüme ekler | Releases sayfası |

Sürüm yayınlamak için:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### Kalıcı Android imzası (önerilir)

Anahtar tanımlanmazsa APK her derlemede geçici bir anahtarla imzalanır; bu durumda yeni sürüm eski sürümün üzerine kurulamaz (önce kaldırmak gerekir ve veriler silinir). Kalıcı anahtar için bir kez:

```bash
keytool -genkey -v -keystore pixelshift-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias pixelshift
# Linux/macOS:
base64 -w 0 pixelshift-release.jks > keystore.txt
# Windows PowerShell:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("pixelshift-release.jks")) > keystore.txt
```

GitHub → depo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Değer |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `keystore.txt` içeriği |
| `ANDROID_KEYSTORE_PASSWORD` | Anahtar deposu parolası |
| `ANDROID_KEY_ALIAS` | `pixelshift` |
| `ANDROID_KEY_PASSWORD` | Anahtar parolası (aynıysa boş bırakılabilir) |

`.jks` dosyasını ve parolaları güvenli bir yerde saklayın; depoya **eklemeyin** (`.gitignore` bunu engeller).
