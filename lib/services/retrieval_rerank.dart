import 'dart:math' as math;

import 'note_graph_service.dart' show cosineSimilarity;
import 'vector_store_service.dart';

/// Maximal Marginal Relevance — diversifies a ranked pool by penalising
/// candidates that are too similar to the ones already picked. We use it to
/// strip near-duplicate chunks from the RAG context window so the LLM sees
/// `k` *different* paragraphs instead of `k` clones of the most-relevant one.
///
/// [lambda] balances relevance vs novelty: 1.0 reduces to plain top-K
/// (no diversification), 0.0 picks the most-different chunks regardless of
/// query relevance. 0.7 is the standard MMR default.
///
/// Candidates whose `chunk.embedding` length doesn't match the query are
/// treated as having zero similarity to already-selected items (so they can
/// still be picked, just based on their dense score).
List<SimilarChunk> applyMmr({
  required List<SimilarChunk> candidates,
  required List<double> queryVec,
  required int k,
  double lambda = 0.7,
}) {
  if (candidates.isEmpty || k <= 0) return const <SimilarChunk>[];
  final pool = List<SimilarChunk>.of(candidates);
  final picked = <SimilarChunk>[];
  while (picked.length < k && pool.isNotEmpty) {
    SimilarChunk? bestCand;
    var bestMmr = double.negativeInfinity;
    var bestIdx = -1;
    for (var i = 0; i < pool.length; i++) {
      final cand = pool[i];
      var maxSimToPicked = 0.0;
      final cv = cand.chunk.embedding;
      for (final p in picked) {
        final pv = p.chunk.embedding;
        if (cv.isEmpty || pv.isEmpty || cv.length != pv.length) continue;
        final cs = cosineSimilarity(cv, pv);
        if (cs > maxSimToPicked) maxSimToPicked = cs;
      }
      final mmr = lambda * cand.score - (1 - lambda) * maxSimToPicked;
      if (mmr > bestMmr) {
        bestMmr = mmr;
        bestCand = cand;
        bestIdx = i;
      }
    }
    if (bestCand == null || bestIdx < 0) break;
    picked.add(bestCand);
    pool.removeAt(bestIdx);
  }
  return picked;
}

/// In-memory BM25 index over `(chunkId -> text)`. Built once and re-used
/// across queries; the owner is responsible for rebuilding when the corpus
/// changes (see [VectorStoreService.searchHybrid]'s versioning).
///
/// Dense embeddings smear over exact tokens (a proper name, a CLI flag, a
/// code identifier), so a small BM25 sidecar recovers literal-match recall
/// without giving up the semantic recall of EmbeddingGemma.
class Bm25Index {
  Bm25Index._({
    required Map<int, List<String>> docTokens,
    required Map<int, int> docLengths,
    required Map<String, double> idf,
    required double avgDl,
    required this.k1,
    required this.b,
  })  : _docTokens = docTokens,
        _docLengths = docLengths,
        _idf = idf,
        _avgDl = avgDl;

  factory Bm25Index.build(
    Map<int, String> docs, {
    double k1 = 1.5,
    double b = 0.75,
  }) {
    final docTokens = <int, List<String>>{};
    final docLengths = <int, int>{};
    final df = <String, int>{};
    for (final entry in docs.entries) {
      final toks = tokenize(entry.value);
      docTokens[entry.key] = toks;
      docLengths[entry.key] = toks.length;
      final seen = <String>{};
      for (final t in toks) {
        if (seen.add(t)) {
          df[t] = (df[t] ?? 0) + 1;
        }
      }
    }
    final n = docs.length;
    final idf = <String, double>{
      for (final e in df.entries)
        // Robertson-Sparck-Jones IDF, shifted to stay non-negative.
        e.key: math.log(1 + (n - e.value + 0.5) / (e.value + 0.5)),
    };
    final totalLen = docLengths.values.fold<int>(0, (a, b) => a + b);
    final avgDl = docLengths.isEmpty ? 0.0 : totalLen / docLengths.length;
    return Bm25Index._(
      docTokens: docTokens,
      docLengths: docLengths,
      idf: idf,
      avgDl: avgDl,
      k1: k1,
      b: b,
    );
  }

  final Map<int, List<String>> _docTokens;
  final Map<int, int> _docLengths;
  final Map<String, double> _idf;
  final double _avgDl;
  final double k1;
  final double b;

  int get documentCount => _docTokens.length;

  Map<int, double> score(String query) {
    final qTokens = tokenize(query);
    if (qTokens.isEmpty || _avgDl == 0) return const <int, double>{};
    final out = <int, double>{};
    for (final entry in _docTokens.entries) {
      final id = entry.key;
      final dl = (_docLengths[id] ?? 0).toDouble();
      if (dl == 0) continue;
      final tf = <String, int>{};
      for (final t in entry.value) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      var s = 0.0;
      for (final qt in qTokens) {
        final idf = _idf[qt];
        if (idf == null) continue;
        final f = (tf[qt] ?? 0).toDouble();
        if (f == 0) continue;
        final num = f * (k1 + 1);
        final den = f + k1 * (1 - b + b * dl / _avgDl);
        s += idf * (num / den);
      }
      if (s > 0) out[id] = s;
    }
    return out;
  }

  /// Word-character tokenizer with case-folding. Keeps alphanumerics +
  /// underscore (so `note_chunk`, `gpt4`, etc. stay intact) and splits on
  /// everything else. Good enough for proper names and code identifiers
  /// without bringing in a stemmer.
  static List<String> tokenize(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < lower.length; i++) {
      final c = lower.codeUnitAt(i);
      final isWord = (c >= 0x61 && c <= 0x7a) || // a-z
          (c >= 0x30 && c <= 0x39) || // 0-9
          c == 0x5f; // _
      if (isWord) {
        buf.writeCharCode(c);
      } else if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }
}

/// Min-max rescales [xs] into `[0, 1]`. Returns zeros when the range is
/// degenerate (all values equal) so a uniform signal contributes nothing to
/// fused scoring instead of dominating it.
List<double> minMaxNormalize(List<double> xs) {
  if (xs.isEmpty) return const <double>[];
  var lo = xs.first;
  var hi = xs.first;
  for (final v in xs) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  if (hi <= lo) return List<double>.filled(xs.length, 0);
  final span = hi - lo;
  return [for (final v in xs) (v - lo) / span];
}
