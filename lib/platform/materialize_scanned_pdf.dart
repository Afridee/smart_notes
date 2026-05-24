import 'materialize_scanned_pdf_stub.dart'
    if (dart.library.io) 'materialize_scanned_pdf_io.dart' as impl;

/// After [FlutterDocScanner] returns a PDF, Android may supply a `content://` URI
/// or a short-lived `file://` path under ML Kit cache. Copies into app cache and
/// returns a stable absolute path suitable for [AttachmentService.importFile].
Future<String?> materializeScannedPdfForImport(String pdfUri) =>
    impl.materializeScannedPdfForImport(pdfUri);

Future<void> discardAndroidScanCacheIfNeeded(String path) =>
    impl.discardAndroidScanCacheIfNeeded(path);
