import 'dart:developer' show log;

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../data/models/note_attachment.dart';
import '../../../data/objectbox/objectbox.dart';
import '../../../services/attachment_service.dart';
import '../../../services/chunker_service.dart';
import '../../../services/embedding_service.dart';
import '../../../services/note_graph_service.dart';
import '../../../services/vector_store_service.dart';

class NotesController extends GetxController {
  NotesController({
    ObjectBox? box,
    EmbeddingService? embedder,
    ChunkerService? chunker,
    VectorStoreService? vectorStore,
    NoteGraphService? graph,
    AttachmentService? attachments,
  })  : _box = box ?? Get.find<ObjectBox>(),
        _embedder = embedder ?? Get.find<EmbeddingService>(),
        _chunker = chunker ?? Get.find<ChunkerService>(),
        _vectorStore = vectorStore ?? Get.find<VectorStoreService>(),
        _graph = graph ?? Get.find<NoteGraphService>(),
        _attachments =
            attachments ?? Get.find<AttachmentService>();

  final ObjectBox _box;
  final EmbeddingService _embedder;
  final ChunkerService _chunker;
  final VectorStoreService _vectorStore;
  final NoteGraphService _graph;
  final AttachmentService _attachments;

  final notes = <Note>[].obs;
  final isSaving = false.obs;
  final saveStatus = ''.obs;
  final lastError = RxnString();

  /// Drives list filtering; kept in sync with [searchFieldController].
  final searchQuery = ''.obs;

  /// Search box on the notes list; [searchQuery] updates via listener.
  late final TextEditingController searchFieldController;

  @override
  void onInit() {
    super.onInit();
    searchFieldController = TextEditingController();
    searchFieldController.addListener(() {
      searchQuery.value = searchFieldController.text;
    });
  }

  @override
  void onClose() {
    searchFieldController.dispose();
    super.onClose();
  }

  void clearSearch() {
    searchFieldController.clear();
  }

  @override
  void onReady() {
    super.onReady();
    refreshNotes();
    _graph.kickoffStartupRepair();
  }

  void refreshNotes() {
    final all = _box.noteBox.getAll()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notes.assignAll(all);
  }

  /// Persists [note], chunks the body, embeds each chunk, and stores
  /// the chunks in ObjectBox with HNSW vectors.
  Future<Note> saveNote({
    int? id,
    required String title,
    required String body,
    required List<NoteAttachmentRef> attachments,
    required String draftAttachmentSessionId,
  }) async {
    isSaving.value = true;
    lastError.value = null;
    saveStatus.value = 'Saving note…';
    try {
      final nid = id;
      final existed = nid != null && nid != 0;

      if (attachments.length > kMaxAttachmentsPerNote) {
        throw StateError(
          'A note can have at most $kMaxAttachmentsPerNote attachments.',
        );
      }

      Note? prev;
      if (nid != null && nid != 0) {
        prev = _box.noteBox.get(nid);
      }
      final prevRefs =
          prev == null ? <NoteAttachmentRef>[] : decodeAttachmentsJson(prev.attachmentsJson);

      final note = nid == null || nid == 0
          ? Note(title: title, body: body)
          : (prev ?? Note(id: nid, title: title, body: body));
      note.title = title;
      note.body = body;
      note.updatedAt = DateTime.now();

      final savedId = _box.noteBox.put(note);
      note.id = savedId;

      var finalizedAttachments = attachments;
      if (draftAttachmentSessionId.trim().isNotEmpty) {
        finalizedAttachments =
            await _attachments.promoteStagingToNote(
          savedNoteId: savedId,
          draftId: draftAttachmentSessionId,
          refs: attachments,
        );
      }

      final removedRefs = existed
          ? prevRefs.where(
              (o) =>
                  !finalizedAttachments.any(
                    (n) =>
                        AttachmentService.posixRelative(n.relativePath) ==
                        AttachmentService.posixRelative(o.relativePath),
                  ),
            ).toList()
          : null;
      if (removedRefs != null && removedRefs.isNotEmpty) {
        await _attachments.deleteFiles(removedRefs);
      }

      note.attachmentsJson = encodeAttachmentsJson(finalizedAttachments);
      _box.noteBox.put(note);

      saveStatus.value = 'Chunking…';
      final bodyChunks = _chunker.split(body);
      final rawHeader = _composeHeader(note);
      final attachHint = attachmentNamesForEmbedHint(finalizedAttachments);
      final header = attachHint.isEmpty
          ? rawHeader
          : (rawHeader.isEmpty ? attachHint : '$rawHeader\n$attachHint');

      final chunkMeta = buildChunkMetadataJson(finalizedAttachments);

      // Title-only notes: still index one chunk so the title is searchable.
      final chunks = bodyChunks.isEmpty && header.isNotEmpty
          ? const <String>['']
          : bodyChunks;

      if (chunks.isNotEmpty) {
        if (existed) {
          await _vectorStore.deleteChunksForNote(savedId);
        }

        final embedInputs = <String>[
          for (final c in chunks)
            header.isEmpty
                ? c
                : (c.isEmpty ? header : '$header\n\n$c'),
        ];

        saveStatus.value = 'Embedding ${chunks.length} chunk(s)…';
        final vectors = await _embedder.embedBatch(
          embedInputs,
          taskType: TaskType.retrievalDocument,
        );

        saveStatus.value = 'Indexing…';
        final indexed = <IndexedChunk>[
          for (var i = 0; i < chunks.length; i++)
            IndexedChunk(
              text: chunks[i],
              header: header,
              vector: vectors[i],
              chunkMetadataJson: chunkMeta,
            ),
        ];
        await _vectorStore.addChunks(note, indexed);
        await _graph.updateNoteEmbeddingFromChunks(note);
        await _graph.refreshEdgesForNote(note.id);
      }

      saveStatus.value = '';
      refreshNotes();
      return note;
    } catch (e, st) {
      lastError.value = e.toString();
      log('NotesController.saveNote failed', name: 'NotesController', error: e, stackTrace: st);
      rethrow;
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> deleteNote(Note note) async {
    await _graph.deleteEdgesForNote(note.id);
    await _vectorStore.deleteChunksForNote(note.id);
    await _attachments.deleteAllFilesForNote(note.id);
    _box.noteBox.remove(note.id);
    refreshNotes();
  }

  /// Builds the per-chunk context header that is concatenated with the body
  /// chunk before embedding and rendered above it in the RAG prompt.
  String _composeHeader(Note note) {
    final parts = <String>[];
    final title = note.title.trim();
    if (title.isNotEmpty) parts.add('Title: $title');
    parts.add('Created: ${_isoDate(note.createdAt)}');
    parts.add('Updated: ${_isoDate(note.updatedAt)}');
    return parts.join('\n');
  }

  String _isoDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
