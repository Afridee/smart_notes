import 'dart:io';

import 'package:flutter/services.dart';

import '../services/content_uri_channel.dart';

Future<String?> materializeScannedPdfForImport(String pdfUri) async {
  if (!Platform.isAndroid) return pdfUri;
  // Scanner may return `content://` or a transient `file://` under
  // `cache/mlkit_docscan_ui_client/`. Always copy ASAP into app cache —
  // the ML Kit cache file often disappears before [File.copy] runs.
  try {
    final out = await ContentUriChannel.materializePdf(pdfUri);
    if (out != null && out.isNotEmpty) return out;
  } on PlatformException {
    // Fall through — try original path below.
  } catch (_) {}
  return pdfUri;
}

Future<void> discardAndroidScanCacheIfNeeded(String path) async {
  if (!Platform.isAndroid) return;
  if (!path.contains('smart_notes_scan_')) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
