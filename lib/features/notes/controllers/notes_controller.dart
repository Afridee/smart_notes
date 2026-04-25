import 'dart:developer' show log;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../data/objectbox/objectbox.dart';
import '../../../services/chunker_service.dart';
import '../../../services/embedding_service.dart';
import '../../../services/vector_store_service.dart';

class NotesController extends GetxController {
  NotesController({
    ObjectBox? box,
    EmbeddingService? embedder,
    ChunkerService? chunker,
    VectorStoreService? vectorStore,
  })  : _box = box ?? Get.find<ObjectBox>(),
        _embedder = embedder ?? Get.find<EmbeddingService>(),
        _chunker = chunker ?? Get.find<ChunkerService>(),
        _vectorStore = vectorStore ?? Get.find<VectorStoreService>();

  final ObjectBox _box;
  final EmbeddingService _embedder;
  final ChunkerService _chunker;
  final VectorStoreService _vectorStore;

  final notes = <Note>[].obs;
  final isSaving = false.obs;
  final saveStatus = ''.obs;
  final lastError = RxnString();

  @override
  void onReady() {
    super.onReady();
    refreshNotes();
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
  }) async {
    isSaving.value = true;
    lastError.value = null;
    saveStatus.value = 'Saving note…';
    try {
      final note = id == null || id == 0
          ? Note(title: title, body: body)
          : (_box.noteBox.get(id) ??
              Note(id: id, title: title, body: body));
      note.title = title;
      note.body = body;
      note.updatedAt = DateTime.now();
      final savedId = _box.noteBox.put(note);
      note.id = savedId;

      saveStatus.value = 'Chunking…';
      final chunks = _chunker.split(body);

      if (chunks.isNotEmpty) {
        if (id != null && id != 0) {
          await _vectorStore.deleteChunksForNote(savedId);
        }

        saveStatus.value = 'Embedding ${chunks.length} chunk(s)…';
        final vectors = await _embedder.embedBatch(
          chunks,
          taskType: TaskType.retrievalDocument,
        );

        saveStatus.value = 'Indexing…';
        final indexed = <IndexedChunk>[
          for (var i = 0; i < chunks.length; i++)
            IndexedChunk(text: chunks[i], vector: vectors[i]),
        ];
        await _vectorStore.addChunks(note, indexed);
      }

      saveStatus.value = 'Done';
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
    await _vectorStore.deleteChunksForNote(note.id);
    _box.noteBox.remove(note.id);
    refreshNotes();
  }
}
