import 'package:get/get.dart';

import '../data/models/note.dart';
import '../data/models/note_chunk.dart';
import '../data/objectbox/objectbox.dart';
import '../objectbox.g.dart';

/// Tuple of (chunkText, embeddingVector) used when bulk-indexing a note.
class IndexedChunk {
  IndexedChunk({required this.text, required this.vector});
  final String text;
  final List<double> vector;
}

/// Result item for vector search.
class SimilarChunk {
  SimilarChunk({required this.chunk, required this.score});
  final NoteChunk chunk;
  final double score;
}

/// ObjectBox-backed vector store with HNSW search on [NoteChunk.embedding].
class VectorStoreService extends GetxService {
  VectorStoreService(this._box);

  final ObjectBox _box;

  /// Persists [chunks] for [note] in a single transaction.
  Future<List<int>> addChunks(Note note, List<IndexedChunk> chunks) async {
    if (chunks.isEmpty) return const [];

    final entities = <NoteChunk>[];
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      final entity = NoteChunk(
        chunkIndex: i,
        text: c.text,
        embedding: c.vector,
      )..note.target = note;
      entities.add(entity);
    }
    return _box.chunkBox.putMany(entities);
  }

  /// Returns top-[k] similar chunks for [queryVec].
  ///
  /// ObjectBox HNSW returns scores as distance; for cosine distance type,
  /// similarity = 1 - distance. We convert and optionally filter by [minScore].
  Future<List<SimilarChunk>> searchSimilar(
    List<double> queryVec, {
    int k = 3,
    double minScore = 0.0,
  }) async {
    final query = _box.chunkBox
        .query(NoteChunk_.embedding.nearestNeighborsF32(queryVec, k))
        .build();
    try {
      final results = query.findWithScores();
      final mapped = <SimilarChunk>[];
      for (final r in results) {
        final similarity = 1.0 - r.score;
        if (similarity < minScore) continue;
        mapped.add(SimilarChunk(chunk: r.object, score: similarity));
      }
      return mapped;
    } finally {
      query.close();
    }
  }

  /// Deletes all chunks belonging to [noteId].
  Future<int> deleteChunksForNote(int noteId) async {
    final query = _box.chunkBox
        .query(NoteChunk_.note.equals(noteId))
        .build();
    try {
      return query.remove();
    } finally {
      query.close();
    }
  }

  int chunkCount() => _box.chunkBox.count();
}
