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

/// Hard lower bound for the final max-sim score before we will draw an edge
/// at all. Anything below this is treated as unrelated even if it happens to
/// be a note's top neighbour. EmbeddingGemma puts noise pairs around
/// 0.15–0.30, so 0.35 buys headroom without being model-specific.
const double kGraphSimilarityFloor = 0.35;

/// Maximum edges a single note may anchor in the graph. The graph is the
/// union of every note's top-K, so verbose notes can't flood the layout and
/// short notes still get a fair shot at connecting to their closest peers.
const int kGraphTopKPerNote = 8;

/// First-stage filter for candidate generation using averaged note vectors
/// (cheap O(N·D)). Anything below this won't be re-ranked with max-sim. Kept
/// deliberately low so we don't prune real matches that average-pooling
/// happens to dilute.
const double kGraphCandidatePrefilter = 0.30;

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

/// Symmetric ColBERT-style max-sim aggregation between two bags of chunk
/// embeddings. For every chunk in [chunksA] we pick the cosine-similarity to
/// its single best counterpart in [chunksB] and average those maxes; we do
/// the same in the reverse direction and return the mean. The two-sided
/// average keeps the score symmetric (so the same edge wins from either
/// note's refresh) and bounded in `[-1, 1]`.
///
/// This avoids the averaging-dilution problem of comparing mean note
/// vectors: a short note that's a strong match for one paragraph of a long
/// note still scores highly.
double maxSimSymmetric(
  List<List<double>> chunksA,
  List<List<double>> chunksB,
) {
  final n = chunksA.length;
  final m = chunksB.length;
  if (n == 0 || m == 0) return 0;
  final rowMax = List<double>.filled(n, double.negativeInfinity);
  final colMax = List<double>.filled(m, double.negativeInfinity);
  for (var i = 0; i < n; i++) {
    final a = chunksA[i];
    for (var k = 0; k < m; k++) {
      final s = cosineSimilarity(a, chunksB[k]);
      if (s > rowMax[i]) rowMax[i] = s;
      if (s > colMax[k]) colMax[k] = s;
    }
  }
  var sumRow = 0.0;
  for (final v in rowMax) {
    sumRow += v;
  }
  var sumCol = 0.0;
  for (final v in colMax) {
    sumCol += v;
  }
  return 0.5 * (sumRow / n + sumCol / m);
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

  /// Recomputes [noteId]'s outgoing edges using a two-stage retrieval:
  ///
  ///   1. **Candidate generation** — cheap cosine over averaged note
  ///      vectors, filtered by [kGraphCandidatePrefilter]. This is O(N·D)
  ///      and is just trying to throw out obviously-unrelated notes.
  ///   2. **Max-sim re-rank** — symmetric per-chunk max-sim
  ///      ([maxSimSymmetric]) over the surviving candidates. This is the
  ///      score that actually decides which edges live.
  ///
  /// We then take the top [kGraphTopKPerNote] candidates that clear
  ///[kGraphSimilarityFloor] and persist them. The graph is the union of
  /// every note's top-K, which gives short notes a fair shot at appearing
  /// in the graph without letting verbose notes flood it (a single hard
  /// cutoff biases against the former and is biased *by* model calibration
  /// for the latter).
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

    final selfVec = self.noteEmbedding;
    final selfChunkVecs = _validChunkVectors(noteId);

    final others = _box.noteBox
        .getAll()
        .where((n) => n.id != noteId && hasValidNoteEmbedding(n))
        .toList();

    // Stage 1: cheap mean-vector prefilter.
    final candidates = <_Candidate>[];
    for (final o in others) {
      final mean = cosineSimilarity(selfVec, o.noteEmbedding);
      if (mean < kGraphCandidatePrefilter) {
        candidates.add(_Candidate(o, mean, null, kept: false));
        continue;
      }
      candidates.add(_Candidate(o, mean, null, kept: false));
    }

    // Stage 2: max-sim re-rank for survivors of the prefilter.
    for (final c in candidates) {
      if (c.mean < kGraphCandidatePrefilter) continue;
      final otherChunkVecs = _validChunkVectors(c.note.id);
      c.maxSim = maxSimSymmetric(selfChunkVecs, otherChunkVecs);
    }

    // Pick top-K by max-sim, applying the floor.
    final reranked = candidates
        .where((c) => c.maxSim != null && c.maxSim! >= kGraphSimilarityFloor)
        .toList()
      ..sort((a, b) => b.maxSim!.compareTo(a.maxSim!));
    final kept = reranked.take(kGraphTopKPerNote).toList();
    final keptIds = {for (final r in kept) r.note.id};
    for (final c in candidates) {
      c.kept = keptIds.contains(c.note.id);
    }

    final edges = <NoteEdge>[];
    for (final r in kept) {
      final otherId = r.note.id;
      final a = noteId < otherId ? noteId : otherId;
      final b = noteId < otherId ? otherId : noteId;
      edges.add(NoteEdge(noteIdA: a, noteIdB: b, similarityScore: r.maxSim!));
    }
    if (edges.isNotEmpty) {
      _box.edgeBox.putMany(edges);
    }

    candidates.sort((a, b) {
      final ax = a.maxSim ?? a.mean;
      final bx = b.maxSim ?? b.mean;
      return bx.compareTo(ax);
    });
    final report = StringBuffer()
      ..writeln(
        'refreshEdges note=$noteId "${self.title}" '
        'others=${others.length} '
        'prefilter\u2265${kGraphCandidatePrefilter.toStringAsFixed(2)} '
        'floor\u2265${kGraphSimilarityFloor.toStringAsFixed(2)} '
        'K=$kGraphTopKPerNote kept=${kept.length}',
      );
    for (final c in candidates.take(20)) {
      final mark = c.kept ? '\u2713' : ' ';
      final ms = c.maxSim == null
          ? '   -  '
          : c.maxSim!.toStringAsFixed(3);
      report.writeln(
        '  $mark maxsim=$ms  mean=${c.mean.toStringAsFixed(3)}  '
        'note=${c.note.id} "${c.note.title}"',
      );
    }
    log(report.toString().trimRight(), name: 'NoteGraphService');
  }

  List<List<double>> _validChunkVectors(int noteId) {
    final out = <List<double>>[];
    for (final c in _vectorStore.getChunksForNote(noteId)) {
      if (c.embedding.length == kNoteEmbeddingDimensions) {
        out.add(c.embedding);
      }
    }
    return out;
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

class _Candidate {
  _Candidate(this.note, this.mean, this.maxSim, {this.kept = false});
  final Note note;
  final double mean;
  double? maxSim;
  bool kept;
}
