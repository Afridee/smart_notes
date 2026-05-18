import 'dart:math' as math;

import 'package:get/get.dart';

import '../data/models/note.dart';
import '../data/models/note_chunk.dart';
import '../data/objectbox/objectbox.dart';
import '../objectbox.g.dart';
import 'note_graph_service.dart' show cosineSimilarity;
import 'retrieval_rerank.dart';

/// Tuple of (chunkText, contextHeader, embeddingVector) used when bulk-indexing a note.
///
/// [text] is the raw body chunk (kept verbatim for display / LLM context).
/// [header] is the per-chunk context block (e.g. title + dates) that was
/// concatenated with [text] before embedding. The vector therefore encodes
/// both, while [text] alone stays unpolluted for any non-RAG use.
class IndexedChunk {
  IndexedChunk({
    required this.text,
    required this.vector,
    this.header = '',
  });
  final String text;
  final String header;
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

  /// Bumped on every write that touches the chunk corpus. The cached BM25
  /// index ([_bm25Cache]) compares against this to know when to rebuild.
  int _corpusVersion = 0;
  Bm25Index? _bm25Cache;
  int? _bm25CacheVersion;

  /// Persists [chunks] for [note] in a single transaction.
  Future<List<int>> addChunks(Note note, List<IndexedChunk> chunks) async {
    if (chunks.isEmpty) return const [];

    final entities = <NoteChunk>[];
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      final entity = NoteChunk(
        chunkIndex: i,
        text: c.text,
        contextHeader: c.header,
        embedding: c.vector,
      )..note.target = note;
      entities.add(entity);
    }
    final ids = _box.chunkBox.putMany(entities);
    _corpusVersion++;
    return ids;
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

  /// Dense retrieval with optional BM25 fusion, then MMR diversification.
  ///
  ///   1. Pull a [candidatePoolSize]-wide dense candidate pool via HNSW.
  ///   2. If [useBm25], augment that pool with BM25's top hits the dense
  ///      search missed (proper names / code identifiers / CLI flags that
  ///      dense embeddings fuzz over).
  ///   3. Min-max-normalize each signal and fuse with [bm25Weight].
  ///   4. Run MMR to strip near-duplicate chunks (often three slices of the
  ///      same long note), then return the final [k].
  ///
  /// Every returned [SimilarChunk.score] is the pure cosine-to-query so the
  /// RAG prompt and citation UI keep displaying a meaningful number.
  Future<List<SimilarChunk>> searchHybrid({
    required String queryText,
    required List<double> queryVec,
    int k = 3,
    int candidatePoolSize = 12,
    double mmrLambda = 0.7,
    bool useBm25 = true,
    double bm25Weight = 0.3,
  }) async {
    final effectivePool = math.max(candidatePoolSize, k);
    final dense = await searchSimilar(queryVec, k: effectivePool);
    final pool = <int, SimilarChunk>{
      for (final d in dense) d.chunk.id: d,
    };

    Map<int, double> bmScores = const {};
    if (useBm25 && queryText.trim().isNotEmpty) {
      final bm25 = _ensureBm25();
      bmScores = bm25.score(queryText);
      final sortedBm = bmScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      var added = 0;
      for (final entry in sortedBm) {
        if (pool.containsKey(entry.key)) continue;
        if (added >= effectivePool) break;
        final chunk = _box.chunkBox.get(entry.key);
        if (chunk == null) continue;
        final cv = chunk.embedding;
        final cs = (cv.length == queryVec.length && cv.isNotEmpty)
            ? cosineSimilarity(cv, queryVec)
            : 0.0;
        pool[entry.key] = SimilarChunk(chunk: chunk, score: cs);
        added++;
      }
    }

    if (pool.isEmpty) return const <SimilarChunk>[];

    final cands = pool.values.toList();
    final denseNorm = minMaxNormalize([for (final c in cands) c.score]);
    final bmNorm = useBm25
        ? minMaxNormalize(
            [for (final c in cands) bmScores[c.chunk.id] ?? 0.0])
        : List<double>.filled(cands.length, 0);

    final fused = <_FusedCandidate>[];
    for (var i = 0; i < cands.length; i++) {
      final combined = useBm25
          ? (1 - bm25Weight) * denseNorm[i] + bm25Weight * bmNorm[i]
          : denseNorm[i];
      fused.add(_FusedCandidate(cands[i], combined));
    }
    fused.sort((a, b) => b.fused.compareTo(a.fused));

    final mmrInput = [
      for (final f in fused.take(math.max(k * 2, k))) f.chunk,
    ];
    return applyMmr(
      candidates: mmrInput,
      queryVec: queryVec,
      k: k,
      lambda: mmrLambda,
    );
  }

  /// Lazy + cached BM25 build over the chunk corpus, keyed on
  /// [_corpusVersion]. Cheap as long as chunks aren't being written between
  /// queries.
  Bm25Index _ensureBm25() {
    if (_bm25Cache != null && _bm25CacheVersion == _corpusVersion) {
      return _bm25Cache!;
    }
    final all = _box.chunkBox.getAll();
    final docs = <int, String>{
      for (final c in all)
        c.id: c.contextHeader.isEmpty
            ? c.text
            : '${c.contextHeader}\n${c.text}',
    };
    final built = Bm25Index.build(docs);
    _bm25Cache = built;
    _bm25CacheVersion = _corpusVersion;
    return built;
  }

  /// Deletes all chunks belonging to [noteId].
  Future<int> deleteChunksForNote(int noteId) async {
    final query = _box.chunkBox
        .query(NoteChunk_.note.equals(noteId))
        .build();
    try {
      final removed = query.remove();
      if (removed > 0) _corpusVersion++;
      return removed;
    } finally {
      query.close();
    }
  }

  int chunkCount() => _box.chunkBox.count();

  /// Chunks for [noteId], ordered by [NoteChunk.chunkIndex].
  List<NoteChunk> getChunksForNote(int noteId) {
    final query = _box.chunkBox
        .query(NoteChunk_.note.equals(noteId))
        .build();
    try {
      final list = query.find();
      list.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
      return list;
    } finally {
      query.close();
    }
  }
}

class _FusedCandidate {
  _FusedCandidate(this.chunk, this.fused);
  final SimilarChunk chunk;
  final double fused;
}
