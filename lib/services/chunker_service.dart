import 'package:get/get.dart';

/// Splits free-form note text into approximately N-token chunks.
///
/// v1 uses a word-count heuristic (1 token ≈ 0.75 words → ~375 words per
/// 500 tokens). It tries to break on sentence boundaries when possible and
/// falls back to a sliding window of words. Replace with a tokenizer-aware
/// chunker once we expose the embedder's tokenizer.
class ChunkerService extends GetxService {
  static const int defaultTargetTokens = 500;
  static const double tokenToWordRatio = 0.75;
  static const int defaultOverlapWords = 32;

  /// Splits [text] into chunks of roughly [targetTokens] tokens.
  /// Returns the original text as one chunk if it's already small enough.
  List<String> split(
    String text, {
    int targetTokens = defaultTargetTokens,
    int overlapWords = defaultOverlapWords,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];

    final wordsPerChunk = (targetTokens * tokenToWordRatio).round();
    final words = cleaned.split(RegExp(r'\s+'));
    if (words.length <= wordsPerChunk) return [cleaned];

    final sentences = _splitIntoSentences(cleaned);
    final chunks = <String>[];
    final buffer = StringBuffer();
    int bufferWords = 0;

    for (final sentence in sentences) {
      final sentenceWordCount = sentence.split(RegExp(r'\s+')).length;
      final wouldOverflow =
          bufferWords + sentenceWordCount > wordsPerChunk && buffer.isNotEmpty;

      if (wouldOverflow) {
        chunks.add(buffer.toString().trim());
        buffer.clear();
        bufferWords = 0;
      }

      if (sentenceWordCount > wordsPerChunk) {
        chunks.addAll(_slidingWindow(sentence, wordsPerChunk, overlapWords));
        continue;
      }

      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(sentence);
      bufferWords += sentenceWordCount;
    }

    if (buffer.isNotEmpty) chunks.add(buffer.toString().trim());
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  List<String> _splitIntoSentences(String text) {
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex).where((s) => s.trim().isNotEmpty).toList();
  }

  List<String> _slidingWindow(String text, int windowWords, int overlapWords) {
    final words = text.split(RegExp(r'\s+'));
    final stride = (windowWords - overlapWords).clamp(1, windowWords);
    final chunks = <String>[];
    for (int i = 0; i < words.length; i += stride) {
      final end = (i + windowWords).clamp(0, words.length);
      chunks.add(words.sublist(i, end).join(' '));
      if (end == words.length) break;
    }
    return chunks;
  }
}
