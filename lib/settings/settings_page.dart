import 'dart:io';

import 'package:flutter/material.dart';

import '../ai/ai_models.dart';
import '../ai/online_providers.dart';
import '../app/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../image_engine/codec.dart';
import 'about_page.dart';

/// Ayarlar: AI sağlayıcıları, dışa aktarma, performans, depolama.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _hf;
  late final TextEditingController _rb;
  bool _showHf = false;
  bool _showRb = false;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final s = Services.of(context).settings;
      _hf = TextEditingController(text: s.hfToken);
      _rb = TextEditingController(text: s.removeBgKey);
      _init = true;
    }
  }

  @override
  void dispose() {
    _hf.dispose();
    _rb.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    final s = services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card('AI sağlayıcıları', Icons.auto_awesome, [
                  const InfoBox(
                    icon: Icons.privacy_tip_outlined,
                    color: PxColors.warning,
                    text: 'Anahtarlar kaynak koda gömülmez; yalnızca bu cihazdaki PIXELSHIFT veri klasöründe saklanır. '
                        'Çevrimiçi bir işlemden önce her seferinde, görselin hangi sağlayıcıya gönderileceği gösterilir ve izniniz istenir.',
                  ),
                  const SizedBox(height: 14),
                  const Text('Hugging Face', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Ücretsiz hesapla alınan erişim anahtarı (Settings › Access Tokens, "Read" yeterli). '
                      'Aylık ücretsiz çıkarım kredisi sınırlıdır; kredi bitince istek reddedilir, ücret oluşmaz.',
                      style: TextStyle(fontSize: 12, color: PxColors.muted)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hf,
                    obscureText: !_showHf,
                    decoration: InputDecoration(
                      labelText: 'Erişim anahtarı (hf_...)',
                      suffixIcon: IconButton(
                        icon: Icon(_showHf ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showHf = !_showHf),
                      ),
                    ),
                    onChanged: s.setHfToken,
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Modeller (gelişmiş)', style: TextStyle(fontSize: 13)),
                    children: [
                      for (final t in HuggingFaceProvider.defaultModels.keys)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextFormField(
                            initialValue: s.hfModels[t] ?? '',
                            decoration: InputDecoration(
                              labelText: t.label,
                              hintText: HuggingFaceProvider.defaultModels[t],
                              helperText: _licenseHelp(s.hfModels[t] ?? HuggingFaceProvider.defaultModels[t]!),
                            ),
                            onChanged: (v) => s.setHfModel(t, v),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 28),
                  const Text('remove.bg', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('Yalnızca arka plan kaldırma. Ücretsiz hesapta önizleme boyutunda sınırlı sayıda istek hakkı vardır.',
                      style: TextStyle(fontSize: 12, color: PxColors.muted)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _rb,
                    obscureText: !_showRb,
                    decoration: InputDecoration(
                      labelText: 'API anahtarı',
                      suffixIcon: IconButton(
                        icon: Icon(_showRb ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showRb = !_showRb),
                      ),
                    ),
                    onChanged: s.setRemoveBgKey,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tam çözünürlük (kredi harcar)', style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text('Kapalıyken ücretsiz önizleme boyutu kullanılır; maske fotoğrafınıza cihazda uygulanır.',
                        style: TextStyle(fontSize: 12)),
                    value: s.removeBgFullRes,
                    onChanged: s.setRemoveBgFullRes,
                  ),
                  const Divider(height: 28),
                  const Text('Görev başına varsayılan sağlayıcı', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final t in AiTask.values)
                    if (t != AiTask.textEdit)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _providerRow(context, t),
                      ),
                ]),
                _card('Dışa aktarma', Icons.ios_share, [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final f in ExportFormat.values)
                      PxChip(label: f.label, selected: s.exportFormat == f, onTap: () => s.setExportDefaults(f, s.exportQuality)),
                  ]),
                  LabeledSlider(
                    label: 'Varsayılan kalite',
                    value: s.exportQuality.toDouble(),
                    min: 10,
                    max: 100,
                    defaultValue: 92,
                    onChanged: (v) => s.setExportDefaults(s.exportFormat, v.round()),
                  ),
                ]),
                _card('Performans', Icons.speed, [
                  const Text('Önizleme çözünürlüğü (uzun kenar). Düşük değer daha akıcı, yüksek değer daha net önizleme sağlar. '
                      'Dışa aktarma her zaman tam çözünürlüktedir.',
                      style: TextStyle(fontSize: 12, color: PxColors.muted)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: [
                    for (final v in [1280, 1600, 2048, 2560])
                      PxChip(label: '$v px', selected: s.previewMaxSide == v, onTap: () => s.setPreviewMaxSide(v)),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Değişiklik bir sonraki açılan projede geçerli olur.', style: TextStyle(fontSize: 11.5, color: PxColors.muted)),
                ]),
                _card('Depolama', Icons.folder_outlined, [
                  SelectableText('Proje klasörü: ${services.paths.projectsDir}', style: const TextStyle(fontSize: 12.5)),
                  if (services.paths.portable)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Taşınabilir mod: veriler uygulama klasöründeki PIXELSHIFT-Veri dizininde.',
                          style: TextStyle(fontSize: 12, color: PxColors.accent)),
                    ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (Platform.isWindows)
                      OutlinedButton.icon(
                        onPressed: () => services.files.revealInExplorer(services.paths.projectsDir),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Klasörü aç'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final n = await services.paths.clearTemp();
                        if (context.mounted) showMessage(context, 'Geçici dosyalar temizlendi ($n öğe).');
                      },
                      icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                      label: const Text('Geçici dosyaları temizle'),
                    ),
                  ]),
                ]),
                _card('Hakkında', Icons.info_outline, [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('PIXELSHIFT hakkında, lisanslar ve gizlilik'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _licenseHelp(String model) {
    final l = HuggingFaceProvider.knownLicenses[model];
    return l == null ? 'Lisansı model sayfasından kontrol edin.' : 'Lisans: $l';
  }

  Widget _providerRow(BuildContext context, AiTask t) {
    final s = Services.of(context).settings;
    final providers = s.buildProviders().where((p) => p.supportedTasks.contains(t)).toList();
    final current = s.providerIdFor(t);
    return Row(
      children: [
        Expanded(child: Text(t.label, style: const TextStyle(fontSize: 13))),
        DropdownButton<String>(
          value: providers.any((p) => p.id == current) ? current : providers.first.id,
          items: [
            for (final p in providers)
              DropdownMenuItem(value: p.id, child: Text(p.isOnline ? '${p.name.split(' (').first} (çevrimiçi)' : 'Yerel (çevrimdışı)')),
          ],
          onChanged: (v) {
            if (v != null) s.setProviderFor(t, v);
          },
        ),
      ],
    );
  }

  Widget _card(String title, IconData icon, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(icon, size: 20, color: PxColors.accent),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
