import 'package:get/get.dart';

import 'vector_store_service.dart';

/// Composes the prompt fed to the LLM from retrieved note chunks.
class RagService extends GetxService {
  static const String defaultSystemInstruction =
      'You are Smart Notes, a helpful on-device assistant. '
      'Answer the user using ONLY the provided note excerpts. '
      'If the answer is not in the notes, say so plainly. '
      'Be concise. Cite the chunk number(s) like [#1], [#2] when relevant.';

  String buildPrompt({
    required String question,
    required List<SimilarChunk> retrieved,
  }) {
    if (retrieved.isEmpty) {
      return 'The user has no indexed notes that match the question.\n\n'
          'Question: $question\n\n'
          'Reply that you have no relevant note context and ask them to write more notes.';
    }
    final ctx = StringBuffer();
    for (var i = 0; i < retrieved.length; i++) {
      final r = retrieved[i];
      ctx.writeln('[#${i + 1}] (score=${r.score.toStringAsFixed(3)})');
      ctx.writeln(r.chunk.text.trim());
      ctx.writeln();
    }
    return 'Note excerpts:\n$ctx\nQuestion: $question';
  }

  String get systemInstruction => defaultSystemInstruction;
}
