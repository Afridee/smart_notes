import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import '../../data/models/note_attachment.dart';
import '../../services/attachment_service.dart';
import '../../services/vector_store_service.dart';
import 'views/chat_attachment_view_pages.dart';

/// Parses `smartnotes://attachment/<attachmentId>` (host `attachment`).
String? smartNotesAttachmentIdFromUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return null;
  if (uri.scheme != 'smartnotes') return null;
  if (uri.host.toLowerCase() != 'attachment') return null;
  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final id = segs.first.trim();
  return id.isEmpty ? null : id;
}

/// Opens the in-app PDF or image viewer for [ref], if supported.
///
/// Shows a snackbar when the file is missing or the MIME type cannot be shown.
Future<void> openNoteAttachmentPreview(
  BuildContext context,
  NoteAttachmentRef ref,
) async {
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.maybeOf(context);
  if (scaffoldMessenger == null || navigator == null) return;

  final abs = await Get.find<AttachmentService>().absolutePathFor(ref);

  if (abs == null) {
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text('Missing file on disk for "${ref.displayName}".')),
    );
    return;
  }

  final mime = ref.mimeType.toLowerCase().trim();
  final ext = p.extension(ref.displayName).toLowerCase();
  final looksPdf = mime == 'application/pdf' || ext == '.pdf';
  final looksImage = mime.startsWith('image/');

  final title =
      ref.displayName.trim().isEmpty ? 'Attachment' : ref.displayName.trim();

  if (looksPdf) {
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PdfAttachmentViewerPage(path: abs, title: title),
      ),
    );
    return;
  }

  if (looksImage) {
    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImageAttachmentViewerPage(path: abs, title: title),
      ),
    );
    return;
  }

  scaffoldMessenger.showSnackBar(
    SnackBar(
      content: Text(
        'Opening "${ref.displayName}" is not supported in-app (type: $mime).',
      ),
    ),
  );
}

/// Resolves citations from this turn via chunk metadata → opens viewer.
Future<void> openSmartNotesAttachmentFromChat(
  BuildContext context,
  String url,
  List<SimilarChunk> citations,
) async {
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  if (scaffoldMessenger == null) return;

  final id = smartNotesAttachmentIdFromUrl(url);
  if (id == null) return;

  NoteAttachmentRef? ref;
  for (final hit in citations) {
    final list =
        attachmentsFromChunkMetadataJson(hit.chunk.chunkMetadataJson);
    for (final a in list) {
      if (a.id == id) {
        ref = a;
        break;
      }
    }
    if (ref != null) break;
  }

  if (ref == null) {
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Attachment not available for this reply.')),
    );
    return;
  }

  await openNoteAttachmentPreview(context, ref);
}
