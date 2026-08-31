import 'package:flutter/foundation.dart';

/// Yalnız DEBUG derlemesinde yazan günlükleyici.
///
/// `debugPrint` adına rağmen release derlemesinde de çalışır ve logcat'e basar.
/// Hata metinleri (sunucu gövdeleri, ağ hataları, dosya yolları, oturum
/// durumları) cihaza USB ile bağlanan ya da `adb logcat` çalıştırabilen
/// herkesin okuyabileceği yere düşüyordu. Uygulama içindeki tüm günlükleme
/// buradan geçer; release'te tek satır çıkmaz.
void logD(String message) {
  if (kDebugMode) debugPrint(message);
}
