import 'dart:io';
import 'dart:math';

import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/models/note_attachment.dart';

/// Persists attachment binaries under `{appDocuments}/smart_notes_attachments/`.
///
/// Draft (unsaved) notes use `_staging/<draftId>/…` until [promoteStagingToNote].
class AttachmentService extends GetxService {
  static const attachmentsRootRelative = 'smart_notes_attachments';
  static const stagingDirName = '_staging';

  Future<String> get _documentsPath async =>
      (await getApplicationDocumentsDirectory()).path;

  Future<String> get attachmentsRootAbsolute async =>
      p.join(await _documentsPath, attachmentsRootRelative);

  /// Normalizes JSON-relative paths (`/` separators) for portability.
  static String posixRelative(String joined) =>
      joined.replaceAll(RegExp(r'[\\/]+'), '/');

  String relativeStagingDir(String draftId) => posixRelative(
        p.join(attachmentsRootRelative, stagingDirName, draftId),
      );

  String relativeNoteDir(int noteId) => posixRelative(
        p.join(attachmentsRootRelative, '$noteId'),
      );

  String _stagingPrefix(String draftId) =>
      '${posixRelative(relativeStagingDir(draftId))}/';

  /// Join `[documents]` with a posix-style relative attachment path from JSON.
  String _absUnderDocs(String documentsPath, String relPosix) {
    final segs = posixRelative(relPosix)
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (segs.any((s) => s == '..')) {
      throw StateError('Invalid attachment relative path.');
    }
    return p.joinAll(<String>[documentsPath, ...segs]);
  }

  Future<void> _ensureParent(String absolutePath) =>
      Directory(p.dirname(absolutePath)).create(recursive: true);

  Future<NoteAttachmentRef> importFile({
    required String sourceAbsolutePath,
    required String displayName,
    required String mimeType,
    required String draftId,
    int? persistedNoteId,
  }) async {
    final trimmedName = displayName.trim();
    final baseName =
        trimmedName.isEmpty ? p.basename(sourceAbsolutePath) : trimmedName;

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';

    var ext = p.extension(baseName).toLowerCase();
    if (ext.isEmpty && mimeType.trim().isNotEmpty) {
      ext = _extensionFromMime(mimeType);
      if (!ext.startsWith('.')) {
        ext = '.$ext';
      }
    }
    if (!ext.startsWith('.') && ext.isNotEmpty) {
      ext = '.$ext';
    }
    if (ext.isEmpty || ext == '.') {
      ext = '.bin';
    }

    final storedName = '$id$ext';
    final attRoot = await attachmentsRootAbsolute;

    late final String absoluteDestFile;
    if (persistedNoteId != null && persistedNoteId > 0) {
      final dirAbs = p.join(attRoot, '$persistedNoteId');
      absoluteDestFile = p.join(dirAbs, storedName);
    } else {
      final dirAbs = p.join(attRoot, stagingDirName, draftId);
      absoluteDestFile = p.join(dirAbs, storedName);
    }

    await _ensureParent(absoluteDestFile);
    await File(sourceAbsolutePath).copy(absoluteDestFile);

    final relStored = posixRelative(
      persistedNoteId != null && persistedNoteId > 0
          ? p.join(relativeNoteDir(persistedNoteId), storedName)
          : p.join(relativeStagingDir(draftId), storedName),
    );

    return NoteAttachmentRef(
      id: id,
      displayName: baseName,
      relativePath: relStored,
      mimeType: mimeType.isNotEmpty ? mimeType : mimeFromBasename(baseName),
    );
  }

  Future<List<NoteAttachmentRef>> promoteStagingToNote({
    required int savedNoteId,
    required String draftId,
    required List<NoteAttachmentRef> refs,
  }) async {
    if (draftId.trim().isEmpty || savedNoteId <= 0) return refs;

    final marker = _stagingPrefix(draftId);
    final hasStaging =
        refs.any((r) => posixRelative(r.relativePath).startsWith(marker));
    if (!hasStaging) return refs;

    final docs = await _documentsPath;
    final destPrefix =
        '${posixRelative(relativeNoteDir(savedNoteId))}/';

    await Directory(p.join(await attachmentsRootAbsolute, '$savedNoteId'))
        .create(recursive: true);

    final out = <NoteAttachmentRef>[];

    for (final r in refs) {
      final relNorm = posixRelative(r.relativePath);
      if (!relNorm.startsWith(marker)) {
        out.add(r);
        continue;
      }

      final fileName = relNorm.substring(marker.length);
      if (fileName.contains('/') || fileName.isEmpty) {
        out.add(r);
        continue;
      }

      final srcAbs = _absUnderDocs(docs, relNorm);
      final newRel = posixRelative('$destPrefix$fileName');
      final dstAbs = _absUnderDocs(docs, newRel);

      await _ensureParent(dstAbs);
      final fSrc = File(srcAbs);
      if (!await fSrc.exists()) {
        out.add(r);
        continue;
      }

      try {
        await fSrc.rename(dstAbs);
      } catch (_) {
        out.add(r);
        continue;
      }

      out.add(
        NoteAttachmentRef(
          id: r.id,
          displayName: r.displayName,
          relativePath: newRel,
          mimeType: r.mimeType,
          addedAt: r.addedAt,
        ),
      );
    }

    await _removeEmptyStagingIfPossible(draftId);
    return out;
  }

