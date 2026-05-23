import 'dart:convert';

/// Maximum PDF/image attachments allowed on a single [Note].
const int kMaxAttachmentsPerNote = 5;

/// Stored on [Note] as JSON (`attachmentsJson`) and duplicated into each chunk
/// `chunkMetadataJson` under key `attachments` for retrieval context.
class NoteAttachmentRef {
  NoteAttachmentRef({
    required this.id,
    required this.displayName,
    required this.relativePath,
    required this.mimeType,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  final String displayName;

  /// Path relative to the app documents directory returned by path_provider.
  final String relativePath;
  final String mimeType;

  /// UTC is fine here; persisted as ISO-8601.
  final DateTime addedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'relativePath': relativePath,
        'mimeType': mimeType,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  static NoteAttachmentRef fromJson(Map<String, dynamic> m) {
    return NoteAttachmentRef(
      id: m['id'] as String,
      displayName: m['displayName'] as String,
      relativePath: m['relativePath'] as String,
      mimeType: m['mimeType'] as String? ?? _mimeFromExtension(m['displayName'] as String? ?? ''),
      addedAt: DateTime.tryParse(m['addedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Decodes `[Note.attachmentsJson]` (stores a JSON array).
List<NoteAttachmentRef> decodeAttachmentsJson(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return [];
  final decoded = jsonDecode(t);
  if (decoded is! List<dynamic>) return [];
  final out = <NoteAttachmentRef>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    try {
      out.add(NoteAttachmentRef.fromJson(Map<String, dynamic>.from(e)));
    } catch (_) {
      continue;
    }
  }
  return out;
}

String encodeAttachmentsJson(List<NoteAttachmentRef> refs) =>
    jsonEncode(refs.map((e) => e.toJson()).toList());

/// Object stored per chunk alongside embeddings (duplicate of note refs).
String buildChunkMetadataJson(List<NoteAttachmentRef> attachments) =>
    jsonEncode(<String, dynamic>{
      'attachments': attachments.map((e) => e.toJson()).toList(),
    });

/// Parses the `attachments` array from [NoteChunk.chunkMetadataJson].
List<NoteAttachmentRef> attachmentsFromChunkMetadataJson(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return [];
  dynamic decoded;
  try {
    decoded = jsonDecode(t);
  } catch (_) {
    return [];
  }
  if (decoded is! Map<String, dynamic>) return [];
  final list = decoded['attachments'];
  if (list is! List<dynamic>) return [];
  final out = <NoteAttachmentRef>[];
  for (final e in list) {
    if (e is! Map) continue;
    try {
      out.add(NoteAttachmentRef.fromJson(Map<String, dynamic>.from(e)));
    } catch (_) {
      continue;
    }
  }
  return out;
}

String attachmentNamesForEmbedHint(List<NoteAttachmentRef> attachments) {
  if (attachments.isEmpty) return '';
  final names = attachments.map((a) => a.displayName.trim()).where((s) => s.isNotEmpty);
  final joined = names.join('; ');
  if (joined.isEmpty) return '';
  return 'Attached files (metadata only - see app for content): $joined';
}

String _mimeFromExtension(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic')) return 'image/heic';
  return 'application/octet-stream';
}
