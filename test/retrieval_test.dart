import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_notes/data/models/note_chunk.dart';
import 'package:smart_notes/services/note_graph_service.dart';
import 'package:smart_notes/services/retrieval_rerank.dart';
import 'package:smart_notes/services/vector_store_service.dart';

void main() {
  // Pin cosineSimilarity to known-good values. If anyone ever introduces the
  // `b[j]` typo described in the original code review, these will fail.
  group('cosineSimilarity', () {
    test('identical unit vectors score 1.0', () {
      expect(
        cosineSimilarity([1, 0, 0], [1, 0, 0]),
        closeTo(1.0, 1e-12),
      );
    });

    test('orthogonal vectors score 0.0', () {
      expect(
        cosineSimilarity([1, 0, 0], [0, 1, 0]),
        closeTo(0.0, 1e-12),
      );
    });

    test('opposite vectors score -1.0', () {
      expect(
        cosineSimilarity([1, 2, 3], [-1, -2, -3]),
        closeTo(-1.0, 1e-12),
      );
    });

    test('known 3-vector cosine', () {
      // a = (1,2,3), b = (4,5,6)
      // dot = 32, |a| = sqrt(14), |b| = sqrt(77)
      final expected = 32 / (math.sqrt(14) * math.sqrt(77));
      expect(
        cosineSimilarity([1, 2, 3], [4, 5, 6]),
        closeTo(expected, 1e-12),
      );
    });

    test('mismatched dimensions return 0 (not an exception)', () {
      expect(cosineSimilarity([1, 2], [1, 2, 3]), 0);
    });

    test('empty inputs return 0', () {
      expect(cosineSimilarity(const [], const []), 0);
    });
  });

  group('maxSimSymmetric', () {
    test('identical bags return 1.0', () {
      final a = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
      ];
      final b = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
      ];
      expect(maxSimSymmetric(a, b), closeTo(1.0, 1e-12));
    });

    test('disjoint bags return 0.0 (orthogonal everything)', () {
      final a = [
        [1.0, 0.0, 0.0],
      ];
      final b = [
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
      expect(maxSimSymmetric(a, b), closeTo(0.0, 1e-12));
    });

    test('asymmetric overlap still scores high (max-sim, not mean)', () {
      // Long note B has 3 unrelated chunks + 1 that is identical to A's
      // single chunk. Mean-pool cosine would be diluted ~0.25; max-sim
      // should score 1.0 from A's side and 1/4 from B's side, mean 0.625.
      final a = [
        [1.0, 0.0, 0.0],
      ];
      final b = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 1.0, 0.0],
      ];
      final score = maxSimSymmetric(a, b);
      expect(score, greaterThan(0.5));
      expect(score, lessThan(1.0));
    });

    test('empty input returns 0', () {
      expect(maxSimSymmetric(const [], const []), 0);
      expect(maxSimSymmetric(const [], [const [1.0]]), 0);
    });
  });

  group('Bm25Index', () {
    test('tokenizer keeps identifiers and lowercases', () {
      final toks = Bm25Index.tokenize('Hello, world! note_chunk gpt4');
      expect(toks, ['hello', 'world', 'note_chunk', 'gpt4']);
    });

    test('exact-match query ranks the right doc highest', () {
      final idx = Bm25Index.build({
        1: 'apples bananas cherries',
        2: 'kubernetes operator for postgres',
        3: 'a quick brown fox jumps over the lazy dog',
      });
      final scores = idx.score('kubernetes operator');
      expect(scores.keys, contains(2));
      // doc 2 wins
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      expect(sorted.first.key, 2);
    });

    test('empty query returns empty scores', () {
      final idx = Bm25Index.build({1: 'hello world'});
      expect(idx.score(''), isEmpty);
      expect(idx.score('   '), isEmpty);
    });
  });

  group('applyMmr', () {
    SimilarChunk fakeChunk(int id, List<double> emb, double score) {
      final c = NoteChunk(id: id, embedding: emb);
      return SimilarChunk(chunk: c, score: score);
    }

    test('drops near-duplicate chunks in favour of a diverse one', () {
      // Three near-clones (cosine ~1 to each other) plus one genuinely
      // different chunk. With lambda=0.5, MMR should pick one clone and
      // the diverse one rather than two clones.
      final clones = [
        fakeChunk(1, [1.0, 0.0, 0.0], 0.95),
        fakeChunk(2, [0.99, 0.01, 0.0], 0.93),
        fakeChunk(3, [0.98, 0.02, 0.0], 0.92),
      ];
      final diverse = fakeChunk(4, [0.0, 1.0, 0.0], 0.80);
      final out = applyMmr(
        candidates: [...clones, diverse],
        queryVec: [1.0, 0.0, 0.0],
        k: 2,
        lambda: 0.5,
      );
      expect(out, hasLength(2));
      // First pick is the best-relevance clone.
      expect(out[0].chunk.id, 1);
      // Second pick should be the diverse one, not another clone.
      expect(out[1].chunk.id, 4);
    });

    test('lambda=1.0 reduces to plain top-K (no diversification)', () {
      final candidates = [
        fakeChunk(1, [1.0, 0.0, 0.0], 0.9),
        fakeChunk(2, [0.99, 0.0, 0.0], 0.85),
        fakeChunk(3, [0.0, 1.0, 0.0], 0.6),
      ];
      final out = applyMmr(
        candidates: candidates,
        queryVec: [1.0, 0.0, 0.0],
        k: 2,
        lambda: 1.0,
      );
      expect(out.map((c) => c.chunk.id).toList(), [1, 2]);
    });

    test('empty pool returns empty', () {
      expect(
        applyMmr(
          candidates: const [],
          queryVec: const [1.0],
          k: 3,
        ),
        isEmpty,
      );
    });
  });

  group('minMaxNormalize', () {
    test('rescales to [0, 1]', () {
      expect(minMaxNormalize([0, 5, 10]), [0.0, 0.5, 1.0]);
    });

    test('uniform input collapses to zeros (no false signal)', () {
      expect(minMaxNormalize([3, 3, 3]), [0.0, 0.0, 0.0]);
    });

    test('empty input returns empty', () {
      expect(minMaxNormalize(const []), isEmpty);
    });
  });
}
