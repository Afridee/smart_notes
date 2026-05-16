import 'dart:developer' show log;
import 'dart:math' as math;

import 'package:get/get.dart';

import '../data/models/note.dart';
import '../data/models/note_edge.dart';
import '../data/objectbox/objectbox.dart';
import '../objectbox.g.dart';
import 'vector_store_service.dart';

/// Chunk / note embedding dimension for EmbeddingGemma in this app.
const int kNoteEmbeddingDimensions = 768;

/// Minimum cosine similarity to persist an undirected note pair.
///
/// EmbeddingGemma scores related-but-not-paraphrased short notes around
/// 0.55–0.75; the per-chunk header (title + dates) drags pairwise scores
/// down further. 0.55 is empirically a reasonable starting point — tune
/// up for stricter graphs or down for noisier ones.
const double kGraphSimilarityThreshold = 0.55;

/// Above this note count, the graph view only draws edges among the top-K
/// hubs by degree ([kGraphHubCount]).
const int kGraphNoteCountThreshold = 500;

const int kGraphHubCount = 50;

List<double> averageVectors(List<List<double>> vectors) {
  if (vectors.isEmpty) return const <double>[];
  final dim = vectors.first.length;
  if (dim == 0) return const <double>[];
  final sum = List<double>.filled(dim, 0);
  var n = 0;
  for (final v in vectors) {
    if (v.length != dim) continue;
    for (var i = 0; i < dim; i++) {
      sum[i] += v[i];
    }
    n++;
  }
  if (n == 0) return const <double>[];
  for (var i = 0; i < dim; i++) {
    sum[i] /= n;
  }
  return sum;
}

double cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length || a.isEmpty) return 0;
  var dot = 0.0;
  var na = 0.0;
  var nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na <= 0 || nb <= 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Notes indexed for the semantic graph (embedding + edges).
class NoteGraphService extends GetxService {
  NoteGraphService(this._box, this._vectorStore);

  final ObjectBox _box;
  final VectorStoreService _vectorStore;

  final isIndexing = false.obs;
  final indexedCount = 0.obs;
  final totalToIndex = 0.obs;

  bool _repairStarted = false;

  bool hasValidNoteEmbedding(Note note) =>
      note.noteEmbedding.length == kNoteEmbeddingDimensions;

  Future<void> kickoffStartupRepair() async {
    if (_repairStarted) return;
    _repairStarted = true;

    try {
      final notes = _box.noteBox.getAll();
      final todo = notes
          .where(
            (n) =>
                !hasValidNoteEmbedding(n) &&
                _vectorStore.getChunksForNote(n.id).isNotEmpty,
          )
          .toList();

      if (todo.isEmpty) return;

      totalToIndex.value = todo.length;
      indexedCount.value = 0;
      isIndexing.value = true;

      for (final note in todo) {
        await updateNoteEmbeddingFromChunks(note);
        await refreshEdgesForNote(note.id);
        indexedCount.value++;
        await Future<void>.delayed(Duration.zero);
      }
    } catch (e, st) {
      log(
        'NoteGraphService.kickoffStartupRepair failed',
        name: 'NoteGraphService',
        error: e,
        stackTrace: st,
      );
    } finally {
      isIndexing.value = false;
    }
  }

  Future<void> updateNoteEmbeddingFromChunks(Note note) async {
    final chunks = _vectorStore.getChunksForNote(note.id);
    if (chunks.isEmpty) {
      note.noteEmbedding = [];
      _box.noteBox.put(note);
      return;
    }
    final vectors = chunks
        .map((c) => c.embedding)
        .where((e) => e.length == kNoteEmbeddingDimensions)
        .toList();
    if (vectors.isEmpty) {
      note.noteEmbedding = [];
      _box.noteBox.put(note);
      return;
    }
    note.noteEmbedding = averageVectors(vectors);
    _box.noteBox.put(note);
  }

  Future<int> deleteEdgesForNote(int noteId) async {
    final q = _box.edgeBox
        .query(
          NoteEdge_.noteIdA.equals(noteId) | NoteEdge_.noteIdB.equals(noteId),
        )
        .build();
    try {
      return q.remove();
    } finally {
      q.close();
    }
  }

