import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:get/get.dart';

import '../../../data/models/note.dart';
import '../../../routes/app_routes.dart';
import '../../../services/gemma_service.dart';
import '../../../services/note_graph_service.dart';

class RelatedEndpoint {
  RelatedEndpoint({required this.other, required this.score});
  final Note other;
  final double score;
}

class GraphController extends GetxController {
  GraphController({
    NoteGraphService? graphService,
    GemmaService? gemma,
  })  : _graphService = graphService ?? Get.find<NoteGraphService>(),
        _gemma = gemma ?? Get.find<GemmaService>();

  final NoteGraphService _graphService;
  final GemmaService _gemma;

  final graphVersion = 0.obs;

  /// Selected note on the graph (ObjectBox id).
  final selectedNoteId = Rxn<int>();

  /// Session cache for "Why?" explanations keyed by `"low_high"` note ids.
  final Map<String, String> whyExplanationCache = {};

  @override
  void onInit() {
    super.onInit();
    rebuildGraph();
  }

  void selectNote(int? id) {
    selectedNoteId.value = id;
  }

  void rebuildGraph() {
    graphVersion.value++;
  }

  List<RelatedEndpoint> relatedForNote(int noteId) {
    final edges = _graphService.edgesTouching(noteId);
    final out = <RelatedEndpoint>[];
    for (final e in edges) {
      final otherId = e.noteIdA == noteId ? e.noteIdB : e.noteIdA;
      final n = _graphService.getNote(otherId);
      if (n != null) out.add(RelatedEndpoint(other: n, score: e.similarityScore));
    }
    return out;
  }

  String pairKey(int idA, int idB) {
    final lo = idA < idB ? idA : idB;
    final hi = idA < idB ? idB : idA;
    return '${lo}_$hi';
  }

  Future<String> generateWhySentence(Note a, Note b) async {
    final key = pairKey(a.id, b.id);
    final cached = whyExplanationCache[key];
    if (cached != null && cached.isNotEmpty) return cached;

    if (!_gemma.isReady.value || _gemma.model == null) {
      throw StateError('Gemma model is not ready.');
    }

    String excerpt(String raw) {
      final t = raw.trim();
      if (t.length <= 300) return t;
      return t.substring(0, 300);
    }

    final prompt =
        'You are a helpful assistant. Given two note excerpts below, write ONE sentence '
        'explaining what concept or topic connects them. Be specific, not generic.\n\n'
        'Note A: ${excerpt(a.body)}\n'
        'Note B: ${excerpt(b.body)}\n\n'
        'Respond with only the one sentence explanation. No preamble.';

    final chat = await _gemma.newChat(
      temperature: 0.35,
      topK: 32,
      topP: 0.9,
    );
    try {
      await chat.addQueryChunk(Message.text(text: prompt, isUser: true));

      final buf = StringBuffer();
      final completer = Completer<void>();
      StreamSubscription<ModelResponse>? sub;
      sub = chat.generateChatResponseAsync().listen(
        (resp) {
          if (resp is TextResponse) buf.write(resp.token);
        },
        onError: (e, _) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
      await sub.cancel();

      final text = buf.toString().trim();
      if (text.isNotEmpty) whyExplanationCache[key] = text;
      return text.isEmpty ? '(No response)' : text;
    } finally {
      await chat.close();
    }
  }

  double opacityForNode(int noteId) {
    final sel = selectedNoteId.value;
    if (sel == null) return 1;
    if (noteId == sel) return 1;
    if (_graphService.neighborIds(sel).contains(noteId)) return 1;
    return 0.2;
  }

  bool selectedGlow(int noteId) => selectedNoteId.value == noteId;

  void openEditor(Note note) {
    Get.toNamed(AppRoutes.noteEditor, arguments: note);
  }
}
