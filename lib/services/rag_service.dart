import 'package:get/get.dart';

import 'gemma_service.dart';
import 'vector_store_service.dart';

/// Composes the prompt fed to the LLM from retrieved note chunks.
class RagService extends GetxService {
  static const String defaultSystemInstruction =
      'You are Smart Notes, a helpful on-device assistant. '
      'Answer the user using ONLY the provided note excerpts. '
      'If the answer is not in the notes, say so plainly. '
      'Be concise. Cite the chunk number(s) like [#1], [#2] when relevant. '
      'Format every reply in Markdown (e.g. ## headings, **bold**, `-` bullets, '
      '`inline code`) when it helps readability.';

  /// Tokens reserved for system instruction, Gemma chat template, and decoding.
  static const int _promptReserveTokens = 768;

  static const int _maxHeaderChars = 240;

  /// Rough Latin-text chars per token for budgeting (conservative).
  static const int _charsPerTokenEst = 4;

  String buildPrompt({
    required String question,
    required List<SimilarChunk> retrieved,
  }) {
    if (retrieved.isEmpty) {
      final q = _trimmedQuestion(question);
      return 'The user has no indexed notes that match the question.\n\n'
          'Question: $q\n\n'
          'Reply that you have no relevant note context and ask them to write more notes. '
          'Use Markdown in your reply (e.g. short heading, bullet list of what they could note down).';
    }

    final tokenCap = Get.find<GemmaService>().loadedMaxTokens;
    final excerptTokenBudget =
        (tokenCap - _promptReserveTokens).clamp(128, tokenCap);
    var excerptCharBudget = excerptTokenBudget * _charsPerTokenEst;
    final q = _trimmedQuestion(question);
    excerptCharBudget -= q.length;
    excerptCharBudget -= 160; // wrappers + chunk metadata lines
    excerptCharBudget = excerptCharBudget.clamp(256, 1 << 20);

    const scoreLineBudget = 48;
    final perChunkTotal =
        (excerptCharBudget / retrieved.length).floor().clamp(96, excerptCharBudget);

    final ctx = StringBuffer();
    for (var i = 0; i < retrieved.length; i++) {
      final r = retrieved[i];
      final scoreLine = '[#${i + 1}] (score=${r.score.toStringAsFixed(3)})';
      final header = _headerFor(r);
      final headerChars = header.isEmpty ? 0 : header.length + 1;
      final bodyBudget = (perChunkTotal - scoreLineBudget - headerChars).clamp(32, perChunkTotal);
      ctx.writeln(scoreLine);
      if (header.isNotEmpty) {
        ctx.writeln(header);
        ctx.writeln();
      }
      var body = r.chunk.text.trim();
      if (body.length > bodyBudget) {
        body = '${body.substring(0, bodyBudget)}…';
      }
      if (body.isNotEmpty) {
        ctx.writeln(body);
      }
      ctx.writeln();
    }
    var result = 'Note excerpts:\n$ctx\nQuestion: $q';
    // Last-resort cap: template overhead can exceed our heuristic; stay under window.
    final maxTotalChars =
        ((tokenCap - _promptReserveTokens) * 3).clamp(400, 500000).round();
    if (result.length > maxTotalChars) {
      result = '${result.substring(0, maxTotalChars)}…';
    }
    return result;
  }

  static const int _maxQuestionChars = 2000;

  String _trimmedQuestion(String question) {
    final q = question.trim();
    if (q.length <= _maxQuestionChars) return q;
    return '${q.substring(0, _maxQuestionChars)}…';
  }

  /// Returns the per-chunk context header to render above the chunk text.
  ///
  /// Prefers the stored [NoteChunk.contextHeader] (populated for chunks
  /// indexed after the contextual-header migration). Falls back to the
  /// parent note's title for legacy chunks so old data still gets some
  /// title context in the prompt.
  String _headerFor(SimilarChunk r) {
    String clip(String s) {
      final t = s.trim();
      if (t.length <= _maxHeaderChars) return t;
      return '${t.substring(0, _maxHeaderChars)}…';
    }

    final stored = r.chunk.contextHeader.trim();
    if (stored.isNotEmpty) return clip(stored);
    final title = r.chunk.note.target?.title.trim() ?? '';
    return title.isEmpty ? '' : clip('Title: $title');
  }

  String get systemInstruction => defaultSystemInstruction;
}
