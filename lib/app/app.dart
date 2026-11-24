import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/app_info.dart';
import '../projects/home_page.dart';
import 'services.dart';
import 'theme.dart';
import 'unsaved_guard.dart';

/// Kök widget: tema, Türkçe yerelleştirme, kapanış koruması.
class PixelShiftApp extends StatefulWidget {
  const PixelShiftApp({super.key, required this.services, this.navigatorKey});
  final AppServices services;

  /// İsteğe bağlı dış gezinti anahtarı (ekran görüntüsü modu ve testler için).
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<PixelShiftApp> createState() => _PixelShiftAppState();
}

class _PixelShiftAppState extends State<PixelShiftApp> {
  late final GlobalKey<NavigatorState> _navigatorKey = widget.navigatorKey ?? GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: () => UnsavedGuard.handleExit(_navigatorKey));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Services(
      services: widget.services,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: AppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: buildPixelTheme(),
        darkTheme: buildPixelTheme(),
        themeMode: ThemeMode.dark,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomePage(),
      ),
    );
  }
}

/// Başlatma hatası ekranı (ör. veri klasörü yazılamıyor).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildPixelTheme(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: PxColors.danger),
                const SizedBox(height: 16),
                const Text('PIXELSHIFT başlatılamadı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                SelectableText(message, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('Kapat')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Paketlenen yazı tiplerinin lisanslarını "Açık kaynak lisansları" sayfasına ekler.
void registerFontLicenses() {
  const fonts = {
    'Inter': 'assets/fonts/LICENSE-Inter.txt',
    'Poppins': 'assets/fonts/OFL-Poppins.txt',
    'Fira Sans': 'assets/fonts/OFL-FiraSans.txt',
    'Anton': 'assets/fonts/OFL-Anton.txt',
    'Archivo Black': 'assets/fonts/OFL-ArchivoBlack.txt',
    'Crimson Text': 'assets/fonts/OFL-CrimsonText.txt',
    'Comic Relief': 'assets/fonts/OFL-ComicRelief.txt',
    'Anonymous Pro': 'assets/fonts/OFL-AnonymousPro.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in fonts.entries) {
      try {
        final text = await rootBundle.loadString(e.value);
        yield LicenseEntryWithLineBreaks([e.key], text);
      } catch (_) {
        // Lisans dosyası yoksa atlanır.
      }
    }
  });
}
