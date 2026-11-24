import 'dart:ui';

import '../app/services.dart';
import '../collage/collage_layouts.dart';
import '../core/errors.dart';
import '../core/ids.dart';
import '../editor/document.dart';
import '../image_engine/codec.dart';
import '../image_engine/engine.dart';
import '../layers/layer.dart';
import '../platform_services/file_service.dart';
import '../platform_services/svg_rasterizer.dart';
import '../templates/templates.dart';
import 'project_database.dart';

class CreatedProject {
  const CreatedProject(this.info, {this.note});
  final ProjectInfo info;
  final String? note;
}

/// Yeni proje oluşturma yolları: fotoğraf, boş tuval, şablon, kolaj.
class ProjectFactory {
  ProjectFactory(this.services);
  final AppServices services;

  static String baseName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final n = dot > 0 ? fileName.substring(0, dot) : fileName;
    return n.trim().isEmpty ? 'Fotoğraf' : n.trim();
  }

  Future<ImportedImage> importPicked(PickedFile f) async {
    final kind = ImageCodec.detect(f.bytes, f.name);
    final maxSide = services.settings.previewMaxSide;
    if (kind == ImageKind.svg) {
      final raster = await SvgRasterizer.rasterize(f.bytes, longSide: 3000);
      return ImageEngine.importRaster(raster, ImageKind.svg, maxSide);
    }
    return ImageEngine.importImage(f.bytes, f.name, maxSide);
  }

  Future<CreatedProject> fromFile(PickedFile f, {ImportedImage? imported}) async {
    final img = imported ?? await importPicked(f);
    final info = await services.store.create(
      name: baseName(f.name),
      sourceBytes: img.storedBytes,
      sourceExtension: img.storedExtension,
      width: img.width,
      height: img.height,
      documentBuilder: (file) => EditDocument(sourceFile: file, sourceWidth: img.width, sourceHeight: img.height),
    );
    return CreatedProject(info, note: img.note);
  }

  Future<CreatedProject> blank(String name, int width, int height, int top, int bottom, {List<Layer> layers = const [], String kind = 'design'}) async {
    if (width < 1 || height < 1 || width > 12000 || height > 12000) {
      throw const UserFacingException('Tuval boyutu 1 ile 12000 piksel arasında olmalı.');
    }
    final png = await ImageEngine.blankCanvasPng(width, height, top, bottom);
    final info = await services.store.create(
      name: name,
      sourceBytes: png,
      sourceExtension: 'png',
      width: width,
      height: height,
      kind: kind,
      documentBuilder: (file) => EditDocument(sourceFile: file, sourceWidth: width, sourceHeight: height, layers: layers),
    );
    return CreatedProject(info);
  }

  Future<CreatedProject> fromTemplate(DesignTemplate t) =>
      blank(t.name, t.width, t.height, t.top, t.bottom, layers: t.build(t.width.toDouble(), t.height.toDouble()));

  /// Kolaj: düz renk zemin + her hücre için görsel katmanı.
  Future<CreatedProject> collage({
    required CollageLayout layout,
    required int width,
    required int height,
    required double spacing,
    required double radius,
    required int background,
    required List<PickedFile> photos,
    void Function(int done, int total)? progress,
  }) async {
    if (photos.isEmpty) throw const UserFacingException('Kolaj için en az bir fotoğraf seçin.');
    final created = await blank('Kolaj', width, height, background, background, kind: 'collage');
    final info = created.info;
    final cells = layout.pixelCells(width.toDouble(), height.toDouble(), spacing);
    final layers = <Layer>[];
    final count = photos.length < cells.length ? photos.length : cells.length;
    for (var i = 0; i < count; i++) {
      progress?.call(i, count);
      final f = photos[i];
      final img = await importPicked(f);
      final asset = await services.store.addAsset(info.id, img.storedBytes, img.storedExtension);
      final Rect cell = cells[i];
      layers.add(ImageLayer(
        id: newId('l'),
        name: f.name.length > 24 ? '${f.name.substring(0, 22)}…' : f.name,
        cx: cell.center.dx,
        cy: cell.center.dy,
        assetFile: asset,
        assetWidth: img.width,
        assetHeight: img.height,
        width: cell.width,
        height: cell.height,
        cornerRadius: radius,
      ));
    }
    progress?.call(count, count);
    final data = await services.store.load(info.id);
    final doc = data.current.copyWith(layers: layers);
    await services.store.save(data.info, [doc], const ['Kolaj oluşturuldu'], 0);
    final skipped = photos.length - count;
    return CreatedProject(
      data.info,
      note: skipped > 0 ? 'Düzende ${cells.length} hücre var; $skipped fotoğraf eklenmedi.' : null,
    );
  }

}
