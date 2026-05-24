import 'package:flutter/services.dart';

/// Android: copies a scanned PDF (`content://` or transient scanner `file://`) into app cache.
class ContentUriChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.smart_notes/content_uri');

  static Future<String?> materializePdf(String contentUri) async {
    return _channel.invokeMethod<String>('materializePdf', contentUri);
  }
}