  Future<void> refreshEdgesForNote(int noteId) async {
    await deleteEdgesForNote(noteId);

    final self = _box.noteBox.get(noteId);
    if (self == null || !hasValidNoteEmbedding(self)) {
      log(
        'refreshEdges skipped: note $noteId has no valid embedding',
        name: 'NoteGraphService',
      );
      return;
    }

    final vec = self.noteEmbedding;
    final others = _box.noteBox
        .getAll()
        .where((n) => n.id != noteId && hasValidNoteEmbedding(n))
        .toList();

    final scored = <(int otherId, String title, double score, bool kept)>[];
    final edges = <NoteEdge>[];
    for (final o in others) {
      final score = cosineSimilarity(vec, o.noteEmbedding);
      final keep = score >= kGraphSimilarityThreshold;
      scored.add((o.id, o.title, score, keep));
      if (!keep) continue;
      final a = noteId < o.id ? noteId : o.id;
      final b = noteId < o.id ? o.id : noteId;
      edges.add(NoteEdge(noteIdA: a, noteIdB: b, similarityScore: score));
    }

    if (edges.isNotEmpty) {
      _box.edgeBox.putMany(edges);
    }

    scored.sort((a, b) => b.$3.compareTo(a.$3));
    final report = StringBuffer()
      ..writeln(
        'refreshEdges note=$noteId "${self.title}" '
        'threshold=${kGraphSimilarityThreshold.toStringAsFixed(2)} '
        'kept=${edges.length}/${scored.length}',
      );
    for (final s in scored) {
      report.writeln(
        '  ${s.$4 ? '✓' : ' '} ${s.$3.toStringAsFixed(3)}  '
        'note=${s.$1} "${s.$2}"',
      );
    }
    log(report.toString().trimRight(), name: 'NoteGraphService');
  }

  List<NoteEdge> edgesTouching(int noteId) {
    final q = _box.edgeBox
        .query(
          NoteEdge_.noteIdA.equals(noteId) | NoteEdge_.noteIdB.equals(noteId),
        )
        .build();
    try {
      final list = q.find();
      list.sort((a, b) => b.similarityScore.compareTo(a.similarityScore));
      return list;
    } finally {
      q.close();
    }
  }

  /// Related notes for backlinks UI, sorted by similarity descending.
  List<(Note note, double score)> topRelatedNotesWithScores(
    int noteId, {
    int limit = 5,
  }) {
    final edges = edgesTouching(noteId);
    final out = <(Note, double)>[];
    for (final e in edges) {
      if (out.length >= limit) break;
      final otherId = e.noteIdA == noteId ? e.noteIdB : e.noteIdA;
      final n = _box.noteBox.get(otherId);
      if (n != null) out.add((n, e.similarityScore));
    }
    return out;
  }

  List<Note> topRelatedNotes(int noteId, {int limit = 5}) =>
      topRelatedNotesWithScores(noteId, limit: limit).map((e) => e.$1).toList();

  List<Note> allNotesSorted() {
    final list = _box.noteBox.getAll()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  List<NoteEdge> allEdges() => _box.edgeBox.getAll();

  /// Applies the >500 notes hub filter from the product spec.
  List<NoteEdge> edgesForGraphView(List<NoteEdge> allEdges, int noteCount) {
    if (noteCount <= kGraphNoteCountThreshold) return allEdges;

    final degree = <int, int>{};
    for (final e in allEdges) {
      degree[e.noteIdA] = (degree[e.noteIdA] ?? 0) + 1;
      degree[e.noteIdB] = (degree[e.noteIdB] ?? 0) + 1;
    }
    final ranked = degree.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final hub =
        ranked.take(kGraphHubCount).map((e) => e.key).toSet();

    return allEdges
        .where((e) => hub.contains(e.noteIdA) && hub.contains(e.noteIdB))
        .toList();
  }

  Set<int> neighborIds(int noteId) {
    final s = <int>{};
    for (final e in edgesTouching(noteId)) {
      s.add(e.noteIdA == noteId ? e.noteIdB : e.noteIdA);
    }
    return s;
  }

  Note? getNote(int id) => _box.noteBox.get(id);
}
