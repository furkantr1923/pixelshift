import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/errors.dart';
import '../image_engine/codec.dart';

/// Seçilen dosya (bayt olarak okunur; Android içerik URI'lerinde de çalışır).
class PickedFile {
  const PickedFile(this.name, this.bytes, {this.path});
  final String name;
  final Uint8List bytes;
  final String? path;
}

/// Kaydetme sonucu: kullanıcıya gösterilecek konum açıklaması.
class SaveResult {
  const SaveResult(this.description, {this.path});
  final String description;
  final String? path;
}

/// Dosya açma/kaydetme, galeri ve paylaşım işlemleri. Platform farkları
/// yalnızca burada ele alınır.
class FileService {
  FileService({this.tempDir});

  final String? tempDir;

  bool get isAndroid => Platform.isAndroid;
  bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static const XTypeGroup imageTypes = XTypeGroup(
    label: 'Görseller',
    extensions: ImageCodec.openExtensions,
    mimeTypes: ['image/*', 'application/octet-stream', 'image/vnd.adobe.photoshop', 'image/svg+xml'],
    uniformTypeIdentifiers: ['public.image'],
  );

  /// Dosya yöneticisinden görsel(ler) seçer.
  Future<List<PickedFile>> pickFiles({bool multiple = false}) async {
    final List<XFile> files;
    if (multiple) {
      files = await openFiles(acceptedTypeGroups: const [imageTypes], confirmButtonText: 'Aç');
    } else {
      final f = await openFile(acceptedTypeGroups: const [imageTypes], confirmButtonText: 'Aç');
      files = f == null ? const [] : [f];
    }
    return _read(files);
  }

  /// Android galerisinden (Fotoğraf Seçici) görsel(ler) seçer.
  /// Android 13+ sistem fotoğraf seçicisi ek izin gerektirmez.
  Future<List<PickedFile>> pickFromGallery({bool multiple = false}) async {
    if (!isAndroid) return pickFiles(multiple: multiple);
    final picker = ImagePicker();
    final List<XFile> files;
    if (multiple) {
      files = await picker.pickMultiImage(requestFullMetadata: false);
    } else {
      final f = await picker.pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      files = f == null ? const [] : [f];
    }
    return _read(files);
  }

  /// Toplu işlem için: dosyalar seçilir ama hemen belleğe okunmaz.
  Future<List<XFile>> pickXFiles({bool gallery = false}) async {
    if (gallery && isAndroid) return ImagePicker().pickMultiImage(requestFullMetadata: false);
    return openFiles(acceptedTypeGroups: const [imageTypes], confirmButtonText: 'Seç');
  }

  Future<List<PickedFile>> _read(List<XFile> files) async {
    final out = <PickedFile>[];
    for (final f in files) {
      try {
        out.add(PickedFile(f.name, await f.readAsBytes(), path: f.path));
      } catch (e) {
        throw UserFacingException('"${f.name}" okunamadı: ${describeError(e)}');
      }
    }
    return out;
  }

  /// Windows: Farklı Kaydet penceresi. Android: galeriye (PIXELSHIFT albümü).
  Future<SaveResult?> saveImage(Uint8List bytes, String suggestedName, ExportFormat format) async {
    if (isAndroid) return saveToGallery(bytes, suggestedName);
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [XTypeGroup(label: format.label, extensions: [format.extension], mimeTypes: [format.mimeType])],
      confirmButtonText: 'Kaydet',
    );
    if (location == null) return null;
    var path = location.path;
    if (p.extension(path).isEmpty) path = '$path.${format.extension}';
    await File(path).writeAsBytes(bytes, flush: true);
    return SaveResult(path, path: path);
  }

  Future<SaveResult> saveToGallery(Uint8List bytes, String fileName) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      final granted = await Gal.requestAccess(toAlbum: true);
      if (!granted) {
        throw const UserFacingException('Galeriye kaydetmek için izin verilmedi. Ayarlardan PIXELSHIFT için fotoğraf iznini açın.');
      }
    }
    final file = await _writeTemp(bytes, fileName);
    try {
      await Gal.putImage(file.path, album: 'PIXELSHIFT');
    } on GalException catch (e) {
      throw UserFacingException('Galeriye kaydedilemedi: ${_galMessage(e)}');
    } finally {
      _deleteQuietly(file);
    }
    return SaveResult('Galeri › PIXELSHIFT albümü ($fileName)');
  }

  String _galMessage(GalException e) => switch (e.type) {
        GalExceptionType.accessDenied => 'erişim reddedildi',
        GalExceptionType.notEnoughSpace => 'cihazda yeterli alan yok',
        GalExceptionType.notSupportedFormat => 'bu format galeride desteklenmiyor',
        GalExceptionType.unexpected => 'beklenmeyen hata',
      };

  /// Paylaşım menüsü (Android'de ana kullanım; Windows'ta da çalışır).
  Future<void> share(Uint8List bytes, String fileName, String mimeType) async {
    final file = await _writeTemp(bytes, fileName);
    await Share.shareXFiles([XFile(file.path, mimeType: mimeType, name: fileName)], subject: fileName);
  }

  /// Toplu işlem çıktı klasörü (yalnızca masaüstü).
  Future<String?> pickDirectory() => getDirectoryPath(confirmButtonText: 'Klasörü seç');

  Future<File> _writeTemp(Uint8List bytes, String fileName) async {
    final dir = Directory(tempDir ?? Directory.systemTemp.path);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  void _deleteQuietly(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Windows Gezgini'nde klasörü açar.
  Future<void> revealInExplorer(String path) async {
    if (!Platform.isWindows) return;
    final target = FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path);
    await Process.run('explorer', [target]);
  }
}
