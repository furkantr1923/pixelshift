import 'dart:io';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/app_info.dart';

/// Hakkında: imza, sürüm, gizlilik ve lisanslar.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hakkında')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset('assets/icon/app_icon.png', width: 112, height: 112),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ShaderMask(
                  shaderCallback: (r) => PxColors.brandGradient.createShader(r),
                  child: const Text(AppInfo.name,
                      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 3, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text('Sürüm ${AppInfo.version} • ${Platform.isAndroid ? 'Android' : 'Windows'}',
                    style: const TextStyle(color: PxColors.muted)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PxColors.primary.withOpacity(0.5)),
                  color: PxColors.primary.withOpacity(0.08),
                ),
                child: const Text(AppInfo.signature,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 24),
              _section('Gizlilik', [
                'Fotoğraflarınız ve projeleriniz yalnızca bu cihazda saklanır; hesap veya bulut yoktur.',
                'Temel düzenleme tamamen çevrimdışı çalışır.',
                'Çevrimiçi AI işlemleri yalnızca sizin açık izninizle, her işlemden önce sağlayıcı bilgisi gösterilerek yapılır. İzin vermezseniz görsel gönderilmez.',
                'Dışa aktarılan dosyalarda EXIF/konum bilgisi bulunmaz.',
              ]),
              _section('Dürüst sınırlamalar', [
                'PSD: katmanlar ayrı açılmaz, birleştirilmiş görüntü düzenlenir.',
                'RAW: ham sensör verisi değil, kameranın gömülü JPEG önizlemesi kullanılır.',
                'GIF: animasyon korunmaz, ilk kare düzenlenir. HEIC/AVIF desteklenmez.',
                '"Yerel" AI araçları klasik görüntü işleme algoritmalarıdır, yapay zekâ modeli değildir.',
              ]),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: AppInfo.name,
                  applicationVersion: AppInfo.version,
                  applicationLegalese: '${AppInfo.signature}\nYazı tipleri SIL Open Font License 1.1 ile dağıtılır.',
                ),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Açık kaynak lisansları'),
              ),
              const SizedBox(height: 12),
              const Center(child: SelectableText(AppInfo.repository, style: TextStyle(color: PxColors.muted, fontSize: 12))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<String> lines) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: PxColors.accent)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l, style: const TextStyle(height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
