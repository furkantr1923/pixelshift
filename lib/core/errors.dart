import 'dart:async';
import 'dart:io';

/// Kullanıcıya doğrudan gösterilebilecek, Türkçe açıklamalı hata.
class UserFacingException implements Exception {
  const UserFacingException(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => message;
}

/// İşlem kullanıcı tarafından iptal edildi.
class OperationCancelled implements Exception {
  const OperationCancelled();

  @override
  String toString() => 'İşlem iptal edildi.';
}

/// Her türlü hatayı anlaşılır Türkçe bir mesaja çevirir.
String describeError(Object error) {
  if (error is UserFacingException) return error.message;
  if (error is OperationCancelled) return error.toString();
  if (error is SocketException) {
    return 'İnternet bağlantısı kurulamadı. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  if (error is TimeoutException) return 'İşlem zaman aşımına uğradı. Daha sonra tekrar deneyin.';
  if (error is HandshakeException) return 'Güvenli bağlantı kurulamadı (sertifika hatası).';
  if (error is FileSystemException) {
    final os = error.osError?.message;
    return 'Dosya işlemi başarısız: ${error.path ?? ''}${os != null ? ' ($os)' : ''}';
  }
  if (error is OutOfMemoryError) {
    return 'Bellek yetersiz. Daha küçük bir görsel deneyin veya diğer uygulamaları kapatın.';
  }
  if (error is FormatException) return 'Dosya biçimi okunamadı: ${error.message}';
  return 'Beklenmeyen bir hata oluştu: $error';
}
