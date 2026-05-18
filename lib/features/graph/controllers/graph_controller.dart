import 'dart:async';

import 'package:flutter/widgets.dart';
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

  /// Pair keys ([pairKey]) currently running [generateWhySentence]. Observable
  /// so sheet rows redraw after minimizing / reopening the bottom sheet while
  /// inference is still streaming.
  final whyGeneratingPairs = <String>[].obs;

  /// Incremented whenever [whyExplanationCache] stores a new explanation so
  /// rows reopening the sheet redraw from cache after off-screen completion.
  final whyExplanationRevision = 0.obs;

  /// Serialization lock: Gemma exposes one active chat session; [GemmaService.newChat]
  /// forcibly replaces it, so overlapping "Why?" / chat prompts corrupt streams.
  Future<void> _whySerial = Future<void>.value();

  /// Drives pinch/pan on the semantic graph; disposed in [onClose].
  final TransformationController graphTransform = TransformationController();

  Future<T> _withWhySerialization<T>(Future<T> Function() body) async {
    final predecessor = _whySerial;
    final gate = Completer<void>();
    _whySerial = gate.future;
    await predecessor;
    try {
      return await body();
    } finally {
      gate.complete();
    }
  }

  bool isWhyGeneratingForPair(int noteIdA, int noteIdB) =>
      whyGeneratingPairs.contains(pairKey(noteIdA, noteIdB));

  void _whyMarkStart(String key) {
    if (!whyGeneratingPairs.contains(key)) {
      whyGeneratingPairs.add(key);
    }
  }

  void _whyMarkEnd(String key) {
    whyGeneratingPairs.remove(key);
  }

  /// After opening the graph from a note tile, we center/zoom once in the viewport.
  bool _pendingViewportFocus = false;

  bool get pendingGraphViewportFocus => _pendingViewportFocus;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Note) {
      selectedNoteId.value = args.id;
      _pendingViewportFocus = true;
    } else {
      selectedNoteId.value = null;
    }
    rebuildGraph();
  }

  @override
  void onClose() {
    graphTransform.dispose();
    super.onClose();
  }

  /// Centers [nodeCenter] in the graph (child coordinates) in the viewport at [scale].
  static Matrix4 matrixCenterOnNode(
    Offset nodeCenter,
    Size viewport,
    double scale,
  ) {
    return Matrix4.identity()
      ..translate(viewport.width / 2, viewport.height / 2)
      ..scale(scale)
      ..translate(-nodeCenter.dx, -nodeCenter.dy);
  }

  /// If we opened from a note list deep link, applies zoom/pan and clears the pending flag.
  void focusGraphViewportOnSelectedIfPending({
    required Map<int, Offset> positions,
    required Size viewport,
    double scale = 1.0,
  }) {
    if (!_pendingViewportFocus) return;
    _pendingViewportFocus = false;
    final id = selectedNoteId.value;
    if (id == null) return;
    final center = positions[id];
    if (center == null) return;
    if (!(viewport.width.isFinite && viewport.height.isFinite) ||
        viewport.width < 1 ||
        viewport.height < 1) {
      return;
    }
    graphTransform.value = matrixCenterOnNode(center, viewport, scale);
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

    return _withWhySerialization(() async {
      final again = whyExplanationCache[key];
      if (again != null && again.isNotEmpty) return again;

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

      _whyMarkStart(key);
      try {
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
          if (text.isNotEmpty) {
            whyExplanationCache[key] = text;
            whyExplanationRevision.value++;
          }
          return text.isEmpty ? '(No response)' : text;
        } finally {
          await chat.close();
        }
      } finally {
        _whyMarkEnd(key);
      }
    });
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
