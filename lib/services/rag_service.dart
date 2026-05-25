import 'package:get/get.dart';

import '../data/models/note_attachment.dart';
import 'gemma_service.dart';
import 'vector_store_service.dart';

/// Composes the prompt fed to the LLM from retrieved note chunks.
class RagService extends GetxService {
  static const String defaultSystemInstruction =
      'You are Smart Notes, a helpful on-device assistant. '
      'Answer the user using ONLY the provided note excerpts. '
      'If the answer is not in the notes, say so plainly. '
      'Be concise. When referencing an excerpt chunk, cite once using only '
      'the Markdown markers [#n] where n matches the excerpt number from context '
      '([#1], [#2], …). '
      'Do not use superscript (^1), footnote/ref syntax ([^1]), '
      'or duplicates like #1 before [#1]; a single [#n] per citation is enough. '
      'Note excerpts sometimes list attached PDFs or images after the snippet. '
      'When you refer to those files in your reply, include the clickable '
      'markdown link copied exactly from the excerpt (format [Label](smartnotes://attachment/<id>). '
      'Format every reply in Markdown (e.g. ## headings, **bold**, `-` bullets, '
      '`inline code`) when it helps readability. ';

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
    excerptCharBudget -= 240; // wrappers + chunk metadata + attachment lines
    excerptCharBudget = excerptCharBudget.clamp(256, 1 << 20);

    const scoreLineBudget = 48;
    final perChunkTotal = (excerptCharBudget / retrieved.length)
        .floor()
        .clamp(96, excerptCharBudget);

    final ctx = StringBuffer();
    for (var i = 0; i < retrieved.length; i++) {
      final r = retrieved[i];
      final scoreLine = '[#${i + 1}] (score=${r.score.toStringAsFixed(3)})';
      final header = _headerFor(r);
      final headerChars = header.isEmpty ? 0 : header.length + 1;
      final bodyBudget = (perChunkTotal - scoreLineBudget - headerChars)
          .clamp(32, perChunkTotal);
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

      final atts = attachmentsFromChunkMetadataJson(r.chunk.chunkMetadataJson);
      if (atts.isNotEmpty) {
        ctx.writeln(
          'Attachments for this excerpt (reuse these markdown links verbatim when referencing a file — the user can open them):',
        );
        for (final a in atts) {
          final label = _safeMarkdownLinkLabel(a.displayName);
          ctx.writeln(
            '- [$label](smartnotes://attachment/${a.id}) — (${a.mimeType})',
          );
        }
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

  String _safeMarkdownLinkLabel(String displayName) {
    var s = displayName.trim();
    if (s.isEmpty) return 'attachment';
    s = s.replaceAll('[', '(').replaceAll(']', ')');
    if (s.length > 120) return '${s.substring(0, 118)}…';
    return s;
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

  /// Device-local calendar context for interpreting relative wording in questions.
  static String formattedLocalCalendarDate(DateTime dateTime) {
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final d = weekdays[dateTime.weekday - 1];
    final m = months[dateTime.month - 1];
    final iso =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}';
    return '$d, $m ${dateTime.day}, ${dateTime.year} ($iso)';
  }

  String get systemInstruction =>
      '$defaultSystemInstruction'
      "Today's calendar date on the user's device (local timezone) is "
      '${formattedLocalCalendarDate(DateTime.now())}. '
      'Use this when interpreting relative phrases (e.g. "today", "this week", '
      '"recently") if the excerpts do not give a conflicting date.';
}