  Future<void> _removeEmptyStagingIfPossible(String draftId) async {
    try {
      final attRoot = await attachmentsRootAbsolute;
      final stagingDraft =
          Directory(p.join(attRoot, stagingDirName, draftId));
      if (!await stagingDraft.exists()) return;
      if (stagingDraft.listSync().isEmpty) {
        await stagingDraft.delete(recursive: false);
      }

      final stagingParent =
          Directory(p.join(attRoot, stagingDirName));
      if (await stagingParent.exists() &&
          stagingParent.listSync().isEmpty) {
        await stagingParent.delete(recursive: false);
      }
    } catch (_) {}
  }

  /// Resolves stored [ref.relativePath] to an absolute path when the file exists.
  Future<String?> absolutePathFor(NoteAttachmentRef ref) async {
    try {
      final docs = await _documentsPath;
      final abs = _absUnderDocs(docs, ref.relativePath);
      if (await File(abs).exists()) return abs;
    } catch (_) {}
    return null;
  }

  Future<void> deleteFiles(List<NoteAttachmentRef> refs) async {
    final docs = await _documentsPath;
    for (final r in refs) {
      try {
        final abs = _absUnderDocs(docs, r.relativePath);
        final f = File(abs);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> deleteAllFilesForNote(int noteId) async {
    try {
      final dir =
          Directory(p.join(await attachmentsRootAbsolute, '$noteId'));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<List<NoteAttachmentRef>> duplicateAttachmentsForNote({
    required List<NoteAttachmentRef> refs,
    required int destinationNoteId,
  }) async {
    if (refs.isEmpty) return refs;
    final docs = await _documentsPath;

    await Directory(p.join(await attachmentsRootAbsolute, '$destinationNoteId'))
        .create(recursive: true);

    final out = <NoteAttachmentRef>[];

    for (final r in refs) {
      final srcAbs = _absUnderDocs(docs, r.relativePath);
      final src = File(srcAbs);
      if (!await src.exists()) {
        continue;
      }

      final id =
          '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}';
      final extDot = () {
        final pe = p.extension(r.displayName);
        if (pe.isNotEmpty) return pe;
        final pr = posixRelative(r.relativePath);
        return p.extension(pr).isNotEmpty
            ? p.extension(pr).toLowerCase()
            : '.bin';
      }();

      final storedName =
          '${id}${extDot.startsWith('.') ? extDot : '.$extDot'}';
      final relDir = posixRelative(relativeNoteDir(destinationNoteId));
      final newRel = posixRelative(p.join(relDir, storedName));

      final dstAbs = _absUnderDocs(docs, newRel);

      await _ensureParent(dstAbs);
      await src.copy(dstAbs);

      out.add(
        NoteAttachmentRef(
          id: id,
          displayName: r.displayName,
          relativePath: newRel,
          mimeType: r.mimeType,
          addedAt: r.addedAt,
        ),
      );
    }

    return out;
  }

  /// Sanitize user-provided filenames (stored basename uses opaque [id]; this is cosmetic only).
  static String safeStem(String stem) =>
      stem.replaceAll(RegExp(r'[^\w\s\-\.]'), '').trim();

  static String _extensionFromMime(String mimeType) {
    switch (mimeType.toLowerCase().trim()) {
      case 'application/pdf':
      case 'pdf':
        return '.pdf';
      case 'image/png':
        return '.png';
      case 'image/jpeg':
      case 'image/jpg':
        return '.jpg';
      case 'image/webp':
        return '.webp';
      case 'image/heic':
      case 'image/heif':
        return '.heic';
      default:
        return '.bin';
    }
  }

  static String mimeFromBasename(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'application/octet-stream';
  }
}

